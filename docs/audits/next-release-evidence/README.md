# Next Release Evidence — 2e28db4

基线：`2e28db4b5cdc221897bbe98ff78fbe7235098e53`（`main`）。

## 内容

| 路径 | 内容 |
|---|---|
| `baseline-2e28db4.json` | 仓库/HEAD/worktree/tag/Release/CI 基线 |
| `environment-2e28db4.json` | 真实 LuCI/Aurora 容器、主题、浏览器、fixture |
| `cross-repo-2e28db4.json` | rill-openwrt-packages / rill-ml / performance-manager HEAD 与 open PR |
| `visual-2e28db4/` | 78 张真实 LuCI 截图、`metrics.jsonl`、`visual-index.csv`、`capture-visual.sh` |
| `interactions-2e28db4/` | 真实浏览器交互截图与 `observations.json` |
| `repro-2e28db4/` | 4 项风险的可执行 harness、输出 JSON |
| `i18n-2e28db4/` | 423/88 逐文件数据、缺失 key TSV |

## 视觉截图计数

- 正常态：3 主题 × 3 断点 × 8 页面 = 72
- 边界：320×900 Overview × 3 主题 = 3；1280@200% 等效 640×900 Sources × 3 主题 = 3
- 合计：**78 PNG**
- 所有正常态/边界截图 `overflow=false`；Aurora dark 26/26 `data-darkmode=true`；无登录页。
- 320 Overview 存在顶部导航 tab 裁切（P2-07）。

## 风险复现

```sh
cd /Users/yunshu/Documents/GitHub/luci-app-cloudflare-ip
node docs/audits/next-release-evidence/repro-2e28db4/repro-risks.cjs \
  > docs/audits/next-release-evidence/repro-2e28db4/repro-output.json
```

结果：`openclash_delete.false_success=true`、`rpc_failure_openclash.not_installed=true`、`rpc_failure_sources.rows=0/error_visible=false`、`sources_refresh.reload_calls=1/save_calls=0`、`rill_reset.reload_calls=0/stale_status=true`。

## UI skill audit（`audit/ui-skill-review`，基于 `a8f89e8`，修复提交 `7a08814`）

| 路径 | 内容 |
|---|---|
| `ui-skill-audit/matrix/` | 8 页 × 3 主题 × 375/768/1280 + 320/200% 共 120 张真实 LuCI 截图；`data/metrics-final.jsonl` |
| `ui-skill-audit/before/`、`after/` | 9 条修复的 BEFORE/AFTER 对照（移动端标签、KV 表格截断、焦点环、复制 aria、空态、错误态、来源重复、确认弹窗） |
| `ui-skill-audit/data/` | findings.json、焦点 432 次采样、对比度失败、i18n 正反日志 |
| `ui-skill-audit/scripts/` | 本地 Playwright 审计、对比度/焦点、错误态、长文本与确认弹窗脚本 |

结论：新发现 14 条（P1 2 / P2 7 / P3 5），已修 9 条；0 页面横向溢出；i18n 476 keys / 487 entries PASS。未创建 PR、未触发 Actions；主题自身按钮对比度仅报告不改。

## Phase D（`de5c4e6` / `6d3f3b6` / `a8f89e8`）

| 路径 | 内容 |
|---|---|
| `phase-d/openclash/` | 真实 mihomo+uhttpd 控制器、真实配置/备份文件；删除成功/失败、恢复失败截图与 JSON；恢复成功 BLOCKED（Ruby/Psych segfault） |
| `phase-d/speedtest/` | 真实 `status.json` + 日志经 `speedtest-status` RPC 读取；running/success/error 三态截图与 JSON |
| `phase-d/intelligence/` | 复制按钮、clipboard 拒绝回退、复制失败提示、Live State 折叠、日志互链截图与 JSON |
| `phase-d/scripts/` | 可复现的 Playwright 脚本 |

