#!/usr/bin/env bash
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; worker=""
cleanup(){ [[ -z "$worker" ]] || { kill -KILL "$worker" 2>/dev/null || true; wait "$worker" 2>/dev/null || true; }; rm -rf "$TMP"; }
trap cleanup EXIT
export CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_PUBLISH_DIR="$TMP/publish" CFIP_PUBLISH_STATUS_FILE="$TMP/status"
mkdir -p "$CFIP_RUNTIME_DIR"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "${CFIP_TEST_PUBLISHER:-$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/publisher.sh}"
printf '#!/bin/sh\nexit 0\n' >"$TMP/init"; chmod +x "$TMP/init"
export CFIP_PUBLISH_INIT="$TMP/init" CFIP_PUBLISH_ENABLED=true CFIP_PUBLISH_BIND=127.0.0.1 CFIP_PUBLISH_PORT=34567
printf '[{"ip":"104.18.1.1","family":"ipv4"}]' >"$TMP/input"
curl(){ local arg path; for arg in "$@"; do case "$arg" in http://*) path="${arg#http://}"; path="${path#*/}"; cat "$CFIP_PUBLISH_DIR/$path"; return ;; esac; done; return 1; }
cfip_publish_result "$TMP/input"
export CFIP_COMMON="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh" CFIP_PUBLISHER="${CFIP_TEST_PUBLISHER:-$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/publisher.sh}" CFIP_INPUT="$TMP/input" CFIP_READY="$TMP/ready"
bash -c '
 set -euo pipefail; source "$CFIP_COMMON"; source "$CFIP_PUBLISHER"
 curl(){ local arg path; for arg in "$@"; do case "$arg" in http://*) path="${arg#http://}"; path="${path#*/}"; cat "$CFIP_PUBLISH_DIR/$path"; return ;; esac; done; return 1; }
 mv(){ if [[ "${*: -1}" == "$CFIP_PUBLISH_DIR/current" ]]; then : >"$CFIP_READY"; kill -STOP "$$"; else command mv "$@"; fi; }
 cfip_publish_result "$CFIP_INPUT"
' & worker=$!
ready=false
for _ in {1..10}; do [[ ! -f "$CFIP_READY" ]] || { ready=true; break; }; kill -0 "$worker" 2>/dev/null || break; sleep 1; done
[[ "$ready" == true ]] || { echo 'FAIL no KILL boundary'; exit 1; }
kill -KILL "$worker"; wait "$worker" 2>/dev/null || true; worker=""
cfip_publish_result "$TMP/input"
left="$(find "$TMP" -maxdepth 1 -type d \( -name '.cfip-link.*' -o -name '.cfip-publish.*' \) | wc -l)"
if [[ -d "$TMP/.cfip-publisher-work" ]]; then
 left=$((left+$(find "$TMP/.cfip-publisher-work" -mindepth 1 -maxdepth 1 -type d | wc -l)))
fi
test "$left" -eq 0 || { echo "FAIL abandoned publisher workspaces remain after next publication: $left"; exit 1; }
echo 'PASS publication after killed writer reclaims abandoned private workspaces'

# An alive owner (including a conservatively retained reused PID) is never reaped.
lease_pid="${BASHPID:-$$}"
root="$(cfip_publisher_workspace_root)"
active="$(cfip_publisher_workspace_create readback "$lease_pid")"
printf 'active bytes' >"$active/payload"
mkdir "$root/unrecognized-data" "$TMP/outside"
printf 'outside bytes' >"$TMP/outside/payload"
ln -s "$TMP/outside" "$root/stage.9999999999.AAAAAA"
cfip_publisher_workspace_sweep "$root"
test "$(cat "$active/payload")" = 'active bytes'
test -d "$root/unrecognized-data"
test "$(cat "$TMP/outside/payload")" = 'outside bytes'
echo 'PASS active owner and unknown or symlink paths preserved'

# Reservations have a fixed sixteen-directory ceiling. Exhaustion must
# preserve the last public generation and every existing lease payload.
before="$(readlink "$CFIP_PUBLISH_DIR/current")"
for _ in {1..14}; do dir="$(cfip_publisher_workspace_create stage "$lease_pid")"; printf retained >"$dir/payload"; done
if cfip_publisher_workspace_create stage "$lease_pid" >"$TMP/unexpected"; then echo 'FAIL over-capacity workspace admitted'; exit 1; fi
if cfip_publish_result "$TMP/input"; then echo 'FAIL publication admitted with exhausted workspaces'; exit 1; fi
test "$(readlink "$CFIP_PUBLISH_DIR/current")" = "$before"
test "$(cat "$active/payload")" = 'active bytes'
rm -rf "$active"
replacement="$(cfip_publisher_workspace_create readback "$lease_pid")"
test -d "$replacement"
echo 'PASS sequential quota refusal preserves current publication and released capacity is reusable'

# Namespace adoption must not claim pre-existing user data or follow a link.
original_publish="$CFIP_PUBLISH_DIR"
mkdir -p "$TMP/foreign/.cfip-publisher-work"
printf unknown >"$TMP/foreign/.cfip-publisher-work/user-data"
CFIP_PUBLISH_DIR="$TMP/foreign/publish"
if cfip_publisher_workspace_root; then echo 'FAIL nonempty namespace adopted'; exit 1; fi
test "$(cat "$TMP/foreign/.cfip-publisher-work/user-data")" = unknown
mkdir "$TMP/linked"
ln -s "$TMP/outside" "$TMP/linked/.cfip-publisher-work"
CFIP_PUBLISH_DIR="$TMP/linked/publish"
if cfip_publisher_workspace_root; then echo 'FAIL linked namespace adopted'; exit 1; fi
test "$(cat "$TMP/outside/payload")" = 'outside bytes'
CFIP_PUBLISH_DIR="$original_publish"
echo 'PASS unowned nonempty namespace and namespace symlink refused'

# Failed quarantine rename refuses new work and preserves abandoned bytes.
bash -c 'exit 0' & dead_pid=$!; wait "$dead_pid"
dead="$root/stage.$dead_pid.ABCDEF"
mkdir "$dead"; printf abandoned >"$dead/payload"
mv(){ case "${*: -1}" in */.reap.*) return 1 ;; *) command mv "$@" ;; esac; }
if cfip_publisher_workspace_create stage "$lease_pid"; then echo 'FAIL failed quarantine admitted work'; exit 1; fi
test "$(cat "$dead/payload")" = abandoned
unset -f mv
cfip_publisher_workspace_sweep "$root"
test ! -e "$dead"
echo 'PASS failed quarantine refuses allocation and retains bytes for later retry'

