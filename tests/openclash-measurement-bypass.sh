#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/runtime"
cat >"$TMP/openclash.yaml" <<'YAML'
external-controller: 127.0.0.1:9090
tun:
  enable: true
YAML
printf '%s\n' '104.16.132.229' '2606:4700::6810:84e5' >"$TMP/candidates.txt"
printf '%s\n' '#!/bin/sh' 'exec "$@"' >"$TMP/probe-exec"
chmod +x "$TMP/probe-exec"

source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/openclash-bypass.sh"
CFIP_LIB_DIR="$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip"
CFIP_OPENCLASH_RUNTIME_CONFIG="$TMP/openclash.yaml"
CFIP_CANDIDATE_INPUT_FILE="$TMP/candidates.txt"
CFIP_PROBE_EXEC="$TMP/probe-exec"
CFIP_MODE=openclash CFIP_OPENCLASH_EXPECTED_ENABLED=1 CFIP_OPENCLASH_INITIAL_HEALTHY=true CFIP_RUN_ID=testbypass
cfip_ip_family() { case "$1" in *:*) printf ipv6 ;; *.*) printf ipv4 ;; *) return 1 ;; esac; }
cfip_openclash_runtime_unchanged() { return 0; }
cfip_monotonic_seconds() { printf 100; }
id() {
	case "$1:$2" in
		-u:nobody) printf 65534 ;;
		-g:daemon) printf 1 ;;
		*) return 1 ;;
	esac
}

NFTPRESENT=true
SET4=false SET6=false RULE4=false RULE6=false RULE4NAT=false RULE6NAT=false
NFT_BATCH=""
nft() {
	case "$*" in
		'list table inet fw4') $NFTPRESENT ;;
		'-a list chain inet fw4 mangle_output')
			printf 'chain mangle_output { type route hook output priority mangle; jump openclash_mangle_output; jump openclash_mangle_output_v6; }\n'
			true
			;;
		'-a list chain inet fw4 nat_output')
			printf 'chain nat_output { type nat hook output priority -1; jump openclash_output; jump openclash_output_v6; }\n'
			true
			;;
		'-a list chain inet fw4 openclash_mangle_output')
			printf 'chain openclash_mangle_output {\n'
			[ "$RULE4" = true ] && printf 'meta skuid 65534 ip daddr . tcp dport @%s return comment "%s" # handle 10\n' "$CFIP_OPENCLASH_BYPASS_SET_V4" "$CFIP_OPENCLASH_BYPASS_COMMENT"
			printf 'ip daddr @localnetwork return\nmeta mark set 0x162\n}\n'
			true
			;;
		'-a list chain inet fw4 openclash_mangle_output_v6')
			printf 'chain openclash_mangle_output_v6 {\n'
			[ "$RULE6" = true ] && printf 'meta skuid 65534 ip6 daddr . tcp dport @%s return comment "%s" # handle 11\n' "$CFIP_OPENCLASH_BYPASS_SET_V6" "$CFIP_OPENCLASH_BYPASS_COMMENT"
			printf 'ip6 daddr @localnetwork_v6 return\nmeta mark set 0x162\n}\n'
			true
			;;
		'-a list chain inet fw4 openclash_output')
			printf 'chain openclash_output {\n'
			[ "$RULE4NAT" = true ] && printf 'meta skuid 65534 ip daddr . tcp dport @%s return comment "%s" # handle 12\n' "$CFIP_OPENCLASH_BYPASS_SET_V4" "$CFIP_OPENCLASH_BYPASS_COMMENT"
			printf 'ip daddr @localnetwork return\ntcp dport 443 redirect to :7892\n}\n'
			true
			;;
		'-a list chain inet fw4 openclash_output_v6')
			printf 'chain openclash_output_v6 {\n'
			[ "$RULE6NAT" = true ] && printf 'meta skuid 65534 ip6 daddr . tcp dport @%s return comment "%s" # handle 13\n' "$CFIP_OPENCLASH_BYPASS_SET_V6" "$CFIP_OPENCLASH_BYPASS_COMMENT"
			printf 'ip6 daddr @localnetwork6 return\ntcp dport 443 redirect to :7892\n}\n'
			true
			;;
		'list chain inet fw4 openclash_mangle_output')
			printf 'chain openclash_mangle_output {\n'
			[ "$RULE4" = true ] && printf 'meta skuid 65534 ip daddr . tcp dport @%s return comment "%s" # handle 10\n' "$CFIP_OPENCLASH_BYPASS_SET_V4" "$CFIP_OPENCLASH_BYPASS_COMMENT"
			printf 'ip daddr @localnetwork return\nmeta mark set 0x162\n}\n'
			true
			;;
		'list chain inet fw4 openclash_mangle_output_v6')
			printf 'chain openclash_mangle_output_v6 {\n'
			[ "$RULE6" = true ] && printf 'meta skuid 65534 ip6 daddr . tcp dport @%s return comment "%s" # handle 11\n' "$CFIP_OPENCLASH_BYPASS_SET_V6" "$CFIP_OPENCLASH_BYPASS_COMMENT"
			printf 'ip6 daddr @localnetwork_v6 return\nmeta mark set 0x162\n}\n'
			true
			;;
		'list chain inet fw4 openclash_output')
			printf 'chain openclash_output {\n'
			[ "$RULE4NAT" = true ] && printf 'meta skuid 65534 ip daddr . tcp dport @%s return comment "%s" # handle 12\n' "$CFIP_OPENCLASH_BYPASS_SET_V4" "$CFIP_OPENCLASH_BYPASS_COMMENT"
			printf 'ip daddr @localnetwork return\ntcp dport 443 redirect to :7892\n}\n'
			true
			;;
		'list chain inet fw4 openclash_output_v6')
			printf 'chain openclash_output_v6 {\n'
			[ "$RULE6NAT" = true ] && printf 'meta skuid 65534 ip6 daddr . tcp dport @%s return comment "%s" # handle 13\n' "$CFIP_OPENCLASH_BYPASS_SET_V6" "$CFIP_OPENCLASH_BYPASS_COMMENT"
			printf 'ip6 daddr @localnetwork6 return\ntcp dport 443 redirect to :7892\n}\n'
			true
			;;
		'list set inet fw4 cfip_'*'_v4')
			[ "$SET4" = true ] || return 1
			printf 'set %s { elements = { 104.16.132.229 . 443 timeout 4m } }\n' "${*: -1}"
			;;
		'list set inet fw4 cfip_'*'_v6')
			[ "$SET6" = true ] || return 1
			printf 'set %s { elements = { 2606:4700::6810:84e5 . 443 timeout 4m } }\n' "${*: -1}"
			;;
		'-c -f '*) NFT_BATCH="$(cat "$3")"; return 0 ;;
		'-f '*)
			NFT_BATCH="$(cat "$2")"
			case "$NFT_BATCH" in *'cfip_'*'_v4'*) SET4=true; RULE4=true; RULE4NAT=true ;; esac
			case "$NFT_BATCH" in *'cfip_'*'_v6'*) SET6=true; RULE6=true; RULE6NAT=true ;; esac
			;;
		'delete rule inet fw4 openclash_mangle_output handle 10') RULE4=false ;;
		'delete rule inet fw4 openclash_mangle_output_v6 handle 11') RULE6=false ;;
		'delete rule inet fw4 openclash_output handle 12') RULE4NAT=false ;;
		'delete rule inet fw4 openclash_output_v6 handle 13') RULE6NAT=false ;;
		'delete set inet fw4 '*_v4) SET4=false ;;
		'delete set inet fw4 '*_v6) SET6=false ;;
		*) return 1 ;;
	esac
}
start-stop-daemon() {
	[ "$1" = -S ] && [ "$2" = -c ] && [ "$3" = nobody:daemon ] && [ "$4" = -x ] && [ "$6" = -- ] || return 90
	shift 6
	"$CFIP_PROBE_EXEC" "$@"
}
export -f nft start-stop-daemon id

