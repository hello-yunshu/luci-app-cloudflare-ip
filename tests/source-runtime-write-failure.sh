#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP/status" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_SOURCE_RUNTIME_DIR="$TMP/runtime/sources" CFIP_SOURCE_CACHE_DIR="$TMP/cache"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "${CFIP_TEST_SOURCE:-$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh}"
CFIP_SOURCE_CURL_MAX_FILESIZE_SUPPORTED=false
curl(){ printf '104.18.1.1\n104.18.1.2\n'; }
cfip_source_fetch_remote writes https://one.example/list ip-text ipv4 community "$TMP/result"
# Reject runtime metadata publication only. Qualified persistent cache remains writable.
mv(){ if [[ "${*: -1}" == "$CFIP_SOURCE_RUNTIME_DIR/writes/metadata.json" ]]; then return 1; fi; command mv "$@"; }
for mode in fresh cached; do
 if [[ "$mode" == cached ]]; then curl(){ return 22; }; fi
 rc=0; cfip_source_fetch_remote writes https://one.example/list ip-text ipv4 community "$TMP/result" || rc=$?
 test "$rc" != 0 || { echo "FAIL $mode status write failure returned success"; exit 1; }
 echo "PASS $mode status write failure rejects success"
done
unset -f mv
curl(){ return 22; }
cfip_source_fetch_remote writes https://one.example/list ip-text ipv4 community "$TMP/result"
jq -e '.fromCache==true and .success==true' "$CFIP_SOURCE_RUNTIME_DIR/writes/metadata.json" >/dev/null
echo 'PASS qualified cache remains usable after runtime write failure'

# Output publication failure must not publish a new success status first.
cp "$CFIP_SOURCE_RUNTIME_DIR/writes/metadata.json" "$TMP/status-before"
mv(){ if [[ "${*: -1}" == "$TMP/result" ]]; then return 1; fi; command mv "$@"; }
for mode in fresh cached; do
 if [[ "$mode" == fresh ]]; then curl(){ printf '104.18.1.1\n104.18.1.2\n'; }; else curl(){ return 22; }; fi
 rc=0; cfip_source_fetch_remote writes https://one.example/list ip-text ipv4 community "$TMP/result" || rc=$?
 test "$rc" != 0
 cmp "$TMP/status-before" "$CFIP_SOURCE_RUNTIME_DIR/writes/metadata.json"
 echo "PASS $mode output write failure rejects success without publishing success status"
done
unset -f mv
# A rejected refresh must not reintroduce a preexisting records file into the pool.
cfip_source_fetch_remote(){ printf '[{"kind":"ip","value":"104.18.9.9","family":"ipv4"}]' >"$6"; return 1; }
CFIP_BUILTIN_SOURCES=cloudflare-official-v4
cfip_collect_enabled_sources "$TMP/pool" "$TMP/source-status"
test "$(jq length "$TMP/pool")" = 0
echo 'PASS collector excludes records from rejected refresh'

uci(){
 [[ "$1" != -q ]] || shift
 case "$1" in
  show) echo 'cf_ip.failed=source' ;;
  get) case "$2" in
   *.enabled) echo 1 ;; *.kind) echo url ;; *.family) echo ipv4 ;; *.parser) echo ip-text ;; *.source_class) echo community ;; *.url) echo https://one.example/list ;;
  esac ;;
 esac
}
cfip_collect_enabled_sources "$TMP/pool" "$TMP/source-status"
test "$(jq length "$TMP/pool")" = 0
echo 'PASS collector excludes rejected custom source records'
