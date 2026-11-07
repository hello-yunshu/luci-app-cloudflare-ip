# Next-release audit index

发布身份：`v2.6.0-8`（2026-11-04，Pre-release），tag → `4cbad4d2bb68315ed22b4c702effb78c1cd03ffb`；后续修复发布 `v2.6.0-9`（Pre-release，tag 目标以 Release 页面为准）。`release-channel.json` 仍为 `stable`，未做 Stable 晋级。审计文档写作 base 为 `ae4282f7f4c543a06693925a9d49098891d85df8`；阶段合并 SHA 见下表，后续只以 tag 固定发布身份。

## 最终合并 SHA

| 阶段 | SHA | 说明 |
|---|---|---|
| v2.6.0-8 发布 | `4cbad4d2bb68315ed22b4c702effb78c1cd03ffb` | tag `v2.6.0-8` 目标，不可变 |
| 阶段 I 清理 | `ae4282f7f4c543a06693925a9d49098891d85df8` | PR #27 merge |
| 阶段 J 自检 | `8257a3d2979cbc187cc0677fc61f81bde3ea0c04` | PR #29 merge，publisher/curl 修复 |
| 阶段 K（r9 收口） | 以 `v2.6.0-9` tag 为准 | 本索引所在合并的 SHA 不写死；发布后 tag 是唯一身份 |

合并前后的文档 SHA 差异不再代表代码漂移：证据仍绑定各自的 exact-SHA run，发布身份由 tag 固定。

入口：主仓库 [README](../../README.md) 的“相关文档”已链接本索引。

## 文档

| 文档 | 用途 |
|---|---|
| [next-release-full-audit.md](next-release-full-audit.md) | 阶段 A 综合审计（2e28db4 基线，保留历史复现） |
| [next-release-issue-register.md](next-release-issue-register.md) | P0–P3 问题矩阵；P0/P1 已更新为 CLOSED/FIXED 或 PASS-BY-USER-DECISION |
| [next-release-interaction-matrix.md](next-release-interaction-matrix.md) | 43 点旧矩阵；当前 51 点七态矩阵见 `next-release-evidence/phase-f/matrix/matrix.json` |
| [next-release-visual-matrix.md](next-release-visual-matrix.md) | 9adb2d5 视觉矩阵；当前缩放/中文证据见 `next-release-evidence/phase-f/zoom-zh/` |
| [next-release-i18n-report.md](next-release-i18n-report.md) | 阶段 A i18n 缺口；当前 516/552 门禁结果在文首 |
| [next-release-phase-f-report.md](next-release-phase-f-report.md) | 阶段 F：七态矩阵、docs 归位、真实缩放、zh 渲染、门禁漂移 |
| [next-release-phase-g-report.md](next-release-phase-g-report.md) | 阶段 G：发布收口准备与待授权清单 |
| [next-release-phase-i-report.md](next-release-phase-i-report.md) | 阶段 I：遗留清理、sync-rill 真实演练、Stable Gate 准备、发布后验证 |
| [next-release-post-release-validation-v2.6.0-8.md](next-release-post-release-validation-v2.6.0-8.md) | v2.6.0-8 发布后 IPK/APK 真实安装与升级验证 |
| [next-release-release-notes-v2.6.0-8.md](next-release-release-notes-v2.6.0-8.md) | v2.6.0-8 线上 Release 正文（已同步） |
| [next-release-release-notes-v2.6.0-9.md](next-release-release-notes-v2.6.0-9.md) | v2.6.0-9 Release 正文（P1-06 修复） |
| [../ROLLBACK_AND_RECOVERY.md](../ROLLBACK_AND_RECOVERY.md) | 升级失败/ENOSPC 的 opkg status 备份与恢复流程 |
| [../STABLE_GATE_ACTION.md](../STABLE_GATE_ACTION.md) | Stable Gate 一页执行/决策清单（NOT READY） |
| [next-release-sync-rill-adjudication.md](next-release-sync-rill-adjudication.md) | 跨仓 sync-rill 本地等价 vs 真实 PR 裁决材料（含真实演练结果） |
| [../STABLE_GATE.md](../STABLE_GATE.md) | Stable Gate 门槛、角色与评审流程 |
| [../RELEASE_CHANNEL_GUARD.md](../RELEASE_CHANNEL_GUARD.md) | stable guard 预期失败的解释与排查边界 |
| [next-release-phase-e-report.md](next-release-phase-e-report.md) | 阶段 E：发布前 6 条 |
| [next-release-phase-b-report.md](next-release-phase-b-report.md) … [next-release-phase-d-report.md](next-release-phase-d-report.md) | 阶段 B–D 执行报告 |
| [../plans/next-release-remediation-plan.md](../plans/next-release-remediation-plan.md) | 阶段 A 修复计划与 GO/NO-GO 条件 |
| [../2.6.0-r8-RELEASE-READY.md](../2.6.0-r8-RELEASE-READY.md) | r8 发布准备、资产与授权清单 |

