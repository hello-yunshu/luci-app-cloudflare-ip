#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/init" "$TMP/work" "$TMP/private"
export RENDER_FIXTURE="$TMP" PATH="$TMP/bin:$PATH" INIT_DIR="$TMP/init"
cat >"$TMP/bin/uci" <<'UCI'
#!/usr/bin/env bash
[[ "${1:-}" != -q ]] || shift
if [[ "${1:-}" != get || "${2:-}" != cf_ip.* ]]; then printf 'unexpected UCI: %s\n' "$*" >>"$RENDER_FIXTURE/side-effects"; exit 99; fi
case "$2" in
 cf_ip.main.work_dir) printf '%s\n' "$RENDER_FIXTURE/work" ;;
 cf_ip.openclash.config) printf '%s\n' "$RENDER_FIXTURE/live.yaml" ;;
 cf_ip.openclash.target_domain) printf 'cdn.example.com\n' ;;
 cf_ip.openclash.name_suffix) printf ' [CF-{n}]\n' ;;
 cf_ip.openclash.backup_count) printf '3\n' ;;
 *) exit 1 ;;
esac
UCI
for tool in curl pidof; do
 cat >"$TMP/bin/$tool" <<'SIDE_EFFECT'
#!/usr/bin/env bash
printf 'unexpected external command: %s\n' "$0 $*" >>"$RENDER_FIXTURE/side-effects"
exit 99
SIDE_EFFECT
 chmod +x "$TMP/bin/$tool"
done
cp "$TMP/bin/curl" "$TMP/init/openclash"
chmod +x "$TMP/bin/uci" "$TMP/init/openclash"
cat >"$TMP/live.yaml" <<'YAML'
proxies:
  - name: Sample
    type: vless
    server: cdn.example.com
    port: 443
    tls: true
    network: ws
    ws-opts:
      path: /ws
YAML
cp "$TMP/live.yaml" "$TMP/original.yaml"
cp "$TMP/live.yaml" "$TMP/private/candidate.yaml"
printf '[{"ip":"104.16.1.1","family":"ipv4"}]\n' >"$TMP/selected.json"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/openclash-transform.sh"
CFIP_LEGACY_BIN="$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-legacy"
CFIP_MEASUREMENT_DEADLINE=$(( $(cfip_monotonic_seconds) + 30 ))
if ! cfip_openclash_transform_selected "$TMP/selected.json" "$TMP/private/candidate.yaml"; then
 cat "$TMP/private/candidate.yaml.render.log" >&2 || :
 exit 1
fi
cmp -s "$TMP/original.yaml" "$TMP/live.yaml"
grep -q 'server: 104.16.1.1' "$TMP/private/candidate.yaml"
grep -q 'name: Sample \[CF-1\]' "$TMP/private/candidate.yaml"
test ! -s "$TMP/side-effects"
if compgen -G "$TMP/live.yaml.bak.*" >/dev/null; then echo 'renderer created a live backup' >&2; exit 1; fi
echo 'real bounded renderer changes only its private candidate without service, controller, UCI-write or live-backup side effects'

# Exercise the entire real v2 -> intended mapping -> renderer -> staged
# readback -> atomic publication -> commit path with a disabled service.
export CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip" CFIP_INIT_DIR="$TMP/init"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
uci() {
    local first="${1:-}" second="${2:-}" third="${3:-}"
    if [[ "$first" == -q && "$second" == get && "$third" == openclash.config.enable ]]; then printf '0\n'; else command uci "$@"; fi
}
pidof() { return 1; }
CFIP_OPENCLASH_CONFIG="$TMP/live.yaml"; CFIP_OPENCLASH_TARGET_DOMAIN=cdn.example.com
CFIP_TARGET_DOMAINS=cdn.example.com; CFIP_OPENCLASH_NAME_SUFFIX=' [CF-{n}]'
CFIP_OPENCLASH_TRANSPORT_FILTER=""; CFIP_OPENCLASH_BACKUP_COUNT=3
CFIP_LEGACY_BIN="$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-legacy"
CFIP_RUNTIME_DIR="$TMP/runtime"; mkdir -p "$CFIP_RUNTIME_DIR"; CFIP_RUN_ID=real-staged-render
CFIP_MEASUREMENT_DEADLINE=$(( $(cfip_monotonic_seconds) + 30 ))
for n in 1 2 3 4; do cp "$TMP/original.yaml" "$TMP/live.yaml.bak.20200101000000.$n"; done
cfip_txn_prepare openclash
cfip_txn_apply openclash "$TMP/selected.json"
cfip_txn_commit
grep -q 'server: 104.16.1.1' "$TMP/live.yaml"
test "$CFIP_OPENCLASH_FILE_WRITTEN" = true
test "$CFIP_OPENCLASH_SERVICE_APPLIED" = false
test "$CFIP_TXN_STATE" = COMMITTED
test ! -s "$TMP/side-effects"
shopt -s nullglob
backups=("$TMP/live.yaml.bak."*)
test "${#backups[@]}" -eq 3
cmp -s "$TMP/original.yaml" "$CFIP_TXN_BACKUP_FILE"
echo 'real disabled-service transaction publishes validated bytes, preserves its backup and enforces configured retention without restarting'
