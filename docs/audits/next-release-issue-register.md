# Next Release Issue Register — 2e28db4 baseline, released v2.6.0-8, post-release findings

审计基线：`main` / `2e28db4b5cdc221897bbe98ff78fbe7235098e53`；发布身份：`v2.6.0-8` → `4cbad4d2bb68315ed22b4c702effb78c1cd03ffb`（Pre-release）；修复发布 `v2.6.0-9`（Pre-release，tag 目标以 Release 为准）。证据目录：`docs/audits/next-release-evidence/`。历史正文保留阶段 A 复现，状态列已更新到发布后修复。

## 最终合并 SHA

| 阶段 | SHA |
|---|---|
| v2.6.0-8 tag 目标 | `4cbad4d2bb68315ed22b4c702effb78c1cd03ffb` |
| 阶段 I 清理 merge | `ae4282f7f4c543a06693925a9d49098891d85df8` |
| 阶段 J 自检 merge | `8257a3d2979cbc187cc0677fc61f81bde3ea0c04` |
| 阶段 K（r9） | 以 `v2.6.0-9` tag 为准（不在文档中写死合并 SHA） |

## 1. 汇总

| 优先级 | 数量 | 状态分布 |
|---|---:|---|
| P0 | 1 | CLOSED / FIXED |
| P1 | 6 | 5 CLOSED / FIXED；1 PASS-BY-USER-DECISION |
| P2 | 9 | 3 CLOSED；6 OPEN / SOURCE_CONFIRMED |
| P3 | 2 | OPEN / SOURCE_CONFIRMED |

> 本表保留阶段 A 的复现结构；P0/P1 状态已按发布后修复更新。P1-06 是发布后由 live 容器 fixture 发现的真实运行时缺陷，已在 `main` 修复，**未包含在 v2.6.0-8 资产中**，需要下一次发布才能到达用户。P2-07/P2-08/P2-09 已关闭，其余 P2/P3 仍未关闭。

## 2. 索引

| ID | 优先级 | 标题 | 状态 | 证据 |
|---|---|---|---|---|
| P0-01 | P0 | OpenClash 删除备份假成功 | CLOSED — FIXED | `phase-d/openclash/`、`phase-e/` |
| P1-01 | P1 | RPC 失败被当作未安装/空 | CLOSED — FIXED | `phase-e/before|after/`、`tests/luci-raw-error-contract.cjs` |
| P1-02 | P1 | Sources 刷新丢失未保存编辑 | CLOSED — FIXED | `ui-refinement-matrix`、`tests/luci-refresh-error.cjs` |
| P1-03 | P1 | Rill reset 不刷新状态 | CLOSED — FIXED | `phase-d/intelligence/`、`tests/luci-view-bindings.cjs` |
| P1-04 | P1 | 简体中文 88 个 key + 2 个菜单缺失 | CLOSED — FIXED（516 keys / 552 entries） | `tests/i18n-contract.py`、`phase-f/zoom-zh/` |
| P1-05 | P1 | 真实设备/硬件/24h soak 证据缺失 | PASS-BY-USER-DECISION (2026-11-04) | `next-release-phase-d-report.md` §Follow-up |
| P1-06 | P1 | publisher 就绪检查在 curl 8.22.0 下恒定失败 | CLOSED — FIXED（main，未进入 r8 资产） | `next-release-evidence/phase-i/publisher-fixture-rewrite.md` |
| P2-01 | P2 | 600/900px media query 与容器宽度风险 | OPEN — SOURCE_CONFIRMED | `cloudflare-ip.css` |
| P2-02 | P2 | Overview 内联 CSS 重复 | OPEN — SOURCE_CONFIRMED | `overview.js` |
| P2-03 | P2 | 深色主题变量双来源/硬编码 | OPEN — SOURCE_CONFIRMED | `cloudflare-ip.css` |
| P2-04 | P2 | 日志 9–10px 字号 | OPEN — SOURCE_CONFIRMED | `cloudflare-ip.css` |
| P2-05 | P2 | `confirm()` 与 LuCI modal 割裂 | OPEN — SOURCE_CONFIRMED | `diagnostics.js` / `intelligence.js` |
| P2-06 | P2 | 缺少 reduced-motion 处理 | OPEN — SOURCE_CONFIRMED | `cloudflare-ip.css` |
| P2-07 | P2 | 320px 顶部导航 tab 裁切 | CLOSED — VERIFIED（320 tab 换行，8 项全部可见） | `phase-f/zoom-zh/reflow-320-*.png` |
| P2-08 | P2 | README 仍称 r6“正在重新资格化” | CLOSED — DOC UPDATED（90dfc13） | `README.md` |
| P2-09 | P2 | rill-ml pin 落后 main，存在未合并 PR | CLOSED — 保持 `da8389f`，理由见 `phase-d/openclash-ruby/cross-repo.md` | `cross-repo.md` |
| P3-01 | P3 | 缺少统一中文术语表 | OPEN — SOURCE_CONFIRMED | `i18n-2e28db4/` |
| P3-02 | P3 | 设计 token/footer 一致性待收口 | OPEN — RUNTIME/视觉 | 78 张截图 |

