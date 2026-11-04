# Next Release Full Audit — 2e28db4 baseline

> 当前候选：`audit/ui-skill-review` / `ffa73f6`（PR #25）。本文保留阶段 A 的 2e28db4 审计正文与复现；缺陷状态与修复证据以 `next-release-issue-register.md`（已更新到 ffa73f6）和 `next-release-phase-f-report.md` 为准。

## 1. 审计基线

| 项 | 值 |
|---|---|
| 仓库 | `hello-yunshu/luci-app-cloudflare-ip` |
| 基线分支 | `main`（实际最新代码） |
| 基线 SHA | `2e28db4b5cdc221897bbe98ff78fbe7235098e53` |
| 工作树 | clean（审计只新增 `docs/audits/**` 与 `docs/plans/**`，未改产品代码） |
| 时间 | 2026-11-03（Asia/Shanghai） |
| tag / Release | `v2.6.0-6` → `2e28db4`；GitHub Release 为 **Pre-release** |
| 当前包版本 | `2.6.0-r6`（`PKG_VERSION=2.6.0`，`PKG_RELEASE=6`） |

### 基线取舍与冲突

提示词要求“不得把 main 当作最新开发代码”，但真实仓库状态是：

- `main` HEAD `2e28db4` 含 PR #21 的 UCI 引号修复与 tag gate 修复；
- PR #18 head `becb327`（`codex/reliability-contracts`）落后 main 4 个提交；
- PR #18 仍 OPEN、mergeable，但不是本轮最新代码。

因此本轮采用 **main HEAD 作为审计基线**，并把 PR #18 的差异单独记录，避免审计漏掉 main 上已合入的修复。该取舍属于对提示词假设的显式修正，已写入本文件；未擅自把 PR #18 视为最新。

### 关联仓库实际 HEAD（审计时点）

| 仓库 | 默认分支 | HEAD | 未合并 PR |
|---|---|---|---|
| `rill-openwrt-packages` | main | `a1245c293605740db3bf49f143ba03f545a89922` | #2（旧 CI PR） |
| `rill-ml` | main | `9602750202f56ed860fc8815bb91e81083d0ffdb` | #50、#51 |
| `luci-app-performance-manager` | main | `d5c42e1867d34ea1aa3013485e713504bd9163aa` | #13 |

当前 `contracts/rill-runtime.json` 的 `openwrtPackage.commit` 与 rill-openwrt main 一致；`preview.commit=da8389f...` 与 rill-ml main `9602750...` 不一致（pin 为历史 preview commit）。这是待审计/待用户决策项，不直接判为缺陷。

证据：`docs/audits/next-release-evidence/baseline-2e28db4.json`、`cross-repo-2e28db4.json`。

## 2. 审计方法与证据级别

- **源码审计**：直接读取 9 个 LuCI JS 模块、`cloudflare-ip.css`、`utils.js`、menu/PO/POT、RPC 后端入口、`ci.yml`、`release.yml`、`sync-rill.yml`、`contracts/rill-runtime.json`。
- **真实 LuCI 运行**：隔离容器 `openwrt/rootfs:x86_64-24.10.8`，LuCI `26.205.85413~cac97ed`，真实 `uhttpd`，真实登录会话，浏览器为 Chromium/Edge；不是 `preview/aurora.html`，不是 `tests/luci-*.cjs` 的假 DOM。
- **视觉矩阵**：3 主题（Bootstrap 原版 / Aurora light / Aurora dark）× 3 主断点（375/768/1280）× 8 页面 = 72 张；另加 320px 与 1280@200% 等效宽度边界共 6 张，总计 **78 张 PNG**。
- **风险复现**：4 项 source-confirmed 风险用加载真实 JS 模块的可执行 harness 复现（`repro-risks.cjs`），输出结构化 JSON；不是只写源码推断。
- **i18n**：从 9 个 JS 模块抽取 `_()` 键，与 POT/zh_Hans 逐项比较，得到 423 个唯一键、88 个缺失；逐文件数据在 `i18n-2e28db4/`。
- **证据级别**：`SOURCE_CONFIRMED`、`REPRODUCED`、`CI_VERIFIED`、`RUNTIME_VERIFIED`、`BLOCKED`、`NOT_RUN`；不把 mock/preview/旧 SHA 证据算 PASS。