cfip_openclash_measurement_bypass_begin
[[ "$CFIP_OPENCLASH_BYPASS_ACTIVE" == true ]]
[[ "$CFIP_OPENCLASH_BYPASS_UID" == 65534 ]]
[[ "$CFIP_OPENCLASH_BYPASS_CHAIN_V4" == 'openclash_mangle_output openclash_output' ]]
[[ "$CFIP_OPENCLASH_BYPASS_CHAIN_V6" == 'openclash_mangle_output_v6 openclash_output_v6' ]]
[[ "$NFT_BATCH" == *'meta skuid 65534 ip daddr . tcp dport @cfip_testbypass_v4 return'* ]]
[[ "$NFT_BATCH" == *'meta skuid 65534 ip6 daddr . tcp dport @cfip_testbypass_v6 return'* ]]
[[ "$NFT_BATCH" == *'104.16.132.229 . 443 timeout 300s'* ]]
[[ "$NFT_BATCH" == *'2606:4700::6810:84e5 . 443 timeout 300s'* ]]
[[ "$(cfip_openclash_measurement_command /bin/echo isolated)" == isolated ]]
cfip_openclash_measurement_bypass_end
[[ "$CFIP_OPENCLASH_BYPASS_ACTIVE" == false && "$RULE4" == false && "$RULE6" == false && "$RULE4NAT" == false && "$RULE6NAT" == false && "$SET4" == false && "$SET6" == false ]]

cfip_openclash_measurement_bypass_begin
RULE4=false
if cfip_openclash_measurement_bypass_end; then echo 'FAIL: bypass loss was not detected' >&2; exit 1; fi
[[ "$CFIP_OPENCLASH_BYPASS_ACTIVE" == false ]]

CFIP_SPEEDTEST_PROTOCOL=http
cfip_openclash_measurement_bypass_begin
[[ "$CFIP_OPENCLASH_BYPASS_ACTIVE" == true ]]
[[ "$NFT_BATCH" == *'meta skuid 65534 ip daddr . tcp dport @cfip_testbypass_v4 return'* ]]
cfip_openclash_measurement_bypass_end

CFIP_SPEEDTEST_PROTOCOL=udp
if cfip_openclash_measurement_bypass_begin; then echo 'FAIL: unsupported measurement protocol was incorrectly exempted' >&2; exit 1; fi
[[ "$CFIP_OPENCLASH_BYPASS_ACTIVE" == false && "$CFIP_OPENCLASH_BYPASS_ERROR" == *'only for TCPing or HTTPS HTTPing on TCP/443'* ]]

echo 'PASS: temporary CFI exception is UID/address/port scoped, supports TCPing and HTTPS HTTPing, handles v4/v6 output chains, and rejects lost rules'
