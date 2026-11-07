# 隐私泄露检查与脱敏 — 2026-11-08

范围：仓库全部 ref 的当前树 + 全部历史 blob；覆盖密钥、订阅/代理、Cloudflare token、SSH 密钥、`.env`、CI secrets、设备与个人信息（IP/MAC/序列号/主机名/SSID/运营商/型号与固件/用户名与邮箱/本机绝对路径）、`docs/` 下全部文本与全部 PNG 截图、测试夹具、workflow、release 说明、提交信息与分支名。

方法：

- `gitleaks detect` 全历史扫描（449 个提交）；
- 自写正则扫描全部 tracked 文本（当前树）与全部历史 blob（1047 个唯一 PNG 之外的文本）；
- 对全部 **1047 个唯一 PNG blob** 做 macOS Vision OCR（`en-US` + `zh-Hans`），并用词级 bounding box 定位敏感词；
- 按 ref 建立 blob→路径映射，区分“当前树仍暴露”与“仅历史 blob 暴露”。

## 1. 结论分级

| 级别 | 数量 | 状态 |
|---|---:|---|
| **确定泄露** | 4 类 | 已在分支修复（见 §3） |
| **疑似** | 4 项 | 判断为非识别性，保留并说明（见 §4） |
| **无** | 6 类 | 未发现（见 §5） |

## 2. 确定泄露（已修）

### 2.1 真实路由器管理页截图（PR #39，最高风险）

`docs/ui/design-spec-2026-11-08/screens/` 中来自用户真实路由器的 nginx-manager / UPnP 参考截图暴露：

| 内容 | 示例值 | 出现位置 |
|---|---|---|
| 设备主机名 | `<host>` | 全部 28 张截图的 LuCI 顶栏 |
| 内网地址 | `192.168.2.x`（DUT 与内网主机）、`192.168.3.x`（11 个） | `nginx-sites.png`、`nginx-sites-dark.png`、`nginx-logs.png`、`upnp-mappings.png` |
| 公网地址 | 3 个公网地址（中国电信/腾讯云网段） | `nginx-logs.png` 访问日志 |
| 自有域名 | 1 个主域名 + 2 个子域名 | `nginx-sites*.png`、`nginx-certificates.png` |
| 站点名 | 3 个站点名（个人服务） | `nginx-sites*.png`、`nginx-logs.png`、`nginx-certificates.png` |

处理：对上述词级区域做背景色实心遮挡（28 张图 + `SPEC.md` 内 真实 DUT 地址替换为 `192.168.1.1`），提交 `c008959`，已推送 PR #39 分支。重新 OCR 复核：主机名 0、私有域名 0、非 Cloudflare IP 0。

### 2.2 `main` 设备证据截图中的主机名

23 张截图顶栏含主机名 `<host>`：

- `docs/audits/next-release-evidence/device-20261107/visual-matrix/` 4 张；
- `docs/audits/next-release-evidence/device-20261107/visual-zoom/` 8 张；
- `docs/audits/next-release-evidence/touch-20261107/` 11 张；
- 其中 `touch-1024-openclash.png` 另含 2 个 私有域名 子域名。

处理：同法遮挡，重新 OCR 复核主机名 0、私有域名 0。Cloudflare anycast IP（`103.31.4.x`、`104.16–19.x`、`172.64.x`、`141.101.x`）属公开测速结果，保留。

### 2.3 文本中的本机绝对路径与真实内网地址

| 模式 | 命中 | 代表位置 |
|---|---:|---|
| `/Users/<user>/` | 134 处 / 56 文件 | `plans/stable-cross-repo-remediation-plan.md` L5、L491；`plans/g4-g5-execution.md` L341/383/391；`docs/audits/next-release-INDEX.md` L64；`docs/audits/g4-g5-evidence/*.json` 的 `rawEvidence` 与 `fileHashes` |
| `/Users/<user>/` | 37 处 | `AUDIT_2026-10-05/evidence/cf-tests.json` |
| `/<user>/clash/clash-proxies.yaml` | 1 处 | `docs/audits/next-release-evidence/device-20261107/README.md` L9 |
| DUT 内网地址 | 7 处 / 6 文件 | `device-20261107/visual-zoom/report.json`、`touch-20261107/touch-matrix.json`、`soak-20261107-12h/README.md`、`phase-c-ci/stable-review.json`、`g6-g7-evidence/device-policy-20261024.json` |
| 页面标题 `-<user>` | 3 处 | `touch-20261107/touch-matrix.json` L77/146/212 |
| 他账号分支名 | 4 处 | `docs/2.X_PRERELEASE_REMOTE_STATE.md` L39/40、`cross-repo-2e28db4.json` L8 |

处理：`/Users/<user>/`、`/opt/clash/clash-proxies.yaml`、`192.168.1.1`、`-<host>`、`<user>/…` 占位化；共 65 个文本文件。`tests/publisher-lan-policy.sh` 的同名地址经确认是合成夹具（模拟 LAN 从 `.1.1` 变为 `.2.1`），**不改**，改后会破坏用例；已回退并本地跑通。

