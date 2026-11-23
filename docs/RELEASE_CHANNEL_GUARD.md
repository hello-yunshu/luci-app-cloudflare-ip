# Release channel policy — expected behavior

`release-channel.json` is the single source of truth for the publication channel. `release.yml` promotes **both** channels automatically on `main`:

| Channel | Published as | `make_latest` |
|---|---|---|
| `prerelease` | GitHub prerelease | `false` |
| `stable` | full GitHub Release | `true` |

Automatic promotion replaced the manual Stable Gate on **2026-11-23** by owner decision. Only the manual promotion step was removed — the exact-SHA qualification manifest, the proxy-upstream requalification block and the immutable tag guard remain mandatory for both channels, so nothing is published that failed verification.

## What a red `Build and Release` run means now

Every failure is a real problem. There is no longer an "expected red run" state.

| Job | Meaning when it fails |
|---|---|
| `changes` | commit classification failed |
| `check-qualification` | channel unsupported/unparsable, qualification manifest invalid or missing, release not eligible for the exact SHA, or proxy upstream refs need requalification |
| `collect` | asset download, checksum or release-asset contract failed |
| `release` | tag collision / immutability guard failed, or asset upload failed |

## Rules

- Do **not** bypass or comment out the qualification, proxy-upstream or tag-immutability checks.
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
