#!/usr/bin/env python3
"""Synthetic archive/ELF-header negatives; not actual CFST execution evidence."""
import copy
import hashlib
import importlib.util
import io
import json
import tarfile
import tempfile
from pathlib import Path
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('cfst',Path(__file__).resolve().parents[1]/'scripts/prepare-cfst-smoke.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
header=bytearray(64);header[:6]=b'\x7fELF\x02\x01';header[16:18]=(2).to_bytes(2,'little');header[18:20]=(62).to_bytes(2,'little')
with tempfile.TemporaryDirectory() as directory:
 root=Path(directory);archive=root/'archive'
 def fixture(entries):
  with tarfile.open(archive,'w:gz') as tar:
   for name,raw,link in entries:
    member=tarfile.TarInfo(name)
    if link:member.type=tarfile.SYMTYPE;member.linkname='outside';tar.addfile(member)
    else:member.size=len(raw);tar.addfile(member,io.BytesIO(raw))
  digest=hashlib.sha256(archive.read_bytes()).hexdigest()
  return dict(id=123,tag_name='v2.3.5',assets=[dict(id=456,name=m.ASSET,size=archive.stat().st_size,digest='sha256:'+digest,browser_download_url='https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.3.5/'+m.ASSET)])
 valid=fixture([('cfst',header,False)])
 target=m.prepare(valid,archive,root/'good');assert target.read_bytes()==header and target.stat().st_mode&0o111
 assert json.loads((target.parent/'cfst-byte-qualification.json').read_text())['execution']=='NOT RUN'
 index=0
 def reject(label,data):
  global index
  index+=1;output=root/('rejected-'+str(index))
  try:m.prepare(data,archive,output)
  except ValueError:assert not output.exists();print('REJECT',label)
  else:raise AssertionError('accepted '+label)
 for field,value in [('digest',None),('digest','sha256:'+'0'*64),('id',True),('size',0),('browser_download_url','https://example.invalid/binary')]:
  data=copy.deepcopy(valid);data['assets'][0][field]=value
  reject('metadata '+field,data)
 data=copy.deepcopy(valid);data['assets']*=2;reject('duplicate metadata asset',data)
 data=copy.deepcopy(valid);data['assets'][0]['digest']='sha256:'+'0'*64
 with patch.object(m.tarfile,'open',side_effect=AssertionError('parsed archive before digest verification')):reject('digest must precede archive parsing',data)
 wrong=bytearray(header);wrong[18:20]=(183).to_bytes(2,'little')
 for label,entries in [('wrong arch',[('cfst',wrong,False)]),('not ELF',[('cfst',b'#!/bin/sh\nexit 0\n',False)]),('traversal',[('../cfst',header,False)]),('absolute path',[('/cfst',header,False)]),('symlink',[('cfst',b'',True)]),('duplicate binary',[('cfst',header,False),('nested/cfst',header,False)]),('missing binary',[('README',b'text',False)])]:
  reject(label,fixture(entries))
 valid=fixture([('cfst',header,False)])
 original=archive.read_bytes();archive.write_bytes(original[:-1]+bytes([original[-1]^1]))
 reject('same-sized archive bytes changed',valid)
 original_binary=target.read_bytes()
 try:m.prepare(valid,archive,target.parent)
 except ValueError:assert target.read_bytes()==original_binary
 else:raise AssertionError('existing output replaced')
print('PASS CFST pre-execution byte/metadata/archive/architecture negatives (synthetic fixtures)')
