#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE="$ROOT/.github/workflows/release.yml"

grep -Fq 'OpenWrt 24.10.x' "$RELEASE"
grep -Fq 'OpenWrt 25.12+' "$RELEASE"
grep -Fq 'luci-app-cloudflare-ip_${{ needs.check-qualification.outputs.version }}-r${{ needs.check-qualification.outputs.release }}_all.ipk' "$RELEASE"
grep -Fq 'luci-app-cloudflare-ip-${{ needs.check-qualification.outputs.version }}-r${{ needs.check-qualification.outputs.release }}.apk' "$RELEASE"
grep -Fq 'Rill integration is included in the main package' "$RELEASE"
grep -Fq 'Runtime is optional' "$RELEASE"
grep -Fq 'Compatibility package' "$RELEASE"
grep -Fq 'New users do not need to download this package manually' "$RELEASE"
grep -Fq 'rill-openwrt-packages/releases' "$RELEASE"

grep -Fq '不要同时安装 IPK 和 APK' "$ROOT/README.md"
grep -Fq 'Rill 集成代码已经包含在主包中' "$ROOT/README.md"
grep -Fq '不包含 Rill Runtime binary' "$ROOT/README.md"
grep -Fq 'Do not install both IPK and APK' "$ROOT/README.en.md"
grep -Fq 'Rill integration is included in the main package' "$ROOT/README.en.md"
grep -Fq 'does not include the Rill Runtime binary' "$ROOT/README.en.md"

echo 'Release and README download guidance contract passed'
