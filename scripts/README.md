# nftables 管理脚本

这个目录包含 nftables 的管理脚本。

## 一键安装使用

```bash
wget -qO- https://raw.githubusercontent.com/utada1stlove/nftbales/refs/heads/main/scripts/nft-menu.sh | sudo bash
```

或者下载后使用：

```bash
wget https://raw.githubusercontent.com/utada1stlove/nftbales/refs/heads/main/scripts/nft-menu.sh
chmod +x nft-menu.sh
sudo ./nft-menu.sh
```

## 功能列表

1. **添加端口转发** - 支持指定网卡、TCP/UDP 协议
2. **禁用 UDP 端口** - 快速禁用指定端口的 UDP 流量
3. **查看所有规则** - 显示当前所有 nftables 规则
4. **删除规则** - 通过句柄号删除指定规则
5. **保存规则** - 持久化保存到 /etc/nftables.conf
6. **清空所有规则** - 清空所有 nftables 规则
7. **开启 IP 转发** - 启用内核 IP 转发功能

## 使用说明

脚本会自动：
- 检查是否为 root 权限
- 检测并安装 nftables（如果未安装）
- 初始化必要的表和链

## 注意事项

- 必须使用 sudo 或 root 权限运行
- 修改规则前建议先备份：`nft list ruleset > backup.conf`
- 清空规则可能导致网络中断，请谨慎操作
