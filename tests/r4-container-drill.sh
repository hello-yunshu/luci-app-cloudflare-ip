#!/usr/bin/env bash
# R4 real-container drill: fresh install, r8->r9 upgrade, rollback, ENOSPC and
# power-loss with the package format native to the container. Runs on the host
# and drives disposable privileged Docker containers.
#
# usage: r4-container-drill.sh --kind ipk|apk --image IMG --r8 FILE --r9 FILE --out DIR
set -euo pipefail

KIND=""; IMAGE=""; R8=""; R9=""; OUT=""
while [ $# -gt 0 ]; do
	case "$1" in
		--kind) KIND="$2"; shift 2 ;;
		--image) IMAGE="$2"; shift 2 ;;
		--r8) R8="$2"; shift 2 ;;
		--r9) R9="$2"; shift 2 ;;
		--out) OUT="$2"; shift 2 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done
[ -n "$KIND" ] && [ -n "$IMAGE" ] && [ -f "$R8" ] && [ -f "$R9" ] && [ -n "$OUT" ] || {
	echo "usage: $0 --kind ipk|apk --image IMG --r8 FILE --r9 FILE --out DIR" >&2
	exit 2
}
case "$KIND" in ipk|apk) ;; *) echo "kind must be ipk or apk" >&2; exit 2 ;; esac

mkdir -p "$OUT"
CONTAINERS=()
cleanup() {
	local c
	for c in ${CONTAINERS[@]+"${CONTAINERS[@]}"}; do
		[ -n "$c" ] && docker rm -f "$c" >/dev/null 2>&1 || true
	done
}
trap cleanup EXIT
trap 'exit 130' INT TERM

FAILS=0
pass() { echo "PASS $*" | tee -a "$OUT/summary.txt"; }
fail() { echo "FAIL $*" | tee -a "$OUT/summary.txt"; FAILS=$((FAILS + 1)); }

LAST_CONTAINER=""
new_container() {
	local suffix="$1"
	LAST_CONTAINER="cfip-r4-${KIND}-${suffix}-$$"
	CONTAINERS+=("$LAST_CONTAINER")
	docker rm -f "$LAST_CONTAINER" >/dev/null 2>&1 || true
	docker run -d --platform linux/amd64 --name "$LAST_CONTAINER" --privileged "$IMAGE" sleep infinity >/dev/null
	sleep 1
}

# docker exec has no deadline of its own and a stalled feed read can hang
# forever, so run it in the background and reap it after a hard limit.
docker_exec_timeout() { # seconds container command...
	local secs="$1" c="$2"
	shift 2
	docker exec "$c" "$@" &
	local pid=$! i=0
	while kill -0 "$pid" 2>/dev/null; do
		if [ "$i" -ge "$secs" ]; then
			# Kill the container-side shell as well: otherwise its retry loop
			# keeps running and collides with the next attempt.
			docker exec "$c" sh -c 'killall -9 opkg uclient-fetch apk wget 2>/dev/null; killall -9 sh 2>/dev/null; true' >/dev/null 2>&1 || true
			kill -9 "$pid" 2>/dev/null || true
			wait "$pid" 2>/dev/null || true
			echo "timed out after ${secs}s: $*" >&2
			return 124
		fi
		sleep 1
		i=$((i + 1))
	done
	wait "$pid"
}

prep_container() {
	local c="$1" n=0 rc=0
	while [ "$n" -lt 3 ]; do
		rc=0
		case "$KIND" in
			ipk)
				docker_exec_timeout 180 "$c" sh -c '
					mkdir -p /var/lock /etc/opkg /usr/local/bin
					# The rootfs feed client has no read deadline; cap each request.
					cat >/usr/local/bin/wget <<'"'"'EOF'"'"'
