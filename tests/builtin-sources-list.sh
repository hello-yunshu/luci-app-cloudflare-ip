#!/usr/bin/env bash
# `uci show` renders list items with single quotes on real OpenWrt; the source
# engine must still receive bare registry ids.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat >"$TMP/bin/uci" <<'UCI'
#!/bin/sh
case "$*" in
  *"get cf_ip.main.builtin_sources"*) printf 'cloudflare-official-v4\ncloudflare-official-v6\n' ;;
  *"show cf_ip.main.builtin_sources"*) printf "cf_ip.main.builtin_sources='cloudflare-official-v4' 'cloudflare-official-v6'\n" ;;
  *) exit 0 ;;
esac
UCI
chmod +x "$TMP/bin/uci"
# shellcheck disable=SC1090
. "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
value="$(PATH="$TMP/bin:$PATH" cfip_configured_builtin_sources)"
test "$value" = 'cloudflare-official-v4 cloudflare-official-v6' || { echo "unexpected builtin sources: $value" >&2; exit 1; }
cat >"$TMP/bin/uci" <<'UCI'
#!/bin/sh
case "$*" in
  *"get cf_ip.main.builtin_sources"*) exit 0 ;;
  *"show cf_ip.main.builtin_sources"*) printf "cf_ip.main.builtin_sources='cloudflare-official-v4'\n" ;;
  *) exit 0 ;;
esac
UCI
value="$(PATH="$TMP/bin:$PATH" cfip_configured_builtin_sources)"
test "$value" = 'cloudflare-official-v4' || { echo "unexpected show fallback: $value" >&2; exit 1; }
echo 'PASS builtin source lists strip UCI show quoting and keep registry ids'
