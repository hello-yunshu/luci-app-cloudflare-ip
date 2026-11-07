# aarch64 exact-SHA evidence (2026-11-07)

Candidate: IPK `luci-app-cloudflare-ip_2.6.0-r9_all.ipk` from CI run `42353699937`, attempt 1, exact commit `d1e36f378ab488c75b336a29e991c723556b45f2`. SHA256 `9ea6679e2804f84301444a93d088a5c9a52dc8f023dbaeb419a74d2b4c97c7ee`.

Environment: official OpenWrt `24.10.8` `armsr/armv8` rootfs imported as `cfip-owrt-arm64:24.10.8` with `docker import --platform linux/arm64`; `uname -m` = `aarch64`, `DISTRIB_ARCH` = `aarch64_generic`. This is an emulated container, **not a device**.

## Results

- Install and same-version force-reinstall: PASS; `opkg list-installed` shows `2.6.0-r9`; the modified `/etc/config/cf_ip` is kept (opkg writes `cf_ip-opkg`).
- CLI: `--version` reports `2.6.0-r9`/schema 2/API 3; `--validate-config` returns `{"success":true,"valid":true}` after `/etc/cf_ip` was chmod'd to a root-private directory (docker-created 0777 was rejected, as designed).
- LuCI: 6/6 core pages render at 1280×900 with zh-CN, no blank view, no horizontal overflow; 3/3 at 200% (`640×450` viewport, `deviceScaleFactor=2`). The `openclash`/`passwall` routes render the overview state because neither service is installed and are **not** counted as those views.
- Harness: uhttpd, rpcd and procd had to be started manually; `/etc/board.json` and `luci.main.mediaurlbase/resourcebase/lang` were set in the container.

## Limits

- Not an aarch64 device; no proxy network, no OpenClash/PassWall service.
- Touch, soft keyboard and power cut are not covered here (see `../touch-20261107/` and the device README).

Artifacts: `install.log`, `install.json`, `arm64-ui.json`, `1280x900-*.png`, `200pct-*.png`, `conditional-*.png`.
