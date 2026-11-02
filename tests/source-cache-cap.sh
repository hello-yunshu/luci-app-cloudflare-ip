#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh"
CFIP_SOURCE_CACHE_DIR="$TMP/cache"
CFIP_SOURCE_CACHE_TOTAL_MAX_BYTES=$((16*1024*1024))
mkdir -p "$CFIP_SOURCE_CACHE_DIR/a" "$CFIP_SOURCE_CACHE_DIR/b" "$CFIP_SOURCE_CACHE_DIR/c"
for d in a b c; do
    head -c $((9*1024*1024)) /dev/zero >"$CFIP_SOURCE_CACHE_DIR/$d/last-good.json"
done
cfip_source_cache_enforce_total
total="$(cfip_source_cache_total_kb)"
((total <= 16*1024))
[[ "$(find "$CFIP_SOURCE_CACHE_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)" -lt 3 ]]
echo 'PASS source cache total cap prunes oldest cache directories'
