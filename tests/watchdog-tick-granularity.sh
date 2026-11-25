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

# BusyBox `date` ignores the nanoseconds field, so `%s%3N` degrades to plain
# seconds. Epoch milliseconds must stay milliseconds instead of shrinking 1000x.
if [[ -n "${EPOCHREALTIME:-}" ]]; then
    live_ms="$(cfip_now_millis)"; wall_ms=$(( ${EPOCHREALTIME//[.,]/} / 1000 ))
    if (( live_ms > wall_ms + 5 || wall_ms > live_ms + 5 )); then
        echo "EPOCHREALTIME path is not milliseconds: $live_ms vs $wall_ms" >&2
        exit 1
    fi
fi
unset EPOCHREALTIME
date() {
    case "${1:-}" in
        +%s%3N|+%s) printf '%s\n' 1795625857 ;;
        *) command date "$@" ;;
    esac
}
if [[ "$(cfip_now_millis)" != 1795625857000 ]]; then
    echo "second-resolution clock was not scaled to milliseconds: $(cfip_now_millis)" >&2
    exit 1
fi
# GNU date still passes real millisecond values through untouched.
date() {
    case "${1:-}" in
        +%s%3N) printf '%s\n' 1795625857123 ;;
        +%s) printf '%s\n' 1795625857 ;;
        *) command date "$@" ;;
    esac
}
if [[ "$(cfip_now_millis)" != 1795625857123 ]]; then
    echo "millisecond clock value was rewritten: $(cfip_now_millis)" >&2
    exit 1
fi
# A format the clock does not understand must still yield a millisecond epoch.
date() {
    case "${1:-}" in
        +%s%3N) printf '%s\n' 'unknown format' ;;
        +%s) printf '%s\n' 1795625857 ;;
        *) command date "$@" ;;
    esac
}
if [[ "$(cfip_now_millis)" != 1795625857000 ]]; then
    echo "unparseable clock fell back to a non-millisecond value: $(cfip_now_millis)" >&2
    exit 1
fi
unset -f date

echo 'watchdog tick granularity contract passed'
