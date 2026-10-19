#!/usr/bin/env python3
"""Actual RPC/run entry/status serializer; config/context/health are fixtures."""
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

ROOT=Path(__file__).resolve().parents[1]
RPC=Path(os.environ.get('CFIP_TEST_RPC',ROOT/'package/luci-app-cloudflare-ip/root/usr/libexec/rpcd/cf_ip'))
CLI=os.environ.get('CFIP_TEST_CLI',str(ROOT/'package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2'))
results=[];failures=[]
with tempfile.TemporaryDirectory(prefix='cfip-early-status-') as directory:
    base=Path(directory)
    backend=base/'backend'
    backend.write_text('''#!/usr/bin/env bash
source "$CFIP_TEST_CLI"
load_config(){ CFIP_MODE="$CFIP_TEST_PROXY"; CFIP_ENABLED=true; CFIP_WORK_DIR="$CFIP_TEST_ROOT/work"; CFIP_OPENCLASH_CONFIG="$CFIP_TEST_ROOT/config.yaml"; return 0; }
cfip_publisher_status_json(){ printf '%s\\n' '{"success":false,"state":"disabled"}'; }
if [[ "${1:-}" == --status ]]; then load_config; cmd_status; exit; fi
reconcile_committed_context(){
 printf '%s' "$$" >"$CFIP_TEST_ROOT/context-pid"
 case "$CFIP_TEST_CASE" in
  external) printf '%s\\n' '{"runId":"external","active_run":false,"last_result":"success","external":"preserve"}' >"$CFIP_STATUS_FILE" ;;
  lost-lock) printf '%s' "$CFIP_TEST_FOREIGN_PID" >"$CFIP_LOCK_DIR/pid" ;;
  symlink) rm -f "$CFIP_STATUS_FILE"; ln -s "$CFIP_TEST_ROOT/user-marker" "$CFIP_STATUS_FILE" ;;
  active) write_status true preflight running '' ;;
  completed) write_status false done success '' ;;
  failed) write_status false failed error 'specific terminal failure' ;;
  failed-recovery) write_status false failed error 'specific terminal failure'; CFIP_RECOVERY_ERROR='fixture recovery failure' ;;
  signal) kill -TERM "$$" ;;
  raw-exit) exit 31 ;;
 esac
 CFIP_ERROR='fixture context failure'
 return 17
}
run_v2
''')
    backend.chmod(0o755)
    for proxy in ('passwall','openclash'):
        for scenario in ('failure','missing','active','raw-exit','signal','external','symlink','completed','failed','failed-recovery','lost-lock','initial-symlink','snapshot-failed'):
            root=base/(proxy+'-'+scenario);(root/'state').mkdir(parents=True);(root/'runtime').mkdir();(root/'init').mkdir()
            status=root/'state/status.json';user=root/'user-marker';user.write_text('{"user":"retained"}\n')
            old=dict(schemaVersion=2,runId='old-run',active_run=False,last_result='success',best_ips=['104.18.1.1'],last_completed_run_at='2026-10-01T00:00:00Z')
            if scenario!='missing':status.write_text(json.dumps(old)+'\n')
            (root/'config.yaml').write_text('proxies: []\n')
            (root/'config.yaml.bak.20261001000000').write_text('retained backup\n')
            (root/'state/run-history.ndjson').write_text('{"runId":"retained-history"}\n')
            files=[user,root/'config.yaml',root/'config.yaml.bak.20261001000000',root/'state/run-history.ndjson']
            def user_files():return {str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
            user_before=user_files()
            user_hash=hashlib.sha256(user.read_bytes()).hexdigest()
            env=dict({k:v for k,v in os.environ.items() if not k.startswith(('CFIP_','CF_IP_'))},CF_IP_AUTO_BIN=str(backend),CFIP_TEST_CLI=CLI,CFIP_TEST_PROXY=proxy,CFIP_TEST_CASE=scenario,CFIP_TEST_ROOT=str(root),CFIP_TEST_FOREIGN_PID=str(os.getpid()),CFIP_STATUS_DIR=str(root/'state'),CFIP_RUNTIME_DIR=str(root/'runtime'),CF_IP_RUNTIME_DIR=str(root/'runtime'),CFIP_INIT_DIR=str(root/'init'),CFIP_LOG_FILE=str(root/'log'),CFIP_LIB_DIR=str(ROOT/'package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip'))
            precondition=scenario in ('initial-symlink','snapshot-failed')
            if scenario=='initial-symlink':status.unlink();status.symlink_to(user)
            if scenario=='snapshot-failed':
                tools=root/'tools';tools.mkdir()
                bad=tools/'sha256sum';bad.write_text('#!/bin/sh\nexit 23\n');bad.chmod(0o755)
                env['PATH']=str(tools)+os.pathsep+env['PATH']
            previous=status.read_bytes() if (precondition or scenario=='lost-lock') else None
            process=None
            try:
                process=subprocess.Popen(['sh',str(RPC),'call','run'],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
                stdout,stderr=process.communicate(timeout=12)
                started=json.loads(stdout)
                proof=dict(startup=started,userBeforeSha256=user_hash,userFilesBeforeSha256=user_before)
                if precondition:
                    assert started.get('success') is False and 'capture previous task status' in started.get('error',''),started
                    assert not (root/'context-pid').exists(),'failed snapshot entered context mutation'
                    assert not (root/'runtime/cf-ip-auto-v2.lock').exists(),'failed snapshot retained shared lock'
                    assert status.read_bytes()==previous,'failed snapshot changed previous bytes'
                    if scenario=='initial-symlink':assert status.is_symlink(),'initial foreign symlink replaced'
                    assert hashlib.sha256(user.read_bytes()).hexdigest()==user_hash and user_files()==user_before,'user data changed'
                    proof.update(userAfterSha256=hashlib.sha256(user.read_bytes()).hexdigest(),userFilesAfterSha256=user_files(),statusUnchanged=True)
                    results.append(dict(proxy=proxy,case=scenario,status='PASS',proof=proof))
                    continue
                assert started.get('success') is True and started.get('acknowledged') is True,started
                deadline=time.monotonic()+10
                while time.monotonic()<deadline:
                    if scenario=='lost-lock':
                        if (root/'log').exists() and 'lost writer lock' in (root/'log').read_text():break
                    elif (root/'context-pid').exists() and not (root/'runtime/cf-ip-auto-v2.lock').exists():break
                    time.sleep(.05)
                if scenario=='lost-lock':
                    assert (root/'runtime/cf-ip-auto-v2.lock/pid').read_text()==str(os.getpid()),'foreign lock owner removed'
                    assert status.read_bytes()==previous,'lost owner replaced task status'
                    assert hashlib.sha256(user.read_bytes()).hexdigest()==user_hash and user_files()==user_before,'user data changed'
                    proof.update(userAfterSha256=hashlib.sha256(user.read_bytes()).hexdigest(),userFilesAfterSha256=user_files(),statusUnchanged=True,foreignLockOwner=os.getpid())
                    results.append(dict(proxy=proxy,case=scenario,status='PASS',proof=proof))
                    continue
                assert not (root/'runtime/cf-ip-auto-v2.lock').exists(),'failure retained the shared lock'
                if scenario=='symlink':
                    assert status.is_symlink() and status.readlink()==user,'foreign symlink replaced'
                    proof['preservedSymlink']=str(status.readlink())
                else:
                    observed=json.loads(subprocess.check_output(['sh',str(RPC),'call','status'],env=env,text=True,timeout=5))
                    proof['observed']={key:observed.get(key) for key in ('runId','requestId','active_run','last_result','error','recovery','external') if key in observed}
                    if scenario=='external':assert observed.get('external')=='preserve' and observed['runId']=='external',observed
                    else:
                        assert observed.get('last_result')=='error' and observed.get('active_run') is False,observed
                        assert observed.get('runId') not in ('',None,'old-run'),observed
                        assert observed.get('runId')==started.get('runId'),(started,observed)
                        assert observed.get('requestId')==started.get('requestId'),(started,observed)
                        if scenario=='failed':assert observed.get('error')=='specific terminal failure',observed
                        elif scenario=='failed-recovery':
                            assert 'specific terminal failure' in observed.get('error','') and 'fixture recovery failure' in observed.get('error',''),observed
                            assert observed.get('recovery',{}).get('error')=='fixture recovery failure',observed
                        elif scenario not in ('raw-exit','signal'):assert 'fixture context failure' in observed.get('error',''),observed
                assert hashlib.sha256(user.read_bytes()).hexdigest()==user_hash and user_files()==user_before,'user data changed'
                proof['userAfterSha256']=hashlib.sha256(user.read_bytes()).hexdigest()
                proof['userFilesAfterSha256']=user_files()
                results.append(dict(proxy=proxy,case=scenario,status='PASS',proof=proof))
            except (AssertionError,ValueError,subprocess.TimeoutExpired,subprocess.CalledProcessError) as error:
                failures.append(dict(proxy=proxy,case=scenario,error=str(error)))
            finally:
                pidfile=root/'context-pid'
                if process is not None and pidfile.exists():
                    pid=int(pidfile.read_text())
                    try:
                        if os.getpgid(pid)==process.pid and str(backend) in subprocess.check_output(['ps','-p',str(pid),'-o','command='],text=True):os.killpg(process.pid,signal.SIGTERM)
                    except (ProcessLookupError,subprocess.CalledProcessError):pass
    print(json.dumps(dict(status='FAIL' if failures else 'PASS',scope='actual RPC, CLI run/cleanup and status serializer with fixture config/context/health',results=results,failures=failures),indent=2))
    raise SystemExit(bool(failures))
