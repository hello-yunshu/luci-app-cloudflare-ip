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
python3 "$VALIDATOR" "$TMP/manifest.json" --commit 0123456789abcdef0123456789abcdef01234567 --require-assets 2 --require-release-eligible --run-id 42 --run-attempt 1
if python3 "$VALIDATOR" "$TMP/manifest.json.valid" --require-assets 2 --require-release-eligible --run-id 42 --run-attempt 1 >/dev/null 2>&1; then echo 'strict gate accepted missing expected commit' >&2; exit 1; fi
if python3 "$VALIDATOR" "$TMP/manifest.json.valid" --commit 0123456789abcdef0123456789abcdef01234567 --require-assets 2 --require-release-eligible >/dev/null 2>&1; then echo 'strict gate accepted missing expected run id' >&2; exit 1; fi
python3 - "$TMP/manifest.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['releaseEligible']=False; d['qualificationState']='incomplete'; json.dump(d,open(p,'w'))
PY
python3 "$VALIDATOR" "$TMP/manifest.json" --commit 0123456789abcdef0123456789abcdef01234567 --require-assets 2 | grep -F 'diagnostic only: releaseEligible=False'
if python3 "$VALIDATOR" "$TMP/manifest.json" --commit 0123456789abcdef0123456789abcdef01234567 --require-assets 2 --require-release-eligible --run-id 42 --run-attempt 1 >/dev/null 2>&1; then echo 'strict release gate accepted false evidence' >&2; exit 1; fi
# Model the workflow dependency: a failed strict check must prevent every publish-side command.
printf 'publish-called\n' >"$TMP/publish.log"
if python3 "$VALIDATOR" "$TMP/manifest.json" --commit 0123456789abcdef0123456789abcdef01234567 --require-assets 2 --require-release-eligible --run-id 42 --run-attempt 1 >/dev/null 2>&1; then
  printf '%s\n' tag create upload promotion >>"$TMP/publish.log"
fi
test "$(wc -l <"$TMP/publish.log")" -eq 1
python3 - "$TMP/manifest.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['releaseEligible']=True; d['qualificationState']='automated-qualification'; d['runId']=True; json.dump(d,open(p,'w'))
PY
if python3 "$VALIDATOR" "$TMP/manifest.json" --commit 0123456789abcdef0123456789abcdef01234567 --require-release-eligible --run-id 42 --run-attempt 1 >/dev/null 2>&1; then echo 'strict release gate accepted bool run id' >&2; exit 1; fi
python3 - "$TMP/manifest.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['runId']=42; d['rill']['stableCommit']='0'*40; json.dump(d,open(p,'w'))
PY
if python3 "$VALIDATOR" "$TMP/manifest.json" --commit 0123456789abcdef0123456789abcdef01234567 --require-release-eligible --run-id 42 --run-attempt 1 >/dev/null 2>&1; then echo 'strict release gate accepted wrong fixed Runtime pin' >&2; exit 1; fi
python3 - "$TMP/manifest.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['rill']['stableCommit']=json.load(open(p+'.valid'))['rill']['stableCommit']; d['packageMigration']['sourceSHA']='0'*40; json.dump(d,open(p,'w'))
PY
if python3 "$VALIDATOR" "$TMP/manifest.json" --commit 0123456789abcdef0123456789abcdef01234567 --require-release-eligible --run-id 42 --run-attempt 1 >/dev/null 2>&1; then echo 'strict release gate accepted wrong migration SHA' >&2; exit 1; fi
echo 'Strict qualification evidence validator blocks noneligible and mismatched release evidence'
python3 - "$VALIDATOR" "$TMP/manifest.json.valid" "$ROOT/contracts/rill-runtime.json" <<'PY'
import copy, importlib.util, json, pathlib, sys
spec=importlib.util.spec_from_file_location("qualification",sys.argv[1]); module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
valid=json.load(open(sys.argv[2])); contract=pathlib.Path(sys.argv[3]); commit=valid["commit"]
cases=[]
for value in (None, [], {}, [valid["packageMigration"]["currentMatrices"][0]]):
 d=copy.deepcopy(valid); d["packageMigration"]["currentMatrices"]=value; cases.append(("missing/incomplete current matrices",d,commit))
for index in (0,1):
 for value in (None, [], {}):
  d=copy.deepcopy(valid);d["packageMigration"]["currentMatrices"][index]["offlineLifecycle"]=value;cases.append(("missing offline lifecycle",d,commit))
 for field,value in (("status","FAIL"),("packagePayloadRemoved",False),("dependenciesPreserved",False),("userDataPreserved",False),("reinstalled",False),("evidenceDirectory","../outside"),("scope","online hooks passed")):
  d=copy.deepcopy(valid);d["packageMigration"]["currentMatrices"][index]["offlineLifecycle"][field]=value;cases.append(("invalid offline lifecycle "+field,d,commit))
