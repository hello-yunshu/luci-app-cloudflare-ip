# Phase I - cleanup, stable gate preparation and post-release validation

Result: **PASS（5 条遗留已处置；Stable Gate 材料已准备但未执行；v2.6.0-8 发布后安装/升级验证 PASS）。** 未改 `release-channel.json`、未移动/删除 tag、未打新 tag、未建新 Release。

## 0. Follow-up (2026-11-05)

阶段 I 的 publisher 排除结论已被推翻并完成重写：

- 两个 fixture 的早期失败不是“uhttpd 未存活 / procd 未注册”。保留现场显示 uhttpd 进程存活、procd 实例 running、generation 文件存在；真正原因是产品 `curl --connect-timeout 1 --max-time 1` 被 24.10.8 当前 feed 的 `curl 8.22.0-r1` 拒绝（`remaining timeout of 999 too small`），就绪检查恒失败。
- 已在 `publisher.sh` 两处改为 2s；fixture 改用真实 procd/uhttpd、真实触发注册断言和真实 reload 命令；在全新 24.10.8 容器连跑两遍 PASS；新增 CI job `publisher-runtime`；登记为 P1-06。
- 该修复只在 `main`，**不包含在 v2.6.0-8 资产**；r8 在装有当前 curl 的设备上 publisher 仍不可用，下一次发布才修复。经用户补充授权，已准备 `v2.6.0-9` Pre-release 作为 P1-06 修复版本。
- ENOSPC 会把 `/usr/lib/opkg/status` 写坏；已新增 [ROLLBACK_AND_RECOVERY.md](../ROLLBACK_AND_RECOVERY.md) 与 `tests/opkg-status-recovery.sh`，演练输出：truncated status rejected，恢复后 opkg 列出 133 packages，rc 0。
- 历史归档分支无法用 git push（85 MiB / 28 MiB pack 均被重置）；改用 GitHub Git Data API 逐 blob 创建 `evidence/*-archive` 分支，清洁 clone 可 fetch 并核对 tree SHA。
- 详细证据：[publisher-fixture-rewrite.md](next-release-evidence/phase-i/publisher-fixture-rewrite.md)、[stable-gate-drills.md](next-release-evidence/phase-i/stable-gate-drills.md)。

Stable Gate 自检也已完成容器可做部分：硬件/架构矩阵、zstd 决策材料、shipped 依赖零公告、rollback/ENOSPC/断电容器演练、触控/键盘浏览器上限；物理设备、24h soak、PassWall 真实网络仍停在外部依赖。详见 [STABLE_GATE.md](../STABLE_GATE.md) §2A/§5A 与 [stable-gate-drills.md](next-release-evidence/phase-i/stable-gate-drills.md)。

历史归档分支 `phase-b/next-release-fixes` 仍只在本地；2026-11-05 推送 85 MiB pack 被 GitHub HTTPS 重置，恢复步骤已写入 INDEX。

## 1. 遗留 5 条

### 1.1 跨仓 sync-rill 真实演练

- 真实执行：临时克隆 `main`，仅给 `contracts/rill-runtime.json` 加一个尾随空行（JSON 语义不变），运行 `rill-openwrt-packages/scripts/open_sync_pr.py`。
- 结果：分支 `automation/rill-qualified-drill-6c05f995648e7cabcd71` 推送成功；PR **#26** 创建成功；CI 自动触发；head `9e9526120baf1f1066ab67aab23b25e9d7855717`。
- 运行：push CI `41929387139`、PR CI `41929395955`、`workflow_dispatch` CI `41929533620`；均只有 `evidence-manifest` job 失败，其余 job success。
- 失败原因：`Stable review rejected: candidate tag is already occupied by different content`。`prepare-stable-review.py` 按设计拒绝改动 contract 的候选，因为 `v2.6.0-8` tag 已存在且不可变。
- 处置：PR #26 已关闭并说明，分支已删除；main/pin/tag/Release 均未变。
- 首次失败暴露的 gate 误红已修复（见 §1.2b）。
- **第二次真实演练（修复后）**：PR **#28**，head `56cb1e5ad23d28edd4c86f11e307f5f94a923a4a`；push CI `41936332364` success（20/20）；pull_request CI `41936344450` success（20/20）。PR #28 已关闭、分支已删除，未合并、pin 未变。
- 结论：**PASS-BY-REAL-PATH（绿色路径已验证）**——推分支、`gh pr create`、CI 自动触发/全绿、显式 dispatch 均验证通过。
- 证据：`phase-i/sync-rill-drill.md`（本报告 §1.1 的 run/PR 记录）。

