#!/usr/bin/env bash
# Prove the documented opkg status backup/restore procedure: a truncated
# /usr/lib/opkg/status (the ENOSPC symptom) is rejected, and restoring the
# pre-upgrade backup makes opkg usable again.
set -euo pipefail
[[ -s /usr/lib/opkg/status ]] || { echo 'UNAVAILABLE: opkg status database required'; exit 77; }
TMP="$(mktemp -d)"
backup="$TMP/status.backup"
cleanup(){
 local rc=$?
 [[ ! -f "$backup" ]] || cp -p "$backup" /usr/lib/opkg/status || true
 rm -rf "$TMP"
 exit "$rc"
}
trap cleanup EXIT

cp -p /usr/lib/opkg/status "$backup"
before_sha="$(sha256sum "$backup" | awk '{print $1}')"
before_count="$(opkg list-installed 2>/dev/null | wc -l)"
[[ "$before_count" -gt 0 ]]
echo "PASS baseline status is readable ($before_count entries)"

size="$(wc -c <"$backup")"
head -c "$((size-32))" "$backup" >"$TMP/truncated"
cat "$TMP/truncated" >/usr/lib/opkg/status
sync
set +e
opkg list-installed >"$TMP/broken.out" 2>"$TMP/broken.err"
broken_rc=$?
set -e
broken_count="$(wc -l <"$TMP/broken.out")"
if [[ $broken_rc -eq 0 && ! -s "$TMP/broken.err" && "$broken_count" -eq "$before_count" ]]; then
 echo 'FAIL truncated status was accepted as valid'
 exit 1
fi
echo "PASS truncated status is rejected (rc=$broken_rc, stderr=$(wc -c <"$TMP/broken.err") bytes)"

cp -p "$backup" /usr/lib/opkg/status.new
sync
mv /usr/lib/opkg/status.new /usr/lib/opkg/status
after_sha="$(sha256sum /usr/lib/opkg/status | awk '{print $1}')"
[[ "$after_sha" == "$before_sha" ]]
opkg list-installed >"$TMP/after.out" 2>"$TMP/after.err"
[[ ! -s "$TMP/after.err" ]]
after_count="$(wc -l <"$TMP/after.out")"
[[ "$after_count" -eq "$before_count" ]]
echo "PASS restored status matches the backup and opkg lists $after_count packages"
