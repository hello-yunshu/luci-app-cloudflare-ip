#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"

load_config() { :; }
cfip_openclash_capture_backup_context() {
	CFIP_OPENCLASH_RUNTIME_CONFIG="$TMP/main.yaml"
	CFIP_OPENCLASH_RUNTIME_ID=""
	CFIP_OPENCLASH_TARGET_CONFIG="$TMP/proxy_provider/nodes.yaml"
	CFIP_OPENCLASH_PROVIDER_NAME=local
	CFIP_OPENCLASH_EXPECTED_ENABLED=0
	CFIP_OPENCLASH_INITIAL_HEALTHY=false
	CFIP_OPENCLASH_DEFERRED=true
}
cfip_openclash_capture_state() { cfip_openclash_capture_backup_context; }
cfip_openclash_check_before_write() { return 0; }
provider_refresh_calls=0
cfip_openclash_provider_refresh() { provider_refresh_calls=$((provider_refresh_calls+1)); return 99; }

mkdir -p "$TMP/proxy_provider"
cat >"$TMP/main.yaml" <<'YAML'
external-controller: 127.0.0.1:9090
proxy-providers:
  local:
    type: file
    path: ./proxy_provider/nodes.yaml
proxy-groups:
  - name: proxy
    type: select
    use: [local]
YAML
cat >"$TMP/proxy_provider/nodes.yaml" <<'YAML'
proxies:
  - name: Original
    type: vless
    server: domain.example
    port: 443
YAML
cp "$TMP/proxy_provider/nodes.yaml" "$TMP/proxy_provider/nodes.yaml.bak.20200101000000"

# A whole-main-config legacy backup must be rejected before a txn directory is made.
cp "$TMP/main.yaml" "$TMP/proxy_provider/nodes.yaml.bak.20200101000001"
CFIP_RUNTIME_DIR="$TMP/runtime"; mkdir -p "$CFIP_RUNTIME_DIR"
if cmd_oc_restore_backup 20200101000001 >"$TMP/rejected.json" 2>/dev/null; then
	echo 'FAIL: whole-config backup was accepted as provider data' >&2
	exit 1
fi
[[ "$(jq -r '.error' "$TMP/rejected.json")" == *'provider-only document'* ]]
[[ -z "$(find "$CFIP_RUNTIME_DIR" -maxdepth 1 -name 'txn-*' -print -quit)" ]]
cmp -s "$TMP/proxy_provider/nodes.yaml" "$TMP/proxy_provider/nodes.yaml.bak.20200101000000"
echo 'PASS legacy whole-config backup rejected before transaction allocation'

# Invalid data passed directly to the publisher is rejected before publication.
printf 'not: a-provider-document\n' >"$TMP/invalid.yaml"
CFIP_OPENCLASH_TARGET_CONFIG="$TMP/proxy_provider/nodes.yaml"
if cfip_openclash_provider_document_valid "$TMP/invalid.yaml"; then
	echo 'FAIL invalid backup passed provider validation' >&2
	exit 1
fi
cmp -s "$TMP/proxy_provider/nodes.yaml" "$TMP/proxy_provider/nodes.yaml.bak.20200101000000"
echo 'PASS invalid provider backup rejected without changing the live provider'

# Failure rollback restores provider bytes only and does not start OpenClash.
mkdir -p "$TMP/txn"
CFIP_TXN_DIR="$TMP/txn"
CFIP_OPENCLASH_CONFIG="$TMP/proxy_provider/nodes.yaml"
CFIP_OPENCLASH_RUNTIME_CONFIG="$TMP/main.yaml"
CFIP_OPENCLASH_TARGET_CONFIG="$TMP/proxy_provider/nodes.yaml"
CFIP_OPENCLASH_EXPECTED_ENABLED=0
CFIP_OPENCLASH_CF_STOPPED=false
CFIP_OPENCLASH_SERVICE_APPLIED=false
CFIP_OPENCLASH_RESTART_ATTEMPTS=1
CFIP_OPENCLASH_SERVICE_ERROR=fixture-start-failure
CFIP_TXN_STATE=MUTATED
CFIP_TXN_MODE=openclash
cp "$TMP/main.yaml" "$TMP/txn/openclash-main.yaml"
cp "$TMP/proxy_provider/nodes.yaml" "$TMP/txn/openclash.yaml"
cp "$TMP/proxy_provider/nodes.yaml" "$TMP/provider-original.yaml"
cp "$TMP/main.yaml" "$TMP/main-original.yaml"
cat >"$TMP/candidate.yaml" <<'YAML'
proxies:
  - name: Candidate
    type: vless
    server: 104.16.1.1
    port: 443
YAML
cp "$TMP/candidate.yaml" "$TMP/txn/openclash.written.yaml"
cp "$TMP/candidate.yaml" "$TMP/proxy_provider/nodes.yaml"
CFIP_TXN_ORIGINAL_RUNNING=false
CFIP_TXN_ROLLED_BACK=false
if cfip_txn_rollback openclash >/dev/null 2>&1; then rollback_rc=0; else rollback_rc=$?; fi
[[ "$rollback_rc" == 0 ]] || { echo "FAIL: provider-only rollback failed (rc=$rollback_rc; ${CFIP_RECOVERY_ERROR:-no detail})" >&2; exit 1; }
cmp -s "$TMP/proxy_provider/nodes.yaml" "$TMP/provider-original.yaml"
cmp -s "$TMP/main.yaml" "$TMP/main-original.yaml"
[[ "$CFIP_TXN_ROLLED_BACK" == true ]]
[[ "$CFIP_OPENCLASH_SERVICE_APPLIED" == false ]]
[[ "$provider_refresh_calls" == 0 ]]
echo 'PASS provider-only rollback restores the provider without restarting OpenClash'