## 3. 审计结果概览

| 指标 | 结果 |
|---|---|
| 页面 | 8 个：Overview、Settings、Sources、Intelligence、OpenClash、PassWall、Advanced、Logs & Records |
| 正常态视觉覆盖 | 8 页 × 3 主题 × 3 断点 = 72；边界 6；合计 78 张 |
| 横向溢出 | 78 个截图对应 DOM 度量均为 `overflow=false` |
| 登录/主题错误 | 无截图出现登录页；Aurora dark 26/26 截图为 `data-darkmode=true` |
| 4 项风险复现 | 4/4 已用可执行 harness 复现（见 §5） |
| i18n | 423 个唯一 JS 键；88 个未进入 POT，88 个无 zh 翻译；2 个菜单标题未翻译 |
| 问题分级（本轮可确定） | **P0 1**、**P1 5**、**P2 9**、**P3 2**（详见 issue register） |
| 真实设备/硬件/24h soak | **NOT RUN** |
| 当前结论 | **NO-GO**（阶段 A 交付物已齐，但 P0/P1 未处置，真实设备证据缺失；阶段 B/C 未启动） |

## 4. 真实运行环境

| 项 | 值 |
|---|---|
| 容器 | `cfip-audit-luci`，`openwrt/rootfs:x86_64-24.10.8`，`/sbin/init`，procd PID 1 |
| LuCI | `26.205.85413~cac97ed` |
| 主题 | Bootstrap（原版）；Aurora `1.4.0-r20260920`（IPK，`luci-theme-aurora`） |
| 浏览器 | Microsoft Edge（Chromium `156.0.0.0`）headless，`agent-browser` |
| 路由 | 真实 `/cgi-bin/luci/admin/services/cf_ip/*` |
| 语言 | `luci.main.lang=zh_cn` |
| 控制器 | OpenClash/PassWall 使用可执行 init stub 以暴露页面路由；真实控制器运行 **NOT RUN**（详见 §8） |
| 状态 fixture | `/etc/cf_ip/status.json` 正常态 fixture；服务真实 run 未执行 |

环境限制：容器与宿主机端口映射在 OpenWrt bridge 网络下不可用，最终使用 `--network host` + `127.0.0.1:18080` 运行真实 uhttpd；容器 DNS 不用于视觉审计。该限制不影响 HTML/CSS/JS/真实 LuCI 渲染，但影响真实代理网络/控制器状态。

## 5. 最严重问题（P0/P1）

### P0-01 OpenClash 删除备份假成功

- **文件/行**：[`openclash.js`](../../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/openclash.js) L162–L167。
- **当前行为**：
  ```js
  callOcDeleteBackup(backup.id).then(function(result) {
      if (result && result.error) { ... error ... }
      else { ui.addNotification(... _('Backup deleted') ...); location.reload(); }
  })
  ```
  后端返回 `{success:false}` 且没有 `error` 时，UI 仍显示 “Backup deleted” 并刷新页面。
- **复现**：`node docs/audits/next-release-evidence/repro-2e28db4/repro-risks.cjs`；输出 `openclash_delete.false_success=true`、`notifications[0].text="Backup deleted"`、`reload_calls=1`，而后端响应为 `{success:false}`。
- **影响**：删除备份是破坏性操作；假成功会让用户以为旧备份已清理，实际可能仍保留；也可能掩盖权限/存储错误。
- **期望**：只有 `result.success === true` 才提示成功；`success:false`、空对象、缺字段都走错误分支；不得 reload 掩盖失败。
- **最小修复**：`if (!result || result.success !== true || result.error) { error; no reload } else { success }`。
- **测试**：真实 RPC 路由 fixture + 本 harness；覆盖 `{"success":false}`、`{}`、`{success:true}`、`{error:"..."}`。
- **主题/断点**：全部；确认框在 LuCI modal 内，需同时验证 375/768/1280 与 Bootstrap/Aurora。
- **跨仓**：无。
- **回退**：纯 UI 判定；回退为不显示假成功，不影响 UCI/配置文件。
- **状态**：**OPEN — REPRODUCED**。

