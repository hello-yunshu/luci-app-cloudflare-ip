#!/usr/bin/env python3
"""Candidate builds do not imply branch publication eligibility."""
import importlib.util
from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'scripts'))
spec=importlib.util.spec_from_file_location('policy',root/'scripts/check-build-version-policy.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
contexts=[('refs/heads/main','push','',True),('refs/heads/release/candidate','push','',True),
 ('refs/pull/18/merge','pull_request','main',True),('refs/pull/18/merge','pull_request','release/candidate',True),
 ('refs/heads/codex/candidate','push','',False),('refs/pull/18/merge','pull_request','codex/base',False)]
for ref,event,base,release in contexts:
 for dev in (True,False):
  for channel in ('stable','prerelease'):
   identity=dict(version='2.6.0-dev' if dev else '2.6.0',channel=channel)
   reject=dev and (release or channel=='stable')
   try:m.validate(identity,ref,event,base)
   except ValueError:assert reject,(identity,ref,event,base)
   else:assert not reject,(identity,ref,event,base)
print('PASS build policy across release/feature refs, PR bases, versions and channels')
