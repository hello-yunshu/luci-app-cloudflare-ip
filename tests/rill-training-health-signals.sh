#!/usr/bin/env bash
# Training health has to be able to say no.
#
# The three original conditions (attributed == 100%, delayed >= 80%, errors
# <= 5%) cannot fail for entries written by the current pipeline: only accepted
# feedback is appended to the window, and it is always attributed, delayed and
# error-free. trainingHealth was therefore always "healthy" once the sample
# count was reached. Add signals that can actually be wrong: a candidate whose
# recent rewards went negative is not learning, and a window that stopped
# receiving samples says nothing about today.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_QUALIFICATION_FILE="$TMP/qualification.json" \
	CFIP_RILL_MIN_FEEDBACK_SAMPLES=30 CFIP_RILL_FAKE_NOW=2000000 CFIP_RILL_TRAINING_MAX_AGE_SECONDS=604800
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/candidate-rill.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

# $1 newest sample timestamp, $2 reward for each recent sample
seed() {
	jq -cn --argjson at "$1" --argjson reward "$2" '
		{state:"learning",validFeedback:30,attributedFeedback:30,delayedCompleted:30,errors:0,candidateFailures:0,
		 recentRewards:[range(0;10)|$reward],
		 trainingWindow:[range(0;30)|{evidenceType:"training",candidateOutcome:"success",attributed:true,delayed:true,error:false,reward:$reward,at:$at}],
		 evaluationWindow:[]}' >"$CFIP_RILL_QUALIFICATION_FILE"
}
health() { jq -r '.trainingHealth' "$CFIP_RILL_QUALIFICATION_FILE"; }

# 1. Fresh, non-negative feedback reaches the gate.
seed 2000000 0.8
cfip_rill_record_qualification "" false false false
[ "$(health)" = healthy ] || fail "fresh positive feedback reported $(health)"

# 2. Rewards that went negative mean the model is not learning anything good.
seed 2000000 -0.9
cfip_rill_record_qualification "" false false false
[ "$(health)" = insufficient ] || fail "negative recent rewards reported $(health)"
[ "$(jq -r '.recentRewardMedian' "$CFIP_RILL_QUALIFICATION_FILE")" = -0.9 ] || fail "recent median not reported"

# 3. A window that stopped receiving samples is not evidence about today.
seed 1000000 0.8
cfip_rill_record_qualification "" false false false
[ "$(health)" = insufficient ] || fail "week-old training window reported $(health)"
[ "$(jq -r '.trainingMaxAgeSeconds' "$CFIP_RILL_QUALIFICATION_FILE")" = 604800 ] || fail "training age budget not reported"

# 4. Below the sample gate nothing changes: still insufficient.
seed 2000000 0.8
jq '.validFeedback=5' "$CFIP_RILL_QUALIFICATION_FILE" >"$TMP/q" && mv "$TMP/q" "$CFIP_RILL_QUALIFICATION_FILE"
cfip_rill_record_qualification "" false false false
[ "$(health)" = insufficient ] || fail "sub-threshold window reported $(health)"

echo 'Rill training health signals contract passed'
