#!/usr/bin/env python3
"""Actual legacy CFST installer, isolated artifacts/command faults; not real CFST proof."""
import hashlib
import io
import json
import os
import stat
from pathlib import Path
import subprocess
import tarfile
import tempfile

ROOT=Path(__file__).resolve().parents[1]
BASH=os.environ.get('CFIP_TEST_BASH','bash')
LEGACY=os.environ.get('CFIP_TEST_LEGACY',str(ROOT/'package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-legacy'))
results=[];failures=[]
def installed_state(target,names):
 state={}
 for name in names:
  p=target/name
  if p.is_symlink():state[name]=dict(kind='symlink',target=os.readlink(p))
  elif p.is_file():state[name]=dict(kind='file',sha256=hashlib.sha256(p.read_bytes()).hexdigest(),mode=oct(stat.S_IMODE(p.stat().st_mode)))
  elif p.is_dir():state[name]=dict(kind='directory',entries=sorted(v.name for v in p.iterdir()))
  else:state[name]=dict(kind='absent')
 return state
with tempfile.TemporaryDirectory(prefix='cfip-cfst-install-') as directory:
 base=Path(directory);worker=base/'worker'
 worker.write_text(r'''source "$CFIP_TEST_LEGACY"
CFST_DIR="$CFIP_TEST_ROOT/cfst"; BINARY_NAME=cfst; LOG_FILE="$CFIP_TEST_ROOT/log"
log(){ :; }
cp(){
 local src="${@: -2:1}" target="${*: -1}"
 if [[ "$CFIP_TEST_CASE" == snapshot-* ]]; then
  case "$CFIP_TEST_CASE:$src" in
   snapshot-binary:"$CFST_DIR/cfst"|snapshot-version:"$CFST_DIR/cfst_version.txt"|snapshot-archive:"$CFST_DIR/cfst.tar.gz"|snapshot-metadata:"$CFST_DIR/cfst.tar.gz.meta") return 23 ;;
  esac
 fi
 command cp "$@"
}
printf(){
 if [[ "$CFIP_TEST_CASE" == version-write && "${2:-}" == v2 ]]; then return 23; fi
 builtin printf "$@"
}
tar(){
 builtin printf called >>"$CFIP_TEST_ROOT/tar-called"
 command tar "$@"
}
mv(){
 local src="${@: -2:1}" target="${*: -1}" role=''
 case "$target" in
  "$CFST_DIR/cfst") role=binary ;;
  "$CFST_DIR/cfst_version.txt") role=version ;;
  "$CFST_DIR/cfst.tar.gz") role=archive ;;
  "$CFST_DIR/cfst.tar.gz.meta") role=metadata ;;
 esac
 [[ -z "$role" ]] || builtin printf '%s -> %s\n' "$src" "$target" >>"$CFIP_TEST_ROOT/mutations"
 if [[ "$CFIP_TEST_CASE" == snapshot-* || "$CFIP_TEST_CASE" == rollback-failure || "$CFIP_TEST_CASE" == bootstrap ]]; then
  [[ "$src" != */version || "$role" != version ]] || return 29
 fi
 case "$CFIP_TEST_CASE:$src:$role" in
  commit-binary:*/binary:binary|commit-version:*/version:version|commit-archive:*incoming.tar.gz:archive|commit-metadata:*/metadata:metadata|cached-metadata:*/metadata:metadata) return 29 ;;
 esac
 if [[ "$CFIP_TEST_CASE" == rollback-failure && "$role" == binary && ( "$src" == *'.old.'* || "$src" == */restore* ) ]]; then return 31; fi
 command mv "$@"
}
# Conditional invocation mirrors the cached-fallback call chain, where Bash
# errexit cannot substitute for explicit per-operation error handling.
if [[ "$CFIP_TEST_CASE" == bad-release-digest ]]; then
 RELEASE_API=https://one.example/release; RELEASE_DOWNLOAD_BASE=https://one.example/releases
 need_cmd(){ :; }; ensure_jq(){ :; }; detect_arch_tag(){ builtin printf test; }
 curl_fetch(){
  if [[ "$2" == "$RELEASE_API" ]]; then
   command jq -cn --arg digest "sha256:$CFIP_TEST_RELEASE_DIGEST" '{tag_name:"v2",assets:[{name:"cfst_linux_test.tar.gz",browser_download_url:"https://one.example/cfst",digest:$digest}]}' >"$1"
  else command cp "$CFIP_TEST_ROOT/incoming.tar.gz" "$1"; fi
 }
 if download_speedtest; then builtin printf retained; exit 0; else exit 1; fi
fi
input="$CFIP_TEST_ROOT/incoming.tar.gz"
[[ "$CFIP_TEST_CASE" != cached-* ]] || input="$CFST_DIR/cfst.tar.gz"
if install_speedtest_archive "$input" v2 https://one.example/cfst "$CFIP_TEST_DIGEST" "$CFST_DIR/cfst.tar.gz"; then
 builtin printf accepted
else builtin printf rejected; exit 1; fi
''')
 scenarios=['success','bootstrap-success','cached-success','cached-metadata','snapshot-binary','snapshot-version','snapshot-archive','snapshot-metadata','version-write',
            'commit-binary','commit-version','commit-archive','commit-metadata','rollback-failure','bootstrap','bad-digest','execution-check','unsafe-path','symlink','target-symlink','target-directory','bad-release-digest','missing-digest']
 for name in scenarios:
  root=base/name;target=root/'cfst';target.mkdir(parents=True)
  old={'cfst':b'#!/bin/sh\necho old-binary\n','cfst_version.txt':b'v1\n','cfst.tar.gz':b'retained archive bytes\n','cfst.tar.gz.meta':b'{"retained":"metadata"}\n'}
  if name not in ('bootstrap','bootstrap-success'):
   for filename,raw in old.items():(target/filename).write_bytes(raw)
   (target/'cfst').chmod(0o755)
  archive=root/'incoming.tar.gz'
  raw=b'#!/bin/sh\necho new-binary\n' if name!='execution-check' else b'#!/bin/sh\nexit 126\n'
  with tarfile.open(archive,'w:gz') as out:
   entry=tarfile.TarInfo('../cfst' if name=='unsafe-path' else 'cfst');entry.mode=0o755
   if name=='symlink':entry.type=tarfile.SYMTYPE;entry.linkname='../outside';out.addfile(entry)
   else:entry.size=len(raw);out.addfile(entry,io.BytesIO(raw))
  (root/'outside').write_text('outside retained')
  if name=='target-symlink':(target/'cfst').unlink();(target/'cfst').symlink_to(root/'outside')
  if name=='target-directory':(target/'cfst').unlink();(target/'cfst').mkdir();(target/'cfst'/'user-data').write_text('retained directory')
  digest=hashlib.sha256(archive.read_bytes()).hexdigest();new_archive=archive.read_bytes()
  if name.startswith('cached-'):(target/'cfst.tar.gz').write_bytes(new_archive);old['cfst.tar.gz']=new_archive
  env=dict(os.environ,CFIP_TEST_LEGACY=LEGACY,CFIP_TEST_ROOT=str(root),CFIP_TEST_CASE=name,CFIP_TEST_DIGEST='' if name=='missing-digest' else ('0'*64 if name=='bad-digest' else digest),CFIP_TEST_RELEASE_DIGEST='0'*64)
  before=installed_state(target,old)
  run=subprocess.run([BASH,str(worker)],env=env,capture_output=True,text=True,timeout=12)
  after=installed_state(target,old)
  retained=[dict(path=str(v.relative_to(target)),sha256=hashlib.sha256(v.read_bytes()).hexdigest(),mode=oct(stat.S_IMODE(v.stat().st_mode))) for v in sorted(target.glob('.cfst-install.*/old-*')) if v.is_file()]
  try:
   if name=='bad-release-digest':
    assert run.returncode==0 and after==before,'bad release digest did not retain the current installation'
    assert not (root/'tar-called').exists(),'downloaded archive was parsed before release digest verification'
   elif name in ('success','bootstrap-success','cached-success'):
    assert run.returncode==0,(run.returncode,run.stdout,run.stderr)
    assert (target/'cfst').read_bytes()==raw and (target/'cfst_version.txt').read_bytes()==b'v2\n'
    assert (target/'cfst.tar.gz').read_bytes()==new_archive
    meta=json.loads((target/'cfst.tar.gz.meta').read_text());assert meta['version']=='v2' and meta['sha256']==digest
   else:
    assert run.returncode!=0,'installer accepted a failed operation'
    if name=='rollback-failure':
     saved=[p for p in target.rglob('*') if p.is_file() and p.name!='cfst']
     assert any(p.read_bytes()==old['cfst'] for p in saved),'failed rollback discarded the binary preimage'
     expected={(v['sha256'],v['mode']) for v in before.values()}
     assert {(v['sha256'],v['mode']) for v in retained}==expected,'failed rollback did not retain every complete preimage with its mode'
     assert 'recover' in run.stderr.lower(),'failed rollback did not report recovery requirement'
    elif name=='target-symlink':
     assert after==before,'unsafe target refusal changed installed artifacts'
     assert (target/'cfst').is_symlink() and (target/'cfst').readlink()==root/'outside','installer replaced a foreign target symlink'
    elif name=='target-directory':
     assert after==before,'unsafe directory refusal changed installed artifacts'
     assert (target/'cfst'/'user-data').read_text()=='retained directory'
    elif name=='bootstrap':assert all(not (target/f).exists() for f in old),'failed bootstrap left partially installed targets'
    else:
     assert all((target/f).is_file() and (target/f).read_bytes()==data for f,data in old.items()),'failure changed or deleted old installed artifacts'
     assert after==before,'failure changed preimage file modes or identity'
     if name.startswith('snapshot-'):assert not (root/'mutations').exists(),'snapshot failure reached live mutation'
     if name in ('bad-digest','missing-digest'):assert not (root/'tar-called').exists(),'archive was parsed before digest verification'
   assert (root/'outside').read_text()=='outside retained','unsafe archive changed outside bytes'
   results.append(dict(case=name,status='PASS',before=before,after=after,returncode=run.returncode,stderr=run.stderr[-1200:],recoveryPreimages=retained))
  except AssertionError as error:failures.append(dict(case=name,error=str(error),before=before,after=after,recoveryPreimages=retained,returncode=run.returncode,stdout=run.stdout,stderr=run.stderr[-1200:]))
 print(json.dumps(dict(status='FAIL' if failures else 'PASS',scope='actual CFST archive installer with script fixtures and filesystem command faults',sourceSha256=hashlib.sha256(Path(LEGACY).read_bytes()).hexdigest(),results=results,failures=failures),indent=2))
 raise SystemExit(bool(failures))
