#!/usr/bin/env bash
# Contract: /etc/cf_ip (run history, Rill state, qualification evidence) must
# survive a sysupgrade. On the device this is what keeps the Rill learner from
# restarting collection from scratch after every flash.
#
# Two independent mechanisms have to hold:
#   * /lib/upgrade/keep.d/<pkg>  -> sysupgrade carries the directory over.
#   * conffiles                  -> package upgrade never rewrites/removes it.
# The keep.d rule historically reached the device inside an older package build
# and was never reproducible from this tree, so a clean rebuild would silently
# drop it. This test pins the shipping contract.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/package/luci-app-cloudflare-ip"
KEEP="$PKG/root/lib/upgrade/keep.d/luci-app-cloudflare-ip"
MAKEFILE="$PKG/Makefile"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

# 1. The rule ships from the tree.
[ -f "$KEEP" ] || fail "missing $KEEP"
[ ! -L "$KEEP" ] || fail "$KEEP must be a regular file, not a symlink"
pass "keep.d rule is present in the package root"

# 2. Exactly one entry, absolute, newline-terminated, no CRLF.
expected='/etc/cf_ip'
[ "$(wc -l <"$KEEP" | tr -d ' ')" = 1 ] || fail "keep.d must hold exactly one entry, got $(wc -l <"$KEEP")"
[ "$(cat "$KEEP")" = "$expected" ] || fail "keep.d entry must be exactly '$expected', got '$(cat "$KEEP")'"
grep -q $'\r' "$KEEP" && fail "keep.d entry must not contain CR"
while IFS= read -r entry; do
	[ -n "$entry" ] || continue
	case "$entry" in
		/*) ;;
		*) fail "keep.d entry must be absolute: $entry" ;;
	esac
	case "$entry" in
		*'*'*|*'?'*|*'['*) fail "keep.d entry must be a literal path, not a glob: $entry" ;;
	esac
	[ "$entry" = "${entry% }" ] || fail "keep.d entry has trailing whitespace: '$entry'"
done <"$KEEP"
pass "keep.d keeps $expected as a single literal absolute path"

# 3. The Makefile actually installs it. A rule that exists in the tree but is
#    not installed never reaches the device.
grep -Fq '$(INSTALL_DIR) $(1)/lib/upgrade/keep.d' "$MAKEFILE" \
	|| fail "Makefile does not create \$(1)/lib/upgrade/keep.d"
grep -Fq 'root/lib/upgrade/keep.d/luci-app-cloudflare-ip $(1)/lib/upgrade/keep.d/' "$MAKEFILE" \
	|| fail "Makefile does not install the keep.d rule"
pass "Makefile installs the rule into /lib/upgrade/keep.d"

# 4. Package upgrade path: the directory stays a conffile, so replacing the
#    package never rewrites the accumulated state.
awk '/^define Package\/luci-app-cloudflare-ip\/conffiles$/{inside=1;next} inside && /^endef$/{exit} inside{print}' "$MAKEFILE" \
	| grep -qxF "$expected" || fail "$expected missing from conffiles"
pass "$expected remains a conffile"

# 5. The file must not be swallowed by .gitignore, or the rule disappears again
#    on the next clean checkout.
if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
	git -C "$ROOT" check-ignore -q "$KEEP" && fail "$KEEP is gitignored"
	pass "keep.d rule is tracked, not gitignored"
fi

# 6. Rill learning state really lives under the kept path, so keeping
#    /etc/cf_ip is sufficient and no second keep entry is needed.
RILL="$PKG/root/usr/libexec/cf-ip/candidate-rill.sh"
for file in rill-qualification.json rill-evidence.json rill-state-meta.json candidate-history.json rill-pending-feedback.json; do
	grep -Fq "\$CFIP_RILL_BASE_DIR/$file" "$RILL" \
		|| fail "$RILL no longer derives $file from \$CFIP_RILL_BASE_DIR; revisit the keep list"
done
grep -Fq '${CFIP_RILL_STATE:-/etc/cf_ip}' "$RILL" \
	|| fail "Rill base dir no longer defaults to /etc/cf_ip; keep list must be updated"
# rill-state.json is the only path that comes from UCI, so it is pinned there.
grep -Fq '/etc/cf_ip/rill-state.json' "$PKG/root/usr/libexec/cf-ip/migrate-managed-config.sh" \
	|| fail "default rill state_file is no longer /etc/cf_ip/rill-state.json"
pass "all Rill state files resolve under $expected"

echo "sysupgrade-keep-contract: PASS"
