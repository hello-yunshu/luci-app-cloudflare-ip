# Stable Gate — criteria, decision and review flow

Status: **prepared, not executed.** `v2.6.0-8` is a published Pre-release. No stable promotion, no channel change, no new tag/Release is authorized by this document.

## 1. Current base

| Item | Value |
|---|---|
| Pre-release | `v2.6.0-8` (2026-11-04), tag → `4cbad4d2bb68315ed22b4c702effb78c1cd03ffb` |
| Assets | IPK `1a3bc3cc…`, APK `a40cc859…`; same run `41901653719` attempt 1 |
| Channel | `stable` in `release-channel.json`, but automatic promotion is disabled by the `release.yml` guard |
| Post-release install | IPK/APK fresh install + r6→r8 upgrade PASS (see phase I report) |
| Stable status | **NOT READY** — blockers below are still open |

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

## 5. Blockers for r8 → stable (current)

| Blocker | Status | Required decision |
|---|---|---|
| Physical device / hardware matrix | NOT RUN (pre-release accepted by user decision) | new device evidence or explicit Stable-boundary acceptance |
| 24h soak | NOT RUN (historical SKIPPED/NOT STARTED) | run soak or explicitly accept |
| PassWall real proxy network | NOT RUN | run on device |
| arm64 beyond install/page load | partial | expand or scope-exclude |
| Full touch/keyboard matrix | partial | run on device |
| Full-workspace non-shipped zstd advisories | open | accept or wait for upstream fix |
| Channel change to stable | not authorized | explicit user authorization; do not bypass guard |

**Conclusion: remain Pre-release; do not execute the Stable Gate.**
