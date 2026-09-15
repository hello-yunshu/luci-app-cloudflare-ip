#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/operational-health.sh"

mixed="$(jq -n '{schemaVersion:1,records:[
  {completed:true,result:"success",fallbackUsed:true,expansionCount:null,reuseAttempted:false},
  {completed:true,result:"success",fallbackUsed:null,expansionCount:null,reuseAttempted:false},
  {completed:true,result:"success",fallbackUsed:null,expansionCount:null,reuseAttempted:false},
  {completed:true,result:"success",fallbackUsed:null,expansionCount:null,reuseAttempted:false},
  {completed:true,result:"success",fallbackUsed:null,expansionCount:null,reuseAttempted:false}
]}')"
rollup="$(cfip_operational_rollup_json "$mixed")"
test "$(jq -r '.sampleCounts.fallback' <<<"$rollup")" = 1
test "$(jq -r '.fallbackRate' <<<"$rollup")" = 1
test "$(jq -r '.meaningfulByMetric.fallback' <<<"$rollup")" = false
test "$(jq -r '.sampleCounts.expansion' <<<"$rollup")" = 0
test "$(jq -r '.expansionRunRate' <<<"$rollup")" = null

enough="$(jq -n '{schemaVersion:1,records:[range(0;5) as $i | {completed:true,result:"success",fallbackUsed:($i==0),expansionCount:$i,reuseAttempted:true,reuseResult:(if ($i%2)==0 then "success" else "validation_failure" end),auditRun:true,winnerRecall:1,topNRecall:1,severeMiss:0}]}')"
rollup="$(cfip_operational_rollup_json "$enough")"
test "$(jq -r '.sampleCounts.fallback' <<<"$rollup")" = 5
test "$(jq -r '.fallbackRate' <<<"$rollup")" = 0.2
test "$(jq -r '.sampleCounts.reuse' <<<"$rollup")" = 5
test "$(jq -r '.meaningfulByMetric.reuse and .meaningfulByMetric.audit' <<<"$rollup")" = true

echo 'Operational comparable-sample null denominator contract passed'
