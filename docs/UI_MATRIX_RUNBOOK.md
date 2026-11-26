# 四仓真实 LuCI UI 矩阵运行手册

> 共享文档，四仓内容保持一致。权威维护副本位于 PM 仓库；改动后同步到 NGINX、UPNP、CFI。
> 本手册固定可复现的真实浏览器断点矩阵。它说明自动截图矩阵的范围，不把自动检查等同于完整 UI 验收。

## 0. 四仓文档审计结论

- 四仓 `docs/UI_DESIGN_SPEC.md` 的共享正文一致；原规范保留六主题作为默认正式矩阵，但此前没有说明用户明确排除某主题时如何标记范围，也没有端到端运行说明。
- PM、NGINX、UPNP、CFI 的断点值和附加状态套件不完全相同，不能用单一“每仓相同宽度/页数”的行数估算。本手册分别列出脚本实际覆盖和行数。
- NGINX、UPNP 原先没有独立矩阵运行手册。CFI 的 `next-release-visual-matrix.md` 明确是旧 SHA 的历史证据，不作为当前矩阵定义。
- 审计时 CFI 规范首页的 CSS 缓存键落后于当时工作区代码，先同步为 `backup-list-scroll-1`；随后诊断区间距修复将运行时缓存键更新为 `rill-diagnostics-gap-1`，规范和矩阵选择器断言也已同步。四仓首页现均链接本手册。

## 1. 矩阵配置

- OpenWrt：`openwrt/rootfs:x86_64-24.10.8`，真实 `uhttpd`、`rpcd`、LuCI。
- 浏览器：Playwright `1.55.0`；工作流安装并记录实际 Chrome/Chromium 版本。
- 语言：`en`、`zh_cn`。完整双语矩阵两种语言都必须有终态报告。
- 默认主题集：`all`，六种模式；用于标准 CI。
- 本次可复现的非 Aurora 主题集：`bootstrap-only`，四种模式：
  `bootstrap-default-light`、`bootstrap-default-dark`、`bootstrap-light`、`bootstrap-dark`。
- 统一选择变量：`LUCI_UI_THEME_SET=all|bootstrap-only`；省略时为 `all`。工作流手动运行输入 `theme_set` 也使用这两个值。
- `bootstrap-only` 将 `aurora-light`、`aurora-dark` 标为 `N/A（本次明确排除）`，不得记作 PASS，也不得宣称六主题验收通过。默认 Push/PR 工作流仍跑六主题。
- 视口包含各仓列出的常用宽度、每个插件断点的 `b−1 / b / b+1`，以及 `320×568`、`568×320` 两种短视口。
- 矩阵自动覆盖真实 LuCI 路由、页面初始状态和各仓声明的扩展状态。交互套件与断点矩阵分开计数。

## 2. 每仓覆盖与行数

下表行数按 `LUCI_UI_THEME_SET=bootstrap-only` 计算。每种语言独立计算；两种语言的行数相加。脚本最终输出的 `expected` 必须与实际 `total` 相同，且 `fail=0`。

| 仓库 | 常用宽度 + 断点邻值 | 短视口 | 主要路由 / 状态 | 每语言行数 | 双语行数 |
|---|---:|---:|---|---:|---:|
| PM | 39 + 6 个概览专用邻值 | 2 | 8 页 × 39 宽度及 2 短视口；健康快照和被动观测各覆盖同样视口；概览断点套件；Benchmark 结果态套件 | 1,992（all: 2,988） | 3,984（all: 5,976） |
| NGINX | 34 | 2 | 8 页 + 根路由别名；含工作流种入的站点、证书、备份和日志数据 | 1,156（all: 1,734） | 2,312（all: 3,468） |
| CFI | 36 | 2 | 8 页 + 根路由别名；默认页面组及已安装代理集成页面组各跑一遍 | 1,832（all: 2,748） | 3,664（all: 5,496） |
| UPNP | 33 | 2 | 8 页 + 根路由别名；另跑向导模式和 10 步向导流程 | 2,804 矩阵行 + 1 张安全保存截图（all: 4,206 + 1 张） | 5,608 矩阵行 + 2 张安全保存截图（all: 8,412 + 2 张） |

### 各仓行数公式

- **PM**：4 主题 × `((39 宽度 + 2 短视口) × (8 页面 + 2 Benchmark 观察态) + 6 概览断点 + 2 × (39 + 2) Benchmark 结果态)` = 1,992 行/语言。
- **NGINX**：4 主题 × `((34 宽度 + 2 短视口) × 8 页面 + 1 根路由别名)` = 1,156 行/语言。
- **CFI**：4 主题 × `((36 宽度 + 2 短视口) × 8 页面 + 1 根路由别名 + (36 + 2) × 4 代理集成页面 + 1 集成根路由别名)` = 1,832 行/语言。真实交互断言另由 `tests/real-luci-ui.cjs` 运行，不乘主题数。
- **UPNP**：4 主题 × `((33 宽度 + 2 短视口) × 8 页面 + 1 根路由别名 + 35 视口 × 2 向导模式 + 35 视口 × 10 向导步骤)` = 2,804 行/语言。每语言另有 1 张安全保存截图。

