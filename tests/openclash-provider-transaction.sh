#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/main-dir/proxy_provider" "$TMP/runtime" "$TMP/bin"
export CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_STATUS_DIR="$TMP/status" CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip" CFIP_OPENCLASH_BACKUP_COUNT=3 CFIP_OPENCLASH_TARGET_DOMAIN=cdn.example.com
mkdir -p "$CFIP_STATUS_DIR"
cat >"$TMP/main-dir/clash.yaml" <<'YAML'
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
cat >"$TMP/main-dir/proxy_provider/nodes.yaml" <<'YAML'
proxies:
  - name: edge
    type: vless
    server: cdn.example.com
    port: 443
    tls: true
YAML
cp "$TMP/main-dir/clash.yaml" "$TMP/main-copy.yaml"
cp "$TMP/main-dir/proxy_provider/nodes.yaml" "$TMP/provider-original.yaml"
cat >"$TMP/bin/uci" <<'UCI'
#!/usr/bin/env bash
[[ "$*" == "-q changes openclash" ]] && exit 0
[[ "$*" == "-q get openclash.config.enable" ]] && { printf 1; exit 0; }
exit 1
UCI
chmod +x "$TMP/bin/uci"; export PATH="$TMP/bin:$PATH"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/openclash-readback.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/transaction.sh"
CFIP_OPENCLASH_CONFIG="$TMP/provider-original.yaml"
CFIP_OPENCLASH_RUNTIME_CONFIG="$TMP/main-dir/clash.yaml"
CFIP_OPENCLASH_RUNTIME_ID='111:100:/usr/bin/mihomo:/fixture/clash.yaml'
CFIP_OPENCLASH_TARGET_CONFIG=''
CFIP_OPENCLASH_PROVIDER_NAME=''
CFIP_OPENCLASH_EXPECTED_ENABLED=1
CFIP_OPENCLASH_INITIAL_RUNNING=true
CFIP_OPENCLASH_INITIAL_HEALTHY=true
CFIP_OPENCLASH_CF_STOPPED=false
CFIP_OPENCLASH_RESTART_ATTEMPTS=0
CFIP_OPENCLASH_SERVICE_APPLIED=false
CFIP_OPENCLASH_HOT_APPLIED=false; CFIP_OPENCLASH_MAINTENANCE_RESTARTED=false
CFIP_OPENCLASH_SERVICE_ERROR=''
CFIP_OPENCLASH_FILE_WRITTEN=false
CFIP_OPENCLASH_DEFERRED=false
CFIP_TARGET_DOMAINS=cdn.example.com
CFIP_OPENCLASH_NAME_SUFFIX=' [CF-{n}]'
CFIP_OPENCLASH_TRANSPORT_FILTER=''
CFIP_RUN_ID=provider-fixture
cfip_openclash_capture_state(){ CFIP_OPENCLASH_EXPECTED_ENABLED=1; CFIP_OPENCLASH_INITIAL_RUNNING=true; CFIP_OPENCLASH_INITIAL_HEALTHY=true; }
cfip_openclash_capture_runtime(){ CFIP_OPENCLASH_RUNTIME_CONFIG="$TMP/main-dir/clash.yaml"; CFIP_OPENCLASH_RUNTIME_ID='111:100:/usr/bin/mihomo:/fixture/clash.yaml'; }
cfip_openclash_runtime_unchanged(){ [[ "$CFIP_OPENCLASH_RUNTIME_ID" == '111:100:/usr/bin/mihomo:/fixture/clash.yaml' ]]; }
cfip_managed_openclash_config_safe(){ [[ -f "$1" ]]; }
cfip_openclash_check_before_write(){ return 0; }
cfip_openclash_readback_selected(){ return 0; }
refresh_calls=0
cfip_openclash_provider_refresh(){ refresh_calls=$((refresh_calls+1)); [[ -s "$CFIP_OPENCLASH_TARGET_CONFIG" ]]; }
cfip_openclash_provider_inspect_runtime(){ CFIP_OPENCLASH_PROVIDER_RUNTIME_VERIFIED=true; CFIP_OPENCLASH_PROVIDER_RUNTIME_NAMES='["edge [CF-1]"]'; }
cfip_openclash_apply_selected(){
  cat >"$CFIP_OPENCLASH_TARGET_CONFIG" <<'YAML'
proxies:
  - name: edge [CF-1]
    type: vless
    server: 104.16.132.229
    port: 443
YAML
}
cfip_openclash_resolve_provider_target
[[ "$CFIP_OPENCLASH_TARGET_CONFIG" == "$TMP/main-dir/proxy_provider/nodes.yaml" ]]
[[ "$CFIP_OPENCLASH_PROVIDER_NAME" == local ]]
# A second referenced provider that also matches must fail closed.
cp "$TMP/main-dir/proxy_provider/nodes.yaml" "$TMP/main-dir/proxy_provider/other.yaml"
cat >"$TMP/main-dir/clash.yaml" <<'YAML'
external-controller: 127.0.0.1:9090
proxy-providers:
  local:
    type: file
    path: ./proxy_provider/nodes.yaml
  other:
    type: file
    path: ./proxy_provider/other.yaml
