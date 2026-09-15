#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_OPERATIONAL_STATE_FILE="$TMP/operational-health.json" CFIP_OPERATIONAL_HISTORY_FILE="$TMP/operational-history.json"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/operational-health.sh"

export CFIP_REUSE_ATTEMPTED=false CFIP_REUSE_FALLBACK_REASON= CFIP_PROBE_METRICS_FILE="$TMP/metrics.json"
printf '%s\n' '{"fallbackUsed":false,"expansionCount":0,"auditRun":false}' >"$CFIP_PROBE_METRICS_FILE"
for n in 1 2 3 4; do
    export CFIP_RUN_ID="healthy-$n" CFIP_LAST_RESULT=success
    cfip_operational_record_run
done
test "$(jq -r '.rolling.windowSize' "$CFIP_OPERATIONAL_STATE_FILE")" = 4
test "$(jq -r '.state' "$CFIP_OPERATIONAL_STATE_FILE")" = warning

printf '%s\n' '{"fallbackUsed":true,"expansionCount":0,"auditRun":false}' >"$CFIP_PROBE_METRICS_FILE"
export CFIP_RUN_ID=fallback-5 CFIP_LAST_RESULT=success
cfip_operational_record_run full-optimize-success fallback_evidence
test "$(jq -r '.rolling.windowSize' "$CFIP_OPERATIONAL_STATE_FILE")" = 5
test "$(jq -r '.rolling.sampleCounts.fallback' "$CFIP_OPERATIONAL_STATE_FILE")" = 5
test "$(jq -r '.rolling.fallbackRate' "$CFIP_OPERATIONAL_STATE_FILE")" = 0.2
test "$(jq -r '.state' "$CFIP_OPERATIONAL_STATE_FILE")" = healthy
test "$(jq -r '.lastEvent.name' "$CFIP_OPERATIONAL_STATE_FILE")" = full-optimize-success

echo 'Completed run immediately refreshes rolling Operational Health'
