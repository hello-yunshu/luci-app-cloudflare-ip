#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP/status" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_SOURCE_RUNTIME_DIR="$TMP/runtime/sources" CFIP_SOURCE_CACHE_DIR="$TMP/cache"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "${CFIP_TEST_SOURCE:-$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh}"
CFIP_SOURCE_CURL_MAX_FILESIZE_SUPPORTED=false
printf '104.18.1.1\n104.18.1.2\n' >"$TMP/remote"
curl(){ cat "$TMP/remote"; }
cfip_source_fetch_remote trust https://one.example/list ip-text ipv4 community "$TMP/result"
cp -R "$CFIP_SOURCE_CACHE_DIR/trust" "$TMP/pristine"
curl(){ return 22; }
for scenario in valid bare legacy hash url parser family class id expired future oversized malformed; do
 rm -rf "$CFIP_SOURCE_CACHE_DIR/trust"
 cp -R "$TMP/pristine" "$CFIP_SOURCE_CACHE_DIR/trust"
 dir="$CFIP_SOURCE_CACHE_DIR/trust"; meta="$dir/metadata.json"
 case "$scenario" in
  bare) rm "$meta" ;;
  legacy) jq ' .schemaVersion=1' "$meta" >"$meta.next"; mv "$meta.next" "$meta" ;;
  hash) printf '104.18.9.1\n104.18.9.2\n' >"$dir/last-good.txt" ;;
  url) jq '.url="https://other.example/list"' "$meta" >"$meta.next"; mv "$meta.next" "$meta" ;;
  parser) jq '.parser="cidr"' "$meta" >"$meta.next"; mv "$meta.next" "$meta" ;;
  family) jq '.family="ipv6"' "$meta" >"$meta.next"; mv "$meta.next" "$meta" ;;
  class) jq '.sourceClass="official"' "$meta" >"$meta.next"; mv "$meta.next" "$meta" ;;
  id) jq '.id="other"' "$meta" >"$meta.next"; mv "$meta.next" "$meta" ;;
  expired) jq '.lastSuccessAt=(now-604801)' "$meta" >"$meta.next"; mv "$meta.next" "$meta" ;;
  future) jq '.lastSuccessAt=(now+3600)' "$meta" >"$meta.next"; mv "$meta.next" "$meta" ;;
  oversized) head -c 524289 /dev/zero >"$dir/last-good.txt" ;;
  malformed) printf 'broken' >"$meta" ;;
 esac
 rc=0; cfip_source_fetch_remote trust https://one.example/list ip-text ipv4 community "$TMP/result" || rc=$?
 if [[ "$scenario" == valid ]]; then
  test "$rc" = 0; test "$(jq length "$TMP/result")" = 2
 else
  test "$rc" != 0 || { echo "FAIL untrusted cache accepted: $scenario"; exit 1; }
  test "$(jq length "$TMP/result")" = 0
  jq -e '.success==false and .fromCache==false and .cacheError=="cache_unqualified"' "$CFIP_SOURCE_RUNTIME_DIR/trust/metadata.json" >/dev/null
 fi
 echo "PASS source cache $scenario"
done
# A successful byte-identical refresh must renew age and recover modified disk bytes.
curl(){ cat "$TMP/remote"; }
cfip_source_fetch_remote trust https://one.example/list ip-text ipv4 community "$TMP/result"
meta="$CFIP_SOURCE_CACHE_DIR/trust/metadata.json"
jq '.lastSuccessAt=1' "$meta" >"$meta.next"; mv "$meta.next" "$meta"
printf '104.18.9.1\n104.18.9.2\n' >"$CFIP_SOURCE_CACHE_DIR/trust/last-good.txt"
cfip_source_fetch_remote trust https://one.example/list ip-text ipv4 community "$TMP/result"
cmp "$TMP/remote" "$CFIP_SOURCE_CACHE_DIR/trust/last-good.txt"
jq -e '.lastSuccessAt > now-60' "$meta" >/dev/null
echo 'PASS source cache same-bytes refresh renews age and repairs changed bytes'
