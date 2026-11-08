# 12-hour soak — main @ 4659503 (complete, INTERMEDIATE EVIDENCE ONLY)

**Status: window complete (144 samples, `SOAK_DONE` present) but this is
intermediate evidence, not the acceptance object.** `main` moved to `30d6c31`
before this window ended, so this window does not cover the bytes that would
ship. It is **not** promoted to a pass because the window filled.

| Item | Value |
|---|---|
| Device | OpenWrt 25.12.5 x86_64 DUT, management address `192.168.2.x` |
| Package | `luci-app-cloudflare-ip 2.6.0-r9` |
| Exact SHA | `4659503879568513d8d2b5102e538d977edf8a77` (merge of PR #42 on `main`) |
| APK SHA-256 | `337e680d42b4a3f90359983ec681736fdf908a953f8709004c6e9490512c1304` |
| Build run | GitHub Actions `CI` run `42404270047`, artifact `luci-app-cloudflare-ip-apk-v25.12.5-run-42404270047-attempt-1` |
| Window start | 2026-11-08 03:16:08 CST (epoch `1794078968`) |
| Window end | 2026-11-08 15:16:08 CST (epoch `1794122168`) |
| Sampling | every 300 s into `/root/cfip-soak-20261108-12h/samples.log` |
| Runner | `/bin/sh /root/cfip-soak-20261108-12h.sh 1794122168`, PID 27589, PPID 1 |
| `SOAK_DONE` | `SOAK_DONE 2026-11-08 15:16:28` |

## Result of this window (measured, not a release verdict)

| Check | Measurement |
|---|---|
| Samples | 144, first `03:16:08`, last `15:11:28` (11 h 55 m 20 s span) |
| Intervals | 143 intervals, all 300 s or 301 s, **0 gaps > 301 s**, no duplicate timestamps |
| `SOAK_DONE` | present at `15:16:28`; runner exited |
| Memory used | min 510 MB, max 920 MB, last 730 MB; first-10 average 727 MB, last-10 average 729 MB → no growth trend |
| Proxy processes (`procs`) | 2 in 143 samples; **1 sample with 0** at `07:31:15` |
| `cf-ip-auto` cron entries | 1 in all samples |
| Error counter (`errors200`) | 2 in all samples — both lines predate the window (11-07 15:09 and 18:32); no new `run failed` |
| `cf_ip` status | `running=true` throughout; `active_run=true` only during the scheduled run starting 07:30 |

### The single `procs=0` sample

At `07:31:15` the sample recorded `procs=0`, memory 510 MB, and
`active_run=true` with `runId 1794094200-13309-19387` (the 07:30 cron run).
The very next sample (`07:36:15`) was back to `procs=2` / 698 MB, and all
following samples stayed at 2. Device inspection after the window shows the
OpenClash watchdog was started at ~07:31 and mihomo restarted again at ~10:18,
i.e. these are **OpenClash's own restart cycles** (its config-update log shows
independent 11:35 and 13:36 refresh cycles), not the plugin failing and not an
error-logged event. The `cf_ip` status remained `running=true`, no new
`run failed` line appeared, and memory returned to the previous plateau.

### Why this window is intermediate only

See `diff-4659503-to-30d6c31.md`: the entire installed backend tree
(`/etc/init.d/cf_ip`, `/usr/bin/cf-ip-auto*`, `/usr/libexec/cf-ip/*`,
`/usr/libexec/rpcd/cf_ip`, ucode controller) is byte-identical between the two
SHAs, but the shipped frontend changed (CSS + `overview.js` / `intelligence.js`
/ `settings.js` + 3 translation catalogs). The intermediate window therefore
observes the same backend as `30d6c31` but **not** the same artifact, so it
cannot serve as acceptance evidence. A full window on `30d6c31` is required.

## Why this build replaced the earlier soak

The previous 12-hour window (`soak-20261107-12h`, package SHA `d1e36f3`) was
stopped at 33.8% of its window and is recorded as a partial observation. The
operator directed that the latest `main` be tested; see the “Termination”
section in that record for the decision and rationale.

## Same version number, different SHA

`main` still carries `2.6.0-r9` (no version bump was requested). This install
is therefore a **same-version replacement**:

- Before: `2.6.0-r9` from exact SHA `d1e36f378ab488c75b336a29e991c723556b45f2`
- After: `2.6.0-r9` from exact SHA `4659503879568513d8d2b5102e538d977edf8a77`
- APK differs only by documents/tests/redaction changes merged since `d1e36f3`;
  shipped runtime file hashes are unchanged (see verification below).

## Pre-install backup and rollback

- Backup: `/root/cfip-backup-20261108-024954.tgz` on the device, containing
  `/etc/config`, `/etc/openclash`, `/etc/cf_ip` (47.9 MB).
- Pre-install config hashes:
  - `/etc/config/cf_ip` `2591b0cb3d332d8b0f8a6be059cf7f2160f4409cef115935c6d28c6a73d93751`
  - `/etc/config/openclash` `8e97eb380b11340e2931816f340ad8b1bc23fbfa3d0abc6afaa7869218d9633b`
  - `/etc/config/dhcp` `a2e5badc86df8af02a2a1be4cff3b129dc40b0255d640b18fe143b2158f3629f`
- Rollback: reinstall the previous APK (`2.6.0-r9`, SHA `d1e36f3`) with
  `apk add --allow-untrusted --force-overwrite`, then restore the tarball with
  `tar xzf /root/cfip-backup-20261108-024954.tgz -C /` and
  `/etc/init.d/cf_ip restart`. Because the version string is identical, the
  tarball is the authoritative rollback for configuration; the previous APK
  must be fetched from the `d1e36f3` qualification artifact if a binary
  rollback is needed.

## Install record

See `install-4659503.log`. Summary: `apk add --allow-untrusted
--force-overwrite` reported `Replacing luci-app-cloudflare-ip (2.6.0-r9 ->
2.6.0-r9)`, `install_rc=0`, `OK: 212.7 MiB in 474 packages`. The pre-upgrade
hook reported `{"success":true,"running":false,...}`; the post-upgrade hook
completed. The line `Command failed: ubus call service delete { "name":
"cf_ip_publisher" } (Not found)` is the expected no-op when the publisher
service object does not exist yet.

## Post-install verification

| Check | Result |
|---|---|
| `apk list -I` | `luci-app-cloudflare-ip-2.6.0-r9 ... [installed]` |
| Uploaded APK SHA-256 on device | matches `337e680d…1304` |
| `/etc/config/cf_ip` hash | unchanged `2591b0cb…3751` |
| `/etc/config/openclash` hash | unchanged `8e97eb38…633b` |
| `uci cf_ip.main.mode` / `enabled` | `openclash` / `1` (unchanged) |
| OpenClash | `running`; mihomo/clash processes present |
| Samba4 | `running`; `/etc/config/samba4` unchanged |
| Shipped file hashes | `/etc/init.d/cf_ip` `72d26c8c…c090` (unchanged), `/usr/bin/cf-ip-auto` `a7bc679b…7bb` |

No version bump, tag, Release, `release-channel.json` change or PR merge was
performed for this install.