#!/bin/sh
exec /bin/uclient-fetch -T 20 "$@"
EOF
					chmod +x /usr/local/bin/wget
					PATH="/usr/local/bin:$PATH"; export PATH
					grep -q openwrt_packages /etc/opkg/distfeeds.conf || echo "src/gz openwrt_packages https://downloads.openwrt.org/releases/24.10.8/packages/x86_64/packages" >> /etc/opkg/distfeeds.conf
					missing=0
					for p in bash jq curl flock tar ca-bundle ca-certificates luci-base; do
						opkg list-installed | grep -q "^$p " || missing=1
					done
					[ "$missing" -eq 0 ] && exit 0
					i=0
					while [ "$i" -lt 6 ]; do
						opkg update >/tmp/opkg-update.log 2>&1 || true
						opkg install bash jq curl flock tar ca-bundle ca-certificates luci-base --force-depends >/tmp/opkg-deps.log 2>&1 || true
						missing=0
						for p in bash jq curl flock tar ca-bundle ca-certificates luci-base; do
							opkg list-installed | grep -q "^$p " || missing=1
						done
						[ "$missing" -eq 0 ] && exit 0
						i=$((i + 1)); sleep 2
					done
					exit 1' >/dev/null 2>&1 || rc=$?
				;;
			apk)
				docker_exec_timeout 180 "$c" sh -c '
					mkdir -p /var/lock
					missing=0
					for p in bash jq curl tar flock ca-certificates luci-base; do
						apk list --installed 2>/dev/null | grep -q "^$p-" || missing=1
					done
					[ "$missing" -eq 0 ] && exit 0
					missing=1; i=0
					while [ "$i" -lt 6 ]; do
						apk update >/tmp/apk-update.log 2>&1 || true
						apk add bash jq curl tar flock ca-bundle ca-certificates luci-base >/tmp/apk-deps.log 2>&1 || true
						missing=0
						for p in bash jq curl tar flock ca-certificates luci-base; do
							apk list --installed 2>/dev/null | grep -q "^$p-" || missing=1
						done
						[ "$missing" -eq 0 ] && exit 0
						i=$((i + 1)); sleep 2
					done
					exit 1' >/dev/null 2>&1 || rc=$?
				;;
		esac
		[ "$rc" -eq 0 ] && return 0
		# A killed package manager can leave its database lock behind; clear
		# both formats before the next attempt.
		docker exec "$c" sh -c 'rm -f /usr/lib/opkg/lock /var/lock/opkg.lock /var/lock/apk.lock /lib/apk/db/lock' >/dev/null 2>&1 || true
		n=$((n + 1))
	done
	docker cp "$c:/tmp/apk-deps.log" "$OUT/prep-$KIND-$c.log" >/dev/null 2>&1 ||
		docker cp "$c:/tmp/opkg-deps.log" "$OUT/prep-$KIND-$c.log" >/dev/null 2>&1 || true
	return 1
}

install_pkg() { # container pkg-file logfile -> rc (opkg requires the .ipk suffix)
	local c="$1" pkg="$2" log="$3" remote="/tmp/install.${KIND}"
	docker cp "$pkg" "$c:$remote" >/dev/null
	case "$KIND" in
		ipk)
			docker_exec_timeout 180 "$c" sh -c "umask 0022; opkg install --force-depends $remote >/tmp/$log 2>&1" || return $?
			;;
		apk)
			docker_exec_timeout 180 "$c" sh -c "umask 0022; apk add --allow-untrusted $remote >/tmp/$log 2>&1" || return $?
			;;
	esac
	return 0
}

rollback_pkg() { # container r8-file
	local c="$1" remote="/tmp/rollback.${KIND}"
	docker cp "$2" "$c:$remote" >/dev/null
	case "$KIND" in
		ipk)
			docker_exec_timeout 180 "$c" sh -c "umask 0022; opkg install --force-downgrade --force-depends $remote >/tmp/rollback.log 2>&1" || return $?
			;;
		apk)
			docker_exec_timeout 180 "$c" sh -c "umask 0022; apk add --allow-untrusted --force-broken-world $remote >/tmp/rollback.log 2>&1" || return $?
			;;
	esac
	return 0
}

# The upstream package feeds are occasionally flaky in CI, so a first install
# that fails on a dependency download is retried until the expected version is
# actually registered.
install_until_version() { # container pkg-file expected-version logfile
	local c="$1" pkg="$2" expected="$3" log="$4" i=0
	while [ "$i" -lt 5 ]; do
		install_pkg "$c" "$pkg" "$log" || true
		[ "$(version_in "$c")" = "$expected" ] && return 0
		case "$KIND" in
			ipk) docker exec "$c" sh -c 'opkg update >/dev/null 2>&1 || true' >/dev/null 2>&1 || true ;;
			apk) docker exec "$c" sh -c 'apk update >/dev/null 2>&1 || true' >/dev/null 2>&1 || true ;;
		esac
		i=$((i + 1))
		sleep 2
	done
	return 1
}

version_in() {
	case "$KIND" in
		ipk) docker exec "$1" sh -c 'opkg list-installed 2>/dev/null | awk "/luci-app-cloudflare-ip /{print \$3}"' ;;
		apk) docker exec "$1" sh -c "apk list --installed 2>/dev/null | grep luci-app-cloudflare-ip | grep -o '2\\.6\\.0-r[0-9]*' | head -1" ;;
	esac
}

