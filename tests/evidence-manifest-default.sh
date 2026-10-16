#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
RESULTS='{"host-contract":{"result":"failure"}}' \
  GITHUB_SHA=0123456789012345678901234567890123456789 GITHUB_RUN_ID=123 \
  bash "$ROOT/tests/evidence-manifest.sh" "$TMP/manifest.json"
jq -e --arg expected "$(jq -er '.resolved.sourceArchiveSha256' \
  "$ROOT/contracts/rill-runtime.json")" '.releaseEligible==false and .rill=={} and .qualificationState=="incomplete" and .stableSourceArchiveSha256==$expected' "$TMP/manifest.json" >/dev/null
RESULTS='{"host-contract":{"result":"failure"}}' PACKAGE_MIGRATION='{"schemaVersion":1}' \
  GITHUB_SHA=0123456789012345678901234567890123456789 GITHUB_RUN_ID=124 \
  bash "$ROOT/tests/evidence-manifest.sh" "$TMP/manifest-with-migration.json"
jq -e '.packageMigration.schemaVersion==1 and .releaseEligible==false' "$TMP/manifest-with-migration.json" >/dev/null
echo 'Evidence manifest default JSON contract passed'
