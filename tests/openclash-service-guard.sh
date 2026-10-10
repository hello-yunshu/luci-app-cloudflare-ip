#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/init" "$TMP/runtime" "$TMP/status"
export TEST_TMP="$TMP" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_STATUS_DIR="$TMP/status" CFIP_INIT_DIR="$TMP/init"
export CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
export CFIP_OPENCLASH_HEALTH_WAIT_INTERVAL_SECONDS=1 PATH="$TMP/bin:$PATH"
printf 'external-controller: 0.0.0.0:9090\nsecret: local-test-secret\n' >"$TMP/openclash.yaml"
printf '0\n' >"$TMP/enable"; printf '\n' >"$TMP/pid"; printf 'down\n' >"$TMP/health"
printf 'healthy\n' >"$TMP/init-mode"; printf '0\n' >"$TMP/restart-count"

cat >"$TMP/bin/uci" <<'EOF_UCI'
#!/usr/bin/env bash
[[ "${1:-}" == -q ]] && shift
case "${1:-}" in
  get) case "$2" in openclash.config.enable) cat "$TEST_TMP/enable" ;; openclash.config.cn_port) printf 9090 ;; cf_ip.main.self_update_url) cat "$TEST_TMP/update-url" ;; *) exit 1 ;; esac ;;
  set) pair="$2"; case "${pair%%=*}" in openclash.config.enable) printf '%s\n' "${pair#*=}" >"$TEST_TMP/enable" ;; cf_ip.main.self_update_url) printf '%s\n' "${pair#*=}" >"$TEST_TMP/update-url" ;; *) exit 1 ;; esac ;;
  commit) printf 'commit\n' >>"$TEST_TMP/migration.log" ;;
  revert) : ;;
  *) exit 1 ;;
esac
EOF_UCI
cat >"$TMP/bin/pidof" <<'EOF_PIDOF'
#!/usr/bin/env bash
[[ "$(cat "$TEST_TMP/pid")" == live ]] && printf '1234\n'
[[ "$(cat "$TEST_TMP/pid")" == live ]]
EOF_PIDOF
cat >"$TMP/bin/curl" <<'EOF_CURL'
#!/usr/bin/env bash
set -euo pipefail
config="" output="" url=""
while (($#)); do
  case "$1" in
    --config) config="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    http://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
[[ "$url" == http://127.0.0.1:9090/group ]]
[[ -z "$config" ]] || grep -q 'Authorization: Bearer local-test-secret' "$config"
if [[ "$(cat "$TEST_TMP/health")" == healthy ]]; then printf '{"proxies":[]}' >"$output"; printf 200; else printf '{"message":"not ready"}' >"$output"; printf 503; fi
EOF_CURL
chmod +x "$TMP/bin/uci" "$TMP/bin/pidof" "$TMP/bin/curl"
cat >"$TMP/init/openclash" <<'EOF_INIT'
#!/usr/bin/env bash
printf '%s\n' "$1" >>"$TEST_TMP/service.log"
case "$1" in
  stop) printf '\n' >"$TEST_TMP/pid"; printf 'down\n' >"$TEST_TMP/health" ;;
  restart)
    printf '%s\n' "$(($(cat "$TEST_TMP/restart-count") + 1))" >"$TEST_TMP/restart-count"
    case "$(cat "$TEST_TMP/init-mode")" in
      healthy) printf 'live\n' >"$TEST_TMP/pid"; printf 'healthy\n' >"$TEST_TMP/health" ;;
      no-core) printf '\n' >"$TEST_TMP/pid"; printf 'down\n' >"$TEST_TMP/health" ;;
      start-fail) printf '0\n' >"$TEST_TMP/enable"; printf '\n' >"$TEST_TMP/pid"; printf 'down\n' >"$TEST_TMP/health" ;;
      *) printf 'live\n' >"$TEST_TMP/pid"; printf 'down\n' >"$TEST_TMP/health" ;;
    esac ;;
esac
exit 0
EOF_INIT
chmod +x "$TMP/init/openclash"

source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
CFIP_OPENCLASH_CONFIG="$TMP/openclash.yaml"; CFIP_MODE=openclash; CFIP_RUN_ID=guard-test
CFIP_VERBOSE=false; CFIP_STOP_SERVICE=true
export CFIP_OPENCLASH_CONFIG

