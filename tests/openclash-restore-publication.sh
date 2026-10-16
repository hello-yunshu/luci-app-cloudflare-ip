#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
load_config() { return 0; }
cfip_openclash_capture_state() { CFIP_OPENCLASH_EXPECTED_ENABLED=0; CFIP_OPENCLASH_INITIAL_HEALTHY=false; CFIP_OPENCLASH_DEFERRED=true; }
cfip_openclash_check_before_write() { return 0; }
cfip_begin_recovery() { return 0; }
cp() {
    if [[ "${!#}" == */openclash.written.yaml ]]; then
        [[ "$fault" != written-snapshot ]] || return 1
        if [[ "$fault" == external-edit ]]; then printf 'external user edit\n' >"$CFIP_OPENCLASH_CONFIG"; fi
    fi
    command cp "$@"
}
mv() {
    if [[ "$fault" == publish-rename && "${!#}" == "$CFIP_OPENCLASH_CONFIG" ]]; then return 1; fi
    command mv "$@"
}
failures=0
for fault in written-snapshot publish-rename external-edit success; do
 if (
    case_dir="$TMP/$fault"; mkdir -p "$case_dir/runtime"
    CFIP_RUNTIME_DIR="$case_dir/runtime"; CFIP_LOG_FILE="$case_dir/trace.log"
    CFIP_OPENCLASH_CONFIG="$case_dir/config.yaml"; CFIP_OPENCLASH_BACKUP_COUNT=3
    CFIP_CLEANUP_DONE=false
    printf 'user original\n' >"$CFIP_OPENCLASH_CONFIG"
    printf 'restored candidate\n' >"$CFIP_OPENCLASH_CONFIG.bak.20200101000000"
    if cmd_oc_restore_backup 20200101000000 >"$case_dir/result.json"; then rc=0; else rc=$?; fi
    printf '%s: rc=%s live=%s\n' "$fault" "$rc" "$(cat "$CFIP_OPENCLASH_CONFIG")"
    case "$fault" in
      success) [[ "$rc" == 0 && "$(cat "$CFIP_OPENCLASH_CONFIG")" == 'restored candidate' ]] ;;
      external-edit) [[ "$rc" != 0 && "$(cat "$CFIP_OPENCLASH_CONFIG")" == 'external user edit' ]] ;;
      *) [[ "$rc" != 0 && "$(cat "$CFIP_OPENCLASH_CONFIG")" == 'user original' ]] ;;
    esac
 ); then :; else failures=$((failures+1)); fi
done
test "$failures" -eq 0
