# Release channel policy — expected behavior

`release-channel.json` is the single source of truth for the publication channel. `release.yml` promotes **both** channels automatically on `main`:

| Channel | Published as | `make_latest` |
|---|---|---|
| `prerelease` | GitHub prerelease | `false` |
| `stable` | full GitHub Release | `true` |

Automatic promotion replaced the manual Stable Gate on **2026-11-23** by owner decision. Only the manual promotion step was removed — the exact-SHA qualification manifest and the immutable tag guard remain mandatory for both channels, so nothing is published that failed verification.

Proxy upstream drift is **reported, never enforced**. `scripts/check-proxy-upstreams.py` runs on every release and writes a table into the job summary, but exits 0 when a ref changed: a new upstream version is not evidence that functionality fails, and the canary's adapter contracts do not install upstream packages, so no automated signal could prove incompatibility anyway. It exits 1 only for a defect in this repository's own baseline — a missing field or an unsupported upstream kind.

## What a red `Build and Release` run means now

Every failure is a real problem. There is no longer an "expected red run" state.

| Job | Meaning when it fails |
|---|---|
| `changes` | commit classification failed |
| `check-qualification` | channel unsupported/unparsable, qualification manifest invalid or missing, or release not eligible for the exact SHA |
| `collect` | asset download, checksum or release-asset contract failed |
| `release` | tag collision / immutability guard failed, or asset upload failed |

## Rules

- Do **not** bypass or comment out the qualification or tag-immutability checks.
- Do **not** treat proxy upstream drift as a release blocker. It is reported in the job summary and the baseline is advanced by a release-owner decision; only a defect in `proxy-upstream-baseline.json` itself fails that step.
- Do **not** hand-edit `release-channel.json` to make a failing run pass.
- Changing channel is a policy change: update `release-channel.json` **and** `tests/release-channel-contract.sh` together, so the contract test keeps matching the workflow.
- A tag is immutable: `scripts/guard-release-tag.sh` refuses to reuse a tag that points at a different SHA.
- A docs-only push is a clean no-op (`changes` classifies `docs/*`, `plans/*`, `README*`, `LICENSE`, `.gitignore` as non-release).

## Retired behavior (for reading old logs)

Before 2026-11-23 the `stable` channel was refused on purpose, and a red run with `check-qualification: failure` plus `collect`/`release` skipped was **expected**. Those runs logged:

```text
stable channel requires an explicit Stable Gate; automatic promotion is disabled
```

Example: run `41904752070` (2026-11-04, `main` after PR #25). If you see that message in a run started after 2026-11-23, the workflow file has been reverted — treat it as a regression.
