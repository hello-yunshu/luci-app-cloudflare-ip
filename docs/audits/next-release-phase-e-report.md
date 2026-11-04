# Phase E - release-blocking fixes (2026-11-04)

Result: **阶段 E PASS（6/6 闭合，本地门禁与 exact-SHA CI 全绿）**。代码分支 `audit/ui-skill-review`，HEAD `1ec2a6d`，PR #25（OPEN / MERGEABLE）；未合并、未打 tag、未建 Release、未改 `release-channel.json`。

## 0. 结论与计数

- NO-GO 硬要求：**12 → 6**。本轮关闭第 5、6、8、11、12、13 条，共 6 条。
- 若用户裁决接受 `sync-rill.yml` 的本地等价验证、不再要求真实 PR 创建证据，跨仓不再计入，NO-GO 为 **5**。
- 剩余 6 条构成：第 4/7/9/10 条证据类 4 条 + 跨仓 `sync-rill.yml` 真实 PR 裁决 1 条 + 发布动作授权 1 条（merge/tag/Release/channel 按规则必须由用户单独授权，不属于待修缺陷）。

## 1. 第 5 条：raw error 分离

改了什么：

- `utils.js` 新增统一错误呈现：`errorText`、`technicalDetails`、`errorNotice`、`errorPanel`、`noticeError`，并提供 `copyText`/`copyButton`。
- 人类可读标题 + 可展开 `<details>` 技术详情（原始 error code/message），详情内提供复制按钮。
- 覆盖所有抛出 raw error 的位置：`overview.js`、`openclash.js`、`sources.js`、`passwall.js`、`settings.js`、`intelligence.js`、`diagnostics.js`、`advanced.js` 以及共享 Save & Apply。
- 技术详情未丢失：`tests/luci-raw-error-contract.cjs` 断言 `errorNotice` 同时包含人类说明与原始错误文本。

证据：

- 真实 LuCI 24.10.8 aarch64 容器 BEFORE：`phase-e/before/diagnostics.png`（`Last error: controlled raw backend failure`）。
- AFTER：`phase-e/after/diagnostics.png`（`The last service run reported an error.` + `Technical details` + 原码 + 复制按钮）。
- 截图哈希不同：before `d2a3e3f8…` / after `e59b3347…`。

退出码：

- `node tests/luci-raw-error-contract.cjs` → **0**
- `node tests/luci-refresh-error.cjs`、`luci-view-bindings.cjs`、`luci-run-status.cjs` → **0**

闭合：**是**。

## 2. 第 6 条：动态状态映射与门禁

改了什么：

- `statusLabel` 未知值不再显示 `Unknown (code)`，改为 `Unknown`；新增 `statusKnown`、`collectUnknownStatusCodes`。
- 新增 `SOURCE_STATE_LABELS`、`SOURCE_ERROR_LABELS`；Sources 的已知 `lastError` 映射为可读文案，未知码显示 `Source error` + 可展开原码（`sourceErrorNode`）。
- Intelligence 增加 `Unknown state codes` 可展开块；`_inspect`/`_health` 走统一映射。
- 语言门禁新增硬编码与映射检查：`tests/i18n-dynamic-contract.py`，并在 CI `i18n-contract` job 中执行正反两向。

证据：

- BEFORE `phase-e/before/intelligence.png`（`Unknown (future_code)`）→ AFTER `phase-e/after/intelligence.png`（`Unknown` + `Unknown state codes`）。
- BEFORE `phase-e/before/sources.png`（raw `future_source_code`）→ AFTER `phase-e/after/sources.png`（`Source error` + 可展开原码）。
- 哈希：intelligence `0350930c…` → `8b6c084d…`；sources `e59faeb1…` → `6ee45c86…`。
- 负向控制：删除 `timeout` 映射后 `--self-test` 必须 FAIL；当前自检 PASS，证明门禁可红。

退出码：

- `python3 -B tests/i18n-dynamic-contract.py` → **0**
- `python3 -B tests/i18n-dynamic-contract.py --self-test` → **0**（内部负向用例按预期 FAIL）
- `python3 -B tests/i18n-contract.py` → **0**（516 keys = JS 507 + menu 9；POT/zh_Hans/en 各 552 条）

闭合：**是**。

## 3. 第 8 条：legacy 自更新

改了什么：