### 1.2 Build and Release stable guard

- 确认 `41904752070` 的失败是设计行为：`changes` success，`check-qualification` failure（`stable channel requires an explicit Stable Gate; automatic promotion is disabled`），`collect`/`release` skipped；未创建 tag/Release。
- 在 `.github/workflows/release.yml` 的 guard 前增加注释；新增 [RELEASE_CHANNEL_GUARD.md](../RELEASE_CHANNEL_GUARD.md) 说明“预期红”与真实故障的区分。
- 未绕过、未删除、未注释掉 guard。

### 1.2b 发布后 CI `evidence-manifest` 误红（已修复）

- 现象：阶段 I 分支 CI run `41933111895` 的 `evidence-manifest` job 失败，日志：
  `Stable review rejected: candidate tag is already occupied by different content`。
- 根因：`prepare-stable-review.py` 把“tag 已存在且候选 tree 不同”当作致命错误。发布后任何 docs-only 提交都会改变 tree，因此每个后续 PR 都会误红。
- 修复：`tagState=occupied-different`、`tagAvailable=false`、`tagConflict=true` 记录冲突，不再让 CI 整体失败；发布安全仍由 `release.yml` 的 pre-upload immutable-tag guard 保证（未改动）。`tests/stable-review.py` 新增 occupied-different 用例，5 tests OK。
- 验证：修复后阶段 I CI 与后续 sync-rill 演练均通过（run id 见交付报告）。

### 1.3 线上 Release notes 与仓库草稿

- 发布时首次使用的草稿头/重复块已在发布后清理；线上正文已替换为干净的最终版本。
- 仓库 [next-release-release-notes-v2.6.0-8.md](next-release-release-notes-v2.6.0-8.md) 已同步为线上正文，并标注“已发布（2026-11-04）”。
- 差异原因已记录：首次发布误用草稿全文，随后仅编辑 Release body，tag 与资产未变。

### 1.4 publisher 测试是否纳入 CI

- 在真实 `cfip-ui-phasef` 容器（OpenWrt 24.10.8 x86_64，`/sbin/init`，procd/uhttpd/uci/jq/curl 可用）中执行：
  - `tests/publisher-uhttpd-readback.sh` → **exit 5**，`publisher_generation_readback_failed`；当时归因“uhttpd 未存活”（后来被推翻，见 §0）。
  - `tests/publisher-procd-rebind.sh` → **exit 1**，`FAIL listener not reachable at 127.0.0.1`；当时归因“procd fixture 未注册/未启动”（后来被推翻，见 §0）。
- 结论：**已重写并纳入 CI（2026-11-05 follow-up，见 §0）。** 两个 fixture 在真实 24.10.8 procd/uhttpd 中全新容器跑通；根因是产品 1s curl 超时在 curl 8.22.0 下不可用，已修复并登记 P1-06；`.github/workflows/ci.yml` 新增 `publisher-runtime` job，`ci-test-inventory.py` 不再排除这两个测试。早期失败日志保留在 `next-release-evidence/phase-i/`。

### 1.5 历史大归档

- 主仓库 `docs/audits/next-release-evidence/` 现有 **35 MB**，包含 phase-d/e/f、矩阵、缩放/中文、visual-2e28db4 基线；足以自证 r8 审计。
- 四个历史归档保留在 linked worktree：`ui-refinement-7c13b1d/` 28 MB、`ui-skill-audit/` 21 MB、`visual-phase-b/` 5.6 MB、`visual-phase-c/` 6.0 MB。它们不是 r8 发布证据，**不归位主仓库**。
- 访问方式：`git worktree list` → `/Users/yunshu/Documents/GitHub/cfip-docs-evidence`，分支 `phase-b/next-release-fixes`；该分支未推远端，干净克隆不可得。2026-11-05 follow-up 尝试推送该分支（24 commits / 约 85 MiB pack），GitHub HTTPS 连续返回 `Connection reset by peer`，仍未推送。INDEX 已记录 bundle 导出/传输/回填的可执行恢复步骤。

