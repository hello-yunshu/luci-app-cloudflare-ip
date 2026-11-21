#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# == 0 ]]; then
    # Preserve the historical protocol matrix against the unshipped legacy
    # fixture. The current standalone entry point delegates mutations to its
    # packaged v2 provider and must reject safely when that provider is absent.
    bash "$0" "$repo_dir/tests/fixtures/legacy-cf-ip-auto"
    guard_dir="$(mktemp -d)"
    trap 'rm -rf "$guard_dir"' EXIT
    if CFIP_V2_BIN="$guard_dir/missing-cf-ip-auto" bash "$0" "$repo_dir/cf-openwrt-auto.sh" >"$guard_dir/output" 2>&1; then
        echo 'FAIL: standalone OpenClash unexpectedly applied without the packaged v2 provider' >&2
        exit 1
    fi
    grep -Fq 'standalone OpenClash apply requires the packaged v2 provider transaction' "$guard_dir/output"
    echo 'current standalone OpenClash safely refuses mutations without the packaged v2 provider'
    exit
fi
. "$1"
PURE_APPLY=true

restart_service() {
    :
}
openclash_check_before_write() { :; }
openclash_check_config() { :; }

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

OPENCLASH_CONFIG="$tmp_dir/clash-proxies.yaml"
OPENCLASH_NAME_SUFFIX=" [CF-{n}]"
OPENCLASH_TRANSPORT_FILTER=""
FAST_IPS=("104.16.1.1")
IP_COUNT=1

target_domains=()
for type in vless vmess trojan; do
    for network in ws xhttp grpc h2 http; do
        target_domains+=("${network}.${type}.proxy.example.com")
    done
done
OPENCLASH_TARGET_DOMAIN="$(IFS=,; printf '%s' "${target_domains[*]}")"

{
    printf 'proxies:\n'
    for type in vless vmess trojan; do
        for network in ws xhttp grpc h2 http; do
            domain="${network}.${type}.proxy.example.com"
            printf '  - name: %s-%s\n' "$type" "$network"
            printf '    type: %s\n' "$type"
            printf '    server: %s\n' "$domain"
            printf '    port: 443\n    tls: true\n'
            printf '    servername: %s\n' "$domain"
            printf '    network: %s\n' "$network"
            printf '    headers:\n      Host: %s\n' "$domain"
        done
    done
} >"$OPENCLASH_CONFIG"

update_openclash

test "$(grep -F -c 'server: 104.16.1.1' "$OPENCLASH_CONFIG")" -eq 15
test "$(grep -F -c 'servername:' "$OPENCLASH_CONFIG")" -eq 15
test "$(grep -E -c '^      Host:' "$OPENCLASH_CONFIG")" -eq 15
test "$(grep -E -c '^        Host:' "$OPENCLASH_CONFIG")" -eq 6
test "$(grep -F -c '[CF-1]' "$OPENCLASH_CONFIG")" -eq 15
test "$(find "$tmp_dir" -name 'clash-proxies.yaml.bak.*' | wc -l | tr -d ' ')" -eq 1

printf 'openclash protocol matrix passed\n'
