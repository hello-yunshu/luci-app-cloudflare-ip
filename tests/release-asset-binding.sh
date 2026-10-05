#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
python3 - "$ROOT" "$TMP" <<'PY'
import copy, hashlib, importlib.util, json, pathlib, sys
root, temp = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("release_assets", root / "scripts/validate-release-assets.py")
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
contract = root / "contracts/rill-runtime.json"
commit = "0123456789abcdef0123456789abcdef01234567"
run_id, version, release = 42, "2.6.0", 4
release_dir = temp / "release"; release_dir.mkdir()
files = {
    "luci-app-cloudflare-ip_2.6.0-4_all.ipk": b"valid-ipk-payload-0001",
    "luci-app-cloudflare-ip-2.6.0-r4.apk": b"valid-apk-payload-0001",
}
formats = {"ipk": ("all", "2.6.0-4"), "apk": ("all", "2.6.0-r4")}
assets = []
for name, raw in files.items():
    path = release_dir / name; path.write_bytes(raw)
    fmt = path.suffix[1:]; arch, package_version = formats[fmt]
    assets.append({"path": f"build-{fmt}/{name}", "sha256": hashlib.sha256(raw).hexdigest(), "size": len(raw),
        "package": {"name":"luci-app-cloudflare-ip", "version":version, "release":release,
                    "architecture":arch, "format":fmt, "packageVersion":package_version}})
manifest = {
 "schemaVersion":1,"commit":commit,"runId":run_id,"jobs":{},"artifacts":[],"assetFiles":assets,
 "qualificationState":"automated-qualification","releaseEligible":True,
 "packageMigration":{"legacyVersion":"2.6.0-r2","sourceTag":"v2.6.0-2","sourceSHA":"652476bd3cdc410bc16e3a47ee96b685c84acbbb","currentSHA":commit,"ipk":"PASS","apk":"PASS","baseOnlyUpgrade":True,"baseAddonToBaseUpgrade":True,"addonRemovalSafe":True,"r3ToR4":True,"runtimeAbsent":True,"runtimePresent":True},
 "stableSourceArchiveSha256":"c06a792811d1f08aa7b640c10ee36047c44f825cf7272aa0f75c42ab60806a84",
 "rill":{"schemaVersion":1,"package":{"repository":"hello-yunshu/rill-openwrt-packages","commit":"64ee22f978ed8f8ed19bb675700678f57eec19e3","qualificationRunId":33735123909,"qualificationManifestSha256":"c"*64},"stablePackageQualification":"PASS","previewRuntimeIntegration":"PASS","stableCommit":"b990cd7043d313b0ff29c9693f091a94a5bdaf47","previewCommit":"da8389fec7f879b826d8d17cbc6bb98c03ef8462","runtime":{"version":"1.5.6","tag":"preview-exact-commit","commit":"da8389fec7f879b826d8d17cbc6bb98c03ef8462","sourceArchiveSha256":"not-applicable-preview","binarySha256":"f"*64},"integration":{"status":"pass","sameRelease":True}}
}
module.validate(manifest, release_dir, commit, run_id, version, release, contract)
print("valid exact-run IPK/APK bytes accepted")

def rejected(label, changed_manifest=None, mutate_files=None):
    before = {p.name:p.read_bytes() for p in release_dir.iterdir() if p.is_file()}
    try:
        if mutate_files: mutate_files()
        module.validate(copy.deepcopy(manifest) if changed_manifest is None else changed_manifest, release_dir, commit, run_id, version, release, contract)
    except (ValueError, KeyError, TypeError):
        print(f"rejected: {label}")
    else:
        raise SystemExit(f"accepted invalid release binding: {label}")
    finally:
        for name, raw in before.items(): (release_dir/name).write_bytes(raw)
        for p in list(release_dir.iterdir()):
            if p.is_file() and p.name not in before: p.unlink()

rejected("same-size different bytes", mutate_files=lambda:(release_dir / next(iter(files))).write_bytes(b"VALID-ipk-payload-0001"))
rejected("one byte changed", mutate_files=lambda:(release_dir / next(iter(files))).write_bytes(files[next(iter(files))][:-1] + b"X"))
bad=copy.deepcopy(manifest); bad["assetFiles"][0]["sha256"],bad["assetFiles"][1]["sha256"]=bad["assetFiles"][1]["sha256"],bad["assetFiles"][0]["sha256"]; rejected("swapped hashes",bad)
bad=copy.deepcopy(manifest); bad["assetFiles"][1]["path"]=bad["assetFiles"][0]["path"]; rejected("duplicate path/basename",bad)
bad=copy.deepcopy(manifest); del bad["assetFiles"][0]["path"]; rejected("hash without name",bad)
bad=copy.deepcopy(manifest); bad["assetFiles"][0]["path"]="/tmp/"+bad["assetFiles"][0]["path"]; rejected("absolute path",bad)
bad=copy.deepcopy(manifest); bad["assetFiles"][0]["path"]="build/../"+pathlib.PurePosixPath(bad["assetFiles"][0]["path"]).name; rejected("path traversal",bad)
rejected("extra package",mutate_files=lambda:(release_dir/"unexpected.ipk").write_bytes(b"x"))
for label, field, value in (("wrong package version","version","2.6.1"),("wrong package release","release",5),("wrong architecture","architecture","mips_24kc")):
    bad=copy.deepcopy(manifest); bad["assetFiles"][0]["package"][field]=value; rejected(label,bad)
bad=copy.deepcopy(manifest); bad["rill"]["stableCommit"]="0"*40; rejected("fixed Runtime commit mismatch",bad)
bad=copy.deepcopy(manifest); bad["rill"]["package"]["qualificationRunId"]=0; rejected("fixed package run mismatch",bad)
bad=copy.deepcopy(manifest); bad["stableSourceArchiveSha256"]="0"*64; rejected("fixed source digest mismatch",bad)

manifest_file=temp/"qualification.json"; manifest_file.write_text(json.dumps(manifest),encoding="utf-8")
checksums="".join(f"{hashlib.sha256((release_dir/n).read_bytes()).hexdigest()}  {n}\n" for n in files)
(release_dir/"sha256sums.txt").write_text(checksums,encoding="ascii")
print("relative checksums generated only for bound assets")
PY
(cd "$TMP/release" && sha256sum -c sha256sums.txt)
echo 'Release asset evidence binding regression passed'
