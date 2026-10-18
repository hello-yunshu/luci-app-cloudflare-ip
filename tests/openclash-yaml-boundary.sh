#!/usr/bin/env bash
# Mixed supported/unsupported syntax must not yield a partial mapping success.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/openclash-readback.sh"
cat >"$TMP/mixed.yaml" <<'YAML'
proxies:
  - name: Supported
    type: vmess
    server: cdn.example.com
    tls: true
    network: ws
  - {name: Hidden, type: vmess, server: cdn.example.com, tls: true, network: ws}
YAML
if cfip_openclash_actual_mapping "$TMP/mixed.yaml" "$TMP/mapping.json"; then
    echo "FAIL: mixed YAML accepted with only $(jq length "$TMP/mapping.json") mapped proxy" >&2
    exit 1
fi
echo 'PASS unsupported mixed YAML rejected before partial mapping output'
head -6 "$TMP/mixed.yaml" >"$TMP/supported.yaml"
cfip_openclash_actual_mapping "$TMP/supported.yaml" "$TMP/positive.json"
jq -e 'length==1 and .[0].name=="Supported"' "$TMP/positive.json" >/dev/null
for form in alias merge folded flow-root; do
    head -6 "$TMP/mixed.yaml" >"$TMP/$form.yaml"
    case "$form" in
        alias) printf '  - *hidden\n' >>"$TMP/$form.yaml" ;;
        merge) printf '    <<: *defaults\n' >>"$TMP/$form.yaml" ;;
        folded) printf '    servername: >\n      cdn.example.com\n' >>"$TMP/$form.yaml" ;;
        flow-root) printf 'proxies: [{name: Hidden}]\n' >"$TMP/$form.yaml" ;;
    esac
    if cfip_openclash_actual_mapping "$TMP/$form.yaml" "$TMP/$form.json"; then echo "accepted unsupported $form" >&2; exit 1; fi
    [[ ! -e "$TMP/$form.json" ]]
done
echo 'PASS supported block mapping and unsupported alias/merge/folded/flow-root boundaries'