- `cf-ip-auto-legacy` 与 `cf-ip-auto`：`AUTO_UPDATE="false"`、`SELF_UPDATE_URL=""`。
- `self_update()` 不再 fetch、不再 `bash -n` 后替换脚本，只记录 `legacy self-update is disabled` 并返回 0。
- `--self-update` 返回 `{"success":false,...}` 与 rc 1，原因 `legacy self-update is disabled; upgrade via the package manager`。
- `/etc/config/cf_ip` 的 `auto_update` 置 0、`self_update_url` 置空并保留迁移注释。

证据：

- `tests/legacy-self-update-disabled.sh` 使用 fake `curl`/`uci`：第一条用例调用 `--self-update`，断言 disabled 文案存在、curl marker 不存在、`success:false`。
- 第二条用例覆盖**自动运行路径**：fake UCI 返回 `auto_update=1` 与外部 `self_update_url=https://legacy.example/update.sh`，执行 `cf-ip-auto-legacy -v`，让流程先到达 `self_update()`，再在 `prepare_work_dir` 处人为失败；断言日志出现 `self-update disabled` 且 curl marker 不存在。
- 不是只做语法检查：两条用例都实际执行脚本路径并确认没有网络拉取、没有文件替换。

退出码：

- `bash tests/legacy-self-update-disabled.sh` → **0**

闭合：**是**。

## 4. 第 11 条：Advanced 弃用字段只读

改了什么：

- `advanced.js` 将 `self_update_url` 设为 `o.readonly = true`、`rmempty = true`，说明改为 `Deprecated and read-only...`。
- 弃用字段保留可读，但不可编辑；不删除 UCI 字段，避免升级时丢配置。

证据：

- 真实 LuCI 读数：before `editable=true, disabled=false`；after `editable=false, disabled=true`（LuCI 把 `readonly` 渲染为 `disabled`）。
- `phase-e/before/advanced.png` → `phase-e/after/advanced.png`；哈希 `36424a2d…` → `c93dd924…`。
- `phase-e/after/advanced-readonly.txt` 记录 DOM 读数。

退出码：

- `node tests/luci-view-bindings.cjs` → **0**

闭合：**是**。

## 5. 第 12 条：uhttpd 副作用

改了什么：

- `Makefile` 移除硬依赖 `+uhttpd`：`DEPENDS:=+luci-base +bash +flock +curl +tar +jq +ca-bundle +ca-certificates`。
- LAN Result Publisher 仍使用 `/usr/sbin/uhttpd`；缺失时 init fail-closed，不影响其他功能。
- README/README.en 写明 uhttpd 不是硬依赖；nginx/lighttpd 系统不会被动安装第二套 Web 服务。

证据：

- 构建出的 r8 IPK control：`Depends: libc, luci-base, bash, flock, curl, tar, jq, ca-bundle, ca-certificates`，**不含 uhttpd**（`phase-e/package/ipk-control.txt`）。
- APK 元数据同版本、同依赖边界（`phase-e/package/apk.metadata.json`）。
- `tests/package-uhttpd-boundary.sh` 同时断言 Makefile 无 `+uhttpd`、init 检查 `/usr/sbin/uhttpd`、README 说明可选依赖。

退出码：

- `bash tests/package-uhttpd-boundary.sh` → **0**

闭合：**是**。结论：不需要 `ALTERNATIVES` 或条件依赖；uhttpd 仅由可选 Publisher 在运行时探测。

## 6. 第 13 条：版本口径

结论：**候选版本为 r8**。

- `Makefile`：`PKG_VERSION:=2.6.0`、`PKG_RELEASE:=8`；README 与发布文档均为 r8。
- `docs/2.6.0-r7-RELEASE-READY.md` 已改名为 `docs/2.6.0-r8-RELEASE-READY.md`，内容更新为 r8 候选。
- 构建产物为 `2.6.0-r8`（IPK/APK metadata 一致）。
- `release-channel.json` 保持 `stable` 未改；仓库无 `v2.6.0-7`/`v2.6.0-8` tag，最新 Release 仍为 `v2.6.0-6`。
- 未打 tag、未建 Release、未改 release channel、未晋级 stable，正式发布等用户单独授权。

退出码：

- `python3 tests/build-version-policy.py` → **0**
- `jq empty release-channel.json` → **0**

闭合：**是**（文档层面）。

## 本地门禁

