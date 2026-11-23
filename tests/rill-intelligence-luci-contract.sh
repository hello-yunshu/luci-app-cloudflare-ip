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
# Runtime package actions must stay above the tuning knobs: the feed refresh
# and Runtime repair are maintenance actions, not part of the live-state rows.
pkg_line=$(grep -n "_package_refresh', _('Runtime Package Management')" "$file" | head -1 | cut -d: -f1)
section_line=$(grep -n "_('Rill Runtime')" "$file" | head -1 | cut -d: -f1)
consumer_line=$(grep -n "Rill Runtime Consumer" "$file" | head -1 | cut -d: -f1)
live_line=$(grep -n "'Live State'" "$file" | head -1 | cut -d: -f1)
[ -n "$pkg_line" ] && [ -n "$section_line" ] && [ -n "$consumer_line" ] && [ -n "$live_line" ] \
  || { echo 'FAIL: Runtime package section or anchors missing from Intelligence view' >&2; exit 1; }
(( section_line < pkg_line )) || { echo 'FAIL: Runtime package actions must be inside the Rill Runtime section' >&2; exit 1; }
(( pkg_line < consumer_line )) || { echo 'FAIL: Runtime package actions must precede the Runtime consumer settings' >&2; exit 1; }
(( pkg_line < live_line )) || { echo 'FAIL: Runtime package actions must not be buried in Live State' >&2; exit 1; }

echo 'Intelligence LuCI fail-safe evidence contract passed'