## 2. 下一阶段：Stable Gate

- 新增 [STABLE_GATE.md](../STABLE_GATE.md)：门槛、角色、评审流程、当前 blocker。
- 结论：**NOT READY**，不执行 Stable 晋级。当前 blocker：
  - 物理设备/硬件矩阵 NOT RUN（pre-release 的 PASS-BY-USER-DECISION 不等于 Stable 证据）；
  - 24h soak NOT RUN；
  - PassWall 真实代理网络 NOT RUN；
  - arm64 仅 r7 安装/页面，r8 未跑，超出 x86 的架构未覆盖；
  - 完整触控矩阵 NOT RUN（键盘已到浏览器上限）；
  - full-workspace 非 shipped zstd 公告已备决策材料，仍待用户裁决；
  - rollback/ENOSPC/断电容器演练 PASS，但真实设备层面的断电/ENOSPC/opkg status 恢复未做；
  - `v2.6.0-8` 资产包含 P1-06（publisher 在 curl 8.22.0 下不可用），Stable 前必须重新构建/发布；
  - channel 变更未授权；guard 不得绕过。
- 已完成的容器自检：硬件/架构矩阵、zstd 决策材料、shipped 依赖零公告、rollback/ENOSPC/断电演练、触控/键盘浏览器上限，见 [STABLE_GATE.md](../STABLE_GATE.md) §2A 与 [stable-gate-drills.md](next-release-evidence/phase-i/stable-gate-drills.md)。
- 评审流程：evidence freeze → exact-SHA Gate → device review → security review → user decision → channel change (separate authorization) → stable release from approved main SHA → post-release validation。

## 3. 发布后验证（v2.6.0-8 资产）

详见 [post-release validation](next-release-post-release-validation-v2.6.0-8.md)。

- IPK（24.10.8 x86_64，镜像 `9972a4b4…`）：opkg update/install rc 0；版本 2.6.0-r8；依赖解析；`cf-ip-auto --status` rc 0。
- IPK 升级 r6→r8：rc 0；`/etc/config/cf_ip` SHA256 不变（`fc5ee4c8…`），自定义值全部保留；新默认写入 `cf_ip-opkg`。
- APK（25.12.5 x86_64，镜像 `c5d5f05b…`）：apk update/add rc 0；版本 2.6.0-r8；依赖解析；status rc 0；post-install 备份生成。
- APK 升级 r6→r8：rc 0；自定义 UCI 值全部保留；`cf_ip` 文件哈希变化是因为 apk 合并默认值并写 `cf_ip.apk-new`，不是配置重置。
- 边界：容器不是物理设备；`/cgi-bin/luci/` 403（无完整 LuCI CGI session），未宣称浏览器页面验证。

## 4. CI 与门禁事实

- 阶段 I 分支 head `b79ab8adbbbd15056ceda48bf5aa424d4af00c44`。
- CI（push）`41936166247`：success，20/20 jobs。
- CI（pull_request）`41936173109`：success。
- Real LuCI UI Gate（workflow_dispatch at branch head）`41936204478`：success。
- 本地：`ci-test-inventory.py` 0、`actionlint` 0、i18n 0/0、`release-channel-contract.sh` 0、`release-tag-immutability.sh` 0、`phase-f/scripts/verify.cjs` 0。
- sync-rill 绿色演练：PR #28，push CI `41936332364` success 20/20，PR CI `41936344450` success 20/20。

## 5. 未做之事

- 未改 `release-channel.json`；未移动/删除 `v2.6.0-8` tag；未打新 tag；未建 Release。
- 未合并 PR #26（已关闭）；未改 Runtime pin；未开真实跨仓 PR。
- 未执行 Stable 晋级。
- 物理设备、24h soak、PassWall 真实代理网络、完整触控矩阵仍未覆盖。
- P1-06 修复只在 `main`，未进入 r8 资产；本阶段不授权新 tag/Release。
- `phase-b/next-release-fixes` 归档分支未推送成功，仍为本地分支。
