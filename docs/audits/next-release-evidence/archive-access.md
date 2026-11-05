# Historical archive access — verified from a clean clone

Date: 2026-11-05. The original `phase-b/next-release-fixes` pack (~85 MiB) and a
28 MiB single-branch push were both rejected by GitHub HTTPS. The four archives
were uploaded with the GitHub Git Data API as separate branches on top of
`origin/main` (`8257a3d`).

| Branch | Path | Tree SHA |
|---|---|---|
| `evidence/ui-refinement-archive` | `docs/audits/next-release-evidence/ui-refinement-7c13b1d` | `fb92ee260fcffd298bf3a92cc2aefed29a4ff566` |
| `evidence/ui-skill-audit-archive` | `docs/audits/next-release-evidence/ui-skill-audit` | `e0096eb8d19e92bce9765651c0eace24caa59ac8` |
| `evidence/visual-phase-b-archive` | `docs/audits/next-release-evidence/visual-phase-b` | `f7e706dc744a7f92d7dd45dad2a2bbf756ada6ce` |
| `evidence/visual-phase-c-archive` | `docs/audits/next-release-evidence/visual-phase-c` | `f620e14d70088e56309d82c2070941781adf5afd` |

Verification performed in a fresh clone:

```text
$ git clone --no-checkout --depth 1 https://github.com/hello-yunshu/luci-app-cloudflare-ip.git /tmp/cfip-clone
$ cd /tmp/cfip-clone
$ git fetch --depth 1 origin evidence/ui-refinement-archive
$ git rev-parse FETCH_HEAD:docs/audits/next-release-evidence/ui-refinement-7c13b1d
fb92ee260fcffd298bf3a92cc2aefed29a4ff566
...
evidence/ui-refinement-archive fb92ee260fcffd298bf3a92cc2aefed29a4ff566
evidence/ui-skill-audit-archive e0096eb8d19e92bce9765651c0eace24caa59ac8
evidence/visual-phase-b-archive f7e706dc744a7f92d7dd45dad2a2bbf756ada6ce
evidence/visual-phase-c-archive f620e14d70088e56309d82c2070941781adf5afd
```

Each branch also contains `docs/audits/next-release-evidence/archive-manifest.md`
with the same tree SHA, so a reviewer can compare without the original worktree.

These archives remain historical process evidence, not release evidence.
