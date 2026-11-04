# Next Release i18n Report — 2e28db4 baseline

> 当前候选：`ffa73f6`。当前语言门禁结果：516 keys（JS 507 + menu 9），POT/zh_Hans/en 各 552 条，`tests/i18n-contract.py` 与 `tests/i18n-dynamic-contract.py` 均 PASS。真实 zh_cn 渲染见 `phase-f/zoom-zh/zh-375-*`、`zh-1280-*`。以下保留阶段 A 的 2e28db4 缺失测量。
基线：`main` / `2e28db4b5cdc221897bbe98ff78fbe7235098e53`。数据：`docs/audits/next-release-evidence/i18n-2e28db4/`。
## 1. 统计
| 指标 | 值 |
|---|---:|
| LuCI JS 模块 | 9 |
| 唯一 `_()` 静态 key | **423** |
| POT msgid（单行） | 340 |
| zh_Hans 条目 | 341 |
| JS key 未进入 POT | **88** |
| JS key 无 zh 翻译 | **88** |

> 历史审计数字为 421 keys / 85 缺失；当前为 **423 / 88**，历史缺口基本仍成立。

## 2. 逐文件缺失
| 文件 | JS keys | 缺失 |
|---|---:|---:|
| `htdocs/luci-static/resources/cloudflare-ip/utils.js` | 16 | 0 |
| `htdocs/luci-static/resources/view/cloudflare-ip/advanced.js` | 32 | 8 |
| `htdocs/luci-static/resources/view/cloudflare-ip/diagnostics.js` | 21 | 1 |
| `htdocs/luci-static/resources/view/cloudflare-ip/intelligence.js` | 164 | 54 |
| `htdocs/luci-static/resources/view/cloudflare-ip/openclash.js` | 34 | 6 |
| `htdocs/luci-static/resources/view/cloudflare-ip/overview.js` | 76 | 2 |
| `htdocs/luci-static/resources/view/cloudflare-ip/passwall.js` | 8 | 3 |
| `htdocs/luci-static/resources/view/cloudflare-ip/settings.js` | 46 | 8 |
| `htdocs/luci-static/resources/view/cloudflare-ip/sources.js` | 44 | 6 |

## 3. 菜单缺口
| 菜单 key | POT | zh_Hans |
|---|---|---|
| `Cloudflare IP Optimization` | YES | YES |
| `Candidate IP Sources` | **MISSING** | **MISSING** |
| `Intelligence` | **MISSING** | **MISSING** |
| `Overview` | YES | YES |
| `Settings` | YES | YES |
| `Advanced` | YES | YES |
| `Logs & Records` | YES | YES |

> 真实截图确认：语言为 zh_cn 时，左侧菜单仍显示 `Candidate IP Sources`、`Intelligence`。

