#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
export CFIP_PROBE_CAPTURE="$TMP/resolve-args"
cat >"$TMP/bin/curl" <<'CURL'
#!/usr/bin/env bash
resolve=''
while (($#)); do
    case "$1" in
      --resolve) resolve="$2"; shift 2 ;;
      *) shift ;;
    esac
done
printf '%s\n' "$resolve" >>"$CFIP_PROBE_CAPTURE"
printf '200,0.010,0.020,0.030,0.040'
CURL
chmod +x "$TMP/bin/curl"
PATH="$TMP/bin:$PATH"
export PATH
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/observe.sh"
cfip_deadline_remaining(){ printf 60; }
cfip_probe_one 104.16.132.229 www.cloudflare.com ipv4 5 | jq -e '.success and .httpCode==200' >/dev/null
cfip_probe_one 2606:4700::6810:84e5 www.cloudflare.com ipv6 5 | jq -e '.success and .httpCode==200' >/dev/null
expected=$'www.cloudflare.com:443:104.16.132.229\nwww.cloudflare.com:443:[2606:4700::6810:84e5]'
[[ "$(cat "$CFIP_PROBE_CAPTURE")" == "$expected" ]]
echo 'PASS candidate probes pass the selected IPv4/IPv6 address to curl --resolve'
