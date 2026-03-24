#!/bin/bash

# nftables 管理菜单脚本
# 使用方法: wget -qO- https://raw.githubusercontent.com/你的用户名/nftbales/main/scripts/nft-menu.sh | sudo bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

    echo "输入要禁用的端口 (单个端口或范围，如 53 或 8000-9000):"
    read -r port

    nft add rule inet filter input udp dport ${port} drop

    echo -e "${GREEN}已禁用 UDP 端口 ${port}${NC}"
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
    echo "0. 退出"
    echo -e "${GREEN}================================${NC}"
}

main() {
    check_root
    check_nft

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
            0) echo "退出"; exit 0 ;;
            *) echo -e "${RED}无效选项${NC}" ;;
        esac

        echo -e "\n按回车继续..."
        read -r
    done
}

main
