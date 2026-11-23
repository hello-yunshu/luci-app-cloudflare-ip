# Changelog

## Unreleased — shared Runtime management (package release 2.6.2-r31)

### 变更

- 智能优选页的 Rill Runtime 软件包管理（检查更新/安装/修复/更新/卸载/更新 CFI）从「实时状态」里抽出来，独立成节放在 Rill 区块最前面；「实时状态」只保留只读遥测，调参项仍留在「Rill Runtime 接入」。
- 「检查更新」所在行的行标题由「Runtime 软件包管理」改为「软件源索引」，和性能管理器同名同位置：这一行做的是刷新统一软件源的索引，再顺带报告运行时有没有更新，用「软件包管理」当标题会让人以为它要改装什么。按钮文字与下面的说明保持原样。
- 同一节新增「上次检查」一行，只记时间（`未检查时写“本次会话尚未检查”`）：点「检查更新」后先存下时间再刷新，页面重载后仍能看到上次问过软件源的时刻。此前检查完只弹一次通知就刷新，通知被冲掉，「刚查过、是最新」和「根本没查」在页面上分不出来。有无更新仍由上面「Runtime Package Status」一行表述，这一行不重复它；结论只存在当前会话，关标签页即清。
- 单目标域名探测默认超时由 5 秒放宽到 8 秒（`probe_timeout`，可 1..30）：设备实测成功样本已到 3.3 秒，5 秒余量过薄，一次正常的慢握手就会被判失败并回滚整笔事务。
- 增加统一软件源 Runtime 管理器交互，提供 Runtime 状态、安装、更新及受限的同版本修复；Runtime 仍为 CFI 可选能力，Native 模式不受影响。
- 环境检测仅列出已检测到的代理软件；没有支持的软件时显示一次未检测到提示。
- 包构建、签名 feed 发布、干净安装与设备升级资格仍待验证；此条目不表示已发布。

### 修复

- 应用后校验的 settle 预算不再写死 30 秒：改为按 `探测数 × 探测超时 × 2 + 退避（2+4+8）` 计算（下限 30、上限 120，仍受全局 measurement 截止时间约束）。原先 2 个 IP × 2 个域名 × 8 秒一轮最坏 32 秒，预算连一整轮都不够，重试名存实亡；现在剩余预算不足以跑完整轮时不再启动重试，避免 `cfip_probe_one` 把最后几个探测截断成假超时。`outcome.json` 的 `serviceSettling` 同时记录 `roundBudgetSeconds`。
- `tests/v2-observation.sh` 的 settle 断言此前是 `case` 分支里的裸 `[[ ]]`，在 `set -e` 下失败不会中断脚本，等于永远通过；改为显式 `exit 1` 并在负向用例中确认会真的失败，`short_budget` 语义同步为「预算不足时不启动重试」（1 轮 / 4 次探测）。
- 应用后校验失败不再只留一句 `post-apply validation failed`：运行错误会带上失败探测数与首个失败的目标（如 `1/4 probes failed: 103.31.4.56 -> assets.hey.run (timeout) (limit 8s)`），概览页同时说明「新节点未通过实际访问校验、已自动回滚、旧节点仍在工作、可调大探测超时」，技术详情保留原始原因；结果徽标在真的回滚时标注「已回滚」。
- Rill Runtime 调用的 stderr 不再原样追加进 `cf-ip-auto.log`：三处 `2>>"$CFIP_LOG_FILE"` 改为有界捕获 + 单行摘要（`cfip_stderr_summary`，跳过 `bash -x` 的 `+` 追踪行并截断）。设备上的日志曾出现单次 1164 行追踪输出，占全文件 1185 行中的 98%，真实历史被埋掉；现在一次失败只留一行带时间戳的记录，且同类失败用 `cfip_log_once` 去重，成功后自动解除。

已发布条目只记录可由 exact-SHA CI 复现的用户可见变更；`Unreleased` 明确表示尚未发布或资格验证的候选。历史版本详情以对应 GitHub Release 的 `qualification.json` 与 Release notes 为准。

