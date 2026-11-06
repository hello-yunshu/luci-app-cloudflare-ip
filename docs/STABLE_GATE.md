# Stable Gate — criteria, decision and review flow

Status: **prepared, not executed.** `v2.6.0-8` and the P1-06 fix `v2.6.0-9` are published Pre-releases. No stable promotion and no channel change are authorized by this document. The compact operating list is [STABLE_GATE_ACTION.md](STABLE_GATE_ACTION.md).

## 1. Current base

| Item | Value |
|---|---|
| Source baseline | `2.6.0-r9`; release tag `v2.6.0-9` → `1bbb3d7a380157e8175f44f42c5f39d9159f09df` |
| Previous Pre-release | `v2.6.0-8` (2026-11-04), tag → `4cbad4d2bb68315ed22b4c702effb78c1cd03ffb` |
| Channel | `stable` in `release-channel.json`, but automatic promotion is disabled by the `release.yml` guard |
| Post-release install | r6→r8 IPK and fresh install PASS; r8→r9 + fresh install container drills in §4A (phase I) |
| Stable status | **NOT READY** — device/owner and decision blockers below are still open |

## 2. Entry criteria

### A. Release identity and bytes

- [ ] Pre-release `v2.6.0-8` still points to `M`; tag not moved.
- [ ] IPK/APK bytes re-downloaded from the published Release match `SHA256SUMS`.
- [ ] `qualification.json` commit/run/attempt still matches the released assets.
- [ ] No P0/P1 open in the issue register.
- [ ] Exact-SHA CI and Real LuCI UI Gate green on the candidate.

### B. Real-device and network coverage

- [ ] Physical OpenWrt device install/upgrade test (not container/VM).
- [ ] Hardware matrix: at least the documented supported devices/architectures.
- [ ] 24-hour soak on the physical device.
- [ ] PassWall **real proxy network** end-to-end (not only fixture/container).
- [ ] OpenClash real controller matrix on device.
- [ ] Architectures beyond x86_64: at least aarch64 package install + runtime page load; other declared architectures or explicitly excluded.
- [ ] Full keyboard/touch matrix on a real touch device.
- [ ] Power-loss / ENOSPC / rollback drill on device.

Current status: physical device and 24h soak are **PASS-BY-USER-DECISION (2026-11-04)** only for the pre-release boundary; they are **NOT RUN** as fresh evidence. PassWall real network is **NOT RUN**. arm64 is install/page-load only. Touch matrix is partial. These do not satisfy a Stable Gate without a new explicit user decision.

### C. Security and dependency boundary

- [ ] Shipped Runtime dependency graph has zero known advisories (currently PASS).
- [ ] Full workspace non-shipped advisories (zstd via optional polars) explicitly accepted or removed.
- [ ] Runtime pin and qualification manifest unchanged, or re-qualified after any change.

Current status: full-workspace non-shipped zstd advisories remain an open user decision; shipped Runtime is clean.

### D. Evidence and documentation

- [ ] Issue register P0/P1 closed with evidence.
- [ ] 51-point matrix, zoom/zh evidence, i18n gates, gate inventory all green.
- [ ] Post-release validation recorded for both IPK and APK.
- [ ] Rollback/withdrawal procedure reviewed.
- [ ] Release notes and CHANGELOG match the published bytes.

## 2A. Self-work completed on 2026-11-05

These items were done without a physical device. They reduce the number of
unknowns but do **not** satisfy the device criteria in §2 B.

### 2A.1 Hardware / architecture matrix

The package is `Architecture: all` for both IPK and APK, so the released bytes
are architecture-independent; installability still depends on the target's
`opkg`/`apk` and the dependency set. Evidence only exists for the rows marked.

| Target | Package | Install/upgrade evidence | LuCI page load | Real device | Status |
|---|---|---|---|---|---|
| OpenWrt 24.10.8 x86_64 | IPK `all` | fresh r9, r8→r9, r9→r8 forced rollback, ENOSPC, power-loss (container) PASS; historical r6→r8/r8→r6 PASS | Real LuCI UI Gate PASS | VM only (`3bf0ec1`), not physical | install PASS; device NOT RUN |
| OpenWrt 25.12.5 x86_64 | APK `all` | fresh r9, r8→r9, r9→r8 rollback, ENOSPC, power-loss (container) PASS | same LuCI frontend; no separate UI run | none | install PASS; device NOT RUN |
| OpenWrt 24.10.8 aarch64_generic | IPK `all` | r7 install PASS (container/emulated), r8 not separately run | r7 8 pages, 0 overflow | none | partial; r8 NOT RUN |
| Other declared arches (armv7, mips*, riscv64) | IPK/APK `all` | not built or tested | not tested | none | NOT RUN / scope decision required |
| OpenWrt < 24.10 | not supported | — | — | — | out of scope |