reset_state() {
  printf '%s\n' "${1:-0}" >"$TMP/enable"; printf '%s\n' "${2:-}" >"$TMP/pid"
  printf '%s\n' "${3:-down}" >"$TMP/health"; printf '%s\n' "${4:-healthy}" >"$TMP/init-mode"
  printf '0\n' >"$TMP/restart-count"; : >"$TMP/service.log"
  CFIP_OPENCLASH_SERVICE_ERROR=""; CFIP_OPENCLASH_EXPECTED_ENABLED=""
  CFIP_OPENCLASH_INITIAL_RUNNING=false; CFIP_OPENCLASH_INITIAL_HEALTHY=false
  CFIP_OPENCLASH_DEFERRED=false; CFIP_OPENCLASH_CF_STOPPED=false
  CFIP_OPENCLASH_RECOVERY_ATTEMPTED=false; CFIP_OPENCLASH_RECOVERY_VERIFIED=false; CFIP_OPENCLASH_RESTART_ATTEMPTS=0
  CFIP_OPENCLASH_FILE_WRITTEN=false; CFIP_OPENCLASH_SERVICE_APPLIED=false
  CFIP_STOPPED_MODE=""; CFIP_TXN_DIR=""; CFIP_TXN_STATE=NONE; CFIP_TXN_ROLLED_BACK=false
  CFIP_TXN_COMMITTED=false; CFIP_TXN_ORIGINAL_RUNNING=false; CFIP_RECOVERY_ACTIVE=false; CFIP_RECOVERY_ERROR=""
}

reset_state 0 '' down
cfip_openclash_capture_state
test "$CFIP_OPENCLASH_DEFERRED" = true
stop_service_for_measurement
test "$(cat "$TMP/enable")" = 0; test ! -s "$TMP/service.log"
echo 'disabled OpenClash stays untouched and deferred'

reset_state 1 live healthy healthy
cfip_openclash_capture_state
cfip_openclash_health_once
if find "$TMP" -name 'cfip-openclash-curl.*' -o -name 'cfip-openclash-health.*' | grep -q .; then echo 'health probe left temporary auth data' >&2; exit 1; fi
stop_service_for_measurement
test "$CFIP_STOPPED_MODE" = openclash; test "$(cat "$TMP/enable")" = 0; test -z "$(cat "$TMP/pid")"
restore_stopped_service_if_needed
test "$(cat "$TMP/enable")" = 1; test "$(cat "$TMP/restart-count")" = 1; test "$CFIP_OPENCLASH_SERVICE_APPLIED" = true
echo 'healthy stop/restart uses stable local controller health and one restart'

reset_state 1 live healthy healthy
CFIP_MEASUREMENT_TIMEOUT=30; CFIP_RECOVERY_TIMEOUT=30; CFIP_MEASUREMENT_DEADLINE=0
cfip_openclash_capture_state
stop_service_for_measurement
cfip_log() { :; }
remember_history() { :; }
declare -f write_status >"$TMP/write-status-function"
write_status() { TEST_STATUS_ARGS="$*"; }
release_lock() { :; }
cfip_cancel_active_operation() { :; }
if fail_run 'measurement failed'; then echo 'failed measurement returned success' >&2; exit 1; fi
test "$(cat "$TMP/enable")" = 1; test "$(cat "$TMP/restart-count")" = 1
test "$CFIP_OPENCLASH_RECOVERY_ATTEMPTED" = true
[[ "$TEST_STATUS_ARGS" == 'false failed error measurement failed' ]]
rollback_active_transaction
test "$(cat "$TMP/restart-count")" = 1
source "$TMP/write-status-function"
echo 'measurement failure recovers once and later cleanup does not restart again'

reset_state 1 '' down
test -z "$(pidof clash)"
if cfip_openclash_capture_state; then echo 'enabled but stopped OpenClash passed preflight' >&2; exit 1; fi
case "$CFIP_OPENCLASH_SERVICE_ERROR" in *"core is not running"*) ;; *) exit 1 ;; esac
test ! -s "$TMP/service.log"
echo 'enabled but stopped OpenClash fails before changes'

reset_state 0 live healthy
if cfip_openclash_capture_state; then echo 'disabled but live OpenClash passed preflight' >&2; exit 1; fi
test "$(cat "$TMP/enable")" = 0; test ! -s "$TMP/service.log"
echo 'disabled with a live core is rejected without stopping it'

reset_state 1 live down
if cfip_openclash_health_wait 2 1; then echo 'unhealthy controller passed its bounded health timeout' >&2; exit 1; fi
test -z "$(cat "$TMP/service.log")"
test "$(cat "$TMP/enable")" = 1
echo 'local controller timeout fails closed without service or node changes'

reset_state 1 live healthy
uci() { return 1; }
if cfip_openclash_capture_state; then echo 'unreadable enable passed preflight' >&2; exit 1; fi
case "$CFIP_OPENCLASH_SERVICE_ERROR" in *"cannot read"*) ;; *) exit 1 ;; esac
unset -f uci
echo 'unreadable enable fails closed'

