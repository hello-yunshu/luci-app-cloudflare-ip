#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; worker=""
cleanup(){ [[ -z "$worker" ]] || { kill -KILL "$worker" 2>/dev/null || true; wait "$worker" 2>/dev/null || true; }; rm -rf "$TMP"; }
trap cleanup EXIT
export CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_PUBLISH_DIR="$TMP/publish" CFIP_PUBLISH_STATUS_FILE="$TMP/status"
mkdir -p "$CFIP_RUNTIME_DIR"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh"
source "${CFIP_TEST_PUBLISHER:-$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/publisher.sh}"
printf '#!/bin/sh\nexit 0\n' >"$TMP/init"; chmod +x "$TMP/init"
CFIP_PUBLISH_INIT="$TMP/init"; CFIP_PUBLISH_ENABLED=true; CFIP_PUBLISH_BIND=127.0.0.1; CFIP_PUBLISH_PORT=34567; CFIP_RUN_ID=old
curl(){ local arg path; for arg in "$@"; do case "$arg" in http://*) path="${arg#http://}"; path="${path#*/}"; cat "$CFIP_PUBLISH_DIR/$path"; return ;; esac; done; return 1; }
printf '[{"ip":"104.18.1.1","family":"ipv4"}]' >"$TMP/old"
printf '[{"ip":"104.18.9.1","family":"ipv4"}]' >"$TMP/new"
cfip_publish_result "$TMP/old"
for f in ip.txt best-ipv4.txt best-ipv6.txt result.json; do cp "$CFIP_PUBLISH_DIR/$f" "$TMP/$f.before"; done
jq(){ if [[ "${1:-}" == -r && "${2:-}" == '.[]|select(.family=="ipv4")|.ip' ]]; then printf 'partial'; return 1; fi; command jq "$@"; }
rc=0; cfip_publish_result "$TMP/new" || rc=$?
test "$rc" != 0 || { echo 'FAIL publisher ignored partial artifact rendering failure'; exit 1; }
for f in ip.txt best-ipv4.txt best-ipv6.txt result.json; do cmp "$TMP/$f.before" "$CFIP_PUBLISH_DIR/$f"; done
unset -f jq
echo 'PASS artifact rendering failure preserves all previous public bytes'

# All renderer failures happen before the public cursor is changed.
for fault in '.[].ip' '.[]|select(.family=="ipv6")|.ip' manifest; do
 jq(){
  if [[ "${1:-}" == -r && "${2:-}" == "$fault" ]] || [[ "$fault" == manifest && "$*" == *'--arg runId'* ]]; then printf 'partial'; return 1; fi
  command jq "$@"
 }
 rc=0; cfip_publish_result "$TMP/new" || rc=$?
 test "$rc" != 0
 for f in ip.txt best-ipv4.txt best-ipv6.txt result.json; do cmp "$TMP/$f.before" "$CFIP_PUBLISH_DIR/$f"; done
 unset -f jq
 echo "PASS private render failure $fault preserves old generation"
done
# A failed cursor rename must retain old bytes too.
mv(){ if [[ "${*: -1}" == "$CFIP_PUBLISH_DIR/current" ]]; then return 1; fi; command mv "$@"; }
rc=0; cfip_publish_result "$TMP/new" || rc=$?
test "$rc" != 0
for f in ip.txt best-ipv4.txt best-ipv6.txt result.json; do cmp "$TMP/$f.before" "$CFIP_PUBLISH_DIR/$f"; done
unset -f mv
echo 'PASS cursor rename failure retains previous generation'
# Fixed-generation URLs survive a subsequent publication, with byte hashes.
first="$(jq -r '.generationPath' "$CFIP_PUBLISH_DIR/result.json")"
CFIP_RUN_ID=new; cfip_publish_result "$TMP/new"
second="$(jq -r '.generationPath' "$CFIP_PUBLISH_DIR/result.json")"
test "$first" != "$second"
cmp "$TMP/ip.txt.before" "$CFIP_PUBLISH_DIR$first/ip.txt"
while IFS=$'\t' read -r name hash; do test "$(sha256sum "$CFIP_PUBLISH_DIR$second/$name" | awk '{print $1}')" = "$hash"; done < <(jq -r '.artifacts|to_entries[]|[.key,.value.sha256]|@tsv' "$CFIP_PUBLISH_DIR$second/result.json")
for _ in {1..5}; do cfip_publish_result "$TMP/new"; done
count="$(find "$CFIP_PUBLISH_DIR/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
test "$count" -le 3
echo 'PASS pinned-generation URLs, artifact digests and bounded generation retention'
# Convert legacy files without exposing a mixture, even if conversion stops midway.
CFIP_PUBLISH_DIR="$TMP/legacy"; mkdir -p "$CFIP_PUBLISH_DIR"
for f in ip.txt best-ipv4.txt best-ipv6.txt; do cp "$TMP/$f.before" "$CFIP_PUBLISH_DIR/$f"; done
printf '{"schemaVersion":1,"runId":"legacy","ips":["104.18.1.1"],"selected":[{"ip":"104.18.1.1","family":"ipv4"}]}' >"$CFIP_PUBLISH_DIR/result.json"
cp "$CFIP_PUBLISH_DIR/result.json" "$TMP/legacy-result.before"
mv(){ if [[ "${*: -1}" == "$CFIP_PUBLISH_DIR/best-ipv6.txt" ]]; then return 1; fi; command mv "$@"; }
rc=0; cfip_publish_result "$TMP/new" || rc=$?
test "$rc" != 0
for f in ip.txt best-ipv4.txt best-ipv6.txt; do cmp "$TMP/$f.before" "$CFIP_PUBLISH_DIR/$f"; done
cmp "$TMP/legacy-result.before" "$CFIP_PUBLISH_DIR/result.json"
unset -f mv
cfip_publish_result "$TMP/new"
jq -e '.ips==["104.18.9.1"] and (.generationPath|startswith("/generations/gen."))' "$CFIP_PUBLISH_DIR/result.json" >/dev/null
echo 'PASS interrupted legacy link conversion retains old bytes and retries successfully'
# Do not prune an unknown directory merely because it resembles an owned ID.
foreign="$CFIP_PUBLISH_DIR/generations/gen.$(printf '%064d' 0)"; mkdir -p "$foreign"; printf 'user' >"$foreign/keep"
for _ in {1..4}; do cfip_publish_result "$TMP/new"; done
test "$(cat "$foreign/keep")" = user
echo 'PASS generation retention preserves unowned directories'
# A downgrade may replace compatibility links with new legacy regular files.
for f in ip.txt best-ipv4.txt best-ipv6.txt; do rm "$CFIP_PUBLISH_DIR/$f"; cp "$TMP/$f.before" "$CFIP_PUBLISH_DIR/$f"; done
rm "$CFIP_PUBLISH_DIR/result.json"; cp "$TMP/legacy-result.before" "$CFIP_PUBLISH_DIR/result.json"
mv(){ if [[ "${*: -1}" == "$CFIP_PUBLISH_DIR/best-ipv6.txt" ]]; then return 1; fi; command mv "$@"; }
rc=0; cfip_publish_result "$TMP/new" || rc=$?
test "$rc" != 0
for f in ip.txt best-ipv4.txt best-ipv6.txt; do cmp "$TMP/$f.before" "$CFIP_PUBLISH_DIR/$f"; done
cmp "$TMP/legacy-result.before" "$CFIP_PUBLISH_DIR/result.json"
unset -f mv
cfip_publish_result "$TMP/new"
echo 'PASS legacy regular files after downgrade retain their bytes through interrupted re-upgrade'
# A reported rename error after the actual switch is resolved by exact link readback.
mv(){ local rc=0; command mv "$@" || rc=$?; if [[ "${*: -1}" == "$CFIP_PUBLISH_DIR/current" ]]; then return 1; fi; return "$rc"; }
cfip_publish_result "$TMP/old"
unset -f mv
jq -e '.ips==["104.18.1.1"]' "$CFIP_PUBLISH_DIR/result.json" >/dev/null
jq -e '.success==true' "$CFIP_PUBLISH_STATUS_FILE" >/dev/null
echo 'PASS observed successful pointer switch resolves a post-rename reported error'
# Hard termination on either side of the single current rename leaves a whole generation.
printf '[{"ip":"104.18.9.1","family":"ipv4"},{"ip":"104.18.9.2","family":"ipv4"}]' >"$TMP/two"
export CFIP_COMMON="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh" CFIP_PUBLISHER="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/publisher.sh"
export CFIP_PUBLISH_INIT CFIP_PUBLISH_ENABLED CFIP_PUBLISH_BIND CFIP_PUBLISH_PORT CFIP_INPUT="$TMP/two" CFIP_READY="$TMP/ready"
for position in before after; do
 cfip_publish_result "$TMP/old"
 old_generation="$(readlink "$CFIP_PUBLISH_DIR/current")"; rm -f "$CFIP_READY"
 export CFIP_KILL_POSITION="$position"
 bash -c '
  set -euo pipefail
  source "$CFIP_COMMON"; source "$CFIP_PUBLISHER"
  curl(){ local arg path; for arg in "$@"; do case "$arg" in http://*) path="${arg#http://}"; path="${path#*/}"; cat "$CFIP_PUBLISH_DIR/$path"; return ;; esac; done; return 1; }
  mv(){
   if [[ "${*: -1}" == "$CFIP_PUBLISH_DIR/current" ]]; then
    [[ "$CFIP_KILL_POSITION" != after ]] || command mv "$@"
    : >"$CFIP_READY"; kill -STOP "$$"
   else command mv "$@"; fi
  }
  cfip_publish_result "$CFIP_INPUT"
 ' & worker=$!
 ready=false
 for _ in {1..10}; do
  if [[ -f "$CFIP_READY" ]]; then ready=true; break; fi
  kill -0 "$worker" 2>/dev/null || break
  sleep 1
 done
 [[ "$ready" == true ]] || { echo 'FAIL publisher did not reach KILL boundary'; exit 1; }
 kill -KILL "$worker"; wait "$worker" 2>/dev/null || true; worker=""
 if [[ "$position" == before ]]; then
  test "$(readlink "$CFIP_PUBLISH_DIR/current")" = "$old_generation"
  jq -e '.ips==["104.18.1.1"]' "$CFIP_PUBLISH_DIR/result.json" >/dev/null
 else
  jq -e '.ips==["104.18.9.1","104.18.9.2"]' "$CFIP_PUBLISH_DIR/result.json" >/dev/null
  cfip_publisher_status_json >"$TMP/live-status"
  test "$(jq -r '.generation' "$TMP/live-status")" = "$(jq -r '.generation' "$CFIP_PUBLISH_DIR/result.json")"
  jq -e '.success==true and .count==2' "$TMP/live-status" >/dev/null
 fi
 echo "PASS KILL $position current switch retains a complete generation"
done
