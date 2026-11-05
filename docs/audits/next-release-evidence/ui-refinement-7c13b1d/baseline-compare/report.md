# v1.8.3-1 real baseline vs current 2.x

Baseline: tag `v1.8.3-1`, commit `77a65a8`, provisioned into a real OpenWrt 24.10.8 + LuCI 26.205.85413 container. Current: working tree 2.6.0-r7 in the same LuCI version. Screenshots: `baseline-compare/v183` and `baseline-compare/current`.

| Aspect | v1.8.3-1 | 2.x (current) | Deviation | Judgement |
|---|---|---|---|---|
| Navigation | 4 entries: Overview, Settings, Advanced, Logs & Records | 6 static + OpenClash/PassWall conditional entries: Overview, Settings, Candidate IP Sources, Intelligence, Advanced, Logs & Records (+2) | +4 feature pages under the same `Services > Cloudflare IP Optimization` root; order preserved | Justified: new Sources/Intelligence/OpenClash/PassWall features require pages; no IA restructure |
| Page title | 24px, weight 700 | 26.56px, weight 700 | +2.56px via clamp(1.35rem, 1.1rem + 0.7vw, 1.8rem) | Acceptable typographic scaling; hierarchy unchanged |
| Section heading | 18px | 16.8px | -1.2px | Minor density change; no semantic change |
| Section container | radius 0px, shadow none | radius 12px, shadow `color(srgb 0.0745098 0.133333 0.219608 / 0.09) 0px 5px 18px 0px` | Cards added | Acceptable: 2.x has 8 pages and needs one card language; radius/shadow are theme-derived and subtle |
| Badge radius | 4px | 4px | none | Preserved |
| Body font | 13px / rgb(64, 64, 64) on rgb(255, 255, 255) | 13px / rgb(64, 64, 64) on rgb(255, 255, 255) | none | Preserved LuCI base typography |
| Footer | 11.375px, border rgb(102, 102, 102) | 11.375px, border rgb(217, 224, 231) | border now theme token instead of fixed #666 | Improvement: one footer component + theme-driven colour |
| Log text | 10px desktop / 9px mobile | 12px desktop and mobile | +2/+3px | Required readability fix (prompt §5.6) |
| Badge colours | raw `--success-color`/`--danger-color`/`--warning-color` | darker readable tokens (#176b31/#a52020/#805600, dark-mode variants) | colour values changed | Contrast/readability improvement, still theme-derived |

## Deliberate non-changes

- Navigation structure, page order, service root, form semantics and LuCI native controls are unchanged.
- No re-branding: footer, badges, cards and buttons keep the original LuCI/Aurora visual language.
- The only typography-scale change is the existing 2.x `clamp()` title; it did not alter information architecture.
