# luci-app-cloudflare-ip 界面设计规范

由 `luci-app-upnp-nat-relay` 与 `luci-app-nginx-manager` 的实际界面实现提炼，
并基于 `192.168.2.1` 真机截图完成对照评估。

- 文档日期：2026-11-08
- 目标：指导 `luci-app-cloudflare-ip` 的界面改造，不改变其功能与信息架构
- 状态：评估与规范，未修改任何目标仓库代码

---

## 0. 结论摘要

### 0.1 视觉诊断

cloudflare-ip 的问题不是“配色难看”，而是三种做法叠加后偏离了 LuCI / Aurora 的原生视觉语言：

1. **全站卡片化**：所有 `.cbi-section` 都被加上了背景、边框、12px 圆角和投影（`TARGET ui.css:52-64`）。两个参照仓库都没有给通用 section 加阴影或圆角。
2. **控件皮肤覆写**：表头改成大写小字 + 底色（`TARGET ui.css:216-223`），输入框和按钮统一抬高、加圆角、加 hover 位移（`TARGET ui.css:124-165`）。
3. **语义化不足**：统计卡里放的不是统计值；数据源状态用普通文本而不是徽标；日志页没有过滤与危险操作分区。

参照仓库的共同语言是：**原生 LuCI 扁平面板 + 液态语义色 + 少量 8px 统计卡 + 一致的徽标/横幅**。
cloudflare-ip 需要的不是重新配色，而是回到这套语言。

### 0.2 最先改的五件事

| 顺序 | 改动 | 文件落点 |
|---|---|---|
| 1 | 去掉通用 `.cbi-section` 的背景、边框、阴影、12px 圆角 | `cloudflare-ip.css:52-64` |
| 2 | 删除视图内联 `<style>` 与内联 style 属性 | `overview.js:191-220,262`；`diagnostics.js:12-33,62,226,239` |
| 3 | 去掉表头的大写、字距与底色 | `cloudflare-ip.css:216-223` |
| 4 | 统计卡只保留真正的计数，0 不再无条件标红 | `overview.js:306-327` |
| 5 | 数据源状态改为徽标；日志页补过滤 | `sources.js:76-86`；`diagnostics.js:159-189` |

### 0.3 是否做成 skill

**结论：不做 skill，做文档。**

理由见第 8 节。简单说：这套规范的价值在于“可追溯到这两个仓库的具体文件与行号”，
把它抽成通用 skill 会丢掉这个约束；而写死行号的 skill 会随代码变化迅速过期。

---

## 1. 证据基础与方法

### 1.1 仓库与版本

| 角色 | 仓库 | 实际读取的分支/提交 | 设备安装版本 |
|---|---|---|---|
| 参照 A | `luci-app-upnp-nat-relay` | `main`，只读 | `1.3.11-r1` |
| 参照 B | `luci-app-nginx-manager` | `main`，只读 | `1.8.5-r1` |
| 目标 | `luci-app-cloudflare-ip` | 读取 `evidence/kvm-12h-20261107` 工作区；与 `main` 的相关 UI 文件无差异 | `2.6.0-r9` |

设备：OpenWrt 25.12.5，LuCI openwrt-25.12，Aurora 主题。

### 1.2 路径缩写

| 缩写 | 完整路径（相对各自仓库根） |
|---|---|
| `UPNP ui.css` | `package/luci-app-upnp-nat-relay/htdocs/luci-static/resources/upnp-nat-relay/upnp-nat-relay.css` |
| `UPNP utils.js` | `package/luci-app-upnp-nat-relay/htdocs/luci-static/resources/upnp-nat-relay/utils.js` |
| `UPNP overview.js` | `package/luci-app-upnp-nat-relay/htdocs/luci-static/resources/view/upnp-nat-relay/overview.js` |
| `NGINX ui.css` | `www/luci-static/resources/nginx-manager/nginx-manager.css` |
| `NGINX utils.js` | `www/luci-static/resources/nginx-manager/utils.js` |
| `NGINX sites.js` | `www/luci-static/resources/view/nginx-manager/sites.js` |
| `CFI ui.css` | `package/luci-app-cloudflare-ip/htdocs/luci-static/resources/cloudflare-ip/cloudflare-ip.css` |
| `CFI overview.js` | `package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/overview.js` |
| `CFI diagnostics.js` | `package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/diagnostics.js` |
| `CFI sources.js` | `package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/sources.js` |

### 1.3 界面走查方式

- 真机 `192.168.2.1`，用 Playwright 只读访问。
- 仅执行：导航、等待、滚动、截图、读取 computed style。
- **未点击保存 / 应用 / 重启 / 删除 / 启动 / 停止 / 测试**，未修改任何配置项。
- 登录方式：使用设备既有 root SSH 创建一次性只读 LuCI 会话（未改账号、未改配置），
  会话用后销毁。没有使用或猜测 LuCI 密码。
- 截图时间：2026-11-08。
- 截图目录：[`screens/`](screens/)。

已覆盖页面：

| 插件 | 页面 | URL 后缀 |
|---|---|---|
| upnp | Overview / Setup Wizard / Settings / Network / Security / Mappings / OpenClash / Logs | `/admin/services/upnp_nat_relay/...` |
| nginx | Overview / Sites / Certificates / Files / Core Config / Backups / Logs | `/admin/services/nginx-manager/...` |
| cloudflare-ip | Overview / Settings / OpenClash / Candidate IP Sources / Intelligence / Advanced / Logs & Records | `/admin/services/cf_ip/...` |

限制：

- 未制造空表、无网络、权限错误等破坏性场景；可自然复现的空态（upnp Logs）已截图。
- `cloudflare-ip` 的 PassWall 页面在本机未安装对应依赖，直接访问回落到 Overview，未作为有效样本。
- 深色模式通过 Aurora 的浏览器本地主题开关切换，未写入设备配置。

### 1.4 代码问题还是主题覆盖问题