reset_state 1 live healthy
cfip_openclash_capture_state; CFIP_STOP_SERVICE=false
stop_service_for_measurement
test -z "$CFIP_STOPPED_MODE"; test "$(cat "$TMP/enable")" = 1; test ! -s "$TMP/service.log"
CFIP_STOP_SERVICE=true
echo 'stop_service disabled preserves a healthy service'

reset_state 1 live healthy
cfip_openclash_capture_state
CFIP_OPENCLASH_EXPECTED_ENABLED=1
cfip_restart_service openclash normal
test "$CFIP_OPENCLASH_SERVICE_APPLIED" = true
test "$CFIP_OPENCLASH_RECOVERY_ATTEMPTED" = false
test "$(cat "$TMP/restart-count")" = 1
echo 'stop_service disabled applies the updated service once without claiming a recovery'

reset_state 1 live healthy
cfip_openclash_capture_state
printf '0\n' >"$TMP/enable"
if cfip_restart_service openclash normal; then echo 'external OpenClash disable was overwritten' >&2; exit 1; fi
test "$(cat "$TMP/enable")" = 0; test ! -s "$TMP/service.log"
case "$CFIP_OPENCLASH_SERVICE_ERROR" in *"refusing to re-enable it"*) ;; *) exit 1 ;; esac
echo 'an externally detectable disable is preserved before service apply'

reset_state 1 live healthy no-core; CFIP_OPENCLASH_EXPECTED_ENABLED=1
if cfip_restart_service openclash recovery; then echo 'restart without core passed' >&2; exit 1; fi
test "$(cat "$TMP/restart-count")" = 1
case "$CFIP_OPENCLASH_SERVICE_ERROR" in *"stable core"*) ;; *) exit 1 ;; esac
echo 'init restart zero without core is a failed recovery'

reset_state 1 live healthy start-fail; CFIP_OPENCLASH_EXPECTED_ENABLED=1; CFIP_OPENCLASH_CF_STOPPED=true; CFIP_STOPPED_MODE=openclash
CFIP_OPENCLASH_FILE_WRITTEN=true
if restore_stopped_service_if_needed; then echo 'start_fail state passed restoration' >&2; exit 1; fi
test "$(cat "$TMP/enable")" = 0; test "$(cat "$TMP/restart-count")" = 1; test -z "$CFIP_STOPPED_MODE"
test "$CFIP_OPENCLASH_FILE_WRITTEN" = true
CFIP_STOPPED_MODE=openclash
restore_stopped_service_if_needed || :
test "$(cat "$TMP/restart-count")" = 1
echo 'OpenClash self-disable after start failure is not retried'

reset_state 1 live healthy
CFIP_OPENCLASH_SERVICE_ERROR=""
short_health_calls=0
cfip_openclash_health_once() {
  short_health_calls=$((short_health_calls + 1))
  if ((short_health_calls == 1)); then printf '\n' >"$TMP/pid"; return 0; fi
  return 1
}
if cfip_openclash_health_wait 2 1; then echo 'short-lived core PID passed stable health gate' >&2; exit 1; fi
test "$short_health_calls" = 1
unset -f cfip_openclash_health_once
echo 'a short-lived core PID cannot satisfy stable health verification'

reset_state 0 '' down
CFIP_OPENCLASH_CONFIG="$TMP/openclash.yaml"
printf 'original\n' >"$CFIP_OPENCLASH_CONFIG"
CFIP_TXN_DIR=""; CFIP_RUN_ID=guard-disabled
cfip_txn_prepare openclash
cfip_openclash_apply_selected() { printf 'updated\n' >"$CFIP_OPENCLASH_CONFIG"; }
cfip_openclash_readback_selected() { return 0; }
printf '[]\n' >"$TMP/selected.json"
cfip_txn_apply openclash "$TMP/selected.json"
test "$CFIP_OPENCLASH_FILE_WRITTEN" = true
test "$CFIP_OPENCLASH_SERVICE_APPLIED" = false
test "$(cat "$TMP/enable")" = 0
test ! -s "$TMP/service.log"
cfip_txn_commit
echo 'disabled transaction writes nodes without restart and marks pending application'

