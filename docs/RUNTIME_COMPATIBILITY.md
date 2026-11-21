# Runtime compatibility matrix

`luci-app-cloudflare-ip` and `luci-app-performance-manager` both execute
`/usr/bin/rill-runtime` from the same canonical Stable package. The old Preview
package remains recognized only so the manager can report a migration conflict.

| Consumer | Required package | Channel marker | Stable installed | Legacy Preview installed |
| --- | --- | --- | --- | --- |
| `luci-app-cloudflare-ip` (Rill Shadow/Assisted) | `rill-runtime` | `/usr/share/rill/runtime-channel` = `stable` | Supported | Reported as `legacy-preview`; Rill is disabled and Stable install remains blocked until explicit removal |
| `performance-manager-rill` | `rill-runtime` | `/usr/share/rill/runtime-channel` = `stable` | Supported | Rejected by package conflict |

Rules:

1. `rill-runtime` and `rill-runtime-preview` install the same executable path
   and declare a package conflict. CFI's Runtime Manager never removes the old
   package automatically; the user must remove it explicitly before installing
   the canonical Stable package.
2. Each package writes `/usr/share/rill/runtime-channel` (`stable` or
   `preview`). Consumers must read this marker before invoking the Runtime. If
   the marker is missing or unreadable, consumers fall back to package DB
   detection (`rill-runtime-preview` / `rill-runtime`) and otherwise treat the
   channel as `unknown`.
3. `luci-app-cloudflare-ip` accepts only the Stable package channel. Legacy
   Preview, unknown or unowned Runtime installations are incompatible:
   `--validate-config` fails for run/save, and the upgrade migration disables
   `cf_ip.rill.enabled` while preserving the rest of the configuration. Native
   mode remains available.
4. `performance-manager-rill` requires `rill-runtime` (Stable). It must not be
   installed on a Preview-only system; the package dependencies enforce this.
5. Activation is explicit: installing a Runtime package alone does not enable
   Rill. The user enables it in LuCI only after the matching channel is
   installed.

The base package never installs or depends on a Runtime. The legacy
`luci-app-cloudflare-ip-rill` compatibility addon now points to `rill-runtime`;
it does not activate Rill by itself. The Rill protocol still uses the existing
`preview-serve` command and `org.rill.preview.*` capabilities; these identify
the protocol surface and do not indicate the package channel.
