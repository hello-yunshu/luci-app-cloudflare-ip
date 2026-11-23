#!/usr/bin/env bash
# Contract: sub-command stderr never lands in the app log verbatim, and a
# repeating failure is reported once instead of once per timer run.
#
# Regression source: cfip_rill_run_captured's predecessors ended in
# `2>>"$CFIP_LOG_FILE"`. A single traced run put 1,164 `+ ...` lines into
# /tmp/cf_ip/cf-ip-auto.log (1,164 of 1,185 lines were noise) and buried the
# real history.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export CFIP_LOG_FILE="$TMP/cf-ip-auto.log"
export CFIP_RUNTIME_DIR="$TMP/runtime"
export CFIP_LOG_MAX_BYTES=1048576

source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/candidate-rill.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

log_lines() { wc -l <"$CFIP_LOG_FILE" 2>/dev/null | tr -d ' ' || printf 0; }
: >"$CFIP_LOG_FILE"

# 1. Summary skips trace lines and reports how much was dropped.
printf '+++ local limit=2 marker\n+++ shift\nboom: runtime unreachable\nmore detail\n' >"$TMP/err1"
summary="$(cfip_stderr_summary "$TMP/err1")"
[ "$summary" = "boom: runtime unreachable (+3 more line(s))" ] \
	|| fail "stderr summary was '$summary'"

# 2. Summary is clamped so one bad line cannot bloat the log entry. The bound
#    must hold in a C locale too: that is what OpenWrt actually runs, and there
#    a multi-byte ellipsis counted as three bytes.
printf '%s\n' "$(printf 'x%.0s' $(seq 1 600))" >"$TMP/err2"
summary="$(cfip_stderr_summary "$TMP/err2" 40)"
[ "${#summary}" -eq 40 ] || fail "summary not clamped to 40 chars: ${#summary}"
[ "${summary%...}" != "$summary" ] || fail "clamped summary lost its ellipsis"

# 3. A failing runtime call logs ONE line, and the raw stderr stays out.
set +e
cfip_rill_run_captured "$TMP/out" "$TMP/err" preview-serve \
	bash -c 'printf "+++ local limit=2\n+++ shift\nboom: runtime unreachable\n" >&2; exit 7'
rc=$?
set -e
[ "$rc" -eq 7 ] || fail "exit code not propagated (got $rc)"
[ "$(log_lines)" -eq 1 ] || fail "failing call wrote $(log_lines) lines, expected 1"
grep -q '^\[.*\] Rill runtime preview-serve failed (rc=7): boom: runtime unreachable' "$CFIP_LOG_FILE" \
	|| { cat "$CFIP_LOG_FILE" >&2; fail "summary line missing or malformed"; }
grep -q '+++' "$CFIP_LOG_FILE" && { cat "$CFIP_LOG_FILE" >&2; fail "trace lines reached the log"; }

# 4. The same failure on the next run is suppressed.
set +e
cfip_rill_run_captured "$TMP/out" "$TMP/err" preview-serve \
	bash -c 'printf "+++ local limit=2\n+++ shift\nboom: runtime unreachable\n" >&2; exit 7'
set -e
[ "$(log_lines)" -eq 1 ] || fail "repeated failure was logged again"

# 5. A different failure is still reported, and success re-arms the key.
set +e
cfip_rill_run_captured "$TMP/out" "$TMP/err" preview-serve \
	bash -c 'echo "boom: schema mismatch" >&2; exit 9'
set -e
[ "$(log_lines)" -eq 2 ] || fail "different failure was suppressed"
grep -q 'rc=9.*schema mismatch' "$CFIP_LOG_FILE" || fail "changed failure not reported"

cfip_rill_run_captured "$TMP/out" "$TMP/err" preview-serve true
[ "$(log_lines)" -eq 2 ] || fail "successful call wrote to the log"
[ -f "$CFIP_RUNTIME_DIR/log_state/rill_runtime" ] && fail "success did not clear the repeat key"

set +e
cfip_rill_run_captured "$TMP/out" "$TMP/err" preview-serve \
	bash -c 'echo "boom: runtime unreachable" >&2; exit 7'
set -e
[ "$(log_lines)" -eq 3 ] || fail "recovery did not re-arm the failure report"

printf 'log-stderr-bounded contract passed\n'