## 4. 88 个缺失 key 逐项清单
| # | key | 来源文件 |
|---:|---|---|
| 1 | `Adaptive Measurement` | `intelligence.js` |
| 2 | `Are you sure you want to restore this backup? A backup of the current configuration will be created first.` | `openclash.js` |
| 3 | `Assisted is qualification-gated and uses only the Native safe envelope; any Runtime problem falls back to Native.` | `intelligence.js` |
| 4 | `Audit Evidence` | `intelligence.js` |
| 5 | `CFST measurement concurrency. This controls load, not the candidate budget.` | `settings.js` |
| 6 | `Candidate Assisted` | `intelligence.js` |
| 7 | `Candidate Intelligence` | `intelligence.js` |
| 8 | `Candidate Shadow` | `intelligence.js` |
| 9 | `Cloudflare IP optimization service is not running. Click Start to begin.` | `overview.js` |
| 10 | `Concurrent target-domain probes, bounded to protect the proxy-off window.` | `advanced.js` |
| 11 | `Current Context Policy` | `intelligence.js` |
| 12 | `Current Endpoint` | `intelligence.js` |
| 13 | `Current State` | `intelligence.js` |
| 14 | `Custom sources accept HTTPS text lists containing IP, IP:port, IPv6, bracketed IPv6:port, or CIDR. Only the IP/CIDR is retained; domains are rejected.` | `sources.js` |
| 15 | `Each run allocates roughly 1/8 to fresh history champions, 5/8 to community seeds, and 1/4 to Cloudflare official range exploration. Missing pools flow to other sources. All candidates are deduplicated and measured locally in one CFST run; community ports are never reused.` | `sources.js` |
| 16 | `Eligible Insufficiency Rate` | `intelligence.js` |
| 17 | `Enable Adaptive Measurement` | `intelligence.js` |
| 18 | `Enable the optional Rill consumer. Native ranking remains authoritative when Rill is disabled or unavailable.` | `intelligence.js` |
| 19 | `Filter by Cloudflare data center in HTTPing mode. Comma-separated, e.g. HKG,NRT,LAX. Only effective with HTTPing.` | `settings.js` |
| 20 | `Fixed package-managed Preview Runtime path; custom executable paths are rejected.` | `intelligence.js` |
| 21 | `Fixed to /usr/bin or /usr/share/cf-ip. CFST is downloaded and executed as root only from these directories.` | `advanced.js` |
| 22 | `Full Audit` | `intelligence.js` |
| 23 | `GitHub download proxy URL. Leave empty for direct downloads. Must end with /.` | `advanced.js` |
| 24 | `Guarded (qualified only)` | `intelligence.js` |
| 25 | `Independent fail-safe deadline for rollback, restoring service state and recovery health checks. Allowed: 10-120 seconds.` | `advanced.js` |
| 26 | `Install rill-runtime-preview matching your OpenWrt release and CPU architecture.` | `intelligence.js` |
| 27 | `K` | `intelligence.js` |
| 28 | `Leave empty to use the current LAN IPv4 automatically. Public or 0.0.0.0 bindings are refused.` | `sources.js` |
| 29 | `Maximum unique IPs supplied to one CFST run. Allocation is automatic: a small local-history share, a majority community share, and the remainder official-range exploration; unused quota flows to the other pools.` | `sources.js` |
| 30 | `Measurement deadline for stop, CFST, probes, apply and normal restart. Recovery has a separate deadline.` | `advanced.js` |
| 31 | `Must stay under /etc/cf_ip. Paths outside the package state directory are rejected.` | `intelligence.js` |
| 32 | `Native measurement` | `intelligence.js` |
| 33 | `Native mode remains available` | `intelligence.js` |
| 34 | `Native only` | `intelligence.js` |
| 35 | `Next Full Audit / Optimize` | `intelligence.js` |
| 36 | `No backups available. Backups are created automatically when the config is updated.` | `openclash.js` |
| 37 | `No history` | `intelligence.js` |
| 38 | `Number of CFST results to verify against every target domain before ranking.` | `advanced.js` |
| 39 | `Number of best IPs to keep. If fewer IPs qualify, the result reports degraded candidate count and never duplicates an IP.` | `settings.js` |
| 40 | `Official sources are authoritative ranges. Community sources are untrusted seed IPs and are always re-tested locally.` | `sources.js` |
| 41 | `Only OpenClash proxies whose server matches this domain will be updated. Comma-separated for multiple domains.` | `openclash.js` |
| 42 | `Only PassWall nodes whose address equals this domain will be updated. Comma-separated for multiple domains.` | `passwall.js` |
| 43 | `Only update proxies with the specified transport protocol. Comma-separated. Values: ws, grpc, xhttp, h2, http. Leave empty to update all supported proxies.` | `openclash.js` |
| 44 | `OpenClash is not installed. Please install OpenClash before using this feature.` | `openclash.js` |
| 45 | `Operational Health` | `intelligence.js` |
| 46 | `Optional compatibility output for other LAN tools. PassWall/OpenClash still use direct modification and do not need this.` | `sources.js` |
| 47 | `PassWall is not installed. Please install PassWall before using this feature.` | `passwall.js` |
| 48 | `PassWall or OpenClash is not installed. Please install one before using this service.` | `settings.js` |
| 49 | `Preserve CFST binary during OpenWrt sysupgrade so it survives system upgrades.` | `settings.js` |
| 50 | `Product Intelligence Summary` | `intelligence.js` |
| 51 | `Random delay upper bound (seconds). Empty/random = 0~300s, 0 = no delay.` | `advanced.js` |
| 52 | `Reason Codes` | `intelligence.js` |
| 53 | `Recent Runs` | `intelligence.js` |
| 54 | `Replay Probe Savings` | `intelligence.js` |
| 55 | `Requested / Effective Mode` | `intelligence.js` |
| 56 | `Retained only for migration compatibility; it is not used by the 2.x engine.` | `advanced.js` |
| 57 | `Rill Runtime: Not installed` | `intelligence.js` |
| 58 | `Runtime installation` | `intelligence.js` |
| 59 | `Runtime is optional; Native mode remains available without it.` | `intelligence.js` |
| 60 | `Scheduler Contract` | `intelligence.js` |
| 61 | `Select how often the speed test runs. The service computes the next run time automatically.` | `settings.js` |
| 62 | `Selection` | `intelligence.js` |
| 63 | `Service action completed, but the speed test is still in progress. Refreshing current status.` | `overview.js` |
| 64 | `Shadow records counterfactual evidence without changing production probe order. Guarded is enabled only after fresh, complete, real audit evidence.` | `intelligence.js` |
| 65 | `Skip IPs with average latency above this value. Leave empty for no upper limit.` | `settings.js` |
| 66 | `Stop the proxy service before speed testing to avoid interference, and restart after updating.` | `settings.js` |
| 67 | `Suffix appended to the original node name. Placeholders: {n} = sequence number, {ip} = IP address. Leave empty to keep original names.` | `passwall.js` |
| 68 | `Suffix appended to the original proxy name. Placeholders: {n} = sequence number, {ip} = IP address. Leave empty to keep original names.` | `openclash.js` |
| 69 | `System Health` | `intelligence.js` |
| 70 | `The generic Rill Runtime is supplied by OpenWrt packaging. Cloudflare IP owns candidate validation, ranking policy, reward and proxy transactions.` | `intelligence.js` |
| 71 | `This snapshot explains fallback, qualification, delayed feedback, Prefix and Colo intelligence without exposing the internal model.` | `diagnostics.js` |
| 72 | `Unavailable` | `intelligence.js` |
| 73 | `Why This Run` | `intelligence.js` |
| 74 | `Winner / Top-N Recall` | `intelligence.js` |
| 75 | `conservative default` | `intelligence.js` |
| 76 | `conservative-default` | `intelligence.js` |
| 77 | `expansions` | `intelligence.js` |
| 78 | `feature contract` | `intelligence.js` |
| 79 | `fresh at` | `intelligence.js` |
| 80 | `insufficient` | `intelligence.js` |
| 81 | `last fallback` | `intelligence.js` |
| 82 | `never` | `intelligence.js` |
| 83 | `next in runs` | `intelligence.js` |
| 84 | `off` | `intelligence.js` |
| 85 | `policy current` | `intelligence.js` |
| 86 | `runs` | `intelligence.js` |
| 87 | `shadow` | `intelligence.js` |
| 88 | `unavailable` | `intelligence.js` |