Hardware matrix conclusion: only x86_64 has end-to-end container evidence;
aarch64 has r7 install/page evidence; every other architecture is unproven. A
Stable claim must either add evidence per row or explicitly scope the release.

### 2A.2 Touch / keyboard ceiling reachable in a browser

| Area | Evidence | Browser-reachable limit |
|---|---|---|
| Keyboard focus | 312/312 real Tab focus sweep PASS; 16/16 keyboard at 200%; 51-point matrix focus states | Chromium covers tab order, focus ring, keyboard activation; OS-level IME and screen-reader output are not proven |
| Touch | 375×900 `hasTouch` tap to Sources and tap Refresh (notification) | Chromium emulates single-finger taps; multi-touch gestures, palm rejection, touch latency and mobile WebKit/Firefox are not covered |
| Remaining | full touch matrix, soft-keyboard layout, real touch device | requires a physical touch device; cannot be closed in headless Chromium |

### 2A.3 Security / dependency boundary material

Shipped Runtime dependency graph: **zero known advisories** (evidence
`docs/audits/g6-g7-evidence/runtime-security-advisories-20261102.json`; the
shipped `rill-runtime` cargo tree contains no `polars` or `zstd`).

Non-shipped zstd advisories (full workspace only, via optional `polars`):

| Advisory | Crate / version | Patched | Shipped? |
|---|---|---|---|
| RUSTSEC-2026-0391 | `zstd` 0.13.3 | >= 0.14.3 | no |
| RUSTSEC-2026-0398 | `zstd-safe` 7.2.4 | >= 8.2.0 | no |
| RUSTSEC-2026-0403 | `zstd-safe` 7.2.4 | >= 8.2.0 | no |
| RUSTSEC-2026-0410 | `zstd-sys` 2.0.16+zstd.1.5.7 | >= 2.1.2 | no |

Options for the Stable decision:

1. **Accept the non-shipped boundary** (recommended for r8): the package and
   shipped Runtime are clean; the advisories live in a workspace member
   (`polars`) that is not built into any released asset. Keep the existing
   fail-closed rule: if `polars`/`zstd` ever enters the shipped feature graph,
   qualification fails.
2. Upgrade the `polars`/`zstd` workspace pins to patched versions and re-run
   the full qualification. This changes the workspace lock and needs a new
   exact-SHA evidence cycle.
3. Remove the `polars` analytics workspace member. Larger change; not needed
   to ship the LuCI package.

This is a user/release-owner decision; the maintainer cannot accept it alone.

### 2A.4 Rollback / ENOSPC / power-loss drill (container)

See `docs/audits/next-release-evidence/phase-i/stable-gate-drills.md` for raw
commands and outputs. Summary:

- r8→r9 upgrade (IPK and APK): rc 0, custom UCI values and `/etc/config/cf_ip`
  hash preserved (IPK); APK merges the new default into `cf_ip.apk-new` without
  resetting user values.
- r9→r8 rollback (IPK and APK): plain install refuses a downgrade; forced
  downgrade returns r8 with the config hash unchanged.
- Fresh r9 install (IPK and APK): `--status` returns schema 2 and the exact
  `2.6.0-r9` package version.
- ENOSPC (full target filesystem, IPK and APK): APK reports
  `No space left on device` and installs nothing. IPK may return exit code 0
  while the extracted payload is zero bytes; the drill detects this as
  `payload_broken` rather than trusting the package-manager status. Freeing
  space plus a reinstall returns a working r9 in both formats.
- Power-loss (container kill during install, IPK and APK): r8 and the config
  survive; removing the stale package-manager lock and reinstalling reaches r9.
- Historical r6→r8 / r8→r6 IPK drills remain in the phase-i record.

These are container-level drills. They do not cover a real device power cut,
flash wear, or the OpenWrt failsafe/rollback path.

## 3. Decision roles

| Role | Responsibility |
|---|---|
| Maintainer | prepares evidence, runs gates, proposes Stable Gate; never self-approves |
| User / release owner | explicitly accepts device/soak/security boundaries and authorizes channel change |
| CI | proves exact-SHA software/qualification facts; cannot authorize a channel change |

