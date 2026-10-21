#!/usr/bin/env python3
"""Actual status entry: refresh observation metadata without rewriting cached job state."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
CLI=os.environ.get('CFIP_TEST_CLI',str(ROOT/'package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2'))
LIB=os.environ.get('CFIP_TEST_LIB_DIR',str(ROOT/'package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip'))
# Resolve before a case deliberately removes Bash and tar from child PATH.
BASH=shutil.which(os.environ.get('CFIP_TEST_BASH','bash'))
if not BASH: raise SystemExit('status metadata test requires an available Bash interpreter')
results=[];failures=[]
def snapshot(root):
    return {str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob('*') if p.is_file()}
with tempfile.TemporaryDirectory(prefix='cfip-status-metadata-') as directory:
    base=Path(directory);worker=base/'worker'
    worker.write_text(r'''source "$CFIP_TEST_CLI"
SCRIPT_VERSION=fixture-current; PACKAGE_RELEASE=fixture-release
CFIP_WORK_DIR="$CFIP_TEST_DEFAULT_WORK"
uci_get(){ printf '%s' "$CFIP_TEST_CONFIG_WORK"; }
cmd_status
''')
    for case in ['missing-cache','sparse-cache','stale-cache','custom-work-dir','missing-tar','missing-cfst-stale-version','corrupt-cache','array-cache']:
        root=base/case;root.mkdir();status=root/'status';status.mkdir();init=root/'init';init.mkdir()
        plugin=init/'passwall';plugin.write_text('#!/bin/sh\nprintf called >"$CFIP_TEST_INIT_EXECUTION"\nexit 23\n');plugin.chmod(0o755)
        work=root/'work';work.mkdir();configured=work
        if case=='custom-work-dir':
            configured=root/'configured-work';(configured/'cfst').mkdir(parents=True)
            binary=configured/'cfst/cfst';binary.write_text('#!/bin/sh\necho unexpected-execution >"$CFIP_TEST_EXECUTION"\n');binary.chmod(0o755)
            (configured/'cfst/cfst_version.txt').write_text('v2.3.5\n')
        if case=='missing-cfst-stale-version':
            (work/'cfst').mkdir()
            (work/'cfst/cfst_version.txt').write_text('v2.3.5\n')
        cached=status/'status.json'
        value={'schemaVersion':2,'running':False,'enabled':False,'active_run':False,'runId':'retained-run','requestId':'retained-request','phase':'idle','extra':{'keep':True}}
        if case in ['stale-cache','custom-work-dir','missing-tar']:
            value.update(script_version='cached-old',package_version='cached-old-release',env={'tar':True,'jq':False,'passwall_installed':False,'passwall_running':True,'openclash_running':True,'custom':'retained'})
        if case=='missing-cfst-stale-version':value['cfst_version']='v2.3.5'
        if case!='missing-cache':cached.write_text('{broken' if case=='corrupt-cache' else '[]' if case=='array-cache' else json.dumps(value))
        before=snapshot(root)
        env=dict(os.environ,CFIP_LIB_DIR=LIB,CFIP_STATUS_DIR=str(status),CFIP_RUNTIME_DIR=str(root/'runtime'),CFIP_INIT_DIR=str(init),CFIP_TEST_CLI=CLI,CFIP_TEST_DEFAULT_WORK=str(work),CFIP_TEST_CONFIG_WORK=str(configured),CFIP_TEST_EXECUTION=str(root/'unexpected-execution'),CFIP_TEST_INIT_EXECUTION=str(root/'unexpected-init-execution'))
        if case=='missing-tar':
            tools=base/'limited-bin';tools.mkdir(exist_ok=True)
            for name in ['jq','date']:
                p=tools/name
                if not p.exists():p.symlink_to(shutil.which(name))
            env['PATH']=str(tools)
        run=subprocess.run([BASH,str(worker)],env=env,capture_output=True,text=True,timeout=15)
        after=snapshot(root)
        try:
            assert before==after,'status query changed cached job or fixture files'
            if case in ['corrupt-cache','array-cache']:
                assert run.returncode!=0,'invalid cached job state was accepted'
            else:
                assert run.returncode==0,run.stderr
                data=json.loads(run.stdout)
                assert data['script_version']=='fixture-current' and data['package_version']=='fixture-current-rfixture-release'
                assert data['running'] is False and data['env']['jq'] is True
                assert data['env']['tar'] is (case!='missing-tar')
                assert data['env']['passwall_installed'] is True and data['env']['openclash_installed'] is False
                assert data['env']['passwall_running'] is None and data['env']['openclash_running'] is None,'old plugin running observation retained as fresh'
                assert data['env']['cfst_installed'] is (case=='custom-work-dir')
                if case=='custom-work-dir':assert data['cfst_version']=='v2.3.5'
                else:assert data['cfst_version'] is None,'last-known CFST version reported without installed binary'
                if case!='missing-cache':
                    assert data['runId']=='retained-run' and data['requestId']=='retained-request' and data['extra']=={'keep':True}
                if case in ['stale-cache','custom-work-dir','missing-tar']:assert data['env']['custom']=='retained'
            results.append(dict(case=case,status='PASS',returncode=run.returncode,cacheFilesUnchanged=True))
        except (AssertionError,ValueError,KeyError) as error:
            failures.append(dict(case=case,error=str(error),returncode=run.returncode,stdout=run.stdout[-2000:],stderr=run.stderr[-1000:]))
print(json.dumps(dict(status='FAIL' if failures else 'PASS',scope='actual cmd_status with controlled UCI/path observations; no cache writes or proxy service execution',results=results,failures=failures),indent=2))
raise SystemExit(bool(failures))
