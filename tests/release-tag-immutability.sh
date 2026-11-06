#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
workflow="$ROOT/.github/workflows/release.yml"
guard="$ROOT/scripts/guard-release-tag.sh"

grep -Eq 'Guard immutable release tag before asset upload' "$workflow"
grep -Eq 'scripts/guard-release-tag.sh' "$workflow"
grep -Eq 'Verify published tag identity' "$workflow"

# Exercise the same guard against a real repository and a conflicting tag.
repo="$(mktemp -d)"
trap 'rm -rf "$repo"' EXIT
git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test
git -C "$repo" commit -q --allow-empty -m base
base="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" tag v2.9.9 "$base"
git -C "$repo" commit -q --allow-empty -m next
next="$(git -C "$repo" rev-parse HEAD)"
if (cd "$repo" && bash "$guard" v2.9.9 "$next" >"$repo/out" 2>&1); then
	echo 'FAIL: immutable tag guard accepted a collision' >&2
	exit 1
fi
grep -Fq 'immutable tag collision' "$repo/out"

# All repository release tags must still resolve to a commit.
test "$(git -C "$ROOT" tag -l 'v2.*' | wc -l | tr -d ' ')" -gt 0
while IFS= read -r tag; do
	test -n "$(git -C "$ROOT" rev-parse "$tag^{commit}")"
done < <(git -C "$ROOT" tag -l 'v2.*')

echo 'Release workflow and guard enforce immutable tags'
