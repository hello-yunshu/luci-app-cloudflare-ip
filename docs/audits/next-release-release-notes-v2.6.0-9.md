# v2.6.0-9 — 线上 Release 正文

状态：**已授权发布（Pre-release）**。发布时直接使用本文件作为线上正文；若资产验证失败则不创建 Release。

**修复 LAN Result Publisher 在当前 OpenWrt curl 上无法就绪的问题。**

Cloudflare IP `2.6.0-r9`（package release r9）· GitHub Pre-release · 源码渠道保持 `stable`，不做 Stable 晋级。

## 修复

- OpenWrt 24.10.8 当前 feed 的 `curl 8.22.0-r1` 会拒绝 1 秒超时（`remaining timeout of 999 too small to resolve via SIGALRM method`），导致 LAN Result Publisher 就绪检查恒失败。就绪与端点检查改为 2 秒，当前 curl 上可正常进入 ready（P1-06）。
- publisher 测试改用真实 procd/uhttpd，并纳入 CI；不再以“容器缺服务”作为排除理由。

## 升级注意事项（重要）

- 升级前按 [升级失败与 opkg status 恢复](../ROLLBACK_AND_RECOVERY.md) 备份 `/usr/lib/opkg/status`（存到 `/root` 或 U 盘，不要只放 `/tmp`）。
- 升级保留现有 `/etc/config/cf_ip`；新默认配置写入 `/etc/config/cf_ip-opkg`。
- 如果设备上 r8 的 publisher 一直显示不可用，升级到 r9 后重启服务或重新保存一次配置即可恢复。
- 不支持降级时直接 `opkg install` 旧包；需要回滚请使用 `--force-downgrade`。

## 未包含

- 本次没有 UI、i18n、OpenClash 或依赖图变更。
- Stable Gate 仍为 **NOT READY**：物理设备、多架构、24h soak、PassWall 真实网络、真机触控、真机断电/ENOSPC 未覆盖；`release-channel.json` 未改。