## v2.6.2-1 — 2026-11-13

### 修复

- 内置来源多选在无法完整显示选中项时折叠为「已选 N 项」，避免原生 MultiValue 第 4 项起只留 `···`、长标签被硬裁切；展开面板仍可看到全部勾选项，控件高度保持该主题原生高度（aurora 36.75px / bootstrap 30px）。
- 折叠样式直接作用于 `.cfi-source-picker`，不依赖正常渲染路径下并不存在的 `.cfi-form-map`；spacing 变量补 `.25rem` 兜底；隐藏原生 `···` 占位需要压过主题 `.cbi-dropdown[multiple][more] > .more` 的 `!important` 规则。

## v2.6.1-1 — 2026-11-13

### 修复

- Makefile 在 po2lmo 缺失时直接失败，不再静默生成空 lmo；去掉 msgid 首尾空白，使 `_()` 的 trimws 能命中翻译。
- 按钮组/操作列按主题 spacing 变量留间距，同页表格首列统一 `min-width:9rem` / 左对齐。
- 页脚容器改为 `div` 并移除自身 `border-top`，避免 bootstrap 裸 `footer` 选择器再次画出横线。

## v2.6.0-14 — 2026-11-13

### 修复

- 恢复被删掉的统一版本条 `.ys-tool-footer`：四仓共用同一段结构与样式，仅项目名、仓库链接与版本号按仓取值；窄屏（≤600px）隐藏标题与文字标签，只保留图标。
- 表格回归原生契约（`.tr/.th/.td` + `data-title`），窄屏堆叠交给主题；补齐页面加载失败时的错误兜底，避免空白页。

## v2.6.0-13 — 2026-11-10

### 修复

- 删除工具页页脚上方的 1px 分隔线：移除 `.ys-tool-footer` 的 `border-top` 及仅供其使用的 `--cfi-footer-border` 变量。设备实测该线由本项目声明（命中 `.ys-tool-footer`），Aurora 原生 `footer` 无边框；删除后 `.ys-tool-footer` 的 computed `border-top-width` 为 `0px`（深色/浅色均如此），页脚下方由 LuCI 原生 `.cbi-page-actions` 提供的分隔线保持不变。

### 备注

- v2.6.0-12 为这条线所做的 `--hairline` 配色调整随声明一并失效。回退：在 `.ys-tool-footer` 中恢复 `border-top: 1px solid var(--cfi-footer-border);` 并在 `:root` 恢复 `--cfi-footer-border: var(--hairline, var(--border-color, #d9e0e7));`。

## v2.6.0-12 — 2026-11-09

### 修复

- 页脚分隔线颜色改用主题 `--hairline`（`--cfi-footer-border: var(--hairline, var(--border-color, #d9e0e7))`）：Aurora 不定义 `--border-color`，旧 fallback 让 1px 分隔线固定为 `rgb(217,224,231)`，深色下对比度约 11.4:1；改用原生 hairline 后深色约 1.25:1，浅色与 Aurora 原生分隔线一致。无 `--hairline` 的主题仍按 `--border-color` → `#d9e0e7` 回退。

### 备注

- 仅 CSS token 变更，未改包内容契约；upnp / nginx 的同类缺失 fallback 另行对齐。

## v2.6.0-11 — 2026-11-09

### 变更

- UI 主题复用收敛（`99fd613`）：删除遮蔽 Aurora 原生 `.cbi-value` 网格、输入框宽度、表格边框/圆角/padding 与窄屏按钮缩放的 158 行自定义覆盖，修复深色表格亮边、设置页子项错位和移动端按钮拥挤；只保留原生样式覆盖不到的横幅、徽标对比度、徽标/统计卡几何与功能版式规则。
- Rill Runtime 依赖契约推进（PR #32）：`contracts/rill-runtime.json` 将 OpenWrt 包 pin 更新到 `0567336375f4cd3cae29c013699ca9279d0ace52`，qualification run `42169166493`（PASS，attempt 1），`manifestSha256` 同步为 `2b98f49d3154a3388876181f6ced9a923870a2e528061f36abf5b3fda0ae2517`；该候选的 consumer CI 21 个 job 全部通过。

