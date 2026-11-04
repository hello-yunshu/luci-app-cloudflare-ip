# Phase F - remaining evidence and gate-drift closure

Result: **PASS（第 4/7/9/10 条闭合；门禁↔CI 漂移已治理）**。代码证据采集于 `ffa73f6`，当前代码候选 `90dfc13`（docs-only 提交，代码树相同；PR #25）；未合并、未打 tag、未建 Release、未改 release-channel。

## 0. 结论与计数

- 第 4 条：**51 个交互点 × 7 态 = 357 个状态单元**；真实可达 **121**，PASS **121**，FAIL **0**；N/A **236** 均有逐条原因。
  - 覆盖率算法：`reachable = PASS + FAIL`；`coverage = PASS / (PASS + FAIL)` = **121/121 = 100%**。
  - 矩阵单元覆盖率（含物理不可达态）：`PASS / 总单元` = `121/357 = 33.9%`。
  - 证据索引：**225** 个状态文件条目（含 BEFORE/AFTER、跨状态复用），每项带 sha256；矩阵截图 **210** 张。
- 第 7 条：7 份 docs 绑定当前候选 `90dfc13`（证据采集 SHA `ffa73f6`，代码树相同）；P0/P1 全部 CLOSED；P2-07/P2-08 也已关闭；docs 放主仓库，README + INDEX 双入口。
- 第 9 条：真实 Chrome 页面缩放 125/150/200%（设置页“网页缩放”，非 CDP emulate）+ 320 reflow；三档 8 页全部 0 横向溢出、0 文字截断、0 焦点环缺失、0 主内容焦点离屏、0 console error。
- 第 10 条：zh_cn 真实渲染 375/1280 共 16 页；英文残留、msgid 泄漏、菜单缺失、期望文案缺失、横向溢出、截断、console error 全部为 0。
- 门禁漂移：`openclash-rpc-contract.sh` 等 5 个脚本纳入 CI；新增 `tests/ci-test-inventory.py` 逐文件一致性检查；254 个本地测试中 247 个在 CI、7 个登记理由排除、0 个遗漏。

## 1. 第 4 条：七态逐交互点

环境：真实 OpenWrt 24.10.8 x86_64 rootfs（procd/uhttpd/rpcd/LuCI 26.301），真实 Chromium 153，主题 Bootstrap light（`data-darkmode=false`），viewport 1280×900，locale en-US。真实可达态用真实 RPC 成功、Playwright 路由按 method 注入真实失败、真实延迟、真实表单/弹窗/copy/collapse/只读交互触发；没有用静态截图冒充状态。

点数构成：阶段 A–C 的 **43 点**（41 交互 + 2 只读）保留，新增 8 点，共 **51**：

- `int-copy`（Intelligence 复制按钮，clipboard 成功/双拒绝）
- `int-collapse`（Live State 折叠，localStorage 持久化）
- `int-open-logs`、`logs-open-intelligence`（跨页外链）
- `oc-details`、`err-details`（技术详情展开/收起）
- `oc-copy`（OpenClash 技术详情复制）
- `adv-self-update`（弃用字段只读）

| 状态 | PASS | N/A | FAIL |
|---|---:|---:|---:|
| success | 51 | 0 | 0 |
| loading | 7 | 44 | 0 |
| disabled | 9 | 42 | 0 |
| error | 17 | 34 | 0 |
| partial | 0 | 51 | 0 |
| cancel | 25 | 26 | 0 |
| rollback | 12 | 39 | 0 |
| **合计** | **121** | **236** | **0** |

N/A 原因分类（逐点写入 `note`，无空白 N/A）：

- `partial`：cf_ip RPC 每请求返回单原子结果，无部分成功契约（51/51）。
- `loading`/`disabled`：普通 form.Button 与只读/外链控件没有异步 busy 语义；Retry 走整页 reload。
- `cancel`：普通按钮、只读内容、外链、details 无取消语义。
- `rollback`：字段级交互不直接写服务器，回滚由所属 Save/Apply 点覆盖。

