#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${CFIP_TEST_LIB_DIR:-$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip}/transaction.sh"
TMP=$(mktemp -d);trap 'command rm -rf "$TMP"' EXIT
cfip_service_running(){ return 1; }
cfip_openclash_capture_state(){ CFIP_OPENCLASH_EXPECTED_ENABLED=0; CFIP_OPENCLASH_INITIAL_HEALTHY=false; }
uci(){ case "${1:-}" in changes) return 0;; export) [[ "$fault" != export ]] || return 23; command cat "$case_dir/user.uci";; *) return 1;; esac; }
printf(){
 if [[ "$fault" == fields && "$1" == '[]\n' ]] || [[ "$fault" == marker-present* && "${2:-}" == present ]] || [[ "$fault" == marker-absent && "${2:-}" == absent ]] || [[ "$fault" == enable && "${2:-}" == 0 ]]; then return 23;fi
 builtin printf "$@"
}
cp(){
 if [[ "$fault" == managed-copy && "${!#}" == */passwall-managed.json ]] || [[ "$fault" == config-copy && "${!#}" == */openclash.yaml ]];then return 23;fi
 command cp "$@"
}
rm(){ [[ "$fault" != marker-present-rmfail ]] || return 23;command rm "$@"; }
failures=0
faults=(fields export managed-copy marker-present marker-absent config-copy enable marker-present-rmfail)
[[ -z "${CFIP_TEST_ONLY_FAULT:-}" ]] || faults=("$CFIP_TEST_ONLY_FAULT")
for fault in "${faults[@]}";do
 case_dir="$TMP/$fault";mkdir -p "$case_dir/runtime" "$case_dir/status"
 CFIP_RUNTIME_DIR="$case_dir/runtime";CFIP_STATUS_DIR="$case_dir/status";CFIP_RUN_ID=prepare-fault
 CFIP_PASSWALL_STATE_FILE="$case_dir/state.json";CFIP_OPENCLASH_CONFIG="$case_dir/live.yaml"
 echo retained-user-config >"$case_dir/user.uci";echo retained-openclash >"$CFIP_OPENCLASH_CONFIG"
 mode=passwall;case "$fault" in config-copy|enable) mode=openclash;;esac
 if [[ "$fault" != marker-absent ]];then echo '{"retained":true}' >"$CFIP_PASSWALL_STATE_FILE";fi
 CFIP_TXN_DIR=;CFIP_TXN_STATE=NONE;CFIP_RECOVERY_ERROR=
 rc=0;cfip_txn_prepare "$mode" || rc=$?
 if [[ "$rc" == 0 || "$CFIP_TXN_STATE" == PREPARED ]];then echo "FAIL $fault accepted failed snapshot write";failures=$((failures+1));continue;fi
 grep -qx retained-openclash "$CFIP_OPENCLASH_CONFIG"
 grep -qx retained-user-config "$case_dir/user.uci"
 if [[ "$fault" == marker-present-rmfail ]];then
  [[ -n "$CFIP_TXN_DIR" && -d "$CFIP_TXN_DIR" && "$CFIP_RECOVERY_ERROR" == *"$CFIP_TXN_DIR"* ]] || { echo 'FAIL incomplete cleanup lost journal/error';exit 1; }
 else
  [[ -z "$CFIP_TXN_DIR" && -z "$(find "$CFIP_RUNTIME_DIR" -name 'txn-*' -print)" ]] || { echo "FAIL $fault left own failed preparation";exit 1; }
  saved_fault=$fault;fault=none
  cfip_txn_prepare "$mode"
  [[ "$CFIP_TXN_STATE" == PREPARED && -z "$CFIP_RECOVERY_ERROR" ]]
  command rm -rf "$CFIP_TXN_DIR";CFIP_TXN_DIR=;fault=$saved_fault
 fi
 echo "PASS $fault refuses failure, preserves input and handles own workspace"
done
[[ "$failures" == 0 ]]
