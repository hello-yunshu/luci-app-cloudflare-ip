#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/tests/rill-integration-in-base.sh"
bash "$ROOT/tests/rill-addon-compat-meta.sh"
MAKEFILE="$ROOT/package/luci-app-cloudflare-ip/Makefile"
test "$(grep -c 'REPLACES:=luci-app-cloudflare-ip-rill' "$MAKEFILE")" = 0
! rg -n '^\s*\$\(INSTALL_(BIN|DATA|CONF|DIR)\).*rill' "$MAKEFILE" | rg 'luci-app-cloudflare-ip-rill' >/dev/null

echo 'r2 base plus addon to r4 has collision-free ownership and a compatibility dependency path'
