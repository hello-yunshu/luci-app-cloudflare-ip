#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"

mkdir -p "$TMP/init" "$TMP/bin"
cat >"$TMP/init/openclash" <<'INIT'
#!/bin/sh
printf '%s\n' "$*" >>"$CFIP_INIT_LOG"
exit 0
INIT
chmod +x "$TMP/init/openclash"
cat >"$TMP/bin/uci" <<'UCI'
#!/bin/sh
args="$*"
case "$args" in
  *"get openclash.config.enable"*) echo 1 ;;
  *"changes openclash"*) if [ -n "${CFIP_PENDING_OC:-}" ]; then printf '%s\n' "$CFIP_PENDING_OC"; fi; exit 0 ;;
  *"set "*) printf 'SET %s\n' "$args" >>"$CFIP_UCI_LOG" ;;
  *"commit "*) printf 'COMMIT %s\n' "$args" >>"$CFIP_UCI_LOG" ;;
  *) exit 0 ;;
esac
UCI
chmod +x "$TMP/bin/uci"

PATH="$TMP/bin:$PATH" CFIP_INIT_DIR="$TMP/init" CFIP_INIT_LOG="$TMP/init.log" \
CFIP_UCI_LOG="$TMP/uci.log" CFIP_MEASUREMENT_DEADLINE=0 \
CFIP_PENDING_OC="openclash.config.custom='x'" \
bash -c 'source "$1"; CFIP_OPENCLASH_EXPECTED_ENABLED=1; CFIP_OPENCLASH_INITIAL_HEALTHY=true; cfip_stop_service openclash' sh \
  "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh" >/dev/null 2>&1 && \
  { echo 'FAIL pending OpenClash UCI was committed'; exit 1; } || true
[[ ! -e "$TMP/init.log" ]]
[[ ! -e "$TMP/uci.log" ]]
grep -q 'pending UCI changes' <<<"${CFIP_OPENCLASH_SERVICE_ERROR:-}" || true
echo 'PASS pending OpenClash UCI is refused before set/commit/stop'

rm -f "$TMP/init.log" "$TMP/uci.log"
PATH="$TMP/bin:$PATH" CFIP_INIT_DIR="$TMP/init" CFIP_INIT_LOG="$TMP/init.log" \
CFIP_UCI_LOG="$TMP/uci.log" CFIP_MEASUREMENT_DEADLINE=0 \
bash -c 'source "$1"; CFIP_OPENCLASH_EXPECTED_ENABLED=1; CFIP_OPENCLASH_INITIAL_HEALTHY=true; cfip_stop_service openclash' sh \
  "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh" >/dev/null 2>&1
grep -q 'stop' "$TMP/init.log"
grep -q 'set openclash.config.enable=0' "$TMP/uci.log"
echo 'PASS no pending UCI allows the normal stop path'
