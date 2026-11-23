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

## Status field semantics

`--rill-self-check`, `--rill-diagnostics` and the `intelligence` block of
`status.json` expose two separately named fields because the Stable package
still speaks the legacy `preview` protocol:

| Field | Meaning | Source | Gates Rill |
| --- | --- | --- | --- |
| `packageChannel` | Installed Runtime package: `stable`, `legacy-preview` or `unknown` | `/usr/share/rill/runtime-channel` marker, then the apk/opkg package DB | Yes — only `stable` is accepted |
| `protocolChannel` | Protocol surface the Runtime answers on: currently always `preview` | Runtime handshake/inspection response | No |
| `qualificationFreshness` | `fresh`, `stale`, `expired` or `none` for the last comparable evaluation | Qualification window (`evaluationFreshAt`) | Yes — `expired`/`none` fall back to Native |

`protocolChannel` is `null` whenever no Runtime was consulted (Rill disabled,
Runtime not installed, handshake rejected), so a missing Runtime can never be
reported as a Preview installation. The earlier combined `channel` field was
removed: it always carried the protocol value, which made a Stable install look
like a Preview one in LuCI and in CLI self-check output.

## Qualification calibration

Qualification is a slow signal by nature: at the default three runs a day, 30
attributed samples is about ten days. Three parts of it were recalibrated so
that the wait buys real evidence instead of a cliff:

| Area | Before | Now |
| --- | --- | --- |
| Failure reward | any failed probe → `-1`, same as an unreachable IP | `-1` only when every probe failed; a partial failure is graded by the failed-probe ratio (`-1.0` per failed fraction) |
| Evaluation health | gated on the **mean** delta; one `-1` sample among ten ties averaged `-0.18` and revoked a ten-day qualification | gated on the **median** delta; the mean stays published as telemetry, and the severe-regression counter plus win/loss counts still reject a candidate that is typically worse |
| Training health | `attributed == 100%`, `delayed >= 80%`, `errors <= 5%` — all three cannot fail for entries the pipeline writes, so the field was always "healthy" | adds signals that can fail: the median recent reward must be non-negative and the newest sample must be within `training_max_age_seconds` |
| Evidence freshness | `evaluation_max_age_seconds` (24 h) revoked qualification, so assisted mode flapped on sparse schedules | three zones: `fresh` (full confidence), `stale` (still assisted, confidence lowered to `medium` with reason `evaluation_stale`), `expired` after `evaluation_stale_seconds` (default 7 days, falls back to Native) |
| Context change | any fingerprint change quarantined state, qualification, evidence **and** the per-IP / prefix / colo histories | the changed dimension decides: `ip_type` quarantines everything, `protocol` also drops the per-IP latency priors, `domains`/`colo` keep every endpoint prior and reset only the model and its evidence |

The safety boundary is unchanged: assisted mode may only reorder the leading
`safe_top_k` Native candidates that already pass the loss, TTFB, total-time and
consecutive-failure filters, runtime health is re-checked on every run, and any
failed gate falls back to Native with `fallbackReason` set. The recalibration
changes how long the evidence bar takes to clear and how it is summarised, not
how much authority the candidate gets.

New UCI options under `config rill` (all exposed in LuCI; values are validated
before a run): `safe_top_k` (1..8), `min_feedback_samples` (5..200),
`evaluation_max_age_seconds` (3600..604800), `evaluation_stale_seconds`
(3600..2592000, must be `>= evaluation_max_age_seconds`),
`training_max_age_seconds` (1..2592000).
