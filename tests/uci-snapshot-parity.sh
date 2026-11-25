#!/usr/bin/env bash
# The `uci show` snapshot must decode values exactly like `uci get`, including
# an apostrophe in the value (uci escapes it as '\'').
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/status"
cat >"$TMP/bin/uci" <<'UCI'
#!/bin/sh
[ "${1:-}" = "-q" ] && shift
case "${1:-}" in
  show)
    if [ "${2:-}" = "cf_ip" ]; then
      cat <<'SNAP'
cf_ip.main=main
cf_ip.main.enabled='0'
cf_ip.main.mode='it'\''s'
cf_ip.main.github_mirror=''
cf_ip.main.name_suffix=' [CF-{n}]'
SNAP
      exit 0
    fi
    ;;
  get)
    case "${2:-}" in
      cf_ip.main.mode) printf '%s' "it's" ;;
      cf_ip.main.name_suffix) printf '%s' " [CF-{n}]" ;;
    esac
    exit 0
    ;;
esac
exit 0
UCI
chmod +x "$TMP/bin/uci"
export PATH="$TMP/bin:$PATH"
export CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
export CFIP_STATUS_DIR="$TMP/status" CFIP_RUNTIME_DIR="$TMP/runtime"
# shellcheck disable=SC1090
. "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
load_config run >/dev/null 2>&1 || true
test "$CFIP_MODE" = "it's" || { echo "mode mismatch: [$CFIP_MODE]" >&2; exit 1; }
test "$CFIP_PASSWALL_NAME_SUFFIX" = " [CF-{n}]" || { echo "suffix mismatch: [$CFIP_PASSWALL_NAME_SUFFIX]" >&2; exit 1; }
test "$CFIP_GITHUB_MIRROR" = "" || { echo "empty option should keep its default: [$CFIP_GITHUB_MIRROR]" >&2; exit 1; }
echo "PASS uci show snapshot decodes like uci get"