| 现象 | 判定 | 依据 |
|---|---|---|
| 全站 section 有阴影、12px 圆角 | **代码问题** | `CFI ui.css:52-64` 明确覆写 |
| 表头大写、字距、有色底 | **代码问题** | `CFI ui.css:216-223` 明确覆写 |
| 移动端 6 个 tab 折成 3 行 | **代码问题** | `CFI ui.css:429-434` 强制 `flex-wrap: wrap` |
| 统计卡里出现 `IPv4` / `HTTP` / `v2.3.5` | **内容/布局问题** | `CFI overview.js:306-327` 把元数据放进统计卡 |
| 390px 下时间戳、GitHub 链接换行 | **布局问题** | KV 表值列过窄，长值没有单独处理 |
| 深色模式下输入框边框偏弱 | **主题原生行为** | upnp/nginx/cfi 三者一致；cfi 只改了圆角/高度，没有改背景与边框色 |
| 深色模式下 badge 对比度 | **代码问题（可改善）** | cfi 用固定浅色文本变量（`CFI ui.css:9-12,23-31`），参照仓库直接用语义色 |

---

## 2. 共同基线（两个参照仓库真正一致的部分）

以下每条都同时得到两个参照仓库的支持；只有单边出现的做法放到第 3 节。

### 2.1 样式架构

**规则 B-01：每个应用一份共享 CSS，视图只负责结构，不注入 `<style>`。**

- upnp 在 `UPNP utils.js:107-116` 通过 `loadSharedCSS()` 注入
  `L.resource('upnp-nat-relay/upnp-nat-relay.css') + '?v=@PKG_VERSION@'`，
  并在 `UPNP utils.js:197-202` 的 `appendFooter()` 中统一调用。
- nginx 在 `NGINX utils.js:45-53` 做同样的事，`NGINX utils.js:141-146` 统一调用。
- 两个仓库的 view 文件中没有任何 `<style>` 或 `E('style')`。

**规则 B-02：颜色优先使用 LuCI 主题变量，变量缺失时回退到语义色。**

- upnp：`UPNP ui.css:11-14, 22-25, 83-87, 100-102`。
- nginx：`NGINX ui.css:20-38, 321-326, 341-343`。

**规则 B-03：页面结构使用 `view.extend` + `E()` 构建，共享组件与页脚放在 `utils.js`。**
三个应用都采用同一套 LuCI 视图模型（`CFI overview.js:222` 的 `return view.extend({...})`；
共享注入与页脚见 B-01 引用的三个 `utils.js`）；这不是需要改动的地方。

### 2.2 设计令牌

#### 颜色

| 令牌 | 参照值 | 出处 | 说明 |
|---|---|---|---|
| 成功 | `#3aa657` | `UPNP ui.css:10,83`；`NGINX ui.css:319,325` | 运行中、Present、Valid |
| 失败 | `#d94b4b` | `UPNP ui.css:11`；`NGINX ui.css:320` | 停止/错误（nginx 把 stopped 归为失败） |
| 警告 A | `#d89b00` | `UPNP ui.css:12,84,102` | upnp 的 stopped/starting |
| 警告 B | `#c68014` | `NGINX ui.css:343` | nginx 的 orange 统计值 |
| 主色 | `#0069d9` | `UPNP ui.css:14,98`；`NGINX ui.css:339` | 中性数值、链接 |
| 次要文本 | `#666` | `UPNP ui.css:13,87,104`；`NGINX ui.css:327` | 描述、标签 |
| 弱文本（空态） | `#888` | `NGINX ui.css:269` | 空态文本 |

**裁决 C-01（警告色）：统一回退值采用 `#c68014`。**
两边差异只有 `#d89b00` 与 `#c68014`；后者在白底上对比度更好，作为 badge 文本更稳。
实际运行时仍应优先读取 `var(--warning-color)`，回退值只用于主题缺失时。

#### 字号与字重

| 用途 | 值 | 出处 |
|---|---|---|
| 状态横幅标题 | `1.3em` | `UPNP ui.css:82`；`NGINX ui.css:324` |
| 状态横幅正文 | `0.9em` | `UPNP ui.css:87`；`NGINX ui.css:327` |
| 统计值 | `1.8em` / bold / line-height 1.2 | `UPNP ui.css:96-98`；`NGINX ui.css:337-339` |
| 统计标签 | `0.85em` | `UPNP ui.css:103-105`；`NGINX ui.css:344-345` |
| 徽标 | `0.85em` / 500 | `UPNP ui.css:19-20`；`NGINX ui.css:12-15` |
| 日志 | 10px / monospace | `UPNP ui.css:180`；`NGINX ui.css:170` |
| 页面标题、分组标题、表单标签 | **不覆写，使用 LuCI 原生** | 两边均无 `.cbi-map-title` / `.cbi-section > h3` 覆写 |

#### 间距

| 用途 | 值 | 出处 |
|---|---|---|
| section 底部间距 | `1.5em` | `UPNP ui.css:3,110` |
| 统计卡网格间距 | `1em`，底部 `1.5em` | `UPNP ui.css:88-91`；`NGINX ui.css:330-333` |
| 状态横幅内边距 / 底部间距 / 元素间距 | `1.5em` / `1.5em` / `1.2em` | `UPNP ui.css:70-73`；`NGINX ui.css:315-318` |
| 统计卡内边距 | `1em 1.2em` | `UPNP ui.css:93`；`NGINX ui.css:335` |
| KV 表标签列宽 | `12em`，不换行 | `UPNP ui.css:211-217`；`CFI ui.css:257-264`（cfi 已沿用） |
| 行操作按钮间距 | `0.1em 0.25em 0.1em 0`，内边距 `0.4rem 0.8rem` | `CFI ui.css:272-277`；与 upnp/nginx 的 actions 规则一致 |

#### 圆角

| 用途 | 值 | 出处 |
|---|---|---|
| 徽标 / chip | `4px` | `UPNP ui.css:19`；`NGINX ui.css:13` |
| 统计卡 | `8px` | `UPNP ui.css:93`；`NGINX ui.css:335` |
| 响应式表格卡片 | `6px` | `UPNP ui.css:353-370`；`NGINX ui.css:424-446` |
| 命令框 / 文本块 | `6px` | `UPNP ui.css:46-48` |
| **通用 section** | **不用圆角** | 两个参照仓库均未覆写 |

