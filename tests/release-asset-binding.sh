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
sys.path.insert(0, str(root / "tests"))
from package_contract_fixtures import manifest as fixture_manifest
from package_identity import source
identity=source(); run_id, version, release = 42, identity["version"], identity["release"]
manifest=fixture_manifest()
release_dir=temp/"release"; release_dir.mkdir()
files={}
for asset in manifest["assetFiles"]:
    fmt=asset["package"]["format"]; name=pathlib.PurePosixPath(asset["path"]).name
    files[name]=f"synthetic {fmt} byte-binding payload".encode()
    (release_dir/name).write_bytes(files[name])
# This test isolates byte binding. Real metadata is exercised unmocked by
# tests/real-package-identity.py and the SDK artifact contract job.
metadata_by_format={a["package"]["format"]:a["package"] for a in manifest["assetFiles"]}
module.PACKAGE.inspect=lambda file,fmt,*args: {"package":metadata_by_format[fmt],"sha256":hashlib.sha256(file.read_bytes()).hexdigest(),"size":file.stat().st_size}
module.validate(manifest, release_dir, commit, run_id, version, release, contract, expected_run_attempt=1)
print("synthetic byte-binding input accepted; real metadata coverage is separate")

def rejected(label, changed_manifest=None, mutate_files=None):
    before = {p.name:p.read_bytes() for p in release_dir.iterdir() if p.is_file()}
    try:
        if mutate_files: mutate_files()
        module.validate(copy.deepcopy(manifest) if changed_manifest is None else changed_manifest, release_dir, commit, run_id, version, release, contract, expected_run_attempt=1)
    except (ValueError, KeyError, TypeError):
        print(f"rejected: {label}")
    else:
        raise SystemExit(f"accepted invalid release binding: {label}")
    finally:
        for name, raw in before.items(): (release_dir/name).write_bytes(raw)
        for p in list(release_dir.iterdir()):
            if p.is_file() and p.name not in before: p.unlink()

rejected("same-size different bytes", mutate_files=lambda:(release_dir / next(iter(files))).write_bytes(files[next(iter(files))].swapcase()))
rejected("one byte changed", mutate_files=lambda:(release_dir / next(iter(files))).write_bytes(files[next(iter(files))][:-1] + b"X"))
bad=copy.deepcopy(manifest); bad["assetFiles"][0]["sha256"],bad["assetFiles"][1]["sha256"]=bad["assetFiles"][1]["sha256"],bad["assetFiles"][0]["sha256"]; rejected("swapped hashes",bad)
bad=copy.deepcopy(manifest); bad["assetFiles"][1]["path"]=bad["assetFiles"][0]["path"]; rejected("duplicate path/basename",bad)
bad=copy.deepcopy(manifest); del bad["assetFiles"][0]["path"]; rejected("hash without name",bad)
bad=copy.deepcopy(manifest); bad["assetFiles"][0]["path"]="/tmp/"+bad["assetFiles"][0]["path"]; rejected("absolute path",bad)
bad=copy.deepcopy(manifest); bad["assetFiles"][0]["path"]="build/../"+pathlib.PurePosixPath(bad["assetFiles"][0]["path"]).name; rejected("path traversal",bad)
rejected("extra package",mutate_files=lambda:(release_dir/"unexpected.ipk").write_bytes(b"x"))
for label, field, value in (("wrong package version","version","2.6.1"),("wrong package release","release",release+1),("wrong architecture","architecture","mips_24kc")):
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
echo 'Release byte/path binding regression passed (synthetic fixtures)'
