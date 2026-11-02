#!/usr/bin/env bash
# Start/status and legacy-config migration regression. Run in an OpenWrt rootfs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p /etc/config /etc/cf_ip /etc/crontabs /usr/bin/cfst /usr/libexec /var/lock
cp "$ROOT/package/luci-app-cloudflare-ip/root/etc/init.d/cf_ip" /etc/init.d/cf_ip
chmod +x /etc/init.d/cf_ip
ln -sf "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2" /usr/bin/cf-ip-auto
ln -sf "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-legacy" /usr/bin/cf-ip-auto-legacy
rm -rf /usr/libexec/cf-ip
ln -sfn "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip" /usr/libexec/cf-ip
cat >/usr/bin/cfst/cfst <<'CFST'
#!/bin/sh
[ "$1" = "--version" ] && { echo v2.3.5; exit 0; }
exit 1
CFST
chmod +x /usr/bin/cfst/cfst
echo v2.3.5 >/usr/bin/cfst/cfst_version.txt

cat >/etc/config/cf_ip <<'UCI'
config service 'main'
	option enabled '1'
	option mode 'passwall'
	option ip_count '4'
	option ip_type 'ipv4'
	option speedtest_protocol 'tcp'
	option speedtest_dn '200'
	option work_dir '/usr/bin'
	option cron_interval '6h'
config passwall 'passwall'
	option target_domain 'example.com'
	option name_suffix ' [CF-{n}]'
config rill 'rill'
	option enabled '0'
	option state_file '/etc/cf_ip/rill-state.json'
config openclash 'openclash'
	option config '/etc/openclash/config/config.yaml'
UCI

# New start must publish a visible failure instead of silently leaving a
# stale running status.
set +e
/etc/init.d/cf_ip start >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]]
jq -e '.running==false and .enabled==true and .phase=="validation_failed" and .last_result=="error" and (.error|type)=="string"' /etc/cf_ip/status.json >/dev/null
[[ ! -s /etc/crontabs/root ]] || ! grep -q 'cf-ip-auto --run' /etc/crontabs/root
echo 'PASS invalid legacy config start reports validation_failed'

# Explicit migration clamps the value, writes a backup, and starts successfully.
CFIP_LIB_DIR=/usr/libexec/cf-ip CFIP_STATUS_DIR=/etc/cf_ip \
  bash "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/migrate-managed-config.sh" >/dev/null
[[ "$(uci -q get cf_ip.main.speedtest_dn)" = 100 ]]
backup="$(find /etc/cf_ip/backups -maxdepth 1 -type d -name 'pre-upgrade-*' -print | head -n 1)"
[[ -n "$backup" && -f "$backup/cf_ip" ]]
grep -q 'cf_ip.main.speedtest_dn' "$backup/changes.tsv"
set +e
/etc/init.d/cf_ip start >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 0 ]]
grep -q 'cf-ip-auto --run' /etc/crontabs/root
jq -e '.running==true and .enabled==true and .last_result=="scheduled"' /etc/cf_ip/status.json >/dev/null
echo 'PASS migration clamps legacy value and schedules the service'

# enabled=0 must publish stopped status even when a previous status exists.
uci set cf_ip.main.enabled=0
uci commit cf_ip
set +e
/etc/init.d/cf_ip start >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 0 ]]
jq -e '.running==false and .enabled==false and .disabled==true and .last_result=="disabled"' /etc/cf_ip/status.json >/dev/null
! grep -q 'cf-ip-auto --run' /etc/crontabs/root
echo 'PASS disabled start publishes stopped status and removes cron'