CFIP_MODE=openclash; CFIP_ENABLED=true; CFIP_STATUS_DIR="$TMP/status"; CFIP_STATUS_FILE="$TMP/status/serialized.json"
CFIP_RUNTIME_DIR="$TMP/runtime"; CFIP_INIT_DIR="$TMP/status-init"; mkdir -p "$CFIP_INIT_DIR"
CFIP_RUN_ID=guard-status; CFIP_OPENCLASH_EXPECTED_ENABLED=0
CFIP_OPENCLASH_DEFERRED=true; CFIP_OPENCLASH_FILE_WRITTEN=true; CFIP_SPEEDTEST_COMPLETED=true
cfip_rill_status_json() { printf '{}'; }
cfip_adaptive_status_json() { printf '{}'; }
cfip_publisher_status_json() { printf '{}'; }
cfip_source_policy_json() { printf '{}'; }
cfip_operational_state_json() { printf '{}'; }
cfip_operational_why_run() { printf ''; }
write_status false done warning 'Nodes updated; OpenClash is disabled and the changes will take effect after it is started'
jq -e '.running == true and .active_run == false and .last_result == "warning" and .speedtestCompleted == true and .service.expectedEnabled == 0 and .service.nodeFileWritten == true and .service.deferredUntilServiceStart == true' "$CFIP_STATUS_FILE" >/dev/null
CFIP_OPENCLASH_FILE_WRITTEN=false; CFIP_OPENCLASH_SERVICE_APPLIED=true
CFIP_OPENCLASH_RECOVERY_VERIFIED=true; CFIP_OPENCLASH_DEFERRED=false
write_status false failed error 'speedtest failed; original service restored'
jq -e '.active_run == false and .last_result == "error" and .service.recoveryVerified == true and .service.serviceApplied == false and .service.nodeFileWritten == false' "$CFIP_STATUS_FILE" >/dev/null
printf '#!/bin/sh\nexit 0\n' >"$CFIP_INIT_DIR/openclash"; chmod +x "$CFIP_INIT_DIR/openclash"
cfip_openclash_health_once() { : >"$TMP/unexpected-status-probe"; return 1; }
write_status false done warning 'status semantics check'
jq -e '.openclash_running == true' "$CFIP_STATUS_FILE" >/dev/null
test ! -e "$TMP/unexpected-status-probe"
echo 'status serializer exposes task, file-write and disabled-service states separately'

# The one-file entry point uses the same status boundaries and health endpoint.
source "$ROOT/cf-openwrt-auto.sh"
INIT_DIR="$TMP/init"; OPENCLASH_CONFIG="$TMP/openclash.yaml"
reset_state 0 '' down
openclash_capture_state
LAST_RESULT=success
restart_service openclash 2>"$TMP/standalone-warning"
test "$LAST_RESULT" = warning
grep -q 'nodes updated; OpenClash is disabled' "$TMP/standalone-warning"
test "$(cat "$TMP/enable")" = 0; test ! -s "$TMP/service.log"
echo 'independent script reports disabled OpenClash as a warning without restart'

old_url='https://raw.githubusercontent.com/hello-yunshu/use-cloudflare-ip/main/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto'
new_url='https://raw.githubusercontent.com/hello-yunshu/luci-app-cloudflare-ip/main/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto'
printf '%s\n' "$old_url" >"$TMP/update-url"; : >"$TMP/migration.log"
"$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/migrate-self-update-url.sh"
test "$(cat "$TMP/update-url")" = "$new_url"
test "$(wc -l <"$TMP/migration.log" | tr -d ' ')" = 1
"$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/migrate-self-update-url.sh"
test "$(cat "$TMP/update-url")" = "$new_url"
test "$(wc -l <"$TMP/migration.log" | tr -d ' ')" = 1
printf '%s\n' 'https://mirror.example/custom/cf-ip-auto' >"$TMP/update-url"
"$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/migrate-self-update-url.sh"
test "$(cat "$TMP/update-url")" = 'https://mirror.example/custom/cf-ip-auto'
rg -q 'migrate-self-update-url.sh' "$ROOT/package/luci-app-cloudflare-ip/Makefile"
rg -q 'PKG_RELEASE:=5' "$ROOT/package/luci-app-cloudflare-ip/Makefile"
rg -q '/usr/libexec/cf-ip/migrate-self-update-url.sh' "$ROOT/package/luci-app-cloudflare-ip/Makefile"
mkdir -p "$TMP/package-build/root/usr/libexec/cf-ip" "$TMP/package-root/usr/libexec/cf-ip"
cp "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/migrate-self-update-url.sh" "$TMP/package-build/root/usr/libexec/cf-ip/"
INSTALL_BIN=install; PKG_BUILD_DIR="$TMP/package-build"; TARGET_ROOT="$TMP/package-root"
"$INSTALL_BIN" -m 0755 "$PKG_BUILD_DIR/root/usr/libexec/cf-ip/migrate-self-update-url.sh" "$TARGET_ROOT/usr/libexec/cf-ip/"
printf '%s\n' "$old_url" >"$TMP/update-url"; : >"$TMP/migration.log"
"$TARGET_ROOT/usr/libexec/cf-ip/migrate-self-update-url.sh"
test "$(cat "$TMP/update-url")" = "$new_url"
echo 'official URL migration is exact/idempotent, custom URLs are preserved, package hook installs it'

echo 'OpenClash service guard contract passed'
