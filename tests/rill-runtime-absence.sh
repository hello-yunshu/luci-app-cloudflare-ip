#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB_DIR="${CFIP_TEST_LIB_DIR:-$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip}"
SCHEMA_FILE="${CFIP_TEST_SCHEMA_FILE:-$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/candidate-rill-feature-schema-v2.json}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_ENABLED=true CFIP_RILL_MODE=shadow CFIP_RILL_RUNTIME="$TMP/missing-runtime" CFIP_RILL_SCHEMA_FILE="$SCHEMA_FILE"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/rill-disabled.sh"
source "$LIB_DIR/candidate-rill.sh"
status="$(cfip_rill_status_json)"
jq -e '.available==false and .state=="not-installed" and .runtimePath=="/usr/bin/rill-runtime" and (.runtimeInstallHint|type)=="string"' <<<"$status" >/dev/null

echo 'Missing Runtime is explicit and preserves Native fallback'
