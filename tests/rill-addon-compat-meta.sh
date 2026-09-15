#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAKEFILE="$ROOT/package/luci-app-cloudflare-ip/Makefile"
addon_package="$(awk '/^define Package\/luci-app-cloudflare-ip-rill$/{inside=1} inside{print} inside && /^endef$/{exit}' "$MAKEFILE")"
addon_description="$(awk '/^define Package\/luci-app-cloudflare-ip-rill\/description$/{inside=1} inside{print} inside && /^endef$/{exit}' "$MAKEFILE")"
addon_install="$(awk '/^define Package\/luci-app-cloudflare-ip-rill\/install$/{inside=1} inside{print} inside && /^endef$/{exit}' "$MAKEFILE")"

grep -Fq '+luci-app-cloudflare-ip' <<<"$addon_package"
grep -Fq '+rill-runtime-preview' <<<"$addon_package"
grep -Fq 'Deprecated compatibility package.' <<<"$addon_description"
grep -Fq 'Rill consumer integration is included in luci-app-cloudflare-ip.' <<<"$addon_description"
grep -Fq 'dependency compatibility' <<<"$addon_description"
! grep -Eq 'INSTALL_(BIN|DATA|CONF|DIR)' <<<"$addon_install"

echo 'Rill addon remains a dependency-preserving compatibility meta package'