每条 PASS 状态的断言类别（`matrix.json` 的 `assertions[state]`）：

- **DOM**：`dom`（maincontent 文本长度、alert 数、details 数、页面横向溢出）＋该点自身的 value/checked/open/expanded/disabled 等。
- **焦点**：`focus`（activeElement tag/text、是否在 maincontent、焦点环、是否在视口内）。鼠标触发态按实际记录 ring=false，不伪称键盘焦点。
- **持久化**：`persistence`，`ASSERTED` 时记录 server-state/uci-staging/localStorage；不持久化的态给 `N/A + reason`。
- **console**：`consoleErrors[state]` 为空才 PASS（断言函数遇到任何 console.error 会直接抛错）。
- **证据**：`evidenceIndex[state]` 含文件路径与 sha256；`environment` 含 sha/theme/viewport/locale/dark。

截图哈希规则与例外：

- 所有可视觉区分的 BEFORE/AFTER 对哈希不同；矩阵 210 张截图由 `verify.cjs` 逐文件校验 sha256。
- 4 个瞬时 busy 点（`ov-refresh-env`、`src-refresh`、`int-selfcheck`、`log-refresh`）在 LuCI 同步重渲染后没有稳定 busy 帧，BEFORE/AFTER 相同；已在 `assertions.loading.screenshotNote` 说明，并用同步 DOM 断言记录 `disabled=true / aria-busy=true`。
- `oc-backup-retry/error` 初始即错误态，BEFORE/AFTER 相同；已在 `note.errorScreenshot` 说明，仍断言 alert/details 与 server 状态不变。

`phase-f/scripts/verify.cjs` 退出码：**0**（51 点、121 PASS、0 FAIL、225 证据条目、48 张缩放/中文截图哈希全不同）。

闭合：**是**。

## 2. 第 7 条：docs 归位与 SHA 绑定

- 7 份 docs 文首统一绑定当前候选 `90dfc13`（证据采集于 `ffa73f6`；`90dfc13` 为 docs-only 证据归档提交，代码树不变）：full audit、issue register、i18n、interaction matrix、visual matrix、remediation plan、phase reports；历史 `2e28db4`/`9adb2d5` 正文保留为基线，不再被当作当前状态。
- 证据元数据：
  - `matrix.json` 每点记录 `environment.sha/theme/viewport/locale/dark`、`evidenceIndex`（文件 + sha256）、`consoleErrors`、`assertions.dom/focus/persistence`。
  - `zoom-zh.json` 每张截图记录 `sha`、`level`/`width`、`page`、`viewportCss`、`interaction`（zoom/reflow/zh）、`consoleErrors`；48 张截图哈希全部不同。
- issue register：P0-01、P1-01/02/03/04 为 **CLOSED — FIXED（90dfc13）** 并附证据；P1-05 为 **PASS-BY-USER-DECISION**；P2-07（320 tab）与 P2-08（README r6 口径）本轮也已关闭。P2 汇总从 0 closed 变为 3 closed。
- 存放决定：**主仓库 `docs/` 树**，不另建独立 docs 仓库。理由：结论必须与代码 SHA、CI run、包哈希同仓绑定；干净检出即可复核；docs 与代码共用 PR/CI 门禁。`cfip-docs-evidence` 是同一 `.git` 的 linked worktree，不是独立远端。
- 入口：主仓库 `README.md` “相关文档”链接 `docs/audits/next-release-INDEX.md`；INDEX 再列 7 份 docs、phase-f 证据、phase-d/e 与基线截图。
- 归档边界：`ui-refinement-7c13b1d/`（28 MB）、`ui-skill-audit/`（21 MB）、`visual-phase-b/`、`visual-phase-c/`（合计 11.6 MB）保留在 linked worktree；它们不是当前候选证据。当前候选的矩阵、真实缩放、zh 截图全部在主仓库。
- 文档体量：`docs/audits/next-release-evidence/` 35 MB（含 phase-f 23 MB）；不含上述四个历史大归档。

