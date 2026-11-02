#!/usr/bin/env bash
# Auxiliary/read-only RPCs must work before a proxy is configured.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" /etc/cf_ip
cat >"$TMP/bin/uci" <<'UCI'
#!/bin/sh
args="$*"
case "$args" in
  *"get cf_ip.main.enabled"*) echo 0 ;;
  *"get cf_ip.main.mode"*) echo passwall ;;
  *"get cf_ip.main.ip_count"*) echo 4 ;;
  *"get cf_ip.main.ip_type"*) echo ipv4 ;;
  *"get cf_ip.main.speedtest_protocol"*) echo tcp ;;
  *"get cf_ip.main.work_dir"*) echo /usr/bin ;;
  *"get cf_ip.passwall.target_domain"*) echo "" ;;
  *"get cf_ip.openclash.config"*) echo /etc/openclash/config/config.yaml ;;
  *"get cf_ip.rill.enabled"*) echo 0 ;;
  *"get cf_ip.rill.state_file"*) echo /etc/cf_ip/rill-state.json ;;
  *"show cf_ip.main.builtin_sources"*) echo "cf_ip.main.builtin_sources=cloudflare-official-v4" ;;
  *"get "*) echo "" ;;
  *) exit 0 ;;
esac
UCI
chmod +x "$TMP/bin/uci"

run_cli() {
    PATH="$TMP/bin:$PATH" \
    CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip" \
    CFIP_STATUS_DIR="$TMP/state" CFIP_RUNTIME_DIR="$TMP/run" CFIP_LOG_FILE="$TMP/log" \
    CFIP_WORK_DIR=/usr/bin \
    CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/candidate-rill-feature-schema-v2.json" \
    "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2" "$@"
}

run_cli --publisher-status | jq -e 'has("state")' >/dev/null
run_cli --adaptive-status | jq -e '.success==true' >/dev/null
run_cli --rill-diagnostics | jq -e '.success==true and .runtime.state=="disabled"' >/dev/null
run_cli --rill-self-check | jq -e '.success==false and .status.state=="disabled"' >/dev/null
run_cli --oc-list-backups | jq -e '.success==true' >/dev/null
echo 'PASS auxiliary RPCs work with disabled/unconfigured proxy'
