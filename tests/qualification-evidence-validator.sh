#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
python3 - "$TMP/manifest.json" "$ROOT" <<'PYFIXTURE'
import json,sys,pathlib
sys.path.insert(0,str(pathlib.Path(sys.argv[2])/"tests"))
from package_contract_fixtures import manifest
value=manifest()
for name in (sys.argv[1],sys.argv[1]+".valid"):
 pathlib.Path(name).write_text(json.dumps(value))
PYFIXTURE

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
p=sys.argv[1]; d=json.load(open(p)); d['rill']['stableCommit']=json.load(open(p+'.valid'))['rill']['stableCommit']; d['packageMigration']['sourceSHA']='0'*40; json.dump(d,open(p,'w'))
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
