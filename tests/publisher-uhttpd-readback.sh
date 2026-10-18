#!/usr/bin/env bash
# Isolated runtime test: actual uhttpd listener, fixture init, loopback only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -x /usr/sbin/uhttpd ]] || { echo 'UNAVAILABLE: actual uhttpd required'; exit 77; }
TMP="$(mktemp -d)"
cleanup(){ [[ ! -s "$TMP/pid" ]] || kill "$(cat "$TMP/pid")" 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT
export CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_PUBLISH_DIR="$TMP/publish" CFIP_PUBLISH_STATUS_FILE="$TMP/status.json"
export CFIP_PUBLISH_BIND=127.0.0.1 CFIP_PUBLISH_PORT="$((30000+RANDOM%20000))" CFIP_PUBLISH_ENABLED=true CFIP_RUN_ID=uhttpd-fixture
export CFIP_HTTP_PID="$TMP/pid" CFIP_HTTP_LOG="$TMP/http.log"
mkdir -p "$CFIP_RUNTIME_DIR"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/publisher.sh"
cat >"$TMP/init" <<'INIT'
#!/bin/sh
case "$1" in
 restart)
  /usr/sbin/uhttpd -f -p "127.0.0.1:$CFIP_PUBLISH_PORT" -h "$CFIP_PUBLISH_DIR" -D -S -R >"$CFIP_HTTP_LOG" 2>&1 &
  echo $! >"$CFIP_HTTP_PID"
  ;;
 stop) kill "$(cat "$CFIP_HTTP_PID")" ;;
esac
INIT
chmod +x "$TMP/init"; CFIP_PUBLISH_INIT="$TMP/init"
printf '[{"ip":"104.18.1.1","family":"ipv4"}]' >"$TMP/selected"
cfip_publish_result "$TMP/selected"
jq -e '.success==true' "$CFIP_PUBLISH_STATUS_FILE" >/dev/null
echo 'PASS actual isolated uhttpd serves exact published bytes'
"$CFIP_PUBLISH_INIT" stop
CFIP_PUBLISH_READY_ATTEMPTS=1
if cfip_publisher_wait_ready "$CFIP_PUBLISH_BIND" "$CFIP_PUBLISH_PORT" "$CFIP_PUBLISH_DIR/result.json"; then echo 'FAIL stopped uhttpd reported ready'; exit 1; fi
echo 'PASS stopped actual uhttpd fails readiness'
