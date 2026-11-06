#!/usr/bin/env bash
# Refuse to reuse an existing release tag for a different commit. Called by
# .github/workflows/release.yml before assets are uploaded; tested against real
# temporary git repositories.
set -euo pipefail

tag="${1:?usage: guard-release-tag.sh <tag> <expected-commit>}"
expected="$(git rev-parse "${2:?expected commit required}^{commit}")"
ref="refs/tags/${tag}"

if git show-ref --verify --quiet "$ref"; then
	tag_sha="$(git rev-parse "${ref}^{commit}")"
	if [ "$tag_sha" != "$expected" ]; then
		echo "immutable tag collision: $tag points to $tag_sha, expected $expected" >&2
		exit 1
	fi
	echo "tag $tag already exists at $expected"
else
	echo "tag $tag is new"
fi
