# Cloudflare IP 2.x Stable 跨仓库修复实施计划

审计日期：2026-10-15（Asia/Shanghai）。结论：**Stable NO-GO；规划完成，修复未开始**。

执行依据：/Users/yunshu/Downloads/luci-app-cloudflare-ip-cross-repo-stable-planning-prompt.md。本轮仅阅读、隔离验证及撰写本文件；没有改业务源码、测试、锁文件、配方、工作流、发布元数据，没有 push、PR、tag、Release、远程 dispatch、生产安装或真实代理写入。以下“修改/安装/晋级”均为未来工作。

## 1. 执行结论

当前不具备 Stable 资格。主产品 exact-head CI 失败；此前成功 CI 的发布晋级也因真实 IPK 与验证器合同冲突失败；Rill 同步会丢迁移字段；OpenClash 特定写入后故障不能恢复；上游依赖安全准入未关闭。SDK、旧资格 PASS、局部测试通过不能替代整体资格。

优先顺序：G0 刷新冻结 → G1 版本与产物合同；G2 上游安全可与 G1 独立进行；之后 G3 Runtime 包资格与同步、G4 消费端门禁；G5 可靠性按文件边界并行，最后 G6 RC 与 G7 Stable 准备。首个独立开发阶段为 G1，不先改所有版本数字。

### 1.1 精确源码基线

以下别名严格代表“仓库 + 完整 SHA”，供所有证据行引用；不是浮动分支。行号除显式说明外来自对应本地检出。本轮用 GitHub API 重新查询远端，没有 fetch/pull/切换检出。

|别名|仓库与基线|完整 SHA|状态|
|---|---|---|---|
|CF|hello-yunshu/luci-app-cloudflare-ip / main|75f5a2d11c13c5d9aa46dfb8159259b2c94c73c5|本地 main = 远端 main；初始干净|
|RP|hello-yunshu/rill-openwrt-packages / main|64ee22f978ed8f8ed19bb675700678f57eec19e3|本地 codex/openwrt-reaudit 与远端 main 相等；初始干净|
|RL|hello-yunshu/rill-ml / 本地与消费端 Preview pin|da8389fec7f879b826d8d17cbc6bb98c03ef8462|本地 codex/openwrt-rill-partition；初始干净|
|RS|hello-yunshu/rill-ml / Stable v1.5.6|b990cd7043d313b0ff29c9693f091a94a5bdaf47|由 contract、包资格及 tag 源码核对|
|RM|hello-yunshu/rill-ml / 远端 main|9602750202f56ed860fc8815bb91e81083d0ffdb|比 RL 前进 3 个提交；远端 Cargo 文件用 Contents API 复核|
|PM|hello-yunshu/luci-app-performance-manager / 远端 main|d5c42e1867d34ea1aa3013485e713504bd9163aa|当前定时 sync 运行基线|
|PML|同上 / 本地 yunshu/openwrt-reaudit|09e5f0f3fd3f18b4eaa153896a6b76895d9a78b5|比 PM 前进 84 个提交；初始干净；不擅自合并|

四仓默认分支均 main；这些仓库及适用父目录未发现 AGENTS.md。已读取 README、存在的开发说明、Rill STABILITY.md / RUNTIME.md、CF preservation matrix / release gates / 真机说明；旧文档只是行为保留线索，不能证明当前 HEAD。

