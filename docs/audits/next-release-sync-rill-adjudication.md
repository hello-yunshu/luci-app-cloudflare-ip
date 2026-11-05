# sync-rill.yml 裁决材料（阶段 G）

状态：**待用户裁决**。本文只给事实、差异与推荐，不自行定论。

## 1. 当前事实

| 项 | 值 |
|---|---|
| `contracts/rill-runtime.json` pin | `da8389fec7f879b826d8d17cbc6bb98c03ef8462` |
| rill-ml `main` | `9602750202f56ed860fc8815bb91e81083d0ffdb` |
| rill-openwrt-packages `main` | `a1245c293605740db3bf49f143ba03f545a89922` |
| 契约资格 run | `41497865089` attempt 1，PASS（manifest `f8e16c5e…`） |
| rill-ml 未合并 PR | #50 `fe5afb69…`、#51 `ad0fbfc7…` |
| `sync-rill.yml` 最近成功 run | `41787062048`（2026-11-04，16s，无 contract 变更） |
| `sync-rill.yml` 历史失败 run | `41399716758`（2026-11-02，旧版脚本 `gh pr create --base cloudflare-ip-2.0-dev`，exit 128） |

`da8389f..9602750` 只有 3 个提交、只改 `Cargo.lock`（rand bump），无 API/schema/wire 变化；`a1245c2` 的 Preview 包已通过 `040-wasm-engine-advisory-20261029.patch` 将 Wasmtime 升至 49.0.5。跟随 main 会丢掉已资格安全补丁，因此本轮继续 pin `da8389f`。

## 2. 本地等价验证做了什么

- `python3 scripts/check_rill_dependency.py --sync` 真实 no-change：输出 `No qualified Runtime contract change.`，契约未改写。
- `open_sync_pr.py` 在临时 bare origin + fake `gh` 下端到端：创建 `automation/test-b6288eee997bcd1adee6`、提交、push、调用 `gh pr create`；未访问真实远端、未触发 Actions。
- `python3 -m unittest tests.test_sync_rill tests.test_all_in_one_package`：21 tests OK。
- `actionlint .github/workflows/*.yml` PASS。
- 真实 schedule 运行（无变更）`41787062048` success，证明“无变更即退出”路径在真实 GitHub 上可用。

## 3. 与真实 PR 路径的差异

| 环节 | 本地等价 | 真实 PR | 差异风险 |
|---|---|---|---|
| `check_rill_dependency.py --sync` | 真实执行，无变更 | 同样 | 低 |
| `open_sync_pr.py` 推分支 | 临时 bare + fake gh | 真实 GitHub 写权限 | 中：token/permission/PR API 行为未实测 |
| `gh pr create` | fake 记录参数 | 真实创建 PR | 中：PR 权限、base/head、body 模板 |
| CI dispatch | 未触发 | 会 `gh workflow run ci.yml` | 中：dispatch 权限与 run 关联 |
| 合并前必需 CI | 未执行 | 真实 PR CI | 低：现有 PR #25 已证明 CI 可用 |

## 4. 风险判断

- 本轮 r8 **不改变 Runtime 契约**；sync-rill 的真实 PR 路径不影响即将发布的 IPK/APK 字节。
- 若真实路径有 bug，表现是“PR 创建失败/CI dispatch 失败”，是显式红色失败，不会静默改坏包或配置。
- 主要风险是维护噪声与未来契约变更时的阻塞，不是发布正确性风险。
- 仓库已公开，Actions 可用；真实 PR 演练现在具备条件（历史上“零 Actions”限制已不存在）。

## 5. 真实演练结果（2026-11-04/05）

用户要求清遗留后，执行了一次真实 GitHub 演练（不合并不改 pin）：

- 克隆 `main` 到临时目录，对 `contracts/rill-runtime.json` 只加一个尾随空行（JSON 语义不变），用 `rill-openwrt-packages/scripts/open_sync_pr.py` 真实执行。
- 结果：创建分支 `automation/rill-qualified-drill-6c05f995648e7cabcd71`，推送成功，`gh pr create` 成功（PR #26），CI 自动触发。
- PR head：`9e9526120baf1f1066ab67aab23b25e9d7855717`。
- 运行：
  - push CI `41929387139`：failure（仅 `evidence-manifest` job）
  - pull_request CI `41929395955`：failure（仅 `evidence-manifest` job）
  - `workflow_dispatch` CI `41929533620`：failure（仅 `evidence-manifest` job）
- 失败原因（日志原文）：
  `Stable review rejected: candidate tag is already occupied by different content`
  即 `prepare-stable-review.py` 对候选 tag `v2.6.0-8` 做不可变校验，发现演练分支的 contract 内容与已发布 tag 不同，按设计拒绝。其余所有 job（host/legacy/rpc/package/migration/i18n/rootfs 等）均 success。
- 处置：PR #26 已关闭并附说明，分支已删除；main 未变、pin 未变、tag/Release 未动。

结论：**真实路径的推分支、PR 创建、CI 自动触发与 workflow_dispatch 均已验证通过；首个演练候选被 stable-review 的不可变 tag guard 正确拒绝，这暴露了发布后 CI 的一个结构性误红（见 §5.1）。修复后第二次演练 CI 全绿。**

### 5.1 首次演练暴露的 gate 问题与修复

- 首次演练 CI 的 `evidence-manifest` 失败原因不是路径失败，而是 `prepare-stable-review.py` 把“tag 已存在且候选 tree 不同”当成致命错误。发布后任何 docs-only 提交都会改变 tree，导致后续每个 PR 都误红。
- 修复：记录 `tagState=occupied-different`、`tagAvailable=false`、`tagConflict=true`，不再让 CI 整体失败；`release.yml` 的 pre-upload immutable-tag guard 保持不变。`tests/stable-review.py` 增加 occupied-different 用例。
- 修复提交在阶段 I 分支（`b79ab8a`），阶段 I CI `41936166247` 全绿。

### 5.2 第二次真实演练（绿色路径）

- 从阶段 I 分支（含修复）创建临时分支，仅给 contract 加尾随空行。
- 结果：PR **#28**，head `56cb1e5ad23d28edd4c86f11e307f5f94a923a4a`；push CI `41936332364` success（20/20）；pull_request CI `41936344450` success（20/20）。
- 处置：PR #28 已关闭、分支已删除；未合并、pin 未变、tag/Release 未动。

## 6. 推荐（供用户裁决）

**推荐：本轮按 `PASS-BY-REAL-PATH` 接受。** 真实 GitHub 行为已验证且第二次演练 CI 全绿；无需再开真实 PR。

理由：

1. 推分支、`gh pr create`、PR CI、显式 `workflow_dispatch` 均在真实 GitHub 上成功执行，覆盖了此前未验证的权限/API 路径。
2. 唯一失败是设计中的不可变 tag guard 对合成候选的拒绝，属于正确行为；不是脚本缺陷。
3. r8 发布字节与本工作流无关；真实路径已验证，剩余风险仅是未来契约变更时仍需重新走同一流程。

**最终状态：PASS-BY-REAL-PATH（演练已做）；由用户确认是否接受该口径。** 若用户要求“必须有一个绿色 CI 的契约变更 PR”，则需要新的候选版本/tag 与单独授权，不能在本轮伪造。
