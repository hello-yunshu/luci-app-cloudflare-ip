#!/usr/bin/env bash
# Behavioural tests for the expanded preinst/postinst hooks. The scripts are
# read from the Makefile exactly as the package manager receives them, then
# their absolute OpenWrt paths are rewritten into a disposable fixture root so
# the online branch can be exercised without touching the host.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAKEFILE="$ROOT/package/luci-app-cloudflare-ip/Makefile"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

extract() {
	local name="$1"
	python3 - "$MAKEFILE" "$name" <<'PY'
import sys
text = open(sys.argv[1]).read()
start = 'define Package/luci-app-cloudflare-ip/' + sys.argv[2] + '\n'
body = text.split(start, 1)[1].split('\nendef', 1)[0]
# Make escapes dollar signs in recipes and joins continuation lines.
body = body.replace('\\\n', '\n').replace('$$', '$')
sys.stdout.write(body + '\n')
PY
}

mkdir -p "$TMP/init" "$TMP/stage" "$TMP/src" "$TMP/dst"
: >"$TMP/calls"
: >"$TMP/uci-calls"

stub() {
	local path="$1" label="$2"
	cat >"$path" <<EOF
#!/bin/sh
printf '%s %s\n' "$label" "\${1:-}" >>"$TMP/calls"
if [ "\${FAIL_ACTION:-}" = "$label:\${1:-}" ]; then
	echo "controlled $label failure" >&2
	exit 23
fi
exit 0
EOF
	chmod +x "$path"
}
stub "$TMP/init/cf_ip" cf_ip
stub "$TMP/init/cf_ip_publisher" cf_ip_publisher
stub "$TMP/init/rpcd" rpcd
stub "$TMP/migrate-self-update-url.sh" migrate-self-update-url.sh
stub "$TMP/migrate-managed-config.sh" migrate-managed-config.sh

cat >"$TMP/uci" <<EOF
#!/bin/sh
printf 'uci %s\n' "\$*" >>"$TMP/uci-calls"
EOF
chmod +x "$TMP/uci"

rewrite() {
	local file="$1"
	sed \
		-e "s#/usr/libexec/cf-ip/migrate-self-update-url.sh#$TMP/migrate-self-update-url.sh#g" \
		-e "s#/usr/libexec/cf-ip/migrate-managed-config.sh#$TMP/migrate-managed-config.sh#g" \
		-e "s#/etc/init.d/cf_ip_publisher#$TMP/init/cf_ip_publisher#g" \
		-e "s#/etc/init.d/cf_ip#$TMP/init/cf_ip#g" \
		-e "s#/etc/init.d/rpcd#$TMP/init/rpcd#g" \
		-e "s#/tmp/luci-indexcache\.#$TMP/luci-indexcache.#g" \
		-e "s#/tmp/luci-modulecache/#$TMP/luci-modulecache/#g" \
		-e "s#/tmp/cf_ip/env_cache.json#$TMP/src/env_cache.json#g" \
		-e "s#/tmp/cf_ip/status.json#$TMP/src/status.json#g" \
		-e "s#/etc/cf_ip/env_cache.json#$TMP/dst/env_cache.json#g" \
		-e "s#/etc/cf_ip/status.json#$TMP/dst/status.json#g" \
		-e "s#/etc/cf_ip#$TMP/dst#g" \
		"$file"
}

extract postinst | rewrite /dev/stdin >"$TMP/postinst"
extract preinst | rewrite /dev/stdin >"$TMP/preinst"
sh -n "$TMP/postinst"
sh -n "$TMP/preinst"

run() {
	# run <hook> [env assignments...]
	local hook="$1"; shift
	: >"$TMP/calls"
	: >"$TMP/uci-calls"
	set +e
	env -i PATH="$TMP:$PATH" HOME="$TMP" "$@" sh "$hook" >"$TMP/out" 2>"$TMP/err"
	RC=$?
	set -e
	CALLS="$(sed -e 's/[[:space:]]*$//' "$TMP/calls")"
	ERRS="$(cat "$TMP/err")"
}

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- postinst ----------------------------------------------------------------
printf '{"runId":"r8"}\n' >"$TMP/src/status.json"
printf '{"cache":true}\n' >"$TMP/src/env_cache.json"

