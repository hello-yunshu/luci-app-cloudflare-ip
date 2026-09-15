#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAKEFILE="$ROOT/package/luci-app-cloudflare-ip/Makefile"
base_install="$(awk '/^define Package\/luci-app-cloudflare-ip\/install$/{inside=1} inside{print} inside && /^endef$/{exit}' "$MAKEFILE")"
base_package="$(awk '/^define Package\/luci-app-cloudflare-ip$/{inside=1} inside{print} inside && /^endef$/{exit}' "$MAKEFILE")"

grep -Fq 'rill.sh' <<<"$base_install"
grep -Fq 'rill-feature-schema-v2.json' <<<"$base_install"
grep -Fq 'rill-disabled.sh' <<<"$base_install"
! grep -Eq '(^|[[:space:]])\+rill-runtime-preview([[:space:]]|$)' <<<"$base_package"
grep -Fq 'REPLACES:=luci-app-cloudflare-ip-rill' <<<"$base_package"

echo 'Rill consumer integration is owned by the base package without a Runtime dependency'
