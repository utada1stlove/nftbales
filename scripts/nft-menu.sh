#!/bin/bash

# nftables 管理菜单脚本
# 使用方法: wget -qO- https://raw.githubusercontent.com/你的用户名/nftbales/main/scripts/nft-menu.sh | sudo bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
TRAFFIC_STATE_DIR="/etc/nftbales"
TRAFFIC_WATCH_FILE="${TRAFFIC_STATE_DIR}/traffic-watch.list"

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}请使用 sudo 运行此脚本${NC}"
        exit 1
    fi
}

check_nft() {
    if ! command -v nft &> /dev/null; then
        echo -e "${YELLOW}未检测到 nftables，正在安装...${NC}"
        if command -v apt &> /dev/null; then
            apt update && apt install -y nftables
        elif command -v yum &> /dev/null; then
            yum install -y nftables
        elif command -v pacman &> /dev/null; then
            pacman -S --noconfirm nftables
        else
            echo -e "${RED}无法自动安装，请手动安装 nftables${NC}"
            exit 1
        fi
    fi
}

ensure_state_dir() {
    mkdir -p "$TRAFFIC_STATE_DIR"
    [[ -f "$TRAFFIC_WATCH_FILE" ]] || : > "$TRAFFIC_WATCH_FILE"
}

validate_port_spec() {
    local value="$1" start end
    [[ "$value" =~ ^[0-9]+(-[0-9]+)?$ ]] || return 1
    if [[ "$value" == *-* ]]; then
        start="${value%-*}"
        end="${value#*-}"
        (( start >= 1 && start <= 65535 && end >= start && end <= 65535 ))
    else
        (( value >= 1 && value <= 65535 ))
    fi
}

format_bytes() {
    local bytes="${1:-0}"
    if (( bytes < 1024 )); then
        printf '%s B' "$bytes"
    elif (( bytes < 1024 * 1024 )); then
        awk -v value="$bytes" 'BEGIN { printf "%.1f KB", value / 1024 }'
    elif (( bytes < 1024 * 1024 * 1024 )); then
        awk -v value="$bytes" 'BEGIN { printf "%.1f MB", value / (1024 * 1024) }'
    else
        awk -v value="$bytes" 'BEGIN { printf "%.2f GB", value / (1024 * 1024 * 1024) }'
    fi
}

format_packets() {
    local packets="${1:-0}"
    if (( packets < 1000 )); then
        printf '%s' "$packets"
    elif (( packets < 1000000 )); then
        awk -v value="$packets" 'BEGIN { printf "%.1fK", value / 1000 }'
    else
        awk -v value="$packets" 'BEGIN { printf "%.1fM", value / 1000000 }'
    fi
}

traffic_rule_comment() {
    local proto="$1" port="$2" direction="$3"
    printf 'nftbales-traffic:%s:%s:%s' "$proto" "$port" "$direction"
}

init_traffic_table() {
    nft add table inet traffic_stats 2>/dev/null || true
    nft add chain inet traffic_stats input { type filter hook input priority 0 \; policy accept \; } 2>/dev/null || true
    nft add chain inet traffic_stats output { type filter hook output priority 0 \; policy accept \; } 2>/dev/null || true
}

traffic_watch_exists() {
    local proto="$1" port="$2"
    grep -Fxq "${proto}|${port}" "$TRAFFIC_WATCH_FILE" 2>/dev/null
}

get_traffic_handle() {
    local chain="$1" proto="$2" port="$3" direction="$4"
    local comment
    comment="$(traffic_rule_comment "$proto" "$port" "$direction")"
    nft -a list chain inet traffic_stats "$chain" 2>/dev/null \
        | grep -F "comment \"$comment\"" \
        | sed -n 's/.*handle \([0-9]\+\)$/\1/p' \
        | tail -1
}

