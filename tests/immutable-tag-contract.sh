#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
workflow="$ROOT/.github/workflows/release.yml"
guard="$ROOT/scripts/guard-release-tag.sh"

grep -Fq 'scripts/guard-release-tag.sh' "$workflow"

repo="$(mktemp -d)"
trap 'rm -rf "$repo"' EXIT
git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test
git -C "$repo" commit -q --allow-empty -m first
first="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" tag v2.0.0 "$first"
git -C "$repo" commit -q --allow-empty -m second
second="$(git -C "$repo" rev-parse HEAD)"

git -C "$repo" rev-parse 'v2.0.0^{commit}' >"$repo/first"
# Same commit: allowed.
(cd "$repo" && bash "$guard" v2.0.0 "$first" >/dev/null)
# Different commit: rejected with a concrete collision diagnostic.
if (cd "$repo" && bash "$guard" v2.0.0 "$second" >"$repo/out" 2>&1); then
	echo 'FAIL: guard accepted a conflicting tag' >&2
	exit 1
fi
grep -Fq 'immutable tag collision: v2.0.0' "$repo/out"
# New tag for the second commit: allowed.
(cd "$repo" && bash "$guard" v2.1.0 "$second" >/dev/null)
echo 'Real tag guard rejects collisions and accepts new tags'
