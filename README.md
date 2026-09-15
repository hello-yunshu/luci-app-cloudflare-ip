# luci-app-cloudflare-ip

[English](README.en.md) | **中文**

<p align="center">
  <strong>OpenWrt Cloudflare IP 优选与节点更新</strong>
</p>

<p align="center">
  通过 LuCI 自动测速、验证并选择 Cloudflare IP，然后安全更新 PassWall 或 OpenClash 节点。
</p>

---

## 这是什么

`luci-app-cloudflare-ip` 是一个 OpenWrt LuCI 插件。它使用
[CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest) 测量候选 IP，按目标域名验证连通性，
再将结果应用到 PassWall 或 OpenClash。

它不会替换代理服务，也不会扫描或改写不匹配的节点。测速、应用和回滚由设备上的事务流程完成；发生超时、探测失败或服务恢复失败时，会回滚配置并尽量恢复原服务状态。

## 功能概览

- LuCI 概览、设置、来源、智能、PassWall、OpenClash、高级和诊断页面
- PassWall / OpenClash 双模式，自动检测已安装的代理服务
- 首次使用时下载 CloudflareSpeedTest，之后可在页面更新
- IPv4、IPv6 或双栈测速；TCP 或 HTTP 协议
- 多域名匹配、目标域名主动探测和逐个 IP 可达性验证
- 定时运行，支持 `6h`、`30m` 和五字段 cron 表达式
- OpenClash YAML 备份、恢复和删除
- 候选来源、IP 历史、运行日志和有限历史记录
- 默认安全的 Native 排序；可选 Adaptive Measurement、Rill Shadow 和 LAN Publisher

## 当前状态

- 当前包版本：`2.6.0-r3`
- 发布标签：`v2.6.0-3`
- 发布渠道：`prerelease`
- 2.x 仍属于 2.0 prerelease development line，不代表稳定版

正式包只从 `main` 的成功 exact-head CI 资格化运行中发布。IPK/APK、`sha256sums.txt` 和 `qualification.json` 属于同一证据链；主机测试和 SDK 构建不能替代真实 OpenWrt 设备、硬件兼容性或长期 soak 验证。

## 快速开始

## 我该下载哪个？

从 [Releases](../../releases) 选择与你的 OpenWrt 版本匹配的主包：

- OpenWrt 24.10.x → 下载 `luci-app-cloudflare-ip_2.6.0-r3_all.ipk`
- OpenWrt 25.12+ → 下载 `luci-app-cloudflare-ip-2.6.0-r3.apk`

不要同时安装 IPK 和 APK。Rill 集成代码已经包含在主包中。一个 `luci-app-cloudflare-ip` 主包已经包含 Native 优选、Adaptive Measurement 和 Operational Health；不包含 Rill Runtime binary。

### 1. 准备环境

- OpenWrt 24.10.x 或 25.12+
- 已安装 PassWall 或 OpenClash
- 代理节点域名已接入 Cloudflare CDN
- 设备可访问 GitHub 或配置可用的 GitHub 镜像

### 2. 安装软件包

从 [Releases](../../releases) 下载与 OpenWrt 版本匹配的主包，并校验文件：

```sh
sha256sum -c sha256sums.txt
```

| 包格式 | 适用版本 | 安装命令 |
| --- | --- | --- |
| `.ipk` | OpenWrt 24.10.x | `opkg install ./luci-app-cloudflare-ip_*.ipk` |
| `.apk` | OpenWrt 25.12+ | `apk add ./luci-app-cloudflare-ip-*.apk` |

依赖由软件包声明，主要包括：`luci-base`、`rpcd`、`uhttpd`、`bash`、`curl`、`tar`、`jq`、`ca-bundle` 和 `ca-certificates`。

安装后刷新 LuCI 页面，在 **服务 → Cloudflare IP 优选** 打开插件。

### 3. 第一次运行

1. 打开 **基本设置**，选择 PassWall 或 OpenClash，并填写节点原始域名。
2. 打开对应的 PassWall / OpenClash 页面，确认目标域名和过滤条件。
3. 在概览页下载 CFST，然后手动运行一次测速。
4. 确认结果和节点可用后，再开启定时任务。

