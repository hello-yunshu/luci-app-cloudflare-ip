#!/usr/bin/env bash
# A quarantine must never overwrite another quarantine.
#
# File names carry a second-resolution stamp, and the old `.$$` fallback reused
# a path whenever a stamp repeated inside the same second — which happens on
# every upgrade that rotates twice quickly. `mv` then replaced the older file,
# so the evidence the quarantine exists to preserve was the thing that got
# destroyed. Two rotations in one second now produce two distinct files.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_STATE="$TMP/state.json" \
	CFIP_RILL_QUALIFICATION_FILE="$TMP/qualification.json" CFIP_RILL_HISTORY_FILE="$TMP/history.json" \
	CFIP_RILL_PREFIX_HISTORY_FILE="$TMP/prefix.json" CFIP_RILL_COLO_HISTORY_FILE="$TMP/colo.json" \
	CFIP_RILL_EVIDENCE_FILE="$TMP/evidence.json" CFIP_TARGET_DOMAINS=one.example \
	CFIP_SPEEDTEST_PROTOCOL=tcp CFIP_IP_TYPE=ipv4 CFIP_SPEEDTEST_CFCOLO=''
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/candidate-rill.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

# 1. The helper itself never hands out a name that is already taken.
target="$TMP/probe.json"
first="$(cfip_unique_path "$target")"
[ "$first" = "$target" ] || fail "free path was renamed to $first"
printf 'a\n' >"$first"
second="$(cfip_unique_path "$target")"
[ "$second" != "$first" ] || fail "helper returned an occupied path"
printf 'b\n' >"$second"
[ "$(cat "$first")" = a ] || fail "second allocation overwrote the first"
echo 'PASS cfip_unique_path never returns an occupied name'

# 2. Two context rotations inside one second must still produce six files.
#    Freeze the stamp so both rotations collide by construction.
date() { if [ "$1" = "+%Y%m%d%H%M%S" ]; then printf '20260101000000'; else command date "$@"; fi; }

seed() { for file in "$CFIP_RILL_STATE" "$CFIP_RILL_QUALIFICATION_FILE" "$CFIP_RILL_EVIDENCE_FILE"; do printf '%s\n' '{}' >"$file"; done; }

cfip_rill_context_guard
seed; CFIP_TARGET_DOMAINS=two.example; cfip_rill_context_guard
seed; CFIP_TARGET_DOMAINS=three.example; cfip_rill_context_guard

count="$(find "$TMP" -maxdepth 1 -name '*.quarantine.context.*' -type f | wc -l | tr -d ' ')"
[ "$count" = 6 ] || fail "same-second rotations produced $count quarantine files, expected 6"
for file in "$TMP"/*.quarantine.context.*; do
	[ -s "$file" ] || fail "quarantine file is empty: $file"
done
echo 'PASS two rotations in the same second preserve all six quarantined files'

echo 'Rill quarantine uniqueness contract passed'
