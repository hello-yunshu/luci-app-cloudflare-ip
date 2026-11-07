# P2 一致性/精细度收尾（2026-11-08）

- 基线：`main@4659503`（P0/P1 已由 #40/#42 合入）
- 分支：`fix/ui-spec-p2`
- 规范：`docs/ui/design-spec-2026-11-08/SPEC.md` §6.3（P2-1 ~ P2-7），位于 `luci-ui-spec-worktree`
- 约束：只改表现层；不动功能行为、RPC 字段、uci 配置项与文案含义；只读走查。

## 1. 做了什么（P2-1 ~ P2-7）

| 项 | 结论 | 改动 | 证据 |
| --- | --- | --- | --- |
| P2-1 Settings 单组过长 | 做 | 13 行拆成 4 组：Service（3 行，含 Mode）/ Speed Test（5 行）/ Measurement & Ranking（4 行）/ Service Handling（2 行）。四个 section 均为同名 `form.TypedSection 'service'` + `anonymous=true`，仍写入同一具名 section `main` | DOM 探针：全部字段 id 仍为 `cbi-cf_ip-main-*`；`tests/luci-save-singleflight.cjs`、`tests/luci-staged-validation.sh` PASS |
| P2-2 Intelligence 原始字段过密 | 做 | 顶部新增无标题只读摘要（Runtime，一行 `runtimeSummary`）；原 11 个 DummyValue 移入 `Adaptive Readouts` 并默认折叠进 “Technical Details”；`Recent Runs` 从长串改为 8 列 `.table`（Time/Result/Best IPs/Adaptive/Candidate/Probes/Fallback/Duration） | `after/intelligence.png`、`after/intelligence-expanded.png`、`after/intelligence-dark.png` |
| P2-3 按钮 hover 位移 | 做 | 删除 `transition` + `translateY(-1px)` + hover 阴影，仅剩主题原生背景/边框过渡 | 容器探针：rest 与 hover 均为 `transform:none`，阴影在 hover 前后同值（`after/evidence-hover-container.json`） |
| P2-4 输入框/按钮皮肤 | 做 | 删除输入框 `min-height:2.35rem`、`border-radius:8px`；删除按钮 `min-height`/`border-radius`/`font-weight:600` | 设备计算样式：input 37.6px/8px → 0px/主题 16px；button 37.6px/8px/600 → auto/主题 12px/500 |
| P2-5 标题字重偏重 | 做 | 删除 `.cbi-map-title`、`.cbi-section > h3`、`.cbi-value-title` 的字号/字重/字距覆盖，只保留 margin/padding | 设备计算样式：section 标题 16.8px/700 → 20px/600；表单标签 600 → 500 |
| P2-6 空态虚线卡片 | 做 | `#maincontent .cfi-empty-state` 去掉边框/圆角/背景/阴影，改为居中次要色文本（必须带 `#maincontent` 前缀，Aurora 的 `#maincontent .cbi-section` 特异性更高） | `container-empty/sources-empty-before.png` / `-after.png`（同容器、同主题、同视口） |
| P2-7 徽标文本色写死 | 做 | 删除 `--cfi-success-text/--cfi-danger-text/--cfi-warning-text/--cfi-neutral-text` 及深色覆盖；badge、stat value、status icon/text 全部改用 `--success-color/--danger-color/--warning-color/--cfi-muted` | 设备计算样式：danger `#a52020` → `#d94b4b`；dark green `#8ce8ac` → `#3aa657` |

顺带（同属 P2-3/P2-4 的连带清理）：删除 `--cfi-radius`、`--cfi-shadow`、`--cfi-shadow-hover` 三个只为上述规则存在的变量；`prefers-reduced-motion` 只剩脉冲动画一条。

## 2. 哪些判定为“不做”，以及理由

1. **空态在设备上复现** — 不做。设备当前未安装 PassWall，四源页会回退到 Overview，空态无法自然出现；按事前约定不为了截图改动设备配置，只在容器里做同主题、同视口的对比。
2. **深色徽标单独分叉第二套色板** — 不做。规范明确要求“统一加深/提亮同一变量，而不是分叉第二套色板”，因此仍走 `--danger-color`。
3. **`.cfi-copy-btn`、`.cfi-link-button` 等行内小按钮统一到原生表单控件尺寸** — 不做。它们不是 CBI 表单提交控件，套用原生 `min-height` 会把表格/详情行撑高；规范参照对象是表单控件。
4. **整表外壳（边框/圆角）与 `.cbi-value` 行分隔线统一** — 不做。不在 P2 明确清单内，且属 P0 已收敛的范围；本次只复用原生 `.table`，不再包一层皮肤。
5. **Intelligence 的 Live State 拆成独立页/独立卡片** — 不做。属于导航结构改动，超出“只改表现层”。
6. **运行历史表加排序/分页/筛选** — 不做。属功能增强，P2 只允许表现层。

