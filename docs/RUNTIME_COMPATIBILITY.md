# Runtime compatibility matrix

`luci-app-cloudflare-ip` and `luci-app-performance-manager` both execute
`/usr/bin/rill-runtime`, but they are qualified against different channels.
Only one Runtime package may be installed at a time:

| Consumer | Required package | Channel marker | Stable installed | Preview installed |
| --- | --- | --- | --- | --- |
| `luci-app-cloudflare-ip` (Rill Shadow/Assisted) | `rill-runtime-preview` | `/usr/share/rill/runtime-channel` = `preview` | Rejected; Rill is disabled by migration and `--validate-config` refuses `rill.enabled=1` | Supported |
| `performance-manager-rill` | `rill-runtime` | `/usr/share/rill/runtime-channel` = `stable` | Supported | Rejected by package conflict |

Rules:

1. `rill-runtime` and `rill-runtime-preview` install the same executable path
   and declare a package conflict. Installing one removes the other.
2. Each package writes `/usr/share/rill/runtime-channel` (`stable` or
   `preview`). Consumers must read this marker before invoking the Runtime. If
   the marker is missing or unreadable, consumers fall back to package DB
   detection (`rill-runtime-preview` / `rill-runtime`) and otherwise treat the
   channel as `unknown`.
3. `luci-app-cloudflare-ip` accepts only `preview`. A Stable or unknown channel
   is treated as incompatible: `--validate-config` fails for run/save, and the
   upgrade migration sets `cf_ip.rill.enabled=0` while preserving the rest of
   the configuration. Native mode remains available.
4. `performance-manager-rill` requires `rill-runtime` (Stable). It must not be
   installed on a Preview-only system; the package dependencies enforce this.
5. Activation is explicit: installing a Runtime package alone does not enable
   Rill. The user enables it in LuCI only after the matching channel is
   installed.

The base package never installs or depends on a Runtime. `luci-app-cloudflare-ip-rill`
is a legacy compatibility addon and pins `rill-runtime-preview`; it does not
activate Rill on a Stable channel.
