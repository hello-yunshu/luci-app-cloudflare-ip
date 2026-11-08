# Soak on `main @ 30d6c31` — TERMINATED EARLY BY USER DECISION

**Status: window NOT complete — terminated at 7 samples on explicit user
decision. `SOAK_DONE` was NOT written and no complete-window claim is made.**
This window does **not** serve as an exact-artifact acceptance window. The
acceptance basis is the user-adjudicated equivalence recorded in
`../VERDICT-20261108.md`.

| Item | Value |
|---|---|
| Device | OpenWrt 25.12.5 x86_64 KVM DUT, management address `192.168.2.x` |
| Package | `luci-app-cloudflare-ip 2.6.0-r9` (version unchanged) |
| Exact SHA | `30d6c319b8f797c596748fdf177d87ee7e9d9c9a` (`main`, merge of PR #46) |
| APK SHA-256 | `070aa3d50033009419d678519e99cc7e15f96abf1cf15022d180a21f4d30873b` |
| Build run | GitHub Actions `CI` run `42453547593`, artifact `luci-app-cloudflare-ip-apk-v25.12.5-run-42453547593-attempt-1` |
| Window start | 2026-11-08 15:21:16 CST (epoch `1794122476`) |
| Window end | 2026-11-09 03:21:16 CST (epoch `1794165676`) |
| Sampling | every 300 s into `/root/cfip-soak-30d6c31-12h/samples.log` |
| Runner | `/bin/sh /root/cfip-soak-final.sh /root/cfip-soak-30d6c31-12h 1794165676`, PID 31864, **PPID 1** |
| `SOAK_DONE` | **absent** — runner killed at 15:52:25, 7 samples collected |

## Termination

- Collected 7 samples, `15:21:16 → 15:51:17`, every 300–301 s.
- Runner `PID 31864` (PPID 1) stopped at **2026-11-08 15:52** on explicit user
  decision to release without waiting for a full window.
- Notes: `mem` 704–741 MB, `procs=2`, `cron=1`, `errors200=2` in all 7 samples —
  baseline only, **not long enough to support a 12 h stability statement**.
- Raw data: `samples-early-terminated.log` (7 lines, verbatim, no `SOAK_DONE`).


## Deployment

See `../soak-20261108-12h/deploy-30d6c31.md` for artifact verification, backup
path, rollback steps, and the pre/post installed-file hash manifest.

## Pre-flight baseline (first sample, 15:21:16)

| Signal | Value |
|---|---|
| Memory used | 720 MB of 984 MB |
| Proxy processes | 2 |
| `cf-ip-auto` cron entries | 1 |
| Error counter (`errors200`) | 2 (both lines predate 2026-11-08 03:16) |
| `cf_ip` status | running, enabled, scheduled, idle |

## Context: why this window exists

- The `4659503` window (`../soak-20261108-12h/`) completed 144 samples but is
  **intermediate evidence only**: `main` advanced to `30d6c31`, whose shipped
  frontend bytes differ (see `../soak-20261108-12h/diff-4659503-to-30d6c31.md`).
- Backend runtime (`root/` tree) is byte-identical across the two SHAs, so this
  window re-measures the same backend on the final artifact.

## Known expected transient

In the previous window one sample recorded `procs=0` at 07:31:15 while OpenClash
restarted on its own cycle; it recovered within one interval and no error was
logged. A similar single-sample dip in this window will be classified the same
way only if it (a) lasts one interval, (b) `cf_ip` status stays `running=true`,
(c) no new `run failed` appears, and (d) memory returns to the plateau.
Anything else is treated as a real anomaly and blocks the release.
