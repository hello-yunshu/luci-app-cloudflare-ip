# G6 RC 验收与 G7 Stable 晋级准备

## 新目标：修复并完成24小时执行与验收

用户已明确要求继续修复并实现完整24小时Soak及验收，取代上一轮失败后的停止安排。22103dc虽然全部软件资格通过，实际首轮在私有候选映射校验rc15处中止，源恢复已验证，独立监督恢复原1.8.3与原设置；没有计时。期望生成器把已有编号变体各自重新全量展开，真实私有副本复现8条期望（仅4条唯一）对4条实际，全部字段可匹配。现改为按现有编号逐条建模并仅补缺号，保持各槽位的认证/传输信息，未标记模板继续完整展开；期望与实际名称唯一、错IP/字段/缺节点/真实重复的拒绝均保留。

相关8项WSL套件和4项原生隔离套件通过，同一真实失败输入在私有副本上得到4对4且全部字段匹配。完整事务回归覆盖扩容、连续更新、同IP幂等、不同认证、缺首号和写前拒绝真实重复；使用实际无ONIGURUMA原生jq与禁正则fixture通过。机器证据见soak-mapping-repair.json。软件修复不等于Soak完成：仍须新SHA全资格、真实首轮、满86400秒观察、负载/复用/资源/恢复的最终审查。24小时未完成前目标保持进行中；不得合并或发布。

## 2026-10-24 用户批准新24小时 Soak 后的最新状态

7db4286 的完整资格40086320914 attempt1及有限在线安装/回退均通过，随后用户明确批准24小时 Native/OpenClash Soak。部署后的首轮真实完整优选在配置应用阶段失败，独立恢复监督已恢复原1.8.3-r1和原设置，24小时计时尚未开始。失败记录见 docs/audits/g6-g7-evidence/soak-baseline-7db4286.json；该失败不能被先前软件绿灯覆盖，当前公开发布继续停止。

已复现异步启动的时间窗口缺陷：init可提前返回，随后固定10秒不足以完成三次稳定健康观察。修复使init与HTTP/PID验证共享原312秒总界限，三个入口一致；未放宽健康条件或新增无限重试。延迟启动正向、总预算耗尽和永不就绪负向在三个入口与本机/路由器隔离函数回归通过，八项相关套件通过。修复后的新SHA必须重新完成全资格与首轮实测，成功后才另起新24小时计时；原失败证据永久保留。

原范围以 stable-cross-repo-remediation-plan.md G6/G7、§8、§9 为准。当前整体 OPEN / Stable NO-GO。早前维护测试已回退原状态；用户随后明确推迟所有实机与Soak，直至再次明确通知。上游安全修复与重新资格已另获授权。备份和敏感现场只留本机受限证据目录，不提交仓库。最新状态和跨电脑继续入口见 plans/g6-g7-handoff-20261024.md。

## 2026-10-24 换机后的最新决定与推进

用户在本聊天更新指令：本地实机验证不作为 G6/G7 完成阻塞，且允许继续实机验证。该决定取代上述延期状态，原文及边界记录于 docs/audits/g6-g7-evidence/device-policy-20261024.json。当前候选实机与新 24h Soak 尚未执行，不能记为 PASS；软件资格、安全审计、同字节绑定仍须通过。完成 G7 是形成具体可审核晋级方案，合并、tag、Release 和 feed 发布仍待该方案单独批准。

已读回 RP run 40061634026 两次 attempt：六个目标均在读取官方 SDK 目录网页时连续 HTTP 502，未进入编译。官方相同路径的 sha256sums 可访问；RP 8581c717db8c57fc83c0ace4d808bb9d32b4b1eb 改为从该校验清单唯一解析 SDK 名称和摘要，拒绝缺失、重复、非法摘要、路径穿越及错版本/目标，保留下载后哈希校验。Linux 本地 54 项测试 PASS，真实官方清单解析 PASS。新资格 run 40066219701 正在运行，不提前记成功或更新 CF pin。