get_traffic_counters() {
    local chain="$1" proto="$2" port="$3" direction="$4"
    local comment line packets bytes
    comment="$(traffic_rule_comment "$proto" "$port" "$direction")"
    line="$(nft -a list chain inet traffic_stats "$chain" 2>/dev/null | grep -F "comment \"$comment\"" | head -1 || true)"
    packets="$(printf '%s\n' "$line" | sed -n 's/.*packets \([0-9]\+\) bytes \([0-9]\+\).*/\1/p')"
    bytes="$(printf '%s\n' "$line" | sed -n 's/.*packets \([0-9]\+\) bytes \([0-9]\+\).*/\2/p')"
    printf '%s|%s\n' "${packets:-0}" "${bytes:-0}"
}

enable_forward() {
    echo 1 > /proc/sys/net/ipv4/ip_forward
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    echo -e "${GREEN}IP 转发已开启${NC}"
}

init_nat() {
    nft add table ip nat 2>/dev/null || true
    nft add chain ip nat prerouting { type nat hook prerouting priority -100 \; } 2>/dev/null || true
    nft add chain ip nat postrouting { type nat hook postrouting priority 100 \; } 2>/dev/null || true
    echo -e "${GREEN}NAT 表已初始化${NC}"
}

add_port_forward() {
    echo -e "${YELLOW}=== 添加端口转发 ===${NC}"

    # 显示网卡信息
    echo -e "\n当前网卡信息："
    ip -br addr | grep -v "lo" | awk '{print $1 " - " $3}'

    echo -e "\n是否指定网卡？(y/n)"
    read -r use_iface

    iface_rule=""
    if [[ "$use_iface" == "y" ]]; then
        echo "输入网卡名称 (如 eth0, ens3):"
        read -r iface
        iface_rule="iifname \"$iface\" "
    fi

    echo "输入本机端口:"
    read -r local_port

    echo "输入目标IP:"
    read -r target_ip

    echo "输入目标端口:"
    read -r target_port

    echo "协议 (tcp/udp):"
    read -r proto

    init_nat
    enable_forward

    nft add rule ip nat prerouting ${iface_rule}${proto} dport ${local_port} dnat to ${target_ip}:${target_port}
    nft add rule ip nat postrouting ip daddr ${target_ip} masquerade

    echo -e "${GREEN}端口转发已添加: ${local_port} -> ${target_ip}:${target_port}${NC}"
}

block_udp() {
    echo -e "${YELLOW}=== 禁用 UDP 端口 ===${NC}"

    nft add table inet filter 2>/dev/null || true
    nft add chain inet filter input { type filter hook input priority 0 \; policy accept \; } 2>/dev/null || true
    nft add chain inet filter output { type filter hook output priority 0 \; policy accept \; } 2>/dev/null || true

    echo "输入要禁用的端口 (单个端口或范围，如 53 或 8000-9000):"
    read -r port

    echo "方向 (input/output/both) [both]:"
    read -r direction
    direction="${direction:-both}"

    case "${direction}" in
        input)
            nft add rule inet filter input udp dport ${port} drop
            echo -e "${GREEN}已禁用进入本机的 UDP 端口 ${port}${NC}"
            ;;
        output)
            nft add rule inet filter output udp dport ${port} drop
            echo -e "${GREEN}已禁用本机发出的 UDP 目标端口 ${port}${NC}"
            ;;
        both)
            nft add rule inet filter input udp dport ${port} drop
            nft add rule inet filter output udp dport ${port} drop
            echo -e "${GREEN}已同时禁用 input/output 的 UDP 端口 ${port}${NC}"
            ;;
        *)
            echo -e "${RED}无效方向，请输入 input、output 或 both${NC}"
            return 1
            ;;
    esac

    if [[ "${port}" == "443" ]]; then
        echo -e "${YELLOW}提示: UDP/443 常用于 QUIC，屏蔽后 YouTube 等场景通常会回退到 TCP/TLS${NC}"
    fi
}