CF Makefile 当前 PKG_VERSION=2.6.0、PKG_RELEASE=5，release-channel.json=prerelease。最新公开预发布为 [v2.6.0-3](https://github.com/hello-yunshu/luci-app-cloudflare-ip/releases/tag/v2.6.0-3)，tag commit 为 8535a42eb425b4fb317771dda603b29daee4d6b0；历史迁移 [v2.6.0-2](https://github.com/hello-yunshu/luci-app-cloudflare-ip/releases/tag/v2.6.0-2) 为 652476bd3cdc410bc16e3a47ee96b685c84acbbb。README 所称当前 r4 / v2.6.0-4 与源码及公开发行均不同。

Rill 最新公开 Stable：[v1.5.6](https://github.com/hello-yunshu/rill-ml/releases/tag/v1.5.6)；包仓公开 Stable：[v1.5.6-r1](https://github.com/hello-yunshu/rill-openwrt-packages/releases/tag/v1.5.6-r1)；PM 最新公开 Stable：[v1.0.3](https://github.com/hello-yunshu/luci-app-performance-manager/releases/tag/v1.0.3)。这些 Release 的 target_commitish=main 不替代 peeled tag SHA。

相关 PR：CF #16 已合并，#15/#14/#13 为历史合并记录，当前远端只有 main；Rill #47 partition 修改、#46 rand 修改已合并，开放 #49 仅更新 tokio/pyo3/libc，不能当作 Wasmtime 修复；RP #3 已合并，#2 仍开放，涉及 feed/release 独立，后续避免冲突；PM #11 已合并、#12 关闭未合并。这里只审阅相关近期记录，不声称覆盖所有历史 PR。

公开渠道补充（本轮API回读，最多100条release列表）：CF最近正式Stable仍为[v1.8.3-1](https://github.com/hello-yunshu/luci-app-cloudflare-ip/releases/tag/v1.8.3-1)，2.x最新为上述预发布；Rill最近标prerelease的历史发行是[v1.2.0-rc.3](https://github.com/hello-yunshu/rill-ml/releases/tag/v1.2.0-rc.3)，不能把它与现在exact-commit Preview渠道混同；RP列表无prerelease发行；PM历史最新prerelease为[v1.0.0-rc.14](https://github.com/hello-yunshu/luci-app-performance-manager/releases/tag/v1.0.0-rc.14)。历史名称不重写，也不作为未来版本选择。

### 1.2 新发现与验证限制

- **真实 IPK 内部 Version 是 2.6.0-r5**，验证器却要求 2.6.0-5；必须修真实合同，不能改伪包制造绿色。
- **CF CI 执行的 Preview binary 与锁定的 RP qualification run 的 binary 哈希不同**。源码相同不代表同一合格 binary；现有 sameRelease 证据未闭合，不能解释为字节相同。
- 新 OpenClash service guard / legacy 独立入口保护本轮 focused tests 通过，不能重复安排已修复的旧故障；仍存在写后快照失败恢复缺口。

四仓源码、相关 runs/jobs、失败日志及所列 artifact 均可访问。本轮没有浏览器 LuCI、真实路由器、真实 CFST 网络测速、本机 SDK 重建、完整 cargo test 或本机 cargo-audit。安全扫描实跑证据是 2026-10-12 RM 的日志，辅以本轮官方公告回读和 RL feature tree，不等于 10-15 重跑安全全库。APK 本轮读取 same-run sidecar metadata，没有本机 apk adbdump；hosted 安装迁移单列。未验证的设备、架构与 soak 仍 OPEN / NOT RUN。

## 2. 跨仓库架构和依赖图

~~~mermaid
flowchart TD
  RS[Rill Stable tag / source / archive hash] --> RPS[RP rill-runtime recipe]
  RL[Rill Preview exact commit / IPC v3] --> RPP[RP rill-runtime-preview recipe]
  RPS --> Q[Target registry / SDK / qualification]
  RPP --> Q
  Q --> FEED[Immutable packages / Release / signed feed]
  Q --> LOCK[CF immutable Runtime contract]
  UI[LuCI views / utils / staged UCI] --> RPC[rpcd cf_ip / ACL]
  RPC --> MAIN[Installed cf-ip-auto = v2]
  MAIN --> SRC[Sources / last-good / CIDR / reuse]
  SRC --> CFST[One bounded CFST / target-domain probes]
  CFST --> NAT[Native eligibility / ranking / safe envelope]
  NAT --> RILL[Optional Candidate Rill preview subprocess]
  LOCK --> RILL
  RILL --> NAT
  NAT --> TXN[PassWall or OpenClash transaction]
  TXN --> HOST[UCI / YAML / service / readback / recovery]
  TXN --> STATUS[Status / history / delayed feedback]
  STATUS --> PUB[Optional LAN Publisher]
  FEED --> PM[PM split consumer]
  FEED --> FULL[PML full APK exact Runtime payload]
~~~

安装入口由 CF package/luci-app-cloudflare-ip/Makefile:58–75 决定：cf-ip-auto-v2 装为 /usr/bin/cf-ip-auto；cf-ip-auto-legacy 为转换与兼容路径。root/usr/libexec/cf-ip/*.sh、root/usr/libexec/rpcd/cf_ip 与八个 LuCI 视图构成实际链条，不能只审独立旧 wrapper。

|层|实际合同|精确身份|
|---|---|---|
|Stable source/runtime|serve IPC v1/v2、签名 WASM handler、Stable ABI|RS；包 1.5.6 release1；archive SHA-256 c06a792811d1f08aa7b640c10ee36047c44f825cf7272aa0f75c42ab60806a84|
|Preview runtime|显式 preview-serve --state，IPC v3、handlerApiVersion2|RL；Feature Schema2、Model Generation2；不是产品包版本|
|RP package|两渠道均安装 /usr/bin/rill-runtime|RP；Preview release2，CONFLICTS=rill-runtime，不能并装两个 owner|
|RP qualification|qualify.yml、六目标|run33735123909；manifest SHA-256 55c31521a617d7205c88f85941a856eab9c64d8467910620791b51cc907620a5|
|CF consumer|contract schema2、Optional Runtime、Native fallback|锁 RP/RS/RL/run 与历史 packageMigration|
|CF 实际集成 binary|来自 CF 自己 SDK 重编的 Preview 包|SHA-256 12cdc66cf49b24b4a1fe735cb61dcda1535de231a0d0cd74d0dce32158e25243|
|RP qualified Preview x86 IPK|本轮直接读上游 artifact9885672715 并解包|package SHA-256 a09c912e3b02454f8de7c90ddb0883cf47c7d4fa485f324f3777ea9f70ab98ee；binary SHA-256 15411284b8107e5a982d0c51aa23dc5721e96cf3afc84cca57f92569eb7c8ca7|

RP metadata/openwrt-targets.json：24.10.8 IPK / 25.12.5 APK × x86_64、aarch64_generic、aarch64_cortex-a53，共六目标。CF CI 另有 24.10.5 / 24.10.8 / 25.12.0 / 25.12.5 四个 x86 SDK job，public assets 选择两个旧 patch SDK 的主包。G1 要区分“构建支持矩阵”和“公开代表资产政策”，不直接删除旧目标。

PM 有真实关联：PM/PML split recipe 依赖 +rill-runtime；PML full APK Makefile:24、80 自己拥有 /usr/bin/rill-runtime 并与 split rill-runtime 冲突，但未列 Preview 包。PML Core usr/sbin/performance-manager.uc:2041–2085 调 preview-serve / IPC v3；PM main contract 同时列 Preview commit 和 Stable 包名。因此共享 ABI/Feature/二进制 owner 要协调，但不因此扩大到 PM 业务重构、整体发布或其 84 个提交合并。是否需具体修改以同机安装/协议回归为依据。

权限不变量：Rill只处理允许的学习/辅助排序，不得直接写UCI/YAML、修改代理、重启服务或执行主机命令。Native必须重新验证候选、目标域名、safe envelope及事务条件；Runtime的坏响应/缺失/错误只能降级，不能扩权。G2/G3/G5测试要用恶意action/未知capability/路径与命令字段验证拒绝，检查CLI/handler导入与宿主执行器没有绕行通道。

实际外部依赖：XIU2/CloudflareSpeedTest Release API/digest/CPU assets；OpenClash UCI enable/core PID/localhost controller /group；PassWall UCI 节点/服务；Cloudflare 官方 v4/v6 与 source.sh registry 的社区 HTTPS 来源；OpenWrt SDK/Rust feed、LuCI UCI apply、rpcd/ubus/ACL、procd/uhttpd、opkg/apk；Actions checkout/setup/download/upload、gh、Docker、RustSec/CodeQL、usign/APK feed 签名。第三方只审兼容与来源，不假定能修改。

## 3. 证据核实表

分类仅四种：**已证实缺陷 / 高风险待复现 / 验证空缺 / 设计/体验建议**。P0 为发布阻断，不等于公网可利用事件；P1 为 Stable 前应修，P2 可后移，P3 后续版本。表中基线别名完整定义于 §1.1。

### 3.1 问题与旧线索复核

|ID / 优先级|分类 / 仓库与源码定位|证据、根因、是否已修复|
|---|---|---|
|V01 P0|已证实缺陷；CF Makefile:4–5；tests/package-release-bump-contract.sh:5–7|release5 对测试固定4；原测试本轮 exit1，host CI 同步失败；未修|
|V02 P0|已证实缺陷；CF scripts/validate-qualification-evidence.py:128–133；validate-release-assets.py:46；openwrt-package-metadata.py:109–140|真实 IPK 2.6.0-r5，strict validator 要2.6.0-5；旧 promotion 日志明确 packageVersion mismatch；未修|
|V03 P1|已证实缺陷；CF ci.yml:714–727；tests/release-asset-contract.sh:3–22；release-asset-binding.sh:13–20|asset job touch 空伪包且固定-4；shell测试未使用VERSION校验身份；binding造纯字节伪IPK/2.6.0-4，没覆盖真实metadata；篡改负向有效应保留|
|V04 P1|已证实缺陷；CF README.md 当前状态/下载段，README.en.md对应段；release.yml:189、209；Makefile:51–55；utils.js:8；rpcd/cf_ip:3、191–192|文档仍r4；UI/RPC模板已按PKG_VERSION替换，不是纯旧常量，但缺package release；未统一|
|C01 P0|已证实缺陷；CF tests/regex-ip-suffix.sh:6–8、53；cf-openwrt-auto.sh OpenClash state guard；ci.yml:197起|本轮原测试exit1，和legacy job同报不能读enable；fixture只mock restart，缺UCI/PID/controller。应补fixture，不能撤销生产fail-closed|
|C02 P0门禁|验证空缺；CF ci.yml:729–740|完整资格未通过；guard正确拒绝host/legacy失败与package guard skipped，不是额外guard bug。当前Release skipped正确|
|S01 P0|已证实缺陷；CF scripts/check_rill_dependency.py:92–115、60–61|内存mock API+捕获write_text调用真实sync，丢顶层packageMigration；check却强制要求该字段；未写工作区、未修|
|S02 P1|已证实缺陷；CF sync-rill.yml:31–43|本轮最新run Author identity unknown；源码后续还缺GH_TOKEN、base为不存在的cloudflare-ip-2.0-dev、branch只按version且不幂等。只有身份是当前实跑到的失败，后续问题不冒充实跑日志|
|S03 P1|高风险待复现；RP sync-rill-version.yml:26–47；update_rill_version.py:68–96|最新sync SUCCESS为无更新路径；变更路径无git身份、branch/push不幂等；重建metadata丢扩展字段，同版本重置release1可能倒退；未触发远端修改|
|R01 P0安全准入|已证实缺陷；RL/RS/RM Cargo.lock wasmtime46.0.3；Cargo.toml:69；runtime/Cargo.toml:26–30、52|RM audit命中两RustSec公告；锁版本命中已证实，具体利用需feature/调用路径判断，见§3.3|
|R02 P0证据合同|已证实缺陷；RP qualify.yml:392–449；CF ci.yml:278–302、551–620|RP targets只绑定Stable hashes，Preview只有汇总PASS；CF自己重编执行的binary与qualified Preview不同hash，缺同bytes资格闭环，未修|
|T01 P1|已证实缺陷；CF transaction.sh:94–100、278–287；openclash-transform.sh:5–10|隔离注入transform写后失败/成功后written快照cp失败，两者applyRc14/rollbackRc1，current=new，rolledBack=false，误判外部冲突。没有假报恢复成功，但无法恢复本次写入|
|T02 P1|高风险待复现；CF transaction.sh:61–79、153–166|正常PassWall有ownership/remarks检查，rollback却全量import snapshot；外部并发改动可能被stale覆盖，须真实UCI staging/commit注入|
|U01 P1|已证实缺陷；CF utils.js:51–78、232–255|Node VM时钟超时、status始终false/error仍resolve，save/apply无条件显示ready；浏览器未跑|
|U02 P1|高风险待复现；CF utils.js:20–26、235–244|VM确认code5被吞；后续uci.load未明确强制fresh read并比candidate；实际LuCI缓存/ubus错报待复现|
|L01 P1|高风险待复现；CF publisher.sh:15–28|四文件逐个atomic write，多文件跨代窗口/中途写失败存在；真实并发HTTP/故障尚未运行|
|L02 P1|高风险待复现；CF cf_ip_publisher:24–39|只在start解析LAN，只有cf_ip reload trigger；未见网络变更重绑。其他外部机制是否重启未证实|
|Y01 P1|高风险待复现；CF openclash-readback.sh:15–35|注释仅block YAML；awk跳过不支持语法不等于整文件拒绝，混合inline/anchor待负向确认|
|N01 P1|高风险待复现；CF source.sh:209–265|curl不支持max-filesize时下载完才检查大小；有deadline但无同等流式磁盘cap，chunked/低磁盘待注入|
|N02 P1|高风险待复现；CF cf-ip-auto-legacy:562–606，同standalone下载函数|在线新下载已有上游digest失败保旧；缺metadata缓存可用自算hash，不能证明来源认证。需区分可信last-good与来源不明遗留包|
|N03 P1|验证空缺；CF ci.yml:700–707|real-CFST smoke下载latest后直接解包执行，未见digest比较；与生产下载校验分开，需补CI供应链验证|
|C03 P2|已证实缺陷（清洁性）；CF cf-ip-auto-v2:761、836|重复cmd_sync，后者包装cmd_sync_explicit为实际路径；清理需行为等价，不属P0|
|P01 P1协调|已证实共享影响；PM/PML contract/split/full Makefile；PML Core:2041–2085|共用binary/IPC，full未列Preview conflict；真实包管理器冲突待复现，只安排必要兼容/owner检查|
|P02 P2旁路|已证实main自动化缺陷；PM sync-rill.yml:31–43；PML同文件:10–41|main定时身份失败；PML已经改read-only drift检测，不能向PML重复安排旧修复或自动恢复PR；不作为CF无条件发布阻断|
|E01 P1|验证空缺；CF strict validator及RP verify_qualification.py:17–82|CF strict fixture允许jobs={}，主要信任releaseEligible；在线workflow另有success检查，没有实际发布绕过证据。应统一离线自洽predicate|
|M01 P1|设计/体验建议；CF package-migration.sh:262–266；validator:57–66；ci.yml:784–785|r2/r3 pins合理；currentSHA为release5时仍生成r3ToR4=true，应新增通用from/to矩阵并保留历史语义|
|D01 P1准入|验证空缺；CF docs/REAL_DEVICE_VALIDATION.md:24–39|真机NOT RUN；72h/7d历史用户批准SKIPPED；不得变PASS|

### 3.2 已执行验证、CI和产物索引

本轮本地 PASS：37次shell/JS/JSON语法检查；CI同范围ShellCheck error级；CF全部workflow actionlint；release-channel-contract、v2-prerelease-workflow-contract、release-asset-binding、qualification-evidence-validator、openwrt-package-metadata、openclash-review-regressions、openclash-service-guard、openclash-legacy-service-guard；check_rill_dependency.py --package-dir 的本地一致性检查。最后一项不是live qualification验证。

本轮 FAIL：package-release-bump-contract、regex-ip-suffix。内存/临时目录复现S01/U01/T01，不写真实代理；Python使用-B/PYTHONDONTWRITEBYTECODE=1。未全跑测试，不用“有测试”冒充PASS。

|索引|本轮回读精确run/job事实|
|---|---|
|CI-CF|[38070244923](https://github.com/hello-yunshu/luci-app-cloudflare-ip/actions/runs/38070244923) @CF整体FAILURE；[host](https://github.com/hello-yunshu/luci-app-cloudflare-ip/actions/runs/38070244923/job/114265996779) release identity失败；[legacy](https://github.com/hello-yunshu/luci-app-cloudflare-ip/actions/runs/38070244923/job/114265996646) regex前置状态失败；[guard](https://github.com/hello-yunshu/luci-app-cloudflare-ip/actions/runs/38070244923/job/114270047828)拒绝|
|REL-CF|[37727468886](https://github.com/hello-yunshu/luci-app-cloudflare-ip/actions/runs/37727468886/job/113148840077) @19252d3751e561b16811f00d027616b6184bac8e，packageVersion mismatch；源CI[37725810592](https://github.com/hello-yunshu/luci-app-cloudflare-ip/actions/runs/37725810592) SUCCESS并未能晋级；当前[38071649447](https://github.com/hello-yunshu/luci-app-cloudflare-ip/actions/runs/38071649447) SKIPPED|
|SYNC-CF|[38683655476](https://github.com/hello-yunshu/luci-app-cloudflare-ip/actions/runs/38683655476/job/116253521167) @CF 身份缺失exit128|
|SEC-RM|[38217192127](https://github.com/hello-yunshu/rill-ml/actions/runs/38217192127/job/114704575559) @RM，cargo-audit FAIL/2 vulnerabilities；CodeQL SUCCESS不能替代依赖安全|
|Q-RP|[33735123909](https://github.com/hello-yunshu/rill-openwrt-packages/actions/runs/33735123909) @RP：六target、Preview parity、signing negatives/evidence SUCCESS|
|REL-RP|[33735959489](https://github.com/hello-yunshu/rill-openwrt-packages/actions/runs/33735959489) release SUCCESS；[33735959422](https://github.com/hello-yunshu/rill-openwrt-packages/actions/runs/33735959422) feed SUCCESS；[33735123997](https://github.com/hello-yunshu/rill-openwrt-packages/actions/runs/33735123997) repository contract SUCCESS；[38677914947](https://github.com/hello-yunshu/rill-openwrt-packages/actions/runs/38677914947)无更新drift SUCCESS|
|CI-PML|[34014116941](https://github.com/hello-yunshu/luci-app-performance-manager/actions/runs/34014116941) @PML：static/runtime-v3 SUCCESS，Core集成准备包源wget SSL/index EOF而FAIL；不能据此断定业务代码回归；同SHA[34014116940](https://github.com/hello-yunshu/luci-app-performance-manager/actions/runs/34014116940) build SUCCESS|
|SYNC-PM|[38682421645](https://github.com/hello-yunshu/luci-app-performance-manager/actions/runs/38682421645/job/116249708814) @PM身份失败，不代表PML当前read-only workflow失败|

本轮内存解ZIP/tar回读，未执行下载binary：

- CF artifact11676374840资格JSON：commit=CF/runId38070244923，host/legacy failure、package guard skipped，qualificationState=incomplete、releaseEligible=false。生成job成功只代表诊断证据生成。
- CF artifact11675979668，24.10.8真实IPK：SHA-256 a388b0ab6e647400bc911132ea277ed5bd46c9f56f7d6e559fea1a52ac549feb；control Version=2.6.0-r5、Architecture=all，依赖含libc/luci-base/bash/curl/tar/jq/CA/uhttpd。
- manifest选用24.10.5 IPK：SHA-256 4fa8a5eb625afdfb460a1927452476beeaafa348ffa33d4d8b5c63159dbeb70f / size141758；25.12.0 APK：85c3c04db5c5af599ab70d9c04a74dd3bcb43f1b3f4909492e83b0cfb30d1915 / size141870，metadata noarch/2.6.0-r5。不同target同basename不能混合。
- CF artifact11676837633的25.12.5 APK sidecar：e611fc45ee26fb8134149c3b57946cc59cde3deee394fb5f8d7f7893ef6f4242 / size141869；未本机独立adbdump，不能抬高证据等级。
- RP artifact9885716347的manifest已读；CF integration artifact11676967461与RP Preview artifact9885672715的实际binary哈希见§2。SDK/flags不同可以导致差异，**没有恶意替换证据**；缺口是可追踪的资格绑定。

可复制复现入口：原V01/C01分别运行 bash tests/package-release-bump-contract.sh 与 bash tests/regex-ip-suffix.sh。S01导入真实模块，mock api返回当前release/run，把CONTRACT.write_text替换成内存捕获，比较顶层keys，丢packageMigration；禁止直接在工作区--sync。U01在Node VM stub rpc/uci/baseclass与时钟，status始终false/error，timeout=1仍resolve。T01在mktemp目录source transaction.sh，stub服务/时钟，分别注入transform写后return1、written-snapshot cp失败，两者apply14/rollback1/new文件保留且被判外部冲突。

### 3.3 安全可达性与反例

本轮RL执行 cargo tree --locked -p rill-runtime -e features -i wasmtime，宿主与 --target x86_64-unknown-linux-musl 均成功：Runtime默认wasm引入wasmtime46.0.3，启用component-model/cranelift/pulley/runtime/parallel-compilation/std，未出现component-model-async。最初offline缺缓存，后续只补外部Cargo缓存再读，未build或改lock。此树不替代每个SDK实际features。

[RUSTSEC-2026-0327](https://rustsec.org/advisories/RUSTSEC-2026-0327.html) / [Wasmtime官方公告](https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-32h6-97mm-8q3c) 指向async callback校验路径；官方说明禁用component-model-async可规避。RL树未启用该feature，故依赖命中已证实，CF当前可触发sandbox escape未证实。未来feature合并可能改变，必须记录。

[RUSTSEC-2026-0316](https://rustsec.org/advisories/RUSTSEC-2026-0316) / [Wasmtime官方公告](https://github.com/bytecodealliance/wasmtime/security/advisories/GHSA-jqpg-j7w6-42pr) 为动态Val lifting资源计量；Rill handler/wasm.rs:38与stateful_wasm.rs:20用typed bindgen，官方称静态typed API不受该路径影响。仍需扫描全binary是否有其他动态调用，不能扩展成所有构建安全PASS。

默认优先升级到实施时同时修复两公告的受支持补丁线，更新相关wasmparser/Cranelift/lock并重资格。本计划不写死未来依赖patch。禁止永久ignore，也不为换绿全局关闭默认WASM：Stable serve和签名handler、其他消费者可能依赖它。若另做OpenWrt core-only profile，须单列能力合同、两渠道回归与全部受影响消费者资格，不能改全产品默认语义。

交叉复核结论：LuCI视角要求timeout不冒充ready；Bash/RPC视角要求恢复不覆盖外部写入；Runtime视角区分锁命中与可达；供应链视角区分源SHA与binaryhash；Release视角拒绝伪包PASS；恢复视角注入每个写入边界；真实用户视角以浏览器操作和状态readback证明体验。采用这些反例统一计划，不将角色名称当作额外证据。

## 4. 版本与发布合同设计

### 4.1 分层单一来源与数据流

保留主Makefile的PKG_VERSION/PKG_RELEASE为产品权威，release-channel.json仅管理渠道。新增小型只读identity reader/CLI（建议scripts/package_identity.py），不增加第二份手填当前版本。构建生成供CLI/RPC/UI读取的产品版本描述，建议usr/share/cf-ip/package-version.json；校验占位符全部替换，package release必须可观察。

分层来源：

1. 源产品身份=Makefile+channel；按既有惯例派生 v<PKG_VERSION>-<PKG_RELEASE>。
2. 产物身份=真实IPK control / APK adbdump的raw packageVersion/name/architecture/file bytes；raw保留，logical version/release规范化后与源身份比对。SDK漂移必须FAIL，不反向静默改源版本。
3. 依赖身份=RP分渠道metadata/recipe的owner；CF contract锁一个已资格run与不可变source/package/binary。
4. 协议身份=IPC/API/handlerABI/schema/model generation，独立兼容演进。
5. 证据身份=target、format、实际basename、raw metadata、size、package/binary SHA-256、source/lock/toolchain/features、run/attempt/artifact ID。

~~~text
现状：
Makefile → 多处sed抽取 → workflow各自猜文件名
真实IPK metadata保留-rN → validator要求-N → promotion失败
当前release固定测试 + touch伪包 → 局部全绿
sync重建JSON → migration字段丢失

改造：
Makefile + channel → 唯一identity reader → build/tag/CLI/RPC/UI/docs派生
真实SDK输出 → 唯一包inspector → raw+normalized metadata + file/hash
target registry + public asset policy → exact allowlist → qualification manifest
qualified Runtime包/binary → consumer集成 → same-bytes证据
同一predicate → 测试/aggregate/promotion/preflight/公开回读
field-aware sync → schema + 允许字段diff + 写后自检 → 未来受审PR
~~~

不采用从Git tag猜所有版本（未打tag构建不可靠）；不采用version.json与Makefile双手填；不全局sed替换数字。各workflow读identity JSON输出，不复制独立grep/sed逻辑。RP可保留自己的包adapter，但共享文档化schema/conformance vectors，不让consumer下载未锁远程工具。

具体CF文件：package/luci-app-cloudflare-ip/Makefile、release-channel.json、scripts/package_identity.py（建议新）、scripts/openwrt-package-metadata.py、validate-qualification-evidence.py、validate-release-assets.py、check_rill_dependency.py；.github/workflows/ci.yml、release.yml、sync-rill.yml；tests/package-release-bump-contract.sh、openwrt-package-metadata.sh、release-asset-contract.sh、release-asset-binding.sh、qualification-evidence-validator.sh、release-channel-contract.sh、v2-prerelease-workflow-contract.sh、release-download-contract.sh、package-migration.sh；README.md/README.en.md及UI/RPC版本模板。新增schema/测试路径在G1编辑前确定allowlist。

### 4.2 允许不可变的内容与应派生的内容

|内容|规则|
|---|---|
|当前产品/package release、显示、tag、下载指南|权威源派生；Runtime package release不再永久断言2|
|当前target/artifact paths|registry和public policy派生，实际metadata确认|
|历史r2/r3 tag/SHA/hash/包|具名historical fixture，保留不改；新增from/to不重写旧记录|
|已资格source/archive/binary hash/run ID|每次受审更新的一组immutable pins，不能变成latest|
|schema/API/Feature/Model Generation|协议不变量，不跟产品版本自动加一|
|clientIdentity.version=2.0.0|不是当然缺陷；RL stateful.rs:1014–1017以name+partitionKey隔离。缺显式客户端兼容身份文档，默认保留并定义语义，产品包版本另显示，避免破坏state/feedback|

### 4.3 真实产物身份及升级规则

- 本run隔离目录，按expected target/format/name发现，再读取包metadata；每个公开identity恰好一个。拒绝旧包/额外包/错架构/addon/runtime混入、路径穿越、符号链接逃逸、重basename、缺metadata和size/hash替换。
- CF公开一IPK+一APK政策可保留，但显式选代表target，不任意find-first。各SDK同名产物保留target namespace，不能混到一个平面目录。
- all/noarch按格式与真实metadata准入表解释；IPK ar/tar包装继续支持；APK用匹配SDK的真实apk工具。不能只依后缀认包。
- 真实包回归来自有来源/hash的fixture或同一SDK job；伪包只用于byte/path负向，不证明metadata/安装。checksum只列绑定资产，拒绝重复/绝对路径/清单自身递归，集合必须一致。
- 不倒退到2.0.0，不此刻拍最终Stable数字；G7读取当时发布序列，以真实opkg compare-versions和apk version -t证明严格升级。工具缺失的格式门禁OPEN。
- 既有base version可递增package release，确需兼容变化也可新SemVer；同版本package-only修订不能被updater重置release。已存在tag/asset不复用、不覆盖。

自动合同测试：临时副本只改authority一次，派生身份/下载示例/构建描述全部一致；覆盖多个未来版本、多位release；拒绝非法版本、非正release、重复authority、metadata漂移、占位符残留、升级倒退、同tag变SHA/hash；历史fixtures不变，协议代数不随包版变；sync保留非owned字段且重复执行无diff。规范演进必须有旧reader兼容或明确拒绝策略，不能静默接受未知schema。

### 4.4 预发布→Stable精确晋级

默认先提交最终版本/渠道候选并重资格；Stable proposal绑定最终精确SHA、同qualification run/attempt、安装包与Runtime bytes、安全DB时间、迁移结果。RC是验收阶段，不要求占用并重写同一个prerelease tag；若channel元数据变更产生新SHA，重新资格。若未来希望只改Release label晋级同SHA同bytes，需独立政策与明确授权，本计划不默认授权。

promotion核对source repository/event/branch/workflow、SHA/status/conclusion、required jobs、manifest hash/run/attempt、pins与资产全体bytes，再检查tag未占用。发布后从公开端重新下载全部包/manifest/checksums，读peeled tag SHA/渠道、解包/hash比对。不允许旧CI提升新代码。

Runtime Stable/Preview各自受控升级；自动发现“最新已资格版本”只用于候选更新，不允许生产漂移latest；不要求Preview API硬升Stable才能发布CF。

## 5. 跨仓库修复问题总表

|工作包/级别|唯一责任/关联|方案与验证|失败回退|
|---|---|---|---|
|WP-A P0 V01/V02；P1 V03/V04|CF / RP只读|唯一identity、真实metadata、动态测试、版本显示；真实IPK/APK与所有篡改负向|回退阶段提交，历史fixture保留|
|WP-B P0 S01；P1 S02|CF / RP|field-aware sync/schema/写后check，身份/token/base/幂等；no-op/update/repeat/失败mock|保留原contract，不产生半写或远端副作用|
|WP-C P0 R01|RillML / RP/CF/PM|安全升级，保默认WASM，两渠道ABI/状态/签名/资源；最新audit/target tree|失败保候选、Stable仍NO-GO；不晋级漏洞版|
|WP-D P0 R02；P1 S03|RP / Rill/CF/PM|两渠道每target包/binary digest资格；同步字段保留/幂等；签名feed负向|不发feed/不推进下游pin，旧资产不可变|
|WP-E P0 C01/C02；P1 E01/M01|CF / RP资格|fixture补新guard、通用migration、统一predicate；Host/Legacy+真实包/DB+tamper|不删断言不ignore，公开Release不动|
|WP-F P1 T01/T02/Y01|CF|先expected-after/journal后mutation，CAS恢复，全文件YAML边界；ENOSPC/外部改动/信号|冲突保live+snapshot与诊断，不stale restore|
|WP-G P1 U01/U02|CF|ready/timeout/cancel分离、fresh UCI readback、请求序列/busy；VM+浏览器|失败保输入与状态，不冒充成功|
|WP-H P1 L01/L02/N01/N02/N03|CF|publish generation/重绑，流式cap、缓存trust、CFST CI digest；HTTP/源/下载故障|保last-good，诚实降级|
|WP-I P1条件 P01|PM / RP/CF|只在实证需要时改lock/owner/ABI；split/full共装与独立state|不混入未合并PM功能，报告支持限制|
|WP-J P2 C03/P02|各问题所属仓库|等价清理/旁路自动化；可后移|不阻断已限定Stable主线|
|P3|另议|新算法、新Runtime框架、扩大未验证架构、全量YAML重写器、新PM功能|不纳入Stable修复范围|

没有本轮缺陷证据的Native/来源/权限链条安排验证任务，不预先重写。发现新P0/P1先附失败证据再加入工作包，不能把所有改善当阻断。

## 6. 阶段路线图

全阶段共用自审：**diff审查 → 原失败与修复验证 → 反例/故障注入 → 相关测试 → 跨仓库兼容复核 → exact-SHA证据**。每子阶段一个责任仓库。工作量S/M/L只表示相对复杂度，不承诺工期。

### G0 现状冻结与开发前复核（责任CF，S）

- 目标/依赖：先刷新本文之后的提交/工作区/remote/run状态；关联四仓，无上游依赖。
- 文件：本计划与下一轮证据索引；读取四仓Makefile/contract/workflows及§3原失败测试，不改业务。
- G0a记录完整SHA/分支/dirty/PR#2/#49/PM分支差异；G0b复现V01/C01/S01/U01/T01并保before；G0c检查artifact可回读和过期状态。
- 设计：SHA+run/attempt+artifact ID索引，不采用“全部切main/拉最新”以免混淆Preview与PM分支。
- 正/负/回归/集成：正确索引可回读；错SHA/过期/缺artifact明确BLOCKED；检查旧问题是否新提交已修；无真机则NOT RUN。
- 验收/证据/复核：每个P0可定位且有责任仓库，维护者/测试视角签收；失败只补证据不修业务。回退为保留原检出/文档与证据。可在独立冻结完成后进入G1/G2/G5。

### G1 主产品统一版本与包产物合同（责任CF，M）

- 前置G0；RP只读。G1a identity reader；G1b真实包parser/validator；G1c动态测试/显示/下载文档；G1d sync字段保留纯函数与schema测试，不运行远端同步。
- 文件：§4.1 CF清单；建议新增contracts/package-artifacts.schema.json、tests/package-identity-contract.sh，编辑前确定allowlist；历史fixture只增加索引，不覆盖包。
- 缺陷V01–V04/S01，复现§3。设计§4；不采用改测试固定=5、全局替换、放宽版本任意字符串。
- 正向：单点authority修改贯通build/tag/CLI/RPC/UI；真实IPK/APKmetadata与源匹配。负向：非法/倒退/缺字段/额外或错target包/同basename/hash替换/字段丢失。回归：历史fixture与现有status字段兼容。
- 集成：同run真实包贯穿inspector→qualification→release validator；本机无apk须隔离Linux补验，否则该项OPEN；真机留G6独立授权。
- 旧行为风险：旧IPK validator规则、只显base version的UI、fixture结构；用明确reader/schema迁移保留历史。
- DoD：V01修复、V02真实包通过且篡改继续拒绝，sync保留migration，相关测试全部通过；不把channel先改Stable。证据为before/after命令、原metadata/hash、diff。包/Release视角复核；失败回退阶段commit、保留证据。
- 并行：G2独立；G5 UI也改utils.js时须串行整合。G4a fixture可在G1接口确定后先做。

### G2 Rill安全与两渠道兼容（责任rill-ml，L）

- 前置G0，可与G1并行；关联RP/CF/PM。先比较RM/RS/RL，确定安全补丁应落哪个受支持基线，不整体用main替换Preview。
- 文件：Cargo.toml、Cargo.lock、crates/rill-runtime/Cargo.toml；升级确需才改src/handler/wasm.rs、stateful_wasm.rs；对应tests/qualification脚本；security.yml/pipeline必要门禁、RUNTIME.md/STABILITY.md能力说明。不扩算法范围。
- G2a新鲜audit+各target树/触发路径；G2b安全依赖升级；G2cStable v1/v2/Preview v3能力、schema/model/state回归；G2d签名资产与平台资格。
- 对应R01。默认保WASM；不采用永久ignore或全局关默认feature。core-only只作为需额外能力评审的备选。
- 正向：Stable签名handler/IPC、Preview health/decide/feedback/snapshot/reset。负向：无handler、坏签名/未知key/损坏包、超大payload、错schema/model/state、异步恶意组件拒绝、fuel/epoch/memory上限。回归：旧state恢复或隔离、重复feedback幂等、delayed lineage不串。
- 集成：release模式binary+真实OpenWrttarget feature tree与CF/PM fixtures；真实设备资源留G6。
- 可能破坏MSRV/SDK Rust、RSS/体积、handlerABI/state；逐项报告。验收新鲜audit无未处理命中，两渠道能力/冻结baseline/签名/资源通过。新源身份由未来获授权流程形成，不重写旧tag。
- 证据：SBOM/lock hash/DB时间/tree/target binary hash/run。Rust安全与消费者视角复核。失败保候选，Stable NO-GO，不推进生产pins。

### G3 Runtime包与同步（拆成单仓子阶段）

**G3a：责任RP，L；前置G2安全源码资格；关联Rill/CF/PM。**

- 文件：两recipe/metadata、metadata/openwrt-targets.json仅政策确需时、scripts/update_rill_version.py、check_upstream_version.py、verify_qualification.py、qualify.yml/sync-rill-version.yml/release.yml/feed.yml/repository-contract.yml及对应tests。
- 对应R02/S03；Stable/Preview各自来源、包身份。manifest增加每target Preview包/binarydigest、features/toolchain/source lock、run/attempt；旧schema兼容reader明确。Preview无archive时用git+lock/build输入，不伪造archive SHA。
- sync repo-local作者、最小write权限、GH_TOKEN限step、有效base、候选身份包含source/package identity，已有branch/PR复用、no-update无写；不force push用户branch。先准备全部变化→schema/允许字段diff/自检→原子写；未知字段保留或显式迁移，失败不半写。
- 默认消费者下载qualified bytes；不采用“同sourceSHA即同binary资格”。必须重编时，为重建binary建立完整独立资格，不能继承旧binary资格。
- 正向六目标两渠道真实metadata/ELF/loader/安装owner；负向错target/旧额外包/同tag变hash/Preview缺digest/坏key/index/package；回归旧reader/feed与state，sync重复/no-op/已有closedPR/权限失败用stub或临时仓库测试，无真实远端写。
- 风险：同binary路径、旧schema消费者、feed身份。验收包集合=registry、每target package/binary绑定，签名负向通过。证据matrix/metadata/installed DB/run/hash，由包/供应链/恢复视角复核；失败不发布新feed、不推进下游lock，保留旧不可变资产。

**G3b：责任CF，M；前置G3a；关联RP。**

- 文件：contract/check_rill_dependency.py/sync-rill.yml/ci.yml Runtime integration、相关sync/Runtime tests；复用G1字段保留设计。
- lock选择一个成功run/attempt，直接取该target qualified Preview，解包hash比对后执行；Native无Runtime路径保留。sync base=main且验证存在性，身份/token/branch/PR幂等。
- GITHUB_TOKEN创建PR可能不触发必需CI：计划须确保人工或获授权token策略使checks实际执行，不能以开PR代替资格。无授权不自行申请或使用新凭证。
- 正/负：no-update无diff、新pin只动owned字段、migration/未知字段保留、重复幂等；缺qual/403/超时/错run/SHA/hash/binary皆拒绝；写后check。回归Native fallback、安全candidate envelope、真实Runtime生命周期。
- DoD：S01/S02关闭、同bytes证据和CI实跑；风险为旧contractreader/自动化行为。Runtime/维护者复核；失败保旧lock且Stable NO-GO，不伪装已升级。

**G3c：条件责任PM，M；前置G3a；只处理实证兼容影响。**

- 先选PM还是PML支持基线，不合并84个提交。可能文件：contracts/rill-runtime.json、split/full Makefile、Core Runtime适配必要行与对应tests，禁止无关PM业务重构。
- 复现共享ABI与包owner：Stable/Preview、split/full组合、卸载/重装/回退；不得force overwrite。共用binary时两消费者identity/partition/state独立。
- full↔Preview若同路径不兼容，显式拒绝并给支持组合；必要时加冲突声明/调整owner。新安全Runtime pin需各自资格，未受影响模块“无影响，不改”。
- main旧sync身份问题与PML已read-only政策分开处理；不擅自还原自动PR。
- DoD：无覆盖他包binary/state，CF与PM v3各自握手/feedback回归；PM视角复核；失败停该分支，CF披露共装限制，不把PM全项目都列为CF阻断。

### G4 主产品CI / 迁移 / Release门禁（责任CF，L）

- 前置G1+G3b；fixture子阶段G4a可G1后先行，关联RP资格。
- 文件：ci.yml/release.yml、经复现定位的tests/regex-ip-suffix.sh、passwall-managed.sh/security-contract.sh及legacy fixtures、package-migration.sh、qualification-evidence-validator.sh/release-asset-binding.sh、validator和具名migration policy。不是无差别重写tests。
- G4a补enable/PID/controller mocks并保fail-closed负向；G4b通用from/to/packageManager/runtime/addon场景；G4c同一predicate；G4d离线preflight/文档。
- 对应C01/C02/E01/M01/V02。guard必须继续拒绝missing/failed/skipped job，诊断manifest成功不代表releaseEligible。
- 正向：真实旧base→候选、base+addon→base、r3与最近公开→候选、有/无Runtime、addon移除baseowned文件保留。负向：安装失败/owner冲突/缺artifact/hash替换/错SHA/run/attempt/extra/wrong arch、伪造job状态、缺source digest；不得产生tag/Release副作用。
- 使用真实opkg/apk隔离root和installed DB；现有假dependency/Runtime包只证明包管理器ownership，不能冒充真实代理或Runtime集成。回归UCI/custom URL/备份/history/cron/卸载语义。
- 不将Stable与Preview必须不同SHA当永久规则，按渠道能力合同判断；不删除历史r3ToR4，新增current通用矩阵并注明旧字段语义。
- DoD：全部Host/Legacy/SDK/真实migration最新exactSHA终态通过，release preflight用相同bytes；线上发布仍NOT RUN。证据metadata/installed DB/owner/配置before-after/manifest与日志；Release/迁移视角复核。失败保持旧公开资产。

G4 最新检查点：缺失/截断安装包的真实 opkg、apk 拒绝与已安装状态保留检查已加入迁移；资格门禁强制要求对应非零退出和保留证据。Host 负向校验通过，真实包管理器执行待当前 SHA CI，仍 NOT EVALUATED。覆盖写入冲突、安装中途失败和完整卸载生命周期仍 OPEN。

### G5 可靠性与LuCI体验（各子阶段唯一责任CF，L）

关联Rill/RP只读；Runtime真实集成等G3，多数可G0后独立复现。事务优先，其次状态诚实性、来源与LAN；共享主入口/公共库修改串行整合。

|子阶段/具体文件|方案/缺陷/备选|正向、负向、回归、集成|
|---|---|---|
|G5a事务：transaction.sh、openclash-transform.sh/readback.sh、cf-ip-auto-v2、legacy/standalone相应函数与事务tests|T01先staged expected-after+恢复journal后mutation；snapshot失败要在真正写前；T02 UCI CAS/owned字段恢复；Y01整文件支持边界preflight。不采用stale全量恢复或全量换YAML框架|成功/无匹配/disabled不启动；每个cp/mv/jq失败、ENOSPC/permission/TERM/KILL/服务timeout/外部编辑；保preimage/expected/observed/root error；一次恢复、self-disable不重试仍通过|
|G5b UI：utils.js、overview.js、所有共享save/apply视图、CSS、JS tests|U01显式ready/timeout/cancel；U02fresh UCI readback比candidate；busy+请求generation避免旧响应覆盖，不采用无限等|code5/网络失败/未提交/init成功未ready/重复点击/快速切页；真实八视图320/375/768/桌面、键盘/焦点/按钮可达；保存/应用/重启实际操作截图，不用静态grep代替|
|G5c网络：source.sh/cfst.sh、legacy/standalone下载、observe/reuse/scheduler/adaptive库与tests|N01流式硬cap+总deadline；N02可信last-good标记；N03 CI先digest后执行；无证据部分先验证不重写|大chunked/慢源/HTTP redirect/坏CIDR/特殊地址/空源/缓存坏或旧/IPv6非nibble；CFST坏digest/错arch/commit失败保旧；deadline kill整树；reuse强制fresh、Native唯一准入、shadow无影响、guarded坏证据回退|
|G5d LAN：publisher.sh、cf_ip_publisher、status/UI、v2-lan-publisher tests|L01 generation目录+原子current切换、成功才更新；跨独立HTTP请求仍需generation标识/读协议，不能声称目录原子切换保证永不跨代；L02网络接口事件重绑|并发HTTP/每文件失败/切换失败/进程退出、LAN IP变更/丢失/恢复、bind不属LAN/0.0.0.0/IPv6/端口占用、停用无监听入口；真实socket/HTTP readback，不以init0报success|
|G5e生命周期/RPC：cf_ip init、rpcd/cf_ip、ACL/menu/config.sh、Makefile hooks与迁移脚本|启动/停止/reload/boot/升级卸载/cron一致，最小读写方法和参数/路径白名单，诊断脱敏；C03证明等价后可删|只读会话不能写、注入/坏backup ID/并发run-sync-start、信号清理；cron重复/禁用/掉电恢复；保旧UCI/backup/history/custom URL，RPC保错误，不擅自操作用户代理|

G5e 最新检查点：共享 writer-lock 的 stale-PID 双写及 PID 写失败误接受已复现并修复；Host 15 个实际函数故障用例及相关回归通过。新增 OpenWrt flock 依赖、安装必需 helper 和四 SDK 目标工具执行门禁。当前 SHA 的 hosted/包资格、原生 procd/rpcd/LuCI、完整生命周期仍 OPEN；详见 `g4-g5-execution.md` 与 `writer-lock-recovery.json`。


- 可能破坏：不支持YAML形态的旧行为、并发编辑、旧缓存兼容、LuCI保存链；默认保守拒绝并给具体原因，不部分解析宣称完整验证。
- 每子阶段工作量M或L，以原失败与反例是否闭合为准。没有证明的风险先复现，有缺陷才最小修复。
- DoD：P1确认关闭，原guard/Native/回退不变量保留，相关测试+跨库兼容通过；UI与HTTP真实证据单列。设备写入只G6另授权。
- 证据：before/after故障日志、文件hash/状态时间线、UI操作截图；恢复/RPC安全/用户视角复核。
- 回退：各子阶段独立commit或功能开关；保last-good、配置和诊断。外部冲突不盲恢复，留下可核对diff和人工恢复路径。未通过则Stable门禁OPEN。

### G6 RC验收（责任CF，L）

- 前置G1–G5必要项；关联冻结的Rill/RP与条件PM。CF拥有RC总证据索引，上游各自拥有资格，不用一个仓库替另一个签收。
- 文件：资格脚本/schema/证据文档、docs/REAL_DEVICE_VALIDATION.md；默认不改产品，发现缺陷返回所属阶段，新SHA重新资格。
- 执行§8全矩阵，Host/mock/真实Runtime/SDK/rootfs/CFST/UI/设备/soak独立结果，不能按总测试数汇成PASS。
- 最小真机建议：非生产或维护窗口，先备份与恢复入口；一台opkg、一台apk（或明确限定验证范围），IPv4/IPv6各一次，PassWall/OpenClash正常与失败恢复，有/无Runtime、cron/reboot、LAN变址；建议新24h资源/重复任务/网络抖动观察。
- 收益为发现procd/flash/负载/真实网络缺陷，风险为短时断网和配置/闪存操作，需用户单独授权。未授权NOT RUN，不阻断软件开发。
- 旧72h/7d保持SKIPPED(user-approved)，不自动套用于新24h或新候选真机。
- DoD：软件必要门禁exactSHA全PASS，设备覆盖或有限风险接受如实记录；Release/恢复/用户视角复核。证据每仓SHA、run/attempt、target、hash、安装DB、日志/截图和缺口。失败撤回RC推荐，重冻结，不拼接旧产物。

### G7 Stable晋级准备（责任CF，M；不自动发布）

- 前置G6软件GO、Rill/RP资格可回读、设备政策决策；关联上游只读。
- 文件：最终version authority/channel（若改则退回G6重资格）、release workflow/README/安装升级与回退说明、最终清单。
- 输出具体proposal：候选版本选择与包管理器比较、tag未占用、最终SHA、同run/attempt包集合、checksums、Runtime pins、支持范围。本文不指定未来版本。
- 正向preflight/升级/下载后回读演练，负向全部tamper拒绝；真正线上发布与发布后验证未做前NOT RUN。
- 主产品Stable可继续默认Native、显式可选Preview辅助且披露渠道，不强迫Preview API升Stable。
- DoD：P0零、P1关闭或有限例外、无未裁决风险。用户批准具体proposal后才进入未来发布动作。
- 复核Release/供应链视角；失败保旧tag/bytes，停止推荐、写撤回说明、必要时新版本hotfix，禁止替换旧资产。

### 6.1 依赖与并行

~~~text
G0 ─┬→ G1 ─→ G4a fixture ──────────────────────┐
    ├→ G2 ─→ G3a RP ─→ G3b CF ─→ G4b/c/d ─────┤→ G6 → G7 proposal → 未来明确发布授权
    │                  └→ G3c PM(真实影响才改)  │
    └→ G5a/e、G5b、G5c/d ──────────────────────┘
~~~

G1/G3b/G4均触ci.yml，接口先确定、整合串行；G5a/e共享入口也排队；G2独立。上游未资格不能新生产pin，包资格未过不能下游晋级。G6必须对整合新SHA重验。本图仅未来任务组织，本轮没有启动并行开发或子代理。

## 7. 逐阶段 Codex 验收清单

通用完成定义（每个子阶段强制执行）：

- [ ] 开始记录完整HEAD/branch/status/remote差异，只改本阶段allowlist，不覆盖用户修改。
- [ ] 每个缺陷有before失败证据；环境缺工具单独BLOCKED/NOT RUN，不能当产品FAIL或PASS。
- [ ] diff审查无删失败用例、降校验、永久ignore漏洞、扩大权限与无关重构。
- [ ] 同一原失败用例修复后通过；至少一个独立反例/边界注入仍正确拒绝。
- [ ] 跑相关测试/真实产物/集成，绑定最终SHA、命令、退出码、环境和原日志。
- [ ] 检查上下游API/ABI/schema/Feature/Model Generation、state/文件owner、升级/回退。
- [ ] 契约保留非owned字段或显式迁移，历史tag/包/hash/证据不可覆盖。
- [ ] 未跑项明确OPEN/NOT RUN，mock/容器/SDK/UI/真机/Release不得互换。
- [ ] 恢复演练保外部配置，证据脱敏且可回读；无独立授权不做远端发布和真机写。
- [ ] 给出changed/why/tests/limits与该阶段GO/NO-GO；失败不隐瞒、不自动进入下阶段。

|阶段DoD|最小证据与复核|
|---|---|
|G0|新基线/失败索引，新提交对旧问题逐项校正；维护者+测试视角|
|G1|单点版本派生、真实IPK/APK贯穿validator、非法/混包/篡改拒绝、sync字段保留；包/Release视角|
|G2|新鲜audit/DB时间、target tree、Stable/Preview冻结协议、签名/资源回归、binary/lock身份；安全+消费者视角|
|G3a|每target两渠道package/binary hash、run/attempt、安装owner、signed feed负向、sync重复/no-op；供应链视角|
|G3b|CF直接消费qualified bytes，lock/migration保留，无Runtime回退、CI确实执行；Runtime视角|
|G3c|明确PM支持基线，共享owner/ABI测试，必要pin与独立资格；无影响模块不改；PM视角|
|G4|Host/Legacy全终态、两格式真实迁移DB、统一predicate/release preflight所有反例；迁移/Release视角|
|G5每子阶段|原失败→修复→注入→回归→兼容；UI实点截图、网络/服务readback分别记录；恢复/权限/用户视角|
|G6|整合RC exactSHA全矩阵，设备/soak真实状态及风险决定；不得拼旧run|
|G7|具体version/channel/tag未占用、同run资产清单/安装与撤回说明、可审proposal；发布仍待未来授权|

## 8. 测试和证据矩阵

“当前”仅指所列精确基线，未来RC重跑。PASS hosted=本轮回读远端终态；PASS local mock只证明模拟。没有把“源码中有脚本”记成执行通过。

|层 / 场景|当前真实状态|未来必要验证 / 证据|
|---|---|---|
|语法/JSON/JS、ShellCheck/actionlint|PASS local @CF，§3.2范围|改后全相关范围、PO/LMO、静态权限；不代表功能PASS|
|版本/渠道|V01 FAIL local/hosted；两个旧prerelease契约PASS|多未来版本/单点修改；Stable渠道演进不能被旧测试永久禁止|
|Host全合同|FAIL hosted @CF，早期退出；本轮仅focused通过|全体必要脚本实际跑完，Native/Reuse/Adaptive/多IP/状态/并发|
|Legacy保护|new guard/review PASS local mock；全legacy FAIL/regex本轮复现|补真实前置mock，standalone/legacy/v2一致，保fail-closed负向|
|RPC/ACL|rpc-luci-contract PASS hosted；本轮读源码|真实ubus读写会话权限、方法白名单、参数/路径/命令注入、日志/诊断敏感数据检查|
|LuCI真实UI|NOT RUN|八视图保存/应用/重启/刷新，code5/timeout/cancel/重复点击/迟到响应；窄屏/键盘/焦点、截图+fresh config readback|
|真实CFST|PASS hosted real-cfst-smoke @CF；本轮未执行binary/网络|CFST版本/digest/arch绑定，真实输入输出、整树deadline；先修CI下载执行前digest缺口|
|候选来源/双栈/缓存|本轮完整NOT RUN，有源码线索|HTTPS/redirect/流式cap、超大慢源/空乱码、last-good新鲜度、IPv6 /0 /128/非nibble、特殊地址与无源不写|
|Native/Reuse/Adaptive|本轮完整NOT RUN|fresh reuse且不调用Runtime；Native唯一安全准入、多IP唯一/不足如实degraded；shadow无影响/guarded证据坏旧压力回full Native|
|真实Runtime集成|PASS hosted @CF真实OpenWrt binary，但R02上游bytes绑定不闭合|二进制缺失/超时/崩溃/压力/错schema/过期training-evaluation/坏state/重启，delayed feedback隔离、Native fallback|
|Rill依赖安全|FAIL hosted @RM；本轮官方公告/tree复核|最新audit/DB时间/每SDK features、签名handler和其他消费者回归，不永久ignore|
|RP SDK矩阵|PASS hosted @RP六目标+Preview parity|升级后两渠道×六target；metadata/ELF/依赖/loader/owner；ARM真实执行或模拟明确区分|
|CF SDK矩阵|PASS hosted @CF四x86 SDK|真实IPK/APK清单/metadata/LMO/依赖，旧包extra/wrong arch拒绝；ARCH=all不证明所有CPU运行|
|真实包迁移|PASS hosted @CF IPK/APK；依赖/Runtime部分为fixture|旧base/addon→候选、r3/最近公开→候选，installed DB与文件owner/配置备份/cron/卸载；真实Runtime集成另证|
|事务/服务停启|new guard/review PASS local mock；T01 FAIL注入；T02/Y01待复现|写前后所有边界、外部改动/恢复timeout/disabled不启动/init0无core不能ready；readback完整性|
|磁盘/信号/断电|T01快照故障FAIL；其余本轮NOT RUN|ENOSPC/permission/TERM/KILL进程树/journal窗口/rootfs重启；物理断电另授权，不等同SIGTERM|
|LAN Publisher|真实HTTP NOT RUN，L01/L02待复现|generation一致/失败保旧、实际监听属当前LAN、LAN变址重绑/短断网/禁用清理/并发请求|
|Cron/init/升级卸载|本轮完整运行NOT RUN|禁用/启动/停止/reload/boot恢复/重复cron/CFST保留；旧addon不删baseowned文件，不重写代理配置|
|Docker replay|PASS hosted @CF，timing=replayed|逻辑/回放指标；不能证明真实网络节省或硬件长期稳定|
|当前SHA rootfs安装|本轮NOT RUN；migration为独立层|当前包在真实隔离rootfs安装/升级/卸载、ubus/procd/uhttpd；旧文档容器PASS不继承|
|PM共享Runtime|PML runtime-v3 hosted PASS；Core集成FAIL传输；PM main sync FAIL|选定基线后最小ABI/owner资格；未合并PML不代表公开PM|
|资产篡改/资格|binding/strict negatives PASS local伪包；真实promotion FAIL|真实包贯穿，错SHA/run/attempt/旧artifact/extra/同size替换/manifest/jobs篡改全部拒绝|
|公开Release/tag回读|元数据已读；新发布未执行；当前promotion SKIPPED|未来授权后peeled tag/channel/所有公开bytes/metadata与同run manifest一致|
|真实设备|NOT RUN|G6最小设备提案需独立授权，明确未覆盖CPU/代理/网络|
|72h/7d soak|SKIPPED（历史用户批准，文档保留）|不转PASS；新24h建议NOT RUN另决策；不阻断软件开发|

每个测试产物至少含：repo/full SHA、contract/source/lock/toolchain/features、run/attempt、target与包管理器版本、真实/模拟标签、命令/退出码、before-after hash、是否改变用户状态、日志位置与缺口。性能/稳定性阈值沿用已定义合同或测试前确定，不能看到结果后改阈值。

### 8.1 远端主线与非主线证据补充

同SHA的主线结果必须优先于“最新一次非主线失败”的泛称：

- RM [pipeline34191264100](https://github.com/hello-yunshu/rill-ml/actions/runs/34191264100)、[linux-musl34191264083](https://github.com/hello-yunshu/rill-ml/actions/runs/34191264083) 为SUCCESS；之后安全公告更新导致同RM security run失败，旧构建绿不覆盖新安全FAIL。
- PM main [CI33512156044](https://github.com/hello-yunshu/luci-app-performance-manager/actions/runs/33512156044)、[build33512156120](https://github.com/hello-yunshu/luci-app-performance-manager/actions/runs/33512156120) 为SUCCESS；PML自己的新CI/构建见§3.2，不能互换。
- Rill最新[pipeline38198799640](https://github.com/hello-yunshu/rill-ml/actions/runs/38198799640)与[linux-musl38198799596](https://github.com/hello-yunshu/rill-ml/actions/runs/38198799596)位于开放依赖PR的 a787a52e18887a4518b9fc6e949de124c6a19d7b，不是RM/RL。本轮日志核实：pipeline的public API baseline job114647342751失败，摘要尚不能确定具体符号差异；musl riscv64gc构建在wasmtime46.0.3 signals.rs:307–406因libc缺REG_PC/REG_S0/REG_SP/REG_A0失败（E0425/exit101）。这是真实上游候选兼容风险，G2安全升级须回归，但不能归因到CF当前x86/ARM pin或宣称当前CF已经触发RISC-V故障。
- Rill SBOM release verification workflow查询未返回运行，当前新发布SBOM资格不能默认为PASS；此项在G2/G7补证。

## 9. Stable发布 GO / NO-GO 条件

### 9.1 必要门禁

GO只针对一个具体候选身份，不泛称整个项目稳定，必须同时满足：

1. V01/V02/S01/R01/R02/C01发布阻断关闭，before/after与最终SHA可核对。
2. 当前支持矩阵全部必要源码/Host/Legacy/RPC/Runtime/SDK/真实包/迁移/安全/preflight终态PASS；必要job缺失、failed、skipped均NO-GO。诊断manifest生成不算资格。
3. 真实package metadata与源authority一致，公开集合唯一；consumer用同run qualified Runtime bytes，或有完整独立重建资格，不能只写sameRelease。
4. T01/U01等P1处理完；T02/Y01/L01/L02/N01/N02/P01风险要完成复现裁决：无影响附反例证据，有缺陷最小修复。未知不写PASS。
5. 真实包管理器比较无正常升级倒退，配置/state/owner/备份保留；恢复不覆盖外部修改；不新增不必要root/命令权限。
6. 新鲜安全扫描无未处理命中；不可达feature只是风险证据，不能永久ignore。有限临时例外必须受影响构建、feature门禁、负责人、失效条件明确，默认修复关闭。
7. 源码、CI/evidence、tag、raw package metadata、Runtime source/package/binary、checksum、渠道一致；artifact过期或不能回读则OPEN待补。
8. 真机/soak按独立政策裁决，软件全绿不自动替代。

### 9.2 风险豁免政策

P0（身份矛盾、不可追溯资产、安全准入未处理、必要CI失败）不接受删断言、降低校验、永久ignore豁免。P1只允许明确隔离/默认关闭/影响受控的具体书面例外，注明边界、验证、期限/退出方案；真实状态仍FAIL/NOT RUN，不改PASS。P2/P3可后移，不能用追求全面引入新算法/框架。

设备缺位不阻断G1–G5及软件资格。默认真实设备门禁保持OPEN、整体Stable NO-GO，直到最小真机验证完成，或用户针对这次具体候选明确接受“软件资格完成、真机未验证”的有限风险。旧72h/7d豁免仍记SKIPPED，但不自动批准新24h或新候选真机。豁免不改变证据事实。

### 9.3 发布失败撤回与恢复

- 发布前不匹配立即停，不创建/覆盖tag/bytes；保失败证据。
- 未来若发布中途失败，停止推荐/标记撤回说明；不篡改已公开bytes/tag，不用新包替同名资产。若平台draft处理被采用，需批准策略并记录已曝光资产；修复使用新身份。
- 安装后失败停止自动写/cron，保preimage/journal/live指纹。仅live仍匹配本事务owned-after时自动恢复；冲突给diff，不盲import旧UCI/YAML。
- Runtime故障Native fallback、隔离坏state/旧feedback；回退binary先核对handler/schema/state，必要时只停辅助，不删除历史。
- 显式降级是独立恢复，不是正常升级；备份配置/state，验证包管理器降级/owner冲突，禁止force-overwrite。

## 10. 需要用户决策的少量事项

这些不阻挡下一轮G1，不把常规实现细节转成反复确认：

1. **Stable可选Preview的产品定位。** 默认Native始终可用、Rill默认关闭、精确锁定显式Preview v3并披露渠道，不强改上游稳定承诺。若要求Stable完全不提供Preview入口，需单独兼容迁移/体验调整。
2. **本次设备风险边界。** 默认先做G6最小非生产设备验证再整体GO；无设备继续软件验收。是否授权真机/新24h或接受具体候选有限发布风险，等RC和可审方案准备后决定；旧72h/7d仍SKIPPED。
3. **OpenWrt patch支持范围。** 默认保留四SDK兼容验证，公开代表资产选择显式化，不扩大未验证CPU；淘汰旧patch须基于真实metadata/升级结果，不以去硬编码为由删除支持。
4. **来源不明CFST缓存兼容。** 默认保已安装可运行binary，但不将缺可信metadata的归档当来源已认证last-good执行；缺可信digest且无binary给可操作错误。若要离线旧归档执行须显式信任来源，不静默放行。

最终版本在G7按真实发布序列/改动性质/包管理器排序决定，不此刻写死数字，不倒退、不重写历史tag。

## 11. 下一轮第一阶段开发提示词草案

**下段仅为未来执行文本，本轮没有运行。只做G0轻量复核+G1，完成验收后停止。**

~~~text
在 /Users/yunshu/Documents/GitHub/luci-app-cloudflare-ip 执行
plans/stable-cross-repo-remediation-plan.md 的 G0 基线刷新与 G1。

目标：统一产品版本/真实IPK与APK身份/资格校验数据流，消除当前版本断言漂移，
保留不可变历史fixtures与Rill migration字段。本轮不是修所有Runtime/事务/UI问题。

先重读适用AGENTS和计划，记录完整HEAD/branch/status/remote。
计划基线75f5a2d11c13c5d9aa46dfb8159259b2c94c73c5若已变化，逐条确认
V01/V02/V03/V04/S01是否仍存在；保用户修改，不reset/clean。

先构造before：
- 原package-release-bump-contract失败；
- 真实IPK -rN metadata对旧validator失败；
- 真实sync函数用内存mock复现packageMigration丢失；
- 记录既有byte-binding/qualification篡改负向，修复后必须继续拒绝。

编辑前列出精确allowlist与小型接口设计：
1. Makefile PKG_VERSION/PKG_RELEASE保持权威，channel单管渠道；新增唯一identity
   reader/CLI给workflow/validator/版本显示，不手填第二份当前版本。
2. 从真实IPK control/APK adbdump保留raw packageVersion，normalized身份与源比对；
   依据受支持SDK真实产物，不猜IPK一定-N，拒绝漂移和升级倒退。
3. asset tests使用同run真实包贯穿metadata与bytes；伪包仅做byte/path负向。
   保target namespace，拒绝旧包/extra/wrong arch/basename碰撞/hash替换。
4. 当前版本测试不固定数字；历史r2/r3 tag/SHA/hash作为具名fixtures保留。
   协议schema/model不随包版改，clientIdentity.version不在此阶段盲改。
5. sync field-aware变更/schema/写后check，保packageMigration及非owned扩展字段；
   测no-op/update/repeat/错资格/未来版本；不实际写远端pin或开PR。
6. UI/RPC只改版本身份派生、双语下载/发布模板，不扩交互/事务修复。

真实APK工具/SDK unavailable时先用隔离Linux可审工具补验，否则留OPEN；
伪包/旧报告不算当前PASS。不得删除失败测试或降低校验换绿。

执行：diff审查→原失败/修复验证→独立故障反例→相关测试→跨仓库只读兼容→证据。
报告完整SHA/dirty、变更原因、命令/退出码、真实包来源/run/attempt/hash和未跑项。
不要先切Stable渠道、不任意决定最终版本、不改其他仓库；不push、创建PR、tag、
Release、远程dispatch或安装路由器。完成G1给阶段GO/NO-GO后停止，不自动G2–G7。
~~~

---

交付自检：11个规定章节；四类证据和P0/P1/P2/P3；精确多仓基线/真实包/CI索引；分层版本来源和不可变pins；各阶段责任/具体文件/依赖/设计/反例/测试/验收/回退；Host、SDK、Runtime、浏览器、真机、Soak与Release分开；未来提示词未执行。下一轮需刷新本文的时效性事实。

