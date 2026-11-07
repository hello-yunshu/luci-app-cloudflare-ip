# Stable Gate — one-page execution and decision checklist

Status: **NOT READY.** This page is the compact operating list behind
[STABLE_GATE.md](STABLE_GATE.md) and §5A. It does not authorize a channel
change, a Stable tag, or a Stable Release.

## A. Decisions (user / release owner)

| # | Decision | Options | Acceptance line | If not decided |
|---|---|---|---|---|
| D1 | Non-shipped zstd advisories | accept boundary / upgrade polars+zstd / remove polars member | written decision in the issue register; fail-closed rule kept | Stable blocked (shipped Runtime is already clean) |
| D2 | Stable channel change | keep `stable` / authorize a separate channel PR | explicit user authorization; `release-channel.json` changed only by an authorized PR; `release-tag-immutability.sh` and `release-channel-contract.sh` exit 0 | remains `stable`, no promotion |
| D3 | Accept container-only rollback/ENOSPC evidence | accept / require device drill | decision recorded; if accepted, the device power/ENOSPC row is moved to a documented residual risk | device drill remains a blocker |

## B. External device / owner work

Each row must produce artifacts (log/screenshot/JSON), not just an assertion.

| # | Work | Who | Equipment | Method | Acceptance line |
|---|---|---|---|---|---|
| E1 | Device install/upgrade (**KVM accepted**) | user/owner or maintainer with KVM/device | one supported OpenWrt device, SSH | install/upgrade/reinstall the exact-SHA package; capture firmware/arch/apk logs | version r9 after install/replacement, config preserved, rollback works |
| E2 | Hardware matrix | user/owner | at least x86_64 and aarch64 | repeat E1 + page load per architecture | every declared architecture either passes or is explicitly scoped out |
| E3 | 12h soak | user/owner | same KVM/device, continuous power | run scheduled updates/proxy updates for 12h; record memory, errors, cron, publisher state | no crash/leak; publisher remains ready; logs archived |
| E4 | PassWall real proxy network | user/owner | device + working PassWall node | start/stop/refresh through the real proxy | node updates and connectivity verified on the real network |
| E5 | OpenClash real controller | user/owner | device with OpenClash + mihomo + Ruby | backup/restore/delete and target update | all three controller actions succeed on device |
| E6 | Touch/keyboard matrix | user/owner | real touch device (tablet/panel) | browser-emulated 8/8 touch pages + 3/3 at 200% done; physical taps, soft keyboard and gestures still need a real device | no dead control; no overflow; keyboard focus complete |
| E7 | Power cut / ENOSPC on device | user/owner | device with recoverable boot / serial | ENOSPC write-path drill done on the KVM DUT (2026-11-07); a real power cut needs recoverable boot/serial or hypervisor control | opkg usable after restore; config intact; procedure followed |

## C. Build and release gate (maintainer, after A/B)

| # | Work | Acceptance line |
|---|---|---|
| R1 | exact-SHA CI | 21/21 success on the release SHA |
| R2 | Real LuCI UI Gate | success on the same SHA |
| R3 | Package bytes | IPK/APK from the same run; SHA256 recorded; `Depends` has no `uhttpd` |
| R4 | Fresh install + upgrade | r8→r9 and fresh install pass on 24.10.8 (IPK) and 25.12.x (APK) containers, including rollback/ENOSPC/power-loss drills |
| R5 | Tag/release guards | `release-tag-immutability.sh`, `release-channel-contract.sh` exit 0; tag target immutable |
| R6 | Post-release | re-download all assets, `sha256sum -c` passes; install notes recorded |

## D. Current count

- Device/owner work still required: **4 items** — E3 12h soak completion, E4 PassWall, E6 physical touch, E7 real power cut. E1 is closed under the KVM decision; E2 is x86_64-DUT pass + aarch64 emulated-only; E5 OpenClash controller passed on the DUT.
- User decisions still required: **D1–D2 = 2 items**. D3 is now only about accepting container evidence for a real power cut, since the device ENOSPC drill passed.
- Build/release steps: **R1–R6**, executable by the maintainer after the above. R1–R3 already pass for `d1e36f3`; no rebuild is needed unless code changes.
- Container evidence already green: publisher fixtures, IPK/APK r8→r9 upgrade + fresh install + rollback/ENOSPC/power-loss drills on 24.10.8 and 25.12.x, matrix, i18n, UI Gate. These are **not** device evidence.

**Conclusion: NOT READY. No Stable action may be executed from this page.**
