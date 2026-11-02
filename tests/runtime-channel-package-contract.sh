#!/usr/bin/env bash
# Verify the package-owned Runtime channel marker in real package bytes.
set -euo pipefail
PACKAGE="${1:?package path required}"
KIND="${2:?ipk or apk required}"
CHANNEL="${3:?stable or preview required}"
case "$KIND" in ipk|apk) ;; *) echo "unsupported package kind: $KIND" >&2; exit 2 ;; esac
case "$CHANNEL" in stable|preview) ;; *) echo "unsupported channel: $CHANNEL" >&2; exit 2 ;; esac
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
DATA="$TMP/data"; mkdir -p "$DATA"
case "$KIND" in
  ipk)
    member="$(tar -tf "$PACKAGE" | sed 's#^\./##' | grep -E '^data\.tar(\.(gz|zst))?$' | head -n1)"
    test -n "$member" || { echo 'missing data.tar member in IPK' >&2; exit 1; }
    tar -xf "$PACKAGE" -C "$TMP" "./$member"
    case "$member" in
      *.zst) tar --zstd -xf "$TMP/$member" -C "$DATA" ;;
      *.gz) tar -xzf "$TMP/$member" -C "$DATA" ;;
      *) tar -xf "$TMP/$member" -C "$DATA" ;;
    esac
    ;;
  apk)
    "${APK:-apk}" --allow-untrusted extract --destination "$DATA" "$PACKAGE" >/dev/null
    ;;
esac
test -x "$DATA/usr/bin/rill-runtime" || { echo 'runtime binary missing from package' >&2; exit 1; }
marker="$DATA/usr/share/rill/runtime-channel"
test -f "$marker" || { echo 'runtime channel marker missing from package' >&2; exit 1; }
value="$(head -n 1 "$marker" | sed 's/[[:space:]]//g')"
test "$value" = "$CHANNEL" || { echo "runtime channel marker is '$value', expected '$CHANNEL'" >&2; exit 1; }
echo "PASS runtime-channel marker '$CHANNEL' inside $(basename "$PACKAGE")"
