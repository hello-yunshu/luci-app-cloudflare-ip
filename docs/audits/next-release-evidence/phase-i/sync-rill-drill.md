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

## Second real drill (green path, after the fix)

| Item | Value |
|---|---|
| Base | `phase-i-closeout` @ `b79ab8a` (contains the stable-review fix) |
| Branch | `automation/rill-qualified-drill-green-6c05f995648e7cabcd71` |
| PR | #28, created, then closed unmerged |
| PR head | `56cb1e5ad23d28edd4c86f11e307f5f94a923a4a` |
| push CI | `41936332364` success (20/20) |
| pull_request CI | `41936344450` success (20/20) |
| Cleanup | PR #28 closed, branch deleted, main/pin/tag untouched |

## Conclusion

Real path verified: branch push, PR creation, CI auto-trigger and explicit `workflow_dispatch`; the fixed gate now records an occupied tag instead of failing, so the second drill is fully green. No merge and no pin change.
