# 12-hour soak — main @ 4659503 (new build, in progress)

**Status: RUNNING — window ends 2026-11-08 15:16:08 CST. No verdict yet.**
This file is written at start time and will be updated with the final verdict
after `SOAK_DONE` appears.

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
| `SOAK_DONE` | not yet (expected at/after 15:16:08) |

## Why this build replaces the previous soak

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
