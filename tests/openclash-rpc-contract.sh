#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/backend" <<'EOF_BACKEND'
#!/usr/bin/env bash
case "$1" in
  --status)
    printf '%s\n' '{"running":true,"active_run":false,"jobRunning":false,"last_result":"warning","best_ips":["104.16.1.1"],"service":{"target":"openclash","expectedEnabled":0,"nodeFileWritten":true,"serviceApplied":false,"deferredUntilServiceStart":true}}'
    ;;
  --oc-restore-backup)
    printf '%s\n' '{"success":true,"nodeFileWritten":true,"serviceApplied":false}'
    exit 7
    ;;
  --sync)
    printf '%s\n' '{"success":false,"error":"OpenClash recovery failed","best_ips":["104.16.1.1"],"service":{"target":"openclash","nodeFileWritten":true,"serviceApplied":false,"error":"controller health timeout"}}'
    exit 1
    ;;
esac
EOF_BACKEND
cat >"$TMP/jsonfilter" <<'EOF_JSONFILTER'
#!/usr/bin/env bash
while (($#)); do
  if [[ "$1" == -s ]]; then
    input="$2"; shift 2
  else
    shift
  fi
done
printf '%s\n' "$input" | jq -r '.plugin // .id // empty'
EOF_JSONFILTER
chmod +x "$TMP/backend" "$TMP/jsonfilter"
export CF_IP_AUTO_BIN="$TMP/backend" PATH="$TMP:$PATH"
rpc() { sh "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/rpcd/cf_ip" call "$1"; }

rpc status >"$TMP/status.json"
cat "$TMP/status.json" | jq -e '.running == true and .active_run == false and .jobRunning == false and .last_result == "warning" and .service.deferredUntilServiceStart == true and .best_ips[0] == "104.16.1.1"' >/dev/null
printf '%s\n' '{"plugin":"openclash"}' | rpc sync | jq -e '.success == false and .error == "OpenClash recovery failed" and .service.error == "controller health timeout" and .best_ips[0] == "104.16.1.1" and .service.nodeFileWritten == true' >/dev/null
echo 'rpcd forwards disabled-pending status and preserves sync failures and write facts'
printf '%s\n' '{"id":"20261010120000"}' | rpc oc-restore-backup | jq -e '.success == false and .rc == 7 and .nodeFileWritten == true' >/dev/null
node "$ROOT/tests/openclash-rpc-render.cjs" "$TMP/status.json"
