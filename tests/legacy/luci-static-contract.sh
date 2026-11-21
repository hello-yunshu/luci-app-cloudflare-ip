#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_helpers.sh"
for class in cfi-log-area cfi-cmd-box cfi-table-scroll cfi-stats-grid cfi-stat-card ys-tool-footer; do grep -q "\.$class" "$PKG/htdocs/luci-static/resources/cloudflare-ip/cloudflare-ip.css" || fail "CSS $class missing"; done
for js in "$PKG"/htdocs/luci-static/resources/view/cloudflare-ip/*.js; do node --check "$js" >/dev/null; done
echo 'legacy LuCI static contract passed'
