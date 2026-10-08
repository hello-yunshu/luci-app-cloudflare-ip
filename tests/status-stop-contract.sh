#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
run_stop() { CFIP_STATUS_DIR="$TMP/status" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip" bash "$SCRIPT" --mark-stopped; }
mkdir -p "$TMP/status" "$TMP/runtime"
printf '%s\n' '{"extra":{"keep":true},"active_run":true,"running":true,"enabled":true,"best_ips":["1.1.1.1"]}' >"$TMP/status/status.json"
run_stop | jq -e '.success==true and .running==false and .scheduled==false and .jobRunning==true' >/dev/null
jq -e '.running==false and .enabled==false and .scheduled==false and .disabled==true and .active_run==true and .jobRunning==true and .extra.keep==true and .best_ips==["1.1.1.1"]' "$TMP/status/status.json" >/dev/null
jq '.' "$TMP/status/status.json" >"$TMP/pretty.json"; mv "$TMP/pretty.json" "$TMP/status/status.json"
run_stop | jq -e '.success==true and .jobRunning==true' >/dev/null
jq -e '.running==false and .extra.keep==true' "$TMP/status/status.json" >/dev/null
rm "$TMP/status/status.json"
run_stop | jq -e '.success==true and .running==false and .scheduled==false and .jobRunning==false' >/dev/null
jq -e '.enabled==false and .running==false and .last_result=="unknown"' "$TMP/status/status.json" >/dev/null
printf '%s\n' '{bad json' >"$TMP/status/status.json"
if run_stop >/dev/null 2>&1; then echo 'corrupt status was reported as stopped' >&2; exit 1; fi
[[ "$(cat "$TMP/status/status.json")" == '{bad json' ]]
printf '%s\n' '{"running":true,"active_run":false}' >"$TMP/status/status.json"
mkdir -p "$TMP/bin"
printf '%s\n' '#!/bin/sh' 'exit 1' >"$TMP/bin/mv"; chmod +x "$TMP/bin/mv"
if PATH="$TMP/bin:$PATH" CFIP_STATUS_DIR="$TMP/status" CFIP_RUNTIME_DIR="$TMP/runtime" CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip" bash "$SCRIPT" --mark-stopped >/dev/null 2>&1; then echo 'failed status rename reported success' >&2; exit 1; fi
jq -e '.running==true and .active_run==false' "$TMP/status/status.json" >/dev/null
echo 'Stopped service status uses atomic structured JSON and preserves job state'