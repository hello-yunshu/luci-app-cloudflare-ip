#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LEGACY="$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-legacy"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cfip-legacy-update.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin"
cat >"$TMP/bin/curl" <<'EOF'
#!/bin/sh
printf 'curl-called\n' >>"$CFIP_TEST_CURL_MARKER"
exit 0
EOF
cat >"$TMP/bin/uci" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$TMP/bin/curl" "$TMP/bin/uci"
export CFIP_TEST_CURL_MARKER="$TMP/curl.marker"

output="$(PATH="$TMP/bin:$PATH" bash "$LEGACY" --self-update 2>&1 || true)"
printf '%s\n' "$output" | grep -q 'legacy self-update is disabled' ||
	{ printf 'FAIL self-update did not report disabled: %s\n' "$output" >&2; exit 1; }
[[ ! -e "$CFIP_TEST_CURL_MARKER" ]] ||
	{ printf 'FAIL self-update attempted a network fetch\n' >&2; exit 1; }
printf '%s\n' "$output" | grep -q '"success":false' ||
	{ printf 'FAIL self-update did not return an honest failure\n' >&2; exit 1; }

# The automatic run path calls self_update() directly. Prove that a legacy
# configuration with auto_update=1 and an external URL still performs no fetch.
cat >"$TMP/bin/uci" <<EOF
#!/bin/sh
case "\$3" in
  cf_ip.main.enabled) printf '%s\n' 1 ;;
  cf_ip.main.mode) printf '%s\n' passwall ;;
  cf_ip.main.ip_count) printf '%s\n' 1 ;;
  cf_ip.main.ip_type) printf '%s\n' ipv4 ;;
  cf_ip.main.speedtest_protocol) printf '%s\n' tcp ;;
  cf_ip.main.stop_service) printf '%s\n' 0 ;;
  cf_ip.main.startup_delay) printf '%s\n' '' ;;
  cf_ip.main.auto_update) printf '%s\n' 1 ;;
  cf_ip.main.self_update_url) printf '%s\n' 'https://legacy.example/update.sh' ;;
  cf_ip.main.download_retries) printf '%s\n' 3 ;;
  cf_ip.main.download_retry_delay) printf '%s\n' 5 ;;
  cf_ip.main.verbose) printf '%s\n' 0 ;;
  cf_ip.main.work_dir) printf '%s\n' '$TMP/blocked/work' ;;
  cf_ip.main.cron_interval) printf '%s\n' 6h ;;
  cf_ip.passwall.target_domain) printf '%s\n' example.com ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMP/bin/uci"
: >"$TMP/blocked"
output="$(PATH="$TMP/bin:$PATH" bash "$LEGACY" -v 2>&1 || true)"
printf '%s\n' "$output" | grep -q 'self-update disabled' ||
	{ printf 'FAIL automatic run did not reach disabled self_update\n%s\n' "$output" >&2; exit 1; }
[[ ! -e "$CFIP_TEST_CURL_MARKER" ]] ||
	{ printf 'FAIL automatic run fetched a self-update URL\n' >&2; exit 1; }
printf 'PASS legacy self-update is disabled without a network fetch\n'
