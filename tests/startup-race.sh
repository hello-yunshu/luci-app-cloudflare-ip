#!/usr/bin/env bash
# Startup behaviour test. Requires an OpenWrt root (bash, jq, flock, uci,
# /lib/functions.sh); run it inside a disposable 24.10/25.12 container.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/package/luci-app-cloudflare-ip"
INIT_FILE="$PKG/root/etc/init.d/cf_ip"
LIB="$PKG/root/usr/libexec/cf-ip"
REAL_RUN="$PKG/root/usr/bin/cf-ip-auto-v2"
CONFIG=/etc/config/cf_ip
WORK="$(mktemp -d)"
SAVED="$WORK/cf_ip.orig"

fail() { echo "FAIL: $*" >&2; exit 1; }

restore_config() {
	[ -f "$SAVED" ] && cp "$SAVED" "$CONFIG" || rm -f "$CONFIG"
}
trap restore_config EXIT

[ -f "$SAVED" ] || { [ -f "$CONFIG" ] && cp "$CONFIG" "$SAVED" || true; }
[ -r /lib/functions.sh ] || fail "/lib/functions.sh missing (not an OpenWrt root)"

set_config() {
	local delay="$1"
	cp "$PKG/root/etc/config/cf_ip" "$CONFIG"
	uci -q set cf_ip.main.enabled=1
	uci -q set cf_ip.main.startup_delay="$delay"
	uci -q set cf_ip.main.work_dir=/usr/share/cf-ip
	uci -q set cf_ip.main.cfst_persist=0
	uci -q set cf_ip.passwall.target_domain=example.com
	uci -q commit cf_ip
}

mkdir -p "$WORK/rt" "$WORK/status" "$WORK/usr" "$WORK/bin" "$WORK/init"
# The engine only accepts a root-owned, non-writable managed work dir.
mkdir -p /usr/share/cf-ip
chmod 0755 /usr/share/cf-ip

# --- 1. the init script submits exactly one background job -------------------
cat >"$WORK/cf-ip-auto" <<EOF
#!/bin/sh
printf '%s\n' "\${1:-}" >>"$WORK/auto.log"
exit 0
EOF
chmod +x "$WORK/cf-ip-auto"
: >"$WORK/auto.log"

set_config 30
(
	export CF_IP_RUNTIME_DIR="$WORK/rt" CF_IP_STATUS_DIR="$WORK/status"
	export CFIP_LIB_DIR="$LIB" CF_IP_AUTO_BIN="$WORK/cf-ip-auto"
	export PATH="$PATH" IPKG_INSTROOT=
	set +u
	. /lib/functions.sh
	. "$INIT_FILE"
	CRONTAB_FILE="$WORK/crontab"
	validate_cf_ip() { return 0; }
	_start_service_unlocked
)
sleep 2
grep -qx -- '--run' "$WORK/auto.log" || fail "first run was not submitted: $(cat "$WORK/auto.log")"
grep -qx -- '--download-cfst' "$WORK/auto.log" && fail "first run also submitted a competing download: $(cat "$WORK/auto.log")"
echo 'PASS first run submits only --run (no competing --download-cfst)'

: >"$WORK/auto.log"
set_config ''
(
	export CF_IP_RUNTIME_DIR="$WORK/rt" CF_IP_STATUS_DIR="$WORK/status"
	export CFIP_LIB_DIR="$LIB" CF_IP_AUTO_BIN="$WORK/cf-ip-auto" IPKG_INSTROOT=
	set +u
	. /lib/functions.sh
	. "$INIT_FILE"
	CRONTAB_FILE="$WORK/crontab"
	validate_cf_ip() { return 0; }
	_start_service_unlocked
)
sleep 2
grep -qx -- '--download-cfst' "$WORK/auto.log" || fail "scheduled startup did not download CFST: $(cat "$WORK/auto.log")"
grep -qx -- '--run' "$WORK/auto.log" && fail "scheduled startup also submitted an unrequested run: $(cat "$WORK/auto.log")"
echo 'PASS non-first startup submits only --download-cfst'

# --- 2. the real engine applies startup_delay before taking the lock --------
cat >"$WORK/bin/sleep" <<EOF
#!/bin/sh
echo "delay-start \$\$" >>"$WORK/delay.log"
exec /bin/sleep 5
EOF
chmod +x "$WORK/bin/sleep"
cat >"$WORK/fake-legacy" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$WORK/fake-legacy"
: >"$WORK/delay.log"
set_config 60

# The wrapper sleep proves the engine reached its delay without yet owning the
# writer lock. A manual run is simulated by acquiring that same lock.
PATH="$WORK/bin:$PATH" \
	CFIP_LIB_DIR="$LIB" CFIP_RUNTIME_DIR="$WORK/rt2" CFIP_STATUS_DIR="$WORK/status2" \
	CFIP_LEGACY_BIN="$WORK/fake-legacy" CFIP_INIT_DIR="$WORK/init" \
	bash "$REAL_RUN" --run >"$WORK/run.out" 2>&1 &
run_pid=$!
for _ in $(seq 1 20); do
	[ -s "$WORK/delay.log" ] && break
	sleep 1
done
if [ ! -s "$WORK/delay.log" ]; then
	kill "$run_pid" 2>/dev/null || true
	fail "engine did not reach apply_startup_delay"
fi
if ! ( . "$LIB/writer-lock.sh"; cf_ip_writer_lock_acquire "$WORK/rt2" && cf_ip_writer_lock_release "$WORK/rt2" ); then
	kill "$run_pid" 2>/dev/null || true
	fail "startup_delay still held the writer lock; manual run would report busy"
fi
kill "$run_pid" 2>/dev/null || true
wait "$run_pid" 2>/dev/null || true
echo 'PASS startup_delay runs before lock acquisition; manual run acquires the lock'

echo 'startup race behaviour passed'
