#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/openclash-readback.sh"
printf '[{"name":"Node [CF-1]","server":"104.16.1.1","servername":"cdn.example.com","network":"ws","host":"cdn.example.com"}]\n' >"$TMP/intended.json"
cp "$TMP/intended.json" "$TMP/actual.json"
cfip_openclash_validate_mapping "$TMP/intended.json" "$TMP/actual.json" </dev/null
jq '.[0].network="grpc"' "$TMP/intended.json" >"$TMP/wrong-network.json"
if cfip_openclash_validate_mapping "$TMP/intended.json" "$TMP/wrong-network.json" </dev/null; then echo 'wrong network passed' >&2; exit 1; fi
jq '. + .' "$TMP/intended.json" >"$TMP/duplicate.json"
if cfip_openclash_validate_mapping "$TMP/intended.json" "$TMP/duplicate.json" </dev/null; then echo 'duplicate mapping passed' >&2; exit 1; fi
jq '. + [.[0] + {server:"104.16.1.2"}]' "$TMP/intended.json" >"$TMP/name-collision.json"
if cfip_openclash_validate_mapping "$TMP/name-collision.json" "$TMP/name-collision.json" </dev/null; then echo 'conflicting duplicate node name passed' >&2; exit 1; fi
jq '.[0].server="104.16.1.2"' "$TMP/intended.json" >"$TMP/wrong-ip.json"
if cfip_openclash_validate_mapping "$TMP/intended.json" "$TMP/wrong-ip.json" </dev/null; then echo 'wrong selected IP passed' >&2; exit 1; fi
printf '[]\n' >"$TMP/missing.json"
if cfip_openclash_validate_mapping "$TMP/intended.json" "$TMP/missing.json" </dev/null; then echo 'missing node passed' >&2; exit 1; fi
echo 'exact IntendedMapping accepts empty stdin; wrong network and duplicate mappings reject'
