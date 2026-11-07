#!/usr/bin/env bash
# Directed managed-path regression test. Run inside a disposable OpenWrt
# rootfs (root-owned /usr/bin and /etc) or with an equivalent root environment.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CLI="$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
LIB="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"

mkdir -p "$TMP/bin" /etc/cf_ip
cat >"$TMP/bin/uci" <<'UCI'
#!/bin/sh
args="$*"
case "$args" in
  *"get cf_ip.main.enabled"*) printf '%s\n' "${CFIP_TEST_ENABLED:-0}" ;;
  *"get cf_ip.main.mode"*) printf '%s\n' "${CFIP_TEST_MODE:-passwall}" ;;
  *"get cf_ip.main.ip_count"*) echo 4 ;;
  *"get cf_ip.main.ip_type"*) echo ipv4 ;;
  *"get cf_ip.main.speedtest_protocol"*) echo tcp ;;
  *"get cf_ip.passwall.target_domain"*) echo example.com ;;
  *"get cf_ip.openclash.target_domain"*) echo example.com ;;
  *"get cf_ip.openclash.config"*) printf '%s\n' "${CFIP_TEST_OC_CONFIG:-/etc/openclash/config/config.yaml}" ;;
  *"get cf_ip.openclash.name_suffix"*) echo ' [CF-{n}]' ;;
  *"get cf_ip.rill.enabled"*) printf '%s\n' "${CFIP_TEST_RILL_ENABLED:-0}" ;;
  *"get cf_ip.rill.mode"*) echo shadow ;;
  *"get cf_ip.rill.runtime"*) printf '%s\n' "${CFIP_TEST_RUNTIME:-/usr/bin/rill-runtime}" ;;
  *"get cf_ip.rill.state_file"*) printf '%s\n' "${CFIP_TEST_STATE:-/etc/cf_ip/rill-state.json}" ;;
  *"get cf_ip.main.work_dir"*) printf '%s\n' "${CFIP_TEST_WORK_DIR:-/usr/bin}" ;;
  *"show cf_ip.main.builtin_sources"*) echo "cf_ip.main.builtin_sources='cloudflare-official-v4'" ;;
  *"get "*) echo "" ;;
  *"set "*) exit 0 ;;
  *"commit "*) exit 0 ;;
  *) exit 0 ;;
esac
UCI
chmod +x "$TMP/bin/uci"

run_cli() {
    PATH="$TMP/bin:$PATH" \
    CFIP_LIB_DIR="$LIB" CFIP_STATUS_DIR="/etc/cf_ip" CFIP_RUNTIME_DIR="$TMP/run" \
    CFIP_LOG_FILE="$TMP/log" CFIP_WORK_DIR="${CFIP_TEST_WORK_DIR:-/usr/bin}" \
    CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/candidate-rill-feature-schema-v2.json" \
    "$CLI" "$@"
}

# Reproduce the original defect target: an arbitrary file must not be moved.
printf 'PROTECTED\n' >"$TMP/victim"
set +e
out="$(CFIP_TEST_STATE="$TMP/victim" run_cli --rill-reset 2>&1)"
rc=$?
set -e
[[ "$rc" -ne 0 ]]
[[ -f "$TMP/victim" ]]
grep -q 'state_file' <<<"$out"
echo 'PASS unsafe state_file rejected without moving the victim'

# A custom executable path in UCI must not be executed.
cat >"$TMP/evil" <<EVIL
#!/bin/sh
printf 'EVIL-RAN\n' >>"$TMP/evil-marker"
exit 1
EVIL
chmod +x "$TMP/evil"
out="$(CFIP_TEST_RILL_ENABLED=1 CFIP_TEST_RUNTIME="$TMP/evil" run_cli --rill-self-check 2>&1)"
[[ ! -e "$TMP/evil-marker" ]]
grep -q '"available":false' <<<"$out"
echo 'PASS unsafe rill.runtime never executed'

# Work directory and OpenClash config are confined to package-owned paths.
set +e
out="$(CFIP_TEST_WORK_DIR="$TMP/evilwork" run_cli --validate-config 2>&1)"
rc=$?
set -e
[[ "$rc" -ne 0 ]]
grep -q 'work_dir' <<<"$out"
echo 'PASS unsafe work_dir rejected'

set +e
out="$(CFIP_TEST_MODE=openclash CFIP_TEST_ENABLED=0 CFIP_TEST_OC_CONFIG="$TMP/evil.yaml" run_cli --validate-config 2>&1)"
rc=$?
set -e
[[ "$rc" -ne 0 ]]
grep -q 'openclash.config' <<<"$out"
echo 'PASS new openclash.config outside /etc/openclash rejected'

# Upgrades must keep an existing, root-owned, private file even when the user
# configured it outside /etc/openclash.
printf 'port: 7890\n' >"$TMP/legacy.yaml"
chmod 600 "$TMP/legacy.yaml"
CFIP_TEST_MODE=openclash CFIP_TEST_ENABLED=0 CFIP_TEST_OC_CONFIG="$TMP/legacy.yaml" run_cli --validate-config >/dev/null
echo 'PASS existing root-owned openclash.config outside /etc/openclash accepted'

# A symlink in the managed state path is rejected.
ln -sf "$TMP/victim" /etc/cf_ip/policy-link
set +e
out="$(CFIP_TEST_STATE=/etc/cf_ip/policy-link run_cli --rill-reset 2>&1)"
rc=$?
set -e
[[ "$rc" -ne 0 ]]
[[ -f "$TMP/victim" ]]
echo 'PASS symlinked state_file rejected'

# Default legacy values still validate.
CFIP_TEST_WORK_DIR=/usr/bin CFIP_TEST_STATE=/etc/cf_ip/rill-state.json CFIP_TEST_MODE=passwall run_cli --validate-config >/dev/null
echo 'PASS default managed paths validate'

# Migration regression (needs real uci): an existing external OpenClash config
# and a valid custom cron expression must survive the upgrade unchanged.
if command -v uci >/dev/null 2>&1 && [ -d /etc/config ] && [ -w /usr/bin ] \
   && [ ! -e /usr/bin/cf-ip-auto ]; then
    printf 'port: 7890\n' >"$TMP/legacy.yaml"
    chmod 600 "$TMP/legacy.yaml"
    cp -p /etc/config/cf_ip "$TMP/cf_ip.before" 2>/dev/null || true
    cat >/etc/config/cf_ip <<CONFIG
config service 'main'
	option enabled '1'
	option mode 'openclash'
	option cron_interval 'custom'
	option cron_custom '30 7,18,23 * * *'
config openclash 'openclash'
	option config '$TMP/legacy.yaml'
CONFIG
    ln -sf "$CLI" /usr/bin/cf-ip-auto
    CFIP_LIB_DIR="$LIB" CFIP_STATUS_DIR="$TMP/status" \
      bash "$LIB/migrate-managed-config.sh" >/dev/null
    [[ "$(uci -q get cf_ip.main.cron_interval)" = custom ]]
    [[ "$(uci -q get cf_ip.openclash.config)" = "$TMP/legacy.yaml" ]]
    echo 'PASS migration keeps custom cron and external OpenClash config'
    rm -f /usr/bin/cf-ip-auto
    if [ -f "$TMP/cf_ip.before" ]; then
        cp -p "$TMP/cf_ip.before" /etc/config/cf_ip
    else
        rm -f /etc/config/cf_ip
    fi
fi