闭合：**是**。

## 3. 第 9 条：真实浏览器缩放

方法：Chrome for Testing 153 真实窗口；打开 `chrome://settings/appearance`，把“网页缩放”下拉设为 125%/150%/200%，再导航到真实 LuCI。`innerWidth` 变为 **1024 / 853 / 640**，DPR 为 **1.25 / 1.5 / 2**。**未使用 CDP `deviceScaleFactor`/`emulate`，也未使用 CSS zoom；** 自动化窗口不响应 Cmd+/Ctrl+ 快捷键，因此用真实设置页下拉，而不再伪称快捷键实测。

三档结果（每档 8 页，共 24 页）：

| 档位 | 有效 CSS 宽度 | 页数 | 横向溢出 | 文字截断 | 焦点环缺失（主内容） | 主内容焦点离屏 | console error |
|---|---:|---:|---:|---:|---:|---:|---:|
| 125% | 1024 | 8 | 0 | 0 | 0 | 0 | 0 |
| 150% | 853 | 8 | 0 | 0 | 0 | 0 | 0 |
| 200% | 640 | 8 | 0 | 0 | 0 | 0 | 0 |
| 320 reflow | 320 | 8 | 0 | 0（见下） | — | — | 0 |

键盘探针：每页从页面起点按 Tab，**第 26 次**进入 `#maincontent`；随后采样 **12** 个主内容控件，焦点环 0 缺失、0 离屏。每页另有 19–20 个 LuCI 全局侧栏链接在窄宽度下处于折叠菜单内、Tab 可聚焦但不可见；这是 Bootstrap 主题的响应式导航行为，不属于插件内容区，已在 `offscreenSidebar` 单独计数。

视觉裁切判定：

- `#tabmenu` 的 `scrollWidth > clientWidth` 但 `overflow-x: visible`，实际 tab 自动换行（200% 截图中 8 个 tab 分两行全部可见），不计为裁切。
- 表格（`.cfi-kv-table`、`.cfi-ip-table`）的滚动宽度来自换行内容，`white-space: normal`，无文字截断。
- 320 下 Sources 的 Built-in Sources 下拉闭合态以省略号显示 2 项；完整 option 文本仍在 DOM，展开可选择，属于 cbi-dropdown 收起态；已作为观察记录在 P2-07。

系统字体放大：当前容器没有可切换的桌面字体缩放会话，无法做真实 OS 字体放大；以 320 reflow + 200% 页面缩放覆盖等效窄宽度，未宣称系统字体实测。

证据：`phase-f/zoom-zh/zoom-{125,150,200}-*.png`（24 张）、`reflow-320-*.png`（8 张）、`zoom-zh.json`。

闭合：**是**（320 的 2 项下拉省略号为已记录的非阻断观察）。

## 4. 第 10 条：zh_cn 真实渲染

方法：容器 `luci.main.lang=zh_cn` + 插件 `cloudflare-ip.zh-cn.lmo`；真实 Chromium 在 375 与 1280 各重采 8 页（16 页），等待视图加载完成后取 `#maincontent` 全文检查。

结果（16/16）：

- 英文残留：**0**（黑名单含 Service Control、Save & Apply、Rill Intelligence、Measurement Policy 等 16 项）
- msgid 泄漏：**0**（无 `_(`、`%s`、`msgid`）
- 菜单缺失：**0**（概览/设置/候选 IP 来源/智能优选/高级/日志与记录）
- 期望中文标题缺失：**0**（8 页逐页关键词）
- 页面横向溢出：**0**
- 非下拉文字截断：**0**
- console error：**0**

证据：`phase-f/zoom-zh/zh-375-*.png`、`zh-1280-*.png`、`zoom-zh.json`。

闭合：**是**。

## 5. 门禁↔CI 漂移治理

新增 CI 脚本（`host-contract` job）：

