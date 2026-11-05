# Post-release validation — v2.6.0-8

Status: **PASS (containerized real OpenWrt install/upgrade).** Assets were downloaded from the published GitHub Release, not from CI artifacts, and installed in fresh OpenWrt rootfs containers.

## 1. Assets under test

| Asset | Size | SHA256 |
|---|---:|---|
| `luci-app-cloudflare-ip_2.6.0-r8_all.ipk` | 182736 | `1a3bc3cc8db4ac1a2b620197212b63463889a137c94d92e4467ea499494cbdeb` |
| `luci-app-cloudflare-ip-2.6.0-r8.apk` | 182025 | `a40cc8599f0c60fafce5279634ab30d0070f5850ec1939d895bffd88ccd5b935` |

Download and checksum:

```sh
gh release download v2.6.0-8 -D /tmp/cfip-release/download
cd /tmp/cfip-release/download && sha256sum -c SHA256SUMS
# both OK
```

## 2. IPK — fresh install (OpenWrt 24.10.8 x86_64)

Image: `openwrt/rootfs@sha256:9972a4b4747cd136abd597475d7b88c51a49fd849d0d53f069a2f4bf446061b9`

```sh
opkg update            # 0
opkg install /tmp/pkg.ipk   # 0
```

Result:

- `opkg list-installed` → `luci-app-cloudflare-ip - 2.6.0-r8`.
- Files present: `/etc/init.d/cf_ip`, `/usr/bin/cf-ip-auto`, `/usr/libexec/rpcd/cf_ip`.
- `/usr/bin/cf-ip-auto --status` → JSON `schemaVersion=2`, rc **0**.
- Dependencies resolved from official 24.10.8 feeds: bash 5.2.37-r1, curl 8.22.0-r1, flock 2.40.2-r1, jq 1.8.1-r1, tar 1.35-r1, ca-bundle, ca-certificates, luci-base.
- No `uhttpd` was installed as a dependency.

## 3. IPK — upgrade from v2.6.0-6

1. Fresh 24.10.8 container; install r6 IPK from the published `v2.6.0-6` Release (`opkg install` rc 0).
2. Set custom config:

```sh
uci set cf_ip.main.ip_count=7
uci set cf_ip.main.mode=openclash
uci set cf_ip.main.candidate_budget=333
uci commit cf_ip
sha256sum /etc/config/cf_ip
# fc5ee4c8e605ba6de9711aed4379720b3ee9ce5b1d233522140bf029f9e2a07b
```

3. Install the published r8 IPK (`opkg install` rc **0**; version r8).

Result:

- `/etc/config/cf_ip` SHA256 **unchanged** (`fc5ee4c8…`), all custom values preserved (`ip_count=7`, `mode=openclash`, `candidate_budget=333`).
- The new package default is written to `/etc/config/cf_ip-opkg` and is **not** applied over the user file.
- `cf-ip-auto --status` rc 0. Non-fatal `ubus call service delete ... (Not found)` lines are expected in a container where the service was never started.

## 4. APK — fresh install (OpenWrt 25.12.5 x86_64)

Image: `openwrt/rootfs@sha256:c5d5f05bab4ce06a4e840b3573671a06ec8ae9842273188ffc53f7021836b8e2`

```sh
apk update                              # 0
apk add --allow-untrusted /tmp/pkg.apk  # 0
```

Result:

- `apk list --installed` → `luci-app-cloudflare-ip-2.6.0-r8 noarch`.
- Files present: `/etc/init.d/cf_ip`, `/usr/bin/cf-ip-auto`, `/usr/libexec/rpcd/cf_ip`.
- `cf-ip-auto --status` → JSON `schemaVersion=2`, rc **0**.
- Post-install created `/etc/cf_ip/backups/pre-upgrade-20261104230631.1978`.
- Dependencies resolved from official 25.12.5 feeds; no `uhttpd`.

## 5. APK — upgrade from v2.6.0-6

1. Fresh 25.12.5 container; install r6 APK from `v2.6.0-6` (rc 0).
2. Set custom config (`ip_count=9`, `mode=openclash`, `candidate_budget=444`); record `/etc/config/cf_ip` SHA256 `39e9fcc7a95c38629a9f551d5cdb9569dcec39199bd87d7073724c6cb7e1eeef`.
3. `apk add --allow-untrusted /tmp/r8.apk` → `Upgrading ... (2.6.0-r6 -> 2.6.0-r8)`, rc **0**.

Result:

- Version r8; all custom UCI values preserved (`ip_count=9`, `mode=openclash`, `candidate_budget=444`).
- `/etc/config/cf_ip` SHA256 changed to `6e64f7d1…` because apk merged package defaults into the file; the package also wrote `/etc/config/cf_ip.apk-new`. User values are intact; this is a package-manager conffile merge, not a reset.
- `cf-ip-auto --status` rc 0; pre-upgrade backup `/etc/cf_ip/backups/pre-upgrade-20261104230802.2457` created.

## 6. Boundary

- Containers use the official OpenWrt rootfs images and real `opkg`/`apk`; this is not a physical-device run.
- `uhttpd` was installed separately to test listener availability; `/cgi-bin/luci/` returned 403 without a full LuCI/uhttpd CGI session, so browser-level page load is **not** claimed here. Package files, CLI status, dependency resolution and upgrade preservation are verified.
- Physical device, hardware matrix, 24h soak, PassWall real proxy network and touch matrix remain outside this validation.
