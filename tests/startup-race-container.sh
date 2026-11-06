#!/bin/sh
# Prepare the disposable OpenWrt root and run the startup-race behaviour test.
# Executed inside the container; the repository is mounted at /src.
set -e
mkdir -p /var/lock
for _ in 1 2 3; do
	opkg update >/tmp/opkg-update.log 2>&1 || true
	opkg install bash jq curl flock >/tmp/opkg-deps.log 2>&1 || true
	ok=1
	for b in bash jq curl flock; do command -v "$b" >/dev/null || ok=0; done
	[ "$ok" = 1 ] && break
	sleep 2
done
for b in bash jq curl flock; do
	command -v "$b" >/dev/null || { echo "missing dependency: $b" >&2; exit 1; }
done
exec bash /src/tests/startup-race.sh
