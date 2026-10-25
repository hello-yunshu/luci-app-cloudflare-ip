#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CFIP_RUN_ID=test-run; CFIP_LOG_FILE="$TMP/test.log"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/observe.sh"
cfip_parse_cfst "$TMP/candidates.json" tcp 32 "$ROOT/tests/fixtures/cfst/tcp-normal.csv:ipv4"
test "$(jq 'length' "$TMP/candidates.json")" -eq 2
test "$(jq -r '.[1].lossRate' "$TMP/candidates.json")" = 0.25
test "$(jq -r '.[0].avgLatencyMs' "$TMP/candidates.json")" = 35.2
cfip_parse_cfst "$TMP/malformed.json" tcp 32 "$ROOT/tests/fixtures/cfst/malformed.csv:ipv4"
test "$(jq 'length' "$TMP/malformed.json")" -eq 1
jq -e '.[0].lossRate==null and .[0].avgLatencyMs==null and .[0].downloadMBps==null' "$TMP/malformed.json" >/dev/null
cfip_probe_one(){ local ip="$1" domain="$2" family="$3"; if [[ "$ip" == 104.16.1.1 ]]; then jq -cn --arg ip "$ip" --arg d "$domain" --arg f "$family" '{ip:$ip,domain:$d,family:$f,success:true,connectMs:20,tlsMs:30,ttfbMs:40,totalMs:50}'; else jq -cn --arg ip "$ip" --arg d "$domain" --arg f "$family" '{ip:$ip,domain:$d,family:$f,success:false,connectMs:0,tlsMs:0,ttfbMs:0,totalMs:0}'; fi; }
cfip_probe_candidates "$TMP/candidates.json" "$TMP/probed.json" example.com 3
cfip_native_rank "$TMP/probed.json" "$TMP/native.json"
test "$(jq 'length' "$TMP/native.json")" -eq 1
test "$(jq -r '.[0].ip' "$TMP/native.json")" = 104.16.1.1
jq '.[0:4]' "$TMP/native.json" >"$TMP/selected.json"; test "$(jq 'length' "$TMP/selected.json")" -eq 1

# Post-apply verification must cover every unique applied IP, not just selected[0].
cfip_probe_one(){ local ip="$1" domain="$2" family="$3"; jq -cn --arg ip "$ip" --arg d "$domain" --arg f "$family" '{ip:$ip,domain:$d,family:$f,success:true,connectMs:10,tlsMs:20,ttfbMs:30,totalMs:40}'; }
CFIP_RUN_ID=post-apply-test; printf '%s\n' '[{"ip":"104.16.1.1","family":"ipv4"},{"ip":"104.16.1.2","family":"ipv4"}]' >"$TMP/post-selected.json"; cfip_post_apply_probe "$TMP/post-selected.json" example.com 3 "$TMP/post.json"
jq -e '.validated==true and (.appliedIps|length)==2 and (.probes|length)==2' "$TMP/post.json" >/dev/null
echo 'v2 observation/eligibility tests passed'

# Real post-apply verifier: fresh OpenClash may report controller readiness
# before its TLS data path is ready. Every retry must verify all IPs/domains.
(
 printf 0 >"$TMP/clock"; printf 0 >"$TMP/probe-count"
 cfip_monotonic_seconds(){ cat "$TMP/clock"; }
 sleep(){ printf '%s' "$(( $(cat "$TMP/clock") + $1 ))" >"$TMP/clock"; }
 cfip_probe_one(){
   printf '%s' "$(( $(cat "$TMP/probe-count") + 1 ))" >"$TMP/probe-count"
   local ok=false code=35 tls=0
   case "$scenario" in
     delayed|mixed|mixed_receive)
       if (( $(cat "$TMP/clock")>=7 )); then ok=true; code=0; tls=20
       elif [[ "$scenario" == mixed && "$2" == two.example ]]; then code=28; tls=20
       elif [[ "$scenario" == mixed_receive && "$2" == two.example ]]; then code=56; tls=20; fi ;;
     receive) code=56; tls=20 ;;
     timeout) code=28; tls=20 ;;
     connect) code=7 ;;
     budget) code=124 ;;
     certificate) code=60 ;;
     http) code=0 ;;
   esac
   jq -cn --arg ip "$1" --arg domain "$2" --arg family "$3" --argjson ok "$ok" --argjson code "$code" --argjson tls "$tls" '{ip:$ip,domain:$domain,family:$family,success:$ok,curlExit:$code,tlsMs:$tls,ttfbMs:30,totalMs:40}'
 }
 CFIP_MODE=openclash; CFIP_OPENCLASH_SERVICE_APPLIED=true
 for scenario in delayed mixed mixed_receive persistent timeout connect receive certificate http budget short_budget reuse; do
   printf 0 >"$TMP/clock"; printf 0 >"$TMP/probe-count"
   CFIP_OPENCLASH_SERVICE_APPLIED=true; CFIP_MEASUREMENT_DEADLINE=180
   [[ "$scenario" != short_budget ]] || CFIP_MEASUREMENT_DEADLINE=3
   [[ "$scenario" != reuse ]] || CFIP_OPENCLASH_SERVICE_APPLIED=false
   if cfip_post_apply_probe "$TMP/post-selected.json" one.example,two.example 3 "$TMP/settling-$scenario.json"; then rc=0; else rc=$?; fi
   # Dynamic local deadline must never replace the caller's measurement bound.
   [[ "$CFIP_MEASUREMENT_DEADLINE" == 180 || "$scenario" == short_budget && "$CFIP_MEASUREMENT_DEADLINE" == 3 ]]
   case "$scenario" in
     delayed|mixed|mixed_receive)
       [[ "$rc" == 0 && "$(cat "$TMP/clock")" == 14 && "$(cat "$TMP/probe-count")" == 16 ]]
       jq -e '.validated==true and (.probes|length)==4 and (.serviceSettling.rounds|length)==4 and .serviceSettling.rounds[0].validated==false' "$TMP/settling-$scenario.json" >/dev/null ;;
     persistent|timeout|connect|receive)
       [[ "$rc" != 0 && "$(cat "$TMP/clock")" == 14 && "$(cat "$TMP/probe-count")" == 16 ]]
       jq -e '.validated==false and (.serviceSettling.rounds|length)==4' "$TMP/settling-$scenario.json" >/dev/null ;;
     short_budget) [[ "$rc" != 0 && "$(cat "$TMP/clock")" == 2 && "$(cat "$TMP/probe-count")" == 8 ]] ;;
     *) [[ "$rc" != 0 && "$(cat "$TMP/clock")" == 0 && "$(cat "$TMP/probe-count")" == 4 ]] ;;
   esac
   echo "PASS post-apply settling $scenario"
 done
)
