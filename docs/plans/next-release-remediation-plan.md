# Next Release Remediation Plan — 2e28db4 baseline

> 当前候选：`90dfc13`。阶段 B–F 已按本计划执行；本轮新增门禁↔CI 一致性检查与七态矩阵。最新状态见 `docs/audits/next-release-phase-f-report.md`。

> 本文件是阶段 A 的计划，不包含任何已执行的产品代码修改。阶段 B 需用户批准后启动；阶段 C 的 stable/tag/Release 需另行明确授权。

## 1. 前置决策（阻塞开工）

| 决策 | 选项 | 影响 |
|---|---|---|
| 基线 | main `2e28db4`（实际最新） vs PR #18 `becb327` | 决定审计/修复分支起点；本轮建议 main，但需用户确认 |
| 版本 | r7 / 2.7.0 或其他 | r6 tag/Release 已占用，不能复用 |
| 视觉方向 | 回退 v1.8.3 原版观感 vs 保留 2.x 设计语言只做收口 | 决定 CSS/信息架构工作量 |
| 设备范围 | 接受容器/VM 真实 LuCI vs 必须物理设备 | 决定阶段 C GO 条件 |
| Rill pin | 继续 pin `da8389f` vs 跟随 rill-ml 新 HEAD/PR #50 | 决定跨仓资格与兼容测试 |
| stable 发布 | 保持自动 stable gate 禁用 | 不为了让 CI 变绿而放开 |

## 2. 依赖图

```text
[用户决策: 基线/版本/视觉/设备/pin]
        |
        +--> WP-01 P0 OpenClash 删除假成功
        +--> WP-02 P1 RPC 失败四态
        +--> WP-03 P1 Sources 草稿保护
        +--> WP-04 P1 Rill reset 状态刷新
        +--> WP-05 P1 i18n 423/88 + 菜单 + 动态映射 + 语言门禁
        +--> WP-06 P2 CSS/主题/字号/确认框/reduced-motion/320 导航
        +--> WP-07 跨仓 Rill 审计与 pin 决策
        +--> WP-08 真实交互矩阵补全（控制器/RPC 注入/键盘）
        +--> WP-09 真实设备/硬件/24h soak（阶段 C）
                    |
                    v
          GO/NO-GO 评审（阶段 C）
```

WP-01/02/03/04 可独立 PR；WP-05 可与 WP-06 并行；WP-07 可独立跨仓；WP-08 依赖 WP-01..06 的修复落地；WP-09 依赖用户设备与版本冻结。

## 3. 工作包

### WP-01（P0）OpenClash 删除备份判定

- 文件：`package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/openclash.js`。
- 改动：成功条件改为 `result && result.success === true && !result.error`；失败显示错误且不 reload。
- 测试：harness 四响应；真实 ubus route fixture；Bootstrap/Aurora 375/768/1280 的 modal。
- 验收：`{success:false}` 无 error 不得出现 “Backup deleted”。
- 回退：仅 UI 判定，回退安全。

### WP-02（P1）RPC 失败四态

- 文件：`openclash.js`、`sources.js`，必要时 `utils.js`。
- 改动：catch 保留错误标记；UI 区分 `UNAVAILABLE/ERROR/NOT_INSTALLED/EMPTY`；增加重试/诊断码。
- 测试：RPC reject、`{}`、`success:false`、权限错误；OpenClash/Sources 各一组。
- 依赖：WP-01 同一文件，建议同一 PR 或顺序 PR。
- 验收：错误不得显示为“未安装/无数据”。

### WP-03（P1）Sources 未保存保护

- 文件：`sources.js`，必要时 `utils.js`。
- 改动：表单 dirty state；刷新前确认或局部刷新；保存后才 reload。
- 测试：dirty/clean、刷新成功/失败、取消/确认；真实浏览器。
- 验收：刷新不丢未保存草稿。

### WP-04（P1）Rill reset 状态刷新

- 文件：`intelligence.js`。
- 改动：reset 成功后重读 status/diagnostics 或局部刷新；generation readback；失败不提示成功。
- 测试：真实 RPC reset + status；成功/失败/超时/generation mismatch。
- 验收：页面代数与后端一致。

### WP-05（P1）i18n 与语言门禁

- 文件：9 个 JS、`po/templates/cloudflare-ip.pot`、`po/zh_Hans/cloudflare-ip.po`、`po/en/cloudflare-ip.po`、`menu.d/*.json`、`.github/workflows/ci.yml`。
- 改动：
  1. 补齐 88 个 key；`Candidate IP Sources`/`Intelligence` 菜单 key。
  2. 建立动态状态映射（中文 + 原始码）。
  3. 建立术语表并统一文案。
  4. 新增 i18n gate（key 抽取、`msgfmt -c`、菜单 key、重复/fuzzy/空 msgstr）。
- 测试：`bash tests/i18n-contract.sh`（新增）；真实 zh 渲染；en 占位符。
- 验收：423/423 key 有 POT/zh；菜单无英文残留；CI gate 阻断。

### WP-06（P2）视觉/主题/可读性收口

- 文件：`cloudflare-ip.css`、`overview.js`、`diagnostics.js`、`intelligence.js`。
- 改动：
  1. 600/900 media query 改为内容宽度/容器查询或明确回退。
  2. 移除 Overview 内联重复 CSS，合并共享规则。
  3. 主题映射由 LuCI/Aurora 状态决定；`prefers-color-scheme` 仅作 fallback。
  4. 日志字号 ≥12px/rem，保留滚动/复制。
  5. `confirm()` → LuCI modal。
  6. `prefers-reduced-motion` 处理。
  7. 320px 导航 tab 换行/滚动/折叠。
