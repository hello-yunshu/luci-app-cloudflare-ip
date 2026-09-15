# luci-app-cloudflare-ip

**English** | [中文](README.md)

<p align="center">
  <strong>Cloudflare IP optimization and node updates for OpenWrt</strong>
</p>

<p align="center">
  Benchmark, verify, and apply Cloudflare IPs to PassWall or OpenClash through LuCI.
</p>

---

## What it does

`luci-app-cloudflare-ip` is an OpenWrt LuCI plugin. It uses
[CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest) to measure candidate IPs,
probes them against the configured target domain, and applies the result to PassWall or OpenClash.

It does not replace either proxy service and does not rewrite unrelated nodes. Measurement, apply, and rollback are handled as one device-side transaction. On timeout, probe failure, or failed service recovery, the transaction rolls back and attempts to restore the original service state.

## Features

- LuCI pages for overview, settings, sources, intelligence, PassWall, OpenClash, advanced options, and diagnostics
- PassWall / OpenClash modes with automatic service detection
- One-click CloudflareSpeedTest download and update
- IPv4, IPv6, or dual-stack measurement; TCP or HTTP protocols
- Multiple target domains, active target-domain probes, and per-IP reachability checks
- Scheduled runs using `6h`, `30m`, or five-field cron expressions
- OpenClash YAML backup, restore, and deletion
- Candidate sources, IP history, runtime logs, and bounded run history
- Safe Native ranking by default, with optional Adaptive Measurement, Rill Shadow, and LAN Publisher

## Current status

- Package version: `2.6.0-r3`
- Release tag: `v2.6.0-3`
- Release channel: `prerelease`
- The 2.x line remains the 2.0 prerelease development line, not a stable release

Packages are promoted only from a successful exact-head qualification run on `main`. IPK/APK files, `sha256sums.txt`, and `qualification.json` belong to one evidence chain; host tests and SDK builds do not replace live OpenWrt, hardware-compatibility, or long-running soak validation.

## Quick start

## Which file should I download?

From [Releases](../../releases), choose the base package for your OpenWrt release:

- OpenWrt 24.10.x → download `luci-app-cloudflare-ip_2.6.0-r3_all.ipk`
- OpenWrt 25.12+ → download `luci-app-cloudflare-ip-2.6.0-r3.apk`

Do not install both IPK and APK. Rill integration is included in the main package. One `luci-app-cloudflare-ip` base package includes Native ranking, Adaptive Measurement, and Operational Health; it does not include the Rill Runtime binary.

### 1. Prepare the router

- OpenWrt 24.10.x or 25.12+
- PassWall or OpenClash installed
- Proxy node domains routed through Cloudflare CDN
- GitHub access, or a working GitHub mirror configured in the plugin

### 2. Install the package

Download the package matching your OpenWrt release from [Releases](../../releases), then verify it:

```sh
sha256sum -c sha256sums.txt
```

| Format | Target | Install command |
| --- | --- | --- |
| `.ipk` | OpenWrt 24.10.x | `opkg install ./luci-app-cloudflare-ip_*.ipk` |
| `.apk` | OpenWrt 25.12+ | `apk add ./luci-app-cloudflare-ip-*.apk` |

Dependencies are declared by the package and include `luci-base`, `rpcd`, `uhttpd`, `bash`, `curl`, `tar`, `jq`, `ca-bundle`, and `ca-certificates`.

After installation, refresh LuCI and open **Services → Cloudflare IP Optimization**.

### 3. Run it once

1. In **Basic Settings**, choose PassWall or OpenClash and enter the original node domain.
2. Open the matching PassWall / OpenClash page and confirm the target domain and filters.
3. Download CFST from the Overview page, then run one manual optimization.
4. Confirm the generated nodes work before enabling the schedule.

Enter the original domain from the node configuration, not an optimized IP. PassWall matches `address`; OpenClash matches `server`. OpenClash `servername` and `Host` values remain unchanged.

## Pages and configuration

### Basic settings

| Option | Description | Default |
| --- | --- | --- |
| Enabled | Enable scheduled optimization | Off |
| Mode | `passwall` or `openclash` | `passwall` |
| IP count | Number of optimized IPs to keep | `4` |
| IP type | `ipv4`, `ipv6`, or `both` | `ipv4` |
| Benchmark protocol | `tcp` or `http` | `tcp` |
| Run schedule | `6h`, `30m`, or five-field cron | `6h` |

The proxy service is stopped before measurement by default to avoid proxy traffic affecting results, then restored to its previous state.

### PassWall

| Option | Description | Default |
| --- | --- | --- |
| Target domain | Node domains to optimize, comma-separated | — |
| Name suffix | Supports `{n}` index and `{ip}` placeholder | ` [CF-{n}]` |

Only nodes whose `address` matches a target domain are managed.

### OpenClash

| Option | Description | Default |
| --- | --- | --- |
| Config file | OpenClash YAML path | `/etc/openclash/config/config.yaml` |
| Target domain | Node domains to optimize, comma-separated | — |
| Name suffix | Supports `{n}` index and `{ip}` placeholder | ` [CF-{n}]` |
| Transport filter | For example, `ws,grpc` | — |
| Backup count | Number of YAML backups to retain | `3` |

Supports `vless`, `vmess`, and `trojan`. A node must have `tls: true` or use a supported network such as `ws`, `xhttp`, `grpc`, `h2`, or `http`. The plugin creates a backup before applying changes and performs block-level intended-mapping readback for managed nodes.

### Candidate sources

The Sources page supports Cloudflare official ranges, community seeds, good historical IPs, and custom HTTPS text lists. Custom lists accept IPs, `IP:port`, IPv6, bracketed IPv6 with a port, and CIDR. Domains are rejected and never DNS-resolved.

