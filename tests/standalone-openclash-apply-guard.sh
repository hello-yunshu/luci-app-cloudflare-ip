#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat >"$TMP/bin/pidof" <<'EOF_PIDOF'
#!/bin/sh
[ "${CORE_RUNNING:-0}" = 1 ]
EOF_PIDOF
chmod +x "$TMP/bin/pidof"
export PATH="$TMP/bin:$PATH"
export TMPDIR="$TMP"

cat >"$TMP/mock-v2" <<'EOF_V2'
#!/bin/sh
printf '%s\n' bridge >>"$EVENTS"
cp "$2" "$CANDIDATE_COPY"
printf '%s\n' "$@" >"$BRIDGE_ARGS"
printf '%s\n' '{"success":true,"hotApplied":true,"restartCount":0,"applicationMethod":"file_provider_put"}'
EOF_V2
chmod +x "$TMP/mock-v2"

source "$ROOT/cf-openwrt-auto.sh"
OPENCLASH_CONFIG="$TMP/provider.yaml"
cat >"$OPENCLASH_CONFIG" <<'EOF_YAML'
proxies:
  - name: node [CF-1]
    type: vless
    server: 203.0.113.10
    port: 443
EOF_YAML
cp "$OPENCLASH_CONFIG" "$TMP/provider.before"
OPENCLASH_TARGET_DOMAIN=cdn.example.com
OPENCLASH_NAME_SUFFIX=' [CF-{n}]'
OPENCLASH_TRANSPORT_FILTER=''
CFIP_V2_BIN="$TMP/mock-v2"
FAST_IPS=(198.51.100.2 2001:db8::2)
export EVENTS="$TMP/events" CANDIDATE_COPY="$TMP/candidates.json" BRIDGE_ARGS="$TMP/args"

# Explicit active measurement preflight rejects a live core before CFST.
MODE=openclash
STOP_SERVICE_BEFORE_SPEEDTEST=false
if (CORE_RUNNING=1 openclash_measurement_preflight) >"$TMP/preflight.out" 2>&1; then
	echo 'FAIL: active standalone measurement was not rejected' >&2
	exit 1
fi
grep -q 'no verified online bypass' "$TMP/preflight.out"
[[ ! -e "$EVENTS" ]]

# Maintenance mode restores and verifies its owned stop before bridge apply.
_STOPPED_SERVICE=openclash
_OPENCLASH_EXPECTED_ENABLED=1
_OPENCLASH_ENABLE_SAVED=1
_OPENCLASH_INITIAL_HEALTHY=false
restart_service() {
	[[ "$1" == openclash ]]
	printf '%s\n' restore >>"$EVENTS"
	_OPENCLASH_INITIAL_HEALTHY=true
	return 0
}
update_openclash
[[ "$(cat "$EVENTS")" == $'restore\nbridge' ]]
jq -e 'length==2 and .[0].ip=="198.51.100.2" and .[0].family=="ipv4" and .[1].ip=="2001:db8::2" and .[1].family=="ipv6"' "$CANDIDATE_COPY" >/dev/null
[[ "$(sed -n '1p' "$BRIDGE_ARGS")" == --apply-selected ]]
[[ "$(sed -n '2p' "$BRIDGE_ARGS")" == "$TMP"/cf-openclash-selected.* ]]
[[ "$(sed -n '3p' "$BRIDGE_ARGS")" == openclash ]]
[[ "$(sed -n '4p' "$BRIDGE_ARGS")" == "$OPENCLASH_CONFIG" ]]
[[ "$(sed -n '5p' "$BRIDGE_ARGS")" == "$OPENCLASH_TARGET_DOMAIN" ]]
[[ "$(sed -n '6p' "$BRIDGE_ARGS")" == "$OPENCLASH_NAME_SUFFIX" ]]
[[ -z "$(sed -n '7p' "$BRIDGE_ARGS")" ]]
cmp -s "$OPENCLASH_CONFIG" "$TMP/provider.before"
[[ "$LAST_RESULT" == success && "$_STOPPED_SERVICE" == "" ]]

# If owned maintenance restoration fails, the bridge is never called and the
# provider (the node-bearing file in this standalone path) remains untouched.
rm -f "$EVENTS"
_STOPPED_SERVICE=openclash
_OPENCLASH_EXPECTED_ENABLED=1
_OPENCLASH_ENABLE_SAVED=1
_OPENCLASH_RECOVERY_ATTEMPTED=false
restart_service() {
	printf '%s\n' restore-failed >>"$EVENTS"
	return 1
}
if (update_openclash) >"$TMP/restore-failure.out" 2>&1; then
	echo 'FAIL: failed restoration unexpectedly reached apply' >&2
	exit 1
fi
grep -q 'no provider changes were submitted' "$TMP/restore-failure.out"
[[ "$(cat "$EVENTS")" == restore-failed ]]
cmp -s "$OPENCLASH_CONFIG" "$TMP/provider.before"

echo 'PASS standalone OpenClash maintenance restore precedes v2 bridge; failed restore submits no candidate'
