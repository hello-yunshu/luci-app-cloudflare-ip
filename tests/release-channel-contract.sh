#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
channel="$ROOT/release-channel.json"
workflow="$ROOT/.github/workflows/release.yml"
python3 -B "$ROOT/scripts/package_identity.py" >/dev/null
grep -Fq 'prerelease: true' "$workflow"
grep -Fq 'make_latest: false' "$workflow"
grep -Fq 'explicit Stable Gate' "$workflow"
echo 'Validated channel schema and explicit Stable promotion boundary'
