# Phase C Report — 2.6.0-r7

## 结论

**PARTIAL / CONDITIONAL GO**。代码、i18n、真实 LuCI UI、容器回归、78 张视觉矩阵与本地门禁通过；CI run `41666070486` 全绿（构建、迁移、Rill 集成、资格门禁、证据清单）。P1-05 物理设备与 24h soak 仍 **NOT RUN**，因此不满足无条件 GO；未创建 tag/Release，未改 release-channel，未晋级 stable。

## 关键数字

- P0：1/1 关闭。P1：4/5 关闭，P1-05 NOT RUN。P2：7/9 修复；P2-01 未复现，P2-09 pin 按约束不跟随。
- i18n：465 个 JS/菜单 key，POT/zh_Hans/en 各 476 条，覆盖 **465/465 (100%)**。
- 版本：`2.6.0-r7`（Makefile `PKG_VERSION=2.6.0`, `PKG_RELEASE=7`）。
- 真实 UI：本地 2/2 + CI `real-luci-ui` 通过；容器分支回归 7/7。
- 视觉：3 主题 × 3 主断点 × 8 页 = 72 + 6 边界 = 78，overflow 0，登录页 0，最小正文长度 219。
- 本地门禁：i18n 正向 PASS / 负向 exit 1；actionlint PASS；`node --check` 全部 JS PASS；security/openclash/LuCI 相关契约 PASS。
- CI：PR run [41666070486](https://github.com/hello-yunshu/luci-app-cloudflare-ip/actions/runs/41666070486) **success**；`real-luci-ui` run [41666070508](https://github.com/hello-yunshu/luci-app-cloudflare-ip/actions/runs/41666070508) success；全部 required checks SUCCESS，PR mergeState CLEAN。
- 构建产物：`luci-app-cloudflare-ip_2.6.0-r7_all.ipk`（sha256 `03d4aaf1…`，175523 B）与 `luci-app-cloudflare-ip-2.6.0-r7.apk`（sha256 `d9fb4ff2…`，175486 B）实际由 CI 构建；IPK v24.10.8 与 APK v25.12.5 升级/回滚迁移 job PASS；`qualification.json` `releaseEligible=true`，`stable-review.json` 状态 `PREPARED_FOR_REVIEW`。

## 真缺陷（缺陷 / 修在哪 / 红绿）

- Overview 内联 CSS 与共享 CSS 重复：统计卡规则移入共享 `cloudflare-ip.css`，`overview.js` 删除重复定义；红=`overview.js` 含 `.cfi-stats-grid`，绿=仅共享样式。
- 主题深色双来源：删除 `prefers-color-scheme: dark` fallback，仅由 `data-darkmode`/LuCI 主题决定；红=CSS 含 media block，绿=不含。真实 Aurora light/dark 26/26 截图正常。
- 动态状态机码：`utils.statusLabel/statusReasons` 映射 mode/qualification/health/confidence/reason，未知值回退 `未知（原码）`；真实中文 Intelligence 显示“不足 / 影子模式”，无 `insufficient/shadow` 泄漏。
- P2-01 600/900 断点：在 768/900 实际内容宽度 ≥600，未复现错配；按最小改动不改，保留为已知风险而非已知缺陷。
- P2-09 Rill pin：contract pin `da8389f` 未跟随 rill-ml main `9602750`；`rill-openwrt-packages` pin `a1245c2` 与远端 main 一致。

## 阶段 B 四项未回退

OpenClash 删除假成功、RPC 失败误判、Sources 刷新丢草稿、Rill reset 不刷新（含 `ev.currentTarget`）均由本地 harness 红→绿与真实容器回归复验通过。

## 提交 / PR

- 代码分支：`phase-c/next-release-r7`；HEAD `402859c`（推送成功）。
- PR：https://github.com/hello-yunshu/luci-app-cloudflare-ip/pull/23（base `main`，未合并；checks 全绿，mergeState CLEAN）。
- 未创建 tag/Release；未改 `release-channel.json`；未晋级 stable。
- 证据与报告仅保留本地 docs 分支，未随代码分支推送，避免把 12MB 截图写入 PR 推送。

## 支持边界

- 构建矩阵：OpenWrt 24.10.5 / 24.10.8（IPK），25.12.0 / 25.12.5（APK），x86_64。
- 主题：Bootstrap（OpenWrt 默认/原版对应主题）、Aurora 1.4.0 light、Aurora 1.4.0 dark。
- 服务模式：PassWall、OpenClash；Native、Adaptive、Rill shadow/assisted/guarded。arm64、其他架构、物理设备未覆盖。

## 未解项与解锁条件

1. **物理设备/24h soak**：当前无真实 OpenWrt 设备接入；NOT RUN。解锁：提供设备型号/firmware/arch，执行安装/升级/回滚与 24h 墙钟 soak，绑定 exact SHA。
2. **P2-01**：未在必测矩阵复现；若后续出现侧栏导致内容宽度 <600 的实际截图，再按容器查询方案修复。
3. **P2-09**：按用户口径保持 pin；如跟随 rill-ml main，需重新资格并另开跨仓 PR。
4. **发布授权**：tag/Release/stable/feed 需另行明确授权；CI 绿灯是必要非充分条件。