## 3. P0

### P0-01 OpenClash 删除备份假成功

- **风险**：破坏性操作假成功，用户误以为备份已删除。
- **当前行为**：[`openclash.js`](../../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/openclash.js) L162–L167 只判断 `result.error`；`{success:false}` 无 error 时仍提示 `Backup deleted` 并 `location.reload()`。
- **复现**：
  1. `cd /Users/yunshu/Documents/GitHub/luci-app-cloudflare-ip`
  2. `node docs/audits/next-release-evidence/repro-2e28db4/repro-risks.cjs`
  3. 读取 `openclash_delete`：`row_delete_buttons=1`、`modal_delete_buttons=1`、`backend={success:false}`、`notifications[0].text="Backup deleted"`、`reload_calls=1`、`false_success=true`。
- **影响**：旧备份可能仍存在，或权限/存储失败被掩盖；用户可能据此做错误清理/保留决策。
- **期望**：`success !== true`、空对象、缺字段、`error` 均走错误提示；成功才 reload。
- **最小修复**：条件改为 `if (!result || result.success !== true || result.error)`；错误提示保留 `result.error || _('Unknown')`；不 reload。
- **测试**：harness 四种响应；真实 ubus RPC route fixture；375/768/1280 × 三主题的 modal。
- **跨仓/回退**：无；纯 UI 判定，回退不影响 UCI。
- **状态**：CLOSED — FIXED（`90dfc13`）。`openclash.js` 只在 `success === true` 时刷新成功态；失败保留错误与备份文件。证据：`phase-d/openclash/delete-success.json`、`delete-failure` 截图、`phase-e/` 技术详情。

## 4. P1

### P1-01 RPC 失败被当作未安装/空

- **风险**：网络/权限/RPC 超时被误判为组件未安装或数据为空，用户按错误状态操作。
- **当前行为**：
  - [`openclash.js`](../../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/openclash.js) L26–L27：`callCheckEnv().catch(function(){return {};})`、`callOcListBackups().catch(function(){return {success:false,backups:[]};})`。
  - [`sources.js`](../../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/sources.js) L18：`callRegistry().catch(function(){return {};})`、`callStatus().catch(function(){return {};})`。
- **复现**：harness 让 `callCheckEnv`/`callOcListBackups` reject，OpenClash 页面文本变为 `OpenClash Not Found`；Sources 页面 `rows=0`、`error_visible=false`。
- **影响**：误装/误删/误判“无数据”；没有重试和诊断码。
- **期望**：四态 `UNAVAILABLE / ERROR / NOT_INSTALLED / EMPTY`；中文说明 + 重试 + 可展开原始错误。
- **最小修复**：catch 保留 `{_error:true}`；渲染错误空状态；对 `success:false` 显示 error，不显示空列表。
- **测试**：RPC reject、`{}`、`success:false`、权限错误；OpenClash/Sources 各一组。
- **状态**：CLOSED — FIXED（`90dfc13`）。RPC 失败与未安装/空数据分离，错误态显示人类说明 + 可展开技术详情。证据：`phase-e/before/diagnostics.png`、`phase-e/after/diagnostics.png`、`tests/luci-raw-error-contract.cjs`。

