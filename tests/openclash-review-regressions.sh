#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/init" "$TMP/runtime" "$TMP/status"
export REVIEW_TMP="$TMP" CFIP_INIT_DIR="$TMP/init" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_STATUS_DIR="$TMP/status" CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
export PATH="$TMP/bin:$PATH"
cat >"$TMP/bin/uci" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" != -q ]] || shift
[[ ! -e "$REVIEW_TMP/read-fail" || "$1" != get ]] || exit 1
case "$1:$2" in
get:openclash.config.enable) cat "$REVIEW_TMP/enable" ;;
get:openclash.config.cn_port) printf 9090 ;;
get:cf_ip.main.mode) printf openclash ;;
set:openclash.config.enable=*) printf '%s' "${2#*=}" >"$REVIEW_TMP/enable" ;;
commit:openclash) [[ ! -e "$REVIEW_TMP/commit-fail" ]] ;;
*) exit 1 ;;
esac
EOF
cat >"$TMP/bin/pidof" <<'EOF'
#!/usr/bin/env bash
[[ "$(cat "$REVIEW_TMP/pid")" == live ]] || exit 1
printf 1234
EOF
cat >"$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
while (($#)); do
 case "$1" in --output) output="$2"; shift 2 ;; *) shift ;; esac
done
calls=$(( $(cat "$REVIEW_TMP/probe-count") + 1 )); printf '%s' "$calls" >"$REVIEW_TMP/probe-count"
if [[ -e "$REVIEW_TMP/disable-during-health" && "$calls" == 3 ]]; then printf 0 >"$REVIEW_TMP/enable"; fi
if [[ -e "$REVIEW_TMP/slow-health" ]]; then printf 20 >"$REVIEW_TMP/clock"; fi
printf '{"proxies":[]}' >"$output"; printf 200
EOF
cat >"$TMP/init/openclash" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >>"$REVIEW_TMP/service.log"
case "$1" in
 stop) printf down >"$REVIEW_TMP/pid" ;;
 restart)
   case "$(cat "$REVIEW_TMP/init-mode")" in
     healthy) printf live >"$REVIEW_TMP/pid" ;;
     no-core) printf down >"$REVIEW_TMP/pid" ;;
     hang) exec /bin/sleep 60 ;;
   esac ;;
esac
EOF
chmod +x "$TMP/bin/uci" "$TMP/bin/pidof" "$TMP/bin/curl" "$TMP/init/openclash"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
cfip_monotonic_seconds() { cat "$TMP/clock"; }
cfip_run_with_timeout() { shift; "$@"; }
sleep() { printf '%s' "$(( $(cat "$TMP/clock") + $1 ))" >"$TMP/clock"; /bin/sleep 0.01; }
reset() {
 printf '%s' "$1" >"$TMP/enable"; printf '%s' "$2" >"$TMP/pid"; printf '%s' "${3:-healthy}" >"$TMP/init-mode"
 printf 0 >"$TMP/clock"; printf 0 >"$TMP/probe-count"; : >"$TMP/service.log"
 rm -f "$TMP/read-fail" "$TMP/disable-during-health" "$TMP/slow-health" "$TMP/commit-fail"
 printf 'secret: test-only\nproxies: []\n' >"$TMP/config.yaml"
 CFIP_MODE=openclash; CFIP_OPENCLASH_CONFIG="$TMP/config.yaml"; CFIP_RUN_ID=review
 CFIP_OPENCLASH_EXPECTED_ENABLED=""; CFIP_OPENCLASH_INITIAL_HEALTHY=false; CFIP_OPENCLASH_CF_STOPPED=false
 CFIP_OPENCLASH_RECOVERY_ATTEMPTED=false; CFIP_OPENCLASH_RECOVERY_VERIFIED=false; CFIP_OPENCLASH_RESTART_ATTEMPTS=0; CFIP_OPENCLASH_SERVICE_APPLIED=false
 CFIP_OPENCLASH_FILE_WRITTEN=false; CFIP_OPENCLASH_SERVICE_ERROR=""; CFIP_STOPPED_MODE=""
 CFIP_TXN_DIR=""; CFIP_TXN_STATE=NONE; CFIP_TXN_COMMITTED=false; CFIP_TXN_ROLLED_BACK=false
 CFIP_CLEANUP_DONE=false; CFIP_RECOVERY_ACTIVE=false; CFIP_RECOVERY_ERROR=""
 CFIP_MEASUREMENT_DEADLINE=0
}
cfip_openclash_apply_selected() { printf '# selected nodes\n' >>"$CFIP_OPENCLASH_CONFIG"; }
cfip_openclash_readback_selected() { return 0; }
printf '[]' >"$TMP/selected.json"

