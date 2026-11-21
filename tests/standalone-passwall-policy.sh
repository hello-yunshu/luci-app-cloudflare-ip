#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
source "$ROOT/cf-openwrt-auto.sh"

MODE=passwall
STOP_SERVICE_BEFORE_SPEEDTEST=false
passwall_process_running() { return 0; }
if (passwall_measurement_preflight) >"$TMP/result" 2>&1; then
	echo 'FAIL: standalone CFI accepted online PassWall measurement without bypass' >&2
	exit 1
fi
grep -q 'refusing to measure through the running proxy' "$TMP/result"
passwall_process_running() { return 1; }
passwall_measurement_preflight
passwall_process_running() { return 2; }
if (passwall_measurement_preflight) >"$TMP/result" 2>&1; then
	echo 'FAIL: standalone CFI accepted an unknown PassWall process state' >&2
	exit 1
fi
grep -q 'cannot determine whether PassWall is running' "$TMP/result"

log() { :; }
need_cmd() { :; }
find_passwall_sections() { printf 'node1\n'; }
uci() {
	case "$1" in
		set|commit) return 0 ;;
		get) return 1 ;;
		*) return 2 ;;
	esac
}
restart_calls=0
restart_service() { restart_calls=$((restart_calls + 1)); }
FAST_IPS=(198.51.100.10)
IP_COUNT=1
PASSWALL_NAME_SUFFIX=''
_STOPPED_SERVICE=''
update_passwall
[[ "$restart_calls" == 0 ]]
[[ "$_STOPPED_SERVICE" == '' ]]

_STOPPED_SERVICE=passwall
update_passwall
[[ "$restart_calls" == 1 ]]
[[ "$_STOPPED_SERVICE" == '' ]]
echo 'PASS standalone PassWall fails closed online; persists without restart unless its maintenance stop is owned'
