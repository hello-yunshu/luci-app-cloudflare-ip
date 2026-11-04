# sync-rill real-path drill evidence

Date: 2026-11-04/05 (Asia/Shanghai)

## What was run

- Temporary clone of `main` (not the release worktree).
- `contracts/rill-runtime.json`: one trailing blank line only (semantically identical JSON).
- Script: `rill-openwrt-packages/scripts/open_sync_pr.py` (real GitHub, real `gh`, real git push).
- Command arguments: `--base main --prefix automation/rill-qualified-drill --qualification-workflow ci.yml`.

## Results

| Item | Value |
|---|---|
| Branch | `automation/rill-qualified-drill-6c05f995648e7cabcd71` |
| Branch push | success |
| PR | #26, created, then closed unmerged |
| PR head | `9e9526120baf1f1066ab67aab23b25e9d7855717` |
| push CI | `41929387139` failure (only `evidence-manifest`) |
| pull_request CI | `41929395955` failure (only `evidence-manifest`) |
| workflow_dispatch CI | `41929533620` failure (only `evidence-manifest`) |
| Other jobs | all success (host, legacy, rpc, package, migration, i18n, rootfs, etc.) |

## Failure cause

```text
Stable review rejected: candidate tag is already occupied by different content
```

`prepare-stable-review.py` compares the candidate against tag `v2.6.0-8`. The drill changed the contract bytes, so the immutable tag guard rejected it by design. This is not an automation-path failure and not a fixture/CI bug.

## Cleanup

- PR #26 closed with an explanatory comment.
- Remote branch deleted.
- `main`, the Runtime pin, tags and Releases untouched.

## Conclusion

Real path verified for: branch push, PR creation, CI auto-trigger, explicit `workflow_dispatch`. No green CI contract-change candidate was produced because `v2.6.0-8` is immutable; a green drill would require a new candidate version/tag and separate authorization.
