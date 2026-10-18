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
 stop) kill "$(cat "$CFIP_HTTP_PID")" || exit 1; rm -f "$CFIP_HTTP_PID" ;;
esac
INIT
chmod +x "$TMP/init"; CFIP_PUBLISH_INIT="$TMP/init"
printf '[{"ip":"104.18.1.1","family":"ipv4"}]' >"$TMP/selected"
cfip_publish_result "$TMP/selected"
jq -e '.success==true' "$CFIP_PUBLISH_STATUS_FILE" >/dev/null
echo 'PASS actual isolated uhttpd serves exact published bytes'
prefix="$(jq -r '.generationPath' "$CFIP_PUBLISH_DIR/result.json")"
while IFS=$'\t' read -r name hash; do
 curl --noproxy '*' -fsS --connect-timeout 1 --max-time 2 "http://$CFIP_PUBLISH_BIND:$CFIP_PUBLISH_PORT$prefix/$name" -o "$TMP/download"
 test "$(sha256sum "$TMP/download" | awk '{print $1}')" = "$hash"
done < <(jq -r '.artifacts|to_entries[]|[.key,.value.sha256]|@tsv' "$CFIP_PUBLISH_DIR/result.json")
echo 'PASS actual uhttpd serves pinned generation artifacts with matching digests'
cfip_publisher_status_json | jq -e '.success==true and .listenerReady==true' >/dev/null
# The independent backend command must read enabled state from a real isolated
# UCI configuration, rather than its process-default disabled flag.
mkdir -p "$TMP/config" "$TMP/delta"
cp /etc/config/cf_ip "$TMP/config/cf_ip"
export CFIP_UCI_CONFIG_DIR="$TMP/config" CFIP_UCI_DELTA_DIR="$TMP/delta"
uci(){ command uci -c "$CFIP_UCI_CONFIG_DIR" -P "$CFIP_UCI_DELTA_DIR" "$@"; }
export -f uci
uci set cf_ip.lan.enabled=1
uci set "cf_ip.lan.bind_address=$CFIP_PUBLISH_BIND"
uci set "cf_ip.lan.port=$CFIP_PUBLISH_PORT"
uci commit cf_ip
CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip" bash "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2" --publisher-status >"$TMP/command-status"
jq -e '.success==true and .listenerReady==true' "$TMP/command-status" >/dev/null
echo 'PASS backend publisher-status loads real isolated UCI enabled state'
unset -f uci
CFIP_PUBLISH_ENABLED=false
cfip_publish_result "$TMP/selected"
jq -e '.success==false and .state=="disabled" and .listenerReady==false' "$CFIP_PUBLISH_STATUS_FILE" >/dev/null
CFIP_PUBLISH_READY_ATTEMPTS=1
if cfip_publisher_wait_ready "$CFIP_PUBLISH_BIND" "$CFIP_PUBLISH_PORT" "$CFIP_PUBLISH_DIR/result.json"; then echo 'FAIL stopped uhttpd reported ready'; exit 1; fi
echo 'PASS stopped actual uhttpd fails readiness'