add_port_traffic_watch() {
    local port proto_choice proto

    echo -e "${YELLOW}=== 添加端口流量统计 ===${NC}"
    ensure_state_dir
    init_traffic_table

    while true; do
        echo "输入要统计的端口或范围 (如 443 或 8000-8099):"
        read -r port
        validate_port_spec "$port" && break
        echo -e "${RED}端口格式无效${NC}"
    done

    echo "协议 (tcp/udp/both) [both]:"
    read -r proto_choice
    proto_choice="${proto_choice:-both}"

    case "$proto_choice" in
        tcp|udp)
            for proto in "$proto_choice"; do
                if traffic_watch_exists "$proto" "$port"; then
                    echo -e "${YELLOW}${proto}/${port} 已存在，跳过${NC}"
                    continue
                fi
                nft add rule inet traffic_stats input "$proto" dport "$port" counter comment "\"$(traffic_rule_comment "$proto" "$port" input)\""
                nft add rule inet traffic_stats output "$proto" sport "$port" counter comment "\"$(traffic_rule_comment "$proto" "$port" output)\""
                printf '%s|%s\n' "$proto" "$port" >> "$TRAFFIC_WATCH_FILE"
                echo -e "${GREEN}已开始统计 ${proto}/${port}${NC}"
            done
            ;;
        both)
            for proto in tcp udp; do
                if traffic_watch_exists "$proto" "$port"; then
                    echo -e "${YELLOW}${proto}/${port} 已存在，跳过${NC}"
                    continue
                fi
                nft add rule inet traffic_stats input "$proto" dport "$port" counter comment "\"$(traffic_rule_comment "$proto" "$port" input)\""
                nft add rule inet traffic_stats output "$proto" sport "$port" counter comment "\"$(traffic_rule_comment "$proto" "$port" output)\""
                printf '%s|%s\n' "$proto" "$port" >> "$TRAFFIC_WATCH_FILE"
                echo -e "${GREEN}已开始统计 ${proto}/${port}${NC}"
            done
            ;;
        *)
            echo -e "${RED}无效协议，请输入 tcp、udp 或 both${NC}"
            return 1
            ;;
    esac
}

list_port_traffic_stats() {
    local proto port input_stats output_stats in_packets in_bytes out_packets out_bytes total_packets total_bytes found=0

    echo -e "${YELLOW}=== 端口流量统计 ===${NC}"
    ensure_state_dir

    while IFS='|' read -r proto port; do
        [[ -n "${proto:-}" && -n "${port:-}" ]] || continue
        input_stats="$(get_traffic_counters input "$proto" "$port" input)"
        output_stats="$(get_traffic_counters output "$proto" "$port" output)"
        in_packets="${input_stats%%|*}"
        in_bytes="${input_stats#*|}"
        out_packets="${output_stats%%|*}"
        out_bytes="${output_stats#*|}"
        total_packets=$((in_packets + out_packets))
        total_bytes=$((in_bytes + out_bytes))

        printf '  %-4s %-12s in=%-18s out=%-18s total=%s\n' \
            "${proto^^}" \
            "$port" \
            "$(format_packets "$in_packets") / $(format_bytes "$in_bytes")" \
            "$(format_packets "$out_packets") / $(format_bytes "$out_bytes")" \
            "$(format_bytes "$total_bytes")"
        found=1
    done < "$TRAFFIC_WATCH_FILE"

    if [[ "$found" -eq 0 ]]; then
        echo -e "${YELLOW}当前没有正在统计的端口${NC}"
        echo -e "${YELLOW}提示: 这是按端口规则计数，不是 vnstat 的整机流量${NC}"
    fi
}

