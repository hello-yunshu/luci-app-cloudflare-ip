# Visual matrix - current 2.6.0-r7 (7c13b1d)

Environment: OpenWrt 24.10.8 x86_64, LuCI 26.205.85413~cac97ed, uhttpd/rpcd in a disposable container; Chromium via Playwright. Themes: Bootstrap (original), Aurora light, Aurora dark.

- Normal-state screenshots: **78** (8 pages x 3 themes x 3 viewports + 320px overview + 640px/200% sources boundary).
- Horizontal overflow: **0/78**.
- Screenshot index: `visual-index.csv` (368 rows, interaction/state columns, old `visual-phase-c` 78 files preserved).
- Keyboard 200%: **16/16 PASS** (Tab order, focus ring, no clipping, bottom controls and footer reachable).
- WCAG AA scan: 24 page-theme combinations, 1105 text elements, 35 below threshold (all native LuCI/Aurora button/tab colours; report `contrast/after/report.md`).

## Per-theme coverage

- `bootstrap`: 26 screenshots, overflow 0.
- `aurora-light`: 26 screenshots, overflow 0.
- `aurora-dark`: 26 screenshots, overflow 0.

## 320px and 200% boundaries

- 320x900 / bootstrap / overview: scrollWidth=320, overflow=False, dark=false.
- 1280x900-200pct-effective-640 / bootstrap / sources: scrollWidth=640, overflow=False, dark=false.
- 320x900 / aurora-light / overview: scrollWidth=320, overflow=False, dark=false.
- 1280x900-200pct-effective-640 / aurora-light / sources: scrollWidth=640, overflow=False, dark=false.
- 320x900 / aurora-dark / overview: scrollWidth=320, overflow=False, dark=true.
- 1280x900-200pct-effective-640 / aurora-dark / sources: scrollWidth=640, overflow=False, dark=true.

## 600/900 content-width matrix

Measured `#maincontent` and `.cfi-form-map` widths at 320/375/640/768/900/1280 in all three themes (settings/sources/intelligence). Before and after match exactly:
- Rows compared: 54; layout/width differences before vs after: **0**.
- Cases where content width <=600px while viewport >600px: **0** (measured matrix in `width-matrix/after/matrix.json`).
- Because no mismatch case exists in Bootstrap/Aurora at the tested widths, the 600px media query is not wrong today. A container-query block was still added under `@supports (container-type: inline-size)` for the real sidebar/content-width case; all original media-query blocks remain unchanged as the fallback for browsers without container-query support.
- 640px (1280 @ 200%) effective width: map width 616 (Aurora) / 630 (Bootstrap); both stay two-column by design, no overflow.

## Original style comparison

v1.8.3-1 (`77a65a8`) was provisioned into the same real LuCI container. Navigation, title/section type scale, radii, shadow, colours and footer are compared in `baseline-compare/report.md`; matched screenshots are `baseline-compare/v183` and `baseline-compare/current`.

## Fixed in this round

- Early-return empty states: shared CSS + footer before return; description/Retry now render (array children).
- Tokens: `--cfi-radius` 12px, `--cfi-radius-card` 8px, `--cfi-radius-chip` 4px, `--cfi-shadow`, `--cfi-shadow-hover`, footer chip/border tokens.
- Tabs: wrap <=900px and restore `:focus-visible` outline; table headers use `--cfi-muted-strong` to pass AA in Aurora light.