#### 阴影

| 场景 | 参照做法 |
|---|---|
| 静态 section、状态横幅、统计卡 | **无阴影**（仅统计卡有 8px 圆角） |
| 悬浮层 / 模态框 | 使用 LuCI 原生 |

cfi 现状：所有 section 都有 `box-shadow: 0 5px 18px ...`（`CFI ui.css:16,52-58`），这是最大的偏离点。

### 2.3 组件规则

#### B-04 状态横幅（Status Banner）

两个参照仓库结构完全一致：

```
.cbi-section.ubr-status-banner / .nm-status-banner
  ├─ .*-status-icon        （2.5em，单字形图标）
  └─ .*-status-text
       ├─ h3               （1.3em，状态词）
       └─ p                （0.9em，次要说明）
```

- 布局：`display:flex; align-items:center; gap:1.2em; padding:1.5em; margin-bottom:1.5em;`
  （`UPNP ui.css:70-74`；`NGINX ui.css:315-318`）。
- 状态识别：左边框 `5px`（`UPNP ui.css:75-77`；`NGINX ui.css:319-320`）。
- 图标与标题使用同一语义色（`UPNP ui.css:78-85`；`NGINX ui.css:321-326`）。
- 允许 `flex-wrap: wrap`（upnp 显式写了，`UPNP ui.css:73`）。
- **不加卡片背景与阴影**；容器本身就是 LuCI 的原生 section。

#### B-05 统计卡（Stat Cards）

- 容器：`repeat(auto-fit, minmax(160px, 1fr))`，`gap:1em`，`margin-bottom:1.5em`
  （`UPNP ui.css:88-91`；`NGINX ui.css:330-333`）。
- 卡片：`padding:1em 1.2em; border-radius:8px; text-align:center`
  （`UPNP ui.css:92-95`；`NGINX ui.css:334-336`）。
- 值：`1.8em; bold; line-height:1.2`；默认主色，只有在状态明确时才加 green/red/orange
  （`UPNP ui.css:96-102`；`NGINX ui.css:337-343`）。
- 标签：`0.85em`，次要文本色（`UPNP ui.css:103-105`；`NGINX ui.css:344-345`）。
- **0 永远是中性色**：upnp 只在计数 `>0` 时加语义色（`UPNP overview.js:201-216`）；
  nginx 的 0 也不加色（`NGINX overview.js:119`）。cfi 的 “0 = red” 是明确偏离。
- **统计卡只放计数或单一短状态词**：
  - upnp 四张卡全是计数（`UPNP overview.js:196-217`）；
  - nginx 除计数外放了 `Enabled/Disabled`、`Unknown/pass` 这类短状态
    （`NGINX overview.js:136-150`），可以作为先例；
  - 两边都没有把版本号、时间戳、URL 这类长文本放进统计卡。cfi 的 CFST Version 应移入 KV 表。
- 390px 下改成两列：cfi 已有 `repeat(2, 1fr)`（`CFI ui.css:446`），可保留。

#### B-06 徽标（Badge）

两个参照仓库的配方几乎相同：

| 属性 | upnp | nginx | 基线 |
|---|---|---|---|
| display | inline-block | inline-flex + center | **inline-flex**（垂直对齐更稳） |
| padding | `0.15em 0.6em` | `0.18em 0.6em` | `0.18em 0.6em` |
| radius | `4px` | `4px` | `4px` |
| font | `0.85em / 500` | `0.85em / 500 / line-height 1.35` | 同 nginx |
| 背景 | 语义色 15% `color-mix` | 同左 | 同左 |
| 文本 | 语义色本身 | 语义色本身 | 语义色本身（不要固定浅色值） |

出处：`UPNP ui.css:18-25`；`NGINX ui.css:8-18,20-38`。
cfi 现有徽标为 `inline-block` / `0.15em`（`CFI ui.css:177-180`），改造时按基线一并调整。

状态词规范：

| 状态 | 徽标 | 语义 |
|---|---|---|
| 正常 | `✔ Running` / `✔ Present` / `✔ Valid` | green |
| 未安装 | `✘ Not Installed` | red 或 orange（按是否阻断功能） |
| 已安装但停止 | `⚠ Installed (Stopped)` | orange |
| 未知 | `? Unknown` | gray |
| 未运行 | `Not run yet` | gray |
| 过期 | `Cached / stale` | orange |
| 错误 | `✘ Error` + 详情折叠 | red |

参照实现示例：`UPNP overview.js:99-111`；`CFI overview.js:154-174,460-475`。

#### B-07 按钮、行操作与危险操作

- 行操作容器：`display:flex; flex-wrap:wrap; align-items:stretch`，按钮之间 `0.1em 0.25em 0.1em 0`
  （`UPNP ui.css:31-43`；`CFI ui.css:266-278` 已沿用）。
- 按钮内边距 `0.4rem 0.8rem`，`white-space:nowrap`。
- 颜色沿用 LuCI 语义类：`cbi-button-action` / `cbi-button-apply` / `cbi-button-negative` / `cbi-button-reset`。
- **不增加 hover 位移、缩放或投影**；参照仓库没有这类动效。
- 危险区 `.ubr-danger-zone` 只用于不可逆操作（upnp 的 “Undo All Initialization”），
  左边框 `5px` 失败色，`margin-bottom:1.5em`（`UPNP ui.css:190-193`）。
  清空日志属于可恢复操作，不放进危险区（见 B-10）。

#### B-08 表格

- 使用 LuCI 原生 `.table`，**不重设表头样式**。
- 只加滚动容器：`width:100%; overflow-x:auto`，表头 `white-space:nowrap`，单元格 `word-break:break-word`
  （`UPNP ui.css:196-217`）。
- KV 表：`th { width:12em; white-space:nowrap }`，`td { word-break:break-word }`
  （`UPNP ui.css:211-217`；cfi 已在 `CFI ui.css:257-264` 沿用）。
- 宽表在窄屏转成卡片行：
  - nginx 在 `1024px` 转换（`NGINX ui.css:424-446`）；
  - upnp 在 `900px` 转换（`UPNP ui.css:353-370`）。
  - **裁决 C-02：≥6 列或带行操作按钮的表用 1024px；≤4 列用 900px。**
    参照的差异来自列数，不是审美分歧。

