#!/usr/bin/env python3
"""Exercise the download boundary without network or publishing side effects."""
import importlib.util
import json
import subprocess
from unittest.mock import patch
from pathlib import Path
spec=importlib.util.spec_from_file_location('download',Path(__file__).resolve().parents[1]/'scripts/download-qualification-artifact.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
sha='a'*40
name=m.scoped_name('package',42,2)
assert name != m.scoped_name('package',42,1)
assert name != m.scoped_name('package',43,2)
source=dict(id=42,run_attempt=2,head_sha=sha)
artifact=dict(name=name,expired=False)
def exercise(run, artifacts, accepted):
 with patch.object(subprocess,'check_output',side_effect=[json.dumps(run),json.dumps([dict(artifacts=artifacts)])]), patch.object(subprocess,'run') as execute:
  try:m.download('owner/repo',42,2,sha,'package','destination')
  except ValueError:
   assert not accepted
   execute.assert_not_called()
  else:
   assert accepted
   execute.assert_called_once_with(['gh','run','download','42','--repo','owner/repo','--name',name,'--dir','destination'],check=True)
exercise(source,[artifact],True)
for field,value in [('id',43),('run_attempt',1),('head_sha','b'*40)]:
 exercise(dict(source,**{field:value}),[artifact],False)
for artifacts in ([],[dict(artifact,name=m.scoped_name('package',42,1))],[artifact,artifact],[dict(artifact,expired=True)]):
 exercise(source,artifacts,False)
for run,attempt in [(True,2),(42,True),(0,1),(42,-1)]:
 try:m.scoped_name('package',run,attempt)
 except ValueError:pass
 else:raise AssertionError('accepted invalid run/attempt')
print('PASS exact-attempt artifact boundary; mocked API/download, not hosted artifact proof')
