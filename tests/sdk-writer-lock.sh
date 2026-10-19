#!/usr/bin/env bash
# Execute an actual SDK-produced OpenWrt flock binary on the CI Linux kernel.
# This is target-utility execution, not installed-package/procd/router proof.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${1:?SDK root required}"; OUT="${2:?evidence directory required}"
[[ "$(uname -s)" == Linux ]] || { echo 'UNAVAILABLE: SDK target utility requires Linux'; exit 77; }
mkdir -p "$OUT"
binary=''
for pattern in '*/ipkg-*/flock/usr/bin/util-linux-flock' '*/apk-*/flock/usr/bin/util-linux-flock' '*/.pkgdir/flock/usr/bin/util-linux-flock'; do
    binary="$(find "$SDK/build_dir" -type f -path "$pattern" -print -quit)"
    [[ -z "$binary" ]] || break
done
[[ -n "$binary" ]] || { echo 'missing SDK target flock binary'; exit 1; }
python3 - "$binary" "$OUT/binary.json" <<'PY'
import hashlib,json,struct,sys
from pathlib import Path
p=Path(sys.argv[1]);size=p.stat().st_size
assert 0<size<=16*1024*1024,'unexpected target utility size'
raw=p.read_bytes()
assert raw[:6]==b'\x7fELF\x02\x01' and int.from_bytes(raw[18:20],'little')==62,'not x86_64 little-endian ELF64'
offset=struct.unpack_from('<Q',raw,32)[0];entry_size,count=struct.unpack_from('<HH',raw,54)
assert entry_size>=56 and offset+entry_size*count<=len(raw),'invalid ELF program headers'
dynamic=any(struct.unpack_from('<I',raw,offset+i*entry_size)[0]==3 for i in range(count))
Path(sys.argv[2]).write_text(json.dumps(dict(path=str(p),sha256=hashlib.sha256(raw).hexdigest(),size=size,dynamic=dynamic,architecture='x86_64'))+'\n')
PY
export CFIP_SDK_FLOCK_BIN="$binary" CFIP_SDK_FLOCK_LOADER='' CFIP_SDK_FLOCK_LIBDIRS=''
if jq -e '.dynamic==true' "$OUT/binary.json" >/dev/null; then
    for candidate in "$SDK"/staging_dir/toolchain-*/lib/ld-musl-x86_64.so.1 "$SDK"/staging_dir/target-*/lib/ld-musl-x86_64.so.1 "$SDK"/staging_dir/toolchain-*/lib/libc.so; do
        if [[ -f "$candidate" ]]; then CFIP_SDK_FLOCK_LOADER="$candidate"; break; fi
    done
    [[ -n "$CFIP_SDK_FLOCK_LOADER" ]] || { echo 'missing SDK musl loader'; exit 1; }
    CFIP_SDK_FLOCK_LIBDIRS="${CFIP_SDK_FLOCK_LOADER%/*}"
    for lib in "$SDK"/staging_dir/target-*/usr/lib "$SDK"/staging_dir/target-*/lib; do
        [[ ! -d "$lib" ]] || CFIP_SDK_FLOCK_LIBDIRS="$CFIP_SDK_FLOCK_LIBDIRS:$lib"
    done
    "$CFIP_SDK_FLOCK_LOADER" --library-path "$CFIP_SDK_FLOCK_LIBDIRS" --list "$binary" >"$OUT/loader.log"
fi
cat >"$OUT/flock-target" <<'WRAPPER'
#!/bin/sh
if [ -n "$CFIP_SDK_FLOCK_LOADER" ]; then
    exec "$CFIP_SDK_FLOCK_LOADER" --library-path "$CFIP_SDK_FLOCK_LIBDIRS" "$CFIP_SDK_FLOCK_BIN" "$@"
fi
exec "$CFIP_SDK_FLOCK_BIN" "$@"
WRAPPER
chmod +x "$OUT/flock-target"
CFIP_FLOCK="$OUT/flock-target" python3 "$ROOT/tests/writer-lock-recovery.py" >"$OUT/cases.json"
jq -e '.status=="PASS" and (.failures|length)==0' "$OUT/cases.json" >/dev/null
jq -n --slurpfile binary "$OUT/binary.json" --slurpfile cases "$OUT/cases.json" \
    --arg commit "${QUALIFICATION_HEAD_SHA:-${GITHUB_SHA:-unknown}}" --arg runId "${GITHUB_RUN_ID:-unknown}" --arg attempt "${GITHUB_RUN_ATTEMPT:-unknown}" \
    '{schemaVersion:1,status:"PASS",scope:"SDK-produced OpenWrt target flock on CI Linux kernel",commit:$commit,runId:$runId,runAttempt:$attempt,binary:$binary[0],cases:$cases[0],installedPackage:"NOT EVALUATED",nativeProcdRpcdLuci:"NOT EVALUATED"}' >"$OUT/receipt.json"
echo 'PASS SDK target flock executes writer-lock recovery and fault matrix'