No automatic promotion. `release.yml` intentionally refuses non-`prerelease` channels; see [RELEASE_CHANNEL_GUARD.md](RELEASE_CHANNEL_GUARD.md).

## 4. Review flow

1. **Evidence freeze**: choose the exact `main` SHA; no code changes after this point.
2. **Gate run**: exact-SHA CI + Real LuCI UI Gate + qualification; record run IDs/attempts.
3. **Device review**: attach physical-device, soak, PassWall real-network, rollback evidence; list uncovered items.
4. **Security review**: shipped vs non-shipped dependency decision.
5. **User decision**: accept or reject each open boundary; record the decision in the issue register.
6. **Channel change**: only after approval, a separate PR may change `release-channel.json` to `prerelease` (or a dedicated stable process is approved); this is a release action and must be explicitly authorized.
7. **Stable release**: only from the approved exact `main` SHA, with the same-run assets; tag is immutable; no asset replacement.
8. **Post-release**: re-download, checksum, install on the supported matrix, record results.

## 5. Blockers for r9 → stable (current)

| Blocker | Status | Required decision |
|---|---|---|
| Physical device / hardware matrix | matrix material prepared (§2A.1); device **NOT RUN** | new device evidence or explicit Stable-boundary acceptance |
| 24h soak | **NOT RUN** (historical SKIPPED/NOT STARTED) | run soak or explicitly accept |
| PassWall real proxy network | **NOT RUN** | run on device |
| arm64 beyond install/page load | r7 install/page only; r8 **NOT RUN** | expand or scope-exclude |
| Full touch/keyboard matrix | keyboard at browser ceiling; full touch **NOT RUN** | run on touch device |
| Full-workspace non-shipped zstd advisories | decision material prepared (§2A.3) | user accept boundary or upgrade |
| Rollback / ENOSPC / power-loss on device | container IPK+APK drills PASS; device **NOT RUN** | device drill plus opkg status backup procedure |
| P1-06 in released bytes | fixed by the P1-06 Pre-release (`v2.6.0-9`); the r9 bytes are the current Stable candidate | use the r9 bytes for a Stable claim |
| Channel change to stable | not authorized | explicit user authorization; do not bypass guard |

### 5A. External-device work (not executable here)

| Work | Who | Equipment | How | Gates that flip green |
|---|---|---|---|---|
| Physical device install/upgrade | user/release owner or a maintainer with hardware | one supported OpenWrt 24.10.x device (x86_64 or aarch64), serial/SSH access | flash/install r8 (or r9), run install + upgrade + rollback, capture firmware/arch/opkg logs | §2 B physical device row; increases §2 A evidence quality |
| Hardware matrix | same | at least one device per declared arch (x86_64, aarch64; scope others) | repeat install/page/proxy checks per row of §2A.1 | §2 B hardware matrix + arm64 rows |
| 24h soak | user/owner | same device powered continuously | run the service/update loop for 24h, record memory, errors, cron, publisher status | §2 B soak row |
| PassWall real proxy network | user/owner | device + a working PassWall node/subscription | start/stop/refresh through a real proxy, verify node updates and connectivity | §2 B PassWall row |
| OpenClash real controller | user/owner | device with OpenClash + mihomo + Ruby | backup/restore/delete and target update against the real controller | §2 B OpenClash row (already partially closed on aarch64) |
| Touch/keyboard matrix | user/owner | real touch device (tablet/panel) | tap-only navigation, soft keyboard, gestures, 200% zoom | §2 B full touch row |
| Power cut / ENOSPC on device | user/owner | device with serial or recoverable boot; small overlay | fill overlay, cut power during upgrade, recover; back up `/usr/lib/opkg/status` first | §2 B rollback drill row |
| zstd boundary / release build | user decides; maintainer executes | none for decision; build host for r9 | accept §2A.3 option 1/2/3; then rebuild r9 and repeat the exact-SHA cycle | §2 C full-workspace row; P1-06 leaves the shipped bytes |

Minimum remaining after all container self-work: **7 device/owner items** (physical device + matrix, soak, PassWall, OpenClash, touch, power/ENOSPC) plus **2 user decisions** (zstd boundary, channel change) and **one new build** (P1-06/r9). The Stable Gate cannot be executed before them.

**Conclusion: remain Pre-release; do not execute the Stable Gate.**
