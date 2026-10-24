# G6 RC 验收与 G7 Stable 晋级准备

原范围以 stable-cross-repo-remediation-plan.md G6/G7、§8、§9 为准。当前整体 OPEN / Stable NO-GO。早前维护测试已回退原状态；用户随后明确推迟所有实机与Soak，直至再次明确通知。上游安全修复与重新资格已另获授权。备份和敏感现场只留本机受限证据目录，不提交仓库。最新状态和跨电脑继续入口见 plans/g6-g7-handoff-20261024.md。

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
