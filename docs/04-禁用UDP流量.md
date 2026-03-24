# 禁用UDP流量

## 什么时候需要禁用UDP？

UDP 是一种网络协议，常用于：
- DNS 查询（端口 53）
- 游戏服务器
- 视频流传输
- QUIC 协议（HTTP/3）

有时需要禁用特定端口的 UDP 流量来：
- 防止 UDP 洪水攻击
- 限制某些服务的使用
- 调试网络问题

## 基本用法

### 禁用单个端口的 UDP

```bash
# 1. 创建 filter 表（如果不存在）
nft add table inet filter

# 2. 创建 input 链（如果不存在）
nft add chain inet filter input { type filter hook input priority 0 \; policy accept \; }

# 3. 禁用 UDP 端口 53
nft add rule inet filter input udp dport 53 drop
```

### 禁用多个端口

```bash
# 禁用端口 53 和 123
nft add rule inet filter input udp dport { 53, 123 } drop
```

### 禁用端口范围

```bash
# 禁用 UDP 端口 10000-20000
nft add rule inet filter input udp dport 10000-20000 drop
```

## 完整示例

### 场景：禁用所有 UDP 53 端口（DNS）

```bash
# 创建表和链
nft add table inet filter
nft add chain inet filter input { type filter hook input priority 0 \; policy accept \; }

# 禁用 UDP 53
nft add rule inet filter input udp dport 53 drop

# 验证
nft list chain inet filter input
```

### 场景：只禁用来自特定IP的UDP流量

```bash
# 禁用来自 1.2.3.4 的 UDP 流量
nft add rule inet filter input ip saddr 1.2.3.4 udp drop
```

### 场景：禁用所有UDP流量（保留特定端口）

```bash
# 允许 DNS（53）和 NTP（123）
nft add rule inet filter input udp dport { 53, 123 } accept

# 禁用其他所有 UDP
nft add rule inet filter input udp drop
```

## 命令解释

| 命令部分 | 含义 |
|---------|------|
| `inet filter` | 使用 inet 表的 filter 功能 |
| `input` | 处理进入本机的流量 |
| `udp dport 53` | 匹配目标端口为 53 的 UDP 流量 |
| `drop` | 丢弃该流量（静默拒绝） |
| `reject` | 拒绝并返回错误信息 |

## drop vs reject

```bash
# drop：静默丢弃，不回应
nft add rule inet filter input udp dport 53 drop

# reject：拒绝并告知对方
nft add rule inet filter input udp dport 53 reject
```

**建议**：通常用 `drop`，更安全，不暴露端口状态。

## 验证规则

```bash
# 查看所有规则
nft list ruleset

# 只查看 filter 表
nft list table inet filter

# 测试（从另一台机器）
nc -u 你的IP 53
# 如果规则生效，连接会超时
```

## 临时禁用规则

```bash
# 查看规则句柄
nft -a list chain inet filter input

# 输出示例：
# table inet filter {
#   chain input {
#     udp dport 53 drop # handle 5
#   }
# }

# 删除规则（使用 handle 号）
nft delete rule inet filter input handle 5
```

## 常见场景

### 禁用游戏服务器端口

```bash
# 禁用 Minecraft 默认端口
nft add rule inet filter input udp dport 19132 drop
```

### 禁用 QUIC（HTTP/3）

```bash
# QUIC 使用 UDP 443
nft add rule inet filter input udp dport 443 drop
```

### 只允许本地 UDP

```bash
# 只允许来自本机的 UDP
nft add rule inet filter input ip saddr 127.0.0.1 udp accept
nft add rule inet filter input udp drop
```

## 下一步

- [规则管理](./05-规则管理.md)
- [快速参考](./06-快速参考.md)