## 证据

| 路径 | 内容 |
|---|---|
| `next-release-evidence/phase-f/matrix/` | 51 点 × 7 态矩阵 JSON（states / assertions / evidenceIndex / consoleErrors / environment）与逐状态 BEFORE/AFTER 截图 |
| `next-release-evidence/phase-f/zoom-zh/` | 真实 Chrome 125/150/200% 页面缩放、320 reflow、zh_cn 375/1280 截图与 `zoom-zh.json` |
| `next-release-evidence/phase-f/gate-inventory.tsv` | 254 个本地测试 → CI job / 排除理由逐行清单 |
| `next-release-evidence/phase-f/verify.json` | 证据校验结果与退出码 |
| `next-release-evidence/phase-i/publisher-fixture-rewrite.md` | publisher fixture 在真实 24.10.8 procd/uhttpd 中跑通的证据、curl 8.22.0 根因与 P1-06 修复 |
| `next-release-evidence/phase-i/stable-gate-drills.md` | rollback / ENOSPC / 断电容器演练的原始命令与结果（含 opkg status DB 损坏发现与恢复演练） |
| `next-release-evidence/phase-i/` | publisher 测试早期失败日志（已由上述重写取代结论） |
| `next-release-evidence/phase-e/` | raw error、动态状态码、Advanced 只读的 BEFORE/AFTER |
| `next-release-evidence/phase-d/` | 真实 OpenClash 控制器与恢复、测速弹窗、Intelligence |
| `next-release-evidence/visual-2e28db4/` | 阶段 A 78 张真实 LuCI 基线截图 |
| `next-release-evidence/i18n-2e28db4/`、`interactions-2e28db4/`、`repro-2e28db4/` | i18n 缺口、交互观测、4 项风险 harness |

## 存放决定

- **放在主仓库的 `docs/` 树内**，不另建独立 docs 仓库。理由：审计结论必须与代码 SHA、CI run、包哈希同仓绑定；评审时一次干净检出即可复核；docs 变更与代码变更走同一条 CI/PR 门禁。
- `cfip-docs-evidence` 是本仓库的 linked worktree（同一 `.git`，分支 `phase-b/next-release-fixes`），不是独立远端仓库。阶段 A–E 的大部分证据已复制回主仓库；仅四个体量较大的历史视觉归档保留在 worktree：`ui-refinement-7c13b1d/`（28 MB）、`ui-skill-audit/`（21 MB）、`visual-phase-b/`（5.6 MB）、`visual-phase-c/`（6.0 MB）。
- 主仓库 `docs/audits/next-release-evidence/` 现有 **35 MB**，包含当前候选的 phase-d/e/f、matrix、zoom/zh、visual-2e28db4 基线；足以自证 r8 审计。上述四个归档是阶段 B/C/refinement 的历史过程材料，不是 r8 发布证据，因此不归位主仓库。
- 访问方式（仅本机）：`git -C /Users/<user>/Documents/GitHub/luci-app-cloudflare-ip worktree list` 可看到 `/Users/<user>/Documents/GitHub/cfip-docs-evidence`（分支 `phase-b/next-release-fixes`）；直接在该目录查看。
- **可复现性结论：是（2026-11-05 收口，已从零 clone 验证）。** git push 大 pack 被 GitHub HTTPS 重置后，改用 GitHub Git Data API 逐 blob 创建归档分支：`evidence/ui-refinement-archive`、`evidence/ui-skill-audit-archive`、`evidence/visual-phase-b-archive`、`evidence/visual-phase-c-archive`。验证输出见 `next-release-evidence/archive-access.md`。
- 获取与验证：<br>`git fetch origin evidence/ui-refinement-archive:refs/remotes/origin/evidence/ui-refinement-archive`<br>`git rev-parse origin/evidence/ui-refinement-archive:docs/audits/next-release-evidence/ui-refinement-7c13b1d`<br>应与 `archive-manifest.md` 记录的 tree SHA 一致；其余三个分支同理。`archive-manifest.md` 位于 `docs/audits/next-release-evidence/`。
- 本地 bundle 仍可作为离线备份：`git bundle create /tmp/cfip-evidence.bundle phase-b/next-release-fixes`，但不再是唯一获取方式。这四个归档不是 r8/r9 发布证据；主仓库 `docs/audits/next-release-evidence/` 已足以自证发布审计。

## 门禁

- 本地门禁↔CI 一致性由 [tests/ci-test-inventory.py](../../tests/ci-test-inventory.py) 在 CI `workflow-lint` job 执行：任何 `tests/` 下的 `.sh/.py/.cjs` 未接入 CI 且未登记排除理由，job 直接失败。
- 当前：255 files / 250 referenced / 11 documented exclusions / 0 leftovers（2026-11-05，`python3 -B tests/ci-test-inventory.py` exit 0）。`publisher-runtime` job 覆盖两个 publisher fixture 与 `opkg-status-recovery.sh`。
