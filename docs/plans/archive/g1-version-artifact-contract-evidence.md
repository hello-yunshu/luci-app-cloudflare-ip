# G0＋G1 版本与产物合同实施证据

日期：2026-10-15（Asia/Shanghai）。

结论：**G0 与 G1 的本地实施和验收完成；可进入下一轮 G2。整体 Stable 仍 NO-GO。**
本轮未提交 commit、push、创建 PR/tag/Release、触发远端 workflow、修改其他仓库、安装路由器或写真实代理配置。现有 Makefile 版本/release、release-channel.json、Runtime pin 和历史迁移资料保持不变。

## 1. 基线与范围冻结

|仓库|本地完整 SHA|远端 main（本轮重新读取）|初始/结束状态|
|---|---|---|---|
|luci-app-cloudflare-ip|75f5a2d11c13c5d9aa46dfb8159259b2c94c73c5|相同|初始仅已有规划文档未跟踪；结束为本阶段修改|
|rill-ml|da8389fec7f879b826d8d17cbc6bb98c03ef8462|9602750202f56ed860fc8815bb91e81083d0ffdb|保持本地Preview检出；干净|
|rill-openwrt-packages|64ee22f978ed8f8ed19bb675700678f57eec19e3|相同|干净|
|luci-app-performance-manager|09e5f0f3fd3f18b4eaa153896a6b76895d9a78b5|d5c42e1867d34ea1aa3013485e713504bd9163aa|保留未合并分支；干净|

适用技能 luci-multilayer-runtime-auditor 与既有计划用于限制边界。没有创建新 worktree、强制重置、清理用户文件或合并其他分支。

G0 再复现：

- 原 package-release-bump-contract.sh：exit1，release5 对固定4。
- 原 rill-package-layout-contract.sh：exit1，另一个隐藏的固定release4。
- 从 git show HEAD 载入原 qualification validator，输入本轮下载的真实SDK包metadata：拒绝 packageVersion does not match version/release。
- 从 git show HEAD 载入原 sync，mock网络、内存捕获写出：丢 packageMigration。
- 原 regex-ip-suffix.sh 仍exit1，不能读OpenClash enable；这是G4 fixture问题，没有在本阶段改变生产guard。
- G5问题保持可复现：Node VM非ready/error状态超时仍resolve；隔离transaction written-snapshot故障返回apply14/rollback1/current=new/rolledBack=false。没有写真实UCI/YAML。