#### B-09 表单

- 使用 LuCI CBI 表单，分组用多个 `cbi-section`，每组保持短小。
- 标签、输入框、按钮的边框/高度/字重交给 LuCI 主题。
- 描述文本放在值下方，使用主题次要色，长度控制在 1–2 行。
- 参照仓库没有跨页的 `.cbi-input-*` / `.cbi-button` / `.cbi-value` 皮肤覆写；
  只在具体页面做局部布局（upnp 的 wizard mode 按钮、nginx 的内联设置/凭证字段/代码编辑器）。
- **裁决 C-03：允许使用 grid 做标签/值对齐（cfi 的 `CFI ui.css:78-86` 可保留），
  但不允许改输入框圆角、最小高度、按钮字重与 hover 动效。**

#### B-10 日志区

- `textarea.cbi-input-textarea` + 等宽字体，`rows=20`。
- 空/加载态：斜体 + 次要色；错误态：失败色（`UPNP ui.css:180-189`；`NGINX ui.css:170-185`）。
- 控制区包含：过滤、刷新、清空。过滤用级别下拉（upnp `diagnostics.js:77-139`）
  或关键字输入（nginx `logs.js:90-97`）；清空与刷新同组，但必须二次确认。
- 清空日志是可恢复操作，不放进危险区。危险区只留给不可逆的初始化回滚
  （upnp `diagnostics.js:189-193`；`UPNP ui.css:190-193`）。

#### B-11 空态与错误态

- 空态：居中、次要色、直接说明“没有什么”，例如 “No logs found.”；
  nginx 用 `text-align:center; padding:20px; color:#888`（`NGINX ui.css:267-271`）。
- **不用虚线框卡片**做空态；两个参照仓库均无这种装饰。
- 错误态：短标题 + 一句可执行说明 + 原始错误折叠展示。
  cfi 的 `utils.errorPanel` 结构符合这个方向，可保留。

#### B-12 页脚

三个应用都已使用统一的 `ys-tool-footer` chip 行：
`Project · GitHub · 云云云`，样式集中在各自 CSS；页脚挂载入口为
`UPNP utils.js:197-202`、`NGINX utils.js:141-146`、`CFI utils.js:577-585`。
这项无需改造；只需保证新的视觉规则不破坏它。

### 2.4 页面布局模式

两个参照仓库实际使用的是同一套“四段式”：

```
H2 页面标题
[状态横幅]                      ← 仅总览/服务健康页
[统计卡 2–4 个]                 ← 仅总览
[操作区 / 表格 / 表单分组]        ← 主体，按任务分 1–3 个 section
[环境检测 / 只读 KV 表]          ← 可选
[页脚 chip 行]
```

列表页：

```
H2
[工具栏按钮，一行]               ← 刷新 / 新增 / 批量操作
[表格 section]                   ← 行操作在最后一列
[页脚]
```

设置页：

```
H2
[分组 1：≤6 行]
[分组 2：≤6 行]
[分组 3：≤6 行]
[Save / Save & Apply / Reset]
[页脚]
```

日志页：

```
H2
[日志 section：控制行（过滤 / 刷新 / 清空）+ 等宽文本区]
[危险区：仅不可逆操作时出现，例如初始化回滚]
[页脚]
```

### 2.5 文案与状态提示

参照仓库的共同写法：

| 场景 | 写法 | 例子/出处 |
|---|---|---|
| 运行中 | 主语 + is running/active + 作用 | “UPnP NAT Relay is active and syncing mappings.” |
| 已停止 | 主语 + is not running + 下一步 | “Cloudflare IP optimization service is not running. Click Start to begin.” |
| 徽标 | 图标 + 2–4 个词 | `✔ Present` / `⚠ Installed (Stopped)` / `✘ Not Installed` |
| 表单说明 | 一句，说明“做什么/影响什么” | “Run the background service and periodically synchronize accepted UPnP mappings.” |
| 空态 | 直接说明无数据 | “No logs found.” / “No IP history available” |
| 错误 | 发生了什么 + 数据是否保留 + 下一步 | “Unable to refresh sources. The previous candidate pool is unchanged; unsaved edits are still kept.”（`CFI sources.js:89`） |

不允许：

- 把内部实现细节、RPC 方法名、字段名放在一级界面。
- 用营销式形容词描述功能。
- 在同一个界面混用两套状态词（例如 “运行中 / Running / active”）。

### 2.6 响应式与深色模式

- 统计卡：`auto-fit/minmax(160px,1fr)`；≤600px 两列（`CFI ui.css:446`）。
- 表格：≤1024 或 ≤900 转卡片行（第 B-08 条）。
- 状态横幅：≤600 允许 `flex-wrap`，图标缩小到 `1.8em`（`CFI overview.js:212-219` 已有）。
- 深色模式：颜色全部走主题变量；徽标/横幅使用同一个语义变量，不写死浅色文本。
- cfi 已定义深色变量（`CFI ui.css:23-31`），但 badge 文本使用了固定浅色值，
  建议改为直接用语义色，或至少验证对比度（见第 5 节 G-09）。

---

## 3. 参照仓库各自独有的做法（不纳入通用基线）

### 3.1 upnp-nat-relay 独有

| 做法 | 位置 | 是否值得 cloudflare-ip 学 |
|---|---|---|
| 三步 wizard 进度点 | `UPNP ui.css:114-135` | 否；cfi 没有向导流程 |
| 分段式 mode 切换按钮（Details/Configuration） | `UPNP ui.css:136-169` | 可选；仅在确有互斥视图时使用 |
| 命令框 + 一键复制 | `UPNP ui.css:46-50` | 可选；cfi 有单个安装命令，可保留现有 `cfi-cmd-box` |
| 向导摘要表 | `UPNP ui.css:220-228` | 否 |
| 安全审计卡片 | `upnp-nat-relay/security.js` | 否；cfi 无对应功能 |

### 3.2 nginx-manager 独有

