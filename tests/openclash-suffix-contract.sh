#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
LEGACY="$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-legacy"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/openclash-readback.sh"

cat >"$TMP/template.yaml" <<'YAML'
proxies:
  - name: Token One
    type: vless
    server: domain.example
    network: ws
    ws-opts:
      headers:
        Host: domain.example
YAML
printf '%s\n' '[{"ip":"104.16.1.1","family":"ipv4"},{"ip":"104.16.2.2","family":"ipv4"}]' >"$TMP/selected.json"

make_uci() {
    local suffix="$1" out="$2"
    cat >"$out" <<UCI
#!/bin/sh
args="\$*"
case "\$args" in
  *"get cf_ip.openclash.target_domain"*) echo domain.example ;;
  *"get cf_ip.openclash.name_suffix"*) printf '%s\n' '$suffix' ;;
  *"get cf_ip.openclash.config"*) echo /etc/openclash/config/config.yaml ;;
  *"get cf_ip.openclash.transport_filter"*) echo "" ;;
  *"get cf_ip.openclash.backup_count"*) echo 3 ;;
  *"get cf_ip.main.work_dir"*) echo /usr/bin ;;
  *"get "*) echo "" ;;
  *) exit 0 ;;
esac
UCI
    chmod +x "$out"
}

render() {
    local suffix="$1" template="$2" output="$3" uci_bin="$4"
    cp "$template" "$output"
    PATH="$(dirname "$uci_bin"):$PATH" CFIP_TEST_UCI="$uci_bin" \
      bash -c 'ln -sf "$CFIP_TEST_UCI" "$1/uci"; exec "$2" --render-selected "$3" "$4"' \
      sh "$(dirname "$uci_bin")" "$LEGACY" "$TMP/selected.json" "$output" >/dev/null
}

check_case() {
    local label="$1" suffix="$2" expected_count="$3" round template render_out intended actual
    make_uci "$suffix" "$TMP/uci-$label"
    template="$TMP/template.yaml"
    for round in 1 2; do
        render_out="$TMP/$label-render-$round.yaml"
        render "$suffix" "$template" "$render_out" "$TMP/uci-$label"
        intended="$TMP/$label-intended-$round.json"
        actual="$TMP/$label-actual-$round.json"
        cfip_openclash_intended_from_templates "$TMP/selected.json" "$template" domain.example "$suffix" ws "$intended"
        [[ "$(jq 'length' "$intended")" -eq "$expected_count" ]]
        cfip_openclash_actual_mapping "$render_out" "$actual"
        cfip_openclash_validate_mapping "$intended" "$actual"
        template="$render_out"
    done
    echo "PASS suffix='$suffix' first+rerun count=$expected_count"
}

check_case default ' [CF-{n}]' 2
check_case empty '' 1
check_case custom ' [Fast-{n}]' 2
check_case literal ' [Fast]' 1
