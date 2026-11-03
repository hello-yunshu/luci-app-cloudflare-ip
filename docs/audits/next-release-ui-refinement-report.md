# UI refinement round - 2.6.0-r7 / 9adb2d5

Verdict: **COMPLETE for the requested interface items**, with physical-device and 24h soak still NOT RUN. Code: branch `phase-c/next-release-r7`, HEAD `9adb2d5`; no tag/Release/channel change.

## Fixes, one line each

| Problem | Where | Red -> green |
|---|---|---|
| Early-return empty/error states returned before `loadSharedCSS()`, so they had no card/footer. | `openclash.js`, `passwall.js`, `sources.js` | Before: css=false, border none, radius 0, footer 0 (at `402859c`). After: css=true, 1px border, 12px radius, themed surface, footer 1, description + Retry visible. 8 real screenshots. |
| Empty-state description/Retry children were passed as variadic `E()` arguments and silently dropped. | `openclash.js`, `passwall.js` | Before DOM: only `h3`. After DOM: `h3` + `p` + Retry; 375/1280 screenshots. |
| Radii, shadows, footer chips were hardcoded across the stylesheet. | `cloudflare-ip.css` | Added `--cfi-radius-card` (8px), `--cfi-radius-chip` (4px), `--cfi-shadow-hover`, footer border/chip tokens; all 4/6/8/9/10px literals replaced. Measured Bootstrap: section 12px, stat card 8px (was 12px due to specificity), table 8px (was 9px). |
| 600/900 breakpoint was viewport-only and could mismatch content width. | `cloudflare-ip.css` | `@supports (container-type: inline-size)` + `@container` blocks added; original media queries untouched as fallback. 54-row matrix before/after: 0 layout differences, 0 mismatch cases measured. |
| Table headers used theme subtext on muted surface (4.04:1 in Aurora light). | `cloudflare-ip.css` | `--cfi-muted-strong` (theme-derived); Aurora light header failures 11 -> 0. |
| Tab row clipped later tabs at 640/768; Bootstrap tab links had no focus ring. | `cloudflare-ip.css` | Wrap <=900px; `:focus-visible` 2px outline. Keyboard 200%: 16/16 PASS; tabbed focus 312/312 PASS. |

## Numbers

- Interaction matrix: **42/42 PASS**, 0 FAIL. State PASS counts: default 42, hover 3, focus 4, active 11, disabled 1, error 4, empty 3, open 9; remaining cells are N/A with reasons in the matrix.
- Keyboard 200%: **16/16 PASS**; per-control real-Tab focus: **312/312 PASS**; 0 focus failures.
- WCAG AA: 24 page-theme combinations, 1105 text elements, **35 below threshold**, all native LuCI/Aurora control colours (Bootstrap save/reset, Aurora primary teal); none are plugin-authored literals, so they are reported and deliberately not overridden.
- Visual: **78/78** normal-state screenshots, 0 horizontal overflow; old 78 `visual-phase-c` screenshots preserved in `visual-index.csv` (374 rows).
- v1.8.3-1 comparison: navigation 4 -> 6 static + 2 conditional pages, section radius 0 -> 12px, shadow none -> themed, body font 13px unchanged, footer font unchanged, log 10/9px -> 12px. Deviations are documented with rationale.
- Intelligence IA: 57 read-only fields in 6 sections (Live State 27). Only wrapping/contrast/focus fixes applied; 4 structural suggestions await approval.

## Not closed

- Physical router hardware and 24h soak: **NOT RUN**.
- OpenClash restore/delete backup: **BLOCKED** (no backup fixtures in the disposable container); backup load-failure + Retry is covered.
- Speed-test log modal: **BLOCKED** (requires `last_result=running` with CFST; no CFST/network in container).

Evidence root: `docs/audits/next-release-evidence/ui-refinement-7c13b1d/`.

SHA binding: visual/token screenshots are at final HEAD `9adb2d5`; interaction matrix, contrast, keyboard, focus and width-matrix evidence is at `7c13b1d` (the only later change is the stat-card radius override, which does not alter any interaction assertion). Matrix screenshots keep their `sha` column in `visual-index.csv`.
