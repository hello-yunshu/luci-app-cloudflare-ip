#!/usr/bin/env bash
# Evaluation health must describe the typical comparison, not the worst one.
#
# Health used to gate on the *mean* reward delta while a dead-probe sample is
# scored -1 and a normal sample ~+0.6, so the delta of one such sample is about
# -1.66. Nine ties plus that one sample averaged -0.18 and revoked a
# qualification built over ten days. The median describes the same window as
# "-0.02, i.e. indistinguishable from Native" and keeps it; genuinely worse
# candidates still lose on the median, the severe counter and the win rate.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CFIP_STATUS_DIR="$TMP" CFIP_RILL_BASE_DIR="$TMP" CFIP_RILL_QUALIFICATION_FILE="$TMP/qualification.json" \
	CFIP_RILL_MIN_FEEDBACK_SAMPLES=30 CFIP_RILL_FAKE_NOW=1000000 CFIP_RILL_EVALUATION_MAX_AGE_SECONDS=86400
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/candidate-rill.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

# $1 = jq expression producing the evaluation delta array
seed_window() {
	local deltas="$1"
	jq -cn --argjson at 1000000 --argjson deltas "$deltas" '
		{state:"shadow-qualified",validFeedback:30,attributedFeedback:30,delayedCompleted:30,
		 trainingWindow:[range(0;30)|{evidenceType:"training",attributed:true,delayed:true,error:false,reward:0.8,at:$at}],
		 evaluationWindow:[ $deltas[] | {evaluationSource:"shadow",comparisonResult:(if .>0.02 then "win" elif .< -0.02 then "loss" else "tie" end),rewardDelta:.,at:$at} ],
		 evaluationHealth:"healthy",evaluationFreshAt:$at}' >"$CFIP_RILL_QUALIFICATION_FILE"
}
health() { jq -r '.evaluationHealth' "$CFIP_RILL_QUALIFICATION_FILE"; }
state() { jq -r '.state' "$CFIP_RILL_QUALIFICATION_FILE"; }

# 1. Nine ties plus one dead-probe sample: mean is alarming, median is not.
seed_window '[ -0.02,-0.02,-0.02,-0.02,-0.02,-0.02,-0.02,-0.02,-0.02,-1.66 ]'
cfip_rill_record_qualification "" false false false
mean="$(jq -r '.rewardDelta' "$CFIP_RILL_QUALIFICATION_FILE")"
median="$(jq -r '.medianRewardDelta' "$CFIP_RILL_QUALIFICATION_FILE")"
awk -v x="$mean" 'BEGIN { exit !(x < -0.05) }' || fail "fixture mean unexpectedly benign: $mean"
awk -v x="$median" 'BEGIN { exit !(x > -0.05) }' || fail "median not robust: $median"
[ "$(health)" = healthy ] || fail "one dead-probe sample still revoked health (health=$(health))"
[ "$(state)" = shadow-qualified ] || fail "one dead-probe sample still demoted the state (state=$(state))"
cfip_rill_qualified || fail "robust health did not qualify the candidate"
echo "PASS one -1 outlier with 9 ties keeps health (mean $mean, median $median)"

# 2. A candidate that is typically worse must still fail: 6 of 10 clearly behind.
seed_window '[ -0.30,-0.30,-0.30,-0.30,-0.30,-0.30,-0.02,-0.02,-0.02,-0.02 ]'
cfip_rill_record_qualification "" false false false
[ "$(health)" = negative ] || fail "consistently worse candidate reported health=$(health)"
[ "$(state)" = shadow ] || fail "consistently worse candidate kept state=$(state)"
cfip_rill_qualified && fail "consistently worse candidate still qualified"
echo 'PASS a consistently worse candidate is still rejected'

# 3. A tie-dominated window must not be rejected for having no wins.
seed_window '[ -0.02,-0.02,-0.02,-0.02,-0.02,-0.02,-0.02,-0.02,0.03,0.03 ]'
cfip_rill_record_qualification "" false false false
[ "$(health)" = healthy ] || fail "tie-dominated window reported health=$(health)"
echo 'PASS tie-dominated window stays healthy'

# 4. Repeated severe regressions alone are enough to reject, even with a benign median.
seed_window '[ -0.30,-0.30,-0.05,-0.05,-0.05,-0.05,-0.05,-0.05,-0.05,-0.05 ]'
cfip_rill_record_qualification "" false false false
[ "$(health)" = negative ] || fail "severe regressions no longer reject (health=$(health))"
echo 'PASS severe-regression count still rejects on its own'

echo 'Rill robust evaluation health contract passed'
