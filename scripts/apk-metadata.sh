#!/usr/bin/env bash
# Read-only APK metadata through the native tool, or a fixed Linux tool image.
set -euo pipefail
if command -v apk >/dev/null 2>&1; then exec apk "$@"; fi
args=("$@"); last=$((${#args[@]} - 1))
file="${args[last]}"
dir="$(cd "$(dirname "$file")" && pwd)"
args[last]="/packages/$(basename "$file")"
if [[ "${CFIP_APK_OFFLINE:-0}" == 1 ]]; then
    exec docker run --rm --pull never --network none -v "$dir:/packages:ro" alpine:3.23 apk "${args[@]}"
fi
exec docker run --rm -v "$dir:/packages:ro" alpine:3.23 apk "${args[@]}"
