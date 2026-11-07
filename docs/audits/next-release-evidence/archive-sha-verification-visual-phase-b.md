# `evidence/visual-phase-b-archive` SHA 三方核对

日期：2026-11-08。独立事项，不属于清理记录。

## 1. 待核对的三组标识

| 来源 | 值 | 对象类型 |
|---|---|---|
| 远端分支 `origin/evidence/visual-phase-b-archive` | `9b0a11ed128d1e76186407374111a211c1795ac3` | commit |
| 本地分支 `evidence/visual-phase-b-archive` | `41944f2b369810ee2df72153d9d37069094e2e97` | commit |
| `docs/audits/next-release-evidence/archive-access.md` 记录 | `f7e706dc744a7f92d7dd45dad2a2bbf756ada6ce` | **tree** |

`git cat-file -t f7e706d` → `tree`。该值不是分支 head，而是证据目录
`docs/audits/next-release-evidence/visual-phase-b` 的 tree SHA。

## 2. 实测

```text
$ git rev-parse 9b0a11e:docs/audits/next-release-evidence/visual-phase-b
f7e706dc744a7f92d7dd45dad2a2bbf756ada6ce
$ git rev-parse 41944f2:docs/audits/next-release-evidence/visual-phase-b
f7e706dc744a7f92d7dd45dad2a2bbf756ada6ce
$ git diff --stat 9b0a11e 41944f2
 docs/audits/next-release-evidence/archive-manifest.md | 13 -------------
 1 file changed, 13 deletions(-)
$ git rev-parse 9b0a11e^ 41944f2^
8257a3d2979cbc187cc0677fc61f81bde3ea0c04
8257a3d2979cbc187cc0677fc61f81bde3ea0c04
```

- 两个 commit 的 `visual-phase-b` 子树完全相同，都等于 `f7e706d`。
- 两个 commit 是同一父提交（`8257a3d`）的兄弟提交，不存在“本地领先远端”的内容差异。
- 唯一差异是 `archive-manifest.md`：远端 `9b0a11e` 含该文件，本地 `41944f2` 删除了它（13 行）。
- 本地分支没有被任何 worktree 检出（`git worktree list` 只包含 `main`、`fix/ui-spec-p0-p1`、`docs/ui-design-spec-from-upnp`）。

同方法抽查 `archive-access.md` 表格中的其他归档：

| 分支 | 路径 tree | 记录值 | 结果 |
|---|---|---|---|
| `evidence/ui-refinement-archive` | `fb92ee260fcffd298bf3a92cc2aefed29a4ff566` | 同左 | MATCH |
| `origin/evidence/visual-phase-c-archive` | `f620e14d70088e56309d82c2070941781adf5afd` | 同左 | MATCH |
| `evidence/ui-skill-audit-archive` | — | `e0096eb8d19e92bce9765651c0eace24caa59ac8` | 本地无该 ref，未验证 |

## 3. 结论

1. “三方不一致”是**对象层级混淆**造成的误报：`f7e706d` 是目录 tree SHA，不能与两个 commit SHA 直接比较。
2. 证据内容无分歧：本地与远端都指向同一 `f7e706d`；差异只在本地的 `archive-manifest.md` 缺失。
3. 远端 `9b0a11e` 是完整、规范的分支状态（含 manifest），应作为 canonical。
4. 本地 `41944f2` 是仅存在于本地的兄弟提交，未推送、未被 worktree 使用、不含独有证据内容。

## 4. 建议（未执行）

- 后续核对统一使用 `git rev-parse <ref>:<path>` 比较 tree SHA，不再把 tree 当成 commit。
- 如需让本地与远端一致，可把本地 `evidence/visual-phase-b-archive` 指到 `9b0a11e`（该分支未被工作区占用）；在用户确认前不改写 ref。
- 本轮按“仍独有即保留”原则保留该分支，不删除。