> 这些计数来自当前脚本的 `expected` 公式。更新路由、断点或场景时，必须同步更新本表和复现记录；不能通过降低 `expected` 来掩盖漏测。

## 3. 可复现工作流运行

在各仓库的 GitHub Actions 中选择 **Real LuCI UI Gate**，使用以下输入：

| 仓库 | `theme_set` | `language` | 其他输入 |
|---|---|---|---|
| PM | `bootstrap-only` | `all` | `benchmark_result_only=false` |
| NGINX | `bootstrap-only` | 分别运行 `en`、`zh_cn` | 两次运行串行等待完成，避免 concurrency 取消 |
| CFI | `bootstrap-only` | 分别运行 `en`、`zh_cn` | `pages` 留空，保留默认页和代理集成页两组 |
| UPNP | `bootstrap-only` | `all` | `scope=full` |

默认 Push/PR 路径不设置 `theme_set`，继续运行六主题矩阵。局部脚本运行时设置同一环境变量即可选择主题；变量未设置时同样为六主题。PM、NGINX、CFI 的本地默认端口都是 `18080`，UPNP 默认 `18083`；同机运行要串行，或为容器、端口和输出目录分别指定唯一值。

运行前记录仓库 SHA、工作树状态、当前 diff SHA-256、运行语言、主题集、工作流 run URL 和工作流提交 SHA。工作流的 `theme_set=bootstrap-only` 必须跳过 Aurora 包下载/安装；否则即使脚本不迭代 Aurora，也不能算按本手册完成了无 Aurora 运行。

同一容器内，切换语言或主题以及重启 uhttpd 的套件必须串行。需要并行时，每个执行组使用独立容器、端口和证据目录。CFI 默认组须确认没有代理测试夹具，再运行已安装代理组。切换语言后重新准备默认组，避免沿用上一轮的夹具。

## 4. 产物与复核

原生样式按 [设计规范](UI_DESIGN_SPEC.md) 的 A-1、P-1 至 P-3、H-1 审查。先查视图是否复用 LuCI 核心组件或浏览器原生控件，再查插件 CSS 是否重绘标准控件，或依赖某个主题的类与变量。发现差异时，在同一浏览器、语言和视口检查 DOM 与最终生效规则。可在开发者工具中临时禁用可疑声明，确认来自 LuCI 核心、主题还是插件，并记录规则来源。跨主题截图用于发现问题，正式截图保留主题正常加载时的页面。

1. 下载整个 Actions artifact，先对原始 ZIP 计算 SHA-256，再解压；保留原始 ZIP 和校验值。
2. 确认每个语言报告中的主题 ID、宽度、路由和状态符合本手册；逐项核对报告行的主题、语言、路由、视口（宽 × 高）和场景，排查重复或缺项。确认实际行数等于预期且失败数为 0。范围内的预期 N/A 算作已覆盖行，排除的主题不产生矩阵行。
3. 正式 E-2 验收时打开全部截图并按报告行建立人工复核台账，逐行记录 `PASS / FAIL / BLOCKED / N/A`。`N/A` 写明理由；本次 Aurora 两项的理由固定为“用户明确要求本次排除 Aurora”。
4. 有失败时先分类为页面问题、主题原生行为、数据/路由缺失或陈旧断言，再修正后重跑相同主题集、语言、路由和视口。
5. 记录用于截图的 Playwright 与 Chrome/Chromium 版本、OpenWrt rootfs 版本、脚本 SHA-256。若源代码有未提交改动，额外归档 `git diff --binary HEAD` 的补丁和参与运行的未跟踪文件，并记录 SHA-256；不能把基础 commit SHA 当成脏工作树的完整源码标识。
6. 本矩阵只证明隔离 OpenWrt 上的浏览器布局/状态覆盖。完整 E-2 放行仍需 exact-SHA Actions 终态、可复核截图和人工台账；并按 E-7 在最终候选包上做设备回看。未做的项目写 `BLOCKED` 或 `N/A`，不推断为通过。

## 5. 局部脚本清单

- PM：`tests/real-luci-ui-visual.cjs`、`tests/real-luci-ui-overview-breakpoint.cjs`、`tests/real-luci-ui-benchmark-result.cjs`
- NGINX：`tests/real-luci-ui-visual.cjs`
- CFI：`tests/real-luci-ui.cjs`、`tests/real-luci-ui-visual.cjs`（工作流按默认页和已安装代理集成页分别调用）
- UPNP：`tests/real-luci-ui-visual.cjs`、`tests/real-luci-ui-wizard-mode.cjs`、`tests/real-luci-ui-wizard-flow.cjs`
