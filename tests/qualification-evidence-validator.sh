#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
python3 - "$TMP/manifest.json" <<'PY'
import json, sys
path=sys.argv[1]
manifest={
  "schemaVersion":1,"commit":"0123456789abcdef0123456789abcdef01234567","runId":42,"jobs":{},"artifacts":[],
  "assetFiles":[{"path":"ipk/luci-app-cloudflare-ip_2.6.0-4_all.ipk","sha256":"a"*64,"size":123,"package":{"name":"luci-app-cloudflare-ip","version":"2.6.0","release":4,"architecture":"all","format":"ipk","packageVersion":"2.6.0-4"}},{"path":"apk/luci-app-cloudflare-ip-2.6.0-r4.apk","sha256":"b"*64,"size":234,"package":{"name":"luci-app-cloudflare-ip","version":"2.6.0","release":4,"architecture":"all","format":"apk","packageVersion":"2.6.0-r4"}}],
  "qualificationState":"automated-qualification","releaseEligible":True,
  "packageMigration":{"legacyVersion":"2.6.0-r2","sourceTag":"v2.6.0-2","sourceSHA":"652476bd3cdc410bc16e3a47ee96b685c84acbbb","currentSHA":"0123456789abcdef0123456789abcdef01234567","ipk":"PASS","apk":"PASS","baseOnlyUpgrade":True,"baseAddonToBaseUpgrade":True,"addonRemovalSafe":True,"r3ToR4":True,"runtimeAbsent":True,"runtimePresent":True},
  "stableSourceArchiveSha256":"c06a792811d1f08aa7b640c10ee36047c44f825cf7272aa0f75c42ab60806a84",
  "rill":{"schemaVersion":1,"package":{"repository":"hello-yunshu/rill-openwrt-packages","commit":"64ee22f978ed8f8ed19bb675700678f57eec19e3","qualificationRunId":33735123909,"qualificationManifestSha256":"c"*64},
    "stablePackageQualification":"PASS","previewRuntimeIntegration":"PASS","stableCommit":"b990cd7043d313b0ff29c9693f091a94a5bdaf47","previewCommit":"da8389fec7f879b826d8d17cbc6bb98c03ef8462",
    "runtime":{"version":"1.5.6","tag":"preview-exact-commit","commit":"da8389fec7f879b826d8d17cbc6bb98c03ef8462","sourceArchiveSha256":"not-applicable-preview","binarySha256":"f"*64},
    "integration":{"status":"pass","sameRelease":True}}
}
json.dump(manifest,open(path,"w"))
json.dump(manifest,open(path+".valid","w"))
PY
VALIDATOR="$ROOT/scripts/validate-qualification-evidence.py"
python3 "$VALIDATOR" "$TMP/manifest.json" --commit 0123456789abcdef0123456789abcdef01234567 --require-assets 2 --require-release-eligible --run-id 42
if python3 "$VALIDATOR" "$TMP/manifest.json.valid" --require-assets 2 --require-release-eligible --run-id 42 >/dev/null 2>&1; then echo 'strict gate accepted missing expected commit' >&2; exit 1; fi
if python3 "$VALIDATOR" "$TMP/manifest.json.valid" --commit 0123456789abcdef0123456789abcdef01234567 --require-assets 2 --require-release-eligible >/dev/null 2>&1; then echo 'strict gate accepted missing expected run id' >&2; exit 1; fi
python3 - "$TMP/manifest.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['releaseEligible']=False; d['qualificationState']='incomplete'; json.dump(d,open(p,'w'))
PY
python3 "$VALIDATOR" "$TMP/manifest.json" --commit 0123456789abcdef0123456789abcdef01234567 --require-assets 2 | grep -F 'diagnostic only: releaseEligible=False'
if python3 "$VALIDATOR" "$TMP/manifest.json" --commit 0123456789abcdef0123456789abcdef01234567 --require-assets 2 --require-release-eligible --run-id 42 >/dev/null 2>&1; then echo 'strict release gate accepted false evidence' >&2; exit 1; fi
# Model the workflow dependency: a failed strict check must prevent every publish-side command.
printf 'publish-called\n' >"$TMP/publish.log"
if python3 "$VALIDATOR" "$TMP/manifest.json" --commit 0123456789abcdef0123456789abcdef01234567 --require-assets 2 --require-release-eligible --run-id 42 >/dev/null 2>&1; then
  printf '%s\n' tag create upload promotion >>"$TMP/publish.log"
fi
test "$(wc -l <"$TMP/publish.log")" -eq 1
python3 - "$TMP/manifest.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['releaseEligible']=True; d['qualificationState']='automated-qualification'; d['runId']=True; json.dump(d,open(p,'w'))
PY
if python3 "$VALIDATOR" "$TMP/manifest.json" --require-release-eligible --run-id 42 >/dev/null 2>&1; then echo 'strict release gate accepted bool run id' >&2; exit 1; fi
python3 - "$TMP/manifest.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['runId']=42; d['rill']['stableCommit']='0'*40; json.dump(d,open(p,'w'))
PY
if python3 "$VALIDATOR" "$TMP/manifest.json" --require-release-eligible --run-id 42 >/dev/null 2>&1; then echo 'strict release gate accepted wrong fixed Runtime pin' >&2; exit 1; fi
python3 - "$TMP/manifest.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['rill']['stableCommit']='b990cd7043d313b0ff29c9693f091a94a5bdaf47'; d['packageMigration']['sourceSHA']='0'*40; json.dump(d,open(p,'w'))
PY
if python3 "$VALIDATOR" "$TMP/manifest.json" --require-release-eligible --run-id 42 >/dev/null 2>&1; then echo 'strict release gate accepted wrong migration SHA' >&2; exit 1; fi
echo 'Strict qualification evidence validator blocks noneligible and mismatched release evidence'
python3 - "$VALIDATOR" "$TMP/manifest.json.valid" "$ROOT/contracts/rill-runtime.json" <<'PY'
import copy, importlib.util, json, pathlib, sys
spec=importlib.util.spec_from_file_location("qualification",sys.argv[1]); module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
valid=json.load(open(sys.argv[2])); contract=pathlib.Path(sys.argv[3]); commit=valid["commit"]
cases=[]
for value in (False,"true",None):
 d=copy.deepcopy(valid); d["releaseEligible"]=value; cases.append((f"releaseEligible={value!r}",d,commit))
d=copy.deepcopy(valid); del d["releaseEligible"]; cases.append(("missing releaseEligible",d,commit))
d=copy.deepcopy(valid); d["qualificationState"]="failed"; cases.append(("failed state",d,commit))
cases.append(("wrong expected commit",copy.deepcopy(valid),"f"*40))
for field in ("packageMigration","rill","assetFiles"):
 d=copy.deepcopy(valid); del d[field]; cases.append((f"missing {field}",d,commit))
d=copy.deepcopy(valid); d["packageMigration"]["ipk"]="FAIL"; cases.append(("required PASS changed to FAIL",d,commit))
for label, data, expected in cases:
 try: module.validate(data,expected,2,True,42,contract)
 except ValueError: continue
 raise SystemExit(f"strict qualification validator accepted {label}")
print("strict qualification negatives rejected: false/string/null/missing/failed/wrong SHA/missing evidence/failed PASS")
PY
