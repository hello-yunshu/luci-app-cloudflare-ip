#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CFIP_OPENCLASH_CONFIG="$TMP/config.yaml"; printf 'original\n' >"$CFIP_OPENCLASH_CONFIG"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/transaction.sh"

cfip_txn_prepare() { CFIP_TXN_DIR="$TMP/txn"; mkdir -p "$CFIP_TXN_DIR"; cp "$CFIP_OPENCLASH_CONFIG" "$CFIP_TXN_DIR/openclash.yaml"; return 0; }
cfip_openclash_check_before_write() { return 0; }
cfip_passwall_apply_selected() { return 1; }
cfip_openclash_apply_selected() { return 1; }

cfip_txn_rollback() { return 0; }
set +e
cfip_txn_apply passwall selected.json
rc=$?
set -e
test "$rc" -eq 11
set +e
cfip_txn_rollback() { return 1; }
cfip_txn_apply passwall selected.json
rc=$?
set -e
test "$rc" -eq 12

cfip_txn_rollback() { return 0; }
set +e
cfip_txn_apply openclash selected.json
rc=$?
set -e
test "$rc" -eq 13
set +e
cfip_txn_rollback() { return 1; }
cfip_txn_apply openclash selected.json
rc=$?
set -e
test "$rc" -eq 14

test "$(cfip_passwall_expand_suffix ' [CF-{n}] {ip}' 2 2606:4700::1)" = ' [CF-2] 2606:4700::1'
test "$(cfip_passwall_base_remarks 'Cloudflare [CF-2]')" = 'Cloudflare'
echo 'v2 transaction return/remark tests passed'