### P1-02 Sources 刷新丢失未保存编辑

- **风险**：刷新成功会 reload 整页，未保存的自定义来源/预算编辑丢失。
- **当前行为**：[`sources.js`](../../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/sources.js) L74，刷新成功后 `setTimeout(function(){location.reload();},500)`。
- **复现**：harness 设置 `draft_before='modified-but-unsaved'` 并点击 Refresh；`reload_calls=1`、`save_calls=0`、`draft_after` 仍为同一值（reload 会丢弃）。
- **影响**：用户输入丢失；重试成本与误操作风险。
- **期望**：dirty state 拦截/提示；刷新只更新状态区，或在保存后 reload。
- **最小修复**：监听表单 dirty；reload 前 `confirm`；或把 refresh 结果局部渲染。
- **测试**：dirty/clean、刷新成功/失败、取消/确认、真实浏览器。
- **状态**：CLOSED — FIXED（`90dfc13`）。刷新只更新状态区，不 reload，未保存草稿保留。证据：`tests/luci-refresh-error.cjs`、`phase-f/matrix/src-refresh-*`。

### P1-03 Rill reset 不刷新状态

- **风险**：重置成功提示后，页面仍显示旧代数/旧证据；用户误以为已生效。
- **当前行为**：[`intelligence.js`](../../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/intelligence.js) L293–L299 只 `addNotification`，无 status/diagnostics 重读。
- **复现**：harness status generation=1；`callReset` 返回 `{success:true}`；`notifications[0]="Rill learning state was reset."`、`reload_calls=0`、`status_generation_after=1`、`stale_status=true`。
- **影响**：后续 reset/qualification 使用旧代数；页面状态与后端不一致。
- **期望**：成功后重新读取 status 或刷新状态区；失败/超时明确提示；generation readback。
- **最小修复**：成功后调用 `callStatus()` 并局部更新；或 reload；错误不提示成功。
- **测试**：真实 RPC reset + status；成功/失败/超时/generation mismatch。
- **状态**：CLOSED — FIXED（`90dfc13`）。成功后重载并反映状态；`ev.currentTarget`/form.Button 事件参数已修复。证据：`phase-d/intelligence/intelligence.json`、`tests/luci-view-bindings.cjs`。

### P1-04 简体中文缺口

- **数据**：423 个唯一 JS key；88 个不在 POT；88 个无 zh_Hans；菜单 `Candidate IP Sources`、`Intelligence` 缺失。
- **逐文件缺失**：Intelligence 54、Advanced 8、Settings 8、Sources 6、OpenClash 6、PassWall 3、Overview 2、Diagnostics 1、Utils 0。
- **证据**：`i18n-2e28db4/i18n-data.json`、`i18n-missing.tsv`；78 张真实截图菜单仍显示英文。
- **影响**：中文不完整；动态状态可能显示机器码；术语不一致。
- **期望**：POT/zh/en 全覆盖；菜单 key；动态映射；语言 CI gate。
- **状态**：CLOSED — FIXED（`90dfc13`）。当前 516 keys（JS 507 + menu 9），POT/zh_Hans/en 各 552 条；`i18n-contract.py` 与 `i18n-dynamic-contract.py` PASS。真实 zh 渲染见 `phase-f/zoom-zh/zh-375-*`、`zh-1280-*`。

### P1-05 真实设备/硬件/24h soak 证据缺失

