# v2.6.0-8 — 线上 Release 正文

状态：**已发布（2026-11-04，Pre-release）**。本文件与 GitHub Release `v2.6.0-8` 的线上正文一致；首次发布时使用的草稿头与重复块已在发布后清理。

**更安全、更可诊断的 Cloudflare IP 优选：错误能看懂、状态能解释、升级不丢配置。**

Cloudflare IP `2.6.0-r8`（package release r8）· GitHub Pre-release · 源码渠道保持 `stable`，不做 Stable 晋级。

## 修复

- OpenClash 备份删除/恢复失败不再显示成功，失败保留错误与文件。
- RPC 超时、权限错误与“未安装/空数据”分离；错误态提供人类说明、可展开技术详情和复制。
- Sources 刷新保留未保存草稿，不再整页 reload。
- Rill reset 成功后刷新状态；修复按钮 busy 态。
- 动态状态码不再显示 `Unknown (code)`，未知码进入可展开块。
- 简体中文补齐 516 keys / 552 entries；菜单、动态状态与错误文案无英文残留。

## 变更

- legacy 自更新停用；升级必须通过包管理器。
- Advanced 的 `self_update_url` 改为只读。
- `uhttpd` 改为可选依赖；仅启用 LAN Result Publisher 时需要。
- 统一错误呈现与深色主题判定。

## 验证

- 51 点七态矩阵：121 PASS / 0 FAIL；真实 Chrome 125/150/200% 缩放与 320 reflow；zh_cn 375/1280 真实渲染。
- 254 个本地测试与 CI job 一一盘点，0 遗漏。

## 升级注意事项（重要）

1. **legacy 自更新已停用。** 旧脚本用户不能再通过 `--self-update` 或自动更新 URL 升级；请用 `opkg`/`apk` 安装本 Release 的 IPK/APK。`--self-update` 现在返回失败（rc 1），这是预期行为，不是故障。
2. **`self_update_url` 已只读。** UCI 字段保留以避免升级丢配置，但页面不可编辑；需要更新时请通过包管理器。
3. **uhttpd 不再是硬依赖。** 使用 nginx/lighttpd 的系统不会被动安装 uhttpd；只有启用 LAN Result Publisher 时才需要本机 `/usr/sbin/uhttpd`，缺失时 Publisher fail-closed，不影响其他功能。
4. **IPK/APK 选择：** OpenWrt 24.10.x 用 IPK；OpenWrt 25.12+ 用 APK。只安装主包即可使用 Native、Adaptive Measurement 与 Operational Health。Rill Runtime 是独立可选包，不在本 Release 内。
5. **升级前备份：** 备份 `/etc/config/cf_ip`、`/etc/cf_ip`、OpenClash/PassWall 目标配置、cron 与服务 enable 状态。升级后先核对包版本与页面状态，再执行真实任务。
6. **校验：** 下载 `SHA256SUMS` 后执行 `sha256sum -c SHA256SUMS`；`qualification.json` 记录同 run/attempt 的 exact-SHA 资格。

## 支持边界

- OpenWrt：24.10.5 / 24.10.8（IPK），25.12.0 / 25.12.5（APK），x86_64；24.10.8 aarch64_generic IPK 安装与 8 页 LuCI 实测 PASS。
- 主题：Bootstrap、Aurora 1.4.0 light/dark。
- 模式：PassWall、OpenClash；Native、Adaptive、Rill shadow/assisted/guarded。
- 物理设备 / 24h soak：按用户 2026-11-04 裁定 `PASS-BY-USER-DECISION`；未补造新记录。
- 未覆盖：arm64 之外的架构、完整键盘/触控全矩阵、PassWall 真实代理网络。
