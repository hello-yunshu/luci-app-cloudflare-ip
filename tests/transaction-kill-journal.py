#!/usr/bin/env python3
"""Real SIGKILL/UCI/filesystem; OpenClash service observations are disabled fixtures."""
from pathlib import Path
import hashlib,json,os,signal,subprocess,tempfile,time
ROOT=Path(__file__).resolve().parents[1]
LIB=os.environ.get('CFIP_TEST_LIB_DIR',str(ROOT/'package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip'))
BASH=os.environ.get('CFIP_TEST_BASH','bash');UCI=os.environ['UCI_REAL_BIN']
results=[];failures=[]
def snapshot(root):
 return {str(p.relative_to(root)):('link:'+os.readlink(p) if p.is_symlink() else hashlib.sha256(p.read_bytes()).hexdigest()) for p in root.rglob('*') if p.is_file() or p.is_symlink()}
with tempfile.TemporaryDirectory(prefix='cfip-kill-journal-') as directory:
 base=Path(directory);worker=base/'worker'
 worker.write_text(r'''set -euo pipefail
source "$CFIP_TEST_LIB_DIR/transaction.sh"
uci(){ "$UCI_REAL_BIN" -c "$CFIP_TEST_CASE/config" -t "$CFIP_TEST_CASE/delta" "$@"; }
cfip_service_running(){ return 1; }
cfip_openclash_capture_state(){ CFIP_OPENCLASH_EXPECTED_ENABLED=0; CFIP_OPENCLASH_INITIAL_HEALTHY=false; }
cfip_openclash_check_before_write(){ return 0; }
if [[ "$1" == probe ]]; then
 rc=0; cfip_txn_prepare "$CFIP_TEST_MODE" || rc=$?
 jq -cn --argjson rc "$rc" --arg error "${CFIP_RECOVERY_ERROR:-}" --arg txn "$CFIP_TXN_DIR" '{rc:$rc,error:$error,txn:$txn}'
 exit
fi
cfip_txn_prepare "$CFIP_TEST_MODE"
if [[ "$CFIP_TEST_PHASE" == mutated ]]; then
 if [[ "$CFIP_TEST_MODE" == passwall ]]; then
  cfip_passwall_set_owned passwall.owned.address 104.18.1.1
  uci commit passwall
 else
  printf 'candidate changed bytes\n' >"$CFIP_TEST_CASE/candidate.yaml"
  cfip_txn_publish_openclash "$CFIP_TEST_CASE/candidate.yaml"
 fi
fi
printf '%s' "$CFIP_TXN_DIR" >"$CFIP_TEST_CASE/ready"
while :;do sleep 1;done
''')
 for mode in ['passwall','openclash']:
  for phase in ['prepared','mutated']:
   root=base/(mode+'-'+phase)
   for name in ['config','delta','runtime','status']:(root/name).mkdir(parents=True,exist_ok=True)
   (root/'config/passwall').write_text("config nodes 'owned'\n option address 'cdn.example.com'\n option remarks 'retained user remarks'\n")
   (root/'live.yaml').write_text('original config bytes\n')
   env=dict(os.environ,CFIP_TEST_LIB_DIR=LIB,CFIP_TEST_CASE=str(root),CFIP_RUNTIME_DIR=str(root/'runtime'),CFIP_STATUS_DIR=str(root/'status'),CFIP_RUN_ID='kill-'+mode+'-'+phase,CFIP_TEST_MODE=mode,CFIP_TEST_PHASE=phase,CFIP_OPENCLASH_CONFIG=str(root/'live.yaml'))
   child=subprocess.Popen([BASH,str(worker),'prepare'],env=env,start_new_session=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True)
   try:
    deadline=time.monotonic()+8
    while not (root/'ready').exists():
     if child.poll() is not None:raise AssertionError(('worker failed',child.returncode,child.stderr.read()))
     if time.monotonic()>deadline:raise AssertionError('worker did not reach kill point')
     time.sleep(.02)
    txn=Path((root/'ready').read_text());os.killpg(child.pid,signal.SIGKILL);assert child.wait(timeout=3)==-signal.SIGKILL
    preimage=txn/('passwall.uci' if mode=='passwall' else 'openclash.yaml');assert preimage.is_file()
    if phase=='mutated':
     journal=txn/('passwall-fields.json' if mode=='passwall' else 'openclash.written.yaml');assert journal.is_file()
     if mode=='passwall':assert json.loads(journal.read_text())[0]['before']=='cdn.example.com'
     else:assert journal.read_bytes()==(root/'live.yaml').read_bytes()
    before=snapshot(root)
    probe=subprocess.run([BASH,str(worker),'probe'],env=env,capture_output=True,text=True,timeout=8);assert probe.returncode==0,probe.stderr
    value=json.loads(probe.stdout)
    assert value['rc']!=0,'new transaction accepted unresolved killed journal'
    assert str(txn) in value['error'] and value['txn']=='','root error lost or orphan adopted for cleanup'
    assert snapshot(root)==before,'refusing new transaction changed preimages/live state'
    results.append(dict(mode=mode,phase=phase,status='PASS',snapshotFiles=len(before),refused=True,journalFiles={k:v for k,v in before.items() if k.startswith('runtime/')},rootError=value['error']))
   except AssertionError as error:failures.append(dict(mode=mode,phase=phase,error=str(error)))
   finally:
    if child.poll() is None:os.killpg(child.pid,signal.SIGKILL);child.wait()
 for kind in ['unknown-directory','unknown-file','unknown-link']:
  root=base/kind
  for name in ['config','delta','runtime','status']:(root/name).mkdir(parents=True,exist_ok=True)
  entry=root/'runtime/txn-unrecognized'
  if kind=='unknown-directory':entry.mkdir();(entry/'user-note').write_text('preserve unknown data')
  elif kind=='unknown-file':entry.write_text('preserve unknown data')
  else:
   (root/'outside').write_text('preserve outside target');entry.symlink_to(root/'outside')
  env=dict(os.environ,CFIP_TEST_LIB_DIR=LIB,CFIP_TEST_CASE=str(root),CFIP_RUNTIME_DIR=str(root/'runtime'),CFIP_STATUS_DIR=str(root/'status'),CFIP_RUN_ID='new',CFIP_TEST_MODE='passwall')
  before=snapshot(root);probe=subprocess.run([BASH,str(worker),'probe'],env=env,capture_output=True,text=True,timeout=8)
  value=json.loads(probe.stdout)
  assert value['rc']!=0 and str(entry) in value['error'] and snapshot(root)==before,kind
  results.append(dict(case=kind,status='PASS',unknownEntryPreserved=True))
 print(json.dumps(dict(status='FAIL' if failures else 'PASS',scope=__doc__,results=results,failures=failures),indent=2))
 raise SystemExit(bool(failures))
