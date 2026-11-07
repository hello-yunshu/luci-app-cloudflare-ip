# 界面与功能质量收口结论（2026-11-06）

- **基线**：`luci-app-cloudflare-ip` PR #33 head `a140550`（worktree `cfip-ui-qc`，分支 `qc/ui-completeness-20261106`）。
- **保留资产**：PR #33 的 120/120 初始视图矩阵（run `42186078063`，merge `8bef198`）未改动、未替代重跑。
- **运行环境**：真实 OpenWrt 24.10.8 rootfs（uhttpd + rpcd + LuCI），Aurora 1.4.0，Bootstrap；Chromium for Testing `chromium-1243`。
- **入口命令**：
  `CFIP_QC_MODE=all CFIP_QC_OUT=docs/audits/next-release-evidence/visual-qc-20261106 node tests/real-luci-ui-quality.cjs`
- **最终汇总**：`zh 48/48`、`zoom 48/48`、`states 7 PASS + 1 NOT_APPLICABLE`、`preferences 1/1`、`errors 0`（脚本 exit 0）。
  外层命令包装在脚本结束后触发一次 Chrome Crashpad 目录的沙箱限制报错，不影响测试进程退出码与产物。

## 一、已解决

| 项 | 结论 | 证据 |
|---|---|---|
| 简体中文真实渲染 | 48/48 PASS。真实 lmo（po2lmo 编译，md5 `c47d3a976609b8308350b616633ffee0`）；断言实际 DOM 文案、6 个中文 tab、英文残留零命中、EN/ZH 像素 diff | `zh/` 48 张截图 + `report.json` |
| 浏览器 125% / 200% 缩放 | 48/48 PASS。物理 1280×900 → 1024×720@DPR1.25、640×450@DPR2；断言 `innerWidth`、媒体查询、无横向溢出 | `zoom/1.25`、`zoom/2` 共 96 张截图 |
| 交互成功态 | settings 保存应用 4→5；logs 清空后 `log_bytes=0` | `states/`、`report.json` |
| 交互取消态 | settings 草稿改为 7 后 Reset 回到已应用值 5；logs 取消保留原文件 | `states/` |
| 交互失败态 | settings 在 `validate-config` 传输层 abort 后 `/etc/config/cf_ip` 仍为 5；logs 在 `clear-log` abort 后日志保留 | `states/` |
| 交互回退态 | `ubus call uci revert` 后全新浏览器会话显示 5（同标签页 reload 会被 Chromium 恢复旧 DOM 值） | `states/` |
| P2-04 日志 9–10px 字号 | 源码已为 12px，实测无截断/溢出 | `cloudflare-ip.css` L194-196 等 |
| P2-05 原生 `confirm()` | 统一为 `utils.confirmAction` | `utils.js#confirmAction`、`diagnostics.js:172`、`intelligence.js:377` |
| P2-06 reduced-motion | 首轮探针 FAIL（`cfi-pulse`），根因为 `overview.js` 内联 `<style>` 晚于共享样式表覆盖；补内联 reduced-motion 规则后 `reduce → none`、`no-preference → cfi-pulse`，终轮 preferences PASS | `overview.js` L207-L212、`report.json` |

## 二、仍存在（已确认、未关闭）

| ID | 内容 | 为何不关闭 |
|---|---|---|
| P2-01 | 600/900px viewport 断点与容器宽度风险 | 本轮 375/1280 与缩放无 overflow，但未覆盖 768 侧栏展开/折叠组合 |
| P2-02 | Overview 内联 CSS 与共享样式重复 | 属可维护性/优先级风险；本轮三主题未见冲突，不做无证据重构 |
| P2-03 | 深色主题变量双来源/硬编码 | Aurora dark 26 张正常，但系统深色偏好与主题 class 不一致的组合未实测 |
| P3-01 | 缺少统一中文术语表 | 产品文案决策，需用户确认术语集合 |
| P3-02 | 设计 token / footer 一致性 | 视觉方向决策；本轮目标为保持原生风格与 Aurora 兼容，未做视觉重构 |

## 三、未验证（写明阻断原因，不标通过）

| 项 | 阻断原因 |
|---|---|
| CI 集成（把 quality 门加入 `real-luci-ui.yml`） | 工作流未改动：无法在不推送远端的前提下验证 runner 上的 lmo 安装、Aurora 包与 Chrome 路径；本轮只做本地真实容器验证 |
| 真实后端故障（非传输层） | 失败态使用 `/ubus/` RPC `abort` 注入，未制造损坏的 `cf_ip` 包或真实磁盘/权限故障 |
| OCR 文本识别 | 本机无 tesseract；中文证据为 DOM 文案 + 截图 + EN/ZH 像素 diff |
| Chrome 设置页缩放滑块本身 | 使用 `deviceMetricsOverride` 布局等效，不是 `chrome://settings` 缩放控件 |
| 768 侧栏开合组合 | 未纳入本轮矩阵 |
| 真机 / 硬件矩阵 / 24h soak | 依据用户 2026-11-04 裁定 PASS，未补造新记录 |
| PassWall / OpenClash 真实网络 | 超出容器范围 |

## 四、归属判断

- **插件缺陷（已修）**：P2-04 / P2-05 / P2-06。
- **测试误报**：上轮 zh 42/48 由脚本 `mainText` 截断 1200 字符造成，修正后 48/48。
- **环境问题（非产品）**：容器 `/etc/cf_ip` 0777 导致 `validate-config` 拒绝（已 `chown root:root` + `chmod 755`）；LuCI `uci.load('luci')` 403 仅 debug 日志。
- **主题**：Aurora 明/暗与 Bootstrap 未发现插件层回归。
