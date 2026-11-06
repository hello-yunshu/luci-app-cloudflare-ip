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

# The workflow must consume the same file, and a non-prerelease channel must
# stop automatic promotion rather than silently publishing.
grep -Fq 'release-channel.json' "$workflow"
grep -Fq "if [[ \"\$channel\" != prerelease ]]" "$workflow"
grep -Fq 'automatic promotion is disabled' "$workflow"
grep -Fq 'prerelease: true' "$workflow"
grep -Fq 'make_latest: false' "$workflow"
echo 'Validated channel file and explicit Stable promotion boundary'