### P1-01 RPC 失败被折叠为“未安装/空”

- **文件/行**：
  - [`openclash.js`](../../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/openclash.js) L26–L27：`callCheckEnv().catch(function(){return {};})`、`callOcListBackups().catch(function(){return {success:false,backups:[]};})`。
  - [`sources.js`](../../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/sources.js) L18：`callRegistry().catch(function(){return {};})`、`callStatus().catch(function(){return {};})`。
- **当前行为**：RPC 超时/网络错误/权限错误被当成“组件未安装”或“没有备份/没有来源”；页面没有错误提示、重试入口或诊断码。
- **复现**：harness 让 `callCheckEnv` 与 `callOcListBackups` reject；OpenClash 页面文本为 “OpenClash Not Found”；Sources 页面输出空表、`rows=0`、`error_visible=false`。
- **影响**：用户会按“未安装/无数据”做错误操作；需区分 `UNAVAILABLE / ERROR / NOT_INSTALLED / EMPTY`。
- **期望**：显式错误状态、中文说明、重试按钮、原始诊断码可展开；不得静默 empty。
- **最小修复**：保留异常对象，渲染 `RPC unavailable` 状态；对 `success:false` 展示错误而非空列表。
- **测试**：ubus/RPC reject、`{}`、`success:false`、无权限；每页至少一个 fixture。
- **状态**：**OPEN — REPRODUCED (JS harness)**。

### P1-02 Sources 刷新丢失未保存编辑

- **文件/行**：[`sources.js`](../../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/sources.js) L74。
- **当前行为**：刷新成功后 500ms 调用 `location.reload()`，没有保存/草稿/脏表单拦截。
- **复现**：harness 设置 `draft_before='modified-but-unsaved'`，调用刷新按钮；`reload_calls=1`、`save_calls=0`、`draft_after` 仍为同一未保存值，页面刷新会丢弃表单编辑。
- **影响**：用户在 Sources 编辑自定义来源/预算时点 Refresh，未保存内容丢失。
- **期望**：检测 dirty state，提示“刷新会丢失未保存修改”，提供保存/取消；或刷新只更新状态区，不 reload 整个页面。
- **测试**：dirty/clean 两种状态、刷新成功/失败、取消/确认；真实浏览器操作。
- **状态**：**OPEN — REPRODUCED (JS harness)**。

### P1-03 Rill reset 只提示不刷新状态

- **文件/行**：[`intelligence.js`](../../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/intelligence.js) L293–L299。
- **当前行为**：`callReset` 成功后只 `addNotification`，没有重新拉取 status/diagnostics，也没有 reload 或 generation readback。
- **复现**：harness 的 status generation=1；`callReset` 返回 `{success:true}`；输出 `notifications[0].text="Rill learning state was reset."`、`reload_calls=0`、`status_generation_after=1`、`stale_status=true`。
- **影响**：用户以为已重置，页面仍显示旧代数/旧证据；后续操作可能使用旧 generation。
- **期望**：成功后重新读取 status 或局部刷新状态区；失败/超时明确提示；reset 与 status 的代数一致。
- **测试**：真实 RPC reset + status；成功、`success:false`、超时、generation mismatch。
- **状态**：**OPEN — REPRODUCED (JS harness)**。

### P1-04 简体中文缺口

- **数据**：423 个唯一 JS key；88 个未进入 POT；88 个无 zh_Hans 翻译；菜单 `Candidate IP Sources`、`Intelligence` 未翻译。
- **证据**：`i18n-2e28db4/i18n-data.json`、`i18n-missing.tsv`；真实截图可见英文菜单（全部 78 张截图）。
- **影响**：中文页面混用英文菜单/说明，动态状态可能显示机器码；不满足中文全链路。
- **期望**：POT/zh/en 完整覆盖；菜单 key；动态状态映射表；语言 CI gate。
- **状态**：**OPEN — MEASURED / RUNTIME_CONFIRMED (菜单)**。

