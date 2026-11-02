#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/package/luci-app-cloudflare-ip/root/etc/init.d/cf_ip_publisher"
config_load(){ :; }
config_get_bool(){ eval "$1=$ENABLED"; }
config_get(){ case "$3" in bind_address) eval "$1=\$BIND";; port) eval "$1=\$PORT";; esac; }
get_lan_ipv4(){ printf '10.0.2.15\n'; }
logger(){ :; }
# rc.common runs close-service after start_service, then its final callback.
native_start(){ start_service || true; :; service_started; }
ENABLED=0; BIND=0.0.0.0; PORT=18087
native_start
echo 'PASS disabled publisher is a successful no-op'
ENABLED=1
for BIND in 0.0.0.0 127.0.0.1 8.8.8.8 10.0.2.16 '::1'; do
 if native_start; then echo "invalid bind reported success: $BIND" >&2;exit 1;fi
done
echo 'PASS invalid, foreign and IPv6 binds retain failure through final callback'
BIND=10.0.2.15
for PORT in 0 80 65536 invalid; do
 if native_start; then echo "invalid port reported success: $PORT" >&2;exit 1;fi
done
echo 'PASS invalid publisher ports retain failure through final callback'
