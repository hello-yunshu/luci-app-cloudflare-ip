# Real Device Validation Matrix

本文件是 RC 前的执行清单，不把 host contract 或 OpenWrt SDK build 当作真机证据。

2026-10-24 当前政策：用户允许实机验证，并明确本地实机验证不阻塞 G6/G7 完成。最终软件候选 `371bf78b772540f5829e5700f4f09a73e33888c1`（run `41411391996` attempt 1）的实机与新 24h Soak 未执行，记 NOT RUN / NOT STARTED；不改写为 PASS。策略原文见 [device-policy-20261024.json](audits/g6-g7-evidence/device-policy-20261024.json)。历史测试及历史 Soak 豁免均不冒充当前候选结果；候选身份与软件证据见 [final-candidate-371bf78.json](audits/g6-g7-evidence/final-candidate-371bf78.json)。

**2026-11-07 政策更新（用户决策，替代上文的设备与 soak 边界）：**
- KVM 虚拟机与物理实体机等同，可用于完整的设备级验证。当前设备为 OpenWrt 25.12.5 x86_64（Microsoft KVM）。
- soak 时长由 24 小时改为 **12 小时**。
- 该更新只影响 2026-11-07 之后的候选验证；上文历史记录不追溯改写。
- 当前证据：exact-SHA `d1e36f3` 在 DUT 上完成同版本替换与配置保留；120/120 视觉矩阵 + 8/8 缩放；12 小时 soak 于 `2026-11-07 23:13:57`（设备本地时间）启动；arm64、触摸与 ENOSPC 结果见 [next-release-evidence](audits/next-release-evidence/)。PassWall 未安装，保持 NOT RUN。

## Matrix

| OpenWrt | Arch | Proxy / protocol | Required scenarios | Evidence |
|---|---|---|---|---|
| 24.10.5 | x86_64 | PassWall / TCP | full optimize、reuse success、current IP regression、rollback | install log、status、diagnostics、managed config diff |
| 24.10.5 | x86_64 | OpenClash / TCP+HTTP | transport filter、multi-IP apply、restart recovery | package/version、OpenClash readback、probe outcome |
| 24.10.8 | x86_64 | PassWall / TCP | delayed feedback across service restart、expiry、generation mismatch | before/after queue、qualification counters、logs |
| 25.12.0 | x86_64 | OpenClash / TCP+HTTP | resource pressure fallback、disabled cron cleanup | Runtime inspect、effective mode、crontab、rollback evidence |
| 25.12.5 | x86_64 | PassWall + OpenClash | end-to-end release candidate smoke | exact binary checksums、installed package metadata |

## Per-device procedure

1. Record device model, firmware image digest, architecture, package commit and Runtime/package qualification IDs.
2. Install the exact same-release base package, optional Rill package and Preview Runtime package; record package manager output and binary checksums.
3. Exercise both `reuse_enabled=1` and forced full optimize. Verify that reuse performs current-IP validation and that a failed validation enters full optimize without stale selection.
4. Change target domain, IP type, protocol, source policy and proxy mode one at a time. Verify fingerprint invalidation, explicit sync mode, LuCI validation rejection, stop/apply/restart ordering and rollback.
5. Restart the service between queue and delayed-feedback processing. Capture accepted, expired and schema/generation-rejected entries.
6. Preserve `/etc/cf_ip/status.json`, `/etc/cf_ip/rill-*.json`, `/etc/cf_ip/reuse-policy.json`, relevant logs, proxy readback and crontab as artifacts.

物理设备状态（2026-10-24 历史口径）：未执行。没有物理设备安装、proxy readback 或真实 network probe 证据前，不写“真机通过”。72h/7d Soak：按用户批准跳过。2026-11-07 起上述口径已由用户决策替代：KVM 设备视为设备级，证据见 [next-release-evidence](audits/next-release-evidence/)；上文历史记录保留不改写。

## Docker-backed validation record (historical)

作为设备不可用时的可重复安装运行 smoke，曾在本机 OpenWrt 25.12.5 x86/64 rootfs 容器中执行。该记录证明旧 SHA 安装后的 OpenWrt 用户空间链路，不替代物理设备和真实代理网络证据；本轮 Cloudflare consumer 修复后的当前 SHA 不继承这份安装证据。

| 项目 | 结果 |
|---|---|
| Container image | `owrt-25.12.5:latest`, local image ID `sha256:228f656806c36a66fd1dc242a101c3c8484fdf94e0dec8a16b646046a3125e6a` |
| Cloudflare commit / Actions | historical: `0cd064fa3cc6722a0fa3ffd7d2ff09568b55d16d` / run `33601273356` |
| Installed packages | `luci-app-cloudflare-ip-2.0.0.1-r1.apk`, `luci-app-cloudflare-ip-rill-2.0.0.1-r1.apk`, `rill-runtime-preview-1.5.6-r2.apk` |
| Package SHA256 | `85e183f710674b577f0a41f132a4e5fd1aca847237dd7926b9271bfb32808480`; `15eb6836639fc27ee680716710b82d2da2a30f578815a7b077f5d12a1eff6d5b`; `36ced00796b0d4aacd62eb3b48f10eebb8a1686b89d36925b1d3e292d4f00114` |
| Runtime checks | install PASS; PassWall/OpenClash validation PASS; invalid config rejection PASS; RPC list/call PASS; status/diagnostics JSON PASS; Runtime help PASS; disabled cron cleanup PASS |
| Boundary | No physical device, proxy readback, or real network probe was performed; post-install ubus registration was not exercised because the container was not booted with procd as PID 1. |

Docker 历史状态：**PASS（旧 SHA 安装运行 smoke）**；当前 SHA Docker 安装运行：**NOT RUN**；物理真机状态：**NOT RUN**；Soak 状态：**SKIPPED（用户批准）**。
