#!/usr/bin/env python3
"""Actual cache/download entry with private archive fixtures; no network or real CFST."""
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
ROOT=Path(__file__).resolve().parents[1]
LEGACY=os.environ.get('CFIP_TEST_LEGACY',str(ROOT/'package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-legacy'))
BASH=os.environ.get('CFIP_TEST_BASH','bash')
results=[];failures=[]
scenarios=[
 ('missing',False,'direct',False,False),('malformed',False,'direct',False,False),
 ('missing-source',False,'direct',False,False),('legacy-bootstrap',False,'direct',False,False),
 ('http-source',False,'direct',False,False),('wrong-digest',False,'direct',False,False),
 ('qualified',False,'direct',True,True),('https-unknown-tag',False,'direct',True,True),('uppercase-digest',False,'direct',True,True),
 ('missing',True,'direct',True,False),('legacy-bootstrap',True,'direct',True,False),
 ('malformed',True,'direct',True,False),('source-object',False,'direct',False,False),
 ('multiple',False,'direct',False,False),('oversized',False,'direct',False,False),
 ('metadata-symlink',False,'direct',False,False),('archive-symlink',False,'direct',False,False),
 ('missing',False,'offline',False,False),('qualified',False,'offline',True,True),
 ('wrong-digest',True,'offline',True,False),('empty-version',False,'direct',False,False)]
def state(paths):
 result={}
 for p in paths:
  if p.is_symlink():result[p.name]={'link':os.readlink(p)}
  elif p.is_file():result[p.name]={'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
  else:result[p.name]={'absent':True}
 return result
with tempfile.TemporaryDirectory(prefix='cfip-cfst-cache-') as directory:
 base=Path(directory);worker=base/'worker'
 worker.write_text(r'''source "$CFIP_TEST_LEGACY"
CFST_DIR="$CFIP_TEST_ROOT/cfst"; BINARY_NAME=cfst; LOG_FILE="$CFIP_TEST_ROOT/log"
log(){ :; }; need_cmd(){ :; }; ensure_jq(){ :; }; detect_arch_tag(){ printf test; }
curl_fetch(){ return 22; }
RELEASE_API=https://one.example/release
if [[ "$CFIP_TEST_FLOW" == offline ]]; then
 if download_speedtest; then exit 0; else exit 1; fi
else
 if install_cached_speedtest_archive "$CFST_DIR/cfst_linux_test.tar.gz"; then exit 0; else exit 1; fi
fi
''')
 for index,(shape,existing,flow,accepted,execute) in enumerate(scenarios):
  name=f'{shape}-{flow}-'+('existing' if existing else 'bootstrap')
  root=base/str(index);target=root/'cfst';target.mkdir(parents=True)
  archive=target/'cfst_linux_test.tar.gz';metadata=target/'cfst_linux_test.tar.gz.meta';binary=target/'cfst';version=target/'cfst_version.txt'
  payload=b'#!/bin/sh\nprintf executed >"$CFIP_TEST_ROOT/executed"\necho fixture-version\n'
  with tarfile.open(archive,'w:gz') as tar:
   member=tarfile.TarInfo('cfst');member.mode=0o755;member.size=len(payload);tar.addfile(member,io.BytesIO(payload))
  digest=hashlib.sha256(archive.read_bytes()).hexdigest()
  marker=dict(schemaVersion=1,version='v1',source='https://one.example/cfst.tar.gz',sha256=digest)
  if shape=='missing-source':del marker['source']
  if shape=='legacy-bootstrap':marker.update(version='unknown',source='cached archive')
  if shape=='https-unknown-tag':marker['version']='unknown'
  if shape=='empty-version':marker['version']=''
  if shape=='http-source':marker['source']='http://one.example/cfst.tar.gz'
  if shape=='wrong-digest':marker['sha256']='0'*64
  if shape=='uppercase-digest':marker['sha256']=digest.upper()
  if shape=='source-object':marker['source']={}
  if shape=='oversized':marker['padding']='x'*20000
  if shape!='missing':metadata.write_text('{broken' if shape=='malformed' else json.dumps(marker)+('\n'+json.dumps(marker) if shape=='multiple' else ''))
  outside=root/'external';outside.write_bytes(b'outside retained')
  if shape=='metadata-symlink':outside.write_bytes(metadata.read_bytes());metadata.unlink();metadata.symlink_to(outside)
  if shape=='archive-symlink':outside.write_bytes(archive.read_bytes());archive.unlink();archive.symlink_to(outside)
  if existing:binary.write_bytes(b'#!/bin/sh\necho retained-current\n');binary.chmod(0o755);version.write_text('retained-version\n')
  paths=[archive,metadata,binary,version,outside];before=state(paths)
  run=subprocess.run([BASH,str(worker)],env=dict(os.environ,CFIP_TEST_ROOT=str(root),CFIP_TEST_LEGACY=LEGACY,CFIP_TEST_FLOW=flow),capture_output=True,text=True,timeout=12)
  after=state(paths);executed=(root/'executed').exists()
  try:
   assert (run.returncode==0)==accepted,dict(returncode=run.returncode,stderr=run.stderr)
   assert executed==execute,'cache entry executed without qualification or rejected a qualified entry'
   if not execute:assert before==after,'refusing cached install changed existing artifacts'
   else:
    assert binary.read_bytes()==payload and version.read_text()==marker['version']+'\n'
    saved=json.loads(metadata.read_text());assert saved['sha256']==digest and saved['version']==marker['version']
    assert before[archive.name]==after[archive.name],'cached install changed its archive input'
   assert before[outside.name]==after[outside.name],'cache qualification changed an external target'
   results.append(dict(case=name,status='PASS',executed=executed,returncode=run.returncode,before=before,after=after))
  except AssertionError as error:failures.append(dict(case=name,error=str(error),executed=executed,returncode=run.returncode,stderr=run.stderr[-1000:],before=before,after=after))
 print(json.dumps(dict(status='FAIL' if failures else 'PASS',scope='actual CFST cached/offline entry with archive/script fixtures',sourceSha256=hashlib.sha256(Path(LEGACY).read_bytes()).hexdigest(),results=results,failures=failures),indent=2))
 raise SystemExit(bool(failures))
