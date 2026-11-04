# Visual matrix - fresh audit corrected (9adb2d5 baseline)

> 当前候选：`90dfc13`。本轮补采真实浏览器 125%/150%/200% 缩放、320 reflow 与 zh_cn 375/1280 截图，见 `phase-f/zoom-zh/` 与 `next-release-phase-f-report.md`；下文的 9adb2d5 矩阵保留为历史视觉证据。

Real OpenWrt 24.10.8 + LuCI 26.205.85413 in a disposable container; Chromium via Playwright. Bootstrap / Aurora light / Aurora dark.

- Normal-state screenshots: **78** (8 pages x 3 themes x 3 viewports + 320px overview + 640px/200% sources).
- Horizontal overflow: **0/78**.
- Screenshot index: `visual-index.csv`, **396 rows**, 0 duplicate paths, 0 missing files; old `visual-phase-c` 78 files preserved.
- Keyboard 200%: **16/16 PASS**.
- WCAG AA re-scan: 24 page-theme combinations, 1389 elements, 41 below threshold (all native LuCI/Aurora buttons/tabs).
- Token/footer audit: 24 page-theme measurements, all with shared CSS + footer; section radius 12px, stat 8px, table 8px where present.

## Audit corrections

- Intelligence had been captured while `Loading view...`; 9 screenshots were recaptured after the view rendered (textLen 3277-3430, footer/css true).
- The previous contrast scan therefore missed Intelligence (0 text elements); re-scan now includes it and reports 41 failures across all 8 pages.
- The token/footer audit initially sampled the same Loading view and reported `css=false/footer=0`; with a proper view wait, all 8 pages x 3 themes report `css=true/footer=1`, no overflow.
- Current v1.8.3 comparison screenshots were recaptured at `9adb2d5`.

## Container query + old-browser fallback (executed)

`@supports` block was stripped from a copy of the served CSS to emulate a browser without container queries, then the same real LuCI page was measured with both stylesheets:

| Width | Full CSS | Stripped (media-only) |
|---|---|---|
| 375 | map=365 cols=1 media600=True | map=365 cols=1 media600=True |
| 375 | map=365 cols=1 media600=True | map=365 cols=1 media600=True |
| 640 | map=630 cols=2 media600=False | map=630 cols=2 media600=False |
| 640 | map=630 cols=2 media600=False | map=630 cols=2 media600=False |
| 768 | map=758 cols=2 media600=False | map=758 cols=2 media600=False |
| 768 | map=758 cols=2 media600=False | map=758 cols=2 media600=False |
| 768 synthetic500 | map=500 cols=1 media600=False | map=500 cols=1 media600=False |
| 768 synthetic500 | map=500 cols=2 media600=False | map=500 cols=2 media600=False |

- At real widths 375/640/768 the two paths are identical (1/2/2 columns, no overflow).
- With a synthetic 500px content container at 768, the full CSS switches to 1 column through `@container`; the stripped CSS keeps the old media-only 2-column behavior. This proves both paths run and that unsupported browsers keep the previous media-query behavior.

## Original style comparison

v1.8.3-1 (`77a65a8`) vs current `9adb2d5`, same container: navigation 4 -> 6 static + 2 conditional, section radius 0 -> 12px, shadow none -> themed, body/footer type unchanged, log 10/9px -> 12px, stat card 8px. Full table: `baseline-compare/report.md`.
