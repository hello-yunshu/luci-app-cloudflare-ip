#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
LIB="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
INIT="$ROOT/package/luci-app-cloudflare-ip/root/etc/init.d/cf_ip"
RPC="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/rpcd/cf_ip"
CLI="$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
export CF_IP_RUNTIME_DIR="$TMP/runtime" CFIP_RUNTIME_DIR="$TMP/runtime"
export CFIP_LOG_FILE="$TMP/cf-ip.log" CFIP_LIB_DIR="$LIB"
mkdir -p "$CF_IP_RUNTIME_DIR"
printf 'must survive lock contention\n' >"$CFIP_LOG_FILE"

. "$INIT"
cf_ip_shared_lock_acquire
test "$(cat "$CF_IP_RUNTIME_DIR/cf-ip-auto-v2.lock/pid")" = "$$"
if bash "$CLI" --clear-log >/dev/null 2>&1; then echo 'CLI writer ignored init-held shared lock' >&2; exit 1; fi
test "$(cat "$CFIP_LOG_FILE")" = 'must survive lock contention'
(
	set -- __source_only__
	. "$RPC" >/dev/null
	set --
	if cf_ip_rpc_lock_acquire; then echo 'rpcd writer ignored init-held shared lock' >&2; exit 1; fi
)
cf_ip_shared_lock_release
test ! -d "$CF_IP_RUNTIME_DIR/cf-ip-auto-v2.lock"

(
	set -- __source_only__
	. "$RPC" >/dev/null
	set --
	cf_ip_rpc_lock_acquire
	if bash "$CLI" --clear-log >/dev/null 2>&1; then echo 'CLI writer ignored rpcd-held shared lock' >&2; exit 1; fi
	. "$INIT"
	if cf_ip_shared_lock_acquire; then echo 'init writer ignored rpcd-held shared lock' >&2; exit 1; fi
	callback() { printf 'nested lifecycle callback\n' >>"$TMP/callback.log"; }
	CF_IP_LOCK_HELD=1 cf_ip_with_shared_lock callback
	test -s "$TMP/callback.log"
	test -d "$CF_IP_RUNTIME_DIR/cf-ip-auto-v2.lock"
	cf_ip_rpc_lock_release
)
test ! -d "$CF_IP_RUNTIME_DIR/cf-ip-auto-v2.lock"
test "$(cat "$CFIP_LOG_FILE")" = 'must survive lock contention'
echo 'init, rpcd, and CLI writers contend on one shared lock; nested lifecycle lock is reused'
