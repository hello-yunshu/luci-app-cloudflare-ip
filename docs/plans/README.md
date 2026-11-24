# 文档索引

计划、契约与审计现在只有一处根：`docs/plans/`（计划与契约）与 `docs/audits/`、`docs/archive/audits/`（审计与证据）。仓库根不再保留 `plans/` 与 `AUDIT_*` 目录。

CI 直接校验 `docs/plans/rill/drift-decision.json`，legacy 测试读取 `docs/plans/transaction/PASSWALL-OWNERSHIP.md`；移动这些文件时必须同步修改 `.github/workflows/ci.yml` 与 `tests/legacy/passwall-target-removal.sh`。

## 现行计划与契约

| 路径 | 说明 |
|---|---|
| `docs/plans/release/RELEASE-GATES.md` | 发布门禁与晋级条件 |
| `docs/plans/release/OPENWRT-BUILD-MATRIX.md` | 支持的 OpenWrt 版本 × 架构矩阵 |
| `docs/plans/release/QUALIFICATION-EVIDENCE.md` | 资格证据清单（旧版本条目已标注） |
| `docs/plans/transaction/HOST-TRANSACTION.md` | 主机侧变更事务与回滚契约 |
| `docs/plans/transaction/PASSWALL-OWNERSHIP.md` | PassWall 目标域归属规则（legacy 测试依赖） |
| `docs/plans/transaction/OPENCLASH-INTENDED-MAPPING.md` | OpenClash 预期映射 |
| `docs/plans/sources/SOURCE-REGISTRY.md` | 候选源注册表 |
| `docs/plans/sources/SOURCE-PARSER-CONTRACT.md` | 源解析输出契约 |
| `docs/plans/sources/CANDIDATE-SCHEDULER.md` | 候选调度策略 |
| `docs/plans/sources/SOURCE-SECURITY.md` | 源与输入的安全边界 |
| `docs/plans/rill/drift-decision.json` | Rill upstream drift 决策（CI 校验） |

## 长期契约（兼容性基线，仍约束实现）

`docs/plans/compatibility/` 保存 1.8.3 → 2.x 的特性保留与兼容性契约。它们不是待办计划；改动对应行为时必须同步更新契约。

- `docs/plans/compatibility/RPC-COMPATIBILITY-CONTRACT.md`
- `docs/plans/compatibility/UCI-MIGRATION-CONTRACT.md`
- `docs/plans/compatibility/STATE-PERSISTENCE-CONTRACT.md`
- `docs/plans/compatibility/SERVICE-LIFECYCLE-CONTRACT.md`
- `docs/plans/compatibility/LUCI-COMPATIBILITY-CONTRACT.md`
- `docs/plans/compatibility/1.8.3-FEATURE-INVENTORY.md`
- `docs/plans/compatibility/2.0-FEATURE-PRESERVATION-MATRIX.md`
- `docs/plans/compatibility/REMOVAL-DECISIONS.md`
- `docs/plans/compatibility/TEST-EVIDENCE-MATRIX.md`

## 归档（已完成 / 已被取代）

`docs/plans/archive/` 只放不再执行、仅作历史依据的文档：

- `next-release-remediation-plan.md`：v2.6.0 前审计修复计划（阶段 A–F 已执行）。
- `00-CLEAN-REBUILD-CHARTER.md`：**已明确被 2.1 Candidate-only 架构取代**。
- `01-BASELINE-AUDIT.md`、`02-ARCHITECTURE.md`、`03-IMPLEMENTATION-PLAN.md`、`04-VALIDATION-PLAN.md`、`05-RISK-REGISTER.md`、`06-AURORA-UI-AUDIT.md`：2.0 clean-rebuild 时期记录。
- `2.2/`、`2.3/`：对应版本的特性契约与路线图。
- `g1-version-artifact-contract-evidence.md`、`g4-g5-execution.md`、`g6-g7-execution.md`、`g6-g7-handoff-20261024.md`：G1–G7 验收执行记录。
- `stable-cross-repo-remediation-plan.md`：2.x Stable 跨仓修复计划（历史审计结论）。
- `docs/archive/audits/AUDIT_2026-10-05/`：2026-10-05 审计包（16 个文件，含证据与脚本）。

## 相关文档

- 当前 Runtime 契约见仓库根 `contracts/rill-runtime.json` 与 `docs/RUNTIME_COMPATIBILITY.md`。
- Rill 1.5.3 / 2.1.1 时期记录已随归档，现行接入要求以 `docs/RUNTIME_COMPATIBILITY.md` 为准。
