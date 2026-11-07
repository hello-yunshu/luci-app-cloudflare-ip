# 12-hour soak — interim observation

**Status: WINDOW NOT COMPLETE — this is not a final verdict.** No pass/fail
decision is made here. The soak runner was left running; it was not stopped,
restarted or re-attached, and no device configuration was changed during this
observation.

| Item | Value |
|---|---|
| Device | OpenWrt 25.12.5 x86_64 Microsoft KVM DUT (192.168.1.1) |
| Package | `luci-app-cloudflare-ip 2.6.0-r9`, exact SHA `d1e36f378ab488c75b336a29e991c723556b45f2` |
| Window start | 2026-11-07 23:13:57 CST (epoch `1794064437`) |
| Window end | 2026-11-08 11:13:57 CST (epoch `1794107637`) |
| Sampling | every 300 s into `/root/cfip-soak-20261107-12h/samples.log` |
| Snapshot collected | 2026-11-08 00:38 CST (read-only SSH) |
| Last sample in snapshot | 2026-11-08 00:34:00 CST |
| Samples in snapshot | 17 of ~145 expected |
| `SOAK_DONE` | **not present yet** (runner still inside the loop) |

Raw snapshot: `samples-snapshot-20261108-0038.log` (the exact `samples.log`
bytes at collection time).

## Continuity

Every interval is 300 s or 301 s (the script uses `sleep 300` after a sample).
No gap and no duplicate timestamp between 23:13:57 and 00:34:00. The runner
process was still alive at collection time.

## Trend observation (interim only)

| Signal | Range over 17 samples | Observation |
|---|---|---|
| Memory used | 699–752 MB of 984 MB (~71–76%) | oscillates; no monotonic growth or step |
| OpenClash/mihomo processes (`procs`) | 2 in all samples | constant |
| `cf-ip-auto` cron entries (`cron`) | 1 in all samples | constant |
| Error counter (`errors200`) | 2 in all samples | constant, see below |
| `cf_ip` status | `running=false`, `phase=idle` in all samples | no stale running state |

The `errors200=2` counter is flat and both matching log lines predate the
window:

- `2026-11-07 15:09:03 run failed: measurement timeout during CloudflareSpeedTest`
  — the old shipped 60 s default (P2-10).
- `2026-11-07 18:32:30 run failed: post-apply validation failed`.

No new `run failed` line appears after 23:13:57. The run attempts logged at
23:28–23:38 come from the manual touch-test side effect already documented in
`device-20261107/README.md`; the config was restored byte-for-byte and this is
a test artifact, not a crash or a soak failure.

## Open items for the final collection (after 11:13:57)

1. Confirm the runner exited and `SOAK_DONE <timestamp>` is present in
   `samples.log`.
2. Confirm all samples are continuous through the end (no gap > 301 s).
3. Review the scheduled 07:30 run that falls inside the window: outcome,
   error lines, and whether process/memory return to baseline afterwards.
4. Recompute the error counter delta and memory slope over the full 12 h.
5. Only then record a pass / anomaly-acceptable / fail verdict in
   `docs/STABLE_GATE.md` §2 B and the issue register.

No version bump, tag, Release, `release-channel.json` change or PR merge was
performed for this interim record.