### 2.4 证据归档分支中的同类图片

`docs/cleanup-notes-20261108`、`archive/ui-artifacts-20261108` 等分支继承 `main` 的旧截图，随各自 rebase/合并一并修复或删除，见 §6。

## 3. 修复汇总

| 对象 | 数量 | 提交 |
|---|---:|---|
| `main` 文本 | 65 文件 / 181 行 | `fix/privacy-redaction-20261108`（本文件所在分支） |
| `main` 截图 | 23 张 | 同上 |
| PR #39 截图 + SPEC.md | 28 文件 | `c008959` |
| PR #40 截图 | 20 张 | `50b9c1f` |
| 合并后复检残留私有域名 | 6 文件 / 27 行 | `fix/privacy-domain-redaction-20261108` |

首轮脱敏漏掉了文本中的私有域名。合并后对 `main` 二次 `git grep`，在 6 个文件中发现：`AUDIT_2026-10-05/evidence/cf-tests.json`、`docs/audits/g4-g5-evidence/legacy-regex-after.log`、`docs/audits/next-release-evidence/device-20261107/run-status.json`、`tests/openclash-protocol-matrix.sh`、`tests/openclash-xhttp-filter.sh`、`tests/regex-ip-suffix.sh`。在本分支统一替换为 `proxy.example.com` / `assets.example.com` / `static.example.com`。

复核：修复后对改动图片重新 OCR，主机名、私有域名、非 Cloudflare IPv4 均为 0；JSON 全部可解析；`tests/openclash-protocol-matrix.sh`、`tests/openclash-xhttp-filter.sh`、`tests/regex-ip-suffix.sh`、`tests/publisher-lan-policy.sh` 全部 PASS；`git grep hey[.]run` 在 `main` + 本分支为 0。

## 4. 疑似（保留，非识别性）

1. **设备型号与固件版本**：`Microsoft Virtual Machine`、`OpenWrt 25.12.5 x86_64`、`OpenClash 0.47.156`、`Aurora 1.2.0`。属通用 VM DMI 与公开软件版本，不含序列号，保留。
2. **cron 计划**：`30 7,18,23 * * *`（`device-20261107/README.md`）。属使用习惯，非身份信息；作为“配置被保留”的证据保留。
3. **`Maintainer: <user>`**：`phase-e/package/ipk-control.txt` 与已发布包元数据。属公开包字段；同一字符串已作为 GitHub 账号 `hello-<user>` 公开存在。
4. **`cdn.example.com` / `api.github.com` / `raw.githubusercontent.com`**：夹具与公开链接，保留。

## 5. 未发现

- 无 API token、Cloudflare Token、密码、私钥、SSH 公私钥、`.env`、订阅链接、`vmess://`/`ss://`/`trojan://` 节点。
- `gitleaks` 全历史 3 条命中均为误报：`openclash-controller-credentials.json` 的 `sourceSha256`、`preflight-release.sh` 的 `key not in ids`、`cfip-g4-g5` 的哈希串。
- workflow 未引用 `secrets.*`，无硬编码凭据。
- 无 MAC、序列号、SSID、Wi-Fi 密码、运营商名称。
- 无个人邮箱（仅 `test@example.com`）。
- 提交信息与分支名未夹带密钥、邮箱、IP、本机路径。

## 6. 残留风险（需用户决定）

1. **历史 commit 仍含旧内容**：449 个提交中，`/Users/<user>/` 等路径字符串与旧版截图 blob 仍在 `.git` 历史里。GitHub 公开仓库可通过历史/API 访问。彻底清除需 `git filter-repo` 重写历史 + force push，会改变所有 SHA 并影响其他工作区，**未执行**。
2. **未合并的归档分支当前树仍含旧文本**：`phase-b/next-release-fixes`（66 文件）、`evidence/ui-refinement-archive`（62）、`evidence/visual-phase-b-archive`（61）、`audit/ui-skill-review`（58）、`codex/reliability-contracts`（53）仍保留 `/Users/<user>/` 路径文本；`origin/evidence/ui-skill-audit-archive` 另含 2 张旧截图（`ui-skill-audit/matrix/aurora-*/320x900/overview.png`）。均为本地用户名路径，无密钥。
3. **工作区未跟踪文件**：`rill-adapter/target/` 为本地构建产物；`docs/... 2.*` 共 507 个重复副本已于 2026-11-08 删除（未提交、不在远端，其中 15 个仍含旧路径/域名文本）。
4. 已修复的图片 blob 旧版本仍存在于历史提交中（见第 1 条），当前各分支 tip 的 OCR 复核为干净。

建议：把第 1、2 条作为独立的“历史清理”决策；若决定重写历史，需冻结所有并行工作区并重新推送所有分支。