### 备注

- 本版本在 `d0455c2` 的干净工作树上产出，未打 tag、未发布；`release-channel.json` 保持 `stable` 不变。

## v2.6.0-9 — 2026-11-05

### 修复

- LAN Result Publisher 就绪检查在 OpenWrt 24.10.8 当前 feed 的 `curl 8.22.0-r1` 上恒失败：`--max-time 1` 被 curl 以 `remaining timeout of 999 too small to resolve via SIGALRM method` 拒绝。就绪/端点检查改为 `--connect-timeout 2 --max-time 2`，发布器可在当前 curl 上进入 ready（P1-06）。
- publisher 测试改为使用真实 procd/uhttpd：uhttpd fixture 使用 shipped UCI 基线并隔离 rill state；procd fixture 断言注册的 interface trigger 并执行真实 reload。两者纳入 CI `publisher-runtime`。

### 文档

- 新增升级失败与 ENOSPC 回滚流程（`docs/ROLLBACK_AND_RECOVERY.md`），包含 `/usr/lib/opkg/status` 备份/原子恢复与 `opkg install --force-reinstall` 步骤。
- Stable Gate 维持 **NOT READY**：物理设备、多架构、24h soak、PassWall 真实网络、真机触控、真机断电/ENOSPC 仍未覆盖。

### 验证

- 真实 24.10.8 容器：两个 publisher fixture 与其余 7 个 publisher 测试全部 PASS；`tests/opkg-status-recovery.sh` PASS。
- 21 项 CI job 全绿（含新增 `publisher-runtime`）；Real LuCI UI Gate success。

## v2.6.0-8 — 2026-11-04

### 修复

- OpenClash 备份删除只在 `success === true` 时提示成功；失败时保留错误与备份文件，不再假成功刷新。
- RPC 失败与“未安装/空数据”分离：OpenClash、Sources、PassWall、Settings 的失败显示人类可读说明 + 可展开/可复制的技术详情。
- Sources 刷新不再整页 reload，保留未保存的自定义来源/预算草稿。
- Rill reset 成功后重新读取并反映状态；修复 LuCI `form.Button` 的 `ev.currentTarget` 事件参数导致的 busy 态缺失。
- 简体中文补齐：516 keys（JS 507 + menu 9），POT/zh_Hans/en 各 552 条；动态状态码与 raw error 进入语言门禁。

### 变更

- legacy 自更新下线：`AUTO_UPDATE=false`、`SELF_UPDATE_URL=""`；`--self-update` 返回失败（rc 1），自动运行路径不再 fetch 或替换脚本。
- Advanced 的弃用字段 `self_update_url` 改为只读；保留 UCI 字段以避免升级丢配置。
- `uhttpd` 从硬依赖移除，仅 LAN Result Publisher 在运行时探测；nginx/lighttpd 系统不会被动安装第二套 Web 服务。
- 统一错误呈现与动态状态映射；深色配色只由 LuCI/Aurora `data-darkmode` 决定。

### 验证

- 51 点七态矩阵：357 个状态单元，121 PASS / 236 N/A / 0 FAIL；覆盖算法 `PASS/(PASS+FAIL)=121/121=100%`。
- 真实 Chrome 125%/150%/200% 页面缩放 + 320 reflow：8 页 × 3 档 0 横向溢出、0 文字截断、0 主内容焦点环缺失；zh_cn 375/1280 共 16 页 0 英文残留、0 msgid 泄漏、0 截断。
- 本地测试盘点：254 个脚本，247 在 CI，7 个登记理由排除，0 遗漏；`tests/ci-test-inventory.py` 在 CI `workflow-lint` job 强制检查。
