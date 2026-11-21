#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"

CFIP_MODE=passwall
CFIP_STOP_SERVICE=false
CFIP_STOPPED_MODE=""
service_running=true
stop_calls=0
cfip_service_running() { [[ "$service_running" == true ]]; }
cfip_stop_service() { stop_calls=$((stop_calls + 1)); }

if stop_service_for_measurement; then
	echo 'FAIL: CFI measured through an active PassWall without a verified bypass' >&2
	exit 1
fi
[[ "$stop_calls" == 0 && -z "$CFIP_STOPPED_MODE" ]]
[[ "$CFIP_MEASUREMENT_ERROR" == *'refusing to measure through the running proxy'* ]]

service_running=false
CFIP_MEASUREMENT_ERROR=""
stop_service_for_measurement
[[ "$stop_calls" == 0 && -z "$CFIP_STOPPED_MODE" ]]

service_running=true
CFIP_STOP_SERVICE=true
stop_service_for_measurement
[[ "$stop_calls" == 1 && "$CFIP_STOPPED_MODE" == passwall ]]

echo 'PASS active PassWall fails closed without verified bypass; explicit maintenance stop remains available'
