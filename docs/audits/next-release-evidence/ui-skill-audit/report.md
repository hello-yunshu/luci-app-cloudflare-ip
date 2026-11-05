# UI skill audit - real LuCI

Result: **新发现 14 条（P1 2 / P2 7 / P3 5），已修 9 条。**

Method: `ui-ux-pro-max`（层级/间距/排版/一致性）、`impeccable`（critique/audit 状态完整性）、`uicraft`（生产级 Web 审计）、`ux-writing-audit`（按钮/标签/错误/空态/toast 四透镜）。与 LuCI/Aurora 冲突处按约束取舍：不引入新设计系统、不改主题配色、不改信息架构。

Environment: OpenWrt 24.10.8 x86_64 rootfs，LuCI `26.301.70438~aa4865e`，真实 uhttpd/rpcd/LuCI 登录；Bootstrap、Aurora light、Aurora dark（`luci-theme-aurora 1.4.0-r20260920`）。基线为 `main b556334` 之后的 `a8f89e8`；本轮分支 `audit/ui-skill-review`，修复提交 `7a08814`。

Coverage: 8 页（Overview / Settings / OpenClash / Candidate IP Sources / PassWall / Intelligence / Advanced / Logs & Records）× 3 主题 × 375/768/1280，外加 320 与 1280@200%（640 CSS px 等效）。共 120 张真实浏览器截图；0 页面级横向溢出；432 个 Tab 焦点采样，0 个无可见焦点指示。前几轮覆盖的 43 项交互与七态矩阵复核未见回归。

## Findings

| Severity | Page | Issue | Basis | Status |
|---|---|---|---|---|
| P1 | 6 form pages | Bootstrap mobile single-column labels stay right-aligned above left controls | UICraft spatial/hierarchy; Nielsen #4; WCAG 3.3.2 | 已修 |
| P1 | all form pages | Input focus ring uses 30% alpha brand tint | WCAG 2.4.11 focus appearance | 已修 |
| P2 | Overview / Logs | 375/320 KV table cells start outside scroll wrapper, cutting first character | UICraft responsive/table readability | 已修 |
| P2 | Intelligence | Copy button changes text to Copied but leaves aria-label=Copy | WCAG 4.1.2; UX writing feedback | 已修 |
| P2 | Overview | Empty Last Result renders “⚠ -” | Impeccable state completeness; UX writing empty state | 已修 |
| P2 | Logs | Diagnostics failure exposes internal command and no next step | UX writing error formula; Nielsen #9 | 已修 |
| P2 | OpenClash | Backup failure exposes internal command; only Retry | UX writing error formula; Nielsen #9 | 已修 |
| P2 | Candidate Sources | “Official · Cloudflare Official” duplication and hard-clipped MultiValue summary | UX writing consistency; UICraft overflow | 已修 |
| P2 | OpenClash | Delete/restore confirmations do not name the backup or say delete is irreversible | UX writing destructive confirmation; Nielsen #5 | 已修 |
| P3 | Aurora dark native controls | Theme-owned buttons measure about 3.7:1 white-on-blue | WCAG 1.4.3 | 仅报告 |
| P3 | Logs | “No logs found.” lacks a next action | UX writing empty-state actionability | 未改 |
| P3 | Intelligence | Copy/collapse buttons are 32px tall (<44 comfortable target; WCAG 2.5.8 24px passes) | UICraft touch; WCAG 2.5.8 | 未改 |
| P3 | Advanced | Deprecated Script Update URL remains editable while the note says 2.x ignores it | Nielsen #5; UX writing consistency | 未改 |
| P3 | Candidate Sources | Custom Sources GridSection keeps 7 columns at 768; headers wrap | UICraft responsive table hierarchy | 未改 |

## Fixed changes