| 做法 | 位置 | 是否值得 cloudflare-ip 学 |
|---|---|---|
| 代码编辑器深色块 | `NGINX ui.css:154-167` | 否；cfi 没有可编辑的 nginx 配置 |
| 文件管理器 | `nginx-manager/files.js` | 否 |
| 凭证输入 + 显隐切换 | `NGINX ui.css:302-312` | 可选；cfi 的 Cloudflare 凭证输入可借鉴 |
| 日志过滤输入 | `NGINX logs.js:90-97` | **是**；cfi 日志页缺少过滤 |
| 证书状态徽标 | `NGINX sites.js`/`certificates.js` | **是**；这是 cfi 数据源状态应采用的模式 |

结论：独有做法只在对应功能存在时复用，不能当作“通用规范”强搬到 cfi。

---

## 4. 冲突与裁决

| 冲突点 | upnp | nginx | 裁决 | 理由 |
|---|---|---|---|---|
| stopped 的颜色 | 警告 `#d89b00` | 失败 `#d94b4b` | **按语义分**：用户主动停止/过渡 = 警告；非预期停机且影响业务 = 失败 | 不能简单取平均；cfi 的 “Service Stopped” 是用户可主动操作的状态，用警告色更合理 |
| 警告色回退值 | `#d89b00` | `#c68014` | **`#c68014`** | 白底文本对比度更好 |
| 徽标布局 | `inline-block` | `inline-flex` | **`inline-flex` + line-height 1.35** | 与文字、图标垂直对齐更稳定 |
| 统计卡内容 | 纯计数（`overview.js:196-217`） | 计数 + 短状态词（`overview.js:136-150`） | **允许计数与单一短状态词；禁止版本号/时间戳/URL** | nginx 证明 `Enabled/Disabled` 可接受；长文本两边都无先例，cfi 的 CFST Version 属于越界 |
| 表格断点 | 900px | 1024px | **按列数选择**：≥6 列或带行操作 → 1024；≤4 列 → 900 | 断点差异来自信息密度，不是风格分歧 |
| 空态 | 日志内斜体占位 | 居中次要色文本 | 分场景：日志内用斜体占位；表格/面板用居中文本 | 两边共同点是“无装饰”，不是具体对齐方式 |
| 表头 | 原生 | 原生 | **原生**，不改大写/字距/底色 | 两边一致，cfi 是唯一偏离者 |
| section 卡片 | 原生平面 | 原生平面 | **原生平面**，无阴影/无大于 8px 圆角 | 两边一致 |
| 输入框圆角/高度 | 原生 | 原生 | **原生** | 两边一致；cfi 是唯一覆写者 |
| 按钮 hover | 无位移 | 无位移 | **无位移/无投影** | 两边一致；cfi 的 `translateY(-1px)` 是孤例 |
| 移动端 tab | 原生横向滚动 | 原生横向滚动 | **单行横向滚动**，不做多行折行 | 两边都未覆写；cfi 的多行折行导致 390px 下占三行 |

---

## 5. “什么算不达标”判定清单

每条都可以用 grep、computed style 或截图直接判定，不依赖主观感受。

| ID | 判定项 | 不达标条件 | 取证方式 |
|---|---|---|---|
| G-01 | 通用 section 皮肤 | `.cbi-section` 被设置 `box-shadow`，或圆角 > `8px` | grep CSS；computed style |
| G-02 | 内联样式 | view 文件中出现 `E('style')` / `<style>` / `style="..."` | grep view 目录 |
| G-03 | 表头皮肤 | `th` 设置 `text-transform:uppercase`、`letter-spacing` 或非透明背景 | grep CSS；computed style |
| G-04 | 统计卡语义 | 统计卡值不是数字/布尔状态 | 读 `*-stat-value` 的文本 |
| G-05 | 状态徽标 | 表格中的运行/安装/新鲜度状态是纯文本 | DOM 检查该单元格是否含 `*-badge` |
| G-06 | 危险操作分区 | 不可逆操作（回滚/删除配置）与刷新类按钮在同一工具栏，且无危险区或二次确认；清空日志不适用此项 | DOM/section 检查 + 按钮回调查看 |
| G-07 | 按钮动效 | 静态按钮 hover 有 `transform` / `box-shadow` | computed style `:hover` 或 CSS |
| G-08 | 输入控件皮肤 | 应用 CSS 改了 input 的 `border-radius` / `min-height` | grep CSS |
| G-09 | 徽标对比度 | 徽标文本与 15% 语义底色的对比度 < 4.5:1 | 颜色计算 / 截图核对 |
| G-10 | 390px 横向溢出 | 出现横向滚动条或内容被裁切 | 390×844 截图 |
| G-11 | 390px 长值 | 时间戳/URL/版本号换行超过 2 行，或被挤压 | 390×844 截图 |
| G-12 | 移动端 tab | 主导航折成 > 2 行 | 390×844 截图 |
| G-13 | 空态装饰 | 空态使用虚线框或大面积彩色底 | 截图 + CSS |
| G-14 | 文案长度 | 表单说明在 1280px 下超过 2 行；一级界面出现字段名/RPC 名 | 1280px 截图 + 源码 |
| G-15 | 字重 | section 标题/表单标签/按钮统一 700 | computed style |
| G-16 | 样式入口 | 同一应用有多个 CSS 入口或视图内样式覆盖 | 文件搜索 |

---

## 6. cloudflare-ip 差距清单

### 6.1 P0：直接造成“主题不对”的问题

#### P0-1 全站 section 被卡片化

- 现状：`CFI ui.css:52-64` 给 `.cfi-dashboard .cbi-section` 和 `.cfi-form-map .cbi-section`
  加了背景、边框、`--cfi-radius: 12px`、`--cfi-shadow: 0 5px 18px ...`（`CFI ui.css:13-17`）。
- 参照：upnp 只给 `.ubr-mappings .cbi-section` 加 `margin-bottom:1.5em`（`UPNP ui.css:110`）；
  nginx 完全不覆写通用 section。
- 截图对照：[cfi-overview.png](screens/cfi-overview.png) vs
  [upnp-overview.png](screens/upnp-overview.png)、[nginx-overview.png](screens/nginx-overview.png)。
  cfi 的每块内容都像独立浮起的卡片；参照仓库是连续平面 + 细分割线。
