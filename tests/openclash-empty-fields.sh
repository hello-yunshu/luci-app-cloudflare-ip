#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/openclash-readback.sh"
cat >"$TMP/config.yaml" <<'EOF_YAML'
proxies:
  - name: Empty TLS [CF-1]
    type: vless
    server: domain.example
    network: ws
    ws-opts:
      headers:
        Host: domain.example
  - name: Explicit false [CF-2]
    type: vmess
    server: other.example
    tls: false
    network: grpc
    servername: other.example
EOF_YAML
cfip_openclash_actual_mapping "$TMP/config.yaml" "$TMP/actual.json"
jq -e 'length==2 and .[0].tls=="" and .[0].network=="ws" and .[0].host=="domain.example" and .[1].tls=="false" and .[1].network=="grpc" and .[1].servername=="other.example"' "$TMP/actual.json" >/dev/null
printf '%s\n' '[{"ip":"104.16.1.1","family":"ipv4"}]' >"$TMP/selected.json"
cfip_openclash_intended_from_templates "$TMP/selected.json" "$TMP/config.yaml" domain.example ' [CF-{n}]' ws "$TMP/intended.json"
jq -e 'length==1 and .[0].server=="104.16.1.1" and .[0].servername=="domain.example" and .[0].network=="ws" and .[0].host=="domain.example"' "$TMP/intended.json" >/dev/null
echo 'OpenClash mapping parser preserves empty TLS fields in shared intended and actual decoding'