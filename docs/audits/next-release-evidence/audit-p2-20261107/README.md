# Audit P2 evidence (2026-11-07)

基线：`origin/main` `c17a8bd`；工作分支 `fix/audit-p2-20261107`。本轮不升版本、不打 tag、不合并 PR #33。

## 环境

- OpenWrt 24.10.8 x86_64（`openwrt/rootfs` 容器，`--network host`）
- LuCI `26.301.70438~aa4865e`；bootstrap 与 Aurora `1.4.0-r20260920`（light/dark）
- 浏览器：Playwright Chromium（headless）

## 项目与结论

| 项目 | 结论 | 证据 |
|---|---|---|
| P2-3 CI 测试清单按路径正则 | 旧实现把 `tests/startup-race.sh` 因 `ci.yml` 注释计为已接线；新解析器只统计 `run:`/`with:` 执行范围，并加 self-test 负例 | `p2-03-inventory.txt` |
| P2-9 `sysupgrade.conf` 非原子追加 | `mktemp + mv` 原子重写，保留文件模式与其他行；7/7 行为测试 PASS，CI 接入 | `p2-09-sysupgrade-atomic.log` |
| P2-7 release notes 中 APK 命名 | 实测 IPK/opkg 落 `/etc/config/cf_ip-opkg`，APK 落 `/etc/config/cf_ip.apk-new`；release notes 已按格式分别描述 | `p2-07-*.log`、`p2-07-run-*.sh` |
| UI P2-04 日志字号 | 审计“日志 9–10px”不可复现（`#log-area` 实测 12px，200% 下 16px）；真实低于 12px 的是 `.cfi-cmd-box`，已改为 12px | `ui/before-css-fix/`、`ui/after-fix/` |
| UI P2-05 confirm/modal 割裂 | 既有实现已用 `utils.confirmAction` → `ui.showModal`，无原生 `confirm()`；取消/确认/失败路径均实测 | `ui/after-fix/report.json` |
| UI P2-06 reduced-motion | overview 内联样式覆盖了共享媒体查询（真实插件 bug），在内联样式中补齐后 `animationName=none` | `ui/after-fix/report.json` |

## 复现命令

```sh
python3 -B tests/ci-test-inventory.py            # 260 local / 255 referenced / 12 excluded, exit 0
bash tests/sysupgrade-config-atomic.sh           # 7 PASS
CFIP_UI_LANG=en bash tests/real-luci-ui-provision.sh <container> <port>
node tests/real-luci-ui.cjs --base http://127.0.0.1:<port> --container <container>
```

UI 证据方法：CSS viewport = 1280 / zoom，`deviceScaleFactor = zoom`（125% → 1024@1.25，200% → 640@2），这是浏览器缩放的等效布局，不是物理浏览器 UI 缩放。矩阵覆盖 bootstrap-light、aurora-light、aurora-dark × 1280/1024/640/768/375 × overview/logs，共 30/30 PASS（zh-CN 实际渲染、无横向溢出）。

## 正式 gate

`ui/gate/ui-gate.json`（英文环境，SHA `8d93144`）：4/4 PASS

1. `sources-refresh-preserves-draft`（不 reload、草稿保留）
2. `luci-modal-and-readable-text`（`#log-area`/`.cfi-cmd-box` ≥12px；Cancel 无 `clear-log` 请求、无原生 dialog）
3. `reduced-motion-disables-pulse`（`animationName=none`）
4. `sources-rpc-error-visible`（显式错误 + Retry）

## 归属判断

- P2-04：审计报告部分误报（日志本身已是 12px）；`cfi-cmd-box` 是插件 CSS 的真实小字号，已修。
- P2-05：不是插件缺陷；缺失的是回归测试，本轮补入正式 gate。Escape/Tab 行为由 LuCI `ui.showModal` 提供。
- P2-06：插件真实缺陷（内联 `<style>` 后应用、同 specificity 覆盖外部 `@media`），已修。

## 边界与未完成项

- 未新增 reducer / 主题改动，不重构 LuCI 原生结构。
- 未执行物理设备/24h soak（沿用既有 PASS-BY-USER-DECISION）。
- `i18n-contract.py` 本轮复跑 PASS（516 keys / 552 entries）；运行时页面已确认主要标签为简体中文。
