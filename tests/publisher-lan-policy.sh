#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/package/luci-app-cloudflare-ip/root/etc/init.d/cf_ip_publisher"
for valid in 10.0.0.1 172.16.0.1 172.31.255.254 192.168.1.1; do
 is_private_ipv4 "$valid"
done
for bad in 172.15.0.1 172.32.0.1 192.169.1.1 127.0.0.1 0.0.0.0 '10.1.1.1.1'; do
 if is_private_ipv4 "$bad"; then echo "FAIL private address policy accepted $bad"; exit 1; fi
done
get_lan_ipv4(){ [ "$up" = true ] || return 1; printf '%s\n' "$fixture_addresses"; }
up=true; fixture_addresses='192.168.1.1
10.8.0.1'
[ "$(resolve_lan_bind '')" = 192.168.1.1 ]
[ "$(resolve_lan_bind 10.8.0.1)" = 10.8.0.1 ]
for bad in 192.168.99.1 0.0.0.0 127.0.0.1 8.8.8.8 ::1 192.168.1.256 192.168.01.1 '192.168.evil.bad'; do
 if resolve_lan_bind "$bad"; then echo "FAIL accepted invalid/foreign address: $bad"; exit 1; fi
done
for bad in 192.168.1.256 192.168.01.1 10.999.1.1 172.16.0.999 '192.168.evil.bad' '10.1.1.'; do
 fixture_addresses="$bad"
 if resolve_lan_bind ''; then echo "FAIL auto-selected malformed address: $bad"; exit 1; fi
done
fixture_addresses=192.168.2.1
[ "$(resolve_lan_bind '')" = 192.168.2.1 ]
if resolve_lan_bind 192.168.1.1; then echo 'FAIL accepted old address after LAN change'; exit 1; fi
up=false
if resolve_lan_bind ''; then echo 'FAIL accepted unavailable LAN'; exit 1; fi
triggers=''
procd_add_reload_trigger(){ :; }
procd_add_interface_trigger(){ triggers="$*"; }
initscript=/fixture/publisher
service_triggers
[ "$triggers" = 'interface.* lan /fixture/publisher reload' ]
echo 'PASS publisher LAN ownership, strict IPv4, address-change/loss and interface trigger policy (mock network status)'
