# Audit P1/P2 remediation evidence — 2026-11-06

Base commit at audit start: `16c68fd` (`origin/main`). Branch:
`fix/audit-p1-p2-20261106`. No version, tag, Release or channel change.

These files are raw command output; no result was edited. Local host is macOS
arm64, so every container run used `--platform linux/amd64` (emulated). CI runs
the same drill script natively on amd64.

## P1-1 — R4 real container drills

Command shape:

```sh
bash tests/r4-container-drill.sh --kind ipk|apk --image IMG --r8 FILE --r9 FILE --out DIR
```

The drill covers fresh r9 install (`--status`), r8→r9 config-preserving upgrade,
forced r9→r8 rollback, ENOSPC install/recovery, and power-loss (`docker kill`
during install) plus retry.

| Run | Image | Result | File |
|---|---|---|---|
| IPK (CI image) | `openwrt/rootfs:x86_64-24.10.8` | 7/7 PASS | `p1-1-ipk-stock-summary.txt` |
| IPK (clean base) | local clean 24.10.8 base | 7/7 PASS | `p1-1-ipk-cleanbase-summary.txt` |
| APK (CI image) | `openwrt/rootfs:x86_64-25.12.5` | 7/7 PASS | `p1-1-apk-summary.txt` |

The clean-base IPK run exists because a local image carried unowned package
files; removing them produced a rootfs equivalent to the stock image. The stock
run is the primary evidence because CI uses that image directly.

ENOSPC details:

- Stock IPK: exit code 0 while opkg failed to close `/usr/lib/opkg/status`
  (`No space left on device`) and left a zero-byte payload; recorded as
  `payload_broken`. See `p1-1-ipk-stock-enospc*`.
- APK: exit code 1, `failed to extract usr/bin/cf-ip-auto: No space left on
  device`, payload broken. See `p1-1-apk-enospc*`.

## P1-2 — preinst/postinst behaviour

`bash tests/package-lifecycle.sh` extracts the hooks from the Makefile exactly as
the package manager receives them and runs the online, failure and offline
branches against a disposable fixture root. Output:
`p1-2-package-lifecycle.txt`. It proves that migration/enable/status failures are
fatal, offline `IPKG_INSTROOT` installs skip the lifecycle, and the hook never
writes global LuCI language state.

## P1-3 — startup race

`tests/startup-race-container.sh` inside a disposable privileged 24.10.8 root,
mounted from the worktree; that wrapper installs the dependencies and runs
`tests/startup-race.sh`. Output: `p1-3-startup-race.txt`. It proves the init
script submits only one background job and that `startup_delay` runs before the
writer lock is taken, so a manual run can acquire the lock immediately.

## P2 — release gates and phase-f

`p2-release-gates.txt` is the output of `release-channel-contract.sh`,
`immutable-tag-contract.sh` and `release-tag-immutability.sh`. The channel gate
now parses `release-channel.json`; the tag gates exercise the real guard against
temporary git repositories, including a conflicting-tag negative case.

`p2-phasef-verify.json` is `verify.cjs` output: 51 points, 17 focus-ring
assertions, 48 unique zoom screenshots, 0 failures at the evidence SHA
`ffa73f6`. `p2-phasef-ui-tree-diff.txt` records that the LuCI source tree is
identical between `ffa73f6` and `16c68fd`; the baseline is the evidence capture
SHA, not a claim about current `main`. Regenerating the visual evidence is PR
#33 work and was out of scope.
