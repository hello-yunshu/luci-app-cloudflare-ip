#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
export CFIP_STATUS_DIR="$TMP/status" CFIP_HOMEPROXY_STATE_FILE="$TMP/status/homeproxy-managed.json"
export CFIP_TXN_DIR="$TMP/txn" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_INIT_DIR="$TMP/init"
mkdir -p "$CFIP_STATUS_DIR" "$CFIP_TXN_DIR" "$CFIP_INIT_DIR"
mkdir -p "$CFIP_RUNTIME_DIR"
touch "$CFIP_INIT_DIR/homeproxy" && chmod +x "$CFIP_INIT_DIR/homeproxy"
source "$CFIP_LIB_DIR/common.sh"
source "$CFIP_LIB_DIR/transaction.sh"

# Model the target OpenWrt jq package built without Oniguruma: regex helpers
# fail at runtime even though ordinary JSON operations remain available.
jq() {
	case "$*" in
		*test\(*|*match\(*|*sub\(*|*gsub\(*) echo 'jq: compiled without Oniguruma regex library' >&2; return 3 ;;
	esac
	command jq "$@"
}
[[ "$(cfip_homeproxy_normalize_domain 'PrOxY.ExAmPlE.TeSt')" == proxy.example.test ]]

DB_KEYS=(homeproxy.config homeproxy.config.routing_mode homeproxy.config.main_node homeproxy.config.main_udp_node homeproxy.hp_active homeproxy.hp_active.type homeproxy.hp_active.address homeproxy.hp_active.port homeproxy.hp_idle homeproxy.hp_idle.type homeproxy.hp_idle.address homeproxy.hp_idle.port)
DB_VALUES=(homeproxy global hp_active same node socks cdn.example.com 1080 node socks idle.example.com 1080)
PENDING_KEYS=()
PENDING_VALUES=()
db_get() { local i; for ((i=0;i<${#DB_KEYS[@]};i++)); do [[ "${DB_KEYS[$i]}" == "$1" ]] && { printf '%s' "${DB_VALUES[$i]}"; return 0; }; done; return 1; }
db_set() { local i; for ((i=0;i<${#DB_KEYS[@]};i++)); do [[ "${DB_KEYS[$i]}" == "$1" ]] && { DB_VALUES[$i]="$2"; return 0; }; done; DB_KEYS+=("$1"); DB_VALUES+=("$2"); }
pending_get() { local i; for ((i=0;i<${#PENDING_KEYS[@]};i++)); do [[ "${PENDING_KEYS[$i]}" == "$1" ]] && { printf '%s' "${PENDING_VALUES[$i]}"; return 0; }; done; return 1; }
pending_set() { local i; for ((i=0;i<${#PENDING_KEYS[@]};i++)); do [[ "${PENDING_KEYS[$i]}" == "$1" ]] && { PENDING_VALUES[$i]="$2"; return 0; }; done; PENDING_KEYS+=("$1"); PENDING_VALUES+=("$2"); }
opkg() { [[ "$1" == status && "$2" == luci-app-homeproxy ]] || return 1; printf 'Package: luci-app-homeproxy\nVersion: %s\n' "${TEST_HOMEPROXY_VERSION:-26.300.08316~d72e293}"; }
cfip_is_ipv4() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }
cfip_is_ipv6() { [[ "$1" == *:* ]]; }
cfip_service_running() { [[ "${TEST_HOME_PROXY_RUNNING:-false}" == true ]]; }
uci() {
	local cmd arg key value i
	[[ "$1" != -q ]] || shift
	cmd="$1"; shift || true
	case "$cmd" in
	  get) key="$1"; pending_get "$key" && return 0; db_get "$key" ;;
	  changes) for ((i=0;i<${#PENDING_KEYS[@]};i++)); do printf "%s='%s'\n" "${PENDING_KEYS[$i]}" "${PENDING_VALUES[$i]}"; done ;;
	  set) arg="$1"; key="${arg%%=*}"; value="${arg#*=}"; pending_set "$key" "$value" ;;
	  commit) for ((i=0;i<${#PENDING_KEYS[@]};i++)); do db_set "${PENDING_KEYS[$i]}" "${PENDING_VALUES[$i]}"; done; PENDING_KEYS=(); PENDING_VALUES=() ;;
	  revert) PENDING_KEYS=(); PENDING_VALUES=() ;;
	  export) printf 'package homeproxy\n' ;;
	  show) for ((i=0;i<${#DB_KEYS[@]};i++)); do [[ "${DB_KEYS[$i]}" == homeproxy.* ]] && printf '%s=%q\n' "${DB_KEYS[$i]}" "${DB_VALUES[$i]}"; done ;;
	  *) echo "unexpected uci invocation: $cmd $*" >&2; return 2 ;;
	esac
}

# Exercise HomeProxy through the same transaction lifecycle used by CFI, not
# only the adapter's direct helper methods.
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
CFIP_TXN_DIR=''
CFIP_RUN_ID=homeproxy-transaction-contract
CFIP_HOMEPROXY_TARGET_DOMAIN=cdn.example.com
CFIP_HOMEPROXY_STATE_FILE="$TMP/status/homeproxy-managed.json"
TEST_HOMEPROXY_VERSION=26.298.29275~c84adb9
CFIP_STOP_SERVICE=false
TEST_HOME_PROXY_RUNNING=true
init_calls=0
cfip_stop_service() { init_calls=$((init_calls + 1)); }
cfip_restart_service() { init_calls=$((init_calls + 1)); }
printf '[{"ip":"198.51.100.9","family":"ipv4"}]\n' >"$TMP/txn-selected.json"
cfip_txn_prepare homeproxy
cfip_txn_apply homeproxy "$TMP/txn-selected.json"
[[ "$CFIP_TXN_STATE" == PERSISTED && "$(db_get homeproxy.hp_active.address)" == 198.51.100.9 ]]
[[ -f "$CFIP_TXN_DIR/homeproxy-managed.json.pending" && "$init_calls" == 0 ]]
cfip_txn_rollback homeproxy
[[ "$CFIP_TXN_ROLLED_BACK" == true && "$(db_get homeproxy.hp_active.address)" == cdn.example.com ]]
[[ ! -e "$CFIP_HOMEPROXY_STATE_FILE" && "$init_calls" == 0 ]]
echo 'PASS HomeProxy transaction prepare/apply/rollback restores UCI and removes pending state without service actions'

cfip_txn_prepare homeproxy
cfip_txn_apply homeproxy "$TMP/txn-selected.json"
cfip_txn_commit
[[ "$CFIP_TXN_COMMITTED" == true && -z "$CFIP_TXN_DIR" ]]
[[ "$(db_get homeproxy.hp_active.address)" == 198.51.100.9 ]]
jq -e '.section=="hp_active" and .domain=="cdn.example.com" and .lastAddress=="198.51.100.9" and .nodeType=="socks"' "$CFIP_HOMEPROXY_STATE_FILE" >/dev/null
echo 'PASS HomeProxy transaction prepare/apply/commit writes managed ownership state'

printf '[{"ip":"198.51.100.10","family":"ipv4"}]\n' >"$TMP/txn-selected-2.json"
cfip_txn_prepare homeproxy
cfip_txn_apply homeproxy "$TMP/txn-selected-2.json"
cfip_txn_rollback homeproxy
[[ "$(db_get homeproxy.hp_active.address)" == 198.51.100.9 ]]
jq -e '.lastAddress=="198.51.100.9"' "$CFIP_HOMEPROXY_STATE_FILE" >/dev/null
[[ "$init_calls" == 0 ]]
echo 'PASS HomeProxy subsequent transaction rollback restores preexisting managed state'

rm -f "$CFIP_HOMEPROXY_STATE_FILE"
db_set homeproxy.hp_active.address cdn.example.com
CFIP_TXN_DIR="$TMP/txn"

cfip_homeproxy_resolve_active_node cdn.example.com
[[ "$CFIP_HOMEPROXY_NODE_SECTION" == hp_active && "$CFIP_HOMEPROXY_NODE_TYPE" == socks ]]
TEST_HOMEPROXY_VERSION=26.298.29275~c84adb9
cfip_homeproxy_resolve_active_node cdn.example.com
[[ "$CFIP_HOMEPROXY_VERSION" == 26.298.29275~c84adb9 ]]
for invalid in custom separate_udp wrong_domain wrong_type unknown_version; do
	db_set homeproxy.config.routing_mode global; db_set homeproxy.config.main_udp_node same
	db_set homeproxy.hp_active.type socks; db_set homeproxy.hp_active.address cdn.example.com
	TEST_HOMEPROXY_VERSION=26.300.08316~d72e293
	case "$invalid" in
	  custom) db_set homeproxy.config.routing_mode custom ;;
	  separate_udp) db_set homeproxy.config.main_udp_node hp_idle ;;
	  wrong_domain) db_set homeproxy.hp_active.address other.example.com ;;
	  wrong_type) db_set homeproxy.hp_active.type vmess ;;
	  unknown_version) TEST_HOMEPROXY_VERSION=26.298.29274~c84adb9 ;;
	esac
	if cfip_homeproxy_resolve_active_node cdn.example.com >/dev/null 2>&1; then echo "FAIL: accepted unsupported HomeProxy case $invalid" >&2; exit 1; fi
	[[ "$(db_get homeproxy.hp_active.address)" != 198.51.100.9 ]]
done
TEST_HOMEPROXY_VERSION=26.300.08316~d72e293
db_set homeproxy.config.routing_mode global; db_set homeproxy.config.main_udp_node same
db_set homeproxy.hp_active.type socks; db_set homeproxy.hp_active.address cdn.example.com
TEST_HOMEPROXY_VERSION=26.300.08316~d72e293
CFIP_RECOVERY_ERROR=''
cfip_homeproxy_resolve_active_node cdn.example.com

# Active-service measurement cannot silently use the proxy or stop it.
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
CFIP_TXN_DIR="$TMP/txn"
cfip_homeproxy_resolve_active_node cdn.example.com
CFIP_MODE=homeproxy CFIP_STOP_SERVICE=false CFIP_STOPPED_MODE=''
TEST_HOME_PROXY_RUNNING=true
stop_calls=0
cfip_stop_service() { stop_calls=$((stop_calls + 1)); }
if stop_service_for_measurement; then echo 'FAIL: measured through active HomeProxy without authorization' >&2; exit 1; fi
[[ "$stop_calls" == 0 && -z "$CFIP_STOPPED_MODE" ]]
CFIP_STOP_SERVICE=true
stop_service_for_measurement
[[ "$stop_calls" == 1 && "$CFIP_STOPPED_MODE" == homeproxy ]]
CFIP_STOPPED_MODE=''
CFIP_STOP_SERVICE=false

printf '%s\n' '[{"ip":"198.51.100.9","family":"ipv4"},{"ip":"198.51.100.10","family":"ipv4"}]' >"$TMP/selected.json"
# A package update between preflight and UCI write invalidates the captured profile.
TEST_HOMEPROXY_VERSION=26.300.08316~d72e293
cfip_homeproxy_resolve_active_node cdn.example.com
TEST_HOMEPROXY_VERSION=26.300.08316~d72e294
if cfip_homeproxy_apply_selected "$TMP/selected.json" >/dev/null 2>&1; then echo 'FAIL: HomeProxy package version race was accepted' >&2; exit 1; fi
[[ "$(db_get homeproxy.hp_active.address)" == cdn.example.com ]]
TEST_HOMEPROXY_VERSION=26.300.08316~d72e293
cfip_homeproxy_resolve_active_node cdn.example.com
printf '[]\n' >"$CFIP_TXN_DIR/homeproxy-fields.json"
cfip_homeproxy_apply_selected "$TMP/selected.json"
[[ "$(db_get homeproxy.hp_active.address)" == 198.51.100.9 ]]
[[ "$(db_get homeproxy.hp_idle.address)" == idle.example.com ]]
[[ "$(jq -r '.expected' "$CFIP_TXN_DIR/homeproxy-fields.json")" == 198.51.100.9 ]]
[[ -f "$CFIP_TXN_DIR/homeproxy-managed.json.pending" ]]
cfip_homeproxy_restore_fields
[[ "$(db_get homeproxy.hp_active.address)" == cdn.example.com ]]
[[ "$(jq -r '.key' "$CFIP_TXN_DIR/homeproxy-fields.json")" == homeproxy.hp_active.address ]]

# Concurrent reference edits reject before writing another field.
db_set homeproxy.config.main_node hp_idle
if cfip_homeproxy_apply_selected "$TMP/selected.json" >/dev/null 2>&1; then echo 'FAIL: active reference race was accepted' >&2; exit 1; fi
[[ "$(db_get homeproxy.hp_active.address)" == cdn.example.com ]]
db_set homeproxy.config.main_node hp_active
TEST_HOMEPROXY_VERSION=26.298.29275~c84adb9
cfip_homeproxy_resolve_active_node cdn.example.com
printf '[]\n' >"$CFIP_TXN_DIR/homeproxy-fields.json"
cfip_homeproxy_apply_selected "$TMP/selected.json"
[[ "$(db_get homeproxy.hp_active.address)" == 198.51.100.9 ]]
cfip_homeproxy_restore_fields
[[ "$(db_get homeproxy.hp_active.address)" == cdn.example.com ]]
echo 'HomeProxy persistence-only mode contract passed'
