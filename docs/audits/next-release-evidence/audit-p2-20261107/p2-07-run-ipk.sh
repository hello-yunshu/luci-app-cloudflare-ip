#!/bin/sh
set -eu

LOG=/work/p2-7-ipk.log
exec >"$LOG" 2>&1

echo "=== environment ==="
opkg --version 2>&1 | head -2 || true
cat /etc/opkg.conf 2>/dev/null || true

mkdir -p /var/lock /var/opkg-lists /tmp
echo "=== install released r8 ==="
opkg update >/dev/null 2>&1 || true
opkg install --force-depends /work/luci-app-cloudflare-ip_2.6.0-r8_all.ipk 2>&1 | tail -8 || true
opkg info luci-app-cloudflare-ip 2>/dev/null | head -4 || opkg status luci-app-cloudflare-ip | head -6

echo "=== user edits config ==="
printf "config global 'global'\n\toption custom_user_marker 'p2-7-conffile'\n" >/etc/config/cf_ip
sha256sum /etc/config/cf_ip >/work/ipk-config-user.sha256

echo "=== upgrade r8 -> r9 ==="
opkg install --force-depends /work/luci-app-cloudflare-ip_2.6.0-r9_all.ipk 2>&1 | tail -10 || true

echo "=== files after upgrade ==="
ls -la /etc/config/ | grep cf_ip || true
for f in /etc/config/cf_ip /etc/config/cf_ip-opkg /etc/config/cf_ip.opkg-new /etc/config/cf_ip.apk-new; do
	if [ -e "$f" ]; then
		echo "-- $f"
		head -6 "$f"
	fi
done

echo "=== user config unchanged? ==="
if sha256sum -c /work/ipk-config-user.sha256; then
	echo "USER_CONFIG_PRESERVED=true"
else
	echo "USER_CONFIG_PRESERVED=false"
fi

echo "=== done ==="
