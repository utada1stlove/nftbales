# nftables 知识库

本仓库是 nftables 的完整学习指南，适合完全零基础的初学者。

## 什么是 nftables？

nftables 是 Linux 的防火墙工具，用于控制网络流量。它是 iptables 的现代替代品，语法更简单，性能更好。

## 一键管理脚本

```bash
wget -qO- https://raw.githubusercontent.com/utada1stlove/nftbales/refs/heads/main/scripts/nft-menu.sh | sudo bash
```

提供交互式菜单，快速管理 nftables 规则。详见 [scripts/README.md](./scripts/README.md)

## 快速开始

如果你完全不懂 nftables，建议按以下顺序学习：

1. **[基础概念](./docs/01-基础概念.md)** - 了解 nftables 的基本架构
2. **[端口转发（内网IP）](./docs/02-端口转发-内网IP.md)** - 最常用的功能
3. **[端口转发（公网IP）](./docs/03-端口转发-公网IP.md)** - 公网IP转发
4. **[禁用UDP流量](./docs/04-禁用UDP流量.md)** - 限制特定协议
5. **[规则管理](./docs/05-规则管理.md)** - 查看、删除、编辑规则
6. **[快速参考](./docs/06-快速参考.md)** - 常用命令速查表

## 主要用途

本知识库重点讲解以下场景：

### 端口转发
- 内网IP转发（如：将本机 80 端口转发到 192.168.1.100:8080）
- 公网IP转发（如：将本机 80 端口转发到 5.6.7.8:8080）

### 流量控制
- 禁用特定端口的 UDP 流量
- 限制访问来源

### 规则管理
- 查看当前规则
- 删除不需要的规则
- 编辑现有规则
- 持久化保存规则

## 常用命令速查

```bash
# 查看所有规则
nft list ruleset

# 查看规则（带句柄号，用于删除）
nft -a list ruleset

# 删除规则
nft delete rule <表> <链> handle <句柄号>

# 保存规则
nft list ruleset > /etc/nftables.conf

# 加载规则
nft -f /etc/nftables.conf

# 清空所有规则
nft flush ruleset
```

## 目录结构

```
nftbales/
├── README.md                    # 本文件
├── docs/                        # 教程文档
│   ├── 01-基础概念.md
│   ├── 02-端口转发-内网IP.md
│   ├── 03-端口转发-公网IP.md
│   ├── 04-禁用UDP流量.md
│   ├── 05-规则管理.md
│   └── 06-快速参考.md
└── scripts/                     # 管理脚本
    ├── README.md
    └── nft-menu.sh             # 交互式管理菜单
```

## 学习建议

- 每个教程都有完整的示例，可以直接复制使用
- 建议在测试环境先练习，避免影响生产环境
- 修改规则前记得备份：`nft list ruleset > backup.conf`
- 如果不小心锁死了，从控制台执行 `nft flush ruleset` 清空规则

## 贡献

欢迎提交 Issue 和 Pull Request 来完善这个知识库。

## 许可

MIT License
