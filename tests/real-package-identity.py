#!/usr/bin/env python3
"""Unmocked metadata/bytes regression over downloaded or freshly built SDK packages.

The qualification manifest below is a validator test input, not a new CI verdict.
Original source-run qualification results must remain unchanged.
"""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'scripts'),str(ROOT/'tests')]
from package_identity import source,artifact_names,filename
from package_contract_fixtures import manifest

def load(name,file):
 spec=importlib.util.spec_from_file_location(name,file);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('sdk_directory',type=Path)
args=parser.parse_args()
checker=load('checker',ROOT/'scripts/check-package-assets.py')
validator=load('binding',ROOT/'scripts/validate-release-assets.py')
assets=checker.check(args.sdk_directory)
public=set(artifact_names(public_only=True))
assets=[a for a in assets if a['path'].split('/')[0] in public]
assert len(assets)==2
identity=source();contract=ROOT/'contracts/rill-runtime.json'
with tempfile.TemporaryDirectory() as directory:
 release=Path(directory)
 for asset in assets:
  shutil.copy(args.sdk_directory/asset['path'],release/Path(asset['path']).name)
 evidence=manifest(assets)
 def validate(data=evidence, version=identity['version']):
  return validator.validate(data,release,data['commit'],data['runId'],version,identity['release'],contract)
 validate()
 print('PASS actual SDK IPK control and real APK adbdump match byte-bound release evidence')
 def rejected(label,func):
  try:func()
  except (ValueError,subprocess.CalledProcessError):print('REJECT',label)
  else:raise AssertionError('accepted '+label)
 for field,value in [('version','9.9.9'),('architecture','mips_24kc'),('release',identity['release']+1)]:
  changed=copy.deepcopy(evidence);changed['assetFiles'][0]['package'][field]=value
  rejected('metadata '+field,lambda:validate(changed))
 changed=copy.deepcopy(evidence)
 for a in changed['assetFiles']:
  old=release/Path(a['path']).name
  a['package'].update(version='9.9.9',packageVersion='9.9.9-r'+str(identity['release']))
  new=release/filename(a['package']);old.rename(new);a['path']='forged/'+new.name
 rejected('coherent forged names/metadata with original package bytes',lambda:validate(changed,'9.9.9'))
 for a,b in zip(changed['assetFiles'],evidence['assetFiles']):
  (release/Path(a['path']).name).rename(release/Path(b['path']).name)
 first=release/Path(assets[0]['path']).name;raw=first.read_bytes()
 first.write_bytes(raw[:-1]+bytes([raw[-1]^1]));rejected('one byte',validate);first.write_bytes(raw)
 extra=release/'extra.apk';extra.write_bytes(b'extra');rejected('extra package',validate);extra.unlink()
 nested=release/'nested';nested.mkdir();shutil.copy(first,nested/first.name);rejected('nested duplicate basename',validate);shutil.rmtree(nested)
 first.rename(release/'saved');first.symlink_to(release/'saved');rejected('symlink asset',validate);first.unlink();(release/'saved').rename(first)
 (release/'sha256sums.txt').write_text(''.join(a['sha256']+'  '+Path(a['path']).name+'\n' for a in assets))
 checker.check(release,True)
 checksum=(release/'sha256sums.txt').read_text();(release/'sha256sums.txt').write_text(checksum+checksum.splitlines()[0]+'\n')
 rejected('duplicate checksum',lambda:checker.check(release,True))
 print('PASS real-artifact positive and metadata/bytes/path/checksum negative regression')
 print(json.dumps({'sourceIdentity':identity,'assets':assets},indent=2))
