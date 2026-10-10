#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/init"
export LEGACY_TMP="$TMP" PATH="$TMP/bin:$PATH" INIT_DIR="$TMP/init"
cat >"$TMP/bin/uci" <<'UCI'
#!/usr/bin/env bash
[[ "$1" != -q ]] || shift
[[ ! -e "$LEGACY_TMP/read-fail" || "$1" != get ]] || exit 1
case "$1:$2" in
get:openclash.config.enable) cat "$LEGACY_TMP/enable" ;;
get:openclash.config.cn_port) printf 9090 ;;
set:openclash.config.enable=*) printf '%s' "${2#*=}" >"$LEGACY_TMP/enable" ;;
commit:openclash) : ;;
*) exit 1 ;;
esac
UCI
cat >"$TMP/bin/pidof" <<'PID'
#!/usr/bin/env bash
[[ "$(cat "$LEGACY_TMP/pid")" == live ]] || exit 1
printf 1234
PID
cat >"$TMP/bin/curl" <<'CURL'
#!/usr/bin/env bash
while (($#)); do case "$1" in --output) output="$2"; shift 2 ;; *) shift ;; esac; done
printf '{"proxies":[]}' >"$output"; printf 200
CURL
cat >"$TMP/init/openclash" <<'INIT'
#!/usr/bin/env bash
printf '%s\n' "$1" >>"$LEGACY_TMP/service.log"
case "$1" in stop) printf down >"$LEGACY_TMP/pid" ;; restart) cat "$LEGACY_TMP/restart-pid" >"$LEGACY_TMP/pid" ;; esac
INIT
chmod +x "$TMP/bin/uci" "$TMP/bin/pidof" "$TMP/bin/curl" "$TMP/init/openclash"
fixture() {
 rm -f "$TMP/read-fail"
 printf '%s' "$1" >"$TMP/enable"; printf '%s' "$2" >"$TMP/pid"; printf '%s' "${3:-live}" >"$TMP/restart-pid"
 printf 0 >"$TMP/clock"; : >"$TMP/service.log"
 mkdir -p "$TMP/state"
 printf '{"best_ips":["104.16.1.2"]}' >"$TMP/state/status.json"
 cat >"$TMP/config.yaml" <<'YAML'
secret: test-only
proxies:
  - name: CF
    type: vless
    server: cdn.example.com
    port: 443
    uuid: isolated-test
    tls: true
    network: xhttp
    servername: cdn.example.com
    xhttp-opts:
      headers:
        Host: cdn.example.com
YAML
 cp "$TMP/config.yaml" "$TMP/original.yaml"
}
# Evaluate the original command functions, with only expensive measurement and
# clock operations stubbed. No sibling v2 engine or shared library is provided.
run_entry() {
 source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/$entry"
 STATUS_DIR="$TMP/state"; STATUS_FILE="$TMP/state/status.json"; LOG_FILE="$TMP/log"; LOCK_FILE="$TMP/lock"
 load_uci_config() { MODE=openclash; OPENCLASH_CONFIG="$TMP/config.yaml"; OPENCLASH_TARGET_DOMAIN=cdn.example.com; WORK_DIR="$TMP"; IP_COUNT=1; AUTO_UPDATE=false; STARTUP_DELAY=0; [[ "$scenario" != stop-disabled ]] || STOP_SERVICE_BEFORE_SPEEDTEST=false; }
 date() { if [[ "${1:-}" == +%s ]]; then cat "$TMP/clock"; else command date "$@"; fi; }
 sleep() { printf '%s' "$(( $(cat "$TMP/clock") + $1 ))" >"$TMP/clock"; /bin/sleep 0.01; }
 self_update() { :; }; download_speedtest() { :; }; prepare_work_dir() { :; }; apply_startup_delay() { :; }
 run_speedtest() { [[ "$scenario" != measurement-fail ]] || die 'isolated speedtest failure'; FAST_IPS=(104.16.1.1); }
 if [[ "${action:-run}" == sync ]]; then
   CLI_ARG1=openclash; cmd_sync
 elif [[ "${action:-run}" == restore ]]; then
   CLI_ARG1=20261010120000; cmd_oc_restore_backup
 elif [[ "${action:-run}" == selected ]]; then
   CLI_ARG1="$TMP/selected.json"; CLI_ARG2=openclash; cmd_apply_selected
 elif [[ "$scenario" == daemon ]]; then
   cron_interval_seconds() { printf 0; }
   sleep() { return 73; } # Bound the legacy daemon after its first completed cycle.
   cmd_daemon
 else
   cmd_run
 fi
}
for entry in cf-ip-auto cf-ip-auto-legacy; do
 for scenario in disabled healthy stop-disabled enabled-down inconsistent read-fail recovery-fail measurement-fail daemon; do
  case "$scenario" in
   disabled|daemon) fixture 0 down ;;
   healthy|stop-disabled|measurement-fail) fixture 1 live ;;
   inconsistent) fixture 0 live ;;
   read-fail) fixture 1 live; : >"$TMP/read-fail" ;;
   enabled-down) fixture 1 down ;;
   recovery-fail) fixture 1 live down ;;
  esac
  set +e
  (set -e; run_entry) >"$TMP/result" 2>"$TMP/errors"
  rc=$?
  set -e
  case "$scenario" in
   disabled)
    test "$rc" = 0; test ! -s "$TMP/service.log"; test "$(cat "$TMP/enable")" = 0
    jq -e '.success and .last_result=="warning" and .nodeFileWritten and (.serviceApplied|not)' "$TMP/result" >/dev/null
    jq -e '.last_result=="warning" and .service.deferredUntilServiceStart and (.active_run|not)' "$TMP/state/status.json" >/dev/null ;;
   healthy)
    test "$rc" = 0; test "$(grep -c '^restart$' "$TMP/service.log")" = 1
    jq -e '.success and .serviceApplied' "$TMP/result" >/dev/null ;;
   stop-disabled)
    test "$rc" = 0; test "$(grep -c '^restart$' "$TMP/service.log")" = 1
    ! grep -q '^stop$' "$TMP/service.log"; jq -e '.success and .serviceApplied' "$TMP/result" >/dev/null ;;
   enabled-down|inconsistent|read-fail)
    test "$rc" != 0; test ! -s "$TMP/service.log"; cmp -s "$TMP/config.yaml" "$TMP/original.yaml"
    jq -e '.last_result=="error" and (.service.expectedEnabled==null or .service.expectedEnabled==0 or .service.expectedEnabled==1)' "$TMP/state/status.json" >/dev/null
    if [[ "$scenario" == read-fail ]]; then jq -e '.error|contains("cannot read openclash.config.enable")' "$TMP/state/status.json" >/dev/null; fi ;;
   recovery-fail)
    test "$rc" != 0; test "$(grep -c '^restart$' "$TMP/service.log")" = 1
    jq -e '.last_result=="error" and .service.nodeFileWritten and (.service.serviceApplied|not)' "$TMP/state/status.json" >/dev/null ;;
   measurement-fail)
    test "$rc" != 0; test "$(grep -c '^restart$' "$TMP/service.log")" = 1
    cmp -s "$TMP/config.yaml" "$TMP/original.yaml"; jq -e '.last_result=="error" and (.active_run|not)' "$TMP/state/status.json" >/dev/null ;;
   daemon)
    test "$rc" = 73; test ! -s "$TMP/service.log"
    jq -e '.last_result=="warning" and .service.nodeFileWritten and (.active_run|not)' "$TMP/state/status.json" >/dev/null ;;
  esac
 done
 echo "$entry preserves native CLI/daemon and guarded disabled/healthy/failure behavior without v2"
