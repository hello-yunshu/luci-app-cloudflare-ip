#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INIT="${CFIP_TEST_INIT:-$ROOT/package/luci-app-cloudflare-ip/root/etc/init.d/cf_ip}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
. "$INIT"
CRONTAB_FILE="$TMP/root"
cf_ip_cron_ensure(){ :; }
cf_ip_cron_reload(){ :; }
logger(){ :; }
cat >"$TMP/user" <<'CRON'
# user note: cf-ip-auto --run should stay documented
# a b c d /usr/bin/cf-ip-auto --run >/dev/null 2>&1
17 3 * * * /usr/bin/printf 'cf-ip-auto --run'
19 3 * * * /usr/bin/cf-ip-auto --run --custom > /tmp/user.log
20 3 * * * /usr/bin/cf-ip-auto --run >/dev/null 2>&1 # user-owned
21 3 * * * /usr/bin/printf 'cf-ip-auto --sync'
CRON
cp "$TMP/user" "$CRONTAB_FILE"
printf '0 */6 * * * /usr/bin/cf-ip-auto --run >/dev/null 2>&1\n0 * * * * /usr/bin/cf-ip-auto --sync >/dev/null 2>&1\n' >>"$CRONTAB_FILE"
cf_ip_cron_remove
cmp "$TMP/user" "$CRONTAB_FILE"
echo 'PASS removal preserves comments and custom user commands; removes exact historical run/sync entries'
cf_ip_cron_add '0 */6 * * *'
cf_ip_cron_add '0 */6 * * *'
cp "$TMP/user" "$TMP/expected"
printf '0 */6 * * * /usr/bin/cf-ip-auto --run >/dev/null 2>&1 # cf_ip managed\n' >>"$TMP/expected"
cmp "$TMP/expected" "$CRONTAB_FILE"
echo 'PASS duplicate scheduling leaves exactly one managed entry and preserves user lines'
cf_ip_cron_remove
cmp "$TMP/user" "$CRONTAB_FILE"
echo 'PASS managed removal preserves user tasks'
cp "$CRONTAB_FILE" "$TMP/before"
mv(){ return 23; }
if cf_ip_cron_add '0 */6 * * *'; then echo 'failed cron publication reported success' >&2;exit 1;fi
cmp "$TMP/before" "$CRONTAB_FILE"
unset -f mv
echo 'PASS failed cron rename preserves old crontab and returns failure'
for fault in cp awk; do
    eval "$fault(){ return 23; }"
    if cf_ip_cron_add '0 */6 * * *'; then echo "failed $fault reported success" >&2;exit 1;fi
    cmp "$TMP/before" "$CRONTAB_FILE"
    unset -f "$fault"
done
test -z "$(find "$TMP" -name 'root.cf_ip.*' -print)"
echo 'PASS failed preimage copy/render preserves old file and cleans staging'
chmod 600 "$CRONTAB_FILE"
cf_ip_cron_add '0 */6 * * *'
python3 - "$CRONTAB_FILE" <<'PYMODE'
import stat,sys
from pathlib import Path
p=Path(sys.argv[1]);assert stat.S_IMODE(p.stat().st_mode)==0o600
assert p.read_bytes().endswith(b'\n') and b'\\n' not in p.read_bytes()
PYMODE
echo 'PASS cron publication preserves private file mode and terminates the command line'