目标域名必须填写节点配置中的原始域名，而不是优选后的 IP。PassWall 按 `address` 匹配；OpenClash 按 `server` 匹配。OpenClash 的 `servername` 和 `Host` 会保留原域名。

## 页面与配置

### 基本设置

| 配置项 | 说明 | 默认值 |
| --- | --- | --- |
| 启用 | 开启定时自动优选 | 关 |
| 模式 | `passwall` 或 `openclash` | `passwall` |
| IP 数量 | 保留的优选 IP 数量 | `4` |
| IP 类型 | `ipv4`、`ipv6` 或 `both` | `ipv4` |
| 测速协议 | `tcp` 或 `http` | `tcp` |
| 运行调度 | `6h`、`30m` 或五字段 cron | `6h` |

测速前默认停止代理服务，避免代理流量干扰结果。运行完成后会恢复原来的服务状态。

### PassWall

| 配置项 | 说明 | 默认值 |
| --- | --- | --- |
| 目标域名 | 需要优化的节点域名，可用逗号分隔多个 | — |
| 名称后缀 | 支持 `{n}` 序号和 `{ip}` 占位符 | ` [CF-{n}]` |

插件只处理 `address` 匹配目标域名的节点，并按优选 IP 数量生成节点。

### OpenClash

| 配置项 | 说明 | 默认值 |
| --- | --- | --- |
| 配置文件 | OpenClash YAML 路径 | `/etc/openclash/config/config.yaml` |
| 目标域名 | 需要优化的节点域名，可用逗号分隔多个 | — |
| 名称后缀 | 支持 `{n}` 序号和 `{ip}` 占位符 | ` [CF-{n}]` |
| 传输协议过滤 | 例如 `ws,grpc` | — |
| 备份数量 | 保留的 YAML 备份数 | `3` |

支持 `vless`、`vmess` 和 `trojan`；节点需要 `tls: true`，或使用 `ws`、`xhttp`、`grpc`、`h2`、`http` 等受支持网络类型。应用前会创建备份，并对管理的节点做意图映射回读。

### 候选来源

候选来源页支持 Cloudflare 官方网段、社区种子、历史优质 IP 和自定义 HTTPS 文本列表。自定义列表接受 IP、`IP:port`、IPv6、带括号的 IPv6 端口和 CIDR；域名会被拒绝，不会被 DNS 解析。

默认候选预算为 `128` 个唯一 IP，范围为 `100–512`。所有来源最终都会在本地合并、去重，并由一次 CFST 运行统一测速；来源数量不会无限扩大单次测速规模。

### Intelligence 与 Rill

Adaptive Measurement 是 Native 预探测调度层，默认 `shadow`，只消费测速前字段。`guarded` 只有在完整、兼容且未过期的审计证据达到召回率、安全性和节省阈值后才会生效；状态损坏、证据过期或探测失败会回退到完整 Native 流程。

