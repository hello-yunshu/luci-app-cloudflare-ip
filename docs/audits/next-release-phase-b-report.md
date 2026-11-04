# Next Release Phase B Report — 2e28db4 → e557f19

判定：**PARTIAL**。P0 全部关闭，4/5 P1 关闭（P1-05 真实设备/24h soak 仍 NOT RUN），P2 5/9 修复、4 条按最小改动保留并记录；i18n 435/435 全覆盖，i18n 门禁与真实 LuCI UI 门禁已接入；未升版本、未打 tag、未改 Release、未 push。

## 1. 关键数字

| 项 | 结果 |
|---|---|
| P0 | 1/1 关闭 |
| P1 | 4/5 关闭；P1-05 NOT RUN |
| P2 | 5/9 修复；4 条记录保留 |
| P3 | 1 条部分覆盖（术语翻译）；1 条不处理 |
| i18n | 439/439 key 覆盖 POT/zh_Hans/en（100%）；阶段 A 88 条清单 88/88 在 POT/zh（66 条阶段 A 清单新增 + 22 条原有；Phase B 另新增 4 条错误文案） |
| i18n 门禁 | `python3 tests/i18n-contract.py` PASS；负向用例 exit 1 |
| 真实 UI 门禁 | `tests/real-luci-ui.cjs` 2/2 PASS |
| 真实分支回归 | 7/7 PASS |
| 视觉矩阵 | 72 正常 + 6 边界 = 78/78；overflow 0；登录页 0 |
| 代码提交 | 分支内 `e557f19` + `6e91903` + `20974eb`（未 push） |

## 2. 缺陷 red→green

红基线：`/tmp/cfip-red-2e28db4`，detached `2e28db4`；绿基线：当前分支工作树（内容提交为 `e557f19`）。同一 harness：

```sh
CFIP_ROOT=/tmp/cfip-red-2e28db4 node docs/audits/next-release-evidence/repro-2e28db4/repro-risks.cjs
node docs/audits/next-release-evidence/repro-2e28db4/repro-risks.cjs
```

| 缺陷 | 根因 | 修复文件与行 | 红证据（2e28db4） | 绿证据（e557f19 内容） |
|---|---|---|---|---|
| P0-01 OpenClash 删除假成功 | 仅判断 `result.error`，`{success:false}` 无 error 仍提示成功并 reload | `openclash.js:183-190` 改为 `success !== true || error` 失败分支 | `false_success=true`, `reload_calls=1` | `false_success=false`, `reload_calls=0` |
| P1-01 RPC 失败当未安装/空 | `catch` 丢弃错误，返回 `{}` | `openclash.js:13,30-31,39-47,105-111`；`sources.js:13,22,26-31,71-72`；`passwall.js:8-34`；`settings.js:8-25,66-74` 保留 `_rpcError` 并渲染错误 + Retry / 明确说明 | OpenClash `OpenClash Not Found`；Sources `rows=0,error=false`；PassWall `PassWall Not Found`；Settings `not_installed=true` | OpenClash `error_visible=true,not_installed=false`；Sources `error_visible=true`；PassWall `error_visible=true,not_installed=false`；Settings `error_visible=true,not_installed=false` |
| P1-02 Sources 刷新丢草稿 | 成功即 `location.reload()` | `sources.js:88` 成功只提示，不 reload | `reload_calls=1, save_calls=0` | `reload_calls=0, draft=modified-but-unsaved` |
| P1-03 Rill reset 不刷新 | 成功后只通知，无状态重读 | `intelligence.js:287-300` 成功 `location.reload()`；另修复 `form.Button` 事件参数 `ev.currentTarget`（`272,287`） | `reload_calls=0, stale_status=true` | `reload_calls=1, stale_status=false` |

真实 UI 额外发现：`intelligence.js` 的 `form.Button` 处理器把事件对象当 DOM 按钮（`button.setAttribute is not a function`），导致 reset 从未调用后端。已改为 `ev.currentTarget`；真实容器 reset 写入 `resetReason=manual_reset` 并触发 reload（`docs/audits/next-release-evidence/regression-phase-b/regression.json`）。

## 3. i18n 与门禁

