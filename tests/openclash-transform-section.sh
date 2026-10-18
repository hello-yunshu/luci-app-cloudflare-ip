#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
for engine in "$ROOT/cf-openwrt-auto.sh" "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-legacy"; do
    (
    source "$engine"
    restart_service() { :; }
    openclash_check_before_write() { :; }
    PURE_APPLY=true
    OPENCLASH_CONFIG="$TMP/$(basename "$engine").yaml"
    OPENCLASH_TARGET_DOMAIN=cdn.example.com
    OPENCLASH_NAME_SUFFIX=' [CF-{n}]'
    OPENCLASH_TRANSPORT_FILTER=''
    FAST_IPS=(104.16.1.1 104.16.1.2); IP_COUNT=2
    cat >"$OPENCLASH_CONFIG" <<'YAML'
proxies:
  - name: Node
    type: vmess
    server: cdn.example.com
    tls: true
    network: ws
proxy-groups:
  - name: Selector
    type: select
    proxies:
      - Node
rules:
  - MATCH,Selector
YAML
    sed -n '/^proxy-groups:/,$p' "$OPENCLASH_CONFIG" >"$TMP/outside-before"
    update_openclash
    update_openclash
    sed -n '/^proxy-groups:/,$p' "$OPENCLASH_CONFIG" >"$TMP/outside-after"
    cmp "$TMP/outside-before" "$TMP/outside-after" || { echo "FAIL: $engine changed non-proxy sections" >&2; exit 1; }
    [[ "$(grep -c '^proxy-groups:' "$OPENCLASH_CONFIG")" == 1 ]]
    [[ "$(grep -c 'server: 104.16.1.' "$OPENCLASH_CONFIG")" == 2 ]]
    echo "PASS scoped transformer: $(basename "$engine")"
    )
done
