#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_helpers.sh"
INIT="$PKG/root/etc/init.d/cf_ip"
for fn in start_service stop_service reload_service service_triggers validate_cf_ip; do grep -q "^$fn" "$INIT" || fail "missing init lifecycle $fn"; done
grep -q -- '--run' "$INIT" || fail "missing run entry"
grep -q -- '--download-cfst' "$INIT" || fail "missing download entry"
grep -q -- '--sync' "$INIT" || fail "missing sync entry"
# Both entries stay reachable, but startup must submit one job: the first run
# takes --run and later boots take --download-cfst.
grep -Fq 'if [ "$first_run" -eq 1 ]; then' "$INIT" || fail "startup is not a single-job branch"
echo 'legacy service lifecycle contract passed'
