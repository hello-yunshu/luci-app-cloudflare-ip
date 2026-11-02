#!/usr/bin/env bash
# A stopped service must not be started with another writer's unvalidated file.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/transaction.sh"
cfip_begin_recovery() { :; }
cfip_restart_service() { printf '%s\n' "$*" >>"$TMP/restarts"; }
for stopped in true false; do
    for applied in true false; do
        CFIP_TXN_DIR="$TMP/txn-$stopped-$applied"; mkdir -p "$CFIP_TXN_DIR"
        CFIP_TXN_STATE=MUTATED; CFIP_TXN_ROLLED_BACK=false
        CFIP_TXN_ORIGINAL_RUNNING=true
        CFIP_OPENCLASH_CONFIG="$TMP/live.yaml"
        printf 'original\n' >"$CFIP_TXN_DIR/openclash.yaml"
        printf 'expected transaction bytes\n' >"$CFIP_TXN_DIR/openclash.written.yaml"
        printf 'external user edit\n' >"$CFIP_OPENCLASH_CONFIG"
        CFIP_OPENCLASH_RESTART_ATTEMPTS=0
        CFIP_OPENCLASH_CF_STOPPED="$stopped"
        CFIP_OPENCLASH_SERVICE_APPLIED="$applied"
        CFIP_OPENCLASH_EXPECTED_ENABLED=1
        CFIP_OPENCLASH_RECOVERY_ATTEMPTED=false
        CFIP_OPENCLASH_SERVICE_ERROR=""
        CFIP_STOPPED_MODE=openclash
        rm -f "$TMP/restarts"
        for repeat in 1 2; do
            if cfip_txn_rollback openclash; then echo 'conflict rollback falsely succeeded' >&2; exit 1; fi
            [[ ! -e "$TMP/restarts" ]] || { echo "FAIL: restarted external config stopped=$stopped applied=$applied" >&2; exit 1; }
            [[ "$(cat "$CFIP_OPENCLASH_CONFIG")" == 'external user edit' ]]
            [[ -f "$CFIP_TXN_DIR/openclash.yaml" && -f "$CFIP_TXN_DIR/openclash.written.yaml" ]]
            [[ "$CFIP_TXN_ROLLED_BACK" == false && "$CFIP_STOPPED_MODE" == '' ]]
            [[ "$CFIP_RECOVERY_ERROR" == *'changed outside this transaction'* ]]
        done
    done
done
# Normal recovery still restores known transaction bytes and restarts once.
CFIP_TXN_DIR="$TMP/positive"; mkdir -p "$CFIP_TXN_DIR"
CFIP_TXN_STATE=MUTATED; CFIP_TXN_ROLLED_BACK=false
printf 'original\n' >"$CFIP_TXN_DIR/openclash.yaml"
printf 'transaction\n' >"$CFIP_TXN_DIR/openclash.written.yaml"
cp "$CFIP_TXN_DIR/openclash.written.yaml" "$CFIP_OPENCLASH_CONFIG"
CFIP_OPENCLASH_CF_STOPPED=true; CFIP_OPENCLASH_SERVICE_APPLIED=false
CFIP_OPENCLASH_RECOVERY_ATTEMPTED=false
rm -f "$TMP/restarts"
cfip_txn_rollback openclash
cfip_txn_rollback openclash
[[ "$(cat "$CFIP_OPENCLASH_CONFIG")" == original ]]
[[ "$(wc -l <"$TMP/restarts" | tr -d ' ')" == 1 ]]
[[ "$CFIP_TXN_ROLLED_BACK" == true ]]
echo 'PASS external rollback conflicts preserve files and journal without restart'
