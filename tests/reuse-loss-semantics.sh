#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP/status" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_LOG_FILE="$TMP/log"
export CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
mkdir -p "$CFIP_STATUS_DIR" "$CFIP_RUNTIME_DIR"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
CFIP_STATUS_FILE="$CFIP_STATUS_DIR/status.json"
CFIP_REUSE_STATE_FILE="$CFIP_STATUS_DIR/reuse-policy.json"
CFIP_REUSE_DECISION_FILE="$CFIP_RUNTIME_DIR/reuse-decision.json"
CFIP_SELECTED_FILE="$CFIP_RUNTIME_DIR/selected.json"
CFIP_OUTCOME_FILE="$CFIP_RUNTIME_DIR/outcome.json"
CFIP_MODE=passwall CFIP_TARGET_DOMAINS='one.example' CFIP_IP_TYPE=ipv4 CFIP_SPEEDTEST_PROTOCOL=tcp
CFIP_PASSWALL_TARGET_DOMAIN=one.example CFIP_OPENCLASH_CONFIG=/tmp/oc.yaml CFIP_OPENCLASH_TARGET_DOMAIN=one.example CFIP_OPENCLASH_TRANSPORT_FILTER=''
CFIP_REUSE_ENABLED=true CFIP_REUSE_MAX_FULL_OPTIMIZE_INTERVAL=86400 CFIP_REUSE_VALIDATION_TIMEOUT=5
CFIP_REUSE_LOSS_LIMIT=0.25 CFIP_REUSE_TTFB_LIMIT=3000 CFIP_REUSE_TOTAL_LIMIT=5000 CFIP_IP_COUNT=1
printf '%s\n' '{"best_ips":["104.16.1.1"],"last_result":"success"}' >"$CFIP_STATUS_FILE"
CFIP_HTTP_OK=true
cfip_probe_one() { jq -cn --arg ip "$1" --arg domain "$2" --arg family "$3" --argjson ok "$CFIP_HTTP_OK" '{ip:$ip,domain:$domain,family:$family,success:$ok,connectMs:10,tlsMs:10,ttfbMs:20,totalMs:40}'; }
fp="$(cfip_reuse_config_fingerprint)"
write_state() {
    local loss="$1" metrics
    if [[ "$loss" == unknown ]]; then metrics='[]'; else metrics="$(jq -cn --argjson loss "$loss" '[{ip:"104.16.1.1",family:"ipv4",lossRate:$loss}]')"; fi
    jq -cn --arg fp "$fp" --argjson now "$(date +%s)" --argjson metrics "$metrics" '{schemaVersion:1,lastFullOptimizeAt:$now,lastValidationAt:$now,validationSuccess:true,configFingerprint:$fp,reuseCount:0,fullOptimizeCount:1,savedProbes:0,savedRuntimeSeconds:0,fullOptimizeCandidates:$metrics,recent:[]}' >"$CFIP_REUSE_STATE_FILE"
}
write_state 0
if ! cfip_reuse_try_current; then echo 'expected measured zero loss to permit reuse' >&2; exit 1; fi
jq -e '.probes|all(.[]; .success==true and .lossRate==0 and .candidateLossRate==0)' "$CFIP_OUTCOME_FILE" >/dev/null
jq -e '.savedProbes==null and .savedRuntimeSeconds==null and .validationProbeCount==1 and (.validationRuntimeSeconds|type)=="number"' "$CFIP_REUSE_STATE_FILE" >/dev/null
write_state 0.4
if cfip_reuse_try_current; then echo 'high historical loss unexpectedly permitted reuse' >&2; exit 1; fi
[[ "$CFIP_REUSE_FALLBACK_REASON" == current_quality_regression ]]
write_state unknown
if cfip_reuse_try_current; then echo 'unknown historical loss unexpectedly permitted reuse' >&2; exit 1; fi
printf '%s\n' '[{"ip":"104.16.1.1","family":"ipv4"}]' >"$CFIP_SELECTED_FILE"
cfip_post_apply_probe "$CFIP_SELECTED_FILE" "$CFIP_TARGET_DOMAINS" "$CFIP_REUSE_VALIDATION_TIMEOUT" "$CFIP_OUTCOME_FILE" || true
jq -e '.probes[0].success==true and .probes[0].lossRate==null and .probes[0].candidateLossRate==null' "$CFIP_OUTCOME_FILE" >/dev/null
cfip_rill_reward_json "$CFIP_OUTCOME_FILE" >"$TMP/reward.json"
jq -e '.components.loss==null and .worstDomain.lossRate==null' "$TMP/reward.json" >/dev/null
write_state 0
CFIP_HTTP_OK=false
if cfip_reuse_try_current; then echo 'failed HTTP probe unexpectedly permitted reuse' >&2; exit 1; fi
cfip_post_apply_probe "$CFIP_SELECTED_FILE" "$CFIP_TARGET_DOMAINS" "$CFIP_REUSE_VALIDATION_TIMEOUT" "$CFIP_OUTCOME_FILE" || true
jq -e '.probes[0].success==false and .validated==false' "$CFIP_OUTCOME_FILE" >/dev/null
echo 'Reuse loss semantics distinguish measured loss, unknown history, and HTTP availability'