The default candidate budget is `128` unique IPs, with a range of `100–512`. All sources are merged and deduplicated locally, then measured in one CFST run; adding sources does not create an unbounded measurement.

### Intelligence and Rill

Adaptive Measurement is a Native pre-probe scheduler and defaults to `shadow`. It consumes pre-probe fields only. `guarded` becomes effective only after complete, compatible, fresh audit evidence meets recall, safety, and savings thresholds. Corrupt state, stale evidence, or probe failure returns the next run to the full Native flow.

Rill is disabled by default. Most users do not need the Rill Runtime. To use Candidate Rill Shadow / Assisted, install the base package first, then install `rill-runtime-preview` matching your OpenWrt release and CPU architecture from [rill-openwrt-packages Releases](https://github.com/hello-yunshu/rill-openwrt-packages/releases), and enable Rill in the LuCI Intelligence page. Rill is only candidate assistance or Shadow observation; Native ranking and safety boundaries remain authoritative. If the Runtime is absent, the page shows `Rill Runtime: Not installed`; Native mode remains available.

New users do not need to install `luci-app-cloudflare-ip-rill` manually. It is now a deprecated compatibility package for existing installations only.

### LAN Publisher

LAN Publisher is disabled by default, accepts LAN bindings only, and refuses `0.0.0.0`. When enabled, it can serve:

```text
/ip.txt
/best-ipv4.txt
/best-ipv6.txt
/result.json
```

It is an optional LAN compatibility output, not a replacement for direct PassWall/OpenClash updates. Do not expose it to the public internet.

### Advanced settings

Advanced options include startup delay, GitHub mirror, download retries, verbose logging, work directory, measurement and recovery deadlines, candidate budget, probe batches, source policy, and CFST persistence across sysupgrade.

Script self-update is deprecated. `auto_update=0` is the default; 2.x is a multi-file package and should be upgraded through a verified IPK/APK. UCI configuration, CFST, source caches, managed ownership, and bounded history persist across upgrades; runtime temporary files can be rebuilt.

## Data and troubleshooting

| Item | Path |
| --- | --- |
| UCI configuration | `/etc/config/cf_ip` |
| Persistent run status | `/etc/cf_ip/status.json` |
| Rill state | `/etc/cf_ip/rill-*.json` |
| Runtime log | `/tmp/cf_ip/cf-ip-auto.log` |
| Core command | `/usr/bin/cf-ip-auto` |
| RPC calls | `ubus call cf_ip <method>` |

Common checks:

- **The menu is missing**: clear the browser cache and run `/etc/init.d/rpcd reload`.
- **No nodes match**: make sure the target domain exactly matches PassWall `address` or OpenClash `server`.
- **Measurement succeeds but apply fails**: check SNI/Host, TLS/network settings, and proxy service state; the transaction will attempt a rollback.
- **CFST download fails**: check system time, CA certificates, DNS, network access, and the GitHub mirror.
- **Rill is unavailable**: confirm `rill-runtime-preview` and `/usr/bin/rill-runtime`; the engine will fall back to Native.

## Project structure

```text
package/luci-app-cloudflare-ip/
├── Makefile
├── root/
│   ├── etc/config/cf_ip                 # Default UCI configuration
│   ├── etc/init.d/cf_ip                 # Service lifecycle and cron
│   ├── usr/bin/cf-ip-auto-v2            # 2.x core entry point
│   ├── usr/libexec/rpcd/cf_ip           # rpcd backend
│   └── usr/libexec/cf-ip/*.sh           # Sources, measurement, transaction, recovery
├── htdocs/luci-static/resources/
│   ├── cloudflare-ip/                   # CSS and shared utilities
│   └── view/cloudflare-ip/              # 8 LuCI views
└── po/                                  # English and Chinese translations
```

## Architecture and safety boundaries

```text
LuCI views
    ↓ ubus / rpcd
cf_ip RPC backend
    ↓
cf-ip-auto → candidate sources → one CFST run → target-domain probes
    ↓
Native Rank / optional Rill assistance
    ↓ transactional apply, readback, health check, and rollback
PassWall or OpenClash
```

The core keeps one Native authority path: candidate sources and Reuse are deterministic; Rill has one Candidate Learner and cannot bypass target-domain probes, the Native safe envelope, or rollback. If fewer candidates qualify, the result reports a degraded candidate count instead of duplicating the fastest IP.

## Build and verification

GitHub Actions runs Shell/JSON/JavaScript checks, legacy contract tests, 2.x host contracts, Docker replay, and OpenWrt SDK IPK/APK builds. Pushes to `main` and Pull Requests trigger CI; Actions can also be dispatched manually.

Docker replay evidence is explicitly marked `replayed`. It does not prove live-device behavior and cannot replace hardware coverage or soak testing. Formal prerelease promotion is triggered only by a successful qualified `workflow_run` from `main`.

## Documentation

- [Real-device validation](docs/REAL_DEVICE_VALIDATION.md)
- [2.2 Adaptive Measurement](docs/2.2_ADAPTIVE_MEASUREMENT.md)
- [2.3–2.6 closeout](docs/2.3_TO_2.6_CLOSEOUT.md)
- [Default UCI configuration](package/luci-app-cloudflare-ip/root/etc/config/cf_ip)

## Acknowledgments

- [XIU2/CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest)
- [hello-yunshu/rill-ml](https://github.com/hello-yunshu/rill-ml)
- [hello-yunshu/rill-openwrt-packages](https://github.com/hello-yunshu/rill-openwrt-packages)

## License

GPL-3.0
