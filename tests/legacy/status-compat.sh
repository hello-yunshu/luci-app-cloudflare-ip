#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_helpers.sh"
grep -Fq 'running:' "$PKG/root/usr/bin/cf-ip-auto-v2"
grep -Fq 'active_run:' "$PKG/root/usr/bin/cf-ip-auto-v2"
grep -Fq 'env:({tar:' "$PKG/root/usr/bin/cf-ip-auto-v2"
echo 'legacy status compatibility contract passed'