原source-run资格没有被改写：[CI38070244923](https://github.com/hello-yunshu/luci-app-cloudflare-ip/actions/runs/38070244923) @上述CF SHA，原结果FAILURE。本轮artifact下载前再次读取run.head_sha并核对，四份artifact均可下载，不存在过期假设。旧计划中的其他PR/上游门禁由其原索引定位，没有新提交证据支持改变原审计结论。

## 2. 实施合同与修改清单

具体技术合同见 [PACKAGE-IDENTITY-CONTRACT.md](../docs/PACKAGE-IDENTITY-CONTRACT.md)。

- scripts/package_identity.py：唯一源身份读取、合法版本/release/channel、tag、raw/normalized格式合同、target registry、既有开发APK映射、真实包管理器升级比较。
- contracts/package-artifacts.json：原四个SDK目标及每种格式一个公开代表；无支持范围删减。
- scripts/openwrt-package-metadata.py：真实IPK/APK提取；拒绝重复control/身份、symlink、读取时文件变更；支持source authority比对。
- 两个qualification/release validator共享同一metadata/filename规则；release additionally重读真实包metadata、size/hash，拒绝额外/嵌套/符号链接包。
- scripts/check-package-assets.py：检查完整SDK target集合、真正包内容、sidecar精确一致及公开目录checksums。
- scripts/apk-metadata.sh：真实apk工具；无native工具时只读Docker适配，没有mock降级。
- CI用registry派生matrix/public artifact选择，以真实SDK产物替代touch空包；Release使用identity reader和证据中准确文件名，不手造下载名称。原Stable显式门禁保留。
- Makefile统一替换所有版本模板，失败立即退出；CLI/RPC兼容保留base version并增加package_version，状态增加package_version，footer/CSS缓存含package release。协议engine/API/schema/model代数未改。
- check_rill_dependency.py保留顶层和嵌套扩展/migration，拒绝未知schema，校验release/recipe与run字段，写入前与序列化后自检，原子替换并保权限，no-op不改原字节。没有实际运行工作区--sync。
- 当前版本测试改为动态authority；historical r2/r3及SHA/hash保留。双语README引用source authority和选定Release资格清单，不把源码候选误称已发布。
- 新测试区分synthetic byte/path fixtures与真实SDK/真实apk覆盖，保留原篡改断言，并新增读内部metadata的反例。

allowlist扩展仅涉及发现的同类当前版本断言：rill-package-layout、OpenClash guard内的release检查、legacy package-conffiles开发映射检查、evidence-manifest-default的当前依赖digest检查；原业务/恢复/权限断言未移除。

## 3. 真实产物链

来源：CF run38070244923 / attempt1 / source SHA75f5a2d11c13c5d9aa46dfb8159259b2c94c73c5。下面为原SDK实际产物，不是本轮新源码重建。用于修复后包合同回归，不能宣称本轮新SHA已资格化。

|SDK artifact|ID|下载ZIP SHA-256|
|---|---|---|
|ipk-v24.10.5|11676179753|70889d1c67bfc0c2b2cac5d9ed9632708131aacbb8aac2e599a161fe6b55a7b3|
|ipk-v24.10.8|11675979668|16cff1b848e67f32cfe11e005180f3c2aff3240caf0ca47600070378ffefe768|
|apk-v25.12.0|11676284203|1e7b3081102f42c3d16f07d6a4cbc36606814e9fb3d43ac41d70180c6b3eaa93|
|apk-v25.12.5|11676837633|b92960a8be3e56a7e7c09d82fa2a140c55fb47109626cf77ef084a035ce43a22|

真实IPK读取control；真实APK使用apk-tools3.0.8-r0的adbdump。Docker tool image alpine:3.23，已用digest sha256:85fe1e81d6758c208f3e1eed4338a1997e19d4be002d4dd32d3100c9a8c010a0。包没有安装或执行脚本。

### 实际主包metadata


|Target / file|Raw version / architecture|Size|Package SHA-256|
|---|---|---|---|
|luci-app-cloudflare-ip-ipk-v24.10.5/luci-app-cloudflare-ip_2.6.0-r5_all.ipk|2.6.0-r5 / all|141758|4fa8a5eb625afdfb460a1927452476beeaafa348ffa33d4d8b5c63159dbeb70f|
|luci-app-cloudflare-ip-apk-v25.12.0/luci-app-cloudflare-ip-2.6.0-r5.apk|2.6.0-r5 / noarch|141870|85c3c04db5c5af599ab70d9c04a74dd3bcb43f1b3f4909492e83b0cfb30d1915|
|luci-app-cloudflare-ip-ipk-v24.10.8/luci-app-cloudflare-ip_2.6.0-r5_all.ipk|2.6.0-r5 / all|141753|a388b0ab6e647400bc911132ea277ed5bd46c9f56f7d6e559fea1a52ac549feb|
|luci-app-cloudflare-ip-apk-v25.12.5/luci-app-cloudflare-ip-2.6.0-r5.apk|2.6.0-r5 / noarch|141869|e611fc45ee26fb8134149c3b57946cc59cde3deee394fb5f8d7f7893ef6f4242|

## 4. 验收结果

|门禁|结果和真实性|
|---|---|
|20份focused shell contracts|PASS local，包括版本、渠道、下载、byte binding、qualification negatives、metadata、布局/owner、base integration、installed routing、manifest、LuCI staged/RPC、v2 status和tag不变性|
|7组Python合同测试|PASS local；未来多版本/多位release、非法版本/release、raw格式、重复metadata、target、sync/no-op/未知schema/失败资格/atomic-write fault|
|真实Make宏双重展开|PASS local GNU Make；只变临时副本authority为未来版本，验证所有模板无残留、CLI/RPC真实执行返回正确package_version、协议代数保留，缺模板构建失败；macOS仅sed -i接口做BSD适配|
|37项包syntax/JS/JSON与Python AST|PASS local|
|actionlint / ShellCheck error / git diff --check|PASS local|
|OpenClash guard完整focused合同|PASS local mock，所有服务健康/disabled/恢复/URL迁移断言保留，只有版本断言改为authority|
|四SDK实际包回读和sidecar|PASS real IPK control / Linux real APK adbdump|
|真实包全链正/负向|PASS；生产validator未mock，拒绝版本/架构/release、内部metadata伪造、字节替换、额外包、嵌套重复、symlink、重复checksum|
|真实包管理器排序|PASS；opkg/apk历史r3→源码候选接受，同版及降级拒绝|
|额外Linux Make容器重跑|BLOCKED环境：Alpine包镜像下载I/O失败，终止了确认属于本任务的容器；不标PASS，不影响已完成本机GNU Make语义/真实包工具门禁|
|新源码完整SDK重建 / exact-SHA hosted CI|NOT RUN；没有push或dispatch|
|浏览器 / rootfs完整安装迁移 / 真机 / Release|NOT RUN；G4–G7独立门禁|
|72h/7d soak|仍SKIPPED（历史用户批准），未转换为PASS|

升级排序用OpenWrt24.10.8官方rootfs内的真实opkg。rootfs下载时比对同目录官方sha256sums，SHA-256为6c94190246a54088e3984fc0c4cbbb518972abb2b10a28e30a0c41554eea8b9d。启动隔离容器仅创建其临时/var/lock并调用compare-versions，网络关闭；未安装包。严格操作符为 >>，不是接受相等版本的单个 >。APK使用实际version -t。

真实包回归中的qualification manifest是明确标记的测试输入；Runtime资格/迁移的辅助字段由原pin生成，不代表本轮重跑了这些门禁；原run的releaseEligible=false仍成立。

### 复跑入口

    PYTHONDONTWRITEBYTECODE=1 bash tests/package-release-bump-contract.sh
    PYTHONDONTWRITEBYTECODE=1 bash tests/release-asset-binding.sh
    PYTHONDONTWRITEBYTECODE=1 bash tests/qualification-evidence-validator.sh
    PYTHONDONTWRITEBYTECODE=1 python3 -B tests/real-package-identity.py SDK_ARTIFACT_DIRECTORY
    PYTHONDONTWRITEBYTECODE=1 python3 -B scripts/check-package-assets.py SDK_ARTIFACT_DIRECTORY
    python3 -B scripts/package_identity.py --upgrade-from INSTALLED_RAW_VERSION --format ipk --manager REAL_OPKG
    python3 -B scripts/package_identity.py --upgrade-from INSTALLED_RAW_VERSION --format apk --manager REAL_APK

下载SDK_ARTIFACT_DIRECTORY时使用上表同run和artifact名称，各artifact保留独立子目录，切勿平铺同名包。临时原始日志、下载包、官方rootfs与排序shim保留于 /tmp/cfip-g1.LwmRcb；该路径是本轮原始证据缓存，不是发布资产或长期唯一索引，本报告保留必要命令、来源与hash。

## 5. 关闭项与不越界项

|问题|本阶段结论|
|---|---|
|V01|关闭local：两项release4与一项release5当前版本固定断言改为动态authority|
|V02|关闭local：真实IPK/APK共享metadata规则贯穿两validator，原真实包拒绝已转为接受|
|V03|关闭local：空伪包CI被真实SDK集合检查替代；synthetic仅隔离byte/path单测|
|V04|关闭source/build层：文档无重复当前版本，footer/CLI/RPC/status含package release；真实浏览器另验|
|S01|关闭local：字段保留、no-op、无资格/非法schema与写失败保原文件测试通过|
|G2 Rill安全|OPEN，未改上游Cargo/锁文件|
|G3 Runtime同bytes/自动sync workflow|OPEN，未改pin或git作者/token/base/PR自动化|
|G4 Legacy fixture/迁移schema/资格整体|OPEN；regex-ip-suffix仍失败；没有删除失败用例、抑制错误或称整体CI绿|
|G5事务/timeout/readback/LAN|OPEN，原风险再次复现，未随版本工作偷偷修复|
|G6/G7真机/RC/Stable|OPEN；不触发发布|

失败回退为按下方明确文件清单撤销本阶段修改或对应未来独立commit；不得reset --hard/clean用户工作区。保留已有规划文档、其他仓库与Runtime pins、历史tag/assets/fixtures。若需回退atomic sync，仅使用允许字段差异与原contract，不覆盖用户扩展字段。

## 6. 完成审计与工作树身份

逐条对照原计划G0/G1：基线/失败前证据/可访问artifact；单一authority/动态matrix及资产名；真实包与metadata合同；篡改仍拒绝；未来单点版本/invalid/downgrade测试；migration/未知字段保留与写后自检；构建/CLI/RPC/footer派生；历史fixture/协议代数不变；阶段相关回归/静态检查；其他仓库干净；未跑门禁明确。均有上方证据。本地阶段GO不等于Stable GO。

当前没有新commit，因此不冒称验证了不存在的新SHA。以下是最终实施文件内容的SHA-256快照（不包含本报告自引用，也不包含本轮之前已存在的规划文档）。后续任何实现文件改变都需重跑受影响验证。

|File|SHA-256|
|---|---|
|.github/workflows/ci.yml|387facaae01f3fd0b21e0a4879f74874f6ee3cbe849e2e3971f05156974978d7|
|.github/workflows/release.yml|b6a2a5d8ce6929e454071544991a1c1bbe14b2d42dfa0eb261808d5040c8648d|
|README.en.md|79a36362f794d06929069e8748cbd94ca74194ddc8b365437b44378ce8000392|
|README.md|410626825c6786313547b2f601d08afbfe3b7810ef0dde762f2b55e2c40cd4c7|
|contracts/package-artifacts.json|8d38332365d3e586184467f55b7466f7f9c278e8afbcc5252acdf890ee325221|
|docs/PACKAGE-IDENTITY-CONTRACT.md|286f8a2bfcea91a80315209827be898aacc06c746b65da724e135527118544be|
|package/luci-app-cloudflare-ip/Makefile|f98f020571ff025bccb6db4c86d4189d096ef524ea8ed3bac4d74ff819beffff|
|package/luci-app-cloudflare-ip/htdocs/luci-static/resources/cloudflare-ip/utils.js|60fc05487047163bd95a811e32fb5d99121d589f3bb89f232a67cd05468bfcd2|
|package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2|3f4b51f4d2378da7d0fa7c07f3713797445f8315f31b071331276a68cbc05243|
|package/luci-app-cloudflare-ip/root/usr/libexec/rpcd/cf_ip|39e9fde5bcaf4e53cb73d2c65b27428f47527bdc957aec4b72dd501f11919488|
|scripts/apk-metadata.sh|51444564e18ef8d08a283e719d542466f09debad3e8e2ab595358222e784c0e6|
|scripts/check-package-assets.py|70bf5bb362e2fccb59d144b0bc437d0a1c4402d7d106a767f808709a2657d8ff|
|scripts/check_rill_dependency.py|1b37039a6232a51a878f176b2bc6334f1b4794ce30d9380088613227385f8b38|
|scripts/openwrt-package-metadata.py|3ff3ba7f4919bded3bcc6b985fc3b8ed964c4a8a538afa5e59a8f0147ec80aae|
|scripts/package_identity.py|50483bdeb2c8f0e929926209a9d2f55d5da1fd3f001199fbe543d38d0547217c|
|scripts/validate-qualification-evidence.py|2dbbdd40c614234e124aad43daa88fa127f262d8330c2b191a9ab38911c99a0f|
|scripts/validate-release-assets.py|9641a3cb92bad44eb43313fe3367d07845dba119754e9bedd2536f3ec2adb28e|
|tests/evidence-manifest-default.sh|5b2577f363cf01aa9d42a00d8d8300e3d5d562102ec3d0eb16f24409386d342b|
|tests/legacy/package-conffiles.sh|9a383f76311f5d0e77565f110dfc2541525a8bc44f6cf62017d43946a21bad40|
|tests/openclash-service-guard.sh|5d4574256d70b05c807a69d0096e533b0f31f1bbae0c3fefc07d20652cf7c82c|
|tests/openwrt-package-metadata.sh|015bb04ad15ad8b300689cd6b97c94b4db4b468f52885d8d25c32af7d75d1aec|
|tests/package-identity-contract.py|aef9ba140f66fa4e3d9d1dc21b3e3bee019eda5d14cfd79617e17a60e03b37c2|
|tests/package-release-bump-contract.sh|435ac29fa2173ab6a0a67a912821e87f9288592be7f942dddb8f3a9bcb6c70e1|
|tests/package_contract_fixtures.py|c859a9d5e8d7074ac6f8a44f07141ed6066972848ca6d624cce24604c2915561|
|tests/qualification-evidence-validator.sh|dbbf44b45555f2c83adfbdcc842d3107dee1f85cba7077ca8743d839d5aff413|
|tests/real-package-identity.py|c532cc22cd268237b857001c1ce9827d402c0da03d42b3a41be8d578ea23eeec|
|tests/release-asset-binding.sh|83b4f4adb6ec8c30db7fde166150e9ee1b6b822c9d99c9e0fb6977bca73ee903|
|tests/release-asset-contract.sh|b2d9ebb127f78c95d4283d5ab750d78f916546d8bede09e9f29587c7ef613eef|
|tests/release-channel-contract.sh|7beae30a1c17afb349943bfb3f6f630cbb5c161544e954f1ade8ecc1ceb8166d|
|tests/release-download-contract.sh|03d08a9e588c79ccb895d6e4fbc5cd1e3d6a14c173cecb7a61bccbe0eca00ce4|
|tests/rill-package-layout-contract.sh|04fedc2318205e230cd1dff289763dc41af53e69a38969d2f0dca317c0cc931d|