status_ok() { # container [expected-version]
	local expected="${2:-2.6.0-r9}"
	rm -f "$OUT/status.txt"
	docker exec "$1" sh -c '/usr/bin/cf-ip-auto --status 2>/dev/null' >"$OUT/status.txt" 2>/dev/null || true
	grep -Eq '"schemaVersion":\s*2' "$OUT/status.txt" &&
		grep -Eq "\"package_version\":\s*\"$expected\"" "$OUT/status.txt"
}

set_drill_config() {
	docker exec "$1" sh -c 'umask 0022; uci -q set cf_ip.main.enabled=1; uci -q set cf_ip.main.ip_count=5; uci -q set cf_ip.passwall.target_domain=example.com; uci -q commit cf_ip'
}
config_sha() { docker exec "$1" sh -c 'sha256sum /etc/config/cf_ip | cut -d" " -f1'; }
config_values() { docker exec "$1" sh -c 'echo "count=$(uci -q get cf_ip.main.ip_count) domain=$(uci -q get cf_ip.passwall.target_domain)"'; }
config_preserved() { # container before-sha
	local now
	now="$(config_sha "$1")"
	[ "$now" = "$2" ] || { fail "config hash changed: $2 -> $now"; return 1; }
	[ "$(config_values "$1")" = "count=5 domain=example.com" ] || { fail "config values changed: $(config_values "$1")"; return 1; }
	return 0
}

echo "kind=$KIND image=$IMAGE" | tee "$OUT/summary.txt"

prep_or_die() { # container label
	if ! prep_container "$1"; then
		fail "$2 container preparation failed (package feed unavailable); log in $OUT"
		exit 1
	fi
}

# ---- A. fresh install -------------------------------------------------------
new_container fresh; fresh="$LAST_CONTAINER"; prep_or_die "$fresh" fresh
install_until_version "$fresh" "$R9" 2.6.0-r9 fresh.log || true
fresh_ver="$(version_in "$fresh")"
if [ "$fresh_ver" = "2.6.0-r9" ] && status_ok "$fresh"; then
	pass "fresh install $fresh_ver with working --status"
else
	fail "fresh install: version=${fresh_ver:-<none>} status=$(tr '\n' ' ' <"$OUT/status.txt" 2>/dev/null | head -c 200)"
fi

# ---- B. r8 -> r9 upgrade ----------------------------------------------------
new_container upgrade; up="$LAST_CONTAINER"; prep_or_die "$up" upgrade
install_until_version "$up" "$R8" 2.6.0-r8 r8.log || true
seed_ver="$(version_in "$up")"
[ "$seed_ver" = "2.6.0-r8" ] || fail "r8 seed install failed: ${seed_ver:-<none>}"
set_drill_config "$up"
before_sha="$(config_sha "$up")"
install_until_version "$up" "$R9" 2.6.0-r9 r9.log || true
up_ver="$(version_in "$up")"
if [ "$up_ver" = "2.6.0-r9" ] && config_preserved "$up" "$before_sha" && status_ok "$up"; then
	pass "r8->r9 upgrade, config hash and values preserved, --status works"
else
	fail "r8->r9 upgrade: version=${up_ver:-<none>} config=$(config_values "$up" 2>/dev/null)"
fi

# ---- C. rollback ------------------------------------------------------------
i=0
while [ "$i" -lt 5 ]; do
	rollback_pkg "$up" "$R8" || true
	[ "$(version_in "$up")" = "2.6.0-r8" ] && break
	i=$((i + 1)); sleep 2
done
rb_ver="$(version_in "$up")"
if [ "$rb_ver" = "2.6.0-r8" ] && config_preserved "$up" "$before_sha" && status_ok "$up" 2.6.0-r8; then
	pass "rollback to r8 with config preserved and working --status"
else
	fail "rollback: version=${rb_ver:-<none>} config=$(config_values "$up" 2>/dev/null)"
fi

# ---- D. ENOSPC --------------------------------------------------------------
new_container enospc; enospc="$LAST_CONTAINER"; prep_or_die "$enospc" enospc
# A mount made by one docker exec does not survive into the next one, so the
# mount, fill, failing install and unmount all run in a single shell. The copy
# of /usr must fit; the dd fill then consumes every remaining block.
used_k="$(docker exec "$enospc" sh -c 'du -sk /usr | cut -f1')"
size="$((used_k + 4096))k"
docker cp "$R9" "$enospc:/tmp/install.$KIND" >/dev/null
case "$KIND" in
	ipk) install_cmd="opkg install --force-depends /tmp/install.ipk >/tmp/enospc.log 2>&1; echo \$? >/tmp/enospc-rc" ;;
	apk) install_cmd="apk add --allow-untrusted /tmp/install.apk >/tmp/enospc.log 2>&1; echo \$? >/tmp/enospc-rc" ;;