- **风险**：当前只有容器/VM 真实 LuCI 证据；物理设备、硬件矩阵、24h soak 未执行。
- **证据**：`docs/REAL_DEVICE_VALIDATION.md` 明确物理设备未执行；历史设备候选 `3bf0ec1` 不是 `2e28db4`。
- **影响**：最终 GO 条件不满足；不能把容器当硬件。
- **期望**：用户提供设备或明确接受边界；记录 firmware/arch/package/proxy/rollback。
- **状态**：PASS-BY-USER-DECISION（2026-11-04）。用户确认“真机 + 24h soak 之前已经做过了，直接 pass”；未补造新记录。历史设备验收见 `g6-g7-evidence/device-acceptance-3bf0ec1.json`，历史 soak 记录为 SKIPPED/NOT STARTED，故本状态仅依据用户裁定。

### P1-06 publisher 就绪检查在 curl 8.22.0 下恒定失败

- **发现**：2026-11-05 在真实 OpenWrt 24.10.8 容器中重写 `tests/publisher-*.sh` 时发现，`publisher.sh` 的 `--connect-timeout 1 --max-time 1` 被当前 feed 的 `curl 8.22.0-r1` 拒绝：`curl: (28) remaining timeout of 999 too small to resolve via SIGALRM method`。真实 procd/uhttpd 已运行、文件可 200 返回，但 `cfip_publisher_wait_ready` 恒失败，发布器无法进入 ready。
- **影响**：`v2.6.0-8` 及更早资产在安装当前 curl 包的设备上 publisher 不可用；此前阶段 I 把失败误判为 fixture 未启动服务。
- **修复**：`publisher.sh` 两处就绪/端点检查改为 `--connect-timeout 2 --max-time 2`；fixture 用真实 procd/uhttpd 并在 24.10.8 容器跑通；新增 CI job `publisher-runtime`。
- **证据**：`next-release-evidence/phase-i/publisher-fixture-rewrite.md`；本机复现：`curl --max-time 1` → rc 28，`--max-time 2` → 200。
- **状态**：CLOSED — FIXED（`main`）。**未包含在 r8 资产**；下一次发布才到达用户。

## 5. P2

### P2-01 600/900px media query 与容器宽度风险
- **文件**：[`cloudflare-ip.css`](../../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/cloudflare-ip/cloudflare-ip.css) L383–L431。
- **当前**：仍按 viewport 600/900 切换 stats grid、表单单列、表格块状；LuCI 侧栏占用后有效内容宽度更窄。
- **风险**：在 768/900 附近侧栏展开时可能提前/延后切换；旧浏览器无 container query。
- **证据**：SOURCE_CONFIRMED；本轮 375/768/1280 无 overflow，但未覆盖侧栏折叠组合。
- **建议**：评估容器查询或按内容宽度断点；保留旧浏览器回退；补 768 侧栏开/合截图。

### P2-02 Overview 内联 CSS 重复
- **文件**：[`overview.js`](../../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/overview.js) L191–L283。
- **当前**：内联 `.cfi-stats-grid`、600px 规则与共享 CSS 重复；覆盖次序依赖加载。
- **风险**：主题/断点表现不一致；难维护。
- **建议**：移入共享 CSS 或明确局部变量；补样式优先级测试。

### P2-03 深色主题变量双来源/硬编码
- **文件**：[`cloudflare-ip.css`](../../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/cloudflare-ip/cloudflare-ip.css) L16–L35。
- **当前**：`data-darkmode`、`prefers-color-scheme`、硬编码色同时存在。
- **风险**：系统深色偏好与 LuCI/Aurora 实际主题不一致时误配色。
- **证据**：Aurora dark 26 张 `data-darkmode=true`；源码仍保留 media fallback。
- **建议**：以 LuCI/Aurora 的 theme class 为准；fallback 仅在无主题 class 时生效；补对比度扫描。

### P2-04 日志 9–10px 字号
- **文件**：[`cloudflare-ip.css`](../../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/cloudflare-ip/cloudflare-ip.css) L190（10px）、L421（9px）。
- **风险**：375/768 下诊断/日志可读性差；长 JSON 难复制。
- **建议**：提高到可读字号（≥12px 或 rem），保留滚动/等宽/复制；三主题截图对比。

