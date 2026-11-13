# Changelog

本文件只记录已闭合、可由 exact-SHA CI 复现的用户可见变更。历史版本详情以对应 GitHub Release 的 `qualification.json` 与 Release notes 为准。

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
