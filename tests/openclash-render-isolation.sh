#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/init" "$TMP/work" "$TMP/private"
export RENDER_REAL_JQ="$(command -v jq)"
export RENDER_FIXTURE="$TMP" PATH="$TMP/bin:$PATH" INIT_DIR="$TMP/init"
cat >"$TMP/bin/jq" <<'JQ'
#!/usr/bin/env bash
# Model the native OpenWrt jq build, which has no ONIGURUMA support.
for arg in "$@"; do
 if [[ "$arg" =~ (gsub|sub|match|test)[[:space:]]*\( ]]; then
  echo 'fixture jq has no regex support' >&2; exit 99
 fi
done
exec "$RENDER_REAL_JQ" "$@"
JQ
chmod +x "$TMP/bin/jq"
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
    uuid: isolated-auth-token
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

# Re-enter from already generated variants, as a real scheduled run does.
# Grow a one-variant file to two, then change both IPs repeatedly. Expected
# mappings must represent existing slots once, not expand each slot again.
for cycle in 2 3 4 5; do
    # Real scheduled CLI invocations start with fresh lifecycle flags.
    CFIP_OPENCLASH_FILE_WRITTEN=false; CFIP_OPENCLASH_SERVICE_APPLIED=false
    ip_round="$cycle"; if [[ "$cycle" == 5 ]]; then ip_round=4; fi
    printf '[{"ip":"104.16.%s.1","family":"ipv4"},{"ip":"104.16.%s.2","family":"ipv4"}]\n' "$ip_round" "$ip_round" >"$TMP/selected.json"
    CFIP_RUN_ID="real-staged-repeat-$cycle"
    CFIP_MEASUREMENT_DEADLINE=$(( $(cfip_monotonic_seconds) + 30 ))
    cfip_txn_prepare openclash
    cfip_txn_apply openclash "$TMP/selected.json"
    cfip_txn_commit
    cfip_openclash_actual_mapping "$TMP/live.yaml" "$TMP/repeated-actual.json"
    jq -e --arg a "104.16.$ip_round.1" --arg b "104.16.$ip_round.2" 'length==2 and ([.[].server]|sort)==([$a,$b]|sort)' "$TMP/repeated-actual.json" >/dev/null
    test "$CFIP_TXN_STATE" = COMMITTED
    test ! -s "$TMP/side-effects"
    if [[ "$cycle" == 2 ]]; then
        # Existing slots may legitimately carry different authentication data;
        # expectation normalization must not collapse or overwrite either one.
        awk '/uuid: isolated-auth-token/ { n++; if(n==2) sub(/isolated-auth-token/,"second-slot-auth") } {print}' "$TMP/live.yaml" >"$TMP/with-auth.yaml"
        mv "$TMP/with-auth.yaml" "$TMP/live.yaml"
    else
        ruby -rpsych -e 'raise "slot authentication changed" unless Psych.safe_load_file(ARGV[0])["proxies"].map { |x| x["uuid"] } == ["isolated-auth-token","second-slot-auth"]' "$TMP/live.yaml"
    fi
done
echo 'repeated real transactions grow and update existing CF variants without duplicate expectations or external side effects'

# A partial generated file can contain slot2 before slot1; fill only the
# missing slot and keep the existing slot's profile and selected-IP index.
awk 'NR==1 {print} /^  - name:/ {n++} n==2 {print}' "$TMP/live.yaml" >"$TMP/partial.yaml"
mv "$TMP/partial.yaml" "$TMP/live.yaml"
CFIP_RUN_ID=real-staged-missing-first-slot
CFIP_OPENCLASH_FILE_WRITTEN=false; CFIP_OPENCLASH_SERVICE_APPLIED=false
CFIP_MEASUREMENT_DEADLINE=$(( $(cfip_monotonic_seconds) + 30 ))
cfip_txn_prepare openclash
cfip_txn_apply openclash "$TMP/selected.json"
cfip_txn_commit
cfip_openclash_actual_mapping "$TMP/live.yaml" "$TMP/partial-actual.json"
jq -e 'length==2 and any(.[]; .name=="Sample [CF-1]" and .server=="104.16.4.1") and any(.[]; .name=="Sample [CF-2]" and .server=="104.16.4.2")' "$TMP/partial-actual.json" >/dev/null
echo 'partial generated configuration fills the missing first slot without expanding the existing second slot twice'

awk '/^  - name:/ {n++} n==1 {print}' "$TMP/live.yaml" >"$TMP/duplicate-block.yaml"
cat "$TMP/duplicate-block.yaml" >>"$TMP/live.yaml"
cp "$TMP/live.yaml" "$TMP/duplicate-preimage.yaml"
CFIP_RUN_ID=real-staged-duplicate-conflict
CFIP_OPENCLASH_FILE_WRITTEN=false; CFIP_OPENCLASH_SERVICE_APPLIED=false
CFIP_MEASUREMENT_DEADLINE=$(( $(cfip_monotonic_seconds) + 30 ))
cfip_txn_prepare openclash
if cfip_txn_apply openclash "$TMP/selected.json"; then echo 'actual duplicate nodes were silently collapsed' >&2; exit 1; else duplicate_rc=$?; fi
test "$duplicate_rc" -eq 15
cmp "$TMP/live.yaml" "$TMP/duplicate-preimage.yaml"
test "$CFIP_OPENCLASH_FILE_WRITTEN" = false
test ! -s "$TMP/side-effects"
echo 'real duplicate-node conflict rejects before publication and preserves the exact preimage'
