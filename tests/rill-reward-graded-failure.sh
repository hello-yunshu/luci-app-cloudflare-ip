#!/usr/bin/env bash
# A partially reachable candidate is not a dead one.
#
# `candidateOutcome=="failure"` used to collapse to a -1 reward whenever any
# single domain probe failed, which is indistinguishable from an unreachable IP
# and — because health used the mean — let one flaky domain dominate a whole
# evaluation window. Now only a candidate with no successful probe keeps -1.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/candidate-rill.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
probe() { # domain ok
	printf '{"domain":"%s","success":%s,"connectMs":20,"tlsMs":20,"ttfbMs":100,"totalMs":200,"lossRate":0,"downloadMBps":40}' "$1" "$2"
}
json() { printf '{"candidateOutcome":"%s","probes":[%s]}\n' "$1" "$2" >"$TMP/o.json"; cfip_rill_reward_json "$TMP/o.json"; }

# 1. Every probe failed: the hard floor stays.
all_fail="$(json failure "$(probe one.example false),$(probe two.example false)")"
[ "$(jq -r '.reward' <<<"$all_fail")" = -1 ] || fail "all-failed candidate did not floor at -1"
echo 'PASS fully unreachable candidate keeps the -1 floor'

# 2. Legacy shape: outcome says failure but carries no probes at all.
printf '{"candidateOutcome":"failure","probes":[]}\n' >"$TMP/o.json"
[ "$(cfip_rill_reward_from_outcome "$TMP/o.json")" = -1 ] || fail "probe-less failure lost the -1 floor"

# 3. Half the domains fail: graded, not floored.
partial="$(json failure "$(probe one.example true),$(probe two.example false)")"
partial_reward="$(jq -r '.reward' <<<"$partial")"
awk -v x="$partial_reward" 'BEGIN { exit !(x > -1 && x < 1) }' || fail "partial failure reward out of range: $partial_reward"
awk -v x="$partial_reward" 'BEGIN { exit !(x < 0) }' && fail "partial failure should still score below zero: $partial_reward"
[ "$(jq -r '.components.partialFailurePenalty' <<<"$partial")" != 0 ] || fail "partial failure penalty not reported"
echo "PASS partial failure is graded (reward $partial_reward) instead of floored"

# 4. Same endpoint measured clean must score strictly better than the half-broken run.
clean="$(json success "$(probe one.example true),$(probe two.example true)")"
clean_reward="$(jq -r '.reward' <<<"$clean")"
awk -v p="$partial_reward" -v c="$clean_reward" 'BEGIN { exit !(c > p) }' \
	|| fail "clean run ($clean_reward) did not beat partial failure ($partial_reward)"
echo "PASS clean run ($clean_reward) outscores the same endpoint's partial failure"

# 5. A partial failure stays a regression against a healthy native baseline, so
#    it is still visible to the severe-regression counter.
delta="$(jq -cn --argjson p "$partial_reward" '0.66 - $p | . * -1')"
awk -v d="$delta" 'BEGIN { exit !(d < -0.25) }' || fail "partial failure delta no longer counts as severe: $delta"
echo "PASS partial failure still registers as a severe regression (delta $delta)"

echo 'Rill graded failure reward contract passed'
