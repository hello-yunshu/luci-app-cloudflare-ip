# GitHub release-asset delivery incident — 2026-11-08

Status at writing: **ongoing / intermittent.** It blocks every CI job that must
download historical release assets (`v2.6.0-2`, `v2.6.0-8`, `v2.6.0-9`), not
this repository's code. No tag or Release may be created while these jobs are
red (see `VERDICT-20261108.md`).

## 1. CI-side failures (run `42464318882`, commit `bb232ea`, attempt 1)

All timestamps are UTC from the job logs.

| Time | Job | Observation |
|---|---|---|
| 08:46:06 | run created | `CI` on PR #47, head `bb232eaaeacf7cb4310193420f05d30d69be6bdd` |
| 08:46:16 | `Real package drill (apk OpenWrt v25.12.5)` | `curl -fsSL --retry 3 .../releases/download/$tag/$name` and `.../SHA256SUMS` |
| 08:46:27–08:46:34 | same job | four `curl: (22) The requested URL returned error: 504` |
| 08:46:37 | `Real package drill (ipk OpenWrt v24.10.8)` | same download step |
| 08:46:48–08:46:55 | same job | four `curl: (22) ... 504` |
| 08:46:40 | `workflow-lint` | `Downloading .../rhysd/actionlint/releases/download/v1.7.12/...tar.gz` → `gzip: stdin: not in gzip format` (server returned an error page instead of the tarball) |
| 09:09:24–09:09:26 | `Real package migration (ipk/apk)` | downloads `v2.6.0-2/sha256sums.txt`, `v2.6.0-8/SHA256SUMS`, `v2.6.0-8/<r8 package>` |
| 09:09:45–09:09:52 | both migration jobs | four `curl: (22) ... 504` per job |
| after | `evidence-manifest`, `qualification-guard` | `qualification artifact rejected: missing, duplicate or expired exact-attempt artifact` — downstream consequence of the drill/migration jobs producing no artifact |

The same failure also hit run `42464302969` (push of the same commit), i.e. it
is independent of the PR event type.

### Attempt 3 (whole-workflow rerun, 2026-11-08T09:33Z)

`workflow-lint` recovered (`actionlint` download succeeded), but every job that
touches release assets still failed, and `real-cfst-smoke` joined them:

| Time (UTC) | Job | Observation |
|---|---|---|
| 09:34:12–09:34:19 | `Real package drill (apk OpenWrt v25.12.5)` | four `curl: (22) ... 504`, exit 22, `No files were found ... r4-apk/` |
| 09:34:07–09:34:14 | `real-cfst-smoke` | four `curl: (22) ... 504` while downloading the CFST binary |
| 09:34:2x | `Real package drill (ipk OpenWrt v24.10.8)` | same 504 pattern |
| after | `evidence-manifest`, `qualification-guard`, drill/migration | fail or blocked as before; no r10 qualification artifact is produced |

These runner-side timestamps coincide with the local probes below
(09:34Z = 17:34 CST), i.e. the same outage was observed independently from a
GitHub runner and from a home connection.

### Attempt 4 (whole-workflow rerun, 2026-11-08T10:36Z)

Started while the asset path was still flapping; the failure mode broadened
from 504 to 503 and connection drops:

| Time (UTC) | Job | Observation |
|---|---|---|
| 10:38:47–10:39:25 | `Real package drill (ipk OpenWrt v24.10.8)` | `curl: (22) ... 503` twice, then `curl: (56) Connection died, tried 5 times before giving up`; no artifact |
| 10:39:42 | same | `No files were found ... r4-ipk/` |
| 10:43:41–10:44:55 | `openwrt-package (v25.12.5, apk)` | `curl: (22) ... 503`, then three `504`, then `404` while fetching build inputs |
| 10:42:48–10:44:26 | `openwrt-package (v25.12.0, apk)` | `curl: (16) Error in the HTTP2 framing layer`, then `404` |
| 10:56 | `qualification-guard` | fails because no exact-attempt artifact exists |