proxy-groups:
  - name: proxy
    type: select
    use: [local, other]
YAML
if cfip_openclash_resolve_provider_target; then echo 'ambiguous file providers were accepted' >&2; exit 1; fi
cp "$TMP/main-copy.yaml" "$TMP/main-dir/clash.yaml"
cfip_openclash_provider_document_valid "$TMP/main-dir/proxy_provider/nodes.yaml"
if cfip_openclash_provider_document_valid "$TMP/main-dir/clash.yaml"; then echo 'whole config accepted as provider backup' >&2; exit 1; fi

cfip_txn_prepare openclash
cfip_txn_apply openclash "$TMP/selected.json"
[[ "$refresh_calls" == 1 ]]
[[ "$CFIP_OPENCLASH_SERVICE_APPLIED" == true ]]
[[ "$CFIP_OPENCLASH_HOT_APPLIED" == true && "$CFIP_OPENCLASH_MAINTENANCE_RESTARTED" == false ]]
[[ "$CFIP_OPENCLASH_RESTART_ATTEMPTS" == 0 ]]
cfip_txn_rollback openclash
[[ "$refresh_calls" == 2 ]]
cmp -s "$TMP/main-dir/proxy_provider/nodes.yaml" "$TMP/provider-original.yaml"
[[ "$CFIP_TXN_ROLLED_BACK" == true ]]

# The only restart in the v2 runtime path is explicit maintenance restoration
# after a configured measurement stop. Ownership stays held until identity is
# re-captured and the same -f/provider pair is verified.
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
cfip_begin_recovery(){ :; }
cfip_restart_service(){ [[ "${MAINTENANCE_RESTART_FAIL:-false}" != true ]]; }
cfip_openclash_capture_runtime(){ CFIP_OPENCLASH_RUNTIME_CONFIG="$TMP/main-dir/clash.yaml"; CFIP_OPENCLASH_RUNTIME_ID='222:200:/usr/bin/mihomo:/fixture/clash.yaml'; }
cfip_openclash_resolve_provider_target(){ CFIP_OPENCLASH_TARGET_CONFIG="$TMP/main-dir/proxy_provider/nodes.yaml"; CFIP_OPENCLASH_PROVIDER_NAME=local; }
CFIP_STOPPED_MODE=openclash; CFIP_OPENCLASH_CF_STOPPED=true; CFIP_OPENCLASH_RUNTIME_CONFIG="$TMP/main-dir/clash.yaml"; CFIP_OPENCLASH_TARGET_CONFIG="$TMP/main-dir/proxy_provider/nodes.yaml"; CFIP_OPENCLASH_PROVIDER_NAME=local
restore_stopped_service_if_needed
[[ -z "$CFIP_STOPPED_MODE" && "$CFIP_OPENCLASH_CF_STOPPED" == false && "$CFIP_OPENCLASH_RUNTIME_ID" == '222:200:/usr/bin/mihomo:/fixture/clash.yaml' ]]
CFIP_STOPPED_MODE=openclash; CFIP_OPENCLASH_CF_STOPPED=true; MAINTENANCE_RESTART_FAIL=true
if restore_stopped_service_if_needed; then echo 'failed maintenance restore released ownership' >&2; exit 1; fi
[[ "$CFIP_STOPPED_MODE" == openclash && "$CFIP_OPENCLASH_CF_STOPPED" == true ]]
echo 'PASS provider target resolution, ambiguity rejection, hot publish, and owned hot rollback without restart'
