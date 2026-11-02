# 2.6.0-r5 Stable 候选晋级方案（历史记录，已被 r6 修复候选取代）

> 状态：本文的字节、哈希和结论只对应 r5 / `371bf78`。当前包 Makefile 已提升为 `2.6.0-r6` 审计修复候选；r6 需要重新执行 exact-head CI 资格化、严格预检和用户审批，本文不构成 r6 的发布许可。

本方案是历史 G7 审查材料。本文记录的候选为 `2.6.0-r5`、候选 tag `v2.6.0-5`、source channel `stable`；当前源码版本以包 Makefile 为准。自动 Stable 晋级在 `release.yml` 中保持禁用；merge、tag、Release、feed 和发布后回读都没有执行。

## 候选身份

- 候选提交：`371bf78b772540f5829e5700f4f09a73e33888c1`（本次只改 Runtime 依赖契约，不改 CF 包内 payload）。
- tested commit：与候选相同；完整 tree `96efc814ec9b0ddb3ff70f939875abe86d4e2315`。
- CI：run `41411391996` attempt `1`，全部 18 个 job success；qualification guard 与 evidence manifest 均 success。
- `qualification.json` SHA256：`f8ec144be0b98ac64832938e53d4c452efb41edcc94420256fcd989bfbf055f9`。
- 同一 run 的 `stable-review.json` 记录 `tagAvailable: true`、`publication: NOT AUTHORIZED / NOT RUN`。
- tag 回读：远端仅存在 `v2.6.0-1`、`v2.6.0-2`、`v2.6.0-3`；`v2.6.0-5` 未占用。执行发布前必须再次刷新。

## 安装包资产

只采用同一成功 run/attempt 的原字节，不重建、不混 run：

| 资产 | 大小 | SHA256 |
|---|---|---|
| `luci-app-cloudflare-ip_2.6.0-r5_all.ipk`（v24.10.5 IPK） | 165277 | `13d8695cbedf7017c99af2514032a9a638ef7469be523873c2a583c5d02bc1c1` |
| `luci-app-cloudflare-ip-2.6.0-r5.apk`（v25.12.0 APK） | 165277 | `5dd686b04ad3933e4bbef5c62e136a3f3c9ef88bd7d7cdbefd41b0d43e2dae2d` |

- `release-preflight.json`：PASS（离线真实 metadata/byte preflight）。
- `release-preflight-negatives.json`：10 项负向全部 PASS，包括错 commit/run/attempt、不可发布、路径穿越、交换摘要、Runtime pin、同长度改字节、额外包、symlink。
- 独立下载回读：两个 SDK artifact 的 `sha256sum -c SHA256SUMS` 均 PASS。该回读针对候选 artifact，不是公开 Release 下载；公开发布仍为 NOT RUN。
- 兼容 addon 只作为构建/迁移资格产物，不作为推荐公开下载。Runtime 独立分发，不混入 CF 主包。

## Runtime 与安全资格

- Runtime 包固定 RP `563fea8b9ff37cfcd7428258482e721775cc003f`，run `41409074857` attempt `1`，manifest SHA256 `8d6b7dc575ada8ba38f7d7ac29e16015836560eb3d66192bd15d59c75340a838`。
- Stable `1.5.6-r4` / Preview `1.5.6-r6` 两渠道、六目标共十二包资格通过；CF 同 run 的真实 Preview Runtime 集成 PASS，binary SHA256 `f0c41e549e3467659b7c9cf3dfcba680a922c352f6317a5e5682fe55167ebc32`。
- 安全修复：新增 patch 040，把默认 WASM 引擎从 Wasmtime 49.0.4 升到 49.0.5，处理 2026-10-29 新公告 `RUSTSEC-2026-0422/0423/0424`；源码 lock 为 `fb26ca6d05a48b657123bee2abcacc025dcfddb76916ed8009024451c201fa03`。
- 新鲜 RustSec DB `2295466c4e9df26647fd67d8fa1c705ac2fc7f81`（2026-10-30，1395 条）：**shipped `rill-runtime` feature graph 235 个依赖零漏洞、零 warning、零 ignore**。
- 完整 workspace lock 416 个依赖仍有 4 条非 shipped 的 zstd 公告（`RUSTSEC-2026-0391/0398/0403/0410`）和 `unsound` warning。原因是可选 `polars` 分析成员依赖 zstd 0.13，而 shipped Runtime 的 cargo tree 不含 `polars`/`zstd`。这些发现被完整记录为风险证据，不写成“全 workspace 零漏洞”，也没有使用 ignore。详见 `docs/audits/g6-g7-evidence/runtime-security-advisories-20261102.json`。
- 该非 shipped 发现是本次 Stable 的主要待裁决安全边界：接受则 Stable 支持范围只覆盖 shipped Runtime；不接受则需等 polars/zstd 上游升级后重新资格。

