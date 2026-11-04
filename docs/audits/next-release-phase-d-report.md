# Phase D - blocked interactions and Intelligence affordances

Result: **阶段 D PARTIAL (historical)** - OpenClash delete success/failure and restore failure ran against the real LuCI/rpcd path; restore success was BLOCKED at the time because the x86_64 Rosetta container could not run the OpenWrt Ruby package. **2026-11-04 follow-up closed restore success on aarch64** and added the Ruby/Psych precheck; see §Follow-up and `next-release-evidence/phase-d/openclash-ruby/RESULTS.md`. Speed-test modal and Intelligence affordances are PASS.

## OpenClash backup paths (real LuCI + real rpcd)

Controller environment: real mihomo/`clash` 1.19.33 core, real uhttpd `/group` controller, real `/etc/config/openclash` (`enable=1`, `cn_port=19090`), real config directory and backup files. Recipe: `phase-d/scripts/openclash-paths.cjs` and `openclash-delete-success.cjs`.

- **Delete success**: real UI Delete -> confirm; notification `Backup deleted`; `reloadCount=1`; backup file missing. PASS
- **Delete failure**: `/bin/rm` fault injection; notification `Unable to delete backup: failed to delete backup`; no reload; backup file present. PASS
- **Restore failure**: real backup present; click Restore -> confirm; backend refused with `OpenClash candidate or backup is not a supported YAML document; nothing was published`; notification `Unable to restore backup...`; no reload; config sha256 unchanged. PASS
- **Restore success**: BLOCKED at phase D (x86_64 Rosetta container, `ruby -v` rc 139). **Closed on 2026-11-04**: real restore passed on OpenWrt 24.10.8 aarch64 with Ruby 3.3.10/Psych 5.1.2 and mihomo 1.19.33; see `next-release-evidence/phase-d/openclash-ruby/RESULTS.md`. Evidence: `openclash/openclash.json`, `delete-success.json`, screenshots.

## Speed-test log modal (real LuCI status/log read path)

Status written to `/etc/cf_ip/status.json`, log to `/tmp/cf_ip/cf-ip-auto.log`; modal reads them through the real `cf_ip.speedtest-status` RPC, not a mock DOM. Running -> Success -> Error transitions were triggered by updating the real files and clicking the modal Refresh. PASS 3/3.

- Running: modal `Speed Test Log`, badge `⏳ Running`, log `Running CFST speedtest; measuring 8 candidates...`; status `running`.
- Success: badge `✔ Success`, log `Speedtest completed; selected 8 IPs; best=104.16.1.1`; status `success`.
- Error: badge `✘ Error`, log `ERROR: CFST run failed: synthetic failure`; status `error`.
Evidence: `speedtest/speedtest.json`, `overview-running.png`, `modal-running.png`, `modal-success.png`, `modal-error.png`.

## Intelligence low-risk improvements

- **Copy buttons**: 5 targets (Current Endpoint, Recent Runs, Runtime Path, Current Context Policy, Resource Guard). Clipboard API success changes the label to `Copied`; a rejected clipboard API falls back to `execCommand` (label `Copied`); clipboard absent + `execCommand` rejected shows `Unable to copy: Copy command was rejected`. PASS 3/3
- **Collapsible Live State**: default collapsed; button has `aria-expanded=false`, `aria-controls`; Enter expands, body visible, label changes to `Hide advanced diagnostics`; state persists in `localStorage` (`cfi.intelligence.liveState`) across reload. PASS
- **Cross links**: Recent Runs -> Logs & Records; Logs page -> Intelligence; both navigate back. PASS
- Structural options (not implemented, awaiting decision):
  1. Split Live State's 27 fields into **Runtime & Learning** (runtime version/state, qualification, adaptive counters) and **Decision & Evidence** (winner/top-N recall, insufficiency rate, replay savings, full audit, scheduler/feature contract, selection).
  2. Move **Recent Runs** and IP history into Logs & Records, leaving a summary + link on Intelligence.
  3. Optional copy button for every long diagnostic subgroup.
  Impact: render-tree/IA change only; no RPC/UCI contract changed; i18n keys unchanged; `intelligence/` and `logs/` screenshots plus `visual-index.csv` rows need recapture; `luci-view-bindings` fixture unaffected. Risk is low functionally, medium for visual-evidence churn; do in a separate change after approval.

Evidence: `intelligence/intelligence.json` and 6 screenshots.

## i18n and gates

- New keys: Copy, Copied, Copy command was rejected, Unable to copy: %s, Show/Hide advanced diagnostics, Open Logs & Records, Open Intelligence.
- i18n contract: 473 keys (JS 464 + menu 9), POT/zh/en 484 entries, PASS. Negative gate with a removed POT/zh key fails as expected.
- View-bindings fixture PASS; `node --check` PASS.
- `tests/luci-refresh-error.cjs`: the diagnostics fixture now binds the real LuCI `L` global required by the new Intelligence cross-link. Local red -> green: pre-fix `ReferenceError: L is not defined` (rc 1), post-fix rc 0 with both original assertions PASS.
- Physical device / 24h soak: **PASS-BY-USER-DECISION** on 2026-11-04. User stated "真机 + 24h soak 之前已经做过了，直接 pass". No new 24h record was fabricated. Historical device acceptance exists for OpenWrt 25.12.5 x86_64 Microsoft VM at `3bf0ec1` (`docs/audits/g6-g7-evidence/device-acceptance-3bf0ec1.json`); historical soak records are SKIPPED / NOT STARTED, so this status rests on the user decision alone, not on a new exact-SHA run.

## Follow-up 2026-11-04 (device/external-environment ledger)

Code branch `audit/ui-skill-review`, local HEAD `44677a4` (not pushed).

| 对账项 | 状态 | 证据 | 判定 |
|---|---|---|---|
| 真机 + 24h soak | PASS-BY-USER-DECISION | 用户原话；历史设备验收 `g6-g7-evidence/device-acceptance-3bf0ec1.json`；无新 24h 记录 | 关闭（不计入剩余） |
| OpenClash 恢复成功 + Ruby/Psych 前置 | PASS | `openclash-ruby/RESULTS.md`、`direct-restore.txt`、`openclash-ruby-restore.json`、三态截图；真实 aarch64 恢复，x86 Rosetta 边界已写清 | 关闭（不计入剩余） |
| 跨仓 Rill / PM | PARTIAL | `cross-repo.md`；pin/冲突/本地验证完成；真实 PR 创建必须触发 Actions，标“需用户裁决” | 仍计 1 条 |

NO-GO 硬要求计数：**14 → 12**（两条关闭，跨仓因 PR 路径保留 1 条）。若用户裁决接受 `sync-rill.yml` 本地等价验证、不再要求真实 PR 创建证据，则跨仓可转 PASS，计数为 **11**。

## Validation boundary (private repository)

- **本轮验证未创建 PR、未触发任何 Actions，验证均为本地执行。**
- Local gates: `node --check` all packaged JS PASS; `actionlint .github/workflows/*.yml` PASS; `python3 tests/i18n-contract.py` PASS; local LuCI fixture suite 7/7 PASS; `bash tests/openclash-rpc-contract.sh` PASS; real LuCI + Playwright evidence in `phase-d/` PASS.
- Historical only: PR #24 and Actions run `41776486445` predate this rule; they were not cancelled and are **not** used as acceptance evidence. No new PR, no dispatch, no rerun.
- Code branch `phase-d/intelligence-polish` at `a8f89e8`; `main` remains `b556334` (not merged, because a push to `main` would trigger Actions). No tag/Release/channel change.
