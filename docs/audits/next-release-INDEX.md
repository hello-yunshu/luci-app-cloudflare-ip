# Next-release audit index

当前代码候选：`audit/ui-skill-review` / `ffa73f6`（PR #25）；版本口径 `2.6.0-r8`。docs 随 PR #25 提交（docs-only commit 位于 `ffa73f6` 之后）。未合并、未打 tag、未建 Release、未改 release-channel。

入口：主仓库 [README](../../README.md) 的“相关文档”已链接本索引。

## 文档

| 文档 | 用途 |
|---|---|
| [next-release-full-audit.md](next-release-full-audit.md) | 阶段 A 综合审计（2e28db4 基线，保留历史复现） |
| [next-release-issue-register.md](next-release-issue-register.md) | P0–P3 问题矩阵；P0/P1 已更新为 CLOSED/FIXED 或 PASS-BY-USER-DECISION |
| [next-release-interaction-matrix.md](next-release-interaction-matrix.md) | 43 点旧矩阵；当前 51 点七态矩阵见 `next-release-evidence/phase-f/matrix/matrix.json` |
| [next-release-visual-matrix.md](next-release-visual-matrix.md) | 9adb2d5 视觉矩阵；当前缩放/中文证据见 `next-release-evidence/phase-f/zoom-zh/` |
| [next-release-i18n-report.md](next-release-i18n-report.md) | 阶段 A i18n 缺口；当前 516/552 门禁结果在文首 |
| [next-release-phase-f-report.md](next-release-phase-f-report.md) | 本轮：七态矩阵、docs 归位、真实缩放、zh 渲染、门禁漂移 |
| [next-release-phase-e-report.md](next-release-phase-e-report.md) | 阶段 E：发布前 6 条 |
| [next-release-phase-b-report.md](next-release-phase-b-report.md) … [next-release-phase-d-report.md](next-release-phase-d-report.md) | 阶段 B–D 执行报告 |
| [../plans/next-release-remediation-plan.md](../plans/next-release-remediation-plan.md) | 阶段 A 修复计划与 GO/NO-GO 条件 |

## 证据

| 路径 | 内容 |
|---|---|
| `next-release-evidence/phase-f/matrix/` | 51 点 × 7 态矩阵 JSON（states / assertions / evidenceIndex / consoleErrors / environment）与逐状态 BEFORE/AFTER 截图 |
| `next-release-evidence/phase-f/zoom-zh/` | 真实 Chrome 125/150/200% 页面缩放、320 reflow、zh_cn 375/1280 截图与 `zoom-zh.json` |
| `next-release-evidence/phase-f/gate-inventory.tsv` | 254 个本地测试 → CI job / 排除理由逐行清单 |
| `next-release-evidence/phase-f/verify.json` | 证据校验结果与退出码 |
| `next-release-evidence/phase-e/` | raw error、动态状态码、Advanced 只读的 BEFORE/AFTER |
| `next-release-evidence/phase-d/` | 真实 OpenClash 控制器与恢复、测速弹窗、Intelligence |
| `next-release-evidence/visual-2e28db4/` | 阶段 A 78 张真实 LuCI 基线截图 |
| `next-release-evidence/i18n-2e28db4/`、`interactions-2e28db4/`、`repro-2e28db4/` | i18n 缺口、交互观测、4 项风险 harness |

## 存放决定

- **放在主仓库的 `docs/` 树内**，不另建独立 docs 仓库。理由：审计结论必须与代码 SHA、CI run、包哈希同仓绑定；评审时一次干净检出即可复核；docs 变更与代码变更走同一条 CI/PR 门禁。
- `cfip-docs-evidence` 是本仓库的 linked worktree（同一 `.git`，分支 `phase-b/next-release-fixes`），不是独立远端仓库。阶段 A–E 的大部分证据已随本 PR 复制回主仓库；仅三个体量较大的历史视觉归档保留在 worktree：`ui-refinement-7c13b1d/`（28 MB）、`ui-skill-audit/`（21 MB）、`visual-phase-b/` 与 `visual-phase-c/`（11.6 MB）。它们不是当前候选证据，当前候选的缩放/中文/矩阵证据全部在主仓库。
- 当前 PR #25 携带 7 份 docs、phase-f 全量证据、phase-d/e 关键证据与基线截图；README 与 `docs/audits/next-release-INDEX.md` 提供可点击入口。

## 门禁

- 本地门禁↔CI 一致性由 [tests/ci-test-inventory.py](../../../tests/ci-test-inventory.py) 在 CI `workflow-lint` job 执行：任何 `tests/` 下的 `.sh/.py/.cjs` 未接入 CI 且未登记排除理由，job 直接失败。
- 当前：254 files / 247 referenced / 7 documented script exclusions / 0 leftovers。
