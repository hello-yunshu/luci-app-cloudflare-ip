#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat >"$TMP/good.yaml" <<'YAML'
proxies:
  - name: "Node # literal"
    type: vmess
    server: cdn.example.com
    tls: true
    network: ws
    ws-opts:
      path: /ws
proxy-groups:
  - name: Selector
    type: select
    proxies: ["Node # literal"]
rules:
  - MATCH,Selector
YAML
cp "$TMP/good.yaml" "$TMP/malformed.yaml"
printf 'broken: [SENSITIVE_TEST_TOKEN\n' >>"$TMP/malformed.yaml"
cp "$TMP/good.yaml" "$TMP/duplicate-root.yaml"; printf 'rules: []\n' >>"$TMP/duplicate-root.yaml"
sed '/      path: \/ws/a\      path: /different' "$TMP/good.yaml" >"$TMP/duplicate-nested.yaml"
sed 's/server: cdn.example.com/server: "cdn\\u002eexample.com"/' "$TMP/good.yaml" >"$TMP/escaped-scalar.yaml"
sed 's/server: cdn.example.com/"server": cdn.example.com/' "$TMP/good.yaml" >"$TMP/quoted-key.yaml"
sed 's/server: cdn.example.com/server: cdn.example.com # comment/' "$TMP/good.yaml" >"$TMP/mapped-comment.yaml"
cp "$TMP/good.yaml" "$TMP/multiple-documents.yaml"; printf '\n---\nother: 1\n' >>"$TMP/multiple-documents.yaml"
cp "$TMP/good.yaml" "$TMP/typed-key.yaml"; printf 'yes: 1\n' >>"$TMP/typed-key.yaml"
sed 's/^  //' "$TMP/good.yaml" >"$TMP/unindented-sequence.yaml"
for engine in "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/openclash-readback.sh" \
    "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-legacy" "$ROOT/cf-openwrt-auto.sh"; do
    (
    source "$engine"
    cfip_openclash_yaml_supported "$TMP/good.yaml"
    for invalid in malformed duplicate-root duplicate-nested escaped-scalar quoted-key mapped-comment multiple-documents typed-key unindented-sequence; do
        if cfip_openclash_yaml_supported "$TMP/$invalid.yaml" >"$TMP/out" 2>"$TMP/reason"; then
            echo "accepted $invalid in $engine" >&2; exit 1
        fi
        grep -q 'unsupported OpenClash proxy YAML' "$TMP/reason"
        ! grep -q SENSITIVE_TEST_TOKEN "$TMP/reason"
    done
    command() { if [[ "${1:-}" == -v && "${2:-}" == ruby ]]; then return 1; else builtin command "$@"; fi; }
    if cfip_openclash_yaml_supported "$TMP/good.yaml" 2>"$TMP/missing-ruby"; then echo 'missing parser accepted' >&2; exit 1; fi
    unset -f command
    grep -q 'Ruby/Psych is required' "$TMP/missing-ruby"
    echo "PASS document syntax, duplicate keys, scalar representation and missing parser: $(basename "$engine")"
    )
done

for engine in "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-legacy" "$ROOT/cf-openwrt-auto.sh"; do
    (
    source "$engine"
    restart_service() { :; }
    openclash_check_before_write() { :; }; openclash_check_config() { :; }
    PURE_APPLY=true
    OPENCLASH_CONFIG="$TMP/$(basename "$engine")-quoted-name.yaml"
    cp "$TMP/good.yaml" "$OPENCLASH_CONFIG"
    OPENCLASH_TARGET_DOMAIN=cdn.example.com; OPENCLASH_TRANSPORT_FILTER=''
    OPENCLASH_NAME_SUFFIX=' [CF-{n}]'; FAST_IPS=(104.16.1.1); IP_COUNT=1
    update_openclash
    ruby -rpsych -e 'raise "name changed meaning" unless Psych.safe_load_file(ARGV[0])["proxies"][0]["name"] == "Node # literal [CF-1]"' "$OPENCLASH_CONFIG"
    echo "PASS quoted literal comment character survives transformation: $(basename "$engine")"
    for label in 'A: B' '[Bracket]' ' Leading' '123'; do
        OPENCLASH_CONFIG="$TMP/$(basename "$engine")-scalar-name.yaml"
        ruby -e 'text=File.read(ARGV[0]); File.write(ARGV[1],text.sub(/^  - name:.*$/,"  - name: "+ARGV[2].dump))' "$TMP/good.yaml" "$OPENCLASH_CONFIG" "$label"
        update_openclash
        ruby -rpsych -e 'raise "name changed meaning" unless Psych.safe_load_file(ARGV[0])["proxies"][0]["name"] == ARGV[1]+" [CF-1]"' "$OPENCLASH_CONFIG" "$label"
    done
    echo "PASS generated colon, bracket, whitespace and numeric names retain string meaning: $(basename "$engine")"
    restart_service() { echo 'unexpected service restart' >&2; exit 99; }
    OPENCLASH_CONFIG="$TMP/$(basename "$engine")-malformed-output.yaml"
    cp "$TMP/good.yaml" "$OPENCLASH_CONFIG"; cp "$OPENCLASH_CONFIG" "$TMP/before"
    OPENCLASH_TARGET_DOMAIN=cdn.example.com; OPENCLASH_TRANSPORT_FILTER=''
    OPENCLASH_NAME_SUFFIX=$' [CF-{n}]\nbroken: ['
    FAST_IPS=(104.16.1.1); IP_COUNT=1
    if (update_openclash) >"$TMP/render-out" 2>"$TMP/render-error"; then echo 'malformed generated YAML published' >&2; exit 1; fi
    cmp "$OPENCLASH_CONFIG" "$TMP/before"
    ! compgen -G "$OPENCLASH_CONFIG.tmp.*" >/dev/null
    ! compgen -G "$OPENCLASH_CONFIG.bak.*" >/dev/null
    grep -q 'rendered OpenClash YAML is unsupported' "$TMP/render-error"
    echo "PASS malformed generated document refuses before backup or publication: $(basename "$engine")"
    )
done
