#!/usr/bin/env bash
# Real procd/uhttpd fixture: the production init script is started by procd,
# its registered interface trigger is asserted, and the exact command that
# procd would run (the init script's reload) rebinds the real listener.
# Interface addresses and private-policy fixtures use loopback so no real
# network configuration is changed. Synthetic ubus event dispatch is not used
# because procd in this container does not deliver it; trigger registration is
# asserted instead.
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
reachable(){
 local code
 code="$(curl --noproxy '*' -sS --connect-timeout 2 --max-time 2 -o /dev/null -w '%{http_code}' "http://$1:$port/" 2>/dev/null || true)"
 # Any HTTP status (including 403/404 from an empty docroot) proves the
 # listener is up; curl's own timeout must not be mistaken for "down".
 [[ -n "$code" && "$code" != 000 ]]
}
wait_up(){ for _ in {1..8}; do if reachable "$1"; then return 0; fi; sleep 1; done; echo "FAIL listener not reachable at $1"; return 1; }
wait_down(){ for _ in {1..8}; do if ! reachable "$1"; then return 0; fi; sleep 1; done; echo "FAIL listener remained reachable at $1"; return 1; }
printf 1 >"$TMP/enabled"
status true 127.0.0.1
"$fixture" start
wait_up 127.0.0.1 || exit 1
echo 'PASS real procd fixture starts actual HTTP listener'
ubus call service list "{\"name\":\"$name\",\"verbose\":true}" | jq -e --arg name "$name" --arg script "$fixture" \
 '.[$name].triggers | any(.[]; .[0]=="interface.*" and .[1][1][0]=="eq" and .[1][1][1]=="interface" and .[1][1][2]==$name and .[1][2][0]=="run_script" and .[1][2][1]==$script and .[1][2][2]=="reload")' >/dev/null
echo 'PASS procd registers the production interface trigger for this fixture'
status true 127.0.0.2
"$fixture" reload
wait_up 127.0.0.2 || exit 1
wait_down 127.0.0.1 || exit 1
ubus call service list "{\"name\":\"$name\"}" | jq -e --arg name "$name" --arg bind "127.0.0.2:$port" '.[$name].instances|any(.[]; .running==true and (.command|index($bind)!=null))' >/dev/null
echo 'PASS trigger reload rebinds owned listener and closes old address'
status false 127.0.0.2
# The production init returns non-zero when no LAN bind can be resolved, but
# procd still applies the resulting empty instance set.
"$fixture" reload || true
wait_down 127.0.0.2 || exit 1
echo 'PASS interface loss removes actual listener'
status true 127.0.0.1
"$fixture" reload
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
