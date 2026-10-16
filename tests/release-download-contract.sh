#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE="$ROOT/.github/workflows/release.yml"
grep -Fq 'outputs.ipk_name' "$RELEASE"
grep -Fq 'outputs.apk_name' "$RELEASE"
if grep -Eq 'Cloudflare IP [0-9]|用户：[0-9]' "$RELEASE"; then exit 1; fi
for text in 'OpenWrt 24.10.x' 'OpenWrt 25.12+' 'Rill integration is included in the main package' 'Runtime is optional' 'Compatibility package' 'New users do not need to download this package manually' 'rill-openwrt-packages/releases'; do
 grep -Fq "$text" "$RELEASE"
done
for file in README.md README.en.md; do
 grep -Fq 'scripts/package_identity.py' "$ROOT/$file"
 grep -Fq 'qualification.json' "$ROOT/$file"
 grep -Fq 'luci-app-cloudflare-ip_*.ipk' "$ROOT/$file"
 grep -Fq 'luci-app-cloudflare-ip-*.apk' "$ROOT/$file"
done
grep -Fq '不要同时安装 IPK 和 APK' "$ROOT/README.md"
grep -Fq 'Do not install both IPK and APK' "$ROOT/README.en.md"
echo 'Download guidance derives from source authority and qualified asset names'
