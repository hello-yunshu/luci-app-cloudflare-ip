#!/usr/bin/env bash
# Inject storage/transform failures around the real transaction state machine.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/transaction.sh"
cfip_begin_recovery() { :; }
cfip_openclash_capture_state() { CFIP_OPENCLASH_EXPECTED_ENABLED=0; CFIP_OPENCLASH_INITIAL_HEALTHY=false; }
cfip_openclash_check_before_write() { :; }
cfip_openclash_readback_selected() {
    [[ "$fault" != staged-readback ]] || return 1
    [[ "$fault" != live-readback || "$CFIP_OPENCLASH_CONFIG" != "$case_dir/live.yaml" ]]
}
cfip_openclash_apply_selected() {
    printf 'transaction candidate\n' >"$CFIP_OPENCLASH_CONFIG"
    if [[ "$fault" == outside-edit ]]; then printf 'external user edit\n' >"$case_dir/live.yaml"; fi
    [[ "$fault" != transform-after-write ]]
}
cp() {
    if [[ "$fault" == written-snapshot && "${!#}" == */openclash.written.yaml ]]; then return 1; fi
    if [[ "$fault" == candidate-copy && "${!#}" == */openclash.candidate.yaml ]]; then return 1; fi
    if [[ "$fault" == backup-copy && "${!#}" == "$case_dir/live.yaml.bak."* ]]; then return 1; fi
    command cp "$@"
}
mv() {
    if [[ "$fault" == publish-rename && "${!#}" == "$case_dir/live.yaml" ]]; then return 1; fi
    command mv "$@"
}
failures=0
for fault in transform-after-write written-snapshot candidate-copy backup-copy publish-rename staged-readback live-readback outside-edit; do
    case_dir="$TMP/$fault"; mkdir -p "$case_dir/runtime"
    CFIP_RUNTIME_DIR="$case_dir/runtime"; CFIP_RUN_ID=write-fault
    CFIP_TXN_DIR=""; CFIP_TXN_STATE=NONE; CFIP_TXN_APPLY=false
    CFIP_OPENCLASH_RESTART_ATTEMPTS=0; CFIP_OPENCLASH_CF_STOPPED=false
    CFIP_OPENCLASH_RECOVERY_ATTEMPTED=false; CFIP_OPENCLASH_SERVICE_APPLIED=false
    CFIP_OPENCLASH_FILE_WRITTEN=false; CFIP_OPENCLASH_SERVICE_ERROR=""
    CFIP_OPENCLASH_CONFIG="$case_dir/live.yaml"
    printf 'user original\n' >"$CFIP_OPENCLASH_CONFIG"
    command cp "$CFIP_OPENCLASH_CONFIG" "$case_dir/original.yaml"
    printf '[{"ip":"104.16.1.1","family":"ipv4"}]\n' >"$case_dir/selected.json"
    cfip_txn_prepare openclash
    if cfip_txn_apply openclash "$case_dir/selected.json"; then rc=0; else rc=$?; fi
    printf '%s: apply=%s state=%s rolledBack=%s applyActive=%s\n' "$fault" "$rc" "$CFIP_TXN_STATE" "$CFIP_TXN_ROLLED_BACK" "$CFIP_TXN_APPLY"
    expected="$case_dir/original.yaml"
    if [[ "$fault" == outside-edit ]]; then printf 'external user edit\n' >"$case_dir/external.yaml"; expected="$case_dir/external.yaml"; fi
    if ((rc == 0)) || ! cmp -s "$expected" "$CFIP_OPENCLASH_CONFIG" || [[ "$CFIP_TXN_APPLY" != false ]]; then
        printf 'FAIL: %s must reject while preserving the original live bytes and clearing apply state\n' "$fault" >&2
        failures=$((failures+1))
    fi
done
test "$failures" -eq 0
