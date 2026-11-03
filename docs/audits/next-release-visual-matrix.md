# Next Release Visual Matrix — 2e28db4

基线：`main` / `2e28db4b5cdc221897bbe98ff78fbe7235098e53`
环境：真实 OpenWrt 24.10.8 x86_64 容器 + LuCI `26.205.85413~cac97ed` + 真实 `uhttpd`；不是 `preview/aurora.html`，不是假 DOM。
浏览器：Microsoft Edge（Chromium 156）headless；真实登录会话；语言 `zh_cn`。

## 1. 矩阵定义

| 项 | 值 |
|---|---|
| 主题 | Bootstrap（原版 LuCI）、Aurora light、Aurora dark |
| 主断点 | 375×900、768×900、1280×900 |
| 页面 | overview、settings、sources、intelligence、openclash、passwall、advanced、logs |
| 正常态截图 | 3 × 3 × 8 = **72** |
| 边界截图 | 320×900 overview × 3 主题 = 3；1280@200% 等效 640×900 sources × 3 主题 = 3；合计 **6** |
| 总截图 | **78 PNG** |
| 索引 | `docs/audits/next-release-evidence/visual-2e28db4/visual-index.csv` |
| 度量 | `metrics.jsonl`（每张的 innerWidth、scrollWidth、overflow、textLen、dark、login） |

> 主题切换：Bootstrap 用 `luci.main.mediaurlbase=/luci-static/bootstrap`；Aurora 用 `/luci-static/aurora` + `localStorage aurora.theme=light|dark`。Aurora dark 的 26 张截图均记录 `data-darkmode=true`。

## 2. 正常态矩阵

| 主题 / 断点 | overview | settings | sources | intelligence | openclash | passwall | advanced | logs |
|---|---|---|---|---|---|---|---|---|
| Bootstrap 375 | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| Bootstrap 768 | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| Bootstrap 1280 | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| Aurora light 375 | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| Aurora light 768 | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| Aurora light 1280 | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| Aurora dark 375 | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| Aurora dark 768 | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| Aurora dark 1280 | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |

**判定依据**：每张页面实际加载（`textLen >= 212`）、无登录页、`document.scrollWidth <= innerWidth` 且 `body.scrollWidth <= innerWidth`；72/72 正常态 `overflow=false`。详见 `metrics.jsonl`。

## 3. 边界抽查

| 边界 | 页面 | 结果 | 证据 |
|---|---|---|---|
| 320×900 | Overview × 3 主题 | 页面无横向滚动；顶部导航 tab `Candidate IP` 右侧被裁切 | `*/320x900/overview.png` |
| 1280@200% 等效 640×900 | Sources × 3 主题 | 表单/说明/两来源 MultiValue 可读；无横向滚动 | `*/1280x900-200pct-effective-640/sources.png` |

> 200% 使用 640 CSS px 有效宽度近似 1280 桌面 200% 浏览器缩放；未用真实浏览器 zoom 菜单，属于**边界近似**，不是精确浏览器缩放证据。键盘/焦点未在此边界执行，标 NOT-RUN。

## 4. 视觉观察

### 4.1 布局

- 375/768/1280 均无页面横向溢出。
- 320 Overview 的 tab 行在极窄屏裁切最右侧 tab；页面本身无横向滚动，但导航项文本不可完整读取。**P2-07**。
- Aurora light/dark 的卡片、表单、表格、页脚在 375/768/1280 均正常堆叠；没有截图显示控件越界。
- Bootstrap 原版在 768/1280 仍为原生 LuCI 视觉；Aurora 保持其自身主题，不应把 Bootstrap 的观感当作 Aurora 的验收。

### 4.2 字体/可读性

- 正文在 375 下可读；表单说明为灰色小字，未出现 9px 级正文（日志区 CSS 仍有 9px，见 P2-04；本轮未截图专门测日志字号）。
- 320 导航 tab 裁切属于可读性问题。
- 长中文说明在 375 下换行合理；未见按钮文字溢出。

### 4.3 颜色/对比度

- Aurora dark 26/26 截图 `data-darkmode=true`；Aurora light 26/26 `false`；Bootstrap 26/26 `false`。
- **未完成全量 WCAG AA 自动扫描**：`NOT-RUN`。本报告不宣称所有正文达到 4.5:1；需要独立的颜色/背景对比扫描与人工复核。
- 旧 `docs/audits/g4-g5-evidence/overview-contrast-fix.json` 是旧 SHA `0d8460f` 的 Bootstrap Overview 采样，不能代表当前 `2e28db4` 或 Aurora。

### 4.4 控制台

- 抽查页面未发现 `agent-browser errors` 页面错误；但未对 78 张逐一保存 console 日志，**全量 console gate NOT-RUN**。
- 页面加载期间曾出现一次 “加载视图中…” 瞬态；复测已加载，未判定为缺陷，但说明需要更可靠的 wait/网络条件。

### 4.5 交互/主题差异

- 菜单 `Candidate IP Sources`、`Intelligence` 在所有语言为中文的截图中仍为英文，属于 i18n P1-04，不是视觉样式问题。
- OpenClash/PassWall 页面通过 init stub 暴露；页面本身可渲染，但真实控制器状态/备份事务未验证。
- `preview/aurora.html` 未用于验收；全部截图是真实 LuCI。

## 5. 截图索引与命名

- 目录：`docs/audits/next-release-evidence/visual-2e28db4/<theme>/<viewport>/<page>.png`
- 命名包含 SHA 目录 `visual-2e28db4`；每行 CSV 包含 `sha/theme/viewport/page/state/title/w/h/scrollWidth/overflow/textLen/file`。
- 状态：`normal`、`boundary-320`、`boundary-200pct-effective-640`。
- 未生成任何模拟图；没有 `PREVIEW_ONLY` 截图。

## 6. 结论

- 正常态 8 页 × 3 主题 × 3 断点：**72/72 PASS**（真实 LuCI/Aurora，无横向 overflow）。
- 边界 320：**PASS（页面无 overflow）但 P2-07 导航 tab 裁切**。
- 边界 200% 等效：**PASS（近似）**，精确浏览器 zoom/键盘未执行。
- WCAG AA 全量对比度、全量 console、键盘/触控：**NOT-RUN**。
- 视觉方向（回退 v1.8.3 原版 vs 保留 2.x 语言）需用户决定，不能由本审计替用户选择。
