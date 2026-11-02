#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/openclash-readback.sh"
declare -f cfip_openclash_yaml_supported >"$TMP/canonical"
for engine in "$ROOT/cf-openwrt-auto.sh" "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-legacy"; do
    name="$(basename "$engine")"; case_dir="$TMP/$name"; mkdir -p "$case_dir"
    config="$case_dir/config.yaml"
    cat >"$config" <<'YAML'
proxies:
  - name: Supported
    type: vmess
    server: cdn.example.com
    tls: true
    network: ws
  - {name: Hidden, type: vmess, server: cdn.example.com, tls: true, network: ws}
YAML
    cp "$config" "$case_dir/before"
    if (
        source "$engine"
        declare -f cfip_openclash_yaml_supported >"$case_dir/definition"
        OPENCLASH_CONFIG="$config"; OPENCLASH_TARGET_DOMAIN=cdn.example.com
        FAST_IPS=(104.16.1.1); IP_COUNT=1; PURE_APPLY=true
        openclash_check_before_write() { :; }
        update_openclash
    ) >"$case_dir/result.log" 2>&1; then echo "unsupported YAML accepted by $name" >&2; exit 1; fi
    grep -q 'unsupported OpenClash proxy YAML' "$case_dir/result.log"
    cmp "$TMP/canonical" "$case_dir/definition"
    cmp "$config" "$case_dir/before"
    [[ "$(find "$case_dir" -name '*.bak.*' -o -name '*.tmp.*' | wc -l | tr -d ' ')" == 0 ]]
    echo "PASS $name rejects unsupported input before backup/temp/publication"
done
