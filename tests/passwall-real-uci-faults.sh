#!/usr/bin/env bash
# Storage and UCI failures exercise the real CLI in an isolated config root.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UCI_REAL_BIN="${UCI_REAL_BIN:?real UCI CLI required}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/transaction.sh"
cfip_begin_recovery() { :; }
cfip_service_running() { return 1; }
uci() {
    local verb="${1:-}"; [[ "$verb" != -q ]] || verb="${2:-}"
    if [[ "$fault" == uci-get && "$verb" == get ]]; then return 1; fi
    if [[ "$fault" == uci-set-before && "$verb" == set ]]; then return 1; fi
    "$UCI_REAL_BIN" -c "$case_dir/config" -t "$case_dir/delta" "$@" || return $?
    if [[ "$fault" == uci-set-after && "$verb" == set ]]; then return 1; fi
}
jq() { [[ "$fault" != journal-jq ]] || return 1; command jq "$@"; }
mv() {
    if [[ "$fault" == journal-rename && "${!#}" == */passwall-fields.json ]]; then return 1; fi
    command mv "$@"
}
for injected in uci-get journal-jq journal-rename uci-set-before uci-set-after; do
    fault=none
    case_dir="$TMP/$injected"; mkdir -p "$case_dir/config" "$case_dir/delta" "$case_dir/runtime"
    cat >"$case_dir/config/passwall" <<'UCI'
config nodes 'owned'
 option address 'cdn.example.com'
 option remarks 'original remarks'
config nodes 'other'
 option address 'other.example.com'
UCI
    CFIP_RUNTIME_DIR="$case_dir/runtime"; CFIP_RUN_ID=fault
    CFIP_PASSWALL_STATE_FILE="$case_dir/managed.json"
    cfip_txn_prepare passwall
    uci export passwall >"$case_dir/before"
    fault="$injected"
    if cfip_passwall_set_owned passwall.owned.address 104.16.1.1; then echo "fault accepted: $fault" >&2; exit 1; fi
    fault=none
    if [[ "$injected" != uci-set-after ]]; then
        uci export passwall >"$case_dir/pre-rollback"
        cmp "$case_dir/before" "$case_dir/pre-rollback"
    fi
    CFIP_TXN_STATE=MUTATED
    cfip_txn_rollback passwall
    uci export passwall >"$case_dir/after"
    cmp "$case_dir/before" "$case_dir/after"
    [[ -z "$(uci changes passwall)" && "$CFIP_TXN_ROLLED_BACK" == true ]]
    echo "PASS real UCI fault: $injected"
done
