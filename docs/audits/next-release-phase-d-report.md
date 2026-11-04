# Phase D - blocked interactions and Intelligence affordances

Result: **阶段 D PARTIAL** - OpenClash delete success/failure and restore failure ran against the real LuCI/rpcd path; restore success remains BLOCKED because the product requires Ruby/Psych and the OpenWrt 24.10 Ruby package segfaults in this container. Speed-test modal and Intelligence affordances are PASS.

## OpenClash backup paths (real LuCI + real rpcd)

Controller environment: real mihomo/`clash` 1.19.33 core, real uhttpd `/group` controller, real `/etc/config/openclash` (`enable=1`, `cn_port=19090`), real config directory and backup files. Recipe: `phase-d/scripts/openclash-paths.cjs` and `openclash-delete-success.cjs`.

- **Delete success**: real UI Delete -> confirm; notification `Backup deleted`; `reloadCount=1`; backup file missing. PASS
- **Delete failure**: `/bin/rm` fault injection; notification `Unable to delete backup: failed to delete backup`; no reload; backup file present. PASS
- **Restore failure**: real backup present; click Restore -> confirm; backend refused with `OpenClash candidate or backup is not a supported YAML document; nothing was published`; notification `Unable to restore backup...`; no reload; config sha256 unchanged. PASS
- **Restore success**: BLOCKED. The backup controller is present, but `cf-ip-auto` validates candidate YAML with `ruby -rpsych`; OpenWrt 24.10 `ruby`/`ruby-psych` were installed offline and `ruby -v` exits 139 (segmentation fault), so every restore is rejected before write. Attempted: real mihomo core + controller, real config/backup, Ruby 3.3.10 + Psych 5.x packages, direct `ruby3.3-bin` and `--disable-gems`. Unlock: a real OpenWrt device/VM where Ruby/Psych runs, or a rebuilt Ruby package for this container CPU. Evidence: `openclash/openclash.json`, `delete-success.json`, screenshots.

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
- Physical device / 24h soak: NOT RUN. Required: exact router model + firmware + arch, real OpenClash/PassWall service and proxy network, and a 24h wall-clock run bound to the exact code SHA (`a8f89e8`). Container results are not a substitute.

## Validation boundary (private repository)

- **本轮验证未创建 PR、未触发任何 Actions，验证均为本地执行。**
- Local gates: `node --check` all packaged JS PASS; `actionlint .github/workflows/*.yml` PASS; `python3 tests/i18n-contract.py` PASS; local LuCI fixture suite 7/7 PASS; `bash tests/openclash-rpc-contract.sh` PASS; real LuCI + Playwright evidence in `phase-d/` PASS.
- Historical only: PR #24 and Actions run `41776486445` predate this rule; they were not cancelled and are **not** used as acceptance evidence. No new PR, no dispatch, no rerun.
- Code branch `phase-d/intelligence-polish` at `a8f89e8`; `main` remains `b556334` (not merged, because a push to `main` would trigger Actions). No tag/Release/channel change.
