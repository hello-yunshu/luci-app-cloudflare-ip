# Intelligence information-architecture audit

Scope: audit + minimal typographic/grouping fixes only. No structural move was made without approval.

## Observed structure

| Section | Read-only fields |
|---|---|
| Measurement Policy | 4 |
| Adaptive Measurement | 11 |
| Product Intelligence Summary | 5 |
| Operational Health | 5 |
| Rill Runtime Consumer | 5 |
| Live State | 27 |

Total read-only fields: **57**; sections: **6**.

## Long fields (measured DOM text)

| Field | Length | Example |
|---|---|---|
| Mode | 183 | Off / Shadow / Guarded (qualified only) / Shadow records counterfactual evidence without changing pr |
| Mode | 155 | Off / Shadow / Assisted (qualification-gated) / Assisted is qualification-gated and uses only the Na |
| Enable Rill Intelligence | 109 | Enable the optional Rill consumer. Native ranking remains authoritative when Rill is disabled or una |
| Runtime Path | 103 | /usr/bin/rill-runtime / Fixed package-managed Preview Runtime path; custom executable paths are reje |
| State File | 83 | Must stay under /etc/cf_ip. Paths outside the package state directory are rejected. |
| Source Strategy | 69 | Balanced / Official-heavy / History-heavy / Diversity-heavy / Community-heavy |
| Source Strategy Loop | 65 | deterministic: no, requested: Unknown (?), effective: Unknown (?) |
| Runtime installation | 62 | Runtime is optional; Native mode remains available without it. |

## Problems found

- **Density**: the Live State section holds 27 read-only fields in one block; users must scan a long column to find runtime, learning, decision and evidence values.
- **Compound labels**: fields such as `Requested / Effective Mode`, `Winner / Top-N Recall`, `Runtime Path` and `State / Model Generation` join two facts in one row; scanning is possible but comparison between facts is harder.
- **Long text**: `Recent Runs` is a single joined string (up to 20 runs); long IPv6 lists and raw error paths have no copy affordance. No horizontal overflow was found after wrapping, but copying from a wrapping paragraph is awkward.
- **Mixed audience**: human-readable summary fields and technical diagnostics (schema, API, generation, inspect) share the same section and visual weight.

## Minimal changes made (no structural change)

- `.cbi-value-field` now uses `overflow-wrap:anywhere` + `word-break:break-word`, so long paths/IPv6/run strings wrap without horizontal overflow.
- Table headers now use `--cfi-muted-strong` (theme-derived) and pass WCAG AA in Aurora light.
- The tab row wraps at <=900px and tab links have a visible focus ring, so the Intelligence tab remains reachable at 200%.

## Structural suggestions (awaiting user decision)

1. Split **Live State** into `Runtime & Learning` and `Decision & Evidence` (27 fields -> 2 groups of ~13).
2. Move `Recent Runs` from the form to the Logs & Records page, or render it as a dense table with one run per row.
3. Add copy buttons for `Runtime Path`, `State File`, current endpoints and long error strings.
4. Put technical diagnostics (`Runtime API`, `Feature Schema`, `Runtime Inspect`) behind a collapsed `Advanced diagnostics` section; keep them available, not hidden.

Evidence: `intelligence-ia.json` (per-field DOM text and lengths), `visual/*/intelligence.png`, `matrix/int-long-values-*.png`.
