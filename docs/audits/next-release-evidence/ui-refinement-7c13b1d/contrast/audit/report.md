# WCAG AA contrast scan - fresh re-scan

Environment: real OpenWrt 24.10.8 + LuCI 26.205.85413, Chromium 1280x900, Bootstrap / Aurora light / Aurora dark. The scan waits for each view to finish loading (`Loading view...` excluded) before measuring. The first scan missed Intelligence because it sampled the Loading view; this re-scan includes it.

- Pages: 24 (8 x 3 themes)
- Text elements: 1389
- Below threshold: 41
- By theme: {"aurora-dark": 22, "aurora-light": 6, "bootstrap": 13}
- By page: {"advanced": 5, "intelligence": 4, "logs": 3, "openclash": 7, "overview": 4, "passwall": 5, "settings": 5, "sources": 8}

## Failure classes

| Class | Count | Why not changed |
|---|---|---|
| LuCI/Aurora native button or tab | 41 | Native theme colour (`cbi-button-*`, `--main-color`); overriding would break the active theme |

No failure uses a colour literal declared by `cloudflare-ip.css`; the plugin styles only radius, spacing, wrapping and focus ring on these controls.

## Fixed during the round

- Table headers used theme `--subtext-color` on the muted surface at 4.04:1 in Aurora light; changed to `--cfi-muted-strong` (theme-derived 82/18 mix), now passing.

Raw data: `contrast.json` (1389 rows), `summary.json`.
