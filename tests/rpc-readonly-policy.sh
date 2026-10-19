#!/usr/bin/env bash
# Source ACL policy + actual refresh cache write; not a native rpcd session test.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-legacy"
STATUS_DIR="$TMP/status"; ENV_CACHE_FILE="$STATUS_DIR/env_cache.json"; WORK_DIR="$TMP/bin"
load_uci_config_if_available(){ :; }
cmd_refresh_env >"$TMP/response"
test -s "$ENV_CACHE_FILE"
cmp "$ENV_CACHE_FILE" "$TMP/response"
jq -e '.success==true' "$ENV_CACHE_FILE" >/dev/null
ACL="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/rpcd/acl.d/luci-app-cloudflare-ip.json"
jq -e '.["luci-app-cloudflare-ip"] | (.read.ubus.cf_ip | index("refresh-env"))==null and (.write.ubus.cf_ip | index("refresh-env"))!=null' "$ACL" >/dev/null || { echo 'FAIL cache-mutating refresh-env granted to read-only session policy'; exit 1; }
python3 - "$ACL" "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/rpcd/cf_ip" <<'PY'
import json,subprocess,sys
acl=json.load(open(sys.argv[1]))['luci-app-cloudflare-ip']
read=set(acl['read']['ubus']['cf_ip']);write=set(acl['write']['ubus']['cf_ip'])
methods=set(json.loads(subprocess.check_output(['sh',sys.argv[2],'list'])))
mutations={'run','clear-log','refresh-env','self-update','download-cfst','source-refresh','start','stop','restart','sync','oc-restore-backup','oc-delete-backup','rill-reset'}
assert mutations <= write and not mutations & read,(read,write)
assert read | write == methods and not read & write,(methods,read,write)
PY
echo 'PASS actual environment refresh writes cache; mutating methods require write ACL and all RPC methods have one policy class'
