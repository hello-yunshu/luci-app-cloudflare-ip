#!/bin/sh
set -eu

LOG=/work/p2-7-apk.log
exec >"$LOG" 2>&1

echo "=== environment ==="
apk --version
echo "--- protected paths ---"
ls -l /etc/apk/protected_paths.d/ 2>/dev/null || echo "no protected_paths.d"
for f in /etc/apk/protected_paths.d/*; do [ -f "$f" ] && { echo "== $f"; cat "$f"; }; done

echo "=== install released r8 ==="
apk add --allow-untrusted --force-non-repository --no-scripts /work/luci-app-cloudflare-ip-2.6.0-r8.apk
apk info luci-app-cloudflare-ip | head -4
echo "--- shipped r8 default config ---"
sha256sum /etc/config/cf_ip
cat /etc/config/cf_ip

echo "=== user edits config ==="
printf "config global 'global'\n\toption custom_user_marker 'p2-7-conffile'\n" >/etc/config/cf_ip
sha256sum /etc/config/cf_ip >/work/config-user.sha256

echo "=== upgrade r8 -> r9 ==="
apk add --allow-untrusted --force-non-repository --no-scripts /work/luci-app-cloudflare-ip-2.6.0-r9.apk
apk info luci-app-cloudflare-ip | head -4

echo "=== files after upgrade ==="
ls -la /etc/config/ | grep cf_ip || true
for f in /etc/config/cf_ip /etc/config/cf_ip-opkg /etc/config/cf_ip.apk-new /etc/config/cf_ip-new /etc/config/cf_ip.new; do
	if [ -e "$f" ]; then
		echo "-- $f (mode $(stat -c '%a' "$f"))"
		cat "$f"
	fi
done

echo "=== user config unchanged? ==="
if sha256sum -c /work/config-user.sha256; then
	echo "USER_CONFIG_PRESERVED=true"
else
	echo "USER_CONFIG_PRESERVED=false"
fi

echo "=== apk audit ==="
apk audit --full 2>&1 | grep -i 'cf_ip' || true

echo "=== fresh root install of r9 (no pre-existing config) ==="
rm -rf /tmp/fresh && mkdir -p /tmp/fresh
apk --root /tmp/fresh --allow-untrusted --force-non-repository --no-scripts add /work/luci-app-cloudflare-ip-2.6.0-r9.apk 2>&1 | tail -3 || true
ls -la /tmp/fresh/etc/config/ 2>/dev/null | grep cf_ip || echo "fresh install did not write /etc/config/cf_ip (dependencies unavailable in fresh root)"

echo "=== done ==="
