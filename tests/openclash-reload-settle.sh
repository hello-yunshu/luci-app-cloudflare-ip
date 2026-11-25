#!/usr/bin/env bash
# Verify that a preflight health-check failure caused by an in-progress
# OpenClash reload (subscription refresh / rule rebuild) is retried after the
# reload settles, while a genuinely unhealthy core still fails fast.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
real_health_wait="$(declare -f cfip_openclash_health_wait)"

CFIP_INIT_DIR="$TMP/init"; mkdir -p "$CFIP_INIT_DIR"
printf '#!/bin/sh\nexit 0\n' >"$CFIP_INIT_DIR/openclash"; chmod +x "$CFIP_INIT_DIR/openclash"
CFIP_OPENCLASH_RELOAD_SETTLE_SECONDS=10
CFIP_OPENCLASH_HEALTH_WAIT_INTERVAL_SECONDS=1
CFIP_OPENCLASH_LOCK_DIR="$TMP/lockdir"; mkdir -p "$CFIP_OPENCLASH_LOCK_DIR"
: >"$CFIP_OPENCLASH_LOCK_DIR/openclash_subs.lock"

printf 0 >"$TMP/clock"
: >"$TMP/sleep-calls"
printf 'down\n' >"$TMP/health"
# busy-until: while fake clock < this value, the reload lock is considered held
printf '' >"$TMP/busy-until"

sleep() {
    printf '%s\n' "$1" >>"$TMP/sleep-calls"
    printf '%s' "$(( $(cat "$TMP/clock") + $1 ))" >"$TMP/clock"
}
cfip_monotonic_seconds() { cat "$TMP/clock"; }
cfip_log() { :; }

uci() {
    local arg
    [[ "${1:-}" == -q ]] && shift
    arg="${*: -1}"
    case "$arg" in
        openclash.config.enable) printf 1 ;;
        openclash.config.cn_port) printf 9090 ;;
        *) return 1 ;;
    esac
}
pidof() { printf '1234\n'; }
cfip_openclash_core_pids() { printf '1234\n'; }
cfip_openclash_read_enable() { CFIP_OPENCLASH_ENABLE_VALUE=1; }

# stub flock: busy while current fake clock < busy-until
flock() {
    local until
    until="$(cat "$TMP/busy-until" 2>/dev/null || true)"
    [[ -n "$until" ]] && (( $(cat "$TMP/clock") < until )) && return 1
    return 0
}

reset() {
    printf 0 >"$TMP/clock"; : >"$TMP/sleep-calls"
    printf '%s' "$2" >"$TMP/busy-until"
    printf '%s\n' "$1" >"$TMP/health"
    CFIP_OPENCLASH_SERVICE_ERROR=""
    CFIP_OPENCLASH_HEALTH_PID_CHANGED=false
}

attempt=0

# --- A: reload lock held during first failure; settles -> retry succeeds.
reset down 4
attempt=0
# simulate the controller recovering once the fake clock reaches 3s
sleep() {
    printf '%s\n' "$1" >>"$TMP/sleep-calls"
    printf '%s' "$(( $(cat "$TMP/clock") + $1 ))" >"$TMP/clock"
    if (( $(cat "$TMP/clock") >= 3 )); then printf 'up\n' >"$TMP/health"; fi
    return 0
}
# This is the *retry* health check (the first failure happened before this
# function was called), so a single successful call after the settle is enough.
cfip_openclash_health_wait() {
    attempt=$((attempt + 1))
    [[ "$(cat "$TMP/health")" == up ]]
}
if ! cfip_openclash_health_wait_after_reload 4; then
    echo "FAIL: reload scenario did not recover after settle" >&2; exit 1
fi
(( attempt >= 1 )) || { echo "FAIL: health check was not retried after settle" >&2; exit 1; }
(( $(cat "$TMP/clock") >= 4 )) || { echo "FAIL: retried before the reload lock was released" >&2; exit 1; }
[[ -s "$TMP/sleep-calls" ]] || { echo "FAIL: settle did not wait for reload" >&2; exit 1; }
echo "PASS reload-settle: waited for reload and recovered health"

# --- B: genuinely unhealthy (no lock, stable PID) -> no waiting at all.
sleep() {
    printf '%s\n' "$1" >>"$TMP/sleep-calls"
    printf '%s' "$(( $(cat "$TMP/clock") + $1 ))" >"$TMP/clock"
}
reset down ''
attempt=0
cfip_openclash_health_wait() { attempt=$((attempt + 1)); return 1; }
if cfip_openclash_health_wait_after_reload 4; then
    echo "FAIL: genuinely unhealthy core was accepted" >&2; exit 1
fi
[[ ! -s "$TMP/sleep-calls" ]] || { echo "FAIL: genuinely unhealthy core should fail fast without waiting" >&2; exit 1; }
echo "PASS fail-fast: stable unhealthy core rejected without delay"

# --- C: held reload lock alone is recognised as reload evidence.
printf 5 >"$TMP/busy-until"; printf 0 >"$TMP/clock"
if ! cfip_openclash_jobs_busy; then echo "FAIL: busy OpenClash lock not detected" >&2; exit 1; fi
printf '' >"$TMP/busy-until"
echo "PASS lock-detection: held OpenClash reload lock recognised"

# --- D: a core restart inside the failed probe window is remembered even
# though the final sample has already settled on the new PID.
reset down ''
printf 1 >"$TMP/pid-calls"
cfip_openclash_health_once() { return 1; }
cfip_openclash_core_pids() {
    local n; n=$(( $(cat "$TMP/pid-calls") + 1 )); printf '%s' "$n" >"$TMP/pid-calls"
    if (( n <= 2 )); then printf '1111'; else printf '2222'; fi
}
eval "$real_health_wait"
if cfip_openclash_health_wait 10 2; then
    echo "FAIL: still-unhealthy controller passed the probe window" >&2; exit 1
fi
[[ "$CFIP_OPENCLASH_HEALTH_PID_CHANGED" == true ]] || {
    echo "FAIL: PID change during the probe window was not recorded" >&2; exit 1
}
echo "PASS pid-change: restart inside the probe window is remembered"

# --- E: the recorded PID change alone triggers the settle wait and retry.
reset down ''
CFIP_OPENCLASH_HEALTH_PID_CHANGED=true
cfip_openclash_core_pids() { printf '2222'; }
retried=0
cfip_openclash_health_wait() { retried=1; return 0; }
if ! cfip_openclash_health_wait_after_reload 10; then
    echo "FAIL: recorded PID change did not trigger a retry" >&2; exit 1
fi
(( retried == 1 )) || { echo "FAIL: health check was not retried after the PID change" >&2; exit 1; }
(( $(cat "$TMP/clock") >= 2 )) || { echo "FAIL: retried before the core PID stabilised" >&2; exit 1; }
echo "PASS pid-change-retry: recorded PID change waited for stability, then retried"