CF 的 evidence-manifest 步骤新增真实当次 SDK 包的离线 preflight 和十项篡改拒绝，结果与相对路径 SHA256SUMS 一起保存在同一 qualification-evidence artifact。此步骤不连接设备，不发布包；需随最终依赖更新后整合 SHA 通过完整 CI 才成为本次候选证据。

RP 8581c71 的 run 40066219701 attempt 1 已全部成功；manifest SHA256 为 421b3f6b4f12c92ac2288734c117f912f4c78ecfe38d714a9482676b71e4fa38。12 个实际下载包均经断网容器的真实 metadata/ELF/package/binary 摘要验证通过。各目标审计 DB 为 8a5b8090ef20c9c1b425f3373f28b0b23cc5c7a0（2026-10-24T03:33:55Z），均零漏洞、零警告、无 ignore；两渠道 lock 均为 3e20b673fd5c32c881a80242556532a919c8b1d2836dc6d538ee00740cad6311。

CF 现更新到该精确 RP 资格，Preview release 5，保留原 migration 与独立上游 source identity。保留 2.6.0-r5 / v2.6.0-5 作为候选，source channel 冻结为 stable；不代表公开 Stable。release.yml 原自动晋级拒绝 Stable 的保护不变。新 CI 在同一次资格中生成 stable-review.json，绑定最终候选 SHA/tested tree、run/attempt、两个原包摘要、Runtime pins、设备政策与 tag 未占用检查；只生成可审材料，不授予发布许可。若其中任何软件或审查门禁失败，G6/G7 软件状态仍 OPEN。

## G6 已执行

2026-10-24 软件退出审查补充：3bf0ec1 / run 40067431976 attempt 1 全部软件资格与生成的 Stable review 成功，head/tested merge 完整 tree 均 ecc1ea8882b37a7d7a3a2ab0dc0173d5ea7018dc；其实际原包在线安装、43 个非配置 payload、disabled 生命周期、真实 CLI/RPC 和 nginx 静态视图均通过，并正常回退原包/包集合/配置/状态/cron/world；所选外部 YAML 与实际生效配置在第二轮显式备份且前后摘要一致。原始私有日志留本机受限目录，脱敏 receipt 为 device-acceptance-3bf0ec1.json。此结果不继承到后续源码。

退出审查同时复现 Y01 未关闭的全文缺口：支持的 proxies 段之后的语法错误和重复根键仍被旧 guard 接受。新 guard 在三个入口解析完整 Psych AST，不实例化 tagged 对象，拒绝重复/复杂/隐式类型键及不能与行读取器等价的 mapped 标量，并验证生成与恢复候选后才允许发布。补修已有 Host 的重复生成、quoted literal # 的截断及需引用名称的序列化。20 项相关 OpenClash 回归、设备现有 Ruby 的隔离实际函数用例通过；真实配置私有副本通过新 guard 和渲染，线上文件/PID 不变。改变了产品源码，必须新 SHA 全资格及相应候选记录；不得以 3bf0ec1 的绿灯完成新候选。

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

## 24h 首轮健康预算修复（2026-10-25）

620b979资格40100766849 attempt1及本地原包preflight/十项负向通过后，实际baseline在测速前健康复查失败，未停止服务或写节点；监督器恢复原1.8.3-r1及原状态，计时未开始。路由器只读复查同一函数：5秒预算一次失败、一次成功，10秒成功。原5秒预算要求三次稳定观察、默认间隔两秒，只给全部认证HTTP及配置读取共一秒余量，边界抖动会误拒绝。

将common预检/写前检查和v2停服务前检查统一为10秒；三次稳定PID、HTTP200和JSON认证校验全部保留。现有完整资格执行的async-startup回归增加真实入口capture/stop/write的虚拟探测耗时：每次探测一秒时健康三次观察7秒通过，持续不健康仍在10秒内拒绝且不停止服务。新SHA必须重新完成完整资格和原包preflight后再部署；原620首轮证据保留，不计入24h。