| 检查 | 退出码 |
|---|---|
| `python3 -B tests/i18n-contract.py`（516 keys / 552 entries） | 0 |
| `python3 -B tests/i18n-dynamic-contract.py` | 0 |
| `python3 -B tests/i18n-dynamic-contract.py --self-test` | 0（负向按预期 FAIL） |
| `node tests/luci-raw-error-contract.cjs` | 0 |
| `bash tests/legacy-self-update-disabled.sh` | 0 |
| `bash tests/package-uhttpd-boundary.sh` | 0 |
| `bash tests/openclash-ruby-precheck.sh` / `node tests/openclash-ruby-precheck.cjs` | 0 / 0 |
| `bash tests/openclash-rpc-contract.sh` | 0（见下方回归修复） |
| `node tests/luci-save-singleflight.cjs`、`luci-save-readback.cjs`、`luci-ready-state.cjs`、`luci-run-status.cjs`、`luci-refresh-error.cjs`、`luci-status-observation.cjs`、`luci-view-bindings.cjs` | 0（8/8） |
| `node --check` 全部打包 JS | 0 |
| `bash -n` 全部脚本；`sh -n` init/rpcd | 0 |
| `actionlint .github/workflows/*.yml` | 0 |
| `python3 tests/build-version-policy.py`；`jq empty release-channel.json` | 0 / 0 |

**回归修复（本轮发现）**：

1. 在 `4bbfca6` 上 `tests/openclash-rpc-contract.sh` 实际为红——`tests/openclash-rpc-render.cjs` 的 utils stub 未同步 `technicalDetails`，渲染 `OpenClash Apply Status` 抛 `TypeError`。已修复 fixture 并在 `356913f` 重跑为绿；CI 未覆盖该脚本，因此这是一次真实的本地门禁补洞，不是形式整改。
2. 原 legacy 测试只覆盖 `--self-update`，而自动运行调用的是另一个 `self_update()`。已在 `1ec2a6d` 补第二条行为用例（`auto_update=1` + 外部 URL + 强制早期失败），确认自动路径不 fetch。

## exact-SHA CI

- 分支 `audit/ui-skill-review`，远端 SHA `1ec2a6df5ce43f30c930d2147a3703787d3450e9`，PR #25。
- PR CI `41841999414`：**success**（host-contract、rpc-luci-contract、rootfs-contract、workflow-lint、legacy-contract、i18n-contract、real-cfst-smoke、docker-replay、package-identity、4 组 openwrt-package、package migration、qualification guard 全部 success）。
- Push CI `41841991191`：**success**。
- Real LuCI UI Gate `41841999512`：**success**。
- 中间提交 `356913f` / `4bbfca6` 的 CI 同样 success；本轮以 `1ec2a6d` 为准。

## 真实 LuCI 证据

- 环境：OpenWrt 24.10.8 aarch64 rootfs，真实 `/sbin/init`、uhttpd/rpcd、LuCI 登录。
- BEFORE/AFTER 四组：Advanced、Diagnostics、Sources、Intelligence。
- 四组 PNG 的 sha256 全部不同：
  - advanced `36424a2d…` → `c93dd924…`
  - diagnostics `d2a3e3f8…` → `e59b3347…`
  - intelligence `0350930c…` → `8b6c084d…`
  - sources `e59faeb1…` → `6ee45c86…`

## 版本与产物

- 候选版本：`2.6.0-r8`。
- IPK：`luci-app-cloudflare-ip_2.6.0-r8_all.ipk`，182658 B，sha256 `a0d9d021149c1cb488240fd2be0699c6ac1bd21fc543a0096abab46d4c85f399`。
- APK：`luci-app-cloudflare-ip-2.6.0-r8.apk`，181946 B，sha256 `29890098b4827ba627548d5c0330d51718f0d045d62b9b0503cfe4f3bb576640`。
- 说明：两份产物最初下载自 `4bbfca6` 的 CI run `41835519468`；后续 `356913f`、`1ec2a6d` 仅改测试 fixture（不进包）。最终 run `41841999414` 的 IPK/APK 已重新下载并逐字节比对，sha256 与上表一致。

## 仍开放

- 第 4/7/9/10 条：七态逐点真实覆盖、docs 归位、1280@200% 真实缩放、zh 真实渲染，均为证据补齐项。
- 跨仓 Rill/PM 的 `sync-rill.yml` 真实 PR 创建：需用户裁决；若接受本地等价验证则可转 PASS。
- 发布动作：merge PR #25、打 tag、建 Release、改 release channel 均需用户单独授权。
- 物理设备 / 24h soak：按用户裁定 `PASS-BY-USER-DECISION`，未补造新记录。
