#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="${1:?release directory required}"
if [[ -n "${2:-}" ]]; then
  test "$2" = "$(python3 -B "$ROOT/scripts/package_identity.py" --field version)"
fi
python3 -B "$ROOT/scripts/check-package-assets.py" "$DIR" --release-dir
echo 'Real release packages, metadata and checksum set passed'