### P1-05 真实设备/硬件/24h soak 证据缺失

- **证据**：`docs/REAL_DEVICE_VALIDATION.md` 明确物理设备未执行；历史 G6/G7 设备候选为 `3bf0ec1`，不是当前 `2e28db4`。
- **影响**：不能满足最终 GO 的真机/硬件/长期稳定性条件；容器/VM 不能替代物理设备。
- **期望**：用户提供设备或明确接受容器/VM 边界；记录 firmware/arch/package/Runtime/proxy 证据。
- **状态**：**NOT_RUN**。

## 6. 视觉与主题审计

### 6.1 三主题 × 三断点

- **Bootstrap 原版**：`/luci-static/bootstrap`，真实 LuCI 页面，78 张中的 26 张。
- **Aurora light**：`luci-theme-aurora 1.4.0`，`localStorage aurora.theme=light`，26 张。
- **Aurora dark**：`aurora.theme=dark`，26 张；所有 Aurora dark 截图 `data-darkmode=true`。
- **断点**：375×900、768×900、1280×900；320×900 与 640×900（1280@200% 有效宽度）边界。

结果：
- 78 张全部 `overflow=false`；无登录页、无空白页（最小 `textLen=212`）。
- 320px Overview 顶部导航 tab 文本被裁切（`Candidate IP` 右侧截断），页面本身无横向滚动；是 P2 边界问题。
- 640px Sources 在 200% 等效宽度下仍可读；MultiValue 两个来源可见；无横向 overflow。
- Aurora dark 375 Sources 的 MultiValue 文本在缩略预览中不易辨认，但放大/像素检查确认标签真实存在且对比可见，不列为缺陷。

### 6.2 源码风险复核

| 风险 | 当前状态 | 证据 |
|---|---|---|
| 600/900px media query 与侧栏/容器宽度 | 仍存在 | [cloudflare-ip.css] L383–L431 |
| Overview 内联 CSS 与共享 CSS 重复 | 仍存在 | [overview.js] L191–L283；共享 `.cfi-stats-grid`/600px |
| `data-darkmode` + `prefers-color-scheme` + 硬编码色 | 仍存在 | [cloudflare-ip.css] L16–L35 |
| 9–10px 日志字号 | 仍存在 | [cloudflare-ip.css] L190、L421 |
| `confirm()` 与 LuCI modal 割裂 | 仍存在 | [diagnostics.js] L146、[intelligence.js] L288 |
| reduced-motion | 未发现处理 | CSS 有 `cfi-pulse` 动画 |
| MultiValue/下拉 375 遮挡 | 未复现为缺陷；标签存在 | 78 张截图 + 像素检查 |
| 依赖缺失早返回样式 | 未确认 | 需专项 fixture |
| Intelligence DummyValue 信息架构 | 未完成专项 | 页面 164 个 i18n key、306 行 |
| 统一 footer/卡片/表格 | 部分存在；自定义 footer | 截图与 CSS |

### 6.3 对比度/WCAG

- **未完成全量 WCAG AA 自动扫描**：`NOT_RUN`；不能写 PASS。
- 旧 Bootstrap overview 证据（`docs/audits/g4-g5-evidence/overview-contrast-fix.json`）为旧 SHA `0d8460f`，不能代表当前 `2e28db4` 或 Aurora。
- 当前截图为真实运行，但颜色对比仍需逐页扫描/人工判定；列入 P2 证据缺口。

## 7. 交互审计摘要

完整 8×7 矩阵见 `next-release-interaction-matrix.md`。覆盖状态：

