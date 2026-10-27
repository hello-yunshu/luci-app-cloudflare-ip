#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(command mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "${CFIP_TEST_COMMON:-$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh}"
printf 'original\n' >"$TMP/state"
printf 'unrelated\n' >"$TMP/state.tmp.user"
fault=rename
mv(){ if [[ "$fault" == rename ]]; then return 1; fi; command mv "$@"; }
cat(){ if [[ "$fault" == stream ]]; then printf 'partial'; return 1; fi; command cat "$@"; }
mktemp(){ if [[ "$fault" == allocation ]]; then return 1; fi; command mktemp "$@"; }
for fault in rename stream allocation; do
 for _ in {1..8}; do
  rc=0; printf 'replacement\n' | cfip_atomic_write "$TMP/state" || rc=$?
  test "$rc" != 0
  test "$(command cat "$TMP/state")" = original
  test "$(command cat "$TMP/state.tmp.user")" = unrelated
  count="$(find "$TMP" -name 'state.tmp.*' -type f | wc -l)"
  test "$count" -eq 1 || { echo "FAIL $fault leaves private temporary files ($count including unrelated file)"; exit 1; }
 done
 echo "PASS repeated atomic write $fault failure preserves destination and removes only own temporary file"
done
fault=none
printf 'replacement\n' | cfip_atomic_write "$TMP/state"
test "$(command cat "$TMP/state")" = replacement
echo 'PASS atomic write recovers after failure'
