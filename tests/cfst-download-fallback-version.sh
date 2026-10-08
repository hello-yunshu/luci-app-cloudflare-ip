#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
source "$ROOT/package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-legacy"
WORK_DIR="$TMP/work"; CFST_DIR="$WORK_DIR/cfst"; mkdir -p "$CFST_DIR"
RELEASE_API='https://example.test/release.json'; RELEASE_DOWNLOAD_BASE='https://example.test/releases'
ARCHIVE="$CFST_DIR/cfst_linux_test.tar.gz"
make_archive() {
    local version="$1" dir; dir="$TMP/$version"
    mkdir -p "$dir"
    cat >"$dir/cfst" <<EOF_BIN
#!/bin/sh
echo '$version'
EOF_BIN
    chmod +x "$dir/cfst"
    tar -czf "$TMP/$version.tar.gz" -C "$dir" cfst
}
make_archive v1
make_archive v2
cp "$TMP/v1.tar.gz" "$ARCHIVE"
digest_v1="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
version='v1'; source='https://example.test/v1/cfst_linux_test.tar.gz'; sha256="$digest_v1"; export version source sha256
jq -cn --arg version "$version" --arg source "$source" --arg sha256 "$sha256" '{schemaVersion:1,version:$version,source:$source,sha256:$sha256}' >"$ARCHIVE.meta"
install_cached_speedtest_archive "$ARCHIVE"
RELEASE_JSON="$(jq -cn --arg digest "sha256:$(sha256sum "$TMP/v2.tar.gz" | awk '{print $1}')" '{tag_name:"v2",assets:[{name:"cfst_linux_test.tar.gz",browser_download_url:"https://example.test/v2/cfst_linux_test.tar.gz",digest:$digest}]}')"
FAIL_ASSET=true
curl_fetch() {
    local output="$1" url="$2"
    if [[ "$url" == "$RELEASE_API" ]]; then printf '%s' "$RELEASE_JSON" >"$output"; return 0; fi
    [[ "$FAIL_ASSET" == false ]] || return 1
    cp "$TMP/v2.tar.gz" "$output"
}
need_cmd() { :; }
ensure_jq() { :; }
detect_arch_tag() { printf test; }
log() { :; }
download_speedtest
[[ "$(cat "$CFST_DIR/cfst_version.txt")" == v1 ]]
[[ "$("$CFST_DIR/cfst")" == v1 ]]
[[ "$(jq -r '.version' "$ARCHIVE.meta")" == v1 ]]
FAIL_ASSET=false
download_speedtest
[[ "$(cat "$CFST_DIR/cfst_version.txt")" == v2 ]]
[[ "$("$CFST_DIR/cfst")" == v2 ]]
[[ "$(jq -r '.version' "$ARCHIVE.meta")" == v2 ]]
[[ "$(jq -r '.sha256' "$ARCHIVE.meta")" == "$(sha256sum "$ARCHIVE" | awk '{print $1}')" ]]
echo 'CFST fallback preserves cached version and retries latest install when download recovers'