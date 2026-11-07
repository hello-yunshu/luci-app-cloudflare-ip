# Real-device round (2026-11-07)

Candidate: CI artifact `luci-app-cloudflare-ip-2.6.0-r9.apk` (run `42347398199`, attempt 1, SHA256 verified on device).
Device: `Microsoft Virtual Machine`, x86_64, OpenWrt `25.12.5`, apk-tools `3.0.5`, OpenClash `0.47.156`, Aurora `1.2.0-r20260808`, Bootstrap `26.218.70234`. This is a KVM virtual machine, not physical hardware.

## Baseline before install

- Installed package: `luci-app-cloudflare-ip 1.8.3-r1`; service enabled (`/etc/rc.d/S99cf_ip`); `mode=openclash`, `enabled=1`.
- `openclash.config=/yunshu/clash/clash-proxies.yaml` (exists, root-owned, mode 600); `cron_interval=custom`, `cron_custom='30 7,18,23 * * *'`.
- No `cfst` binary; PassWall not installed; OpenClash installed and running.
- Config and package files backed up on device (`/tmp/cfip-backup-20261107`) and locally (`device-backup-20261107`).

## Install and upgrade result

Install succeeded. Two upgrade regressions were confirmed and fixed:

1. `migrate-managed-config.sh` reset the existing `openclash.config` to the default `/etc/openclash/config/config.yaml`, which does not exist on this device. The runtime path check rejected files outside `/etc/openclash`.
2. `cron_interval=custom` was reset to `6h` even though `cron_custom` was a valid expression, because the migration called `--to-cron custom` without the expression.

Device values were restored immediately after the discovery. With the fixed scripts overlaid:

- `/usr/bin/cf-ip-auto --validate-config` → `{"success":true,"valid":true,"mode":"openclash","cron_interval":"custom"}`
- Migration is idempotent: config hash unchanged, custom schedule and external OpenClash path retained.

Final config diff is limited to `measurement_timeout` (added `300` for the run below), `work_dir` (new default `/usr/bin`) and `self_update_url` (intentional repo rename); all pre-existing user options are preserved. See `config-preservation.txt`.

## Functional results

| Check | Result |
|---|---|
| Service start/stop/restart | PASS (procd service present, stop reports not running, restart active) |
| Autostart | PASS (`/etc/rc.d/S99cf_ip`) |
| Config read/write via UCI RPC | PASS (read 0 → write 1 → commit → read 1 → restore 0) |
| CFST download | PASS (`v2.3.5`, 3.26 s, real GitHub API) |
| Run with shipped `measurement_timeout=60` | FAIL — `measurement timeout during CloudflareSpeedTest` |
| Run with `measurement_timeout=300` | PASS — 2/2 IPs, OpenClash stopped/restarted, config backup written |
| Logs | PASS (timestamped lifecycle log, failure reason included) |
| OpenClash real controller | PASS (service stopped for measurement, restarted, 3 processes after run) |
| PassWall real network | NOT RUN — PassWall is not installed on this device |

The run takes about 140 s with this workload, so the shipped 60 s deadline is too short. `300` was left in the device config as a workaround and is called out in the release review; reverting it will make scheduled runs fail again.

## UI rendering

- 120/120 matrix PASS: 8 pages × 5 CSS widths (320/375/640/768/1280) × bootstrap-light, aurora-light, aurora-dark, with device language `zh-cn`, no blank/loading views, theme assets loaded, no truncation/overflow. See `visual-matrix/report.json` and representative screenshots.
- 8/8 zoom PASS: aurora light/dark × 125% (`1024@1.25`) and 200% (`640@2`) for overview and logs, `data-darkmode` correct, `overflow=false`. See `visual-zoom/report.json` and screenshots.
- Login was tested with a temporary password; the original `/etc/shadow` root line and LuCI language/theme were restored after the run, and SSH key login still works.

## Soak

Started `2026-11-07 15:17:18`, target end `2026-11-08 15:17:18`; 5-minute samples of memory, OpenClash process count, cron entries, recent run errors and `cf_ip` status are written to `/tmp/cfip-soak-20261107/samples.log` on the device. **Not complete at the time of this report.**

## Stable Gate gaps (release decision: keep 2.6.0-r9)

- Physical device: **NOT SATISFIED** — this is a VM.
- 24-hour soak: **NOT COMPLETE**.
- PassWall real network: **NOT RUN** (not installed).
- Hardware matrix beyond x86_64, touch matrix, power-loss/ENOSPC drill: **NOT RUN**.
- Candidate artifact used for this round predates the two migration fixes; a rebuilt, re-qualified artifact is required before any release.
- OpenClash works only after raising `measurement_timeout`; the 60 s default failed on this device.

No tag, Release, version bump or `release-channel.json` change was made in this round.
