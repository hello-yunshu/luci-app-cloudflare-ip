#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAKEFILE="$ROOT/package/luci-app-cloudflare-ip/Makefile"
INIT="$ROOT/package/luci-app-cloudflare-ip/root/etc/init.d/cf_ip_publisher"
README="$ROOT/README.md"

grep -q 'DEPENDS:=+luci-base' "$MAKEFILE"
! grep -q 'DEPENDS:=.*+uhttpd' "$MAKEFILE" ||
	{ echo 'FAIL package hard-depends on uhttpd' >&2; exit 1; }
grep -q '[ -x /usr/sbin/uhttpd ]' "$INIT" ||
	{ echo 'FAIL publisher does not check the optional uhttpd runtime' >&2; exit 1; }
grep -q 'uhttpd.*not a hard dependency\|uhttpd.*不是硬依赖' "$README" ||
	{ echo 'FAIL README does not document the optional uhttpd boundary' >&2; exit 1; }
echo 'PASS uhttpd is optional for the LAN publisher; no second web server is installed'