## G6 软件状态与未执行边界

- `371bf78` 的 Host、Legacy、RPC-LuCI、四 x86 SDK、两格式真实包迁移、同字节 Runtime 集成、真实 CFST smoke、Docker replay、资产合同、preflight 与负向、qualification/evidence guard 全部 PASS。
- 设备策略沿用 `docs/audits/g6-g7-evidence/device-policy-20261024.json`：用户明确本地实机验证不阻塞 G6/G7 完成。当前候选实机为 **NOT RUN**；新 24h Soak 为 **NOT RUN**，没有从历史 72h/7d 豁免推导 PASS。
- 完整八视图真实浏览器操作、当前 exact-candidate 隔离 rootfs/procd/rpcd 启动、物理硬件、PassWall 在线、IPv6 WAN、断电/ENOSPC 持久性均未在本候选上重跑；已有部分组件/native receipt，不得当作本候选 PASS。
- 因此本方案是 **CONDITIONAL GO**：软件资格与可审资产已齐，发布仍取决于用户对上述设备/Soak 与非 shipped zstd 边界的明确裁决。

## 安装、升级、回退与撤回

1. 安装前备份 CF 配置/状态、选中 YAML 片段和实际生效 OpenClash 配置、包 DB/world、cron、服务 enable 状态及原版可恢复包到用户受限目录；记录原进程和配置摘要，并验证独立 SSH 恢复入口。
2. 校验 checksum、真实包 metadata、owner admission 和包管理器 solver；使用原文件名本地安装。不要 force-overwrite，不自动升级其他包。APK 使用 `apk add --allow-untrusted ./luci-app-cloudflare-ip-2.6.0-r5.apk`；IPK 使用 `opkg install ./luci-app-cloudflare-ip_2.6.0-r5_all.ipk`。新增依赖先列出，保护现有 nginx listener，不让默认 uhttpd 抢占端口。
3. 安装后核对包版本、owned payload 每文件 hash、rpcd/UI/status、实际代理稳定 PID 和认证后的 HTTP 健康。先测 disabled/lifecycle/无匹配/失败恢复，再有界执行真实任务；init 返回 0 不等于代理健康。
4. 失败时停止新增任务并保留诊断，使用已验证的原 `1.8.3-r1` APK 回退，恢复本次 owned 配置和原 cron/enable 状态；仅移除本次新增依赖。包数据库由包管理器维护，不整份覆盖旧 DB。外部并发修改时停止自动覆盖，保留 diff 并人工裁决。
5. 设备 APK 比较已证明 `2.6.0-r5 > 1.8.3-r1` 和 `2.6.0-r5 > 2.6.0-r3`；IPK 升级/降级/状态保留使用 CI 的实际 opkg 迁移证据。该证据不扩展到其他平台。
6. 发布后故障应停止推荐、记录撤回范围，以新版本修复；禁止替换公开 tag/原资产。真正发布后的独立下载/校验步骤在发布前保持 NOT RUN。

## 工作流与最终批准

现有 `release.yml` 只允许 `main` 上的 prerelease 自动路径，遇到 `stable` channel 明确退出；本方案不修改该 guard。实际 Stable 发布必须另设受控人工步骤，至少再次确认：

- 候选 `371bf78`（或重新资格后的 exact SHA）与 tree 未变；
- `v2.6.0-5` 仍未被占用；
- 同一成功 run/attempt 的 IPK/APK/SHA256SUMS/qualification.json 可回读；
- Runtime pin/run/manifest 与支持范围仍一致；
- 新鲜安全 DB 与本次披露的非 shipped zstd 边界已获裁决；
- 设备/Soak 风险接受或补验已完成。

若先把本方案/文档合并到 `main` 导致 SHA/tree 改变，必须对新 `main` SHA 重新跑完整 CI 和 preflight，不能把 `371bf78` 的包当成新 `main` 包。本文档的后续 docs-only 提交不改变包字节，但不是新的发布候选。

## 当前发布状态

`NOT AUTHORIZED / NOT RUN`。没有 merge、tag、Release、feed 或发布后验证；没有修改任何公开资产。
