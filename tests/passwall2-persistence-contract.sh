#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UCI_REAL_BIN="${UCI_REAL_BIN:?real UCI CLI required}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/config" "$TMP/delta" "$TMP/runtime" "$TMP/status" "$TMP/init"
touch "$TMP/init/passwall2"; chmod +x "$TMP/init/passwall2"
uci() { "$UCI_REAL_BIN" -c "$TMP/config" -t "$TMP/delta" "$@"; }
opkg() {
    [[ "$1" == status && "$2" == luci-app-passwall2 ]] || return 1
    printf 'Package: luci-app-passwall2\nVersion: 26.11.11-r1\n'
}
cfip_service_running() { [[ "${TEST_PW2_RUNNING:-false}" == true ]]; }
cfip_begin_recovery() { :; }

cat >"$TMP/config/passwall2" <<'UCI'
config global 'global'
	option enabled '1'
	option node 'shunt'
	option acl_enable '0'
	option socks_enabled '0'
config nodes 'shunt'
	option protocol '_shunt'
	option shunt_group 'CN'
	option default_node 'proxy'
	option rule1 'direct'
config shunt_rules 'rule1'
	option group 'CN'
	option remarks 'Direct traffic'
config nodes 'proxy'
	option protocol 'socks'
	option address 'cdn.example.com'
	option port '1080'
config nodes 'direct'
	option protocol 'direct'
UCI

export CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
export CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_STATUS_DIR="$TMP/status"
export CFIP_TXN_DIR='' CFIP_RUN_ID=pw2-contract CFIP_INIT_DIR="$TMP/init"
export CFIP_PASSWALL2_TARGET_DOMAIN=cdn.example.com
export CFIP_PASSWALL2_STATE_FILE="$TMP/status/passwall2-managed.json"
source "$CFIP_LIB_DIR/common.sh"
source "$CFIP_LIB_DIR/transaction.sh"
CFIP_TXN_DIR=''
# Avoid requiring the host's coreutils `timeout` for the service-status stub.
cfip_run_with_timeout() { shift; "$@"; }
[[ "$(cfip_pw2_normalize_target 'PrOxY.ExAmPlE.TeSt')" == proxy.example.test ]]
cat >"$TMP/apk-installed" <<'APK'
P:luci-app-passwall2
V:26.11.11-r1
APK
CFIP_APK_DB="$TMP/apk-installed"
( unset -f opkg; PATH=/usr/bin:/bin; [[ "$(cfip_pw2_package_version)" == 26.11.11-r1 ]] )
unset CFIP_APK_DB
init_calls=0
cfip_stop_service() { init_calls=$((init_calls+1)); return 0; }
cfip_restart_service() { init_calls=$((init_calls+1)); return 0; }

cat >"$TMP/selected.json" <<'JSON'
[{"ip":"198.51.100.9","family":"ipv4"},{"ip":"198.51.100.10","family":"ipv4"}]
JSON

# Exercise the production transaction entry points with a real libuci CLI.
TEST_PW2_RUNNING=true
cfip_txn_prepare passwall2
[[ "$CFIP_TXN_STATE" == PREPARED && "$CFIP_TXN_ORIGINAL_RUNNING" == true ]]
[[ "$(jq -r 'type' "$CFIP_TXN_DIR/passwall2-fields.json")" == object ]]
cfip_txn_apply passwall2 "$TMP/selected.json"
[[ "$CFIP_TXN_STATE" == PERSISTED ]]
[[ "$(uci get passwall2.proxy.address)" == 198.51.100.9 ]]
[[ "$(uci get passwall2.shunt.default_node)" == proxy ]]
[[ ! -e "$CFIP_PASSWALL2_STATE_FILE" && -f "$CFIP_TXN_DIR/passwall2-managed.json.pending" ]]
[[ "$init_calls" == 0 ]]
cfip_txn_rollback passwall2
[[ "$CFIP_TXN_ROLLED_BACK" == true && "$(uci get passwall2.proxy.address)" == cdn.example.com ]]
[[ ! -e "$CFIP_PASSWALL2_STATE_FILE" && "$init_calls" == 0 ]]
echo 'PASS PassWall2 real UCI transaction rollback; unrelated graph fields preserved; no service action'

