#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 -B "$ROOT/scripts/package_identity.py"
python3 -B "$ROOT/tests/package-identity-contract.py"
echo 'Package identity derives from the source authority'
