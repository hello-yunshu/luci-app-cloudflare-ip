# Offline package preflight

Collect the qualification manifest and public IPK/APK from one exact CI run and attempt. Use `scripts/download-qualification-artifact.py` to check the source workflow head SHA and select attempt-scoped artifact names. Keep the downloaded metadata and migration details. Put only the two public package files in a separate release directory.

Run against the exact tested commit recorded in the manifest:

```sh
python3 scripts/release-preflight.py qualification.json release \
  --commit TESTED_COMMIT --run-id RUN_ID --run-attempt ATTEMPT \
  --apk-bin /absolute/path/to/local/apk --output preflight-receipt.json
```

The supplied apk tool must be available locally. An offline Docker adapter must use an already present image, `--pull never`, `--network none`, and a read-only package mount. The command does not download packages or create tags, Releases, feeds, or uploads. It rejects an existing receipt path so a failed rerun cannot leave an older receipt looking current.

The same strict qualification and actual metadata/byte validator used by release collection checks required jobs, SHA/run/attempt, Runtime pins, generic migration matrices, public package identity, size and SHA-256. A successful receipt records the manifest and package digests. Missing or modified package bytes and mismatched provenance fail without a success receipt.

A PR workflow can test a merge commit distinct from its head SHA. Preserve both identities: the run API identifies its source head; qualification records the actual tested commit. Prove tree equality explicitly when using that result for the head. A later source change requires fresh qualification. Preflight does not complete device acceptance or authorize publication. Migration tests with fixture dependencies and offline package roots do not prove online init/procd behavior.

## Verified checkpoint

Run 39000051779 attempt 1, PR head `07802d4ce5c26c4456aba51f5caef0e9bba1b455`, tested commit `229363fb1c900df6b484a5246645395ec628b689`. Both trees are `04d32482234e8b388775f284cd94e2018fb93ec1`. All hosted CI jobs passed. Downloaded IPK/APK bytes passed local preflight using a network-disabled, no-pull APK metadata adapter. Wrong attempt and one-byte modification of a copied actual IPK were rejected without a receipt. Receipt: `docs/audits/g4-g5-evidence/offline-preflight-39000051779.json`.

All ten migration scenarios retain installed DB snapshots. The four controlled user files (UCI with custom URL, backup, history, cron) have matching before/final hashes. This checkpoint covers these tested paths; broader upgrade/uninstall, lifecycle, negative migration and G5 requirements remain open.
