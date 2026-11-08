# Deploy `main@30d6c31` (same version number, second replacement)

Object: `main` = `30d6c319b8f797c596748fdf177d87ee7e9d9c9a` (merge of PR #46).
Version unchanged: `luci-app-cloudflare-ip 2.6.0-r9`.

| Item | Value |
|---|---|
| Artifact | `luci-app-cloudflare-ip-apk-v25.12.5-run-42453547593-attempt-1` |
| APK SHA-256 | `070aa3d50033009419d678519e99cc7e15f96abf1cf15022d180a21f4d30873b` |
| Size | 183,844 bytes |
| Local verify | `shasum -a 256 -c SHA256SUMS` → all OK; metadata `sha256` matches |
| Device verify | `sha256sum /tmp/luci-app-cloudflare-ip-30d6c31.apk` → same `070aa3d5…073b` |

## Same version number, different SHA (chain)

| Step | Version | Exact SHA | APK SHA-256 |
|---|---|---|---|
| Baseline (original) | `2.6.0-r9` | `d1e36f378ab488c75b336a29e991c723556b45f2` | (prior artifact) |
| Swap 1 (2026-11-08 03:16) | `2.6.0-r9` | `4659503879568513d8d2b5102e538d977edf8a77` | `337e680d42b4a3f90359983ec681736fdf908a953f8709004c6e9490512c1304` |
| **Swap 2 (2026-11-08 15:21)** | `2.6.0-r9` | **`30d6c319b8f797c596748fdf177d87ee7e9d9c9a`** | **`070aa3d50033009419d678519e99cc7e15f96abf1cf15022d180a21f4d30873b** |

## Backup and rollback

- Backup: `/root/cfip-backup-30d6c31-20261108-152006.tgz` (47,986,398 bytes),
  contains `/etc/config` and `/etc/openclash`.
- Rollback steps:
  1. `apk add --allow-untrusted --force-overwrite /tmp/luci-app-cloudflare-ip-4659503.apk`
     (re-upload the `4659503` artifact, SHA-256 `337e680d…1304` if the device copy
     is gone).
  2. `tar xzf /root/cfip-backup-30d6c31-20261108-152006.tgz -C /`
  3. `/etc/init.d/cf_ip restart` and verify `ubus call cf_ip status`.

## Installation

`apk add --allow-untrusted --force-overwrite` → `(1/1) Replacing
luci-app-cloudflare-ip (2.6.0-r9 -> 2.6.0-r9)`, `install_rc=0`,
`OK: 212.7 MiB in 474 packages`. The `ubus call service delete { "name":
"cf_ip_publisher" } (Not found)` line is the expected no-op for a publisher
service object that does not exist yet.

## Pre/post installed-file hashes (device)

Captured with `sha256sum` on the device immediately before and after
installation (`/tmp/pre_deploy_hashes.txt`, `/tmp/post_deploy_hashes.txt`).

**Unchanged (backend — 31 files):** `/etc/init.d/cf_ip`
`72d26c8c…c090`, `/etc/init.d/cf_ip_publisher` `18a86c04…1912`,
`/usr/bin/cf-ip-auto` `a7bc679b…27bb`, `/usr/bin/cf-ip-auto-legacy`
`e8215651…3db0`, `/usr/libexec/rpcd/cf_ip` `b37cb2ce…359f`,
all 20 files under `/usr/libexec/cf-ip/`,
`/usr/lib/lua/luci/controller/cloudflare-ip.lua`,
`/usr/share/cf-ip/candidate-rill-feature-schema-v2.json`,
`/usr/share/luci/menu.d/luci-app-cloudflare-ip.json`,
`/usr/share/rpcd/acl.d/luci-app-cloudflare-ip.json`.

**Changed (shipped frontend — 4 files):**

| Path | Before | After |
|---|---|---|
| `/www/luci-static/resources/cloudflare-ip/cloudflare-ip.css` | `f0a93a9b…1e6` | `4b3b3cf2…eea` |
| `…/view/cloudflare-ip/intelligence.js` | `a24540fb…e9c` | `cc73dda8…2c5` |
| `…/view/cloudflare-ip/overview.js` | `c97aa59c…6ab` | `3d877397…bd3d` |
| `…/view/cloudflare-ip/settings.js` | `c78b6572…21a` | `0aa0f52f…249d` |

Config hashes unchanged: `/etc/config/cf_ip` `2591b0cb…3751`,
`/etc/config/openclash` `8e97eb38…633b`, `/etc/config/samba4` `2209dd36…bb2f`.

## Post-install service check

| Check | Result |
|---|---|
| `apk list -I` | `luci-app-cloudflare-ip-2.6.0-r9 … [installed]` |
| `uci cf_ip.main.mode` / `enabled` | `openclash` / `1` |
| `ubus call cf_ip status` | `running=true`, `enabled=true`, `scheduled=true`, `active_run=false` |
| OpenClash | `running`; mihomo/clash processes present |
| Samba4 | `running` |
| LuCI view files | 8 files present |

## Honest note on the first start attempt

The first attempt to start the `30d6c31` window (15:20:52) reused the old
runner script, which hardcodes the `20261108-12h` directory. It appended exactly
one sample to the previous window's log. That line was removed
(`samples.log` back to 145 lines, `SOAK_DONE` last), the runner was killed, and
a parameterised script (`/root/cfip-soak-final.sh <dir> <end_epoch>`) was used
for a clean start at **15:21:16**. The intermediate window's sample file is
therefore exactly the 144 samples + `SOAK_DONE` already committed to this
branch.