reset 1 live
cfip_openclash_capture_state
test "$(cat "$TMP/probe-count")" = 3
test "$(cat "$TMP/clock")" -le 5
reset 1 live; : >"$TMP/slow-health"
if cfip_openclash_health_wait 5; then echo 'late health response passed deadline' >&2; exit 1; fi
reset 1 live; : >"$TMP/disable-during-health"
if cfip_openclash_capture_state; then echo 'disable during preflight was ignored' >&2; exit 1; fi
echo 'three healthy samples respect the deadline and final enable state'

reset 1 live
cfip_txn_prepare openclash
rollback_active_transaction
test ! -s "$TMP/service.log"
echo 'prepared-only cleanup never claims restart responsibility'

reset 0 down
cfip_txn_prepare openclash
printf '# external edit\n' >>"$CFIP_OPENCLASH_CONFIG"
cp "$CFIP_OPENCLASH_CONFIG" "$TMP/user-edit"
if cfip_txn_apply openclash "$TMP/selected.json"; then echo 'external config edit was overwritten' >&2; exit 1; fi
rollback_active_transaction || :
cmp -s "$CFIP_OPENCLASH_CONFIG" "$TMP/user-edit"; test ! -s "$TMP/service.log"
test -d "$CFIP_TXN_DIR"
echo 'external YAML changes and recovery evidence survive rejected apply and cleanup'

reset 0 down
cfip_txn_prepare openclash
printf 1 >"$TMP/enable"; printf live >"$TMP/pid"
if cfip_txn_apply openclash "$TMP/selected.json"; then echo 'external service start was ignored' >&2; exit 1; fi
test ! -s "$TMP/service.log"; ! rg -q 'selected nodes' "$CFIP_OPENCLASH_CONFIG"
echo 'external start is detected before node mutation'

reset 1 live no-core
cfip_txn_prepare openclash; cfip_stop_service openclash; CFIP_STOPPED_MODE=openclash
if cfip_txn_apply openclash "$TMP/selected.json"; then echo 'failed normal recovery passed' >&2; exit 1; fi
rollback_active_transaction || :
test "$(grep -c '^restart$' "$TMP/service.log")" = 1
rg -q 'selected nodes' "$CFIP_OPENCLASH_CONFIG"; test "$CFIP_OPENCLASH_FILE_WRITTEN" = true
test -d "$CFIP_TXN_DIR"
echo 'failed normal recovery preserves written nodes and never retries from transaction cleanup'

reset 1 live
cfip_openclash_capture_state
: >"$TMP/commit-fail"
if cfip_stop_service openclash; then echo 'failed stop-state commit was accepted' >&2; exit 1; fi
test ! -s "$TMP/service.log"; test "$(cat "$TMP/enable")" = 1
echo 'failed temporary UCI commit never stops the service or silently disables it'

