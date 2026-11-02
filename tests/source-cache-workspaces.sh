#!/usr/bin/env bash
# Actual cache publisher and process KILL; no remote endpoints or proxy mutation.
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; worker=''
cleanup(){ [[ -z "$worker" ]] || { kill -KILL "$worker" 2>/dev/null || true; wait "$worker" 2>/dev/null || true; }; rm -rf "$TMP"; }
trap cleanup EXIT
export CFIP_COMMON="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
export CFIP_TEST_SOURCE="${CFIP_TEST_SOURCE:-$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh}"
source "$CFIP_COMMON"; source "$CFIP_TEST_SOURCE"
export CFIP_TEST_CACHE="$TMP/cache" CFIP_READY="$TMP/ready" CFIP_INPUT="$TMP/input"
mkdir "$CFIP_TEST_CACHE"
printf '104.18.1.1\n104.18.1.2\n' >"$CFIP_INPUT"
export CFIP_INPUT_HASH="$(sha256sum "$CFIP_INPUT" | awk '{print $1}')"
publish(){ cfip_source_cache_publish "$CFIP_TEST_CACHE" "$CFIP_INPUT" cache https://one.example/list ip-text ipv4 community "$CFIP_INPUT_HASH" 2 0; }
for position in before after; do
 export CFIP_KILL_POSITION="$position"
 for _ in {1..3}; do
  rm -f "$CFIP_READY"
  bash -c '
   set -euo pipefail; source "$CFIP_COMMON"; source "$CFIP_TEST_SOURCE"
   mv(){
    if [[ "${*: -1}" == "$CFIP_TEST_CACHE/last-good.json" ]]; then
     [[ "$CFIP_KILL_POSITION" != after ]] || command mv "$@"
     : >"$CFIP_READY"; kill -STOP "$$"
    else command mv "$@"; fi
   }
   cfip_source_cache_publish "$CFIP_TEST_CACHE" "$CFIP_INPUT" cache https://one.example/list ip-text ipv4 community "$CFIP_INPUT_HASH" 2 0
  ' & worker=$!
  ready=false
  for _ in {1..10}; do [[ ! -f "$CFIP_READY" ]] || { ready=true; break; }; kill -0 "$worker" 2>/dev/null || break; sleep 1; done
  [[ "$ready" == true ]] || { echo 'FAIL no cache KILL boundary'; exit 1; }
  kill -KILL "$worker"; wait "$worker" 2>/dev/null || true; worker=''
 done
 publish
 left="$(find "$CFIP_TEST_CACHE" -name '.cache.*' -type f | wc -l)"
 if [[ -d "$CFIP_TEST_CACHE/.cfip-cache-work" ]]; then left=$((left+$(find "$CFIP_TEST_CACHE/.cfip-cache-work" -mindepth 1 -maxdepth 1 -type d | wc -l))); fi
 test "$left" -eq 0 || { echo "FAIL source cache retains $left abandoned candidates after KILL $position and next publication"; exit 1; }
 jq -e --arg hash "$CFIP_INPUT_HASH" '.contentHash==$hash and .parsedCount==2' "$CFIP_TEST_CACHE/last-good.json" >/dev/null
 echo "PASS source cache reclaims three killed $position-switch workspaces on next publication"
done

lease_pid="${BASHPID:-}"
[[ -n "$lease_pid" ]] || lease_pid="$(exec sh -c 'printf "%s" "$PPID"')"
root="$(cfip_source_cache_work_root "$CFIP_TEST_CACHE")"
active="$(cfip_source_cache_work_create "$CFIP_TEST_CACHE" "$lease_pid")"
printf active >"$active/payload"
printf 'legacy candidate: preserve' >"$CFIP_TEST_CACHE/.cache.AAAAAA"
mkdir "$root/user-data" "$TMP/outside"
printf outside >"$TMP/outside/payload"
ln -s "$TMP/outside" "$root/write.2147483000.AAAAAA"
publish
[[ "$(cat "$active/payload")" == active && "$(cat "$TMP/outside/payload")" == outside ]]
[[ -d "$root/user-data" && -L "$root/write.2147483000.AAAAAA" ]]
[[ "$(cat "$CFIP_TEST_CACHE/.cache.AAAAAA")" == 'legacy candidate: preserve' ]]
echo 'PASS live/reused owner, unknown data, symlink and old unmarked cache candidate preserved'

leases=()
for _ in {1..14}; do leases+=("$(cfip_source_cache_work_create "$CFIP_TEST_CACHE" "$lease_pid")"); done
before="$(sha256sum "$CFIP_TEST_CACHE/last-good.json")"
if publish; then echo 'FAIL cache publication admitted with exhausted workspace capacity'; exit 1; fi
[[ "$(sha256sum "$CFIP_TEST_CACHE/last-good.json")" == "$before" ]]
[[ "$(cat "$active/payload")" == active && -d "$root/user-data" ]]
CFIP_SOURCE_CACHE_DIR="$TMP"; CFIP_SOURCE_RUNTIME_DIR="$TMP/runtime"
curl(){ cat "$CFIP_INPUT"; }
cfip_source_fetch_remote cache https://one.example/list ip-text ipv4 community "$TMP/fallback-result"
unset -f curl
jq -e 'length==2 and .[0].value=="104.18.1.1"' "$TMP/fallback-result" >/dev/null
jq -e '.fromCache==true and .lastError=="cache_publication_failed"' "$CFIP_SOURCE_RUNTIME_DIR/cache/metadata.json" >/dev/null
[[ "$(sha256sum "$CFIP_TEST_CACHE/last-good.json")" == "$before" ]]
echo 'PASS full source refresh falls back to qualified last-good when workspace admission fails'
rm -rf "${leases[0]}"
replacement="$(cfip_source_cache_work_create "$CFIP_TEST_CACHE" "$lease_pid")"
test -d "$replacement"
echo 'PASS workspace admission refusal preserves last-good and released capacity is reusable'

for shape in foreign linked writable unsafe-parent; do
 parent="$TMP/$shape"; mkdir "$parent"
 case "$shape" in
  foreign) mkdir "$parent/.cfip-cache-work"; printf unknown >"$parent/.cfip-cache-work/payload" ;;
  linked) ln -s "$TMP/outside" "$parent/.cfip-cache-work" ;;
  writable) mkdir "$parent/.cfip-cache-work"; ln -s cf-ip-source-cache-work-v1 "$parent/.cfip-cache-work/.owner"; chmod 777 "$parent/.cfip-cache-work" ;;
  unsafe-parent) chmod 777 "$parent" ;;
 esac
 if cfip_source_cache_work_create "$parent" "$lease_pid" >"$TMP/unexpected"; then echo "FAIL unsafe $shape namespace admitted"; exit 1; fi
 [[ "$(cat "$TMP/outside/payload")" == outside ]]
 echo "PASS unsafe $shape namespace refused without adopting user data"
done

parent="$TMP/quarantine"; mkdir "$parent"
root="$(cfip_source_cache_work_root "$parent")"
bash -c 'exit 0' & dead_pid=$!; wait "$dead_pid"
dead="$root/write.$dead_pid.ABCDEF"; mkdir "$dead"; printf abandoned >"$dead/payload"
mv(){ case "${*: -1}" in */.reap.*) return 19 ;; *) command mv "$@" ;; esac; }
if cfip_source_cache_work_create "$parent" "$lease_pid" >"$TMP/unexpected"; then echo 'FAIL cache allocation ignored quarantine failure'; exit 1; fi
[[ "$(cat "$dead/payload")" == abandoned ]]
unset -f mv
replacement="$(cfip_source_cache_work_create "$parent" "$lease_pid")"
test ! -e "$dead"; test -d "$replacement"
echo 'PASS failed quarantine preserves bytes and refuses allocation; retry reclaims dead lease'