### P2-05 `confirm()` 与 LuCI modal 割裂
- **文件**：[`diagnostics.js`](../../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/diagnostics.js) L146；[`intelligence.js`](../../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/intelligence.js) L288。
- **风险**：外观/键盘体验不一致；自动化与可访问性差。
- **建议**：统一 LuCI modal；保留 Esc/Enter/Tab；补确认/取消测试。

### P2-06 缺少 reduced-motion 处理
- **文件**：`cloudflare-ip.css` 的 `cfi-pulse` 动画。
- **风险**：触摸/低动态偏好用户体验；无 `prefers-reduced-motion` 分支。
- **建议**：加入 reduced-motion 禁用/弱化动画；三主题验证。

### P2-07 320px 顶部导航 tab 裁切
- **证据**：`visual-2e28db4/aurora-light/320x900/overview.png` 等 3 张；`Candidate IP` 右侧被裁切，页面 `overflow=false`。
- **风险**：极窄屏导航项不可读/不可点；虽然页面无横向滚动，但 tab 容器裁切。
- **建议**：320 下 tab 换行/横向滚动/菜单折叠；补 320 全页交互。
- **状态（90dfc13）**：CLOSED — VERIFIED。本轮 320 reflow 重采 8 页，tab 自动换行，8 个 tab 全部可见，页面 `overflow=false`；证据 `phase-f/zoom-zh/reflow-320-*.png`。遗留观察：Sources 的 Built-in Sources 下拉在 320 闭合态以省略号显示（2 项），完整 option 文本仍在 DOM，属于 cbi-dropdown 标准收起态，非页面裁切。

### P2-08 README 仍称 r6“正在重新资格化”
- **文件**：`README.md` L39–L40。
- **当前**：README 称 `2.6.0-r6` 是当前审计修复候选、正在重新 CI/预检；实际 r6 Release 已存在（pre-release）。
- **风险**：维护者/用户对发布状态误判。
- **建议**：发布后更新 README 状态；或改为“当前源码版本/最近发布”自动生成。
- **状态（90dfc13）**：CLOSED — DOC UPDATED。README 已改为“r6 已作为 pre-release 发布，其字节对应审计修复前基线；当前源码为 r8 候选，尚未创建 tag/Release”。

### P2-09 rill-ml pin 落后 main，存在未合并 PR
- **证据**：`cross-repo-2e28db4.json`；contract preview `da8389f`，rill-ml main `9602750`；PR #50/#51；Performance Manager #13。
- **风险**：Runtime/Protocol/schema 可能漂移；直接跟随 main 会绕过资格。
- **建议**：逐项比较 pin 与 main 的 API/schema；确认 PR #50 的安全依赖合并与重新资格；用户决定是否跟随。
- **结论（2026-11-04）**：保持 `da8389f`。`da8389f..9602750` 仅 3 个提交、只改 `Cargo.lock`（rand bump），无 API/schema 变化；`a1245c2` 的 Preview 包已通过 `040-wasm-engine-advisory-20261029.patch` 将 Wasmtime 升至 49.0.5，资格 run `41497865089` 绑定该组合；跟随 main 会丢失已资格补丁并需重新资格。证据见 `phase-d/openclash-ruby/cross-repo.md`。

## 6. P3

### P3-01 缺少统一中文术语表
- **证据**：`i18n-2e28db4/`；当前“候选来源/智能优选/Rill 智能/自适应测量”等混用。
- **建议**：建立术语表（Cloudflare IP 优选、候选来源、智能优选、影子模式、辅助模式、资格校验、降级、回滚、测速、备份恢复、运行时、配置已应用）；专有名词保留。

### P3-02 设计 token/footer 一致性
- **证据**：78 张截图；自定义 `--cfi-radius:12px`、shadow、`ys-tool-footer` 与 LuCI 原生控件混用。
- **建议**：按用户视觉方向决定：回退 v1.8.3 原版观感，或保留 2.x 语言只做 token/间距/层级收口；不要无理由整站重构。