- 期望：删除 section 的背景、边框、阴影、12px 圆角；只保留统计卡的 8px 圆角。
- 优先级：**P0**。这是“丑”的主要来源。

#### P0-2 视图内联样式与重复定义

- 现状：
  - `CFI overview.js:191-220` 定义了一整段 `css`，`CFI overview.js:262` 用 `E('style')` 注入；
    其中布局、左边框、`.cfi-status-icon`、`.cfi-status-text` 只存在于这段内联样式。
  - CSS 文件只在 `CFI ui.css:347-353` 给 `.cfi-status-banner` 加了卡片皮肤（背景/边框/阴影），
    与视图内的横幅布局分裂成两处定义。
  - `CFI diagnostics.js:12-33` 再次定义 `css`，`CFI diagnostics.js:62` 注入。
  - 另有内联属性：`CFI diagnostics.js:226`（空态 style）、`CFI diagnostics.js:239`（按钮栏 style）。
- 参照：两个仓库的 view 目录中 `<style>` / `E('style')` 数量为 0。
- 期望：全部移入 `CFI ui.css`；视图只保留类名。
- 优先级：**P0**。它会让主题适配、后续改版和审计都无法单点修改。

#### P0-3 表头被改成“后台系统风”

- 现状：`CFI ui.css:216-223`：
  `background: var(--cfi-surface-muted); font-size:0.8rem; font-weight:700; letter-spacing:0.02em; text-transform:uppercase;`
  再叠加 `CFI ui.css:207-215` 的整表边框与 `8px` 圆角。
- 参照：两边都是原生 `.table`，表头不加底色、不做大写变换。
- 截图：cfi Overview / OpenClash / Logs 的蓝色表头带，
  对比 [nginx-sites.png](screens/nginx-sites.png) 的原生表头。
- 期望：删除表头背景、大写、字距、加粗；保留 `white-space:nowrap` 与滚动容器。
- 优先级：**P0**。

### 6.2 P1：影响可读性、状态判断与移动端

#### P1-1 统计卡的 0 被标红、版本号占位

- 现状：`CFI overview.js:306-327`：
  - Best IP Count 为 0 时无条件 `red`（`overview.js:308`）；
  - IP Type、Speed Test Protocol、CFST Version 作为 `1.8em` 统计值显示。
- 参照：upnp 的 0 不加语义色（`UPNP overview.js:201-216`）；
  nginx 的 0 也不加色（`NGINX overview.js:119`），但允许 `Enabled/Disabled` 这类短状态词
  （`NGINX overview.js:136-150`）。两边都没有把版本号放进统计卡。
- 截图：390px 下 `IPv4` 尚可，但长版本号/时间戳会把卡片撑高；
  0 的红色会让“尚未运行”看起来像故障。
- 期望：0 改为中性色或橙色（未运行）；统计卡最多保留计数与 Last Run 状态；
  CFST Version 移入 Service Information；IP Type / Protocol 若保留应缩短或降级为 KV。
- 优先级：**P1**。

#### P1-2 数据源状态是纯文本

- 现状：`CFI sources.js:76-86` 直接把 `state` 放进 `.td`：
  `Fresh` / `Cached / stale` / `Not fetched` / `Error` 都是普通文本。
  `sourceStateLabel` 只返回字符串（`CFI utils.js:170-176`）。
- 参照：upnp/nginx 在表格里用徽标（`UPNP overview.js:99-111`；`NGINX sites.js` 的 Enabled/SSL 徽标）。
- 截图：[cfi-sources.png](screens/cfi-sources.png) —— 状态列与 URL 列视觉权重相同，扫读困难。
- 期望：状态列改为 `cfi-badge green/orange/red/gray`，图标 + 短词；
  “Not fetched” 用灰色，“Cached/stale” 用橙色，“Error” 用红色。
- 优先级：**P1**。

#### P1-3 日志页缺少过滤

- 现状：`CFI diagnostics.js:159-189`：
  - 只有 Refresh / Clear Logs 两个按钮，没有级别/时间/关键字过滤；
  - Clear Logs 与刷新同组，但确认文案只说明“清除日志”，没有说明是否可恢复；
  - IP History 用普通表格（`diagnostics.js:258-264`），刷新按钮单独一行（`diagnostics.js:239-253`）。
- 参照：upnp 在日志控制行放级别下拉（`upnp diagnostics.js:77-139`）；
  nginx 放站点选择 + Filter 输入（`NGINX logs.js:80-97`）；
  两边的清空按钮都与刷新同在按钮组（upnp `diagnostics.js:169`；nginx `logs.js:108-120`）。
  危险区只用于不可逆的初始化回滚（upnp `diagnostics.js:189-193`）。
- 截图：[cfi-logs.png](screens/cfi-logs.png) vs [upnp-logs.png](screens/upnp-logs.png)。
  cfi 的“Recent Logs”像一个大空盒子，操作和内容没有层次。
- 期望：控制行 = 过滤 + 刷新；清空与刷新同组并保留二次确认；IP History 用徽标/等宽字体；
  空态用斜体占位而不是虚线卡片。
- 优先级：**P1**。

#### P1-4 移动端主导航折成三行

- 现状：`CFI ui.css:429-434` 在 ≤900px 强制 `flex-wrap: wrap`，
  390px 下 6 个页面标签折成 3 行（2 个/行）。
- 参照：upnp/nginx 都没有覆写 tabmenu，保持原生横向滚动。
- 截图：[cfi-overview-390.png](screens/cfi-overview-390.png) vs
  [upnp-overview-390.png](screens/upnp-overview-390.png)、
  [nginx-overview-390.png](screens/nginx-overview-390.png)。
- 期望：恢复原生单行横向滚动；如必须提升可发现性，用滚动阴影/渐隐提示，
  不要多行折行。
- 优先级：**P1**。

#### P1-5 390px 下长值挤压/换行

- 现状：`CFI overview.js:448` 的 Service Information 表使用 `cfi-kv-table`（包装在 `overview.js:526`）；
  它没有 `cfi-responsive-table`，因此 `CFI ui.css:493-545` 的卡片化规则不覆盖它。
  在 390px 下 `LAST RUN TIME` 换 2 行、`GITHUB` 链接换 2 行，值列明显过窄。
