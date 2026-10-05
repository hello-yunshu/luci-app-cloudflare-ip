#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
python3 - "$ROOT" "$TMP" <<'PY'
import hashlib, io, json, pathlib, subprocess, sys, tarfile
root, tmp=pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]); helper=root/"scripts/openwrt-package-metadata.py"
control=b"Package: luci-app-cloudflare-ip\nVersion: 2.6.0-4\nArchitecture: all\n"
buf=io.BytesIO()
with tarfile.open(fileobj=buf,mode="w:gz") as tar:
 info=tarfile.TarInfo("./control"); info.size=len(control); tar.addfile(info,io.BytesIO(control))
payload=buf.getvalue(); ipk=tmp/"luci-app-cloudflare-ip_2.6.0-4_all.ipk"
def member(name,data):
 n=(name+"/").encode().ljust(16,b" "); header=n+b"0".ljust(12)+b"0".ljust(6)+b"0".ljust(6)+b"100644".ljust(8)+str(len(data)).encode().ljust(10)+b"`\n"
 return header+data+(b"\n" if len(data)%2 else b"")
ipk.write_bytes(b"!<arch>\n"+member("debian-binary",b"2.0\n")+member("control.tar.gz",payload))
result=json.loads(subprocess.check_output([sys.executable,str(helper),str(ipk),"--format","ipk","--package-name","luci-app-cloudflare-ip"],text=True))
assert result["package"]=={"name":"luci-app-cloudflare-ip","version":"2.6.0","release":4,"architecture":"all","format":"ipk","packageVersion":"2.6.0-4"}
assert result["sha256"]==hashlib.sha256(ipk.read_bytes()).hexdigest() and result["size"]==ipk.stat().st_size
apk=tmp/"luci-app-cloudflare-ip-2.6.0-r4.apk"; apk.write_bytes(b"apk payload")
apkbin=tmp/"apk"; apkbin.write_text("#!/usr/bin/env python3\nimport json\nprint(json.dumps({'packages':[{'name':'luci-app-cloudflare-ip','version':'2.6.0-r4','architecture':'all'}]}))\n")
apkbin.chmod(0o755)
result=json.loads(subprocess.check_output([sys.executable,str(helper),str(apk),"--format","apk","--apk-bin",str(apkbin),"--package-name","luci-app-cloudflare-ip"],text=True))
assert result["package"]["packageVersion"]=="2.6.0-r4" and result["package"]["release"]==4
print("IPK control and APK adbdump metadata are extracted and byte-bound")
PY
