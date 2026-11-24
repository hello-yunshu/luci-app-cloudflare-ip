#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Reproduce the BusyBox build that has no FEATURE_FANCY_SLEEP: fractional
# arguments are rejected, integer ones still work.  On such a device the polling
# watchdog used to fall back to a full second between liveness checks, so an
# operation that finishes in milliseconds still blocked its caller for 1 s.
REAL_SLEEP="$(command -v sleep)"
mkdir -p "$TMP/bin"
cat >"$TMP/bin/sleep" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
    *.*) exit 1 ;;
esac
exec "$REAL_SLEEP" "\$@"
EOF
chmod +x "$TMP/bin/sleep"

source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
export PATH="$TMP/bin:$PATH"
unset CFIP_WATCHDOG_TICK CFIP_SLEEP_FRACTIONAL

# The test times the code under test, so it keeps its own clock.
now_ms() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        local t="${EPOCHREALTIME//[.,]/}"
        printf '%s' "$(( t / 1000 ))"
    elif [[ -r /proc/uptime ]]; then
        awk '{ printf "%d", $1 * 1000 }' /proc/uptime
    fi
}

start="$(now_ms)"
if [[ -z "$start" ]]; then
    echo 'watchdog tick granularity contract skipped (no millisecond clock)'
    exit 0
fi

cfip_run_with_timeout 5 true
elapsed=$(( $(now_ms) - start ))
if [[ "${CFIP_WATCHDOG_TICK:-}" != fifo ]]; then
    echo "expected the FIFO tick without fractional sleep, got '${CFIP_WATCHDOG_TICK:-}'" >&2
    exit 1
fi
if (( elapsed >= 900 )); then
    echo "fast operation still paid the coarse tick: ${elapsed}ms" >&2
    exit 1
fi

# Five more fast operations must fit inside a single coarse tick's budget.
start="$(now_ms)"
for _ in 1 2 3 4 5; do cfip_run_with_timeout 5 true; done
elapsed=$(( $(now_ms) - start ))
if (( elapsed >= 1500 )); then
    echo "watchdog tick is not sub-second: 5 fast operations took ${elapsed}ms" >&2
    exit 1
fi

# A finer tick must not weaken the deadline itself.
set +e
cfip_run_with_timeout 1 "$REAL_SLEEP" 3
rc=$?
set -e
if [[ "$rc" -ne 124 ]]; then
    echo "timeout contract broken: expected 124, got $rc" >&2
    exit 1
fi

echo 'watchdog tick granularity contract passed'
