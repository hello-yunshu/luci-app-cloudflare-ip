#!/usr/bin/env python3
"""Admission parser faults; controlled metadata reader, not real APK proof."""
import importlib.util
import json
import tempfile
from pathlib import Path
from unittest.mock import patch
from types import SimpleNamespace
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('guard',ROOT/'scripts/apk-ownership-preflight.py');guard=importlib.util.module_from_spec(spec);spec.loader.exec_module(guard)
with tempfile.TemporaryDirectory() as directory:
    root=Path(directory);db=root/'lib/apk/db/installed';db.parent.mkdir(parents=True)
    package=root/'candidate.apk';package.write_bytes(b'controlled-fixture')
    base={'info':{'name':'luci-app-cloudflare-ip'},'paths':[{'name':'usr/bin','files':[{'name':'cf-ip-auto'}]}]}
    cases=[('empty-db','',base,True),('own-upgrade','P:luci-app-cloudflare-ip\nF:usr/bin\nR:cf-ip-auto\n',base,True),('foreign-owner','P:foreign\nF:usr/bin\nR:cf-ip-auto\n',base,False),('missing-owner','F:usr/bin\nR:cf-ip-auto\n',base,False),('missing-directory','P:foreign\nR:cf-ip-auto\n',base,False),('traversal-db','P:foreign\nF:../usr\nR:cf-ip-auto\n',base,False),('duplicate-owner','P:a\nF:usr/bin\nR:cf-ip-auto\n\nP:b\nF:usr/bin\nR:cf-ip-auto\n',base,False)]
    for name,change in [('wrong-name',{'info':{'name':'other'}}),('missing-paths',{'paths':[]}),('traversal',{'paths':[{'name':'../usr/bin','files':[{'name':'cf-ip-auto'}]}]}),('duplicate-path',{'paths':base['paths']*2}),('missing-entry',{'paths':[{'name':'usr','files':[{'name':'other'}]}]})]:cases.append((name,'',dict(base,**change),False))
    for name,text,value,accepted in cases:
        db.write_text(text);before=db.read_bytes()
        with patch.object(guard.subprocess,'run',return_value=SimpleNamespace(returncode=0,stdout=json.dumps(value),stderr='')):
            try:result=guard.inspect(root,package,'controlled-reader');success=result['success']
            except ValueError:success=False
        assert success==accepted,name
        assert before==db.read_bytes(),name+' changed database'
        print('PASS',name)
    db.unlink()
    try:guard.inspect(root,package,'unused')
    except FileNotFoundError:pass
    else:raise AssertionError('missing DB accepted')
    print('PASS missing database fails closed')
