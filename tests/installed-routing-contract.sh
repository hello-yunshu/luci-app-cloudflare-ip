#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MENU="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/luci/menu.d/luci-app-cloudflare-ip.json"
CONTROLLER="$ROOT/package/luci-app-cloudflare-ip/root/usr/lib/lua/luci/controller/cloudflare-ip.lua"
jq empty "$MENU"
for plugin in passwall openclash; do
  jq -e --arg plugin "$plugin" '
    .["admin/services/cf_ip/" + $plugin] |
    .action == {type:"view", path:("cloudflare-ip/" + $plugin)} and
    .depends.fs == {("/etc/init.d/" + $plugin):"executable"}
  ' "$MENU" >/dev/null
done
grep -Fq 'nixio.fs.access' "$CONTROLLER"
grep -Fq 'id = "passwall"' "$CONTROLLER"
grep -Fq 'id = "openclash"' "$CONTROLLER"
grep -Fq 'p.id},' "$CONTROLLER"
echo 'Installed-aware LuCI routing contract passed'
