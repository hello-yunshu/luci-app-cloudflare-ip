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

## Exact-SHA requalification (2026-11-07)

The first candidate predated the two migration fixes. The final candidate is the CI artifact rebuilt from exact SHA `d1e36f378ab488c75b336a29e991c723556b45f2` (run `42353699937`, attempt 1):

- `qualification.json` manifest: `commit=d1e36f3…`, `runId=42353699937`, `runAttempt=1`; `validate-qualification-evidence.py` → `release qualification passed`.
- APK: `luci-app-cloudflare-ip-2.6.0-r9.apk`, SHA256 `c014731bdefe5f1478139a66b6226dd818c9ca1737e06b08fdbcdf4109a4c4ca` (`/tmp/cfip-d1e36f3.apk` on the device); installed with `apk add --allow-untrusted --force-overwrite` → `Replacing luci-app-cloudflare-ip (2.6.0-r9 -> 2.6.0-r9)`, pre/post-upgrade hooks ran. The earlier `/tmp/luci-app-cloudflare-ip-2.6.0-r9.apk` (`305f01de…`) is the superseded pre-fix artifact.
- `/etc/config/cf_ip` SHA256 unchanged after reinstall; `cron_interval=custom`, `openclash.config` outside `/etc/openclash` preserved; `--validate-config` → `{"success":true,"valid":true}`.
- IPK counterpart: `luci-app-cloudflare-ip_2.6.0-r9_all.ipk` from the same run (artifact `13566913851`), SHA256 `9ea6676f…`, used for the aarch64 container run.

## Soak

Restarted for the user-approved **12-hour** duration: `2026-11-07 23:13:57` → `2026-11-08 11:13:57` (device local time, epoch `1794064437` → `1794107637`). The sampler writes one line every 300 s to `/root/cfip-soak-20261107-12h/samples.log`; `README.txt` in that directory records host, start/end and interval. Each sample records memory, OpenClash process count, cron entry count, the last 200 error lines and the `cf_ip` status. It runs detached (`cfip-soak-12h.sh`), so no live monitoring is needed; the file can be retrieved after the 12 hours. **Not complete at the time of this report.**

A touch-test side effect at about `23:35–23:38` (device time) saved three explicit default options and restarted the service. The config was restored byte-for-byte to the pre-test copy (SHA256 `2591b0cb…`) and a stale `running:true` status left by the interrupted run was cleared after confirming no `cf-ip-auto` process existed. This is a manual test artifact, not a crash; see `../drills-20261107/README.md`.

## Stable Gate gaps (release decision: keep 2.6.0-r9)

- Physical device: **SATISFIED under the user's KVM-equivalence decision (2026-11-07)**. Device row is closed; this remains a VM, not physical hardware.
- 12-hour soak: **IN PROGRESS** (`23:13:57` → `11:13:57`), not complete.
- PassWall real network: **NOT RUN** — PassWall is not installed on this device; no substitute scenario was used.
- arm64: **install/page PASS in an emulated aarch64 container** (exact-SHA IPK, 8/8 pages, 3/3 at 200%), but no aarch64 DUT.
- Touch: **browser-emulated PASS** (8/8 pages at 1024×768 `hasTouch`, 3/3 at 200%); physical touch, soft keyboard and multi-finger gestures are **BLOCKED**.
- ENOSPC: **device write-path drill PASS** — a 2 MB tmpfs was filled, `cfip_atomic_write` returned 1, the previous `status.json` stayed intact and no partial temp file remained.
- Real power cut: **BLOCKED** — requires hypervisor power control or recoverable boot; it would also interrupt the 12-hour soak.
- Device rollback drill: **NOT RUN** (container rollback drills PASS).
- Candidate artifact: rebuilt and re-qualified from exact SHA `d1e36f3…`; the earlier artifact is superseded.
- OpenClash works only after raising `measurement_timeout`; the 60 s default failed on this device. See the issue-register recommendation.

No tag, Release, version bump or `release-channel.json` change was made in this round.
