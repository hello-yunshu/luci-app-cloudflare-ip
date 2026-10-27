#!/usr/bin/env bash
# Read-only APK metadata through the native tool, or a fixed Linux tool image.
set -euo pipefail
if command -v apk >/dev/null 2>&1; then exec apk "$@"; fi
args=("$@"); last=$((${#args[@]} - 1))
file="${args[last]}"
dir="$(cd "$(dirname "$file")" && pwd)"
args[last]="/packages/$(basename "$file")"
offline=()
if [[ "${CFIP_APK_OFFLINE:-0}" == 1 ]]; then offline=(--pull never --network none); fi
exec docker run --rm "${offline[@]}" -v "$dir:/packages:ro" alpine:3.23 apk "${args[@]}"
