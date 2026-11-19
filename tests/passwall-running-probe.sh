#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/init" "$TMP/bin" "$TMP/passwall-runtime/bin"

# A non-procd rc.common service may print usage and return 0 for `running`.
cat >"$TMP/init/passwall" <<'EOF_INIT'
#!/usr/bin/env bash
echo "Usage: $0 start|stop" >&2
exit 0
EOF_INIT
chmod +x "$TMP/init/passwall"

# Stub BusyBox pgrep so both match/no-match states are deterministic.
cat >"$TMP/bin/busybox" <<'EOF_BUSYBOX'
#!/usr/bin/env bash
[[ "$1" == pgrep && "$2" == -f && "$3" == "$CFIP_TEST_PROCESS_DIR" ]] || exit 2
[[ "${CFIP_TEST_PROCESS_PRESENT:-false}" == true ]]
EOF_BUSYBOX
chmod +x "$TMP/bin/busybox"

source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh"
export PATH="$TMP/bin:$PATH" CFIP_INIT_DIR="$TMP/init"
export CFIP_TEST_PROCESS_DIR="$TMP/passwall-runtime/bin"
export INIT_DIR="$TMP/init"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-legacy"

if cfip_service_running passwall; then
    echo 'init script usage success was mistaken for a running PassWall process' >&2
    exit 1
fi
if passwall_process_running "$CFIP_TEST_PROCESS_DIR"; then
    echo 'legacy probe mistook init script usage success for a running PassWall process' >&2
    exit 1
fi

export CFIP_TEST_PROCESS_PRESENT=true
cfip_passwall_process_running "$CFIP_TEST_PROCESS_DIR" || {
    echo 'PassWall process marker was not recognized' >&2
    exit 1
}
passwall_process_running "$CFIP_TEST_PROCESS_DIR" || {
    echo 'legacy probe did not recognize a matching PassWall runtime process' >&2
    exit 1
}

echo 'PassWall runtime process probe contract passed'
