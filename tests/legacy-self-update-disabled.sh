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
printf 'PASS legacy self-update is disabled without a network fetch\n'