- 正常态：8/8 页面有真实截图（PASS）。
- 空/未安装：OpenClash 无备份、Sources 无自定义来源、Intelligence Rill 未安装/禁用、Diagnostics 空日志有真实页面状态。
- RPC 失败：OpenClash/Sources 已用 harness 复现错误折叠（FAIL），其余页面未注入。
- 表单保存/应用/回读/重启：Settings 的 invalid/valid 保存尝试未得到可判定结果；真实 `uci` 未改变，标记 NOT-RUN（自动化未捕获 validation bubble）。
- 弹窗/确认：OpenClash 删除 modal 在 harness 中真实打开；浏览器真实备份列表为空，未执行真实删除；Diagnostics/Rill 的 `confirm()` 被浏览器自动化自动 dismiss，标记 BLOCKED/NOT-RUN。
- 键盘/焦点/触控：未执行；NOT-RUN。
- 未保存保护：Sources 刷新 reload 已复现（FAIL）。

## 8. 跨仓、打包与 CI

### Rill

- `contracts/rill-runtime.json`：
  - openwrtPackage `a1245c2` 与 rill-openwrt main 一致；
  - preview `da8389f` 与 rill-ml main `9602750` 不一致；
  - stable upstream `b990cd7` 与 preview 不可混用。
- rill-ml 有 #50（security compatibility）与 #51（dependabot）；是否跟随新 HEAD/重新资格需用户决定。
- `sync-rill.yml` 使用 main 与 rill-openwrt main；最近 schedule run `41593205753` success，但日志为 `No qualified Runtime contract change.`，未验证实际创建 PR 的变更路径。
- Performance Manager PR #13 处理 Runtime ownership；Cloudflare IP 与 PM 的 Runtime/Preview 冲突策略仍缺架构结论。

### 打包/发布

- r6 Release 为 pre-release；`release-channel.json` 为 `stable`；`release.yml` 有 stable 自动发布保护；`Build and Release` run `41588532619` 失败是设计保护，不应改为绿。
- 当前 Release 资产与 r6 tag 绑定；下一版本若改代码，不能复用 r6 tag/assets；版本决定需用户。
- r6 IPK/APK 已通过当前 CI（run `41586123833`）与严格预检；但这是 r6 发布证据，不是 next-release UI/设备证据。

### CI

- main run `41586123833` success；PR #18 checks success；`sync-rill` run success（no-change）。
- 无 i18n/`msgfmt` gate；无 playwright/puppeteer/jsdom 真实 UI gate；`tests/luci-*.cjs` 是假 DOM/form fixture，不能替代真实 LuCI/Aurora。
- 旧 G4/G5/G6/G7 证据 SHA 不是当前 `2e28db4`；只能作为历史线索。

## 9. 阶段 A 交付物

| 文件 | 状态 |
|---|---|
| `docs/audits/next-release-full-audit.md` | 本文件 |
| `docs/audits/next-release-issue-register.md` | 已完成 |
| `docs/audits/next-release-interaction-matrix.md` | 已完成（含 NOT-RUN/BLOCKED） |
| `docs/audits/next-release-visual-matrix.md` | 已完成（78 张截图） |
| `docs/audits/next-release-i18n-report.md` | 已完成 |
| `docs/plans/next-release-remediation-plan.md` | 已完成 |
| `docs/audits/next-release-evidence/` | 已完成（截图/日志/JSON/harness） |

## 10. 结论

- **阶段 A 交付物已齐**；4 项 source-confirmed 风险均已用可执行 harness 复现；视觉正常态覆盖 8 页 × 3 主题 × 3 断点，并完成 320/200% 边界抽查。
- **NO-GO**：P0-01 与 P1-01/02/03/04 仍未处置；真实设备/硬件/24h soak 未执行；交互矩阵中仍有大量 NOT-RUN/BLOCKED。
- 未修改产品代码、未创建 tag/Release、未 push 产品改动、未触发/重跑 Actions。
- 需用户决定：新版本号（r7 或 2.7.0）、视觉方向（回退 v1.8.3 原版 vs 保留 2.x 语言只做收口）、是否接受容器/VM 替代物理设备、rill-ml pin 是否跟随新 HEAD。