run "$TMP/postinst" IPKG_INSTROOT=
[ "$RC" -eq 0 ] || fail "postinst success rc=$RC"
[ "$CALLS" = "migrate-self-update-url.sh
migrate-managed-config.sh
cf_ip enable
rpcd reload" ] || fail "postinst success calls: $CALLS"
[ ! -s "$TMP/uci-calls" ] || fail "postinst wrote global uci state: $(cat "$TMP/uci-calls")"
[ "$(cat "$TMP/dst/status.json")" = '{"runId":"r8"}' ] || fail "status not migrated"
[ "$(cat "$TMP/dst/env_cache.json")" = '{"cache":true}' ] || fail "env cache not migrated"
echo 'PASS postinst online success migrates status and does not touch global LuCI language'

rm -rf "$TMP/dst"; mkdir -p "$TMP/dst"
run "$TMP/postinst" IPKG_INSTROOT= FAIL_ACTION=migrate-self-update-url.sh:
[ "$RC" -ne 0 ] || fail "postinst swallowed self-update migration failure"
case "$ERRS" in *"self-update URL migration failed"*) ;; *) fail "self-update error not reported: $ERRS" ;; esac
case "$CALLS" in *managed*) fail "continued after self-update migration failure: $CALLS" ;; esac
echo 'PASS postinst self-update migration failure is fatal'

run "$TMP/postinst" IPKG_INSTROOT= FAIL_ACTION=migrate-managed-config.sh:
[ "$RC" -ne 0 ] || fail "postinst swallowed managed config migration failure"
case "$ERRS" in *"managed config migration failed"*) ;; *) fail "managed config error not reported: $ERRS" ;; esac
echo 'PASS postinst managed config migration failure is fatal'

run "$TMP/postinst" IPKG_INSTROOT= FAIL_ACTION=cf_ip:enable
[ "$RC" -ne 0 ] || fail "postinst swallowed enable failure"
case "$ERRS" in *"cf_ip enable failed"*) ;; *) fail "enable error not reported: $ERRS" ;; esac
echo 'PASS postinst enable failure is fatal'

rm -rf "$TMP/dst"; : >"$TMP/dst" # a regular file blocks mkdir -p /etc/cf_ip
printf '{"runId":"r8"}\n' >"$TMP/src/status.json"
run "$TMP/postinst" IPKG_INSTROOT=
[ "$RC" -ne 0 ] || fail "postinst swallowed status migration failure"
case "$ERRS" in *"status migration failed"*) ;; *) fail "status migration error not reported: $ERRS" ;; esac
[ -f "$TMP/src/status.json" ] || fail "source status lost on failure"
echo 'PASS postinst status migration failure is fatal'

rm -f "$TMP/dst"; rm -f "$TMP/src/status.json" "$TMP/src/env_cache.json"
run "$TMP/postinst" IPKG_INSTROOT="$TMP/offline"
[ "$RC" -eq 0 ] || fail "offline postinst rc=$RC"
[ -z "$CALLS" ] || fail "offline postinst touched online lifecycle: $CALLS"
echo 'PASS postinst offline root skips online lifecycle'

# --- preinst ----------------------------------------------------------------
run "$TMP/preinst" IPKG_INSTROOT= PKG_UPGRADE=0
[ "$RC" -eq 0 ] || fail "fresh install preinst rc=$RC"
[ -z "$CALLS" ] || fail "preinst stopped services for a fresh install: $CALLS"
echo 'PASS preinst fresh install does not stop services'

run "$TMP/preinst" IPKG_INSTROOT="$TMP/offline" PKG_UPGRADE=1
[ "$RC" -eq 0 ] || fail "offline preinst rc=$RC"
[ -z "$CALLS" ] || fail "offline preinst touched services: $CALLS"
echo 'PASS preinst offline root skips online lifecycle'

run "$TMP/preinst" IPKG_INSTROOT= PKG_UPGRADE=1 FAIL_ACTION=cf_ip:stop
[ "$RC" -ne 0 ] || fail "preinst swallowed cf_ip stop failure"
case "$ERRS" in *"cf_ip stop failed"*) ;; *) fail "stop error not reported: $ERRS" ;; esac
[ "$CALLS" = "cf_ip stop" ] || fail "preinst continued after stop failure: $CALLS"
echo 'PASS preinst refuses upgrade when cf_ip stop fails'

run "$TMP/preinst" IPKG_INSTROOT= PKG_UPGRADE=1 FAIL_ACTION=cf_ip_publisher:stop
[ "$RC" -ne 0 ] || fail "preinst swallowed publisher stop failure"
[ "$CALLS" = "cf_ip stop
cf_ip_publisher stop" ] || fail "preinst calls on publisher failure: $CALLS"
echo 'PASS preinst refuses upgrade when publisher stop fails'

run "$TMP/preinst" IPKG_INSTROOT= PKG_UPGRADE=1
[ "$RC" -eq 0 ] || fail "preinst success rc=$RC"
[ "$CALLS" = "cf_ip stop
cf_ip_publisher stop" ] || fail "preinst success calls: $CALLS"
echo 'PASS preinst upgrade stops both services'

echo 'package lifecycle behaviour passed'