What **did** pass in this attempt: `Real package drill (apk OpenWrt v25.12.5)`,
`real-cfst-smoke`, `workflow-lint` and every non-network job. So the outage was
narrowing, not code-related.

### Recovery window (basis for attempt 5)

| Local time (CST) | Probe result |
|---|---|
| 18:20:38 | `v2.6.0-8/SHA256SUMS` 200 (208 bytes) — first success |
| 18:25–18:34 | flapping again: 504, then connection timeouts (`000`), one 200 |
| 18:43:43 | `v2.6.0-8/…-r8_all.ipk` 200 (182736 bytes) |
| 18:44:13 | `v2.6.0-2/…-r2_all.ipk` 302 → 200 |
| 18:44:34 / 18:44:40 | `v2.6.0-8/SHA256SUMS`, `v2.6.0-2/sha256sums.txt` 200 |
| 18:58:58–18:59:08 | `downloads.openwrt.org` 25.12.5 / 24.10.8 / 25.12.0 and the r8 IPK all 200 |

Attempt 5 (whole-workflow rerun) was started at 18:59 CST on the strength of
that sustained window.

### Attempt 5 (whole-workflow rerun, 2026-11-08T11:00Z)

The drill/migration paths recovered, but the **build** jobs became the blockers:

| Time (UTC) | Job | Observation |
|---|---|---|
| ~11:05–11:08 | `openwrt-package (v24.10.5, ipk)` | build-input download `404` / `Download failed`; `ERROR: package/rill-runtime failed to build` |
| ~11:07–11:08 | `openwrt-package (v24.10.8, ipk)` | `curl: (22) ... 503/504` while fetching build inputs, including `https://github.com/hello-yunshu/rill-ml/archive/refs/tags/v1.5.6.tar.gz`; OpenWrt mirror fallbacks then return `404` (the third-party tarball is not mirrored) |
| ~11:05–11:08 | `openwrt-package (v25.12.0, apk)` | same rill-ml source fetch failure during the Rust build |
| — | `Real package drill (apk)` / `Real package drill (ipk)` | **success** |
| — | `real-cfst-smoke`, `workflow-lint`, all non-network jobs | **success** |
| 11:20 | `qualification-guard` | fails: no exact-attempt artifact |

The rill-ml source is fetched from GitHub's archive path, so the build jobs
depend on the same upstream as the release-asset downloads. On 2026-11-08 at
19:24 CST (11:24Z) that URL returned `200`, and every required input was verified
green before attempt 6:

| Input | Status at 19:25 CST |
|---|---|
| `v2.6.0-8/SHA256SUMS` | 200 |
| `v2.6.0-8/…-r8.apk` | 200 |
| `v2.6.0-8/…-r8_all.ipk` | 200 |
| `v2.6.0-2/sha256sums.txt` | 200 |
| `rill-ml/archive/refs/tags/v1.5.6.tar.gz` | 200 |

Attempt 6 (whole-workflow rerun) started at 19:26 CST.

### Attempt 6 (2026-11-08T11:26Z)

Everything network-heavy passed — both package drills, all four package builds,
migration and the remaining contract jobs — except `rootfs-contract`:

- `rootfs-contract` exited 1 at 11:26:22Z with no output from its container
  script; the step's `opkg update` output is redirected, so the visible trace is
  only `Process completed with exit code 1`. The OpenWrt package index was
  reachable from the maintainer side at the same time (`Packages.gz` 200).
- `evidence-manifest` and `qualification-guard` then failed with the explicit
  cause: `qualification jobs rejected: required qualification job
  rootfs-contract did not succeed` — a cascade, not a missing artifact.

Attempt 7 started at 19:59 CST.

### Attempt 7 (2026-11-08T11:59Z)

Two unrelated flakes, both jobs that had passed in earlier attempts:

| Time (UTC) | Job | Observation |
|---|---|---|
| 12:01:06 | `workflow-lint` | `gzip: stdin: not in gzip format` while installing actionlint — the download endpoint returned an error page again |
| 12:13:08 | `openwrt-package (v25.12.5, apk)` | step exit `2` right after `package/rill-runtime/compile` reported success (`Serial diagnostic exit code ... : 0`); no error line was emitted. The same job produced the r10 apk in attempt 3 and passed in attempt 6 |