done

# Check the other installed legacy OpenClash entry points. These run through
# the same native shell file, without the v2 engine or its libraries.
for entry in cf-ip-auto-legacy; do
 for scenario in sync-disabled sync-healthy restore-disabled restore-healthy selected-read-fail; do
  action="${scenario%%-*}"
  [[ "$action" != selected ]] || action=selected
  case "$scenario" in
   *-disabled) fixture 0 down ;;
   *-healthy) fixture 1 live ;;
   selected-read-fail) fixture 1 live; : >"$TMP/read-fail"; printf '[{"ip":"104.16.1.1"}]' >"$TMP/selected.json" ;;
  esac
  if [[ "$action" == restore ]]; then
   printf 'secret: restored-test\nproxies:\n  - name: Backup\n    type: vless\n    server: backup.example.com\n    port: 443\n    uuid: backup-test\n    tls: true\n    network: xhttp\n' >"$TMP/config.yaml.bak.20261010120000"
  fi
  set +e
  (set -e; run_entry) >"$TMP/result" 2>"$TMP/errors"
  rc=$?
  set -e
  case "$scenario" in
   sync-disabled)
    test "$rc" = 0; test ! -s "$TMP/service.log"
    jq -e '.success and .last_result=="warning" and .nodeFileWritten and (.serviceApplied|not)' "$TMP/result" >/dev/null
    jq -e '.last_result=="warning" and .service.deferredUntilServiceStart' "$TMP/state/status.json" >/dev/null ;;
   sync-healthy)
    test "$rc" = 0; test "$(grep -c '^restart$' "$TMP/service.log")" = 1
    jq -e '.last_result=="success" and .service.serviceApplied' "$TMP/state/status.json" >/dev/null ;;
   restore-disabled)
    test "$rc" = 0; test ! -s "$TMP/service.log"
    jq -e '.success and .last_result=="warning" and .nodeFileWritten and (.serviceApplied|not)' "$TMP/result" >/dev/null
    jq -e '.last_result=="warning" and .service.deferredUntilServiceStart' "$TMP/state/status.json" >/dev/null ;;
   restore-healthy)
    test "$rc" = 0; test "$(grep -c '^restart$' "$TMP/service.log")" = 1
    jq -e '.success and .serviceApplied and .last_result=="success"' "$TMP/result" >/dev/null ;;
   selected-read-fail)
    test "$rc" != 0; test ! -s "$TMP/service.log"; test "$(cat "$TMP/enable")" = 1 ;;
  esac
 done
 echo "$entry sync, selected-node and backup restore entry points preserve OpenClash state and report apply results"
done
