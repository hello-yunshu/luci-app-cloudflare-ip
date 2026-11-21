#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/work/cfst" "$TMP/runtime" "$TMP/status" "$TMP/worker"

cat >"$TMP/probe-exec" <<'EOF_PROBE'
#!/bin/sh
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
exec "$@"
EOF_PROBE

cat >"$TMP/bin/start-stop-daemon" <<'EOF_SSD'
#!/bin/sh
[ "$1" = -S ] && [ "$2" = -c ] && [ "$3" = nobody:daemon ] && [ "$4" = -x ] && [ "$6" = -- ] || exit 90
probe_exec="$5"
shift 6
exec "$probe_exec" "$@"
EOF_SSD

cat >"$TMP/work/cfst/cfst" <<'EOF_CFST'
#!/bin/sh
input=''
output=''
httping=false
while [ "$#" -gt 0 ]; do
	case "$1" in
		-f) input="$2"; shift 2 ;;
		-o) output="$2"; shift 2 ;;
		-httping) httping=true; shift ;;
		*) shift ;;
	esac
done
[ -s "$input" ] && [ -n "$output" ] || exit 91
printf '%s\n' "$httping" >>"${CFIP_TEST_INVOCATIONS:?}"
{
	printf '%s\n' 'IP 地址,已发送,已接收,丢包率,平均延迟,下载速度(MB/s),地区码'
	while IFS= read -r ip; do
		[ -n "$ip" ] || continue
		printf '%s,1,1,0.00,120.00,1.25,NRT\n' "$ip"
	done <"$input"
} >"$output"
EOF_CFST
chmod 755 "$TMP/probe-exec" "$TMP/bin/start-stop-daemon" "$TMP/work/cfst/cfst"
printf '%s\n' 104.16.132.229 >"$TMP/worker/input.txt"
chmod 600 "$TMP/worker/input.txt"

export CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
export CFIP_PROBE_EXEC="$TMP/probe-exec"
export CFIP_RUNTIME_DIR="$TMP/runtime"
export CFIP_STATUS_DIR="$TMP/status"
export CFIP_LOG_FILE="$TMP/cfi.log"
export CFIP_TEST_INVOCATIONS="$TMP/invocations"
export PATH="$TMP/bin:$PATH"
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2"

CFIP_WORK_DIR="$TMP/work"
CFIP_MODE=openclash
CFIP_OPENCLASH_BYPASS_ACTIVE=true
CFIP_OPENCLASH_BYPASS_USER=nobody
CFIP_OPENCLASH_BYPASS_GROUP=daemon
CFIP_OPENCLASH_BYPASS_UID=65534
CFIP_OPENCLASH_BYPASS_GID=1
CFIP_CANDIDATE_INPUT_FILE="$TMP/worker/input.txt"
CFIP_CANDIDATES_FILE="$TMP/worker/parsed.json"
CFIP_RUN_ID=cfst-bypass-test
CFIP_SPEEDTEST_THREADS=1
CFIP_SPEEDTEST_PING_COUNT=1
CFIP_SPEEDTEST_DN=1
CFIP_SPEEDTEST_DT=6
CFIP_SPEEDTEST_TLL=0
CFIP_SPEEDTEST_TL=
CFIP_SPEEDTEST_CFCOLO=NRT
CFIP_PROBE_TOP_COUNT=1
CFIP_RUNTIME_DIR="$TMP/runtime"
CFIP_MEASUREMENT_STARTED_AT=1
CFIP_MEASUREMENT_DEADLINE=100

cfip_deadline_remaining() { printf '30'; }
chown() { return 0; }
cfip_openclash_measurement_bypass_assert() { return 0; }
cfip_run_with_timeout() {
	local limit="$1"
	shift
	[[ "$limit" == 30 && "$1" == start-stop-daemon ]] || {
		echo "FAIL: bounded CFST runner did not receive an executable start-stop-daemon command" >&2
		return 92
	}
	"$@"
}

for protocol in tcp http; do
	CFIP_SPEEDTEST_PROTOCOL="$protocol"
	rm -f "$CFIP_CANDIDATES_FILE"
	run_cfst
	jq -e --arg protocol "$protocol" 'length==1 and .[0].ip=="104.16.132.229" and .[0].testProtocol==$protocol' "$CFIP_CANDIDATES_FILE" >/dev/null
done

[[ "$(cat "$TMP/invocations")" == $'false\ntrue' ]]
echo 'PASS: full CFST runs through a bounded external probe command in TCPing and HTTPing modes'
