#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INIT="$ROOT/package/luci-app-cloudflare-ip/root/etc/init.d/cf_ip"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

# Extract the helper from the init script (the file cannot be sourced directly
# because it is an rc.common service wrapper).
helper="$(awk '/^cf_ip_sysupgrade_write\(\) \{/{inside=1} inside{print} inside && /^\}$/{exit}' "$INIT")"
[ -n "$helper" ] || fail "cf_ip_sysupgrade_write not found in $INIT"
eval "$helper"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/cfip-sysupgrade.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
CONF="$WORK/sysupgrade.conf"
export CF_IP_SYSUPGRADE_CONF="$CONF"

entries() { grep -c '^/usr/bin/cfst/cfst$' "$CONF" 2>/dev/null || true; }
mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }
no_temp() { [ "$(find "$WORK" -maxdepth 1 -name 'sysupgrade.conf.cfip.*' | wc -l | tr -d ' ')" = 0 ]; }

# 1. add creates the file with the expected mode and one entry.
cf_ip_sysupgrade_write add "/usr/bin/cfst/cfst" || fail "add on missing file failed"
[ "$(entries)" = 1 ] || fail "expected one entry, got $(entries)"
[ "$(mode_of "$CONF")" = 644 ] || fail "expected mode 644, got $(mode_of "$CONF")"
no_temp || fail "temporary file left behind after add"
pass "add creates a 644 keep-list entry"

# 2. add is idempotent and keeps unrelated lines.
printf '%s\n' "/etc/config/cf_ip" "/usr/bin/other" >>"$CONF"
cf_ip_sysupgrade_write add "/usr/bin/cfst/cfst" || fail "second add failed"
[ "$(entries)" = 1 ] || fail "duplicate entry after second add"
grep -qxF "/etc/config/cf_ip" "$CONF" || fail "unrelated line lost"
grep -qxF "/usr/bin/other" "$CONF" || fail "unrelated line lost"
pass "add is idempotent and preserves unrelated lines"

# 3. remove deletes only the exact line.
cf_ip_sysupgrade_write remove "/usr/bin/cfst/cfst" || fail "remove failed"
[ "$(entries)" = 0 ] || fail "entry still present after remove"
grep -qxF "/etc/config/cf_ip" "$CONF" || fail "remove dropped unrelated line"
no_temp || fail "temporary file left behind after remove"
pass "remove deletes only the target line"

# 4. removing the only line yields an empty (but valid) file.
printf '%s\n' "/usr/bin/cfst/cfst" >"$CONF"
cf_ip_sysupgrade_write remove "/usr/bin/cfst/cfst" || fail "remove of last line failed"
[ ! -s "$CONF" ] || fail "expected empty file after removing last line"
pass "remove of the last entry leaves an empty file"

# 5. remove on a missing file is a no-op success and creates nothing.
rm -f "$CONF"
cf_ip_sysupgrade_write remove "/usr/bin/cfst/cfst" || fail "remove on missing file failed"
[ ! -e "$CONF" ] || fail "remove created the file"
no_temp || fail "temporary file left behind for missing-file remove"
pass "remove on a missing file is a no-op"

# 6. a failure while rewriting leaves the original file untouched.
printf '%s\n' "/etc/config/cf_ip" >"$CONF"
CF_IP_SYSUPGRADE_CONF="$WORK/missing-dir/sysupgrade.conf" cf_ip_sysupgrade_write add "/usr/bin/cfst/cfst" 2>/dev/null \
	&& fail "add into a missing directory unexpectedly succeeded"
grep -qxF "/etc/config/cf_ip" "$CONF" || fail "original file changed after failed write"
pass "failed rewrite leaves the original file intact"

# 7. concurrent adders keep exactly one entry and leave no temp files.
rm -f "$CONF"
printf '%s\n' "/etc/config/cf_ip" >"$CONF"
pids=()
for _ in $(seq 1 20); do
	cf_ip_sysupgrade_write add "/usr/bin/cfst/cfst" &
	pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid" || fail "concurrent add failed"; done
[ "$(entries)" = 1 ] || fail "expected one entry after concurrent adds, got $(entries)"
grep -qxF "/etc/config/cf_ip" "$CONF" || fail "concurrent add dropped unrelated line"
no_temp || fail "temporary files left behind after concurrent adds"
pass "20 concurrent adds keep exactly one entry"

echo "sysupgrade-config-atomic: 7 PASS"