remove_port_traffic_watch() {
    local selection proto port line tmp
    local -a entries

    ensure_state_dir
    mapfile -t entries < <(grep -Ev '^[[:space:]]*$' "$TRAFFIC_WATCH_FILE" 2>/dev/null || true)

    if [[ "${#entries[@]}" -eq 0 ]]; then
        echo -e "${YELLOW}当前没有正在统计的端口${NC}"
        return 0
    fi

    list_port_traffic_stats
    echo
    echo "输入要删除的编号:"
    local index=1
    for line in "${entries[@]}"; do
        proto="${line%%|*}"
        port="${line#*|}"
        printf '  %d) %s/%s\n' "$index" "${proto^^}" "$port"
        index=$((index + 1))
    done

    read -r selection
    [[ "$selection" =~ ^[0-9]+$ ]] || { echo -e "${RED}编号无效${NC}"; return 1; }
    (( selection >= 1 && selection <= ${#entries[@]} )) || { echo -e "${RED}编号无效${NC}"; return 1; }

    line="${entries[$((selection - 1))]}"
    proto="${line%%|*}"
    port="${line#*|}"

    local input_handle output_handle
    input_handle="$(get_traffic_handle input "$proto" "$port" input)"
    output_handle="$(get_traffic_handle output "$proto" "$port" output)"
    [[ -n "$input_handle" ]] && nft delete rule inet traffic_stats input handle "$input_handle"
    [[ -n "$output_handle" ]] && nft delete rule inet traffic_stats output handle "$output_handle"

    tmp="$(mktemp)"
    grep -Fvx "$line" "$TRAFFIC_WATCH_FILE" > "$tmp" 2>/dev/null || true
    mv "$tmp" "$TRAFFIC_WATCH_FILE"

    echo -e "${GREEN}已移除 ${proto^^}/${port} 的流量统计${NC}"
}

list_rules() {
    echo -e "${YELLOW}=== 当前规则 ===${NC}"
    nft -a list ruleset
}

delete_rule() {
    echo -e "${YELLOW}=== 删除规则 ===${NC}"

    nft -a list ruleset

    echo -e "\n输入表名 (如 ip nat, inet filter):"
    read -r table

    echo "输入链名 (如 prerouting, input):"
    read -r chain

    echo "输入规则句柄号 (handle):"
    read -r handle

    nft delete rule ${table} ${chain} handle ${handle}

    echo -e "${GREEN}规则已删除${NC}"
}

save_rules() {
    nft list ruleset > /etc/nftables.conf
    systemctl enable nftables 2>/dev/null || true
    echo -e "${GREEN}规则已保存到 /etc/nftables.conf${NC}"
}

flush_rules() {
    echo -e "${RED}警告: 这将清空所有规则！${NC}"
    echo "确认清空？(yes/no)"
    read -r confirm

    if [[ "$confirm" == "yes" ]]; then
        nft flush ruleset
        echo -e "${GREEN}所有规则已清空${NC}"
    fi
}

show_menu() {
    clear
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}   nftables 管理菜单${NC}"
    echo -e "${GREEN}================================${NC}"
    echo "1. 添加端口转发"
    echo "2. 禁用 UDP 端口"
    echo "3. 查看所有规则"
    echo "4. 删除规则"
    echo "5. 保存规则"
    echo "6. 清空所有规则"
    echo "7. 开启 IP 转发"
    echo "8. 添加端口流量统计"
    echo "9. 查看端口流量统计"
    echo "10. 删除端口流量统计"
    echo "0. 退出"
    echo -e "${GREEN}================================${NC}"
}

main() {
    check_root
    check_nft
    ensure_state_dir

    while true; do
        show_menu
        read -r choice

        case $choice in
            1) add_port_forward ;;
            2) block_udp ;;
            3) list_rules ;;
            4) delete_rule ;;
            5) save_rules ;;
            6) flush_rules ;;
            7) enable_forward ;;
            8) add_port_traffic_watch ;;
            9) list_port_traffic_stats ;;
            10) remove_port_traffic_watch ;;
            0) echo "退出"; exit 0 ;;
            *) echo -e "${RED}无效选项${NC}" ;;
        esac

        echo -e "\n按回车继续..."
        read -r
    done
}

main