- `tests/openclash-rpc-contract.sh`
- `tests/openclash-legacy-service-guard.sh`
- `tests/openclash-url-migration.sh`
- `tests/openclash-ruby-precheck.sh`
- `tests/openclash-ruby-precheck.cjs`

新增一致性门禁：`tests/ci-test-inventory.py`（CI `workflow-lint` job 执行）。它遍历 `tests/` 下所有 `.sh/.py/.cjs`，解析全部 workflow 的显式路径与 glob；未接入且未登记理由即 exit 1。

盘点结果：**254** 个本地测试文件，**247** 个在 CI，**7** 个脚本登记排除，**0** 个遗漏。逐行清单：`phase-f/gate-inventory.tsv`（script → in_ci → CI job → 理由）。

按 CI job 的分布：

| CI job | 覆盖脚本数 |
|---|---:|
| `ci.yml:host-contract` | 204 |
| `ci.yml:legacy-contract` | 26 |
| `ci.yml:rill-runtime-integration` | 4 |
| `ci.yml:rootfs-contract` | 3 |
| `ci.yml:openwrt-package` | 3 |
| `real-luci-ui.yml:real-luci-ui` | 2 |
| `ci.yml:rpc-luci-contract` | 2 |
| `ci.yml:i18n-contract` | 2 |
| `ci.yml:evidence-manifest` | 2 |
| `ci.yml:workflow-lint` / `real-cfst-smoke` / `package-migration` / `release.yml:collect` | 各 1 |

7 个排除项：

| 脚本 | 原因 |
|---|---|
| `tests/publisher-procd-rebind.sh` | 需要 live procd/uhttpd 与可绑定 loopback；当前 CI 不启动 init |
| `tests/publisher-uhttpd-readback.sh` | 需要 live uhttpd 监听；rootfs-contract 不启动 init |
| `tests/real-package-identity.py` | 需要已下载 SDK 包；openwrt-package/migration job 已覆盖同产物 |
| `tests/package-identity-contract.py` | 由 `package-release-bump-contract.sh` 传递执行（host-contract） |
| `tests/openclash-rpc-render.cjs` | 由 `openclash-rpc-contract.sh` 调用 |
| `tests/package_contract_fixtures.py` / `tests/helpers/flock-kernel.py` | fixture 模块 / 被 shell 测试 import 的 helper |

退出码：`python3 -B tests/ci-test-inventory.py` = **0**；`actionlint` = **0**；`node --check matrix.cjs/zoom-zh.cjs/verify.cjs` = **0**；`node phase-f/scripts/verify.cjs` = **0**。

闭合：**是**。

## 6. CI 与分支

- 代码候选：`90dfc13`（`ffa73f6` + docs 证据归档提交；代码树与 `ffa73f6` 相同）。
- 代码证据 SHA `ffa73f6` 的 exact-SHA CI：
  - PR CI **41865842245**：success（全部 20 个 job success）
  - push CI **41865829195**：success
  - Real LuCI UI Gate **41865842265**：success
- 当前候选 `90dfc13` 的 exact-SHA CI：
  - PR CI **41883367845**：success
  - push CI **41883717485**：success
  - Real LuCI UI Gate **41883367585**：success
- 阶段 G 收口提交为 docs-only，其 exact-SHA CI 见阶段 G 报告与交付消息。
- 未合并、未打 tag、未建 Release、未改 release-channel。

## 7. 仍开放

- 跨仓 `sync-rill.yml` 真实 PR 证据：仍待用户裁决；保持 `da8389f`，不计入本轮 4 条。
- 发布动作（merge/tag/Release/channel）：按规则只能由用户单独授权。
- `publisher-procd-rebind`/`publisher-uhttpd-readback` 若要进 CI，需要单独的 live OpenWrt init job。
- LuCI 全局侧栏在 640/853/1024 有效宽度下折叠菜单内的 19–20 个链接：主题行为，插件主内容键盘可达性不受影响。
- 320 下 Built-in Sources 下拉闭合态省略号：cbi-dropdown 标准收起态，完整文本在 DOM；非阻断。