# EXIT task-state updates are deliberately scoped to OpenClash.
for exit_mode in openclash passwall; do
 reset 1 live
 printf '{"runId":"review","active_run":true}' >"$TMP/exit-status"
 set +e
 (
  CFIP_MODE="$exit_mode"; CFIP_STATUS_FILE="$TMP/exit-status"; CFIP_ENABLED=true
  write_status() { printf '%s\n' "$*" >"$CFIP_STATUS_FILE"; }
  release_lock() { :; }
  run_cleanup 9
 )
 exit_rc=$?
 set -e
 test "$exit_rc" = 9
 if [[ "$exit_mode" == openclash ]]; then
  rg -q '^false failed error OpenClash run interrupted or failed' "$TMP/exit-status"
 else
  jq -e '.active_run == true' "$TMP/exit-status" >/dev/null
 fi
done
echo 'EXIT status repair is confined to OpenClash; PassWall status behavior is unchanged'

reset 0 down
load_config() { :; }
cp "$CFIP_OPENCLASH_CONFIG" "$CFIP_OPENCLASH_CONFIG.bak.20261010120000"
printf '# current nodes\n' >>"$CFIP_OPENCLASH_CONFIG"
cmd_oc_restore_backup 20261010120000 >"$TMP/backup-result"
jq -e '.success and .last_result=="warning" and .deferredUntilServiceStart and (.serviceApplied|not)' "$TMP/backup-result" >/dev/null
test ! -s "$TMP/service.log"; test "$(cat "$TMP/enable")" = 0
reset 1 down
cp "$CFIP_OPENCLASH_CONFIG" "$CFIP_OPENCLASH_CONFIG.bak.20261010120000"
if cmd_oc_restore_backup 20261010120000 >"$TMP/backup-result"; then echo 'unhealthy backup restore passed' >&2; exit 1; fi
test ! -s "$TMP/service.log"
echo 'backup restoration shares disabled-pending and unhealthy-service protections'

source "$ROOT/cf-openwrt-auto.sh"
INIT_DIR="$TMP/init"; OPENCLASH_CONFIG="$TMP/config.yaml"
date() { if [[ "${1:-}" == +%s ]]; then cat "$TMP/clock"; else command date "$@"; fi; }
for init_mode in healthy no-core; do
 reset 1 live "$init_mode"
 _OPENCLASH_EXPECTED_ENABLED=1; _OPENCLASH_INITIAL_HEALTHY=true; _OPENCLASH_ENABLE_SAVED=""; _STOPPED_SERVICE=""
 _OPENCLASH_RESTART_ATTEMPTS=0; _OPENCLASH_RECOVERY_ATTEMPTED=false
 stop_service openclash
 if restart_service openclash 2>"$TMP/standalone-apply-error"; then
   test "$init_mode" = healthy
 else
   test "$init_mode" = no-core
 fi
 cleanup_stopped_service
 test "$(grep -c '^restart$' "$TMP/service.log")" = 1
 test "$(cat "$TMP/enable")" = 1
done
echo 'standalone healthy restoration and failed restoration have the same one-attempt cleanup contract'

reset 1 live; _OPENCLASH_EXPECTED_ENABLED=1; _OPENCLASH_ENABLE_SAVED=""; _STOPPED_SERVICE=""
_OPENCLASH_RESTART_ATTEMPTS=0; _OPENCLASH_RECOVERY_ATTEMPTED=false
: >"$TMP/read-fail"
if restart_service openclash; then echo 'standalone unreadable enable started service' >&2; exit 1; fi
test ! -s "$TMP/service.log"
rm -f "$TMP/read-fail"; printf hang >"$TMP/init-mode"
if openclash_init_bounded restart 1; then echo 'hanging init exceeded its bound' >&2; exit 1; else test "$?" = 124; fi
test -z "$_OPENCLASH_INIT_PID"
set +e
(trap _on_exit EXIT; exit 7)
exit_rc=$?
set -e
test "$exit_rc" = 7
echo 'standalone read failures, hanging init and EXIT preserve bounded failure behavior'
echo 'OpenClash review regression contract passed'
