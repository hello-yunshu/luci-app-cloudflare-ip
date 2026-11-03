# Pre-release Stage Report — 2.6.0-r7

## 结论

**PARTIAL**（发布准备完成，发布动作未执行）。阶段 C 之后没有阶段 D；本轮完成合入准备、arm64 安装、真实键盘/触控走查、精确 200% 设备指标和发布就绪文档。物理设备/24h soak 仍 NOT RUN，因此发布结论仍为 **CONDITIONAL GO**。

## 本轮新增证据

- arm64：OpenWrt 24.10.8 `aarch64_generic` 容器安装 `luci-app-cloudflare-ip_2.6.0-r7_all.ipk` 成功（opkg 版本 `2.6.0-r7`），8 个 LuCI 页面加载、无 overflow、无登录页；证据 `docs/audits/next-release-evidence/arm64/`。
- 键盘：真实 LuCI Tab 依次到达 checkbox/select/text input，`:focus-visible` 为真且 outline solid；Esc 关闭 LuCI confirm modal；Enter 激活确认按钮并清空日志。
- 触控：375×900、`hasTouch` 真实点击 tab 进入 Sources，点击 Refresh 出现通知。
- 200%：headless 键盘 zoom 不改变 `innerWidth`；改用 CDP 精确设备指标 `640×450 CSS / DPR2 / physical 1280×900`，页面 `scrollWidth=640`、无 overflow。未宣称浏览器菜单 zoom。
- 代码未新增缺陷；阶段 B/C 修复未回退。

## 版本 / CI / PR

- 版本：`2.6.0-r7`；IPK/APK 由 CI 实际构建；迁移 job PASS；`releaseEligible=true`，stable-review `PREPARED_FOR_REVIEW`。
- PR #23：HEAD `402859c`，checks 全绿，mergeState CLEAN，未合并。
- 未创建 tag/Release；未改 `release-channel.json`；未晋级 stable。
- 发布就绪文档：`docs/2.6.0-r7-RELEASE-READY.md`，包含一条 `gh release create` 命令（未执行）。

## 未解项与解锁条件

1. 物理设备/24h soak：NOT RUN。需真实设备 + 24h 墙钟执行后绑定 exact SHA。
2. arm64 仅验证 24.10.8 IPK 安装与页面；其他架构/版本仍 NOT RUN。
3. 浏览器菜单 zoom 无法在 headless 触发；当前为 CDP 精确 200% 设备指标，非交互式 zoom。
4. P2-01 600/900 未复现，保留风险；P2-09 pin 保持 `da8389f`。
5. tag/Release/stable/feed 等待用户授权；PR 合并等待授权。

## 清理

已删除 `cfip-arm64` 容器、`cfip-openwrt-arm64:24.10.8` 临时镜像、`/tmp/cfip-arm64`、`/tmp/cfip-artifacts`、`/tmp/cfip-ui`、Playwright 临时包与负向 PO；`git worktree list` 仅主工作树。
