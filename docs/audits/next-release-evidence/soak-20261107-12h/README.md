# 12-hour soak — terminated before window end (superseded)

**Status: WINDOW NOT COMPLETE — no pass/fail verdict is claimed.** The runner
was left untouched through the interim snapshot below, then stopped at
2026-11-08 03:15 CST on explicit direction to test a newer build. It was not
restarted or re-attached. The reason and the decision are recorded in
“Termination” below.

| Item | Value |
|---|---|
| Device | OpenWrt 25.12.5 x86_64 Microsoft KVM DUT (192.168.1.1) |
| Package | `luci-app-cloudflare-ip 2.6.0-r9`, exact SHA `d1e36f378ab488c75b336a29e991c723556b45f2` |
| Window start | 2026-11-07 23:13:57 CST (epoch `1794064437`) |
| Window end (planned) | 2026-11-08 11:13:57 CST (epoch `1794107637`) |
| Sampling | every 300 s into `/root/cfip-soak-20261107-12h/samples.log` |
| Snapshot collected | 2026-11-08 00:38 CST (read-only SSH) |
| Last sample in snapshot | 2026-11-08 00:34:00 CST |
| Samples in snapshot | 17 of ~145 expected |
| Terminated | 2026-11-08 03:15:43 CST |
| Samples collected in total | 49 of ~145 expected (33.8% of window) |
| Last sample | 2026-11-08 03:14:04 CST |
| `SOAK_DONE` | **absent** (runner killed before the loop end) |

Raw snapshot: `samples-snapshot-20261108-0038.log` (the exact `samples.log`
bytes at collection time).

## Continuity

Every interval is 300 s or 301 s (the script uses `sleep 300` after a sample).
No gap and no duplicate timestamp across the full 23:13:57 → 03:14:04 span
(largest gap 301 s). The runner process was alive until it was stopped.

## Trend observation (49 samples, not a verdict)

| Signal | Range over 49 samples | Observation |
|---|---|---|
| Memory used | 645–755 MB of 984 MB | oscillates; no monotonic growth or step |
| OpenClash/mihomo processes (`procs`) | 2 in all samples | constant |
| `cf-ip-auto` cron entries (`cron`) | 1 in all samples | constant |
| Error counter (`errors200`) | 2 in all samples | constant, see below |
| `cf_ip` status | `running=false` in 44 samples, `true` in the first 5 (23:13–23:33) | the `true` window matches the documented manual touch test; `phase` is `scheduled` in those 4 samples and `idle` in the rest |

The `errors200=2` counter is flat and both matching log lines predate the
window:

- `2026-11-07 15:09:03 run failed: measurement timeout during CloudflareSpeedTest`
  — the old shipped 60 s default (P2-10).
- `2026-11-07 18:32:30 run failed: post-apply validation failed`.

No new `run failed` line appears after 23:13:57. The run attempts logged at
23:28–23:38 come from the manual touch-test side effect already documented in
`device-20261107/README.md`; the config was restored byte-for-byte and this is
a test artifact, not a crash or a soak failure.

## Termination

- **Stopped at:** 2026-11-08 03:15:43 CST, by `kill` on the runner PID 1216.
- **Collected:** 49 samples, 23:13:57 → 03:14:04, every 300–301 s, no gap
  above 301 s; 33.8% of the planned 12 h window. `SOAK_DONE` absent.
- **Reason:** the operator directed a new 12-hour soak of the latest build from
  `main`. The device can only host one harness at a time, and the old package
  (`d1e36f3`) is superseded by `4659503`.
- **Decision:** let the new build take over instead of waiting 8 h for the old
  window to close. Waiting would have delayed the required evidence for the
  current `main` by more than 20 h while adding nothing that the new window
  does not already cover. This record is kept as a partial observation, not as
  a completed soak.
- **What this partial window does support:** continuity of sampling, flat
  error counter, constant process/cron counts, no memory growth over 4 h.
  It does **not** cover the scheduled 07:30 run, an overnight idle period, or
  the full 12 h.
- **Raw data:** `samples-final-20261108-0320.log` (all 49 samples, copied from
  the device before the runner was stopped); earlier snapshot:
  `samples-snapshot-20261108-0038.log`.

No version bump, tag, Release, `release-channel.json` change or PR merge was
performed for this record.
