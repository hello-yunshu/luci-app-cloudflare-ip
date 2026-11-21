#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
load_config() { return 0; }
cfip_managed_openclash_config_safe() { [[ -f "$1" ]]; }
uci() {
    case "${*: -1}" in
        openclash.config.config_path) printf '%s\n' "$case_dir/main.yaml" ;;
        *) return 1 ;;
    esac
}
cfip_openclash_capture_backup_context() {
    CFIP_OPENCLASH_RUNTIME_CONFIG="$case_dir/main.yaml"
    CFIP_OPENCLASH_RUNTIME_ID=""
    CFIP_OPENCLASH_TARGET_CONFIG="$case_dir/proxy_provider/nodes.yaml"
    CFIP_OPENCLASH_PROVIDER_NAME=local
    CFIP_OPENCLASH_EXPECTED_ENABLED=0
    CFIP_OPENCLASH_INITIAL_HEALTHY=false
    CFIP_OPENCLASH_DEFERRED=true
}
cfip_openclash_resolve_provider_target() {
    CFIP_OPENCLASH_TARGET_CONFIG="$case_dir/proxy_provider/nodes.yaml"
    CFIP_OPENCLASH_PROVIDER_NAME=local
}
cfip_openclash_capture_state() { cfip_openclash_capture_backup_context; }
cfip_openclash_check_before_write() { return 0; }
cfip_begin_recovery() { return 0; }
cp() {
    if [[ "${!#}" == */openclash.written.yaml ]]; then
        [[ "$fault" != written-snapshot ]] || return 1
        if [[ "$fault" == external-edit ]]; then printf 'external user edit\n' >"$CFIP_OPENCLASH_TARGET_CONFIG"; fi
    fi
    command cp "$@"
}
mv() {
    if [[ "$fault" == publish-rename && "${!#}" == "$CFIP_OPENCLASH_TARGET_CONFIG" ]]; then return 1; fi
    command mv "$@"
}
failures=0
for fault in written-snapshot publish-rename external-edit success; do
 if (
    case_dir="$TMP/$fault"; mkdir -p "$case_dir/runtime"
    CFIP_RUNTIME_DIR="$case_dir/runtime"; CFIP_LOG_FILE="$case_dir/trace.log"
    mkdir -p "$case_dir/proxy_provider"
    CFIP_OPENCLASH_CONFIG="$case_dir/main.yaml"; CFIP_OPENCLASH_BACKUP_COUNT=3
    CFIP_OPENCLASH_TARGET_CONFIG="$case_dir/proxy_provider/nodes.yaml"
    CFIP_CLEANUP_DONE=false
    cat >"$case_dir/main.yaml" <<'YAML'
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
    cat >"$case_dir/proxy_provider/nodes.yaml" <<'YAML'
proxies:
  - name: Original
    type: vless
    server: original.example
    port: 443
YAML
    cat >"$case_dir/expected.yaml" <<'YAML'
proxies:
  - name: Restored One
    type: vless
    server: 104.16.1.1
    port: 443
YAML
    cp "$case_dir/expected.yaml" "$CFIP_OPENCLASH_TARGET_CONFIG.bak.20200101000000"
    if cmd_oc_restore_backup 20200101000000 >"$case_dir/result.json"; then rc=0; else rc=$?; fi
    printf '%s: rc=%s live=%s\n' "$fault" "$rc" "$(head -n 1 "$CFIP_OPENCLASH_TARGET_CONFIG")"
    case "$fault" in
      success) [[ "$rc" == 0 ]] && cmp -s "$CFIP_OPENCLASH_TARGET_CONFIG" "$case_dir/expected.yaml" ;;
      external-edit) [[ "$rc" != 0 && "$(cat "$CFIP_OPENCLASH_TARGET_CONFIG")" == 'external user edit' ]] ;;
      *) [[ "$rc" != 0 && "$(head -n 1 "$CFIP_OPENCLASH_TARGET_CONFIG")" == 'proxies:' ]] ;;
    esac
 ); then :; else failures=$((failures+1)); fi
done
test "$failures" -eq 0