- 参照：upnp/nginx 的 KV 值较短，未出现同类问题；其响应式规则允许表格转卡片。
- 截图：[cfi-overview-390.png](screens/cfi-overview-390.png)。
- 期望：≤600px 时把 KV 行改为“标签在上、值在下”的两行结构；
  时间戳/URL 用 `word-break:break-word` 并允许整行占满。
- 优先级：**P1**。

### 6.3 P2：一致性/精细度问题

#### P2-1 Settings 单组过长

- 现状：Speed Test 一组 13 行（`CFI settings.js` 的 Speed Test 段），
  1280×800 首屏截断，用户需要长滚动。
- 参照：upnp 设置分 3 组，每组 ≤6 行（Service & Sync / Automation / Logging）。
- 期望：拆成 “Speed Test” / “Measurement & Ranking” / “Service” 三组，
  保持现有字段与保存行为不变。
- 优先级：**P2**。

#### P2-2 Intelligence 原始字段密度高

- 现状：页面直接展示 `runtimeVersion`、`fallbackReason`、`_context_policy` 等字段，
  长字符串与 “—” 占满一列；相关代码见 `CFI intelligence.js:15-37,192-251`。
  注意：`intelligence.js:63-105` 已对 Live State 做了折叠/复制，问题集中在 DummyValue 原始字段。
- 参照：upnp/nginx 的只读详情都先给摘要 + 折叠原始数据。
- 截图：[cfi-intelligence.png](screens/cfi-intelligence.png)。
- 期望：顶部保留 `runtimeSummary` 一行结论；原始字段默认折叠；
  “—” 统一用灰色徽标或省略整行。
- 优先级：**P2**。

#### P2-3 按钮 hover 位移

- 现状：`CFI ui.css:158-165` 给所有按钮加 `transition` 和 `translateY(-1px)` + 阴影。
- 参照：两边都没有静态按钮的 hover 位移。
- 期望：删除位移与阴影，仅保留主题原生 hover；保留 `prefers-reduced-motion` 处理。
- 优先级：**P2**。

#### P2-4 输入框与按钮的“应用化”皮肤

- 现状：`CFI ui.css:124-136` 输入框 `min-height:2.35rem; border-radius:8px`；
  `CFI ui.css:153-159` 按钮 `min-height:2.35rem; border-radius:8px; font-weight:600`。
- 参照：两边都使用原生 CBI 控件尺寸与圆角（仅行操作加 padding）。
- 截图：1280px 下差异不大；深色模式下 cfi 的输入框圆角与按钮字重更明显。
- 期望：移除 `min-height`、`border-radius`、`font-weight`；保留 focus-visible outline。
- 优先级：**P2**。

#### P2-5 标题与分组标题过重

- 现状：`CFI ui.css:44-50` 页面标题 `clamp(1.35rem,...,1.8rem) / 700 / -0.015em`；
  `CFI ui.css:66-72` 分组标题 `1.05rem / 700 / -0.01em`；表单标签 600（`CFI ui.css:110-114`）。
- 参照：全部使用 LuCI 原生标题与字重，没有负字距。
- 期望：删除覆盖，交回主题；最多保留 `margin` 控制。
- 优先级：**P2**。

#### P2-6 空态虚线卡片

- 现状：`CFI ui.css:280-285` `.cfi-empty-state` 使用虚线边框 + 12px 圆角 + muted 背景。
- 参照：nginx 空态是居中文本（`NGINX ui.css:267-271`）；upnp 日志空态是斜体内联文本。
- 期望：去掉虚线框与背景，改为居中次要色文本。
- 优先级：**P2**。

#### P2-7 徽标文本色写死

- 现状：`CFI ui.css:9-12` 定义 `--cfi-success-text:#176b31` 等固定浅色值，并在深色模式覆盖（`:23-31`）；
  参照直接用 `var(--success-color)`（`UPNP ui.css:22-25`）。
- 风险：自定义主题或高对比度模式下，固定浅色文本不跟随。
- 期望：badge 文本直接使用语义变量；若担心对比度，统一加深/提亮同一变量，而不是分叉出第二套色板。
- 优先级：**P2**。

---

## 7. 建议的改造顺序与文件级落点

### Phase A：回到原生视觉语言（只动 CSS + 删除内联样式）

1. `CFI ui.css:52-64` 删除 section 背景/边框/圆角/阴影。
2. `CFI ui.css:13-17` 只保留 `--cfi-radius-card: 8px` 与 chip `4px`；删除 `--cfi-radius:12px`、两个 shadow。
3. `CFI ui.css:216-223` 删除表头底色、大写、字距、700；保留 `nowrap`。
4. `CFI ui.css:44-72` 删除标题/分组标题的字号、字重、字距覆盖。
5. `CFI ui.css:124-165` 删除输入框/按钮的 min-height、圆角、字重、hover 位移。
6. 删除 `CFI overview.js:191-220,262` 与 `CFI diagnostics.js:12-33,62` 的样式注入；
   把仍在使用的 `.cfi-status-*`、`.cfi-ip-table` 规则并入 `CFI ui.css`。
7. 删除 `CFI diagnostics.js:226,239` 的内联 style，改类名。

验收：G-01/G-02/G-03/G-07/G-08/G-15 全部通过；
1280 与 390 截图与参照并排无明显“浮卡”差异。

### Phase B：语义与信息层次

1. `CFI overview.js:306-327` 重排统计卡：只保留计数/状态；其余移入 Service Information。
2. `CFI overview.js:308` 的 0 不再无条件红色。
3. `CFI sources.js:76-86` 状态改徽标；`CFI utils.js:170-176` 增加状态→颜色映射。
4. `CFI diagnostics.js:159-189` 加过滤；`diagnostics.js:191-265` 改造日志区与 IP History。
5. `CFI ui.css:429-434` 移除 tab 折行；`CFI ui.css:493-545` 增加 KV 表响应式规则
   （当前只覆盖 `cfi-responsive-table` / `cfi-source-table`，见 `overview.js:448,526`）。
