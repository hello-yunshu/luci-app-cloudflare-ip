# 2.6.0-r5 Stable 候选晋级方案

本方案是 G7 审查材料，不是发布许可。版本权威为包 Makefile；当前候选 `2.6.0-r5`，tag `v2.6.0-5`，source channel `stable`。未公开候选沿用 r5，不为每次资格单独递增；已发布 tag 和资产不可覆盖。真正冻结的候选 SHA、tested commit/tree、成功 CI run/attempt、两个安装包及其摘要，以最终成功 run 的 `qualification-evidence-run-<run>-attempt-<attempt>/stable-review.json` 为准。任何软件门禁失败都不能以本文件代替。

## 资格与支持范围

- 主产品默认 Native，Runtime 为显式可选的 Preview 辅助；不把 Preview v3 API 称为 Rill Stable，不让 Runtime 直接写代理配置。
- CF 软件资格包括 Host/Legacy/RPC-LuCI、四个 x86 SDK、真实 IPK/APK 迁移、同字节 Runtime 集成、真实 CFST smoke、Docker replay、实际包 metadata、离线 preflight 和十项当前字节篡改拒绝。各层证据独立，不把 replay/fixture 当设备 PASS。
- Runtime 固定 RP `8581c717db8c57fc83c0ace4d808bb9d32b4b1eb`，run `40066219701` attempt `1`，manifest SHA256 `421b3f6b4f12c92ac2288734c117f912f4c78ecfe38d714a9482676b71e4fa38`。Stable `1.5.6-r3` / Preview `1.5.6-r5` 两渠道、六目标共十二包资格及实际 metadata/ELF/hash 验证通过。具体 source/patch/lock/features/binary 身份见该 manifest 和 `contracts/rill-runtime.json`；不把新的上游修复提交冒充配方原始 source base。
- 安全审计保留默认 WASM/Cranelift/Pulley，Wasmtime 49.0.4、Tokio 1.53.3，十二个目标记录零漏洞、零警告、无 ignore。DB `8a5b8090ef20c9c1b425f3373f28b0b23cc5c7a0`；最终审查须核对资格时间，发布拖延或有新公告时重审，不能永久复用本次审计。
- 已接入设备是 OpenWrt 25.12.5 x86_64、APK、Microsoft VM、OpenClash。最终候选实际部署结果另列；不声明物理硬件、其他 CPU、PassWall 在线部署、opkg 实机、真实闪存掉电或所有 IPv6 WAN 场景通过。
- 用户在 2026-10-24 明确允许实机验证，并决定本地实机不阻塞 G6/G7 完成。新 24h Soak 未执行即记 NOT STARTED，不从历史 72h/7d 豁免推导 PASS；不从软件资格推导设备覆盖。

## 原字节资产

只采用同一个成功 CF run/attempt 的以下资产，不重新构建、不拼不同 run：

- `luci-app-cloudflare-ip_2.6.0-r5_all.ipk`
- `luci-app-cloudflare-ip-2.6.0-r5.apk`
- `qualification.json`、`release-preflight.json`、`release-preflight-negatives.json`、相对路径 `SHA256SUMS` 和 `stable-review.json`

原字节 SHA256 从 `stable-review.json.assets` 和 `SHA256SUMS` 读取。兼容 addon 不作为推荐下载；Runtime 独立资格/分发，不混入主产品两个包。PR merge commit 与 head 不同必须证明完整 tree 相同，审查 receipt 对此拒绝不等价树。tag 占用在生成 receipt 时检查，执行发布前还需刷新。

## 安装、升级、回退与撤回

1. 安装前备份 CF 配置/状态、选中 YAML 片段和实际生效 OpenClash 配置、包 DB/world、cron、服务 enable 状态及原版可恢复包；备份只留用户受限目录。记录原进程和配置摘要，并验证独立 SSH 恢复入口。
2. 校验 checksum、包真实 metadata、owner admission 和包管理器 solver；使用原文件名本地安装。不要 force-overwrite，不自动升级其他包。APK 目标安装 `apk add --allow-untrusted ./luci-app-cloudflare-ip-2.6.0-r5.apk`；IPK 目标使用 `opkg install ./luci-app-cloudflare-ip_2.6.0-r5_all.ipk`。新增依赖先明确列出，保护现有 nginx listener，不让默认 uhttpd 抢占端口。安装时停用 CF 自动优选，验证完成再按用户原状态恢复。
3. 安装后核对包版本、owned payload 每文件 hash、rpcd/UI/status、实际代理稳定 PID 和认证后的 HTTP 健康。先测试 disabled/lifecycle/无匹配/失败恢复，再执行有界真实任务；init 返回 0 不等于代理健康。
4. 失败时停止新增任务并保留诊断，使用已验证的原 `1.8.3-r1` APK 回退，恢复本次 owned 配置和原 cron/enable 状态；仅移除本次新增依赖。包数据库由包管理器维护，不整份覆盖旧 DB。出现用户或外部并发修改时停止自动覆盖，保留 diff 并人工裁决。
5. 设备实测 APK 比较已证明 `2.6.0-r5 > 1.8.3-r1` 和 `2.6.0-r5 > 2.6.0-r3`。IPK 升级、降级和状态保留使用本次 CI 的实际 opkg 迁移证据；额外线上平台不扩展为已验证。
6. 发布后出现故障应停止推荐、记录撤回范围，以新版本修复；禁止替换公开 tag/原资产。发布后独立下载和校验步骤在真正发布前保持 NOT RUN。

## 工作流与最终批准

现有 `release.yml` 的自动 workflow_run 仍只允许 prerelease，明确拒绝 Stable。此次 CI 只新增只读审查生成：完整资格、同 run 原包 preflight、十项负向、head/tested tree 一致、tag 未占用和当前设备政策均满足后，上传审查 receipt；不执行 merge、tag、Release 或 feed。

实际 Stable 发布另设受控人工晋级步骤：必须针对上述具体 SHA/tag/run/attempt/摘要和支持范围取得用户批准。若先合并到 main 导致 SHA/tree 或渠道/版本/工作流变化，应重新资格并生成新方案，不能把 PR 旧包当作新 main 包。晋级从唯一成功 run 收集原包，不重建；在外部发布前再次检查安全新鲜度、tag 未占用和审批对象一致，再创建不可覆盖的 tag/Stable Release。完成后独立下载公开资产复核 checksum/metadata/manifest/run/attempt。feed 必须单列真实目标并单独获批，不隐式扩展。

当前发布状态：NOT AUTHORIZED / NOT RUN。G6/G7 是否完成由最终资格、原字节复核、实际覆盖记录和审查结果决定。
