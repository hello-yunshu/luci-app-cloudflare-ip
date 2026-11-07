# Device drills (2026-11-07)

Device: OpenWrt `25.12.5` x86_64 Microsoft KVM (DUT), `2.6.0-r9` at exact SHA `d1e36f3`.

| Drill | Result | Details |
|---|---|---|
| ENOSPC write path | **PASS** | 2 MB tmpfs at `/tmp/cfip-enospc` filled to 100%; `cfip_atomic_write` returned 1, left the previous `status.json` intact (`{"seed":true}`), created no partial temp file; `CFIP_STATUS_DIR` status read still worked. See `enospc-device.log`. |
| Real power cut | **BLOCKED** | Needs hypervisor power control or recoverable boot/serial. It would also interrupt the running 12-hour soak. |
| Device rollback drill | **NOT RUN** | Container IPK/APK rollback + power-loss drills already pass; a device downgrade was not attempted. |
| Container reference | PASS | `../exact-sha-d1e36f3/drill-apk/`, `../exact-sha-d1e36f3/migration-apk/`, `../../device-20261107/` |

## Test-induced disturbance (recorded, not hidden)

A touch-test attempt touched a settings form control, which produced a "配置已保存，正在重启服务..." toast, added three explicit default options (`speedtest_dt`, `speedtest_threads`, `speedtest_ping_count`) and restarted the service. The config was restored byte-for-byte to the pre-test copy (SHA256 `2591b0cb…`); a stale `running:true` status left by the interrupted run was cleared after confirming no `cf-ip-auto` process existed. The 12-hour sampler therefore has a short service-restart event at about `23:35–23:38`; it is not a crash and must be read as a manual test artifact.