- 当前 key：430 个 JS + 9 个菜单 = 439；POT/zh_Hans/en 各 447 条（含历史条目）。
- 补入阶段 A 清单缺失的 66 条 key（含 `Candidate IP Sources`、`Intelligence`）以及 Phase B 新增错误/确认文案 4 条；阶段 A 清单中的 22 条长句原已在 PO 中，阶段 A 单行解析造成误报，现已复核为 88/88 覆盖。
- 真实 zh_cn 菜单：`概览 / 设置 / OpenClash / 候选 IP 来源 / PassWall / 智能优选 / 高级 / 日志与记录`（78 张截图均记录该菜单）。
- 门禁：`tests/i18n-contract.py` 做 JS/菜单抽取、`msgfmt -c`、POT/zh/en 覆盖、空 msgstr、fuzzy、重复 id 检查。
- CI：`.github/workflows/ci.yml` 新增 `i18n-contract` job，并加入 `qualification-guard`/`evidence-manifest` 的 required needs；`scripts/qualification_jobs.py` 同步。
- 负向验证：临时移除 `Intelligence`/`Candidate IP Sources` 后 exit 1，恢复后 PASS。输出见 `i18n-phase-b/negative-gate.txt`、`positive-gate.txt`。

## 4. 真实 UI 门禁与回归

门禁文件：`tests/real-luci-ui.cjs` + `tests/real-luci-ui-provision.sh` + `.github/workflows/real-luci-ui.yml`。

- 触发：`pull_request` 影响 `htdocs/**`、`menu.d/**`、`rpcd/**`、`etc/config/**`、`tests/real-luci-ui*` 或 workflow；另支持 `workflow_dispatch`。
- 内容：真实 OpenWrt 容器、真实 uhttpd/LuCI 登录、真实 rpcd；断言（1）Sources 输入草稿在刷新后保留且页面未 reload；（2）移除 `cf_ip` rpcd 对象后显示显式错误与 Retry。
- 本地结果：2/2 PASS，证据 `ui-gate-phase-b/ui-gate.json`、3 张 PNG。

分支回归（真实容器，证据 `regression-phase-b/regression.json`）：

| 场景 | 结果 |
|---|---|
| OpenClash 未安装分支（真实 check-env） | PASS |
| PassWall 未安装分支（真实 check-env） | PASS |
| OpenClash RPC 失败（对象缺失） | PASS，显式错误而非未安装 |
| PassWall RPC 失败（对象缺失） | PASS，显式错误而非未安装 |
| Settings RPC 失败（对象缺失） | PASS，显式环境错误而非“未安装代理” |
| 备份删除失败（UI 真实点击 + `rm` 失败注入） | PASS，错误提示、无 reload、备份保留 |
| Rill reset（真实 rill-reset + reload + `manual_reset` 元数据） | PASS |

补充：Diagnostics 清除日志已改为 LuCI modal；真实 UI 取消可关闭、确认后日志清空（`logs-clear.json`）。

## 5. 视觉与可读性

矩阵：Bootstrap / Aurora light / Aurora dark × 375/768/1280 × 8 页 = 72；320 Overview ×3 + 640 Sources ×3 = 6；共 78 PNG。

- `overflow=0`（78/78）；登录页 0；`minTextLen=219`。
- Aurora dark 26/26 `data-darkmode=true`；Bootstrap/Aurora light 均为 light（Bootstrap 用浏览器 `colorScheme=light` 复测，避免系统深色污染）。
- 320px：tab 行均换行，Aurora 5 行、Bootstrap 2 行；所有 tab `maxRight < 320`，页面 `scrollWidth=320`。见 `layout-evidence.json`。
- 日志字号 12px、monospace（`accessibility-evidence.json`）；`prefers-reduced-motion: reduce` 下 `animationName=none`，默认 `cfi-pulse`。
- 证据：`visual-phase-b/`（78 PNG、`metrics.jsonl`、`visual-index.csv`、`summary.json`、`capture.sh`）。

P2 未修项：
- P2-01 600/900 媒体查询：按最小改动保留，改容器查询会改变现有断点观感，影响低。
- P2-02 Overview 内联 CSS：保留，纯维护性问题，移除会改变桌面卡片布局。
- P2-03 主题变量双来源：保留 `prefers-color-scheme` 作为无主题状态 fallback；Aurora light/dark 已实测。
- P2-09 Rill pin：按用户口径不跟随，跨仓资格不在本阶段。

## 6. 门禁逐条

