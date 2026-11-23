#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
workflow="$ROOT/.github/workflows/release.yml"
grep -Fq 'release-channel.json' "$workflow"
grep -Fq 'prerelease|stable) ;;' "$workflow"
grep -Fq "prerelease: \${{ needs.check-qualification.outputs.channel != 'stable' }}" "$workflow"
grep -Fq "make_latest: \${{ needs.check-qualification.outputs.channel == 'stable' }}" "$workflow"
echo 'release workflow channel contract passed'
