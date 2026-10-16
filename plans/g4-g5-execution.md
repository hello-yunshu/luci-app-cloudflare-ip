# G4、G5 执行记录

基线：CF `cb06c61bc09ec2dbb98e249d46c212e2d80238bd`，G3 十二包资格 run 38928695476 attempt 1 不变。工作分支 `codex/reliability-contracts`。当前未完成 G4/G5，不具备新的 Stable 资格。保留旧分支、已发布资产、用户配置及既有 G3 证据。

## 完成定义

以 `stable-cross-repo-remediation-plan.md` 的 G4a–d、G5a–e 及逐阶段 DoD 为完整范围。G4 必须覆盖 Host/Legacy、真实 SDK/两格式迁移、统一 Release predicate、同 bytes 的离线 preflight；G5 必须覆盖事务、真实 LuCI 八视图交互、来源/CFST、LAN generation 与重绑定、生命周期/RPC。UI/HTTP/运行/包/设备证据分别记录，未执行不得视为 PASS。

## 当前证据

- G4a/C01：原后缀测试因缺少 OpenClash UCI 状态 fixture 失败。只修改该 fixture，模拟显式禁用且无 core 的服务；保留真实 pre-write guard。增加未知状态、enable 外部改变、core 外部启动三个拒绝反例，逐一比对配置未改变。25 个 Legacy 组脚本本地通过，ShellCheck error 级与 diff 检查通过；最终 exact-SHA 远程资格仍 OPEN。
- G5a/T01：新回归用例复现两类失败：transform 写后失败留下新 live 内容且恢复冲突；written snapshot 复制失败留下 MUTATED 与 applyActive=true。修复前日志已保存，不降低断言。尚未修改生产事务代码。

## 未完成项

G4b/c/d、G5a 修复及完整故障矩阵、G5b 浏览器和 UCI readback、G5c 网络与二进制更新、G5d 真实 HTTP/地址变化、G5e 生命周期/RPC，以及整合提交的远程 CI 都保持 OPEN。真实设备/持续运行属于后续 G6，未授权不写设备。合并、tag、Release/feed 发布不执行。

证据见 `docs/audits/g4-g5-evidence/initial-evidence-index.json`。
