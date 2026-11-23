#!/usr/bin/env bash
# Runtime channel matrix: only the canonical Stable package is accepted.
# Legacy Preview and unknown Runtime ownership are rejected.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" /etc/cf_ip /etc/config
cat >"$TMP/bin/uci" <<'UCI'
#!/bin/sh
args="$*"
case "$args" in
  *"get cf_ip.main.enabled"*) echo 1 ;;
  *"get cf_ip.main.mode"*) echo passwall ;;
  *"get cf_ip.main.ip_count"*) echo 4 ;;
  *"get cf_ip.main.ip_type"*) echo ipv4 ;;
  *"get cf_ip.main.speedtest_protocol"*) echo tcp ;;
  *"get cf_ip.main.work_dir"*) echo /usr/bin ;;
  *"get cf_ip.passwall.target_domain"*) echo example.com ;;
  *"get cf_ip.openclash.config"*) echo /etc/openclash/config/config.yaml ;;
  *"get cf_ip.rill.enabled"*) echo 1 ;;
  *"get cf_ip.rill.mode"*) echo shadow ;;
  *"get cf_ip.rill.state_file"*) echo /etc/cf_ip/rill-state.json ;;
  *"show cf_ip.main.builtin_sources"*) echo "cf_ip.main.builtin_sources=cloudflare-official-v4" ;;
  *"get "*) echo "" ;;
  *"set "*) exit 0 ;;
  *"commit "*) exit 0 ;;
  *) exit 0 ;;
esac
UCI
chmod +x "$TMP/bin/uci"

printf 'stable\n' >"$TMP/channel-stable"
printf 'preview\n' >"$TMP/channel-preview"
printf 'unexpected\n' >"$TMP/channel-unknown"
mkdir -p "$TMP/apkdb" "$TMP/opkginfo"

run_validate() {
    local channel="$1"
    PATH="$TMP/bin:$PATH" CFIP_RILL_CHANNEL_FILE="$channel" \
    CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip" \
    CFIP_APK_PACKAGE_DB_DIR="$TMP/apkdb" CFIP_OPKG_INFO_DIR="$TMP/opkginfo" \
    CFIP_STATUS_DIR="$TMP/state" CFIP_RUNTIME_DIR="$TMP/run" CFIP_LOG_FILE="$TMP/log" \
    CFIP_WORK_DIR=/usr/bin \
    CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/candidate-rill-feature-schema-v2.json" \
    "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2" --validate-config 2>&1
}

run_validate "$TMP/channel-stable" | jq -e '.success==true' >/dev/null
echo 'PASS canonical Stable Runtime channel accepted'

set +e
out="$(run_validate "$TMP/channel-unknown")"
rc=$?
set -e
[[ "$rc" -ne 0 ]]
# An unreadable marker is not a Preview installation: the engine now reports
# "not installed" and asks for the Stable package instead of naming the legacy
# preview package, so this branch asserts that split rather than the old text.
grep -q 'Rill Runtime is not installed' <<<"$out"
grep -q 'Stable rill-runtime' <<<"$out"
echo 'PASS Unknown Runtime channel rejected for Preview consumer'

set +e
out="$(run_validate "$TMP/channel-preview")"
rc=$?
set -e
[[ "$rc" -ne 0 ]]
grep -q 'rill-runtime-preview' <<<"$out"
echo 'PASS legacy Preview Runtime channel rejected pending explicit migration'

# Migration must disable an enabled Rill consumer when the legacy Preview
# Runtime is detected. Stable Runtime remains the only accepted channel.
cat >/etc/config/cf_ip <<'CONFIG'
config service 'main'
	option enabled '1'
	option mode 'passwall'
	option ip_count '4'
	option ip_type 'ipv4'
	option speedtest_protocol 'tcp'
	option work_dir '/usr/bin'
	option cron_interval '6h'
config passwall 'passwall'
	option target_domain 'example.com'
config rill 'rill'
	option enabled '1'
	option mode 'shadow'
	option state_file '/etc/cf_ip/rill-state.json'
config openclash 'openclash'
	option config '/etc/openclash/config/config.yaml'
CONFIG
CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip" \
CFIP_RILL_CHANNEL_FILE="$TMP/channel-preview" CFIP_STATUS_DIR="$TMP/state" \
  bash "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/migrate-managed-config.sh" >/dev/null
[[ "$(uci -q get cf_ip.rill.enabled)" = 0 ]]
echo 'PASS migration disables Rill on legacy Preview Runtime'
