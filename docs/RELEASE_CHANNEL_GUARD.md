# Release channel guard — expected behavior

`release-channel.json` is the single source of truth for the publication channel. `release.yml` only supports the automatic **prerelease** path on `main`; any other channel is refused before collection or publication.

## What a guard failure looks like

A red `Build and Release` run on `main` with these job states is **expected**, not a packaging failure:

| Job | State | Meaning |
|---|---|---|
| `changes` | success | classified the commit as release-relevant |
| `check-qualification` | failure | channel is `stable`; automatic promotion refused |
| `collect` | skipped | no assets were collected |
| `release` | skipped | no tag/Release was created |

The log contains exactly:

```text
stable channel requires an explicit Stable Gate; automatic promotion is disabled
```

Example: run `41904752070` (2026-11-04, `main` after PR #25) failed in `check-qualification` for this reason; `collect` and `release` were skipped, and no tag or Release was created.

## What is NOT a guard failure

These indicate a real problem and must be investigated:

- `changes` job failure (commit classification);
- failure **after** the channel check: qualification manifest/asset validation, checksum, tag collision, asset upload;
- a `release` job that ran or partially ran;
- a new tag or Release with unexpected assets;
- `stable channel` message in a run where `release-channel.json` is `prerelease`.

## Rules

- Do **not** bypass, delete or comment out the guard.
- Do **not** change `release-channel.json` to make an automatic run pass.
- A stable release requires a separate explicit Stable Gate and user authorization; see [STABLE_GATE.md](STABLE_GATE.md).
- A manual prerelease uses `gh release create --prerelease` with assets from the same exact-SHA run/attempt and does not change the channel file.
