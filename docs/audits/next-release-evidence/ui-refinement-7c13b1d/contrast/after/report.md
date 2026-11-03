# WCAG AA contrast scan (current 2.x, real LuCI)

Method: Chromium at 1280x900, real OpenWrt 24.10.8 uhttpd/LuCI, themes Bootstrap / Aurora light / Aurora dark. For every visible text node the effective background (including gradient stops and alpha compositing) is resolved and the WCAG 2.x contrast ratio is computed; normal text needs 4.5:1, large text (>=24px, or >=18.66px bold) needs 3:1.

- Pages scanned: 24 (8 pages x 3 themes)
- Text elements measured: 1105
- Below threshold: 35
- By theme: {"aurora-dark": 18, "aurora-light": 5, "bootstrap": 12}
- By page: {"advanced": 5, "logs": 3, "openclash": 5, "overview": 4, "passwall": 5, "settings": 5, "sources": 8}

## Failures (all theme-owned native LuCI control colours)

| Theme | Page | Element | Ratio | Required | Colour | Background | Text | Why not changed |
|---|---|---|---|---|---|---|---|---|
| bootstrap | settings | `button.cbi-button.cbi-button-save` | 3.04:1 | 4.5:1 | `rgb(0, 172, 89)` | `rgb(245,245,245)` | Save | LuCI/Aurora native button or tab colour (`--main-color` / `cbi-button-*`); changing it would override the active theme |
| bootstrap | settings | `button.cbi-button.cbi-button-reset` | 4.29:1 | 4.5:1 | `rgb(246, 43, 18)` | `rgb(245,245,245)` | Reset | LuCI/Aurora native button or tab colour (`--main-color` / `cbi-button-*`); changing it would override the active theme |
| bootstrap | sources | `button.cbi-button.cbi-button-add` | 3.04:1 | 4.5:1 | `rgb(0, 172, 89)` | `rgb(245,245,245)` | Add | LuCI/Aurora native button or tab colour (`--main-color` / `cbi-button-*`); changing it would override the active theme |
| aurora-light | settings | `button.cbi-button.cbi-button-save` | 3.97:1 | 4.5:1 | `lab(51.3503 -19.237 -40.2116)` | `rgb(221,236,245)` | Save | LuCI/Aurora native button or tab colour (`--main-color` / `cbi-button-*`); changing it would override the active theme |
| aurora-dark | overview | `button.cbi-button.cbi-button-apply` | 4.12:1 | 4.5:1 | `lab(100 0 0)` | `rgb(0,152,144)` | ▶ Start | LuCI/Aurora native button or tab colour (`--main-color` / `cbi-button-*`); changing it would override the active theme |
| aurora-dark | settings | `li` | 4.12:1 | 4.5:1 | `lab(100 0 0)` | `rgb(0,152,144)` | Save & Apply | LuCI/Aurora native button or tab colour (`--main-color` / `cbi-button-*`); changing it would override the active theme |
| aurora-dark | settings | `span.open` | 4.12:1 | 4.5:1 | `lab(100 0 0)` | `rgb(0,152,144)` | ▾ | LuCI/Aurora native button or tab colour (`--main-color` / `cbi-button-*`); changing it would override the active theme |
| aurora-dark | sources | `button.cbi-button.cbi-button-add` | 4.12:1 | 4.5:1 | `lab(100 0 0)` | `rgb(0,152,144)` | Add | LuCI/Aurora native button or tab colour (`--main-color` / `cbi-button-*`); changing it would override the active theme |
| aurora-dark | sources | `button.btn.cbi-button-action` | 4.12:1 | 4.5:1 | `lab(100 0 0)` | `rgb(0,152,144)` | Refresh Sources | LuCI/Aurora native button or tab colour (`--main-color` / `cbi-button-*`); changing it would override the active theme |

## Fixed during this round

- Table headers (`.cfi-table-wrap th`, `.cfi-source-table .th`, GridSection `th`) used theme `--subtext-color` on the muted surface at 4.04:1 in Aurora light. They now use `--cfi-muted-strong` (82% subtext + 18% text), still theme-derived, and pass in all three themes.

Raw per-element results: `contrast.json` (1105 rows), summary: `summary.json`.