1. **Mobile label alignment**: raised selector specificity over Bootstrap's `.cbi-value label.cbi-value-title` right-alignment inside the single-column media/container queries. Before/after: `before/before-375-settings.png`, `after/after-375-settings.png`.
2. **Focus ring**: `outline: 2px solid var(--cfi-link)` instead of a 30% tint. Before/after computed: `color(srgb … / 0.3)` → `rgb(23,105,170)`; `after/after-focus-input.png`.
3. **KV table clipping**: restored `0.12em 0.6rem` horizontal padding for mobile `.cfi-kv-table` cells. Before/after: `before/before-375-overview.png`, `after/after-320-overview.png`.
4. **Copy aria state**: `aria-label` now toggles Copy → Copied → Copy with the visible label. DOM evidence: `data/before-aria.json`.
5. **Last Result empty**: “⚠ -” → `Not run yet` neutral gray badge; `after/after-320-overview.png`.
6. **Diagnostics error**: actionable sentence + collapsed `Technical details`; `after/after-logs-error.png`.
7. **OpenClash backup error**: same actionable pattern + Retry; `after/after-openclash-error.png`.
8. **Source labels**: official options now use the registry name only, removing “Official · Cloudflare Official” duplication and fitting the 375px MultiValue summary; `before/before-375-sources.png` → `after/after-375-sources.png`.
9. **Destructive confirmations**: delete/restore now name the backup timestamp; delete states it cannot be undone; `before/before-delete-modal.png` → `after/after-delete-modal.png`.

New i18n keys: Not run yet, Diagnostics unavailable. Refresh the page…, Unable to load OpenClash backups. Retry…, Technical details, Restore the backup from %s…, Delete the backup from %s…. Removed obsolete raw-error/confirmation keys. i18n contract: 476 keys / 487 entries, PASS; negative control FAIL as expected (`data/i18n-positive.txt`, `data/i18n-negative.txt`).

## Not changed (recommendations)

- **P3 Aurora dark native buttons 3.7:1**: theme-owned palette; do not change theme colors. Recommend upstream Aurora fix or accept as native admin density.
- **P3 “No logs found.”**: recommend “No logs yet. Run a speed test from Overview to generate output.” Copy-only change; deferred to avoid another i18n round without user request.
- **P3 32px copy/collapse buttons**: WCAG 2.5.8 minimum 24px is met; increasing to 44px would break LuCI admin density. Keep.
- **P3 Advanced deprecated URL**: recommend marking `self_update_url` read-only or moving it under a migration note in a future, approved IA pass.
- **P3 Custom Sources 7-column grid at 768**: native `form.GridSection`; converting it to the responsive card table is structural and out of scope. Recommend a future dedicated change.

## v1.8.3-1 baseline

No unhelpful deviation found; **0 rollback recommendations**. Deliberate deviations remain improvements: larger page title / smaller section heading (clearer hierarchy), 12px card surfaces for 8 pages, theme-token footer border, 12px log text (from 9–10px), darker readable badge tokens, and 4 feature pages added under the same Services root without changing navigation structure. The only reversible candidate is the section heading 16.8px vs baseline 18px; it is retained for density and title/heading contrast.

## Local gates

- `node --check` all packaged JS: PASS
- `actionlint .github/workflows/*.yml`: PASS
- i18n contract: PASS (negative control FAIL as expected)
- local LuCI fixtures 7/7: PASS; `tests/openclash-rpc-contract.sh`: PASS; package identity: PASS
- Real LuCI Playwright matrix: 120/120 captured, 0 page overflow
- **未创建 PR、未触发任何 Actions，验证均为本地执行。** No tag/Release/channel change; no push.

## Evidence

- `matrix/<theme>/<viewport>/<page>.png`: 120 final screenshots
- `data/metrics-final.jsonl`: per-page overflow/clip/tiny-target/contrast metrics
- `data/focus-before.json`: 432 tab stops before fixes
- `data/contrast-failures.json`: theme-owned contrast findings
- `before/`, `after/`: paired evidence for the 9 fixes
- `scripts/`: local Playwright audit, contrast/focus, error-state, stress and confirmation scripts
