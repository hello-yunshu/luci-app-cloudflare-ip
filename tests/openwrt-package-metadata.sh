#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
python3 - "$ROOT" "$TMP" <<'PY'
import hashlib, io, json, pathlib, subprocess, sys, tarfile
root, tmp=pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]); helper=root/"scripts/openwrt-package-metadata.py"
sys.path.insert(0,str(root/"scripts"))
from package_identity import source
identity=source(); version=identity["version"]; release=identity["release"]; raw=identity["packageVersion"]
# Synthetic container/parser fixtures only. Real SDK coverage is separate.
control=f"Package: luci-app-cloudflare-ip\nVersion: {raw}\nArchitecture: all\n".encode()
buf=io.BytesIO()
with tarfile.open(fileobj=buf,mode="w:gz") as tar:
 info=tarfile.TarInfo("./control"); info.size=len(control); tar.addfile(info,io.BytesIO(control))
payload=buf.getvalue(); ipk=tmp/f"luci-app-cloudflare-ip_{raw}_all.ipk"
outer=io.BytesIO()
with tarfile.open(fileobj=outer,mode="w:gz") as tar:
 for name,data in (("./debian-binary",b"2.0\n"),("./control.tar.gz",payload),("./data.tar.gz",b"data")):
  info=tarfile.TarInfo(name); info.size=len(data); tar.addfile(info,io.BytesIO(data))
ipk.write_bytes(outer.getvalue())
result=json.loads(subprocess.check_output([sys.executable,str(helper),str(ipk),"--format","ipk","--package-name","luci-app-cloudflare-ip"],text=True))
assert result["package"]=={"name":"luci-app-cloudflare-ip","version":version,"release":release,"architecture":"all","format":"ipk","packageVersion":raw}
assert result["sha256"]==hashlib.sha256(ipk.read_bytes()).hexdigest() and result["size"]==ipk.stat().st_size
legacy_ipk=tmp/"legacy.ipk"
def member(name,data):
 n=(name+"/").encode().ljust(16,b" "); header=n+b"0".ljust(12)+b"0".ljust(6)+b"0".ljust(6)+b"100644".ljust(8)+str(len(data)).encode().ljust(10)+b"`\n"
 return header+data+(b"\n" if len(data)%2 else b"")
legacy_ipk.write_bytes(b"!<arch>\n"+member("debian-binary",b"2.0\n")+member("control.tar.gz",payload))
legacy=json.loads(subprocess.check_output([sys.executable,str(helper),str(legacy_ipk),"--format","ipk","--package-name","luci-app-cloudflare-ip"],text=True))
assert legacy["package"]==result["package"]
apk=tmp/f"luci-app-cloudflare-ip-{raw}.apk"; apk.write_bytes(b"apk payload")
apkbin=tmp/"apk"; apkbin.write_text(f"#!/usr/bin/env python3\nimport json\nprint(json.dumps({{'packages':[{{'name':'luci-app-cloudflare-ip','version':{raw!r},'architecture':'all'}}]}}))\n")
apkbin.chmod(0o755)
result=json.loads(subprocess.check_output([sys.executable,str(helper),str(apk),"--format","apk","--apk-bin",str(apkbin),"--package-name","luci-app-cloudflare-ip"],text=True))
assert result["package"]["packageVersion"]==raw and result["package"]["release"]==release
print("Synthetic ar/tar IPK and mocked APK parser fixtures passed (not real package evidence)")
PY
