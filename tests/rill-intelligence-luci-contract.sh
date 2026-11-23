#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; file="$ROOT/package/luci-app-cloudflare-ip/htdocs/luci-static/resources/view/cloudflare-ip/intelligence.js"
node --check "$file"
grep -Eq 'Decision Evidence|Native Holdout|Decision Confidence|Learning Context|Unavailable / Native fallback' "$file"
grep -Eq 'Rill Runtime: Not installed|Native mode remains available|rill-runtime' "$file"
grep -Eq 'native|Rill|wins|ties|losses|holdout|fallback' "$file"
# The package channel and the Runtime protocol surface are different things and
# must be rendered from their own fields instead of the old shared "channel".
grep -Eq 'packageChannel' "$file"
grep -Eq 'protocolChannel' "$file"
# Evidence freshness is decided by the engine (fresh / stale / expired / none)
# and only translated in the view; the row must not derive it locally.
grep -Eq '_evidence_freshness' "$file"
grep -Eq "statusLabel\('freshness'" "$file"
grep -Eq 'qualificationFreshness' "$file"
grep -Eq "statusLabel\('evaluation'" "$file"
# contextChanged is emitted inside intelligence, so the row must read it there.
grep -Eq 'i\.contextChanged' "$file"
utils="$ROOT/package/luci-app-cloudflare-ip/htdocs/luci-static/resources/cloudflare-ip/utils.js"
grep -Eq "freshness: \{" "$utils"
grep -Eq "evaluation: \{" "$utils"
echo 'Intelligence LuCI fail-safe evidence contract passed'
