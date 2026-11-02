#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_PUBLISH_STATUS_FILE="$TMP/status.json" CFIP_PUBLISH_DIR="$TMP/publish"
mkdir -p "$CFIP_RUNTIME_DIR" "$CFIP_PUBLISH_DIR"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "${CFIP_TEST_PUBLISHER:-$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/publisher.sh}"
printf '{"success":true,"bind":"127.0.0.1","port":34567,"count":1,"paths":["/result.json"]}' >"$CFIP_PUBLISH_STATUS_FILE"
printf '{"schemaVersion":1,"runId":"test","ips":["104.18.1.1"],"selected":[{"ip":"104.18.1.1","family":"ipv4"}]}' >"$CFIP_PUBLISH_DIR/result.json"
CFIP_PUBLISH_ENABLED=true
curl(){ return 7; }
cfip_publisher_status_json >"$TMP/observed"
jq -e '.success==false' "$TMP/observed" >/dev/null || { echo 'FAIL missing listener returned cached success'; exit 1; }
# Read-only status must not rewrite the stored last-publish observation.
jq -e '.success==true' "$CFIP_PUBLISH_STATUS_FILE" >/dev/null
cat >"$TMP/init" <<'INIT'
#!/bin/sh
exit 0
INIT
chmod +x "$TMP/init"; CFIP_PUBLISH_INIT="$TMP/init"; CFIP_PUBLISH_ENABLED=false
cfip_publish_result "$TMP/unused"
jq -e '.success==false and .state=="disabled"' "$CFIP_PUBLISH_STATUS_FILE" >/dev/null || { echo 'FAIL disabling retained old ready status'; exit 1; }
echo 'PASS publisher missing-listener status and disabled state are honest'

# A stop failure must stay visible and must not claim disabled success.
printf '#!/bin/sh\nexit 1\n' >"$CFIP_PUBLISH_INIT"
rc=0; cfip_publish_result "$TMP/unused" || rc=$?
test "$rc" != 0
jq -e '.success==false and .error=="publisher_stop_failed"' "$CFIP_PUBLISH_STATUS_FILE" >/dev/null
cfip_publisher_status_json >"$TMP/observed"
jq -e '.error=="publisher_stop_failed"' "$TMP/observed" >/dev/null
echo 'PASS publisher stop failure stays visible'
# Reject malformed and oversized persisted observations without unbounded reads.
for malformed in broken oversized; do
 if [[ "$malformed" == broken ]]; then printf 'broken' >"$CFIP_PUBLISH_STATUS_FILE"
 else { printf '{"success":true}'; head -c 17000 /dev/zero | tr '\000' ' '; } >"$CFIP_PUBLISH_STATUS_FILE"; fi
 cfip_publisher_status_json >"$TMP/observed"
 jq -e '.success==false and .error=="publisher_status_invalid"' "$TMP/observed" >/dev/null
done
echo 'PASS malformed/oversized publisher status is rejected'
ubus(){ printf '{"up":true,"ipv4-address":[{"address":"8.8.8.8"},{"address":"192.168.01.1"},{"address":"192.168.5.1"}]}'; }
test "$(cfip_publisher_resolve_bind '')" = 192.168.5.1
ubus(){ printf '{"up":false,"ipv4-address":[{"address":"192.168.5.1"}]}'; }
if cfip_publisher_resolve_bind ''; then echo 'FAIL resolved unavailable LAN'; exit 1; fi
unset -f ubus
echo 'PASS automatic readback uses first qualified current LAN address'
if cfip_publisher_resolve_bind 127.000.0.1; then echo 'FAIL ambiguous leading-zero address'; exit 1; fi
# A configuration change must not hide a responding new endpoint behind old metadata.
printf '#!/bin/sh\nexit 0\n' >"$CFIP_PUBLISH_INIT"
printf '{"success":true,"bind":"127.0.0.1","port":34567}' >"$CFIP_PUBLISH_STATUS_FILE"
CFIP_PUBLISH_BIND=127.0.0.1; CFIP_PUBLISH_PORT=45678
cfip_publisher_endpoint_open(){ [[ "$2" == 45678 ]]; }
rc=0; cfip_publish_result "$TMP/unused" || rc=$?
test "$rc" != 0
jq -e '.error=="publisher_still_responding"' "$CFIP_PUBLISH_STATUS_FILE" >/dev/null
echo 'PASS disable checks current and previously published endpoints'
# Independent publisher-status command loads the committed configuration.
bash -c '
 ROOT="$1"; TMP="$2"; CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
 source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
 loaded=0
 load_config(){ loaded=$((loaded+1)); }
 cfip_publisher_status_json(){ printf "{\"success\":false}"; }
 cmd_publisher_status >"$TMP/command"
 test "$loaded" = 1
' bash "$ROOT" "$TMP"
echo 'PASS publisher-status command loads committed configuration'