结论：阶段 D PARTIAL（OpenClash 恢复成功仍 BLOCKED，缺可运行的 Ruby/Psych）；删除两条路径与恢复失败、测速弹窗、Intelligence 三项均 PASS。私有仓库禁用 Actions，本目录证据均为本地真实 LuCI/Playwright/本地契约执行。

## 2.6.0-r7 UI refinement（`7c13b1d` -> `9adb2d5`）

| 路径 | 内容 |
|---|---|
| `ui-refinement-7c13b1d/visual/` | 78 张 3 主题 × 3 断点 × 8 页面正常态 + 320/200% 边界截图；`captures.json` |
| `ui-refinement-7c13b1d/visual-index.csv` | 396 行，含 `interaction`/`state`/`sha`；既有 `visual-phase-c` 78 张全部保留 |
| `ui-refinement-7c13b1d/matrix/` | 42 个交互点的七态矩阵、BEFORE/AFTER 截图、DOM/持久化断言；`matrix.json` |
| `ui-refinement-7c13b1d/early-return/` | OpenClash/PassWall 未安装 + RPC 失败，修复前后 16 张截图与 computed style |
| `ui-refinement-7c13b1d/contrast/` | 3 主题 × 8 页面 1389 个文本元素 WCAG AA 扫描；`audit/report.md` |
| `ui-refinement-7c13b1d/width-matrix/` | 320/375/640/768/900/1280 × 3 主题 × 3 页面内容宽度矩阵（修复前后） |
| `ui-refinement-7c13b1d/keyboard-200/` | 640 CSS px（1280@200%）Tab/焦点/底部可达性 |
| `ui-refinement-7c13b1d/focus-sweep/` | Bootstrap + Aurora dark 逐控件真实 Tab 焦点与 hover |
| `ui-refinement-7c13b1d/baseline-compare/` | v1.8.3-1（`77a65a8`）与 2.x 同环境对照截图与 `report.md` |
| `ui-refinement-7c13b1d/token-footer/` | token/footer 修复前后截图与 computed radius/shadow |

结论：CI run 41703798493 success，Real LuCI UI Gate 41703798508 success；43/43 检查 PASS（41 交互 + 2 只读）；78/78 截图无横向溢出；200% 键盘 16/16 PASS；逐控件 Tab 焦点 312/312；WCAG 扫描 41 项不达标，均为 LuCI/Aurora 原生按钮/标签色，已在报告中说明不覆盖主题的原因。物理设备与 24h soak 当时 `NOT RUN`（后按用户裁定改为 `PASS-BY-USER-DECISION`）。

## Phase E（`1ec2a6d`）

| 路径 | 内容 |
|---|---|
| `phase-e/before/`、`after/` | Advanced、Diagnostics、Sources、Intelligence 四组真实 LuCI BEFORE/AFTER 截图与 DOM 文本读数；四组 PNG sha256 均不同 |
| `phase-e/package/` | r8 IPK control、IPK/APK metadata（含 sha256/size，确认 `Depends` 无 uhttpd） |

结论：6 条发布前必须做全部闭合；本地门禁与 exact-SHA CI `41841999414` / `41841991191` / `41841999512` 全绿；详见 `docs/audits/next-release-phase-e-report.md`。

## 边界

- 真实物理设备、硬件矩阵、24h soak：按用户 2026-11-04 裁定 **PASS-BY-USER-DECISION**，未补造新记录。
- 真实 OpenClash：phase D 已使用真实 mihomo 1.19.33 + uhttpd 控制器，并在 aarch64 上完成真实备份恢复；PassWall 真实代理网络仍 **NOT RUN**。
- 本轮已跑 WCAG AA 三主题全页扫描、键盘 200% 与逐控件焦点；真实触控设备、物理硬件矩阵仍 **NOT RUN**。
- 200% 缩放为 640 CSS px 有效宽度近似，不是精确浏览器 zoom。
- 审计容器与 fixture 不属于产品代码；审计完成后清理容器/镜像，保留本目录证据。
