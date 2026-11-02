#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(command mktemp -d)"; worker=""
cleanup(){
 if [[ -n "$worker" ]]; then kill -KILL "$worker" 2>/dev/null || true; wait "$worker" 2>/dev/null || true; fi
 rm -rf "$TMP"
}
trap cleanup EXIT
export CFIP_STATUS_DIR="$TMP/status" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_SOURCE_RUNTIME_DIR="$TMP/runtime/sources" CFIP_SOURCE_CACHE_DIR="$TMP/cache"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "${CFIP_TEST_SOURCE:-$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh}"
CFIP_SOURCE_CURL_MAX_FILESIZE_SUPPORTED=false
printf '104.18.1.1\n104.18.1.2\n' >"$TMP/old"
printf '104.18.9.1\n104.18.9.2\n' >"$TMP/new"
remote="$TMP/old"; curl(){ cat "$remote"; }
cfip_source_fetch_remote publish https://one.example/list ip-text ipv4 community "$TMP/result"
cp -R "$CFIP_SOURCE_CACHE_DIR/publish" "$TMP/pristine"
cache_bytes(){ if [[ -s "$CFIP_SOURCE_CACHE_DIR/publish/last-good.json" ]]; then jq -rj '.content' "$CFIP_SOURCE_CACHE_DIR/publish/last-good.json"; else cat "$CFIP_SOURCE_CACHE_DIR/publish/last-good.txt"; fi; }
# Inject failures at each private candidate stage, without breaking runtime status.
mktemp(){ if [[ "$fault" == allocation && "$*" == *'/.cache.'* ]]; then return 1; fi; command mktemp "$@"; }
jq(){
 if [[ "$fault" == render && "$*" == *--rawfile* ]]; then return 1; fi
 if [[ "$fault" == readback && "$*" == *'/.cache.'* && "$*" == *'.content'* ]]; then return 1; fi
 command jq "$@"
}
chmod(){ if [[ "$fault" == mode && "$*" == *'/.cache.'* ]]; then return 1; fi; command chmod "$@"; }
mv(){
 if [[ "$fault" == switch && "${*: -1}" == "$CFIP_SOURCE_CACHE_DIR/"* && ( "${*: -1}" == */metadata.json || "${*: -1}" == */last-good.json ) ]]; then return 1; fi
 command mv "$@"
}
for fault in allocation render readback mode switch; do
 rm -rf "$CFIP_SOURCE_CACHE_DIR/publish"; cp -R "$TMP/pristine" "$CFIP_SOURCE_CACHE_DIR/publish"
 remote="$TMP/new"; curl(){ cat "$remote"; }
 rc=0; cfip_source_fetch_remote publish https://one.example/list ip-text ipv4 community "$TMP/result" || rc=$?
 cache_bytes >"$TMP/observed"
 cmp "$TMP/old" "$TMP/observed" || { echo "FAIL $fault destroyed previous qualified cache"; exit 1; }
 test "$rc" = 0
 jq -e 'length==2 and .[0].value=="104.18.1.1"' "$TMP/result" >/dev/null
 jq -e '.fromCache==true and .lastError=="cache_publication_failed"' "$CFIP_SOURCE_RUNTIME_DIR/publish/metadata.json" >/dev/null
 test -z "$(find "$CFIP_SOURCE_CACHE_DIR/publish" -name '.cache.*' -print)"
 fault=none; curl(){ return 22; }
 cfip_source_fetch_remote publish https://one.example/list ip-text ipv4 community "$TMP/result"
 echo 'PASS source cache publication failure preserves previous qualified fallback'
done
unset -f mv mktemp jq chmod
# Kill the actual publisher immediately before and after its single rename.
export CFIP_COMMON="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
export CFIP_TEST_SOURCE="${CFIP_TEST_SOURCE:-$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh}"
export CFIP_NEW_FILE="$TMP/new" CFIP_READY="$TMP/ready"
for position in before after; do
 rm -rf "$CFIP_SOURCE_CACHE_DIR/publish"; cp -R "$TMP/pristine" "$CFIP_SOURCE_CACHE_DIR/publish"; rm -f "$CFIP_READY"
 export CFIP_KILL_POSITION="$position"
 bash -c '
  set -euo pipefail
  source "$CFIP_COMMON"; source "$CFIP_TEST_SOURCE"
  curl(){ cat "$CFIP_NEW_FILE"; }
  mv(){
   if [[ "${*: -1}" == "$CFIP_SOURCE_CACHE_DIR/publish/last-good.json" ]]; then
    [[ "$CFIP_KILL_POSITION" != after ]] || command mv "$@"
    : >"$CFIP_READY"; kill -STOP "$$"
   else command mv "$@"; fi
  }
  cfip_source_fetch_remote publish https://one.example/list ip-text ipv4 community "$CFIP_RUNTIME_DIR/killed-result"
 ' & worker=$!
 ready=false
 for _ in {1..10}; do
  if [[ -f "$CFIP_READY" ]]; then ready=true; break; fi
  if ! kill -0 "$worker" 2>/dev/null; then break; fi
  sleep 1
 done
 if [[ "$ready" != true ]]; then kill -KILL "$worker" 2>/dev/null || true; wait "$worker" 2>/dev/null || true; echo 'FAIL publisher did not reach kill boundary'; exit 1; fi
 kill -KILL "$worker"; wait "$worker" 2>/dev/null || true; worker=""
 curl(){ return 22; }
 cfip_source_fetch_remote publish https://one.example/list ip-text ipv4 community "$TMP/result"
 cache_bytes >"$TMP/observed"
 if [[ "$position" == before ]]; then cmp "$TMP/old" "$TMP/observed"; else cmp "$TMP/new" "$TMP/observed"; fi
 echo "PASS source cache KILL $position publication retains a qualified complete generation"
done
# Concurrent snapshots must bind bytes and metadata from the same rename generation.
(
 for _ in {1..24}; do
  cfip_source_cache_snapshot "$CFIP_SOURCE_CACHE_DIR/publish" "$TMP/read-raw" "$TMP/read-meta"
  cfip_source_cache_valid "$TMP/read-raw" "$TMP/read-meta" publish https://one.example/list ip-text ipv4 community
 done
) & worker=$!
for i in {1..12}; do
 if ((i % 2)); then file="$TMP/old"; else file="$TMP/new"; fi
 hash="$(sha256sum "$file" | awk '{print $1}')"
 cfip_source_cache_publish "$CFIP_SOURCE_CACHE_DIR/publish" "$file" publish https://one.example/list ip-text ipv4 community "$hash" 2 0
done
wait "$worker"; worker=""
echo 'PASS concurrent source cache snapshots preserve generation identity'
