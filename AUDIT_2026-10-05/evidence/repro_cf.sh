#!/usr/bin/env bash
set -euo pipefail
ROOT="$PWD"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
export CFIP_STATUS_DIR="$TMP/status" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_LOG_FILE="$TMP/log"
mkdir -p "$CFIP_STATUS_DIR" "$CFIP_RUNTIME_DIR"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
# Controlled hash tool substitute: this Windows Git runtime lacks sha256sum.
# The test concerns write timing, not hashing correctness.
sha256sum() { cat >/dev/null; printf '%064d  -\n' 1; }
uci() { case "${*: -1}" in cf_ip.passwall.target_domain) printf old.example ;; *) return 1 ;; esac; }
printf '{"contextFingerprint":"old","lineageId":"%064d"}' 2 >"$CFIP_RILL_STATE_META_FILE"
printf '{"sentinel":"model-state"}' >"$CFIP_RILL_STATE"
printf '{"sentinel":"qualification"}' >"$CFIP_RILL_QUALIFICATION_FILE"
printf '\nREPRO CFI-01: validate staged candidate, without commit\n'
cmd_validate_config '{"cf_ip.passwall.target_domain":"new.example"}'
test ! -e "$CFIP_RILL_STATE" && echo 'CONFIRMED: validation moved existing model state out of canonical path'
test ! -e "$CFIP_RILL_QUALIFICATION_FILE" && echo 'CONFIRMED: validation moved qualification out of canonical path'

printf '\nREPRO CFI-02: failed service stop during sync\n'
load_config() { return 0; }
init_run_paths() { CFIP_RUN_ID=audit; CFIP_SELECTED_FILE="$TMP/selected.json"; CFIP_OUTCOME_FILE="$TMP/outcome.json"; }
printf '{"best_ips":["104.16.1.1"]}' >"$CFIP_STATUS_FILE"
cfip_txn_prepare() { CFIP_TXN_DIR="$TMP/txn"; mkdir -p "$CFIP_TXN_DIR"; CFIP_TXN_STATE=PREPARED; return 0; }
stop_service_for_measurement() { CFIP_STOPPED_MODE=passwall; return 1; }
CFIP_PASSWALL_TARGET_DOMAIN=old.example
if cmd_sync_explicit passwall; then exit 1; fi
printf 'after sync failure: state=%s stopped=%s snapshot=%s\n' "$CFIP_TXN_STATE" "$CFIP_STOPPED_MODE" "$CFIP_TXN_DIR"
test "$CFIP_STOPPED_MODE" = passwall && test -d "$CFIP_TXN_DIR" && echo 'CONFIRMED: sync returned with no rollback/restore and retained active snapshot'

printf '\nREPRO CFI-03: successful reuse HTTP probe is classified loss=1\n'
printf '[{"ip":"104.16.1.1","family":"ipv4"}]' >"$TMP/current.json"
CFIP_MEASUREMENT_DEADLINE=0
cfip_probe_one() { jq -cn --arg ip "$1" '{ip:$ip,success:true,totalMs:100,ttfbMs:50}'; }
cfip_post_apply_probe "$TMP/current.json" old.example 5 "$TMP/reuse-outcome.json"
jq -c '{validated,probeLoss:[.probes[].lossRate]}' "$TMP/reuse-outcome.json"
if jq -e --argjson loss 0.25 --argjson ttfb 3000 --argjson total 5000 'all(.probes[]; .success==true and (.lossRate//0)<=$loss and (.ttfbMs//999999)<=$ttfb and (.totalMs//999999)<=$total)' "$TMP/reuse-outcome.json" >/dev/null; then exit 1; fi
echo 'CONFIRMED: default reuse gate rejects every successful probe with current-IP record shape'
