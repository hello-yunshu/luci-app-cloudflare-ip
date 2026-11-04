# Cross-repo Rill / Performance Manager (2026-11-04)

## 1. Pin 事实与结论

| 对象 | 值 |
|---|---|
| rill-ml `origin/main` | `9602750202f56ed860fc8815bb91e81083d0ffdb` |
| Cloudflare preview pin | `da8389fec7f879b826d8d17cbc6bb98c03ef8462` |
| rill-openwrt-packages `origin/main` / contract pin | `a1245c293605740db3bf49f143ba03f545a89922` |
| Contract qualification | `qualify.yml` run `41497865089`，attempt 1，PASS；manifest `f8e16c5e…` |

`git merge-base da8389f 9602750 = da8389f`；`da8389f..9602750` 为 3 个提交，只有 `Cargo.lock` 的 10 行增删（PR #47 合入 + rand 0.9 bump + PR #46 合入），没有 API/schema/wire 变化。rill-ml main 本身仍是 `wasmtime 46.0.3`；`fe5afb6`（PR #50）和 `ad0fbfc`（PR #51）都未合入 main。

**结论：继续 pin `da8389f`，不跟 `9602750`。** 依据：
1. 契约 qualification `41497865089` 绑定的是 `da8389f` + 包提交 `a1245c2`；改 pin 必须重新资格。
2. `a1245c2` 的 Preview 包已经用 `040-wasm-engine-advisory-20261029.patch` 把 Wasmtime 升到 49.0.5（`metadata/rill-runtime-preview.json`），也包含 010/020/030 补丁；跟随 main `9602750` 不会获得这些安全修复，反而会丢掉已资格补丁。
3. 差异只有 rand 锁文件更新，收益不足；等 PR #50/#51 合入并重新资格后再评估。

`python3 scripts/check_rill_dependency.py --package-dir /tmp/rill-pin-wt`（a1245c2 工作树）输出
`PASS: qualified rill-runtime 1.5.6 from a1245c293605740db3bf49f143ba03f545a89922`。

## 2. PM #13 /usr/bin/rill-runtime 归属

**结论：PR #13 已经解决了冲突，不需要再补丁。**

- `luci-app-performance-manager-all` 拥有 `/usr/bin/rill-runtime`，并在 Makefile 声明
  `PM_ALL_CONFLICTS`（含 `rill-runtime`、`rill-runtime-preview`、core/LuCI/glue），
  APK 侧生成负依赖 `!rill-runtime>=0` 等（`package/luci-app-performance-manager-all/Makefile` L14、L23–L26、L82）。
- 拆分包 `performance-manager-rill` 只依赖 `+rill-runtime`，不写该文件（`package/performance-manager-rill/Makefile` L21）。
- Preview 包自身声明 `CONFLICTS:=rill-runtime`，APK 负依赖 `!rill-runtime (>=0)`（`rill-openwrt-packages/package/rill-runtime-preview/Makefile` L15、L26–L27）。
- `scripts/verify_runtime_package_ownership.py` 校验 stable/preview/full 的二进制字节一致、负依赖完整，并跑
  Full→Stable、Stable→Full、Full→Preview、Preview→Full、Full→split、split→Full 六种顺序；拒绝后 installed set、world、Runtime/Core/config 摘要保持不变。
- 真实 SDK 证据：`docs/audits/g3-runtime-package-evidence/pm-full-final/ownership/results.json`（六种顺序均拒绝，Runtime SHA `bcc587db…`）。
- 本地 `python3 -m unittest tests.test_sync_rill tests.test_all_in_one_package`：21 tests OK。

共存时的检测与提示：包管理器在事务开始前拒绝冲突，脚本不执行；PM Runtime 预检在二进制缺失/版本不符时 fail-closed。Cloudflare 侧只读 `/usr/bin/rill-runtime`，不安装、不写该路径。

## 3. sync-rill.yml 真实 PR 路径

工作流：`.github/workflows/sync-rill.yml`（schedule 每 6 小时、`workflow_dispatch`、`repository_dispatch: rill-runtime-qualified`）。

真实 PR 路径需要：
1. `permissions: contents: write`、`pull-requests: write`、`actions: write`（job 级）；`GH_TOKEN` 可读 rill-ml releases 和 rill-openwrt-packages 的 `qualify.yml` runs/artifacts。
2. 仓库允许 Actions 创建 PR（`gh api repos/.../actions/permissions/workflow` 返回 `can_approve_pull_request_reviews=true`）；`main` 当前未受保护（branch protection 404）。
3. `open_sync_pr.py` 用 `gh auth git-credential` 推送确定性分支 `automation/rill-qualified-<sha>`，再 `gh pr create`。
4. 带 `--qualification-workflow ci.yml` 时，若分支无匹配 run，会 `gh workflow run ci.yml`（显式 dispatch）。

**无法在“零 Actions”下验证真实 PR 创建**：PR 本身会触发 `pull_request` 的 CI；没有匹配 run 时脚本还会主动 dispatch；两者都会创建 run。此项列为**需用户裁决**。

本地可执行验证（已做）：
- 真实 no-change：`check_rill_dependency.py --sync` 输出 `No qualified Runtime contract change.`，契约未改写。
- `open_sync_pr.py` 在临时 bare origin + fake `gh` 下端到端跑通：创建 `automation/test-b6288eee997bcd1adee6`、提交、push、调用 `gh pr create`；未访问真实远端、未触发 Actions。
- `actionlint .github/workflows/*.yml` PASS。

## 4. 边界

本轮未创建 PR、未 push、未 dispatch、未重跑任何 Actions。真实 PR 创建路径的远端行为未验证，等待用户裁决。
