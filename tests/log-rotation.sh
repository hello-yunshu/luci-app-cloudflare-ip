#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
CFIP_LOG_FILE="$TMP/run.log"
CFIP_LOG_MAX_BYTES=100
head -c 140 /dev/zero | tr '\0' x >"$CFIP_LOG_FILE"
cfip_log 'rotation-marker'
[[ -f "$CFIP_LOG_FILE.1" ]]
[[ "$(wc -c <"$CFIP_LOG_FILE")" -le 100 ]]
grep -q 'rotation-marker' "$CFIP_LOG_FILE"
echo 'PASS log rotation caps the active log'
