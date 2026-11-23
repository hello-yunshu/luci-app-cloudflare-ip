#!/usr/bin/env bash
# A learning-context change must invalidate only what it actually invalidates.
#
# Before this contract the guard quarantined state, qualification, evidence AND
# the per-IP / prefix / colo histories on any change, so adding one target
# domain threw away weeks of "is this IP actually fast" evidence that has
# nothing to do with the domain. Now the scope decides:
#   domains  -> model + evidence only, endpoint priors survive
#   protocol -> additionally the per-IP latency priors (tcp vs http totals)
#   ip_type  -> everything (the other family's samples are incomparable)
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
qcount() { find "$TMP" -name '*.quarantine.context.*' -type f | wc -l | tr -d ' '; }
seed() { for file in "$@"; do printf '%s\n' '{"keep":true}' >"$file"; done; }
scope_of() { jq -r '.contextChangeScope // "none"' "$CFIP_RILL_STATE_META_FILE"; }

cfip_rill_context_guard; old="$(cfip_rill_context_fingerprint)"

# 1. domains: model and evidence are workload specific, endpoint priors are not.
seed "$CFIP_RILL_STATE" "$CFIP_RILL_QUALIFICATION_FILE" "$CFIP_RILL_EVIDENCE_FILE" \
	"$CFIP_RILL_HISTORY_FILE" "$CFIP_RILL_PREFIX_HISTORY_FILE" "$CFIP_RILL_COLO_HISTORY_FILE"
CFIP_TARGET_DOMAINS=two.example; cfip_rill_context_guard
[ "$(qcount)" = 3 ] || fail "domains change quarantined $(qcount) files, expected 3"
[ "$(scope_of)" = domains ] || fail "domains change reported scope '$(scope_of)'"
[ "$(jq -r '.contextChanged' "$CFIP_RILL_STATE_META_FILE")" = true ] || fail "contextChanged not recorded"
[ "$(jq -r '.previousContextFingerprint' "$CFIP_RILL_STATE_META_FILE")" = "$old" ] || fail "previous fingerprint lost"
for file in "$CFIP_RILL_HISTORY_FILE" "$CFIP_RILL_PREFIX_HISTORY_FILE" "$CFIP_RILL_COLO_HISTORY_FILE"; do
	[ -s "$file" ] || fail "domains change dropped endpoint prior $file"
done
echo 'PASS domains change keeps endpoint priors and resets only the model'

# 2. protocol: latency priors measure something else now, prefix/colo stay.
before="$(qcount)"
seed "$CFIP_RILL_STATE" "$CFIP_RILL_QUALIFICATION_FILE" "$CFIP_RILL_EVIDENCE_FILE" "$CFIP_RILL_HISTORY_FILE"
CFIP_SPEEDTEST_PROTOCOL=http; cfip_rill_context_guard
[ "$(scope_of)" = protocol ] || fail "protocol change reported scope '$(scope_of)'"
[ "$(( $(qcount) - before ))" = 4 ] || fail "protocol change quarantined $(( $(qcount) - before )) files, expected 4"
[ ! -e "$CFIP_RILL_HISTORY_FILE" ] || fail "protocol change kept incomparable latency priors"
for file in "$CFIP_RILL_PREFIX_HISTORY_FILE" "$CFIP_RILL_COLO_HISTORY_FILE"; do
	[ -s "$file" ] || fail "protocol change dropped $file"
done
echo 'PASS protocol change drops latency priors and keeps prefix/colo quality'

# 3. ip_type: nothing measured for the other family applies.
before="$(qcount)"
seed "$CFIP_RILL_STATE" "$CFIP_RILL_QUALIFICATION_FILE" "$CFIP_RILL_EVIDENCE_FILE" \
	"$CFIP_RILL_HISTORY_FILE" "$CFIP_RILL_PREFIX_HISTORY_FILE" "$CFIP_RILL_COLO_HISTORY_FILE"
CFIP_IP_TYPE=ipv6; cfip_rill_context_guard
[ "$(scope_of)" = ip_type ] || fail "ip_type change reported scope '$(scope_of)'"
[ "$(( $(qcount) - before ))" = 6 ] || fail "ip_type change quarantined $(( $(qcount) - before )) files, expected 6"
for file in "$CFIP_RILL_STATE" "$CFIP_RILL_QUALIFICATION_FILE" "$CFIP_RILL_HISTORY_FILE" \
	"$CFIP_RILL_PREFIX_HISTORY_FILE" "$CFIP_RILL_COLO_HISTORY_FILE" "$CFIP_RILL_EVIDENCE_FILE"; do
	[ ! -e "$file" ] || fail "ip_type change kept $file"
done
echo 'PASS ip_type change quarantines every candidate-dependent file'