Rill 默认关闭。普通用户不需要 Rill Runtime。只有希望使用 Candidate Rill Shadow / Assisted 时，才需要先安装主包，再从 [rill-openwrt-packages Releases](https://github.com/hello-yunshu/rill-openwrt-packages/releases) 安装与你的 OpenWrt 版本和 CPU 架构匹配的 `rill-runtime-preview`，然后在 LuCI Intelligence 页面启用 Rill。Rill 只作为候选辅助或 Shadow 观测，Native 排序和安全边界始终保留；Rill Runtime 不存在时页面会显示 `Rill Runtime: Not installed`，Native mode remains available。

不要要求新用户手工安装 `luci-app-cloudflare-ip-rill`。它已进入兼容迁移阶段，仅用于已有安装的依赖兼容。

### LAN Publisher

LAN Publisher 默认关闭，只允许绑定到 LAN 地址，拒绝 `0.0.0.0`。启用后可提供：

```text
/ip.txt
/best-ipv4.txt
/best-ipv6.txt
/result.json
```

它是可选的 LAN 兼容输出，不替代 PassWall/OpenClash 的直接更新。不要将其暴露到公网。

### 高级设置

常用高级项包括启动延迟、GitHub 镜像、下载重试次数、详细日志、工作目录、测速和恢复 deadline、候选预算、主动探测批次、来源策略及 sysupgrade 时保留 CFST。

脚本自更新已弃用。`auto_update=0` 是默认值；2.x 是多文件软件包，请通过经过校验的 IPK/APK 升级。UCI 配置、CFST、来源缓存、托管关系和有限历史会保留，运行临时文件可重建。

## 数据与故障排查

| 内容 | 路径 |
| --- | --- |
| UCI 配置 | `/etc/config/cf_ip` |
| 持久运行状态 | `/etc/cf_ip/status.json` |
| Rill 状态 | `/etc/cf_ip/rill-*.json` |
| 运行日志 | `/tmp/cf_ip/cf-ip-auto.log` |
| 核心命令 | `/usr/bin/cf-ip-auto` |
| RPC 调用 | `ubus call cf_ip <method>` |

常见问题：

- **看不到菜单**：刷新浏览器缓存，并执行 `/etc/init.d/rpcd reload`。
- **没有匹配节点**：确认目标域名与 PassWall 的 `address` 或 OpenClash 的 `server` 完全一致。
- **测速成功但应用失败**：检查目标域名的 SNI/Host、TLS/传输协议和代理服务状态；事务流程会尝试回滚。
- **CFST 下载失败**：检查设备时间、CA 证书、DNS、网络连接和 GitHub 镜像设置。
- **Rill 不可用**：确认 `rill-runtime-preview` 与路径 `/usr/bin/rill-runtime`；否则会自动使用 Native。

## 项目结构

```text
package/luci-app-cloudflare-ip/
├── Makefile
├── root/
│   ├── etc/config/cf_ip                 # UCI 默认配置
│   ├── etc/init.d/cf_ip                 # 服务生命周期与 cron
│   ├── usr/bin/cf-ip-auto-v2            # 2.x 核心入口
│   ├── usr/libexec/rpcd/cf_ip           # rpcd 后端
│   └── usr/libexec/cf-ip/*.sh           # 来源、测速、事务、恢复等模块
├── htdocs/luci-static/resources/
│   ├── cloudflare-ip/                   # CSS 与共享工具
│   └── view/cloudflare-ip/              # 8 个 LuCI 视图
└── po/                                  # 中英文翻译
```

## 架构与安全边界

```text
LuCI 视图
    ↓ ubus / rpcd
cf_ip RPC 后端
    ↓
cf-ip-auto → 候选来源 → 一次 CFST 测速 → 目标域名主动探测
    ↓
Native Rank / 可选 Rill 辅助
    ↓ 事务化应用、回读、健康检查与回滚
PassWall 或 OpenClash
```

核心流程保持单一 Native 权威路径：候选来源和 Reuse 是确定性逻辑；Rill 只有一个 Candidate Learner，不能绕过目标域名探测、Native safe envelope 或回滚流程。候选不足时报告 degraded candidate count，不复制最快 IP 来伪造数量。

## 构建与验证

GitHub Actions 会执行 Shell/JSON/JavaScript 检查、Legacy 合约测试、2.x 主机合约测试、Docker replay 和 OpenWrt SDK 的 IPK/APK 构建。推送到 `main` 或提交 Pull Request 会触发 CI，也可在 Actions 页面手动运行。

Docker replay 证据会明确标记为 `replayed`，不能证明真实设备表现，也不能替代硬件矩阵或 soak。正式 prerelease 只由 `main` 上成功的 `workflow_run` 资格化结果晋级。

## 相关文档

- [真实设备验证](docs/REAL_DEVICE_VALIDATION.md)
- [2.2 Adaptive Measurement](docs/2.2_ADAPTIVE_MEASUREMENT.md)
- [2.3–2.6 收口记录](docs/2.3_TO_2.6_CLOSEOUT.md)
- [默认 UCI 配置](package/luci-app-cloudflare-ip/root/etc/config/cf_ip)

## 致谢

- [XIU2/CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest)
- [hello-yunshu/rill-ml](https://github.com/hello-yunshu/rill-ml)
- [hello-yunshu/rill-openwrt-packages](https://github.com/hello-yunshu/rill-openwrt-packages)

## License

GPL-3.0