for index in (0,1):
 for value in (None, [], {}):
  d=copy.deepcopy(valid);d["packageMigration"]["currentMatrices"][index]["ownershipConflict"]=value;cases.append(("missing ownership conflict",d,commit))
 for field,value in (("rawInitialInstallRecoveryVerified",None),("guardedAdmission",None),("admissionExitCode",True),("rawManagerStateMutated",None),("exitCode",0),("exitCode",True),("exitCode","1"),("status","FAIL"),("rejected",False),("foreignOwnerPreserved",False),("preexistingPayloadPreserved",False),("installedStatePreserved",False),("userDataPreserved",False),("evidenceDirectory","../outside"),("id","wrong")):
  d=copy.deepcopy(valid);d["packageMigration"]["currentMatrices"][index]["ownershipConflict"][field]=value;cases.append(("invalid ownership conflict "+field,d,commit))
for index in (0,1):
 for value in (None, [], {}, [valid["packageMigration"]["currentMatrices"][index]["negativeInstalls"][0]]):
  d=copy.deepcopy(valid); d["packageMigration"]["currentMatrices"][index]["negativeInstalls"]=value; cases.append(("missing/incomplete negative install matrix",d,commit))
 for row_index in (0,1):
  for field,value in (("exitCode",0),("exitCode",True),("exitCode","1"),("exitCode",-1),("exitCode",256),("status","FAIL"),("rejected",False),("installedStatePreserved",False),("payloadPreserved",False),("userDataPreserved",False),("evidenceDirectory","../outside"),("id",[])):
   d=copy.deepcopy(valid); d["packageMigration"]["currentMatrices"][index]["negativeInstalls"][row_index][field]=value; cases.append(("invalid negative install "+field,d,commit))
for index in (0,1):
 for field,value in (("sha256","broken"),("size",True),("size",0)):
  d=copy.deepcopy(valid); d["packageMigration"]["currentMatrices"][index]["inputs"]["currentBase"][field]=value; cases.append(("invalid matrix input "+field,d,commit))
 for field,value in (("name","wrong"),("format","unknown"),("architecture","mips"),("release",True),("packageVersion","bad")):
  d=copy.deepcopy(valid); d["packageMigration"]["currentMatrices"][index]["inputs"]["currentBase"]["package"][field]=value; cases.append(("invalid matrix metadata "+field,d,commit))
 for row_index in range(5):
  for field,value in (("status","FAIL"),("runtimeAbsent",False),("runtimePresent",False),("userDataPreserved",False),("evidenceDirectory","../outside"),("from",[]),("id",[])):
   d=copy.deepcopy(valid); d["packageMigration"]["currentMatrices"][index]["scenarios"][row_index][field]=value; cases.append(("invalid matrix scenario "+field,d,commit))
for field in list(valid["jobs"]):
 d=copy.deepcopy(valid); del d["jobs"][field]; cases.append((f"missing required job {field}",d,commit))
 for result in ("failure", "skipped", "cancelled", "in_progress", None, True):
  d=copy.deepcopy(valid); d["jobs"][field]["result"]=result; cases.append((f"job {field}={result!r}",d,commit))
for jobs in ({}, [], None, {**valid["jobs"], "unexpected": {"result":"success"}}):
 d=copy.deepcopy(valid); d["jobs"]=jobs; cases.append((f"invalid job set {jobs!r}",d,commit))
module.validate(valid,commit,2,True,42,contract,1)
for value in (None, True, False, 0, -1, "1", 2):
 d=copy.deepcopy(valid)
 if value is None: d.pop("runAttempt")
 else: d["runAttempt"]=value
 cases.append((f"invalid or mismatched runAttempt={value!r}",d,commit))
for expected_attempt in (None, True, 0, -1, 2):
 try: module.validate(valid,commit,2,True,42,contract,expected_attempt)
 except ValueError: continue
 raise SystemExit(f"strict validator accepted expected attempt {expected_attempt!r}")
for value in (False,"true",None):
 d=copy.deepcopy(valid); d["releaseEligible"]=value; cases.append((f"releaseEligible={value!r}",d,commit))
d=copy.deepcopy(valid); del d["releaseEligible"]; cases.append(("missing releaseEligible",d,commit))
d=copy.deepcopy(valid); d["qualificationState"]="failed"; cases.append(("failed state",d,commit))
cases.append(("wrong expected commit",copy.deepcopy(valid),"f"*40))
for field in ("packageMigration","rill","assetFiles"):
 d=copy.deepcopy(valid); del d[field]; cases.append((f"missing {field}",d,commit))
d=copy.deepcopy(valid); d["packageMigration"]["ipk"]="FAIL"; cases.append(("required PASS changed to FAIL",d,commit))
for label, data, expected in cases:
 try: module.validate(data,expected,2,True,42,contract,1)
 except ValueError: continue
 raise SystemExit(f"strict qualification validator accepted {label}")
print("strict qualification negatives rejected: false/string/null/missing/failed/wrong SHA/missing evidence/failed PASS")
PY
