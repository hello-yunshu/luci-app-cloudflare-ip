#!/usr/bin/env bash
# Evidence freshness is graded, not binary: fresh keeps full confidence, stale
# keeps the qualification but lowers confidence, expired falls back to Native.
# A 24h-only cutoff made assisted mode flap on sparse run schedules even though
# the safe envelope and runtime health are re-checked on every run anyway.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" \
	CFIP_RILL_EVALUATION_MAX_AGE_SECONDS=100 CFIP_RILL_EVALUATION_STALE_SECONDS=300 \
	CFIP_RILL_FAKE_NOW=1000
export CFIP_RILL_QUALIFICATION_FILE="$TMP/qualification.json" \
	CFIP_RILL_SCHEMA_FILE="$ROOT/package/luci-app-cloudflare-ip/root/usr/share/cf-ip/candidate-rill-feature-schema-v2.json"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/candidate-rill.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
seed() {
	jq -cn --argjson at "$1" '{state:"shadow-qualified",evaluationHealth:"healthy",evaluationFreshAt:$at,
		evaluationWindow:[{comparisonResult:"win",rewardDelta:0.1,at:$at}],trainingWindow:[],window:[]}' \
		>"$CFIP_RILL_QUALIFICATION_FILE"
}

seed 950
[ "$(cfip_rill_qualification_freshness)" = fresh ] || fail "age 50s not reported fresh"
cfip_rill_qualified || fail "fresh evidence was not qualified"

seed 800
[ "$(cfip_rill_qualification_freshness)" = stale ] || fail "age 200s not reported stale"
cfip_rill_qualified || fail "stale-but-not-expired evidence must stay qualified"

seed 600
[ "$(cfip_rill_qualification_freshness)" = expired ] || fail "age 400s not reported expired"
cfip_rill_qualified && fail "expired evidence kept the qualification"

# A negative evaluation still revokes regardless of freshness.
seed 950
jq '.evaluationHealth="negative"' "$CFIP_RILL_QUALIFICATION_FILE" >"$TMP/q" && mv "$TMP/q" "$CFIP_RILL_QUALIFICATION_FILE"
cfip_rill_qualified && fail "negative evaluation health kept the qualification"

# No comparable evidence at all can never qualify, however fresh the file looks.
jq -cn '{state:"shadow-qualified",evaluationHealth:"stale",evaluationFreshAt:null,evaluationWindow:[],trainingWindow:[],window:[]}' \
	>"$CFIP_RILL_QUALIFICATION_FILE"
[ "$(cfip_rill_qualification_freshness)" = none ] || fail "empty evaluation window not reported as none"
cfip_rill_qualified && fail "missing evidence qualified the candidate"

echo 'Evaluation freshness: fresh / stale / expired zones and revocation hierarchy hold'
