#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_EVIDENCE_FILE="$TMP/rill-evidence.json"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"; source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/candidate-rill.sh"
printf '%s\n' '{broken' >"$CFIP_RILL_EVIDENCE_FILE"
printf '%s\n' '{"decisionId":"corrupt-evidence","requestedMode":"shadow","effectiveMode":"shadow","nativeOrder":["1.1.1.1"],"rillOrder":["2.2.2.2"],"authorityActionId":"1.1.1.1","nativeRillTop1Agreement":false,"generation":2,"confidenceReasons":["native_authority"]}' >"$TMP/decision.json"
printf '%s\n' '{"reward":0.6,"nativeCounterfactualReward":0.5,"rillShadowReward":0.6,"rewardDelta":0.1,"comparison":"win"}' >"$TMP/outcome.json"
cfip_rill_record_evidence "$TMP/decision.json" "$TMP/outcome.json" '{}'
test "$(jq 'length' "$CFIP_RILL_EVIDENCE_FILE")" = 1
test -n "$(find "$TMP" -name 'rill-evidence.json.quarantine.*' -type f -print -quit)"
echo 'Corrupt evidence is quarantined before recording new evidence'
