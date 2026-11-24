# 文档索引

CFI 的计划与契约目前分两处，原因是 CI 仍直接引用仓库根的 `plans/` 路径：

- `plans/`：计划、兼容性契约与发布门禁（CI 校验 `plans/rill/drift-decision.json`，legacy 测试读取 `plans/transaction/PASSWALL-OWNERSHIP.md`）。**下次版本变更时并入 `docs/plans/`**，届时同步修改 `.github/workflows/ci.yml`、`tests/legacy/passwall-target-removal.sh` 与 `release.yml` 的 docs-only 分类。
- `docs/plans/`：文档侧计划与归档。

## 现行计划与契约（`plans/`）

| 路径 | 说明 |
|---|---|
| `plans/release/RELEASE-GATES.md` | 发布门禁与晋级条件 |
| `plans/release/OPENWRT-BUILD-MATRIX.md` | 支持的 OpenWrt 版本 × 架构矩阵 |
| `plans/release/QUALIFICATION-EVIDENCE.md` | 资格证据清单（旧版本条目已标注） |
| `plans/transaction/HOST-TRANSACTION.md` | 主机侧变更事务与回滚契约 |
| `plans/transaction/PASSWALL-OWNERSHIP.md` | PassWall 目标域归属规则（legacy 测试依赖） |
| `plans/transaction/OPENCLASH-INTENDED-MAPPING.md` | OpenClash 预期映射 |
| `plans/sources/SOURCE-REGISTRY.md` | 候选源注册表 |
| `plans/sources/SOURCE-PARSER-CONTRACT.md` | 源解析输出契约 |
| `plans/sources/CANDIDATE-SCHEDULER.md` | 候选调度策略 |
| `plans/sources/SOURCE-SECURITY.md` | 源与输入的安全边界 |
| `plans/rill/drift-decision.json` | Rill upstream drift 决策（CI 校验） |

## 长期契约（兼容性基线，仍约束实现）

`plans/compatibility/` 保存 1.8.3 → 2.x 的特性保留与兼容性契约。它们不是待办计划；改动对应行为时必须同步更新契约。

- `plans/compatibility/RPC-COMPATIBILITY-CONTRACT.md`
- `plans/compatibility/UCI-MIGRATION-CONTRACT.md`
- `plans/compatibility/STATE-PERSISTENCE-CONTRACT.md`
- `plans/compatibility/SERVICE-LIFECYCLE-CONTRACT.md`
- `plans/compatibility/LUCI-COMPATIBILITY-CONTRACT.md`
- `plans/compatibility/1.8.3-FEATURE-INVENTORY.md`
- `plans/compatibility/2.0-FEATURE-PRESERVATION-MATRIX.md`
- `plans/compatibility/REMOVAL-DECISIONS.md`
- `plans/compatibility/TEST-EVIDENCE-MATRIX.md`

## 归档（已完成 / 已被取代）

`plans/` 内的历史文档仍保留在原分组，按标题中的状态提示判断；`docs/plans/archive/` 存放文档侧已完成计划。

- `plans/00-CLEAN-REBUILD-CHARTER.md`：**已明确被 2.1 Candidate-only 架构取代**。
- `plans/01-BASELINE-AUDIT.md`、`plans/02-ARCHITECTURE.md`、`plans/03-IMPLEMENTATION-PLAN.md`、`plans/04-VALIDATION-PLAN.md`、`plans/05-RISK-REGISTER.md`、`plans/06-AURORA-UI-AUDIT.md`：2.0 clean-rebuild 时期记录。
- `plans/2.2/`、`plans/2.3/`：对应版本的特性契约与路线图。
- `plans/g1-version-artifact-contract-evidence.md`、`plans/g4-g5-execution.md`、`plans/g6-g7-execution.md`、`plans/g6-g7-handoff-20261024.md`：G1–G7 验收执行记录。
- `plans/stable-cross-repo-remediation-plan.md`：2.x Stable 跨仓修复计划（历史审计结论）。
- `plans/rill/RILL-1.5.3-INTEGRATION.md`、`plans/rill/RILL-QUALIFICATION.md`：Rill 1.5.3 / 2.1.1 时期记录；当前 Runtime 契约见仓库根 `contracts/rill-runtime.json` 与 `docs/RUNTIME_COMPATIBILITY.md`。
- `docs/plans/archive/next-release-remediation-plan.md`：v2.6.0 前审计修复计划（阶段 A–F 已执行）。

## 待随下个版本执行

- 根目录 `AUDIT_2026-10-05/` 迁入 `docs/archive/audits/`，并同时把根 `plans/` 并入 `docs/plans/`。两项都是非 `docs/*` 路径变更，会触发 `release.yml` 的发布晋级；必须在版本号变更时一并完成，避免用旧版本号重发。