esac
docker_exec_timeout 300 "$enospc" sh -c "
	rm -rf /root/usr.bak
	cp -a /usr /root/usr.bak || exit 1
	mount -t tmpfs -o size=$size tmpfs /usr || exit 1
	cp -a /root/usr.bak/. /usr/ || exit 1
	free=\$(df -k /usr | awk 'NR==2{print \$4}')
	dd if=/dev/zero of=/usr/.fill bs=1024 count=\$free 2>/dev/null || true
	df -k /usr | tail -1 > /tmp/enospc-fill.log
	umask 0022
	$install_cmd
	if [ -s /usr/bin/cf-ip-auto ]; then echo payload_ok > /tmp/enospc-state; else echo payload_broken > /tmp/enospc-state; fi
	rm -f /usr/.fill
	umount /usr || umount -l /usr || true
	rm -rf /root/usr.bak" >/dev/null 2>&1 || true
docker cp "$enospc:/tmp/enospc.log" "$OUT/enospc.log" >/dev/null 2>&1 || true
docker cp "$enospc:/tmp/enospc-fill.log" "$OUT/enospc-fill.log" >/dev/null 2>&1 || true
docker cp "$enospc:/tmp/enospc-state" "$OUT/enospc-state" >/dev/null 2>&1 || true
docker cp "$enospc:/tmp/enospc-rc" "$OUT/enospc-rc" >/dev/null 2>&1 || true
# APK reports ENOSPC explicitly. IPK's opkg can return 0 while writing a
# zero-length payload, so a broken install on a full filesystem is also a
# genuine out-of-space outcome (recorded, not hidden).
if grep -qi 'no space left on device' "$OUT/enospc.log" || grep -q 'payload_broken' "$OUT/enospc-state" 2>/dev/null; then
	pass "ENOSPC prevented a valid install (rc=$(cat "$OUT/enospc-rc" 2>/dev/null), state=$(cat "$OUT/enospc-state" 2>/dev/null))"
else
	fail "ENOSPC drill did not reach a real out-of-space outcome"
fi
install_until_version "$enospc" "$R9" 2.6.0-r9 recover.log || true
rec_ver="$(version_in "$enospc")"
if [ "$rec_ver" = "2.6.0-r9" ] && status_ok "$enospc"; then
	pass "ENOSPC recovery reinstall reaches r9 with working --status"
else
	fail "ENOSPC recovery: version=${rec_ver:-<none>}"
fi

# ---- E. power loss ----------------------------------------------------------
new_container power; power="$LAST_CONTAINER"; prep_or_die "$power" power
install_until_version "$power" "$R8" 2.6.0-r8 r8.log || true
seed_ver="$(version_in "$power")"
[ "$seed_ver" = "2.6.0-r8" ] || fail "power-loss r8 seed install failed: ${seed_ver:-<none>}"
set_drill_config "$power"
before_sha="$(config_sha "$power")"
docker cp "$R9" "$power:/tmp/install.apk" >/dev/null 2>&1 || true
docker cp "$R9" "$power:/tmp/install.ipk" >/dev/null 2>&1 || true
case "$KIND" in
	ipk) docker exec -d "$power" sh -c 'umask 0022; opkg install --force-depends /tmp/install.ipk >/tmp/power.log 2>&1' ;;
	apk) docker exec -d "$power" sh -c 'umask 0022; apk add --allow-untrusted /tmp/install.apk >/tmp/power.log 2>&1' ;;
esac
sleep 0.15
docker kill "$power" >/dev/null
sleep 1
docker start "$power" >/dev/null
sleep 1
power_ver="$(version_in "$power")"
if [ "$power_ver" = "2.6.0-r8" ] && config_preserved "$power" "$before_sha"; then
	pass "power-loss left r8 intact with original config"
else
	fail "power-loss state: version=${power_ver:-<none>} config=$(config_values "$power" 2>/dev/null)"
fi
# A killed package manager may leave a lock behind; removing it is the
# documented recovery step, then the install must complete normally.
docker exec "$power" sh -c 'rm -f /lib/apk/db/lock /usr/lib/opkg/lock' >/dev/null 2>&1 || true
install_until_version "$power" "$R9" 2.6.0-r9 retry.log || true
retry_ver="$(version_in "$power")"
if [ "$retry_ver" = "2.6.0-r9" ] && config_preserved "$power" "$before_sha" && status_ok "$power"; then
	pass "power-loss retry reaches r9 with config preserved"
else
	fail "power-loss retry: version=${retry_ver:-<none>} config=$(config_values "$power" 2>/dev/null)"
fi

echo "drill $KIND: $FAILS failure(s)" | tee -a "$OUT/summary.txt"
[ "$FAILS" -eq 0 ]
