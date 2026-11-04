#!/usr/bin/env bash
set -euo pipefail
ROOT=/Users/yunshu/Documents/GitHub/luci-app-cloudflare-ip
SHOT="$ROOT/docs/audits/next-release-evidence/visual-2e28db4"
BASE=http://127.0.0.1:18080/cgi-bin/luci/admin/services/cf_ip
PAGES=(overview settings sources intelligence openclash passwall advanced logs)
THETHEME="${1:-}"
METRICS="$SHOT/metrics.jsonl"

set_theme() {
  local theme="$1" media="$2" localstore="$3"
  docker exec cfip-audit-luci sh -c "uci set luci.main.mediaurlbase='$media'; uci commit luci; rm -rf /tmp/luci-indexcache*; /etc/init.d/uhttpd restart >/dev/null 2>&1"
  agent-browser eval "localStorage.setItem('aurora.theme','$localstore'); location.reload();" >/dev/null 2>&1 || true
  sleep 2
  agent-browser open "$BASE/overview" >/dev/null 2>&1 || true
  agent-browser wait --load networkidle >/dev/null 2>&1 || true
}

capture() {
  local theme="$1" vp="$2" page="$3"
  local url="$BASE/$page"
  agent-browser open "$url" >/dev/null 2>&1 || true
  agent-browser wait --load networkidle >/dev/null 2>&1 || true
  agent-browser errors --clear >/dev/null 2>&1 || true
  agent-browser screenshot "$SHOT/$theme/$vp/$page.png" >/dev/null 2>&1
  local metric
  metric="$(agent-browser eval "JSON.stringify({theme:'$theme',viewport:'$vp',page:'$page',title:document.title,path:location.pathname,w:innerWidth,h:innerHeight,docScrollWidth:document.documentElement.scrollWidth,bodyScrollWidth:document.body.scrollWidth,overflow:(document.documentElement.scrollWidth>innerWidth||document.body.scrollWidth>innerWidth),textLen:(document.querySelector('#maincontent')||document.body).innerText.length,dark:document.documentElement.getAttribute('data-darkmode'),login:!!document.querySelector('input[name=luci_password]')})" 2>/dev/null | sed -e 's/^"//' -e 's/"$//' -e 's/\\"/"/g')"
  printf '%s\n' "$metric" >> "$METRICS"
  local errs
  errs="$(agent-browser errors 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g')"
  printf 'ERRORS\t%s\t%s\t%s\t%s\n' "$theme" "$vp" "$page" "${errs:-none}" >> "$METRICS.errors"
}

for theme in ${THETHEME:-bootstrap aurora-light aurora-dark}; do
  case "$theme" in
    bootstrap) set_theme "$theme" /luci-static/bootstrap light ;;
    aurora-light) set_theme "$theme" /luci-static/aurora light ;;
    aurora-dark) set_theme "$theme" /luci-static/aurora dark ;;
  esac
  mkdir -p "$SHOT/$theme/320x900" "$SHOT/$theme/1280x900-200pct-effective-640"
  for vp in 375x900 768x900 1280x900; do
    w=${vp%x*}; h=${vp#*x}
    agent-browser set viewport "$w" "$h" >/dev/null 2>&1 || true
    for page in "${PAGES[@]}"; do
      capture "$theme" "$vp" "$page"
    done
  done
  # Boundary: 320px narrow overview
  agent-browser set viewport 320 900 >/dev/null 2>&1 || true
  capture "$theme" 320x900 overview
  # Boundary: 1280px desktop at 200% effective CSS width (~640px)
  agent-browser set viewport 640 900 >/dev/null 2>&1 || true
  capture "$theme" 1280x900-200pct-effective-640 sources
done

echo "captured"
wc -l "$METRICS"
