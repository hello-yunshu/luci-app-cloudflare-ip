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

## 5. 推荐（供用户裁决）

**推荐：本轮按 `PASS-BY-LOCAL-EQUIVALENT` 接受，不为此单独开真实 PR；在下一次 Runtime 契约真正变更前，安排一次真实的 `workflow_dispatch` 演练。**

理由：

1. r8 的发布字节与该工作流无关；真实 PR 路径未验证不构成发布阻断。
2. 本地已覆盖脚本核心逻辑、no-change 真实运行、单测与 actionlint；剩余风险是 GitHub 权限/PR API，失败会显式报错。
3. 真实 PR 演练会产生额外分支、PR、CI run 与通知；在发布收口窗口增加噪声，收益低于成本。

如果用户的验收口径是“任何未在真实 GitHub 跑过的自动化都不得计 PASS”，则替代方案是：授权后执行一次 `workflow_dispatch`（或等下一次有合格变更时）真实创建 PR，观察 PR/CI/dispatch 三件事，再标记 PASS。这需要额外一次远端写操作与 CI，不应由代理自行执行。

**最终状态仍为 PARTIAL，等待用户选择：接受本地等价，或要求真实 PR。**
