# LOCAL_REPRODUCTION — 8 → 9 → 10 upgrade while GitHub asset delivery is down

**This is local reproduction evidence only. It does NOT replace the CI drill /
migration gate, which was still red when this was produced (see
`incident-20261108-github-asset-delivery.md`). No tag or Release may be created
until the CI jobs that download historical release assets pass on the exact
release SHA.**

Purpose: the GitHub asset CDN returned `504` for `v2.6.0-2`, `v2.6.0-8` and
`v2.6.0-9` packages, so `Real package drill` / `Real package migration` could
not run in CI. The two packages the drill needs already existed locally and were
verified byte-for-byte against GitHub's published digests, so the same upgrade
path was exercised locally instead of leaving the chain idle.

## Inputs

| Input | File | SHA-256 | Provenance |
|---|---|---|---|
| r8 apk | `luci-app-cloudflare-ip-2.6.0-r8.apk` | `a40cc8599f0c60fafce5279634ab30d0070f5850ec1939d895bffd88ccd5b935` | cached local copy; equals the `sha256:` digest reported by `api.github.com` for release `v2.6.0-8` |
| r8 ipk | `luci-app-cloudflare-ip_2.6.0-r8_all.ipk` | `1a3bc3cc8db4ac1a2b620197212b63463889a137c94d92e4467ea499494cbdeb` | same |
| r9 apk | `luci-app-cloudflare-ip-2.6.0-r9.apk` | `65d0be85c30532e382dc1e4fd6e26891df5a64a8af71a5fc55c1d72ddb33a62d` | same, release `v2.6.0-9` |
| r9 ipk | `luci-app-cloudflare-ip_2.6.0-r9_all.ipk` | `12fdc8931be9ac899d551872d4ed4060d065d4cde2865a71c7545dc2ff2822ad` | same |
| r10 apk | `luci-app-cloudflare-ip-2.6.0-r10.apk` | `2e98a079f96246c0ff8b0f21255be2e9dd7655ce276856e576d06e4b5fbfa51d` | CI artifact `luci-app-cloudflare-ip-apk-v25.12.5-run-42464318882-attempt-3`, built from `bb232ea…` |
| r10 ipk | `luci-app-cloudflare-ip_2.6.0-r10_all.ipk` | `34f1874892d6bbca26862060561cfdb344543559ffae060256f455cdb56c097a` | CI artifact `luci-app-cloudflare-ip-ipk-v24.10.8-run-42464318882-attempt-3`, built from `bb232ea…` |

The r10 metadata files report `packageVersion: 2.6.0-r10`, `release: 10`.

## Environment

- Docker, privileged disposable containers, platform `linux/amd64`
- IPK: `openwrt/rootfs:x86_64-24.10.8`
- APK: `openwrt/rootfs:x86_64-25.12.5`
- Run on 2026-11-08 on the maintainer workstation, no device was touched
- Raw outputs: `~/.cache/cfip-audit/local-repro/20261108/{ipk,apk}-{r8r9,chain-8-9-10}`

## Commands (verbatim)

```bash
# same drill script the CI uses, r8 -> r9 (fresh install, upgrade, rollback, ENOSPC, power loss)
bash tests/r4-container-drill.sh --kind ipk --image openwrt/rootfs:x86_64-24.10.8 \
  --r8 ~/.cache/cfip-audit/release/luci-app-cloudflare-ip_2.6.0-r8_all.ipk \
  --r9 ~/.cache/cfip-audit/release/luci-app-cloudflare-ip_2.6.0-r9_all.ipk \
  --out ~/.cache/cfip-audit/local-repro/20261108/ipk-r8r9

bash tests/r4-container-drill.sh --kind apk --image openwrt/rootfs:x86_64-25.12.5 \
  --r8 ~/.cache/cfip-audit/release/luci-app-cloudflare-ip-2.6.0-r8.apk \
  --r9 ~/.cache/cfip-audit/release/luci-app-cloudflare-ip-2.6.0-r9.apk \
  --out ~/.cache/cfip-audit/local-repro/20261108/apk-r8r9

# chained 8 -> 9 -> 10 on one container (local script, same install and verification primitives)
bash /tmp/cfip-local-upgrade-chain.sh --kind ipk --image openwrt/rootfs:x86_64-24.10.8 \
  --r8  ~/.cache/cfip-audit/release/luci-app-cloudflare-ip_2.6.0-r8_all.ipk \
  --r9  ~/.cache/cfip-audit/release/luci-app-cloudflare-ip_2.6.0-r9_all.ipk \
  --r10 ~/.cache/cfip-audit/release/r10-ipk/luci-app-cloudflare-ip_2.6.0-r10_all.ipk \
  --out ~/.cache/cfip-audit/local-repro/20261108/ipk-chain-8-9-10

bash /tmp/cfip-local-upgrade-chain.sh --kind apk --image openwrt/rootfs:x86_64-25.12.5 \
  --r8  ~/.cache/cfip-audit/release/luci-app-cloudflare-ip-2.6.0-r8.apk \
  --r9  ~/.cache/cfip-audit/release/luci-app-cloudflare-ip-2.6.0-r9.apk \
  --r10 ~/.cache/cfip-audit/release/r10-apk/luci-app-cloudflare-ip-2.6.0-r10.apk \
  --out ~/.cache/cfip-audit/local-repro/20261108/apk-chain-8-9-10
```

## Results

`tests/r4-container-drill.sh` (unchanged, the CI script), 7 checks per format:

| Check | IPK (24.10.8) | APK (25.12.5) |
|---|---|---|
| fresh install r9, `--status` works | PASS | PASS |
| r8→r9, config hash and values preserved | PASS | PASS |
| rollback to r8, config preserved | PASS | PASS |
| ENOSPC prevents a valid install | PASS (`rc=0`, `payload_broken`) | PASS (`rc=1`, `payload_broken`) |
| ENOSPC recovery reinstall reaches r9 | PASS | PASS |
| power-loss leaves r8 intact with config | PASS | PASS |
| power-loss retry reaches r9, config preserved | PASS | PASS |

Chained 8→9→10 upgrade:

| Step | IPK | APK |
|---|---|---|
| r8 seed installed | PASS | PASS |
| r8→r9, config hash and values preserved, `--status` r9 | PASS | PASS |
| r9→r10, config hash and values preserved, `--status` r10 | PASS | PASS |

Config used by the check: `cf_ip.main.enabled=1`, `cf_ip.main.ip_count=5`,
`cf_ip.passwall.target_domain=example.com`; the `/etc/config/cf_ip` SHA-256 was
unchanged across both upgrade hops in both formats.

## Boundary — what this does not cover

- Not a CI gate. `Real package drill`, `Real package migration`,
  `real-cfst-smoke`, `evidence-manifest` and `qualification-guard` were still
  red/blocked on `bb232ea` because GitHub returned 504 for assets. Once the
  asset path recovers, the **whole workflow must be rerun** (not `--failed`,
  because artifact names embed `run_attempt`) and must pass before any tag.
- Containers, not a device: no physical power cut, no real touch input, no
  PassWall network, no OpenClash controller matrix.
- The chained script installs the base package only; the `rill` addon package is
  not part of the 8→9→10 chain (it is covered by the CI drill/migration jobs).
- The local chain script is a reproduction aid, not a repository test; it lives
  in `/tmp` and is not committed.