cfip_txn_prepare passwall2
cfip_txn_apply passwall2 "$TMP/selected.json"
cfip_txn_commit
[[ "$CFIP_TXN_COMMITTED" == true && -z "$CFIP_TXN_DIR" ]]
[[ "$(uci get passwall2.proxy.address)" == 198.51.100.9 ]]
jq -e '.node=="proxy" and .rootNode=="shunt" and .domain=="cdn.example.com" and .lastAddress=="198.51.100.9" and .packageVersion=="26.11.11-r1"' "$CFIP_PASSWALL2_STATE_FILE" >/dev/null
[[ "$init_calls" == 0 ]]
echo 'PASS PassWall2 real UCI transaction prepare/apply/commit; one active SOCKS leaf persisted; service untouched'

# A later failed transaction restores both the address and the ownership
# preimage, while leaving the preceding committed management state intact.
cfip_txn_prepare passwall2
cfip_txn_apply passwall2 "$TMP/selected.json"
[[ "$(uci get passwall2.proxy.address)" == 198.51.100.9 ]]
cfip_txn_rollback passwall2
[[ "$(uci get passwall2.proxy.address)" == 198.51.100.9 ]]
jq -e '.lastAddress=="198.51.100.9"' "$CFIP_PASSWALL2_STATE_FILE" >/dev/null
[[ "$init_calls" == 0 ]]
echo 'PASS PassWall2 subsequent rollback restored prior managed state and address'

# Combinations whose active graph cannot be safely applied are rejected during
# target resolution, before opening a transaction or changing configuration.
uci set passwall2.@global[0].acl_enable=1; uci commit passwall2
if cfip_pw2_resolve_target cdn.example.com; then echo 'FAIL: ACL root was accepted' >&2; exit 1; fi
uci set passwall2.@global[0].acl_enable=0; uci commit passwall2
uci set passwall2.proxy.chain_proxy=other; uci commit passwall2
if cfip_pw2_resolve_target cdn.example.com; then echo 'FAIL: chained SOCKS leaf was accepted' >&2; exit 1; fi
uci -q delete passwall2.proxy.chain_proxy; uci commit passwall2
uci set passwall2.shunt.default_node=missing; uci commit passwall2
if cfip_pw2_resolve_target cdn.example.com; then echo 'FAIL: invalid active graph reference was accepted' >&2; exit 1; fi
uci set passwall2.shunt.default_node=proxy; uci commit passwall2
[[ "$(uci get passwall2.proxy.address)" == 198.51.100.9 ]]
echo 'PASS PassWall2 ACL, chain and invalid-reference profiles fail closed without node mutation'

# A user edit to the owned field after CFI wrote it must block rollback and
# retain both the user's value and the transaction journal for recovery.
cfip_txn_prepare passwall2
cfip_txn_apply passwall2 "$TMP/selected.json"
uci set passwall2.proxy.address=203.0.113.4
uci commit passwall2
if cfip_txn_rollback passwall2; then echo 'FAIL: external owned-field edit was overwritten' >&2; exit 1; fi
[[ "$(uci get passwall2.proxy.address)" == 203.0.113.4 ]]
[[ "$CFIP_TXN_ROLLED_BACK" == false && -f "$CFIP_TXN_DIR/passwall2-fields.json" ]]
echo 'PASS PassWall2 real UCI external owned-field conflict preserved with journal'

# The service measurement guard remains separate from the persistence adapter:
# active proxy use fails closed by default, and explicit maintenance intent is
# the only path that may stop the service for measurement.
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
cfip_service_running() { [[ "${TEST_PW2_RUNNING:-false}" == true ]]; }
cfip_stop_service() { init_calls=$((init_calls + 1)); return 0; }
CFIP_MODE=passwall2 CFIP_STOP_SERVICE=false CFIP_STOPPED_MODE=''
CFIP_MEASUREMENT_ERROR=''
TEST_PW2_RUNNING=true
init_calls=0
if stop_service_for_measurement; then echo 'FAIL: measured through active PassWall2 without authorization' >&2; exit 1; fi
[[ "$init_calls" == 0 && -z "$CFIP_STOPPED_MODE" && "$CFIP_MEASUREMENT_ERROR" == *'refusing to measure through the running proxy'* ]]
CFIP_STOP_SERVICE=true
stop_service_for_measurement
[[ "$init_calls" == 1 && "$CFIP_STOPPED_MODE" == passwall2 ]]
echo 'PASS PassWall2 active measurement fails closed; explicit maintenance stop is separately gated'
