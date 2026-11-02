#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAKEFILE="$ROOT/package/luci-app-cloudflare-ip/Makefile"
base_package="$(awk '/^define Package\/luci-app-cloudflare-ip$/{inside=1} inside{print} inside && /^endef$/{exit}' "$MAKEFILE")"
base_install="$(awk '/^define Package\/luci-app-cloudflare-ip\/install$/{inside=1} inside{print} inside && /^endef$/{exit}' "$MAKEFILE")"

python3 -B "$ROOT/scripts/package_identity.py" >/dev/null
! grep -Fq 'REPLACES:=luci-app-cloudflare-ip-rill' <<<"$base_package"
grep -Fq 'candidate-rill.sh' <<<"$base_install"
grep -Fq 'candidate-rill-feature-schema-v2.json' <<<"$base_install"
! grep -Eq '(^|[[:space:]])\+rill-runtime-preview([[:space:]]|$)' <<<"$base_package"

echo 'Current base uses collision-free Candidate Rill paths; historical migration pins are independent'
