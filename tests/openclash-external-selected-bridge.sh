#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
export CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_STATUS_DIR="$TMP/status" CFIP_LOG_FILE="$TMP/log"
mkdir -p "$CFIP_RUNTIME_DIR" "$CFIP_STATUS_DIR"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"

CONFIG="$TMP/active.yaml"
SELECTED="$TMP/selected.json"
printf 'proxies: []\n' >"$CONFIG"
printf '[{"ip":"198.51.100.2","family":"ipv4"}]\n' >"$SELECTED"
CFIP_OPENCLASH_TARGET_DOMAIN='cdn.example.com,static.example.com'
CFIP_OPENCLASH_NAME_SUFFIX=' [CF-{n}]'
CFIP_OPENCLASH_TRANSPORT_FILTER='vless,vmess'

load_config() {
	[[ "${1:-}" != aux ]]
	CFIP_OPENCLASH_TARGET_DOMAIN='cdn.example.com,static.example.com'
	CFIP_OPENCLASH_NAME_SUFFIX=' [CF-{n}]'
	CFIP_OPENCLASH_TRANSPORT_FILTER='vless,vmess'
}
SYNC_ARGS=""
cmd_sync_explicit() {
	SYNC_ARGS="$*|$CFIP_BRIDGE_EXPECTED_CONFIG|$CFIP_TARGET_DOMAINS"
}

cmd_apply_selected_bridge "$SELECTED" openclash "$CONFIG" 'cdn.example.com, static.example.com' ' [CF-{n}]' 'vless,vmess'
[[ "$SYNC_ARGS" == "openclash $SELECTED|$CONFIG|cdn.example.com,static.example.com" ]]

SYNC_ARGS=""
if cmd_apply_selected_bridge "$SELECTED" openclash "$CONFIG" 'other.example.com' ' [CF-{n}]' 'vless,vmess' >"$TMP/mismatch.out" 2>&1; then
	echo 'FAIL: domain mismatch reached the transaction' >&2
	exit 1
fi
[[ -z "$SYNC_ARGS" ]]
grep -q 'target domains differ' "$TMP/mismatch.out"

printf '[{"ip":"198.51.100.2","family":"ipv4"},{"ip":"198.51.100.2","family":"ipv4"}]\n' >"$SELECTED"
if cmd_apply_selected_bridge "$SELECTED" openclash "$CONFIG" 'cdn.example.com,static.example.com' ' [CF-{n}]' 'vless,vmess' >"$TMP/invalid.out" 2>&1; then
	echo 'FAIL: malformed external candidates reached the transaction' >&2
	exit 1
fi
grep -q 'malformed or contains duplicate' "$TMP/invalid.out"

echo 'PASS v2 external selected bridge validates mode, file, domains, suffix and transport before transaction handoff'