Direct checks at 20:22 CST: actionlint `v1.7.12` tarball 200, r8 IPK 200, rill-ml
archive 200. Attempt 8 started at 20:23 CST.

### Why a partial rerun cannot be used

Artifact names embed `${{ github.run_attempt }}`, and `evidence-manifest`
downloads `qualification-*`/package artifacts with
`--run-attempt "$GITHUB_RUN_ATTEMPT"`. Rerunning only the failed jobs moves
those jobs to a new attempt while the artifact-producing jobs stay on the old
attempt, so the downstream lookup is guaranteed to miss. Every retry here is a
whole-workflow rerun for that reason (verified on attempts 1→2).

### API fallback (not used by CI)

`api.github.com/repos/<repo>/releases/assets/<asset-id>` with
`Accept: application/octet-stream` returned **200** for the very object whose
`releases/download/...` URL returned 504. The blob backend was healthy; the
web asset-redirect path was not. CI keeps using the web URLs, so this is
recorded only as a diagnostic, not as a workaround.

## 2. Local direct-connection probes (home network, Asia/Shanghai)

The GitHub **control plane** answered normally while the **asset download
path** returned 504.

| Local time (CST) | URL | HTTP | Bytes |
|---|---|---|---|
| 17:31:55 | `.../releases/download/v2.6.0-9/SHA256SUMS` | 302 | 0 |
| 17:31:55 | `.../releases/download/v2.6.0-9/SHA256SUMS` (followed) | 200 | 208 |
| 17:31:55 | `https://api.github.com/repos/.../releases/tags/v2.6.0-9` | 200 | 11311 |
| 17:31:55 | `https://api.github.com/rate_limit` | 200 | 678 |
| 17:34:49–17:35:04 | `.../releases/download/v2.6.0-9/SHA256SUMS` ×5 | 504 ×5 | 92 each |
| 17:35:40 | `.../releases/download/v2.6.0-2/sha256sums.txt` | 504 | 92 |
| 17:35:54 | `.../releases/download/v2.6.0-2/luci-app-cloudflare-ip-2.6.0-r2.apk` | 504 | 92 |
| 17:36:09 | `.../releases/download/v2.6.0-8/SHA256SUMS` | 504 | 92 |
| 17:36:23 | `.../releases/download/v2.6.0-8/luci-app-cloudflare-ip-2.6.0-r8.apk` | 504 | 92 |
| 17:36:37 | `.../releases/download/v2.6.0-8/luci-app-cloudflare-ip_2.6.0-r8_all.ipk` | 504 | 92 |
| 17:36:51 | `.../releases/download/v2.6.0-9/SHA256SUMS` | 504 | 92 |
| 17:37:08 | `.../releases/download/v2.6.0-9/luci-app-cloudflare-ip-2.6.0-r9.apk` | **200** | 182127 |
| 17:37:23 | `.../releases/download/v2.6.0-9/luci-app-cloudflare-ip_2.6.0-r9_all.ipk` | 504 | 92 |
| 17:37:36 | `.../releases/download/v2.6.0-9/qualification.json` | 504 | 92 |

The 92-byte body is the gateway error page itself:

```html
<html><body><h1>504 Gateway Time-out</h1>
The server didn't respond in time.
</body></html>
```

Interpretation:

- `api.github.com` (metadata, digests, rate limit) is healthy.
- `github.com/<owner>/<repo>/releases/download/...` (asset CDN) returns 504
  across **all** tags and both formats, per-object and intermittently — one
  object (`r9.apk`) succeeded while every other object failed seconds apart.
- The CI `--retry 3` budget is too small to ride out the outage.
- Nothing in the repository can cause or fix this; only GitHub can.
- `githubstatus.com` reported **"All Systems Operational"** with 0 incidents
  while these probes were failing (checked 2026-11-08 18:15 CST), so the status
  page does not cover the release-asset path. Trust the direct probe, not the
  status page.

