#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
channel_file="$ROOT/release-channel.json"
workflow="$ROOT/.github/workflows/release.yml"

python3 -B "$ROOT/scripts/package_identity.py" >/dev/null

# Read the actual channel file instead of only grepping workflow text.
python3 - "$channel_file" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
assert doc.get("schemaVersion") == 1, "release-channel schemaVersion must be 1"
assert doc.get("channel") in {"prerelease", "stable"}, "unexpected channel"
assert isinstance(doc.get("reason"), str) and doc["reason"].strip(), "reason must be non-empty"
print("channel file: %s (%s)" % (doc["channel"], doc["reason"]))
PY

# The workflow must consume the same file, and both channels must promote
# automatically: `stable` publishes a non-prerelease latest Release while
# `prerelease` publishes the development line. The exact-SHA qualification
# manifest and the immutable tag guard stay mandatory either way.
grep -Fq 'release-channel.json' "$workflow"
grep -Fq 'case "$channel" in' "$workflow"
grep -Fq 'prerelease|stable) ;;' "$workflow"
grep -Fq "prerelease: \${{ needs.check-qualification.outputs.channel != 'stable' }}" "$workflow"
grep -Fq "make_latest: \${{ needs.check-qualification.outputs.channel == 'stable' }}" "$workflow"

# The retired manual Stable Gate must not creep back in unnoticed.
if grep -Fq 'automatic promotion is disabled' "$workflow"; then
  echo 'release.yml still carries the retired manual Stable Gate' >&2
  exit 1
fi
echo 'Validated channel file and automatic promotion policy'