# Unsafe writable namespaces are refused without silently changing permissions.
mkdir -p "$TMP/writable/.cfip-publisher-work"
ln -s cf-ip-publisher-work-v1 "$TMP/writable/.cfip-publisher-work/.owner"
chmod 777 "$TMP/writable/.cfip-publisher-work"
CFIP_PUBLISH_DIR="$TMP/writable/publish"
if cfip_publisher_workspace_root; then echo 'FAIL writable namespace adopted'; exit 1; fi
CFIP_PUBLISH_DIR="$original_publish"
echo 'PASS unsafe namespace permissions refused'

# Concurrent empty reservations become visible before payload admission.
mkdir "$TMP/concurrent"
export CFIP_PUBLISH_DIR="$TMP/concurrent/publish" CFIP_BARRIER="$TMP/concurrent"
pids=()
for i in {1..32}; do
 bash -c '
  source "$CFIP_PUBLISHER"
  lease_pid="${BASHPID:-$$}"
  if dir="$(cfip_publisher_workspace_create stage "$lease_pid")"; then
   printf admitted >"$dir/payload"; : >"$CFIP_BARRIER/accepted.$1"
   for _ in {1..15}; do [[ ! -f "$CFIP_BARRIER/release" ]] || break; sleep 1; done
   rm -rf "$dir"
  else : >"$CFIP_BARRIER/refused.$1"; fi
 ' _ "$i" & pids+=("$!")
done
ready=false
for _ in {1..10}; do
 count="$(find "$TMP/concurrent" -maxdepth 1 -type f \( -name 'accepted.*' -o -name 'refused.*' \) | wc -l)"
 if ((count == 32)); then ready=true; break; fi
 sleep 1
done
: >"$TMP/concurrent/release"
for pid in "${pids[@]}"; do wait "$pid"; done
[[ "$ready" == true ]] || { echo 'FAIL concurrent allocation timed out'; exit 1; }
accepted="$(find "$TMP/concurrent" -maxdepth 1 -type f -name 'accepted.*' | wc -l)"
((accepted >= 0 && accepted <= 16)) || { echo "FAIL concurrent admitted count: $accepted"; exit 1; }
retry="$(cfip_publisher_workspace_create stage "$lease_pid")"
test -d "$retry"
rm -rf "$retry"
echo "PASS 32 concurrent reservations admit at most sixteen payload writers ($accepted admitted); subsequent retry succeeds"