## 3. Provenance check of local copies (no download needed)

GitHub's API reports `sha256:` digests per asset. Cached files match exactly:

| File | Cached SHA-256 | API digest |
|---|---|---|
| `luci-app-cloudflare-ip-2.6.0-r8.apk` | `a40cc8599f0c60fafce5279634ab30d0070f5850ec1939d895bffd88ccd5b935` | match |
| `luci-app-cloudflare-ip_2.6.0-r8_all.ipk` | `1a3bc3cc8db4ac1a2b620197212b63463889a137c94d92e4467ea499494cbdeb` | match |
| `luci-app-cloudflare-ip-2.6.0-r9.apk` | `65d0be85c30532e382dc1e4fd6e26891df5a64a8af71a5fc55c1d72ddb33a62d` | match |
| `luci-app-cloudflare-ip_2.6.0-r9_all.ipk` | `12fdc8931be9ac899d551872d4ed4060d065d4cde2865a71c7545dc2ff2822ad` | match |

These four files under `~/.cache/cfip-audit/release/` are therefore byte-identical
to the published `v2.6.0-8` / `v2.6.0-9` assets and may be used as
`LOCAL_REPRODUCTION` inputs. They do **not** substitute for the CI gate.

## 4. Retry procedure used

- Whole-workflow rerun (`gh run rerun <id>`), never `--failed`: artifact names
  embed `run_attempt`, so a partial rerun leaves successful jobs' artifacts on
  the old attempt and the downstream jobs look for names that no longer exist.
- Probe order: first `api.github.com` (control plane), then a known asset
  through `-L`; only when the asset path returns 200 is a rerun started.
- If a rerun fails again with 504, record the new timestamp and code here and
  stop; no tag, no Release.

## 5. What this does not affect

`openwrt-package` build jobs, which produce the r10 apk/ipk from the current
source, do not download historical release assets and succeeded in attempt 1.
Their bytes can be collected while the asset path is down; only the drill /
migration gate and the release tag remain blocked.

## 6. Attempt 8 — GREEN (recovery)

| Time (UTC) | Observation |
|---|---|
| 12:18 | whole-workflow rerun started after the asset probe returned `200` |
| 12:44:24 | run `42464318882` completed with `conclusion: success`, `run_attempt: 8` |
| after | artifacts present as `...-run-42464318882-attempt-8`, including `qualification-evidence-run-42464318882-attempt-8`; no drill / migration / cfst 5xx in the logs |

## 7. Closure

- PR head `bb232ea` merged to `main` as `cbc17a7e629ed0e7c96e62874f2976a5e2b6ac4a`.
  Merge tree equals the PR head tree (`3cddfd8d1b293fc4d481cb9922559a6b777635bb`),
  so the qualified bytes are the merged bytes.
- `main` push CI run `42481820841` (attempt `1`) completed `conclusion: success`
  at `2026-11-08T13:02:28Z` on `cbc17a7`. The drill, migration, `rootfs-contract`
  and `real-cfst-smoke` gates downloaded historical release assets successfully
  in CI — the formal gate was rerun, not substituted.
- Release `v2.6.0-10` was created from run `42481820841` / attempt `1` artifacts:
  ipk `f56e55267f311a5b47bc11a73c07c2d92de058921ee7211fb03af706742b9a98`,
  apk `4ba2dad6d4cd0689b22cbb263bca1b6359ed754b6fa98c20cd29b7e9a5c19ae8`.
  `SHA256SUMS` verified after download from the published Release.
- The local 8→9→10 drill in `local-reproduction-20261108.md` was a stopgap only;
  it is **not** the release gate. The CI rerun above is the formal gate.
- `Build and Release` run `42483033922` failed by design at the stable-channel
  guard (`stable channel requires an explicit Stable Gate; automatic promotion
  is disabled`); this is expected and unrelated to the asset outage. The
  Pre-release was published manually with `--prerelease`.
