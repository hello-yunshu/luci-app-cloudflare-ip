#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/openclash-readback.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/transaction.sh"

mkdir -p "$TMP/bin" "$TMP/txn"
cat >"$TMP/bin/uci" <<'UCI'
#!/bin/sh
case "$*" in
  *"get openclash.config.enable"*) echo 0 ;;
  *"changes openclash"*) exit 0 ;;
  *) exit 0 ;;
esac
UCI
chmod +x "$TMP/bin/uci"
PATH="$TMP/bin:$PATH"
export PATH

cat >"$TMP/config.yaml" <<'YAML'
proxies:
  - name: Original
    type: vless
    server: domain.example
YAML
cp "$TMP/config.yaml" "$TMP/txn/openclash.yaml"
cp "$TMP/config.yaml" "$TMP/original.yaml"
CFIP_TXN_DIR="$TMP/txn"
CFIP_OPENCLASH_CONFIG="$TMP/config.yaml"
CFIP_OPENCLASH_EXPECTED_ENABLED=0
CFIP_OPENCLASH_CF_STOPPED=false
CFIP_OPENCLASH_SERVICE_APPLIED=false
CFIP_OPENCLASH_RESTART_ATTEMPTS=1
CFIP_OPENCLASH_SERVICE_ERROR=fixture-start-failure
CFIP_TXN_STATE=MUTATED
CFIP_TXN_MODE=openclash

# An invalid backup/candidate must be rejected before publication.
printf 'not: a-proxies-document\n' >"$TMP/invalid.yaml"
set +e
cfip_txn_publish_openclash "$TMP/invalid.yaml" pre-restore >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]]
cmp -s "$TMP/config.yaml" "$TMP/original.yaml"
echo 'PASS invalid OpenClash backup rejected before publication'

# A failed startup must restore the transaction snapshot rather than retain
# the failed candidate.
cat >"$TMP/candidate.yaml" <<'YAML'
proxies:
  - name: Candidate
    type: vless
    server: 104.16.1.1
YAML
cp "$TMP/candidate.yaml" "$TMP/txn/openclash.written.yaml"
cp "$TMP/candidate.yaml" "$TMP/config.yaml"
CFIP_TXN_DIR="$TMP/txn"
CFIP_TXN_STATE=MUTATED
CFIP_TXN_ROLLED_BACK=false
CFIP_OPENCLASH_RESTART_ATTEMPTS=1
CFIP_OPENCLASH_SERVICE_APPLIED=false
CFIP_OPENCLASH_CF_STOPPED=false
set +e
cfip_txn_rollback openclash >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]]
cmp -s "$TMP/config.yaml" "$TMP/original.yaml"
echo 'PASS failed startup rollback restores the original OpenClash snapshot'
