#!/bin/sh

old_url='https://raw.githubusercontent.com/hello-yunshu/use-cloudflare-ip/main/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto'
new_url='https://raw.githubusercontent.com/hello-yunshu/luci-app-cloudflare-ip/main/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto'
current="$(uci -q get cf_ip.main.self_update_url 2>/dev/null)" || exit 0
[ "$current" = "$old_url" ] || exit 0
uci -q set "cf_ip.main.self_update_url=$new_url" || exit 1
uci -q commit cf_ip || exit 1
