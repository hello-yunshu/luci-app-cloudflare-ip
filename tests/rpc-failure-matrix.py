#!/usr/bin/env python3
"""Execute the actual RPC shim against a failing backend; no rpcd ACL proof."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
RPC = Path(os.environ.get('CFIP_TEST_RPC', ROOT/'package/luci-app-cloudflare-ip/root/usr/libexec/rpcd/cf_ip'))
METHODS = ['status','validate-config','check-env','refresh-env','speedtest-status','read-log','clear-log','ip-history','download-cfst','source-status','source-registry','source-refresh','publisher-status','adaptive-status','rill-self-check','rill-diagnostics','rill-reset','self-update','sync','oc-list-backups','oc-restore-backup','oc-delete-backup']
failures = []
with tempfile.TemporaryDirectory(prefix='cfip-rpc-failure-') as directory:
    tmp = Path(directory)
    backend = tmp/'backend'
    backend.write_text('#!/bin/sh\nif [ "$1" = --read-log ] && [ -n "${RPC_TEST_LOG_RESPONSE+x}" ]; then printf "%s\\n" "$RPC_TEST_LOG_RESPONSE"; exit "$RPC_TEST_LOG_RC"; fi\nprintf "%s\\n" "$RPC_TEST_RESPONSE"\nexit "$RPC_TEST_RC"\n')
    backend.chmod(0o755)
    # Controlled parser fixture only; native jsonfilter/rpcd/ACL remains separate.
    parser = tmp/'jsonfilter'
    parser.write_text('''#!/bin/sh
while [ "$#" -gt 0 ]; do
 case "$1" in -s) input="$2"; shift 2 ;; -e) expr="$2"; shift 2 ;; *) shift ;; esac
done
printf '%s' "$input" | jq -r "${expr#\\$} // empty"
''')
    parser.chmod(0o755)
    env = dict(os.environ, PATH=str(tmp)+os.pathsep+os.environ['PATH'], CF_IP_AUTO_BIN=str(backend))
    request = json.dumps(dict(candidate={},plugin='openclash',id='20260827120000',expectedGeneration='fixture'))+'\n'
    for response, rc, expected in [('{"success":true,"detail":"retained"}',7,False), ('{"success":false,"error":"specific failure","detail":"retained"}',9,False), ('not-json',0,False), ('[]',0,False), ('{}\n{}',0,False), ('{"success":true,"detail":"retained"}',0,True)]:
        for method in METHODS:
            run = subprocess.run(['sh',str(RPC),'call',method],input=request,text=True,capture_output=True,env=dict(env,RPC_TEST_RESPONSE=response,RPC_TEST_RC=str(rc)),timeout=8)
            try:
                result = json.loads(run.stdout)
                assert isinstance(result,dict) and result.get('success') is expected, result
                if rc:
                    assert result.get('rc')==rc, result
                    assert result.get('detail')=='retained', result
                    if 'specific failure' in response: assert result.get('error')=='specific failure',result
            except (ValueError, AssertionError) as error:
                failures.append(dict(method=method,backendExit=rc,response=response,stdout=run.stdout,error=str(error)))
    run = subprocess.run(['sh',str(RPC),'call','speedtest-status'],text=True,capture_output=True,env=dict(env,RPC_TEST_RESPONSE='{"success":true}',RPC_TEST_RC='0',RPC_TEST_LOG_RESPONSE='{"success":true,"detail":"log failure"}',RPC_TEST_LOG_RC='7'),timeout=8)
    try:
        result = json.loads(run.stdout)
        assert result.get('success') is True and result['log_data']['success'] is False and result['log_data']['rc']==7,result
    except (ValueError,AssertionError,KeyError) as error:
        failures.append(dict(method='speedtest-status',phase='independent-log-failure',stdout=run.stdout,error=str(error)))
    uci = tmp/'uci'
    uci.write_text('''#!/bin/sh
printf '%s\\n' "$*" >>"$RPC_UCI_CALLS"
if [ "$1" = "$RPC_UCI_FAIL" ]; then exit 23; fi
case "$*" in *get*) printf 0 ;; esac
exit 0
''')
    uci.chmod(0o755)
    init = tmp/'init'
    init.write_text('''#!/bin/sh
printf '%s\\n' "$*" >>"$RPC_INIT_CALLS"
# Exit immediately so a broken shim cannot spend four seconds on readiness.
exit 17
''')
    init.chmod(0o755)
    lifecycle_cases = 0
    for action in ('start','stop','restart'):
        for phase in ('set','commit'):
            calls = tmp/'init-calls'
            calls.unlink(missing_ok=True)
            run = subprocess.run(['sh',str(RPC),'call',action],text=True,capture_output=True,env=dict(env,INIT_SCRIPT=str(init),CF_IP_RUNTIME_DIR=str(tmp/'runtime'),RPC_UCI_FAIL=phase,RPC_UCI_CALLS=str(tmp/'uci-calls'),RPC_INIT_CALLS=str(calls)),timeout=8)
            lifecycle_cases += 1
            try:
                result = json.loads(run.stdout)
                assert result.get('success') is False and result.get('error')=='uci_'+phase+'_failed' and result.get('rc')==23,result
                assert not calls.exists(),'init invoked after failed configuration mutation'
                assert not (tmp/'runtime/cf-ip-auto-v2.lock').exists(),'failed action retained shared lock'
            except (ValueError,AssertionError) as error:
                failures.append(dict(method=action,phase=phase,stdout=run.stdout,error=str(error)))
    for action in ('start','restart'):
        calls = tmp/'init-calls'
        calls.unlink(missing_ok=True)
        run = subprocess.run(['sh',str(RPC),'call',action],text=True,capture_output=True,env=dict(env,INIT_SCRIPT=str(init),CF_IP_RUNTIME_DIR=str(tmp/'runtime'),RPC_UCI_FAIL='none',RPC_UCI_CALLS=str(tmp/'uci-calls'),RPC_INIT_CALLS=str(calls)),timeout=8)
        lifecycle_cases += 1
        try:
            result = json.loads(run.stdout)
            assert result.get('success') is False and result.get('error')=='init_enable_failed' and result.get('rc')==17,result
            assert calls.read_text().splitlines()==['enable'],'lifecycle action invoked after failed init enable'
        except (ValueError,AssertionError) as error:
            failures.append(dict(method=action,phase='enable',stdout=run.stdout,error=str(error)))
    print(json.dumps(dict(status='FAIL' if failures else 'PASS',scope='actual shell RPC dispatcher with fixture backend/parser',methods=len(METHODS),cases=len(METHODS)*6,independentLogCases=1,lifecycleCases=lifecycle_cases,failures=failures),indent=2))
    raise SystemExit(bool(failures))
