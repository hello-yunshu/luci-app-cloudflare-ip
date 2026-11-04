# Phase G - release closeout preparation

Result: **准备完成，未执行任何发布动作**。代码候选 `90dfc13`（PR #25，OPEN / MERGEABLE）；阶段 G 收口提交只增加 CHANGELOG、Release notes、发布检查清单、sync-rill 裁决材料与文档 SHA 同步，不改变代码树。未合并、未打 tag、未建 Release、未改 `release-channel.json`。

## 0. 结论与计数

- 发布身份：`2.6.0-r8`，候选 tag `v2.6.0-8`，Release 标题 `v2.6.0-8`，类型 **Pre-release**。
- 候选包（exact-SHA `90dfc13`，run `41883717485` attempt 1）：
  - IPK 182736 B，SHA256 `1a3bc3cc8db4ac1a2b620197212b63463889a137c94d92e4467ea499494cbdeb`
  - APK 182025 B，SHA256 `a40cc8599f0c60fafce5279634ab30d0070f5850ec1939d895bffd88ccd5b935`
- IPK/APK `Depends` 均为 9 项，**无 uhttpd**。
- 阶段 G 前 exact-SHA `90dfc13` 的三份 CI 全绿（PR `41883367845`、push `41883717485`、UI Gate `41883367585`）。
- 待授权动作 4 项：merge → tag → Release → channel（channel 建议不动）。

## 1. 发布内容定稿

- 新增 [CHANGELOG.md](../../CHANGELOG.md)：`v2.6.0-8` 段落，只写已闭合的 Phase D/E/F 事实，未闭合项不写入。
- 新增 [Release notes 草稿](next-release-release-notes-v2.6.0-8.md)：一句话定位、变更分类、升级注意事项（legacy 自更新停用、`self_update_url` 只读、uhttpd 可选、IPK/APK 选择、备份与校验）。
- 新增 [2.6.0-r8 发布准备](../2.6.0-r8-RELEASE-READY.md)：身份、资产、授权清单、命令、回滚。
- README 中英文状态同步：r6 已发布为 pre-release；r8 为当前候选；发布收口材料已准备，等待授权。

## 2. 产物与资产校验

| 资产 | 大小 | SHA256 | 证据 |
|---|---:|---|---|
| `luci-app-cloudflare-ip_2.6.0-r8_all.ipk` | 182736 | `1a3bc3cc…cbdeb` | run `41883717485`，`qualification.json` assetFiles |
| `luci-app-cloudflare-ip-2.6.0-r8.apk` | 182025 | `a40cc859…5b935` | 同上 |
| `sha256sums.txt` | — | 与上面两项一致 | `qualification-evidence` artifact |
| `qualification.json` | — | commit `90dfc13` / run `41883717485` / attempt 1 | 同上 |

依赖核对：

- IPK `control`：`Depends: libc, luci-base, bash, flock, curl, tar, jq, ca-bundle, ca-certificates`。
- APK（apk-tools 3.0.8 `--simulate`，network-disabled）：同上 9 项。
- 两者均**不含 `uhttpd`**。

可复现性：`e8766f5` 与 `90dfc13` 两个 docs-only 提交的公开 IPK 逐字节相同（`1a3bc3cc…`），说明 docs/CHANGELOG 变更不改变包内容；最终 tag 仍以合并后 `main` 的 run 为准。

## 3. 发布前回归

- `90dfc13`：PR CI `41883367845` success；push CI `41883717485` success；Real LuCI UI Gate `41883367585` success。
- `ffa73f6`（代码修复提交）：PR `41865842245`、push `41865829195`、UI Gate `41865842265`，均 success。
- 阶段 G 收口提交：docs-only；其 exact-SHA CI 结果见最终交付消息（本报告提交时尚未产生该 run）。
- docs/INDEX/issue register 已从 `ffa73f6` 同步到 `90dfc13`；证据 JSON 保留采集 SHA `ffa73f6`（真实采集时间），不伪改。

## 4. 回滚与渠道

- 当前 `release-channel.json` 为 `stable`；`release.yml` 明确拒绝非 `prerelease` 的自动晋级，因此即使合并后也不会自动发 Release。
- 本版本用人工 `gh release create --prerelease`；**不改 channel**。发布 pre-release 不会触发任何仓库内自动更新/feed，因为仓库没有 feed 发布步骤。
- 回滚：
  1. 不移动、不删除、不替换 tag；tag 是不可变身份。
  2. 问题版本：Release 标记 draft/加警告，停止推荐；发 `v2.6.0-9` 修复。
  3. 设备：用 r6 Release 包回装，恢复升级前 UCI/代理/cron/enable 备份，只移除新增依赖。
  4. 若未来改过 channel：恢复原 `release-channel.json` 并重跑 CI；当前无此动作。

## 5. tag 目标与合并策略

- **推荐**：PR #25 用 **Create a merge commit** 合并（`main` 是 PR 头的祖先，无冲突；`tree(M) = tree(P)`），等 `main` 上 `M` 的 CI 全绿后，以 `M` 为 `--target` 创建 tag/Release。
- **原因**：发布策略要求正式包只从 `main` 的 exact-SHA CI 运行发布；`90dfc13`/阶段 G 提交都在 PR 分支，不是 `main` 提交。
- **例外**：若用户明确接受“直接在 PR 头打 tag”，则 tag 目标为阶段 G 提交 `P`，使用 `P` 的 exact-SHA run；这是对 main 策略的一次性偏离，需在 Release notes 标注。
- 不使用 squash/rebase 作为首选：merge commit 保留树与提交身份，便于 `tree(M) = tree(P)` 的证明。

## 6. 跨仓 sync-rill

- 详见 [sync-rill 裁决材料](next-release-sync-rill-adjudication.md)。
- 推荐：本轮按 **PASS-BY-LOCAL-EQUIVALENT** 接受；不为此单独开真实 PR；在下一次 Runtime 契约真实变更前做一次真实 `workflow_dispatch` 演练。
- 理由：r8 不改变 Runtime 契约，发布字节与该工作流无关；真实 PR 路径失败会显式报错，不会静默改坏包；仓库已公开，未来具备演练条件。
- 最终由用户裁决，本文不自行定案。

## 7. 待授权清单

| # | 动作 | 前置条件 | 风险 |
|---|---|---|---|
| 1 | `gh pr merge 25 --merge` | 用户明确授权；PR MERGEABLE | 合并后需重跑 main CI；可 revert |
| 2 | 等 `main` merge commit `M` CI 全绿 | CI + UI Gate success；qualification 同 run/attempt | 红则修复，不重试撞运气 |
| 3 | `gh release create v2.6.0-8 --target M --prerelease` | 用户单独授权 tag/Release；资产校验通过 | tag 不可回滚；坏版本发 r9 |
| 4 | channel 保持不变 | 用户不授权改 channel | 无自动 Stable 晋级 |

## 8. 仍开放

- merge/tag/Release/channel：等待用户单独授权。
- 跨仓 sync-rill：等待用户裁决。
- 物理设备/24h soak：PASS-BY-USER-DECISION，未补造记录。
- PassWall 真实代理网络、arm64 之外架构、完整触控矩阵：未覆盖。
