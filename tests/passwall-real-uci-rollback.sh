#!/usr/bin/env bash
# Supply a real locally built uci CLI; all configuration paths are isolated.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UCI_REAL_BIN="${UCI_REAL_BIN:?real UCI CLI required}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/config" "$TMP/delta"
uci() { "$UCI_REAL_BIN" -c "$TMP/config" -t "$TMP/delta" "$@"; }
cat >"$TMP/config/passwall" <<'UCI'
config nodes 'owned'
 option address 'cdn.example.com'
 option remarks 'Node A'
config nodes 'unrelated'
 option address 'other.example.com'
 option remarks 'original user value'
UCI
source "${CFIP_TEST_LIB_DIR:-$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip}/transaction.sh"
CFIP_RUN_ID=real-uci; case_index=0
CFIP_PASSWALL_STATE_FILE="$TMP/managed.json"
cfip_begin_recovery() { :; }
cfip_service_running() { return 1; }
# Each scenario is independent. Keep prior failed journals until fixture cleanup,
# while subsequent scenarios use a new runtime rather than bypassing the guard.
prepare_case() {
    case_index=$((case_index+1))
    CFIP_RUNTIME_DIR="$TMP/runtime-$case_index"
    mkdir -p "$CFIP_RUNTIME_DIR"
    CFIP_TXN_DIR=""; CFIP_TXN_STATE=NONE
    cfip_txn_prepare passwall
}

prepare_case
cfip_passwall_set_owned passwall.owned.address 104.16.1.1
uci commit passwall
uci set 'passwall.unrelated.remarks=external user edit'
uci commit passwall
CFIP_TXN_STATE=MUTATED
cfip_txn_rollback passwall
[[ "$(uci get passwall.unrelated.remarks)" == 'external user edit' ]] || { echo 'FAIL real UCI: rollback overwrote unrelated committed edit' >&2; exit 1; }
[[ "$(uci get passwall.owned.address)" == cdn.example.com ]]
echo 'PASS real UCI: owned address restored and unrelated external field preserved'
prepare_case
cfip_passwall_set_owned passwall.owned.address 104.16.1.2
uci commit passwall
uci set passwall.owned.address=1.1.1.1
uci commit passwall
CFIP_TXN_STATE=MUTATED
if cfip_txn_rollback passwall; then echo 'owned-field conflict accepted' >&2; exit 1; fi
[[ "$(uci get passwall.owned.address)" == 1.1.1.1 ]]
[[ "$CFIP_TXN_ROLLED_BACK" == false && -f "$CFIP_TXN_DIR/passwall-fields.json" ]]
[[ "$CFIP_RECOVERY_ERROR" == *'changed outside this transaction'* ]]
echo 'PASS real UCI: external owned-field edit rejected and journal retained'
retained="$CFIP_TXN_DIR"
journal_before="$(sha256sum "$retained"/* | sort)"
if cfip_txn_prepare passwall; then echo 'FAIL: unresolved journal allowed another same-runtime transaction' >&2; exit 1; fi
[[ "$CFIP_RECOVERY_ERROR" == *"$retained"* && "$CFIP_TXN_DIR" == "$retained" ]]
[[ "$(sha256sum "$retained"/* | sort)" == "$journal_before" ]]
[[ "$(uci get passwall.owned.address)" == 1.1.1.1 ]]
echo 'PASS real UCI: unresolved journal blocks same-runtime entry without changing external config or preimages'