## 3. 已知权衡（不粉饰）

- 深色模式下 danger 徽标文本 `#d94b4b` 对 `#262624` 背景约 3.6:1，低于 WCAG AA 4.5:1。这是“徽标文本跟随语义变量”的直接结果，修复责任应在主题（Aurora 深色下提亮 `--danger-color`），本应用不再维护第二套色板。
- 设备侧 `intelligence-expanded.png` 只有 after：`main@4659503` 的展开逻辑只覆盖 rill 的 `_state`，而设备没有 rill 配置 section，before 不存在可展开区域。
- 设置页分组为 4 组而非规范举例的 3 组：13 行按语义均分后每组 ≤5 行，且 Mode 与 Service 生命周期绑定，放在 Speed Test 组会重新变成 8 行。

## 4. 测试

| 检查 | 结果 |
| --- | --- |
| `node --check`（settings.js / intelligence.js） | PASS |
| `tests/i18n-contract.py` | PASS（527 keys；POT/zh_Hans/en 均为 563） |
| `tests/i18n-dynamic-contract.py` | PASS |
| `tests/luci-view-bindings.cjs` | PASS |
| `tests/luci-save-singleflight.cjs` | PASS |
| `tests/luci-ready-state.cjs` | PASS |
| `tests/luci-run-status.cjs` | PASS |
| `tests/luci-refresh-error.cjs` | PASS |
| `tests/rill-intelligence-luci-contract.sh` | PASS |
| `tests/luci-validation-contract.sh` | PASS |
| `tests/luci-staged-validation.sh` | PASS（EXIT=0） |
| `tests/real-luci-ui-visual.cjs`（容器 24.10.8，8 页 × 5 宽度 × 3 主题） | PASS 120/120 |
| `tests/real-luci-ui.cjs`（容器交互门禁） | PASS（草稿保留 / 日志弹窗 / reduced-motion / RPC 错误态） |

视觉门禁首次重跑在 `bootstrap-light 375 openclash` 出现一次浏览器进程崩溃（`Target page, context or browser has been closed`），重跑后 120/120 全过，判定为瞬态环境问题，未改任何断言。

`ci-test-inventory.py` 会列出工作区里 903 个 iCloud 生成的 `* 2.*` 未跟踪重复文件（其中 800 个与原件 md5 相同）；这些文件未被提交，也未删除，属工作区噪音而非本次改动。

## 5. 设备侧做法与安全边界

- 设备（OpenWrt 25.12，Aurora，1280×900）通过只读 `ubus session` 采证：`scope` 按 `access-group` / `ubus` / `uci` / `file` 分别 grant，cookie `sysauth_https`。
- 亮/暗两套 before/after 均在同一设备、同一视口、同一主题下采集；深色用 `prefers-color-scheme: dark`（Aurora 纯 CSS 实现）。
- 只替换了三个静态文件，窗口约 1.5 分钟；替换前确认 `/root/cfip-soak-20261108-12h.sh` 只轮询 ubus/procs/cron/日志，不访问 HTTP/静态资源，`samples.log` 5 分钟节奏连续（procs=2 未变）。
- 采证后三文件按 md5 恢复至 `main@4659503`（settings.js `141b885c…`、intelligence.js `a5be86fe…`、cloudflare-ip.css `b5f2b7ea…`），只读会话已 `session destroy`，全程未点保存/应用/重启。

## 6. 截图

- 亮色：`before/`、`after/`（overview / settings / sources / intelligence / intelligence-expanded / openclash / passwall，`evidence-light.json`）
- 暗色：`before/*-dark.png`、`after/*-dark.png`（`evidence-dark.json`）
- 空态：`container-empty/sources-empty-before.png`、`sources-empty-after.png`
- Hover / 控件计算样式：`after/evidence-hover-container.json`