6. `CFI ui.css:280-285` 空态去装饰。

验收：G-04/G-05/G-06/G-10/G-11/G-12/G-13 通过；
状态列在 1280 截图中可 3 秒内扫出异常。

### Phase C：信息架构与细节

1. `CFI settings.js` 拆分 Speed Test 组。
2. `CFI intelligence.js` 原始字段默认折叠、统一空值。
3. `CFI ui.css` 徽标文本色改为语义变量，跑深色/浅色对比度。
4. 统一 section 间距为 `1.5em`。

验收：G-09/G-14/G-16 通过；深色模式截图无明显低对比徽标。

---

## 8. 是否沉淀为 skill

**不做 skill，保留为文档。** 理由：

1. **规范的证据是行号级的。** 本文件每一条都指向这两个仓库的具体文件与位置；
   skill 的通用描述会自然抹掉这些引用，而把行号写进 skill 又会随代码更新迅速失效。
2. **规范不是跨项目通用的。** 它是“LuCI + Aurora + 这三个插件”的具体语言，
   换到非 LuCI 项目会误导；做成全局 skill 收益低、维护成本高。
3. **没有需要自动化的重复流程。** 规范的使用方式是人工对照截图与 CSS；
   不需要脚本、工具调用或固定输入输出，skill 的运行时价值为零。
4. 若未来需要复用，建议以 **仓库内文档 + 第 5 节判定清单** 的形式复制，
   而不是抽成技能；判定清单本身就是可执行的 review checklist。

---

## 9. 附录

### 9.1 截图索引

| 文件 | 说明 |
|---|---|
| `screens/upnp-overview.png` | 参照 A 总览（状态横幅、统计卡、KV 表） |
| `screens/upnp-overview-390.png` | 参照 A 390px 总览 |
| `screens/upnp-overview-dark.png` | 参照 A 深色总览 |
| `screens/upnp-settings.png` / `upnp-settings-dark.png` | 参照 A 设置分组与表单 |
| `screens/upnp-mappings.png` | 参照 A 列表页/行操作 |
| `screens/upnp-network.png` | 参照 A 分段控件与信息提示 |
| `screens/upnp-logs.png` | 参照 A 日志空态与危险区 |
| `screens/upnp-wizard.png` / `upnp-security.png` | 参照 A 独有页面，仅作参考 |
| `screens/nginx-overview.png` / `-390.png` | 参照 B 总览与窄屏 |
| `screens/nginx-sites.png` / `-dark.png` | 参照 B 表格与徽标 |
| `screens/nginx-certificates.png` | 参照 B 证书状态徽标 |
| `screens/nginx-logs.png` | 参照 B 过滤控件 |
| `screens/nginx-core-config.png` | 参照 B 表单/代码区 |
| `screens/cfi-overview.png` / `-390.png` / `-dark.png` | 目标总览（问题主证据） |
| `screens/cfi-settings.png` / `-dark.png` | 目标设置（长分组、控件皮肤） |
| `screens/cfi-sources.png` | 目标数据源（纯文本状态） |
| `screens/cfi-intelligence.png` | 目标 Intelligence（原始字段密度） |
| `screens/cfi-logs.png` | 目标日志（缺过滤/危险区） |
| `screens/cfi-advanced.png` | 目标高级设置 |
| `screens/cfi-openclash.png` | 目标 OpenClash 集成 |

### 9.2 关键引用速查

| 主题 | 引用 |
|---|---|
| upnp 共享 CSS 加载 | `UPNP utils.js:107-116,197-202` |
| nginx 共享 CSS 加载 | `NGINX utils.js:45-53,141-146` |
| cfi 共享 CSS 加载 | `CFI utils.js:486-495,578` |
| 状态横幅（upnp） | `UPNP ui.css:70-87` |
| 状态横幅（nginx） | `NGINX ui.css:315-327` |
| 统计卡（upnp） | `UPNP ui.css:88-106` |
| 统计卡（nginx） | `NGINX ui.css:330-346` |
| 徽标（upnp） | `UPNP ui.css:18-25` |
| 徽标（nginx） | `NGINX ui.css:8-18,20-38` |
| 表格滚动/KV（upnp） | `UPNP ui.css:196-217` |
| 表格响应式（nginx） | `NGINX ui.css:424-446` |
| 危险区（upnp） | `UPNP ui.css:190-193` |
| 日志区（upnp/nginx） | `UPNP ui.css:180-189`；`NGINX ui.css:170-185` |
| cfi 卡片化 | `CFI ui.css:13-17,52-64` |
| cfi 表头皮肤 | `CFI ui.css:207-223` |
| cfi 表单/按钮皮肤 | `CFI ui.css:124-165` |
| cfi 内联样式 | `CFI overview.js:191-220,262`；`CFI diagnostics.js:12-33,62` |
| cfi 统计卡语义 | `CFI overview.js:306-327` |
| cfi 数据源状态 | `CFI sources.js:76-86`；`CFI utils.js:170-176` |
| cfi 日志页 | `CFI diagnostics.js:159-189,191-265` |
| cfi 移动端 tab 折行 | `CFI ui.css:429-434` |

### 9.3 未覆盖的场景

- 错误态（RPC 失败、CFST 未安装、无网络）未人为制造；只读取了自然存在的状态。
- PassWall 页面在本机不可用。
- 未验证 Safari/Firefox；截图仅覆盖 Chromium。
- 未评估 LuCI 主题切换器本身（Argon/Bootstrap 等）的差异；本规范以 Aurora 实测为准，
  但颜色均走主题变量，迁移到其他主题时应重新核对对比度。

---

## 10. 最终判断

- 这套规范**值得落地**：两个参照仓库在核心组件上高度一致，足以形成稳定基线。
- cloudflare-ip **可以保留自己的信息化差异**（例如更适合本功能的 KV 表、单个命令框、
  折叠诊断），但不应保留与基线冲突的卡片皮肤、表头皮肤和控件皮肤。
- 先做 Phase A 就能消除大部分“丑”的观感；Phase B 解决“看不懂/状态不突出”；
  Phase C 是精修。
