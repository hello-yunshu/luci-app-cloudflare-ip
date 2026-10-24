#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# == 0 ]]; then
    rc=0
    for entry in common legacy standalone; do
        bash "$0" "$entry" || rc=1
    done
    exit "$rc"
fi
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
case "$1" in
    common) source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"; probe=cfip_openclash_health_once ;;
    legacy) source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-legacy"; probe=openclash_health_once ;;
    standalone) source "$ROOT/cf-openwrt-auto.sh"; probe=openclash_health_once ;;
    *) exit 2 ;;
esac
CFIP_OPENCLASH_CONFIG="$TMP/proxies.yaml"; OPENCLASH_CONFIG="$CFIP_OPENCLASH_CONFIG"
printf 'proxies: []\n' >"$CFIP_OPENCLASH_CONFIG"
credential=fixture-controller-secret; expected="$credential"; calls=0
uci() {
    case "${*: -1}" in
        openclash.config.cn_port) printf 9090 ;;
        openclash.config.dashboard_password) [[ "$credential" != missing ]] || return 1; printf '%s' "$credential" ;;
        *) return 1 ;;
    esac
}
pidof() { printf '1234\n'; }
curl() {
    local config='' output=''
    while (($#)); do
        case "$1" in --config) config="$2"; shift 2 ;; --output) output="$2"; shift 2 ;; *) shift ;; esac
    done
    # This fixture does not accept an unauthenticated request for a protected controller.
    if [[ -n "$expected" ]]; then grep -qF "Authorization: Bearer $expected" "$config" || return 22
    else [[ ! -s "$config" ]] || return 22; fi
    printf 'called\n' >>"$TMP/curl-calls"
    printf '{"proxies":{}}' >"$output"; printf 200
}
if ! "$probe" 1; then echo "FAIL $1: proxies fragment cannot authenticate with OpenClash UCI credential" >&2; exit 1; fi
# A selected full YAML's existing credential retains precedence.
printf 'secret: yaml-secret\nproxies: []\n' >"$CFIP_OPENCLASH_CONFIG"
expected=yaml-secret
"$probe" 1
printf 'proxies: []\n' >"$CFIP_OPENCLASH_CONFIG"
credential=missing; expected=''
"$probe" 1
# An unsafe UCI credential must be refused before curl is called.
credential=$'unsafe\nheader'; expected="$credential"
before="$(wc -l <"$TMP/curl-calls")"
if "$probe" 1; then echo "FAIL $1: multiline credential accepted" >&2; exit 1; fi
[[ "$(wc -l <"$TMP/curl-calls")" == "$before" ]]
echo "PASS $1: UCI fragment fallback, YAML precedence, no-auth controller and unsafe credential rejection"
