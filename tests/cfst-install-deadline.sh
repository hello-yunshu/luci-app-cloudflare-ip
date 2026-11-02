#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat >"$TMP/legacy" <<'LEGACY'
#!/bin/sh
sleep 5
LEGACY
chmod +x "$TMP/legacy"
mkdir -p "$TMP/work/cfst"
CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
# shellcheck source=/dev/null
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
# The script initializes these at source time, so override after sourcing.
CFIP_WORK_DIR="$TMP/work"
CFIP_LEGACY_BIN="$TMP/legacy"
CFIP_CFST_INSTALL_TIMEOUT=1
set +e
ensure_cfst
rc=$?
set -e
[[ "$rc" -eq 124 ]]
echo 'PASS CFST install is bounded by the total timeout'
