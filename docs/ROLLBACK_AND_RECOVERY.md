# Rollback, ENOSPC and opkg status recovery

Use this before any package upgrade and after any failed/aborted upgrade.
Container evidence: `docs/audits/next-release-evidence/phase-i/stable-gate-drills.md`.

## 1. Before upgrading (opkg / OpenWrt 24.10.x)

Store the backup **outside `/usr`** (for example `/root` or a USB path), because
an ENOSPC can leave `/usr/lib/opkg/status` truncated.

```sh
stamp=$(date +%Y%m%d-%H%M%S)
cp -p /usr/lib/opkg/status "/root/opkg-status.$stamp"
sha256sum "/root/opkg-status.$stamp" > "/root/opkg-status.$stamp.sha256"
cp -p /etc/config/cf_ip "/root/cf_ip.$stamp"
```

Keep the SHA256 beside the backup. Do not store it only in `/tmp`.

## 2. State that survives a rebuild (and what does not)

`/etc/cf_ip` is the only stateful directory (about 1 MiB on a device with
weeks of history). It holds `status.json`, `run-history.ndjson`,
`candidate-history.json`, and the Rill learner: `rill-state.json`,
`rill-qualification.json`, `rill-evidence.json`, `rill-state-meta.json`
(lineage + context fingerprint) and `rill-pending-feedback.json`. Losing it
restarts Rill collection from zero.

Two independent mechanisms keep it:

| Path | Mechanism | Covers |
| --- | --- | --- |
| `conffiles` in the Makefile | opkg/apk never rewrites it | package upgrade/rollback |
| `/lib/upgrade/keep.d/luci-app-cloudflare-ip` | sysupgrade copies it back | `sysupgrade` with "keep settings" |

The keep.d rule ships from
`package/luci-app-cloudflare-ip/root/lib/upgrade/keep.d/luci-app-cloudflare-ip`
and is pinned by `tests/sysupgrade-keep-contract.sh`. Earlier releases carried
the file on the device without it existing in the tree, so a clean rebuild would
have dropped it and silently stopped keeping the state.

What still loses data:

- `sysupgrade -n`, "do not keep settings", `firstboot`, or wiping the overlay
  (`/overlay`) — the keep list is not consulted, the directory is gone.
- Flashing a full image over the existing overlay instead of `sysupgrade`.

Back up before any of those, outside `/tmp`:

```sh
stamp=$(date +%Y%m%d-%H%M%S)
cp -a /etc/cf_ip "/root/cf_ip-state.$stamp"
tar -C /etc -czf "/root/cf_ip-state.$stamp.tar.gz" cf_ip
sha256sum "/root/cf_ip-state.$stamp.tar.gz" > "/root/cf_ip-state.$stamp.sha256"
```

Restore after the flash, before the first run:

```sh
[ -d /etc/cf_ip ] || mkdir -p /etc/cf_ip
tar -C /etc -xzf "/root/cf_ip-state.$stamp.tar.gz"
/etc/init.d/cf_ip restart
```

Keeping the bytes is necessary but not sufficient: Rill also rotates lineage
when the **learning context** changes, because a model trained for one context
is not valid for another. The fingerprint covers `ip_type`, the target domain
list, the speedtest protocol, and any `cfCOLO` restriction. Changing any of them
(even during an upgrade that preserved the files) starts the model over;
superseded files are renamed `*.quarantine.context.<timestamp>`, never deleted,
and `learningContext` / `lastResetReason` / `contextChangeScope` in the RPC
payload report it. How much is superseded depends on the dimension that moved:
an `ip_type` change drops every candidate-dependent file, a protocol change
additionally drops the per-IP latency priors, and a domain or colo change keeps
the per-IP, prefix and colo histories because they still describe the same
endpoints. A state file whose feature width no longer matches the runtime is
likewise quarantined as `feature_width_mismatch` or
`invalid_or_legacy_snapshot`.

## 3. After a failed upgrade or ENOSPC

1. Free space first (`df -k /usr`); restoring into a full filesystem fails the
   same way. Remove caches/downloads, not package files you still need.
2. Restore the status database atomically:

```sh
cp -p /root/opkg-status.$stamp /usr/lib/opkg/status.new
sync
mv /usr/lib/opkg/status.new /usr/lib/opkg/status
sha256sum -c /root/opkg-status.$stamp.sha256 --status || \
  { echo 'backup checksum mismatch' >&2; exit 1; }
```

3. Verify opkg can read the database:

```sh
opkg list-installed >/dev/null
```

Any parse error or empty list means stop; do not run another install.

4. Re-run the intended action:

```sh
opkg install --force-reinstall /tmp/luci-app-cloudflare-ip_<version>_all.ipk
```

For a rollback to an older version, opkg refuses a plain downgrade
(`Not downgrading package ...`). Use:

```sh
opkg install --force-downgrade /tmp/luci-app-cloudflare-ip_<older>_all.ipk
```

## 4. If the package files were partially replaced

The status backup describes the old package set, while `/usr` may contain new
files. After restoring the status and freeing space, `--force-reinstall` the
version you want, then verify:

```sh
opkg list-installed | grep luci-app-cloudflare-ip
/usr/bin/cf-ip-auto --status
uci show cf_ip | head
```

The UCI config is preserved across upgrade/rollback; the new defaults appear as
`/etc/config/cf_ip-opkg`.

## 5. APK / OpenWrt 25.12+

Back up the installed database and config:

```sh
cp -p /lib/apk/db/installed "/root/apk-installed.$stamp"
cp -p /etc/config/cf_ip "/root/cf_ip.$stamp"
```

After freeing space, restore the database, then reinstall the APK:

```sh
cp -p "/root/apk-installed.$stamp" /lib/apk/db/installed
apk add --allow-untrusted /tmp/luci-app-cloudflare-ip-<version>.apk
```

APK rollback, ENOSPC and power-loss drills passed in the 25.12.5 container
(`/audit-p1-p2-20261106/p1-1-apk-summary.txt`, 7/7 PASS); real-device flash
behaviour and a real power cut remain device-level work.

## 6. Evidence

`tests/opkg-status-recovery.sh` truncates the database, asserts it is rejected,
restores the pre-upgrade backup, and asserts opkg lists the same package count.
It runs in the `publisher-runtime` CI job against a disposable 24.10.8 rootfs.

**Not covered:** real flash corruption, failsafe mode, a real power cut, and
restoring the APK database after a real device failure. These remain
device-level work.
