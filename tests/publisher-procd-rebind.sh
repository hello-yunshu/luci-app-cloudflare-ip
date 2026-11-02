#!/usr/bin/env bash
# Real procd/uhttpd + event dispatch; interface addresses and private-policy
# fixtures use loopback to avoid changing any real network configuration.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -x /usr/sbin/uhttpd && -x /etc/rc.common ]] || { echo 'UNAVAILABLE: isolated OpenWrt procd/uhttpd runtime required'; exit 77; }
TMP="$(mktemp -d)"; name="cfip-lan-fixture-$$"; fixture="$TMP/$name"
cleanup(){ local rc=$?; trap - EXIT; [[ ! -x "$fixture" ]] || "$fixture" stop >/dev/null 2>&1 || true; if [[ -n "${CFIP_PROCD_TRACE_LOG:-}" && -f "$TMP/init-trace" ]]; then cp "$TMP/init-trace" "$CFIP_PROCD_TRACE_LOG" || true; fi; rm -rf "$TMP"; exit "$rc"; }
trap cleanup EXIT
port="$((32000+RANDOM%16000))"
init_source="${CFIP_TEST_PUBLISHER_INIT:-$ROOT/package/luci-app-cloudflare-ip/root/etc/init.d/cf_ip_publisher}"
cat >"$fixture" <<INIT
#!/bin/sh /etc/rc.common
. '$init_source'
if [ '${CFIP_PROCD_TRACE_LOG:-}' != '' ]; then exec 2>>'$TMP/init-trace'; set -x; fi
ubus(){
 [ "\$1" != -t ] || shift 2
 if [ "\$1 \${2:-}" = 'call network.interface.lan' ]; then
  cat '$TMP/network.json'
 elif [ "\$1 \${2:-} \${3:-}" = 'call service set' ]; then
  # Isolate the interface name at the RPC boundary; production trigger code runs.
  payload="\$(printf '%s' "\$4" | jq --arg interface '$name' '.triggers |= map(if .[0]=="interface.*" then .[1][1][2]=\$interface else . end)')"
  command ubus call service set "\$payload"
 else command ubus "\$@"; fi
}
# The production private-address policy is separately tested unchanged.
is_private_ipv4(){ case "\$1" in 127.0.0.1|127.0.0.2) return 0 ;; *) return 1 ;; esac; }
config_load(){ :; }
config_get_bool(){ eval "\$1=\$(cat '$TMP/enabled')"; }
config_get(){ case "\$3" in bind_address) eval "\$1=''" ;; port) eval "\$1=$port" ;; esac; }
INIT
chmod +x "$fixture"
status(){ printf '{"up":%s,"ipv4-address":[{"address":"%s"}]}' "$1" "$2" >"$TMP/next"; mv "$TMP/next" "$TMP/network.json"; }
reachable(){ curl --noproxy '*' -sS --connect-timeout 1 --max-time 1 -o /dev/null "http://$1:$port/" 2>/dev/null; }
wait_up(){ for _ in {1..8}; do if reachable "$1"; then return 0; fi; sleep 1; done; echo "FAIL listener not reachable at $1"; return 1; }
wait_down(){ for _ in {1..8}; do if ! reachable "$1"; then return 0; fi; sleep 1; done; echo "FAIL listener remained reachable at $1"; return 1; }
printf 1 >"$TMP/enabled"
status true 127.0.0.1
"$fixture" start
wait_up 127.0.0.1 || exit 1
echo 'PASS real procd fixture starts actual HTTP listener'
status true 127.0.0.2
ubus call service event "{\"type\":\"interface.update\",\"data\":{\"interface\":\"$name\"}}"
wait_up 127.0.0.2 || exit 1
wait_down 127.0.0.1 || exit 1
ubus call service list "{\"name\":\"$name\"}" | jq -e --arg name "$name" --arg bind "127.0.0.2:$port" '.[$name].instances|any(.[]; .running==true and (.command|index($bind)!=null))' >/dev/null
echo 'PASS real interface event rebinds owned listener and closes old address'
status false 127.0.0.2
ubus call service event "{\"type\":\"interface.update\",\"data\":{\"interface\":\"$name\"}}"
wait_down 127.0.0.2 || exit 1
echo 'PASS interface loss removes actual listener'
status true 127.0.0.1
ubus call service event "{\"type\":\"interface.update\",\"data\":{\"interface\":\"$name\"}}"
wait_up 127.0.0.1 || exit 1
echo 'PASS interface restoration restarts actual listener through retained trigger'

# Exercise the native procd reload path with disabled configuration. Config
# reads remain isolated fixtures; this does not prove real-UCI event delivery.
printf 0 >"$TMP/enabled"
"$fixture" reload
wait_down 127.0.0.1 || exit 1
ubus call service list "{\"name\":\"$name\"}" | jq -e --arg name "$name" '[.[$name].instances[]? | select(.running==true)] | length==0' >/dev/null
echo 'PASS disabled reload removes real owned procd listener'
"$fixture" restart
wait_down 127.0.0.1 || exit 1
echo 'PASS disabled restart does not create a listener'
printf 1 >"$TMP/enabled"
"$fixture" reload
wait_up 127.0.0.1 || exit 1
echo 'PASS re-enabled reload restores actual listener'
