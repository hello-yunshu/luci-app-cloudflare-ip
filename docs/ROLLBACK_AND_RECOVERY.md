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

## 2. After a failed upgrade or ENOSPC

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

## 3. If the package files were partially replaced

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

## 4. APK / OpenWrt 25.12+

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

## 5. Evidence

`tests/opkg-status-recovery.sh` truncates the database, asserts it is rejected,
restores the pre-upgrade backup, and asserts opkg lists the same package count.
It runs in the `publisher-runtime` CI job against a disposable 24.10.8 rootfs.

**Not covered:** real flash corruption, failsafe mode, a real power cut, and
restoring the APK database after a real device failure. These remain
device-level work.
