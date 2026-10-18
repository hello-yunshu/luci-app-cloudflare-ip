#!/usr/bin/env bash
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; worker=""
cleanup(){ [[ -z "$worker" ]] || { kill -KILL "$worker" 2>/dev/null || true; wait "$worker" 2>/dev/null || true; }; rm -rf "$TMP"; }
trap cleanup EXIT
export CFIP_PUBLISH_DIR="$TMP/publish" CFIP_RUNTIME_DIR="$TMP/runtime"
export CFIP_COMMON="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
export CFIP_PUBLISHER="${CFIP_TEST_PUBLISHER:-$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/publisher.sh}"
mkdir -p "$CFIP_PUBLISH_DIR/generations/unknown-user-data" "$CFIP_RUNTIME_DIR"
printf 'legacy bytes\n' >"$CFIP_PUBLISH_DIR/ip.txt"
printf retained >"$CFIP_PUBLISH_DIR/generations/unknown-user-data/payload"
for round in {1..6}; do
 export CFIP_READY="$TMP/ready.$round"
 bash -c '
  set -euo pipefail; source "$CFIP_COMMON"; source "$CFIP_PUBLISHER"
  mv(){ if [[ "${*: -1}" == "$CFIP_PUBLISH_DIR/current" ]]; then : >"$CFIP_READY"; kill -STOP "$$"; else command mv "$@"; fi; }
  cfip_publisher_prepare_layout
 ' & worker=$!
 ready=false
 for _ in {1..10}; do [[ ! -f "$CFIP_READY" ]] || { ready=true; break; }; kill -0 "$worker" 2>/dev/null || break; sleep 1; done
 [[ "$ready" == true ]] || { echo 'FAIL bootstrap KILL boundary not reached'; exit 1; }
 kill -KILL "$worker"; wait "$worker" 2>/dev/null || true; worker=""
 test "$(cat "$CFIP_PUBLISH_DIR/ip.txt")" = 'legacy bytes'
 test ! -e "$CFIP_PUBLISH_DIR/current"
done
count="$(find "$CFIP_PUBLISH_DIR/generations" -mindepth 1 -maxdepth 1 -type d -name 'gen.*' | wc -l)"
((count <= 4)) || { echo "FAIL interrupted bootstrap snapshots accumulate: $count"; exit 1; }
test "$(cat "$CFIP_PUBLISH_DIR/generations/unknown-user-data/payload")" = retained
source "$CFIP_COMMON"; source "$CFIP_PUBLISHER"
cfip_publisher_prepare_layout
test "$(cat "$CFIP_PUBLISH_DIR/ip.txt")" = 'legacy bytes'
echo "PASS six interrupted bootstraps retain bounded owned snapshots ($count), preserve unknown data and recover legacy bytes"

# An invalid current pointer must fail before any owned-generation pruning.
before="$(find "$CFIP_PUBLISH_DIR/generations" -mindepth 1 -maxdepth 1 -type d -name 'gen.*' | sort)"
rm -f "$CFIP_PUBLISH_DIR/current"
ln -s generations/unknown-user-data "$CFIP_PUBLISH_DIR/current"
if cfip_publisher_prepare_layout; then echo 'FAIL invalid cursor accepted'; exit 1; fi
after="$(find "$CFIP_PUBLISH_DIR/generations" -mindepth 1 -maxdepth 1 -type d -name 'gen.*' | sort)"
test "$before" = "$after"
test "$(cat "$CFIP_PUBLISH_DIR/generations/unknown-user-data/payload")" = retained
echo 'PASS invalid current cursor refuses layout before pruning any generation'
