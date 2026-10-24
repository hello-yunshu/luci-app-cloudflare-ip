# G6 RC 验收与 G7 Stable 晋级准备

原范围以 stable-cross-repo-remediation-plan.md G6/G7、§8、§9 为准。当前整体 OPEN / Stable NO-GO。早前维护测试已回退原状态；用户随后明确推迟所有实机与Soak，直至再次明确通知。上游安全修复与重新资格已另获授权。备份和敏感现场只留本机受限证据目录，不提交仓库。最新状态和跨电脑继续入口见 plans/g6-g7-handoff-20261024.md。

## 2026-10-24 换机后的最新决定与推进

用户在本聊天更新指令：本地实机验证不作为 G6/G7 完成阻塞，且允许继续实机验证。该决定取代上述延期状态，原文及边界记录于 docs/audits/g6-g7-evidence/device-policy-20261024.json。当前候选实机与新 24h Soak 尚未执行，不能记为 PASS；软件资格、安全审计、同字节绑定仍须通过。完成 G7 是形成具体可审核晋级方案，合并、tag、Release 和 feed 发布仍待该方案单独批准。

已读回 RP run 40061634026 两次 attempt：六个目标均在读取官方 SDK 目录网页时连续 HTTP 502，未进入编译。官方相同路径的 sha256sums 可访问；RP 8581c717db8c57fc83c0ace4d808bb9d32b4b1eb 改为从该校验清单唯一解析 SDK 名称和摘要，拒绝缺失、重复、非法摘要、路径穿越及错版本/目标，保留下载后哈希校验。Linux 本地 54 项测试 PASS，真实官方清单解析 PASS。新资格 run 40066219701 正在运行，不提前记成功或更新 CF pin。

CF 的 evidence-manifest 步骤新增真实当次 SDK 包的离线 preflight 和十项篡改拒绝，结果与相对路径 SHA256SUMS 一起保存在同一 qualification-evidence artifact。此步骤不连接设备，不发布包；需随最终依赖更新后整合 SHA 通过完整 CI 才成为本次候选证据。

RP 8581c71 的 run 40066219701 attempt 1 已全部成功；manifest SHA256 为 421b3f6b4f12c92ac2288734c117f912f4c78ecfe38d714a9482676b71e4fa38。12 个实际下载包均经断网容器的真实 metadata/ELF/package/binary 摘要验证通过。各目标审计 DB 为 8a5b8090ef20c9c1b425f3373f28b0b23cc5c7a0（2026-10-24T03:33:55Z），均零漏洞、零警告、无 ignore；两渠道 lock 均为 3e20b673fd5c32c881a80242556532a919c8b1d2836dc6d538ee00740cad6311。

CF 现更新到该精确 RP 资格，Preview release 5，保留原 migration 与独立上游 source identity。保留 2.6.0-r5 / v2.6.0-5 作为候选，source channel 冻结为 stable；不代表公开 Stable。release.yml 原自动晋级拒绝 Stable 的保护不变。新 CI 在同一次资格中生成 stable-review.json，绑定最终候选 SHA/tested tree、run/attempt、两个原包摘要、Runtime pins、设备政策与 tag 未占用检查；只生成可审材料，不授予发布许可。若其中任何软件或审查门禁失败，G6/G7 软件状态仍 OPEN。

## G6 已执行

- 刷新 PR18（OPEN/DRAFT）、分支 1e806fe5fd1b3d7c18db72837d97377d1875e2c9 和成功资格39898577254 attempt1；上游 RP38928695476 attempt1 仍成功且 artifact 可读。
- 部署是 OpenWrt25.12.5 x86_64、APK3.0.5、Microsoft VM；已有1.8.3-r1和真实 OpenClash，无 PassWall/Runtime。不能称为物理设备/所有架构覆盖。
- 备份配置/代理/原应用 payload/包DB/world/cron/enable 状态到权限受限目录。公开旧APK SHA与checksum一致，19个非用户配置payload与现装文件逐一相同。实际 isolated APK root 升级→降级成功后，才执行在线安装。
- 同 run canonical APK 原SHA75a382c082f5de45c9780822fe00f7cbc5b161e868a71f0f10eef10ebfa65ba1重新下载验证。实际 owner admission PASS，原 DB SHA留存。
- 独立五分钟回退保护；停用自动优选后安装候选及唯一新增依赖uhttpd，再停止/禁用该新增默认web服务，原 nginx HTTP200保持。真实 APK hooks 执行，OpenClash PID、代理和网络配置字节未变。
- 实际原包降级/移除新增依赖后，原包集合、world、配置、代理PID均恢复。回退不是整份旧DB覆盖。

## G6 发现的问题及当前修复

目标 YAML 是 proxies-only 片段，控制器凭据在 OpenClash UCI 中。旧健康检查只从目标文件读 secret，导致实际稳定控制器被拒绝；使用现有 UCI dashboard_password 的只读对照通过。新增回归在 common、legacy、standalone 三个实际入口全部复现失败。仅无 YAML secret 时补读现有 UCI 凭据；不改变端口、ACL、stable PID/HTTP200/JSON 门禁，也不输出凭据。三入口四个分支通过，私有组件的实际控制器请求通过。详见 docs/audits/g6-g7-evidence/openclash-controller-credentials.json。

新源码必须提交并完成最新 exact-SHA hosted/SDK/迁移/同字节 preflight 后再安装；历史资格不晋升新源码。

## G6 待执行门禁

1. 新 SHA 全部软件必要门禁及上游资格/安全证据回读。
2. 新包实际在线安装，真实 UI、完整优选/无匹配/故障恢复/disabled/cron/reboot/LAN变址；测试前冻结每项恢复步骤，覆盖选中 YAML 片段和实际生效配置。
3. 有/无合格 Runtime、IPv4/IPv6与真实网络；PassWall/opkg未提供时明确未覆盖，不能用 mocks 换算。
4. 新24h Soak 的开始/结束、资源/重复任务/网络波动、稳定性阈值及中断状态实际记录。历史72h/7d豁免不继承。
5. 完整矩阵逐层结论，未覆盖设备由用户针对最终候选明确风险决定；失败回所属阶段，不拼旧run。

## G7 当前准备与约束

- 当前 version authority 为2.6.0-r5、tag候选v2.6.0-5；远端查询该tag未占用。版本比较在实际APK中2.6.0-r5 >1.8.3-r1，并实际完成升级/回退。最终提交与字节随本次修复重新冻结。
- release-channel.json 当前prerelease；release.yml明确拒绝Stable自动晋级。G7必须提供可审核的具体channel/版本/工作流方案，不能把当前prerelease资产说成Stable，也不能绕过检查。若改version/channel/workflow，则新SHA重新G6资格。
- 最终proposal需列最终SHA、同run/attempt IPK/APK及SHA256、Runtime source/package/binary pins、支持范围与设备/soak决定、升级和撤回说明、tag未占用回读。
- 发布只在具体proposal另获批准后执行。当前没有merge/tag/Release/feed/发布后验证；不得为了“完成G7”自动上线。
