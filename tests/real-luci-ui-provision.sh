#!/usr/bin/env bash
set -euo pipefail

CONTAINER="${1:-cfip-ui-gate}"
PORT="${2:-18080}"
LANG_CODE="${CFIP_UI_LANG:-en}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/package/luci-app-cloudflare-ip"

for command in docker openssl; do
	command -v "$command" >/dev/null || { echo "missing host command: $command" >&2; exit 1; }
done

docker exec "$CONTAINER" sh -c '
	set -eu
	for command in bash jq curl; do
		command -v "$command" >/dev/null || { echo "missing container command: $command" >&2; exit 1; }
	done
	mkdir -p /etc/cf_ip /usr/libexec/cf-ip /usr/libexec/rpcd /usr/share/cf-ip \
		/usr/share/luci/menu.d /usr/share/rpcd/acl.d \
		/www/luci-static/resources/view/cloudflare-ip \
		/www/luci-static/resources/cloudflare-ip
'

docker cp "$PKG/htdocs/luci-static/resources/view/cloudflare-ip/." "$CONTAINER:/www/luci-static/resources/view/cloudflare-ip/"
docker cp "$PKG/htdocs/luci-static/resources/cloudflare-ip/." "$CONTAINER:/www/luci-static/resources/cloudflare-ip/"
docker cp "$PKG/root/usr/share/luci/menu.d/luci-app-cloudflare-ip.json" "$CONTAINER:/usr/share/luci/menu.d/"
docker cp "$PKG/root/usr/share/rpcd/acl.d/luci-app-cloudflare-ip.json" "$CONTAINER:/usr/share/rpcd/acl.d/"
docker cp "$PKG/root/usr/bin/cf-ip-auto-v2" "$CONTAINER:/usr/bin/cf-ip-auto"
docker cp "$PKG/root/usr/bin/cf-ip-auto-legacy" "$CONTAINER:/usr/bin/cf-ip-auto-legacy"
docker cp "$PKG/root/usr/libexec/cf-ip/." "$CONTAINER:/usr/libexec/cf-ip/"
docker cp "$PKG/root/usr/libexec/rpcd/cf_ip" "$CONTAINER:/usr/libexec/rpcd/cf_ip"
docker cp "$PKG/root/etc/config/cf_ip" "$CONTAINER:/etc/config/cf_ip"
docker cp "$PKG/root/etc/init.d/cf_ip" "$CONTAINER:/etc/init.d/cf_ip"
docker cp "$PKG/root/usr/share/cf-ip/candidate-rill-feature-schema-v2.json" "$CONTAINER:/usr/share/cf-ip/"

if [ -n "${CFIP_UI_LMO:-}" ]; then
	docker exec "$CONTAINER" mkdir -p /usr/lib/lua/luci/i18n
	docker cp "$CFIP_UI_LMO" "$CONTAINER:/usr/lib/lua/luci/i18n/cloudflare-ip.zh-cn.lmo"
fi

PKG_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$PKG/Makefile" | head -n1)"
PKG_RELEASE="$(sed -n 's/^PKG_RELEASE:=//p' "$PKG/Makefile" | head -n1)"
PKG_FULL_VERSION="$PKG_VERSION-r$PKG_RELEASE"

docker exec "$CONTAINER" sh -c "
	set -eu
	chmod +x /usr/bin/cf-ip-auto /usr/bin/cf-ip-auto-legacy /usr/libexec/rpcd/cf_ip /etc/init.d/cf_ip
	for script in /usr/libexec/cf-ip/*.sh; do chmod +x \"\$script\"; done
	sed -i 's|@PKG_VERSION@|$PKG_VERSION|g; s|@PKG_RELEASE@|$PKG_RELEASE|g; s|@PKG_FULL_VERSION@|$PKG_FULL_VERSION|g' \
		/usr/bin/cf-ip-auto /usr/libexec/rpcd/cf_ip /www/luci-static/resources/cloudflare-ip/utils.js
	uci set uhttpd.main.listen_http='127.0.0.1:$PORT'
	uci set uhttpd.main.listen_https=''
	uci set luci.main.mediaurlbase='/luci-static/bootstrap'
	uci set luci.main.lang='$LANG_CODE'
	uci commit uhttpd
	uci commit luci
	rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache
	/etc/init.d/rpcd restart >/dev/null 2>&1
	/etc/init.d/uhttpd restart >/dev/null 2>&1
"

HASH="$(openssl passwd -6 -salt cfip-gate "${CFIP_UI_PASSWORD:-cfip-gate}")"
docker exec "$CONTAINER" sh -c "sed -i 's|^root:[^:]*:|root:$HASH:|' /etc/shadow"

for attempt in 1 2 3 4 5 6 7 8 9 10; do
	status="$(curl -sS --max-time 3 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/cgi-bin/luci/" 2>/dev/null || true)"
	if [ "$status" = 200 ] || [ "$status" = 302 ] || [ "$status" = 403 ]; then
		echo "provisioned $CONTAINER on 127.0.0.1:$PORT lang=$LANG_CODE"
		exit 0
	fi
	sleep 1
done
echo "uhttpd did not become ready on 127.0.0.1:$PORT" >&2
exit 1