完整机器可读清单：`i18n-missing.tsv`（含 `in_pot`/`in_zh`/files 列）。

## 5. 动态状态映射缺口
当前没有集中的显示映射模块。已存在的部分映射在 `intelligence.js` 的 `runtimeSummary()`（Rill requested/effective/fallback），但以下值仍可能以英文/机器码出现在页面或诊断区：
- `qualificationState`、`qualificationReason`
- `requestedMode` / `effectiveMode`
- `fallbackReason`
- `operationalHealth.state` / `reasonCodes`
- `confidenceReasons`
- source `success/stale/fromCache/lastError`
- RPC 错误分类（未安装/不可用/权限/超时/空）
建议统一为“中文短语 + 原始码可展开”的映射，未知值安全降级为 `未知（原始值）`，不静默显示英文。

## 6. 术语表建议
| 英文/机器值 | 建议中文 | 备注 |
|---|---|---|
| Cloudflare IP Optimization | Cloudflare IP 优选 | 品牌/菜单保留 Cloudflare IP |
| Candidate IP Sources | 候选来源 | 菜单 |
| Intelligence | 智能优选 | 菜单；Rill 保留 |
| Native | 原生排序 | 不译作“本地” |
| Shadow | 影子模式 |  |
| Assisted | 辅助模式 |  |
| Qualified | 资格校验通过 | qualificationState |
| Fallback | 降级/回退 | 按语义区分 |
| Rollback | 回滚 | 事务 |
| Speedtest | 测速 |  |
| Backup restore | 备份恢复 |  |
| Runtime | 运行时 | Rill Runtime 保留 |
| Configuration applied | 配置已应用 |  |
| Rill / PassWall / OpenClash / CFST / HTTP / IPv4 / IPv6 / CIDR | 保留原文 | 专有名词 |

## 7. 语言门禁建议
1. 用脚本从 9 个 JS 模块抽取 `_(...)` 调用，与 `po/templates/cloudflare-ip.pot` 比较；任何新 key 未进 POT 即失败。
2. 用 `msgfmt -c` 校验 zh_Hans/en PO 语法、占位符、重复 msgid、fuzzy；zh 中 `msgstr=""` 失败。
3. 单独检查 `menu.d/*.json` 的 title 是否在 POT/zh；目前 `Candidate IP Sources`/`Intelligence` 会失败。
4. 对动态状态映射建立 allowlist（状态码→中文），未知码必须渲染安全降级文案。
5. CI 在 `host-contract` 或独立 `i18n-contract` job 运行；失败阻断 merge，不以“仅警告”放过。

## 8. 结论
- 静态中文覆盖 **未完成**：88/423 key 缺失，菜单 2 个缺失；不能用“PO 文件存在”宣告完成。
- 动态状态映射、术语表、语言门禁均未实现。
- 真实中文渲染已在 78 张截图中确认，但英文菜单仍可见；这是当前可复现的 i18n 缺口。
