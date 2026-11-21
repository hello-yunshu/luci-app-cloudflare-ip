#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/runtime" "$TMP/status" "$TMP/init"
export CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_STATUS_DIR="$TMP/status" CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"

cat >"$TMP/dns-guard" <<'GUARD'
#!/bin/sh
printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$PPID" >>"$CFIP_DNS_LEASE_LOG"
case "$1" in
  --maintenance-begin) [ "${CFIP_DNS_LEASE_BEGIN_FAIL:-0}" = 0 ] ;;
  --maintenance-end) [ "${CFIP_DNS_LEASE_END_FAIL:-0}" = 0 ] ;;
  *) exit 2 ;;
esac
GUARD
chmod +x "$TMP/dns-guard"
export CFIP_DNS_GUARD_BIN="$TMP/dns-guard" CFIP_DNS_LEASE_LOG="$TMP/lease.log"
CFIP_RUN_ID='run-42.with:punctuation'
CFIP_DNS_MAINTENANCE_ACTIVE=false; CFIP_DNS_MAINTENANCE_ID=""; CFIP_DNS_MAINTENANCE_ERROR=""

cfip_dns_maintenance_begin
[[ "$CFIP_DNS_MAINTENANCE_ACTIVE" == true ]]
[[ "$CFIP_DNS_MAINTENANCE_ID" == 'run42.with:punctuation' ]]
cfip_dns_maintenance_begin
[[ "$(wc -l <"$CFIP_DNS_LEASE_LOG" | tr -d ' ')" == 1 ]]
cfip_dns_maintenance_end
[[ "$CFIP_DNS_MAINTENANCE_ACTIVE" == false ]]
[[ "$(sed -n '1s/|.*//' "$CFIP_DNS_LEASE_LOG")" == --maintenance-begin ]]
[[ "$(sed -n '2s/|.*//' "$CFIP_DNS_LEASE_LOG")" == --maintenance-end ]]
[[ "$(sed -n '1s/.*|//' "$CFIP_DNS_LEASE_LOG")" == "$$" ]]
[[ "$(sed -n '2s/.*|//' "$CFIP_DNS_LEASE_LOG")" == "$$" ]]
echo 'PASS CFI begins and releases an owner-bound DNS lease in the same process'

: >"$CFIP_DNS_LEASE_LOG"
export CFIP_DNS_LEASE_BEGIN_FAIL=1
CFIP_MODE=openclash; CFIP_OPENCLASH_EXPECTED_ENABLED=1; CFIP_STOP_SERVICE=true
CFIP_OPENCLASH_INITIAL_HEALTHY=true; CFIP_OPENCLASH_CF_STOPPED=false
CFIP_OPENCLASH_SERVICE_ERROR=""; CFIP_DNS_MAINTENANCE_ACTIVE=false
cfip_openclash_health_wait() { return 0; }
stop_calls=0
cfip_stop_service() { stop_calls=$((stop_calls+1)); return 0; }
if stop_service_for_measurement; then echo 'OpenClash stopped after lease refusal' >&2; exit 1; fi
[[ "$stop_calls" == 0 && "$(wc -l <"$CFIP_DNS_LEASE_LOG" | tr -d ' ')" == 1 ]]
[[ "$(sed -n '1s/|.*//' "$CFIP_DNS_LEASE_LOG")" == --maintenance-begin ]]
[[ "$CFIP_OPENCLASH_SERVICE_ERROR" == *'lease'* ]]
echo 'PASS failed lease acquisition prevents OpenClash maintenance stop'

# If OpenClash is back and its identity is verified but lease-end fails, keep
# the lease active for cleanup/expiry while releasing stop ownership. Cleanup
# must retry only lease-end, never perform a second restart.
: >"$CFIP_DNS_LEASE_LOG"
export CFIP_DNS_LEASE_BEGIN_FAIL=0 CFIP_DNS_LEASE_END_FAIL=1
CFIP_DNS_MAINTENANCE_ACTIVE=true; CFIP_DNS_MAINTENANCE_ID=run-lease-end; CFIP_DNS_MAINTENANCE_RELEASE_ALLOWED=false
CFIP_STOPPED_MODE=openclash; CFIP_OPENCLASH_CF_STOPPED=true
CFIP_OPENCLASH_RUNTIME_CONFIG=/fixture/main.yaml; CFIP_OPENCLASH_TARGET_CONFIG=/fixture/provider.yaml; CFIP_OPENCLASH_PROVIDER_NAME=local
CFIP_OPENCLASH_MAINTENANCE_RESTARTED=false; CFIP_OPENCLASH_SERVICE_APPLIED=false; restart_calls=0
cfip_begin_recovery() { :; }
cfip_restart_service() { restart_calls=$((restart_calls+1)); return 0; }
cfip_openclash_capture_runtime() { CFIP_OPENCLASH_RUNTIME_CONFIG=/fixture/main.yaml; CFIP_OPENCLASH_RUNTIME_ID='42:10:/mihomo:/fixture/main.yaml'; }
cfip_openclash_resolve_provider_target() { CFIP_OPENCLASH_TARGET_CONFIG=/fixture/provider.yaml; CFIP_OPENCLASH_PROVIDER_NAME=local; }
if restore_stopped_service_if_needed; then echo 'lease-end failure was reported as success' >&2; exit 1; fi
[[ "$restart_calls" == 1 && -z "$CFIP_STOPPED_MODE" && "$CFIP_OPENCLASH_CF_STOPPED" == false ]]
[[ "$CFIP_DNS_MAINTENANCE_ACTIVE" == true && "$CFIP_DNS_MAINTENANCE_RELEASE_ALLOWED" == true ]]
export CFIP_DNS_LEASE_END_FAIL=0
cfip_dns_maintenance_cleanup
[[ "$restart_calls" == 1 && "$CFIP_DNS_MAINTENANCE_ACTIVE" == false ]]
[[ "$(wc -l <"$CFIP_DNS_LEASE_LOG" | tr -d ' ')" == 2 ]]
echo 'PASS lease-end failure retains DNS lease ownership without repeating the verified service restart'
