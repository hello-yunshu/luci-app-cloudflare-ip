# Fresh-eyes audit - 2.6.0-r7 UI round

**Result: FINDINGS (7 audit/evidence issues, 7 fixed). No product-code defect found in this audit; after correction the UI round re-verifies CLEAN.**

## Scope checked against the prompt

- §0/§1: original LuCI style, v1.8.3-1 baseline (`77a65a8`) vs current.
- §2/§7: four Phase B/C regressions re-run on `9adb2d5` (OpenClash false success/delete failure, RPC errors, Sources draft, Rill reset).
- §3/§4: theme x breakpoint x page visual set, seven-state interaction evidence, keyboard/Tab.
- §5: CSS tokens, footer, 600/900 fallback, WCAG AA, 200% keyboard.
- §6: i18n contract and CI jobs.
- §8: CI/PR/release constraints (no tag/Release/channel change).

## Findings and fixes

| # | Finding | Evidence | Fix / re-verification |
|---|---|---|---|
| 1 | Intelligence screenshots were `Loading view...`; the contrast scan therefore measured 0 Intelligence text elements, and a token audit falsely saw no CSS/footer. | 9 Intelligence PNGs, captures textLen=89 at 1280; contrast `byPage` had no Intelligence; token audit `css=false/footer=0`. | Recaptured 9 screenshots after view load (textLen 3277-3430, footer/css true); re-ran contrast (1389 elements, 41 failures) and token audit (all 24 page-theme rows css/footer true). |
| 2 | Three matrix points had identical BEFORE/AFTER screenshots: `ov-cfst`, `oc-backup-retry`, `log-history`. | SHA256 equal for both images. | `ov-cfst` re-run: real `cf_ip.download-cfst` RPC, disabled `Downloading...`, notification, distinct after. `oc-backup-retry` re-run with controlled first-call failure: alert -> Retry -> backup table (1 row). `log-history` reclassified as read-only. |
| 3 | Two of the 42 matrix points were content checks without an actionable control (`log-history`, `int-long-values`). | No button/input in their sections; assertions were counts/text only. | Reclassified as read-only; matrix is now 43 checks = 41 interactive + 2 read-only. |
| 4 | All six Save points asserted only server `uci changes`, which was empty, so Save persistence was unproven. No real Save & Apply point existed. | `set-save/src-save/int-save/oc-save/pw-save/adv-save` all `changes=""`. | Re-ran each with a changed value and browser UCI staging assertion (`browserValue`, `changes=1`); added `set-apply` with real Save & Apply and server readback (`uci get cf_ip.main.ip_count = 8`). |
| 5 | The `@container` old-browser fallback path was never executed; only static reasoning existed. | No fallback JSON/screenshots in prior evidence. | Stripped the `@supports` block from a served CSS copy and measured both paths. Real widths 375/640/768: identical (1/2/2 columns, no overflow). Synthetic 500px container at 768: full CSS 1 column, stripped CSS 2 columns, proving both paths and that unsupported browsers keep the old media behavior. |
| 6 | `int-long-values` sampled the Loading view (`fields=0`). | matrix assertion `fields=0`. | Re-ran after load: 57 fields, 5 long, 0 clipped, no overflow. |
| 7 | Audit scripts were only in `/tmp`, not with the evidence. | no `scripts/` directory. | Copied matrix, focus, keyboard, contrast, visual, fallback, token and correction scripts to `ui-refinement-7c13b1d/scripts/`. |

## Re-verification numbers

- Matrix: 43 checks, 43 PASS; 41 interactive + 2 read-only; state PASS: default 43, hover 3, focus 4, active 12, disabled 1, error 4, empty 3, open 10; rest N/A with a recorded reason.
- Per-control real Tab focus: 312/312 PASS; keyboard 200%: 16/16 PASS.
- Visual: 78/78 normal screenshots, 0 overflow; index 396/396 rows 1:1, no duplicates.
- WCAG: 24 page-theme combinations, 1389 elements, 41 below AA; all native LuCI/Aurora button/tab colours, no plugin colour literal.
- Tokens/footer: 24/24 page-theme rows shared CSS + footer; section 12px, stat 8px, table 8px.
- Regressions on `9adb2d5`: OpenClash delete-failure PASS, OpenClash/PassWall/Settings RPC-error PASS, Sources draft PASS, Rill reset PASS.

## Not closed
- Physical hardware and 24h soak: NOT RUN.
- OpenClash backup restore/delete: BLOCKED (no real backup controller); load-failure + Retry covered.
- Speed-test log modal: BLOCKED (requires running CFST).
- Intelligence structural suggestions: awaiting user decision.

