# Stable Gate drills — rollback, ENOSPC, power-loss (containers)

Date: 2026-11-05. Scope: **container-level drills only**. No physical device,
flash, or failsafe path is exercised. Images and packages:

| Item | Value |
|---|---|
| Base image | `openwrt/rootfs@sha256:9972a4b4747cd136abd597475d7b88c51a49fd849d0d53f069a2f4bf446061b9` (24.10.8 x86_64) |
| Base state | r6 IPK installed, custom UCI (`enabled=1`, `mode=openclash`, `ip_count=7`, `lan.port=34567`) committed; config SHA256 `f1b3946e73f11dc82c438683cdfe9a59eab1db0487bf9cc3e8ea5cff028b0b63` |
| r6 IPK | 172082 bytes, SHA256 `a7c0c411d4be2784e196757bd9b1a2b31f9b6ea8ad520eb1649e6fb4d2d405d5` |
| r8 IPK | 182736 bytes, SHA256 `1a3bc3cc8db4ac1a2b620197212b63463889a137c94d92e4467ea499494cbdeb` (matches the published asset) |

## 1. Upgrade and rollback

Upgrade r6 → r8 (`opkg install r8.ipk`): rc 0, version `2.6.0-r8`, config SHA256
unchanged, custom values retained; the new default config was written to
`/etc/config/cf_ip-opkg`.

Plain downgrade (`opkg install r6.ipk`):

```
Not downgrading package luci-app-cloudflare-ip on root from 2.6.0-r8 to 2.6.0-r6.
```

rc 0 but no change. Explicit rollback (`opkg install --force-downgrade r6.ipk`):
rc 0, version `2.6.0-r6`, config SHA256 unchanged, custom values retained.

Conclusion: rollback requires `--force-downgrade` (or remove + install); the
config survives both directions. This is the procedure to document for support.

## 2. ENOSPC

### 2.1 Narrow `/tmp` (script-phase abort)

A 2 MiB `/tmp` tmpfs with 12 KiB free made the upgrade fail before extraction:

```
cf_ip stop failed; refusing package removal
 * pkg_run_script: package "luci-app-cloudflare-ip" prerm script returned status 1.
```

rc 255, version stayed r6, config SHA256 unchanged, binary still ran
(`--status` rc 0). This is an abort at the package-script boundary, not a
data-write ENOSPC.

### 2.2 Full target filesystem (real ENOSPC)

`/usr` was replaced by a 13.4 MiB tmpfs containing the real r6 `/usr` copy plus
a filler leaving 4 KiB free; the package was reinstalled fresh (r8, no prior r8
files). Result:

```
Installing luci-app-cloudflare-ip (2.6.0-r8) to root...
 * opkg_conf_write_status_files: Couldn't close //usr/lib/opkg/status: No space left on device.
Configuring luci-app-cloudflare-ip.
```

rc 0, but the opkg status DB write failed; subsequent `opkg list-installed`
printed `parse_from_stream_nomalloc: Missing new line character at end of file!`
and the package appeared installed with its binary present. Config SHA256
unchanged.

Recovery: freed the full filesystem (detached the tmpfs, exposing the intact
original `/usr` with no package and a valid DB), then reinstalled:

```
retry-rc=0
luci-app-cloudflare-ip - 2.6.0-r8
config SHA256 unchanged
--status rc=0
```

Conclusion: on a full device, ENOSPC can corrupt `/usr/lib/opkg/status` even
though files were written. Support procedure must free space first, verify the
status DB, then reinstall; a device-side DB backup/restore step is required for
a Stable claim. This is not covered by the current rollback documentation.

## 3. Power loss

Started `opkg install r8.ipk` in a live container and killed the container
(`docker kill`) after 3 s, then restarted it:

```
version: 2.6.0-r6
config SHA256 unchanged
install rc file absent (process killed mid-install)
install log had run the service-stop/prerm phase only
```

Reinstall after restart: rc 0, version `2.6.0-r8`, config SHA256 unchanged,
`--status` rc 0.

Conclusion: an abrupt power cut during the prerm phase leaves the old version
installed and the config intact; a retry succeeds. A cut during the data-write
phase was not forced in this drill and remains device-only work (flash
behaviour cannot be reproduced in a container).

## 4. Not covered

- physical-device flash wear, failsafe mode, and boot-time recovery;
- `apk` (25.12.x) rollback/ENOSPC/power-loss drills;
- interruption during the actual file-extraction phase (timing was not forced);
- real power cut (docker kill is not a hardware power loss).

## 5. opkg status backup/restore drill

Procedure: `docs/ROLLBACK_AND_RECOVERY.md`. Test: `tests/opkg-status-recovery.sh`,
run in a fresh 24.10.8 container with 133 installed packages:

```
PASS baseline status is readable (133 entries)
PASS truncated status is rejected (rc=0, stderr=92 bytes)
PASS restored status matches the backup and opkg lists 133 packages
rc=0
```

The test truncates `/usr/lib/opkg/status` (the ENOSPC symptom), records the
backup SHA256, restores the backup atomically, and requires the package count to
match. It is wired into the `publisher-runtime` CI job.

Not covered: interruption of the restore itself (power cut while writing the
backup), APK database restore, and real flash corruption.

