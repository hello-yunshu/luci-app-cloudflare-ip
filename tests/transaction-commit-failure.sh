#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/runtime" "$TMP/status"
cat >"$TMP/passwall.uci" <<'EOF_UCI'
passwall.s1.address='cdn.example.com'
passwall.s1.remarks='Node A'
EOF_UCI
cat >"$TMP/managed.json" <<'EOF_STATE'
{"schemaVersion":1,"sections":[{"section":"s1","domain":"cdn.example.com","baseRemarks":"Node A","lastAddress":"cdn.example.com","lastRemarks":"Node A"}]}
EOF_STATE
cp "$TMP/passwall.uci" "$TMP/passwall.before"
cp "$TMP/managed.json" "$TMP/managed.before"
cat >"$TMP/bin/uci" <<'EOF_UCI_BIN'
#!/usr/bin/env bash
set -euo pipefail
state="${UCI_FAKE_STATE:?}"
[[ "${1:-}" == -q ]] && shift
case "${1:-}" in
  changes) : ;;
  export) cat "$state" ;;
  import) cat >"$state" ;;
  revert|commit) cat >/dev/null || true ;;
  get) key="${2#passwall.}"; section="${key%%.*}"; field="${key#*.}"; sed -n "s/^passwall\.${section}\.${field}=//p" "$state" | head -1 | sed "s/^'//;s/'$//" ;;
  set) pair="$2"; path="${pair%%=*}"; value="${pair#*=}"; awk -v p="$path" -v v="$value" 'BEGIN{done=0} {k=$0; sub(/=.*/,"",k); if(k==p){print k "=\x27" v "\x27"; done=1} else print} END{if(!done) print p "=\x27" v "\x27"}' "$state" >"$state.next"; mv "$state.next" "$state" ;;
  *) exit 1 ;;
esac
EOF_UCI_BIN
chmod +x "$TMP/bin/uci"
export PATH="$TMP/bin:$PATH" UCI_FAKE_STATE="$TMP/passwall.uci" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_STATUS_DIR="$TMP/status" CFIP_LOG_FILE="$TMP/log"
export CFIP_RUN_ID=commit-failure CFIP_PASSWALL_STATE_FILE="$TMP/managed.json" CFIP_PASSWALL_TARGET_DOMAIN=cdn.example.com CFIP_PASSWALL_NAME_SUFFIX=' [CF-{n}]'
source "${CFIP_TEST_LIB_DIR:-$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip}/common.sh"
source "${CFIP_TEST_LIB_DIR:-$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip}/transaction.sh"
export CFIP_LIB_DIR="${CFIP_TEST_LIB_DIR:-$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip}"
source "${CFIP_TEST_CLI:-$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2}"
CFIP_RUN_ID=commit-failure
CFIP_PASSWALL_TARGET_DOMAIN=cdn.example.com;CFIP_PASSWALL_NAME_SUFFIX=' [CF-{n}]'
cfip_restart_service(){ return 0; }
cat >"$TMP/selected.json" <<'EOF_SELECTED'
[{"ip":"104.16.1.1","family":"ipv4"}]
EOF_SELECTED
cfip_txn_prepare passwall
cfip_txn_apply passwall "$TMP/selected.json"
test -f "$CFIP_TXN_DIR/passwall-managed.json.pending"
mv() {
    if [[ "${2:-}" == "$CFIP_PASSWALL_STATE_FILE" && "${1:-}" == *.pending ]]; then return 1; fi
    command mv "$@"
}
rc=0; cfip_txn_commit || rc=$?
test "$rc" -ne 0
cfip_txn_rollback passwall
cmp -s "$TMP/passwall.uci" "$TMP/passwall.before"
cmp -s "$TMP/managed.json" "$TMP/managed.before"
test "$CFIP_TXN_ROLLED_BACK" = true
echo 'transaction commit failure rollback behavior passed'
# A completed configuration commit must not silently hide retained journals,
# and cleanup failure must not roll the already committed configuration back.
unset -f mv
cfip_txn_prepare passwall
cfip_txn_apply passwall "$TMP/selected.json"
cp "$CFIP_TXN_DIR/passwall-managed.json.pending" "$TMP/committed.expected"
cp "$TMP/passwall.uci" "$TMP/config.committed"
rm(){ [[ "${!#}" != "$CFIP_TXN_DIR" ]] || return 23;command rm "$@"; }
rc=0;cfip_txn_commit || rc=$?
if [[ "$rc" == 0 ]];then echo 'FAIL cleanup failure reported successful commit and lost retained path' >&2;exit 1;fi
[[ "$CFIP_TXN_COMMITTED" == true && "$CFIP_TXN_STATE" == COMMITTED && -d "$CFIP_TXN_DIR" && "$CFIP_RECOVERY_ERROR" == *"$CFIP_TXN_DIR"* ]]
cmp "$TMP/managed.json" "$TMP/committed.expected"
cfip_txn_rollback passwall
cmp "$TMP/managed.json" "$TMP/committed.expected"
cmp "$TMP/passwall.uci" "$TMP/config.committed"
echo 'committed configuration survives cleanup failure; retained journal/root error are explicit'
CFIP_MODE=passwall;CFIP_STOPPED_MODE="";CFIP_CLEANUP_DONE=false
rc=0;sync_recovery_failure 'sync transaction commit failed' >"$TMP/result.json" || rc=$?
[[ "$rc" -ne 0 ]]
jq -e '.success==false and .configurationCommitted==true and .rolledBack==false and .recoveryRequired==true and (.recoveryError|contains("Configuration committed"))' "$TMP/result.json" >/dev/null
cmp "$TMP/managed.json" "$TMP/committed.expected"
echo 'sync failure envelope distinguishes committed configuration from pending journal cleanup'
