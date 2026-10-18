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
cp "$TMP/supported.yaml" "$TMP/with-groups.yaml"
cat >>"$TMP/with-groups.yaml" <<'YAML'
proxy-groups:
  - name: User selector
    type: select
    proxies:
      - Supported
YAML
cfip_openclash_actual_mapping "$TMP/with-groups.yaml" "$TMP/group-mapping.json"
jq -e 'length==1 and .[0].name=="Supported"' "$TMP/group-mapping.json" >/dev/null || { echo 'FAIL proxy-group parsed as a proxy node' >&2; exit 1; }
echo 'PASS mapping is scoped to the top-level proxies section'
cp "$TMP/supported.yaml" "$TMP/duplicate-server.yaml"
printf '    server: external.example.com\n' >>"$TMP/duplicate-server.yaml"
if cfip_openclash_actual_mapping "$TMP/duplicate-server.yaml" "$TMP/duplicate-server.json"; then echo 'FAIL duplicate server field silently accepted' >&2; exit 1; fi
echo 'PASS duplicate mapping field rejected'
for field in type tls network servername Host; do
    cp "$TMP/supported.yaml" "$TMP/duplicate-$field.yaml"
    printf '    %s: repeated\n    %s: repeated\n' "$field" "$field" >>"$TMP/duplicate-$field.yaml"
    if cfip_openclash_actual_mapping "$TMP/duplicate-$field.yaml" "$TMP/duplicate-$field.json" 2>"$TMP/reason"; then echo "accepted duplicate $field" >&2; exit 1; fi
    grep -q "duplicate mapped field $field" "$TMP/reason"
    [[ ! -e "$TMP/duplicate-$field.json" ]]
done
grep -v '    type:' "$TMP/supported.yaml" >"$TMP/nested-type.yaml"
printf '    metadata:\n      type: vmess\n' >>"$TMP/nested-type.yaml"
if cfip_openclash_actual_mapping "$TMP/nested-type.yaml" "$TMP/nested-type.json" 2>"$TMP/reason"; then echo 'accepted nested proxy type' >&2; exit 1; fi
grep -q 'nested mapped field type' "$TMP/reason"
echo 'PASS duplicate mapped fields and nested proxy type reject with specific reasons'