- 测试：3 主题 × 3 断点 + 320/200%；键盘/触控；WCAG 对比扫描。
- 验收：无裁切/遮挡；对比度达标或明确例外。

### WP-07（P2/跨仓）Rill 兼容与 pin

- 文件：`contracts/rill-runtime.json`、`sync-rill.yml`、跨仓 PR。
- 改动：比较 `da8389f` 与 rill-ml `9602750` 的 API/schema；审查 PR #50/#51；决定是否跟随并重新资格。
- 测试：`check_rill_dependency.py`、Runtime/Protocol 兼容矩阵、sync 变更路径端到端。
- 验收：pin 与 schema 一致；sync 实际创建 PR 的路径 PASS；不得 force overwrite。

### WP-08（P1/P2）交互矩阵补全

- 内容：真实控制器安装/隔离 fixture；RPC timeout/权限注入；Settings 保存/应用/回读/回滚；键盘 Tab/Esc/Enter；触控命中；OpenClash restore/delete 成功/失败；Diagnostics clear cancel/confirm。
- 验收：8×7 矩阵无未解释 NOT-RUN；交互证据绑定 SHA/theme/viewport/page/state。

### WP-09（阶段 C）真实设备/硬件/soak

- 内容：物理设备安装/升级/回滚、PassWall/OpenClash 真包、IPv4/IPv6、异常网络、24h soak。
- 验收：设备型号/firmware/arch/package/Runtime/proxy/rollback 证据；未覆盖项用户签字。
- 边界：容器/VM 不能替代物理硬件。

## 4. 测试与回退

| 工作包 | 正向 | 异常 | 回归 | 回退 |
|---|---|---|---|---|
| WP-01 | `success:true` | `success:false`/`{}`/error | 其他备份操作 | 仅 UI；无配置写入 |
| WP-02 | 正常数据 | RPC reject/超时/权限 | 未安装/空态 | UI 状态；无配置写入 |
| WP-03 | clean 刷新 | dirty 刷新/取消 | 保存/应用 | 不 reload；无写入 |
| WP-04 | reset 成功 | reset 失败/超时 | generation 一致 | 不写学习状态 |
| WP-05 | 全 key | 缺失/fuzzy/占位符 | 菜单/zh 渲染 | 文案回退英文？不允许；必须补齐 |
| WP-06 | 3 主题 3 断点 | 320/200%/键盘 | 无 overflow | CSS 回退旧规则 |
| WP-07 | pin 一致 | 漂移/PR 未合并 | Runtime/Protocol | 保持旧 pin |
| WP-09 | 真机安装/升级 | 断网/回滚/重启 | 配置/权限持久 | 备份恢复 |

## 5. GO/NO-GO 条件

- P0/P1 全部处置并有可追溯测试。
- 4 项风险复现用例转为 PASS。
- i18n 88/88 补齐、菜单无英文残留、语言 gate 绿。
- 3 主题 × 3 断点真实截图/交互通过；320/200% 边界通过。
- 交互矩阵无未解释 NOT-RUN。
- 真实设备/硬件/回滚/跨仓证据可追溯；未覆盖项由维护者明确接受。
- CI 绿是必要不充分条件；stable/tag/Release 另行授权。

## 6. 当前结论（阶段 B 执行后）

- WP-01（P0）已关闭：OpenClash 删除仅在 `success === true` 时提示成功。
- WP-02（P1）已关闭：OpenClash/Sources/PassWall/Settings 的 check-env 或注册表 RPC reject 显示显式错误与 Retry/说明，不再误报未安装/空数据。
- WP-03（P1）已关闭：Sources 刷新不再整页 reload，保留未保存草稿。
- WP-04（P1）已关闭：Rill reset 成功后真实 reload；真实 UI 另修复 `form.Button` 事件参数误用（`ev.currentTarget`）。
- WP-05（P1）已完成：465 个 JS/菜单 key 100% 覆盖 POT/zh_Hans/en；`tests/i18n-contract.py` 接入 CI，并完成负向变红验证。
- WP-06（P2）已关闭可复现项：日志 12px、reduced-motion、320px 导航换行、确认框统一、README 状态；Phase C 进一步合并 Overview 重复 CSS、移除主题深色 fallback。600/900 断点未在必测宽度复现，保留为风险。
- WP-07（P2/跨仓）未执行：按用户口径 Rill pin 固定，不做跨仓 pin 变更/重新资格。
- WP-08（P1/P2）真实 UI 门禁已落地：`tests/real-luci-ui.cjs` + 独立 workflow，真实容器覆盖草稿保护与 RPC 错误可见；分支回归覆盖未安装/RPC 失败/删除失败/Rill reset。
- WP-09（阶段 C）仍 **NOT RUN**：物理设备、硬件矩阵、24h soak 未执行。
- 阶段 C（r7 候选）：P2-02/P2-03 已修复；动态状态已映射；真实 UI/回归/78 视觉/语言/actionlint 通过；代码已推送并开 PR #23。物理设备与 24h soak 仍 NOT RUN，发布结论为 CONDITIONAL GO。
- 版本号、tag/Release、stable/feed 与 24h soak 边界仍待用户拍板；未发布。