uci -q delete passwall.owned.remarks
uci commit passwall
prepare_case
cfip_passwall_set_owned passwall.owned.remarks 'temporary suffix'
uci commit passwall
CFIP_TXN_STATE=MUTATED
cfip_txn_rollback passwall
if uci -q get passwall.owned.remarks; then echo 'absent field not restored' >&2; exit 1; fi
echo 'PASS real UCI: originally absent owned field removed during rollback'
prepare_case
cfip_passwall_set_owned passwall.owned.address 104.16.1.3
uci commit passwall
CFIP_TXN_STATE=MUTATED
jq() {
    if [[ "${1:-}" == -c ]]; then return 1; fi
    command jq "$@"
}
if cfip_txn_rollback passwall; then echo 'FAIL: jq row decoding failure falsely reported rollback success' >&2; exit 1; fi
[[ "$CFIP_TXN_ROLLED_BACK" == false && -f "$CFIP_TXN_DIR/passwall-fields.json" ]]
unset -f jq
echo 'PASS real UCI: journal row decoding failure preserves incomplete recovery'
prepare_case
cfip_passwall_set_owned passwall.owned.address 104.16.1.4
uci commit passwall
uci set 'passwall.unrelated.remarks=pending user edit'
pending="$(uci changes passwall)"
CFIP_TXN_STATE=MUTATED
if cfip_txn_rollback passwall; then recovery=success; else recovery=conflict; fi
[[ "$(uci changes passwall)" == "$pending" ]] || { echo "FAIL: rollback $recovery changed or committed unrelated pending delta" >&2; exit 1; }
[[ "$(uci get passwall.unrelated.remarks)" == 'pending user edit' ]]
echo 'PASS real UCI: unrelated pending delta preserved without implicit commit'
uci revert passwall
prepare_case
cfip_passwall_set_owned passwall.owned.address 104.16.1.5
uci commit passwall
printf '{"external":"user state edit"}\n' >"$CFIP_PASSWALL_STATE_FILE"
CFIP_TXN_STATE=MUTATED
if cfip_txn_rollback passwall; then echo 'managed-state external conflict accepted' >&2; exit 1; fi
[[ "$(cat "$CFIP_PASSWALL_STATE_FILE")" == '{"external":"user state edit"}' ]]
[[ -f "$CFIP_TXN_DIR/passwall-fields.json" ]]
echo 'PASS real UCI: external managed-state edits preserved with journal'
prepare_case
printf '{"candidate":true}\n' >"$CFIP_TXN_DIR/passwall-managed.json.pending"
printf '{"external":"changed before commit"}\n' >"$CFIP_PASSWALL_STATE_FILE"
if cfip_txn_commit; then echo 'managed-state commit conflict accepted' >&2; exit 1; fi
[[ "$(cat "$CFIP_PASSWALL_STATE_FILE")" == '{"external":"changed before commit"}' ]]
echo 'PASS real UCI: commit rejects changed managed-state file'
uci set 'passwall.unrelated.remarks=preexisting pending edit'
pending="$(uci changes passwall)"
if prepare_case; then echo 'preexisting pending changes accepted' >&2; exit 1; fi
[[ "$(uci changes passwall)" == "$pending" ]]
echo 'PASS real UCI: transaction entry rejects and preserves pending user changes'
uci revert passwall
uci set $'passwall.owned.remarks=first line\nsecond line\tend\n\n'
uci commit passwall
uci export passwall >"$TMP/special-before"
prepare_case
cfip_passwall_set_owned passwall.owned.remarks 'temporary remarks'
uci commit passwall
CFIP_TXN_STATE=MUTATED
cfip_txn_rollback passwall
uci export passwall >"$TMP/special-after"
cmp "$TMP/special-before" "$TMP/special-after" || { echo 'FAIL: special-character remarks were not restored byte-for-byte' >&2; exit 1; }
echo 'PASS real UCI: tabs, multiline and trailing-newline remarks preserved'
for original in "single ' quote and [*]? glob" 'literal $(printf do-not-execute) and `printf do-not-execute`' 'backslash \ and "double quotes"'; do
    uci set "passwall.owned.remarks=$original"
    uci commit passwall
    uci export passwall >"$TMP/quoted-before"
    prepare_case
    cfip_passwall_set_owned passwall.owned.remarks 'temporary remarks'
    uci commit passwall
    CFIP_TXN_STATE=MUTATED
    cfip_txn_rollback passwall
    uci export passwall >"$TMP/quoted-after"
    cmp "$TMP/quoted-before" "$TMP/quoted-after"
done
echo 'PASS real UCI: quote, glob, backslash and literal shell text preserved'