| 检查 | 结果 |
|---|---|
| `python3 tests/i18n-contract.py` | PASS |
| i18n 负向用例 | FAIL（exit 1，符合预期） |
| `node tests/real-luci-ui.cjs` | PASS（2/2） |
| 分支回归 `regression.cjs` | PASS（7/7） |
| 视觉 78 张 | PASS，overflow 0 |
| `node --check` 全部 JS | PASS |
| `bash tests/security-contract.sh` | PASS |
| `tests/openclash-rpc-contract.sh` | PASS |
| `tests/luci-validation-contract.sh` | PASS |
| `tests/luci-refresh-error.cjs` / `luci-view-bindings.cjs` | PASS |
| `tests/log-rotation.sh` / `openclash-empty-fields.sh` / `openclash-review-regressions.sh` | PASS |
| `tests/package-release-bump-contract.sh` / `release-channel-contract.sh` / `build-version-policy.py` | PASS |
| `tests/release-asset-binding.sh` / `qualification-evidence-validator.sh` / `evidence-manifest-default.sh` | PASS |
| `actionlint`（v1.7.12） | PASS |
| `tests/luci-staged-validation.sh` | 本机 macOS FAIL；红基线同样 FAIL（`/etc/cf_ip` 不存在），属宿主环境限制，非本次回归 |
| `tests/aux-rpc-disabled.sh` | 本机 macOS FAIL；红基线同样失败，属宿主环境限制 |
| GitHub Actions | **NOT RUN**（按约束未 push/未触发） |
| 物理设备/硬件/24h soak | **NOT RUN** |

## 7. 环境

| 项 | 值 |
|---|---|
| OpenWrt | 24.10.8 x86_64，rootfs `openwrt-24.10.8-x86-64-rootfs.tar.gz`（最终重建 sha256 `c1d63240d9d2b421ed8f1c6f67883030615ffa7f4115acabbb83f1574b526da7`） |
| LuCI | `26.205.85413~cac97ed` |
| Aurora | `luci-theme-aurora 1.4.0-r20260920`，sha256 `5b3f2d669ef82e575498d1b99c4b9b498088540eeff7db989f214b63d3ef8a8e` |
| 浏览器 | Microsoft Edge 156.0.0.0 headless（agent-browser）；Playwright Chromium for UI 门禁 |
| 容器 | `cfip-ui-gate`，`--network host`，uhttpd `127.0.0.1:18080`；已删除 |
| 临时镜像 | `cfip-openwrt-rootfs:24.10.8`；已删除 |
| fixture | 真实 LuCI/rpcd；OpenClash/PassWall init stubs；`/etc/cf_ip` 700；状态/备份 fixture；仅测试容器，未改产品 |

## 8. 清理清单

- 已删除容器 `cfip-ui-gate`。
- 已删除临时镜像 `cfip-openwrt-rootfs:24.10.8`。
- 已删除红基线 worktree `/tmp/cfip-red-2e28db4`（`git worktree list` 仅剩主工作树）。
- 已删除 `/tmp/cfip-rootfs`、`/tmp/cfip-pkgs`、`/tmp/cfip-ui`、`/tmp/po2lmo*`、浏览器临时脚本/指标、临时 PO 负向副本、审计临时克隆与日志。
- 保留：仓库内 `docs/audits/next-release-evidence/` 与 78+ 张截图（证据，不属临时产物）。

## 9. 仍需用户拍板

1. **版本号**：未升 `PKG_VERSION/PKG_RELEASE`，r7/2.7.0 等编号未定。
2. **发布前置**：是否基于本分支 exact-head 触发 CI、是否需要新增真实 UI workflow 为 required check、是否允许 push/PR。
3. **Rill pin**：保持 `da8389f` 不跟随；如需跟随 rill-ml main/PR #50/#51，需另行资格。
4. **24h soak / 物理设备**：仍 NOT RUN；容器证据不能替代硬件与长期 soak。
5. **P2 保留项**：P2-01/02/03 是否接受“最小改动”口径，或后续单独安排视觉/结构重构。

## 10. 提交

- 代码与门禁：`e557f19` + `6e91903` + `20974eb`（`phase-b/next-release-fixes`，未 push）。
- 证据与报告：本目录及 `docs/plans/`、`docs/audits/*.md`，随本分支文档提交。
- 未创建 tag、未修改 Release、未 push main。
