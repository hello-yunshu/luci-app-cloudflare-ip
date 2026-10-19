#!/usr/bin/env python3
"""Actual RPC + actual run lock/start ordering; config/context are isolated fixtures."""
import concurrent.futures
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

ROOT=Path(__file__).resolve().parents[1]
RPC=Path(os.environ.get('CFIP_TEST_RPC',ROOT/'package/luci-app-cloudflare-ip/root/usr/libexec/rpcd/cf_ip'))
failures=[];results=[];processes=[]
RPC_SHELL=os.environ.get('CFIP_TEST_RPC_SHELL','sh')
with tempfile.TemporaryDirectory(prefix='cfip-rpc-run-') as directory:
    tmp=Path(directory); runtime=tmp/'runtime';runtime.mkdir()
    (tmp/'pids').mkdir()
    backend=tmp/'backend'
    backend.write_text('''#!/usr/bin/env bash
printf '%s' "$$" >"$CFIP_TEST_PIDS/$$"
source "$CFIP_TEST_CLI"
load_config(){
 if [[ "$CFIP_TEST_MODE" == invalid ]]; then cfip_json_error 'fixture configuration rejected'; return 23; fi
 [[ "$CFIP_TEST_MODE" != slow ]] || sleep 3
}
reconcile_committed_context(){
 printf '%s' "$$" >"$CFIP_TEST_MARKER"
 for _ in {1..15}; do [[ ! -f "$CFIP_TEST_RELEASE" ]] || break; sleep 1; done
 return 1
}
run_v2
''')
    backend.chmod(0o755)
    env=dict(os.environ,CF_IP_AUTO_BIN=str(backend),CF_IP_RUNTIME_DIR=str(runtime),CFIP_RUNTIME_DIR=str(runtime),CFIP_LIB_DIR=str(ROOT/'package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip'),CFIP_TEST_CLI=os.environ.get('CFIP_TEST_CLI',str(ROOT/'package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2')),CFIP_STATUS_DIR=str(tmp/'state'),CFIP_LOG_FILE=str(tmp/'log'),CFIP_TEST_MODE='valid',CFIP_TEST_MARKER=str(tmp/'marker'),CFIP_TEST_RELEASE=str(tmp/'release'),CFIP_TEST_PIDS=str(tmp/'pids'))
    lock=runtime/'cf-ip-auto-v2.lock'
    def call(**extra):
        started=time.monotonic()
        process=subprocess.Popen([RPC_SHELL,str(RPC),'call','run'],env=dict(env,**extra),stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
        processes.append(process)
        try:stdout,_=process.communicate(timeout=12)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid,signal.SIGTERM);process.communicate(timeout=3);raise
        return json.loads(stdout),time.monotonic()-started
    def check(name,fn):
        try: fn();results.append(dict(case=name,status='PASS'))
        except (AssertionError,ValueError,subprocess.TimeoutExpired) as error: failures.append(dict(case=name,error=str(error)))
    def rejected_config():
        result,_=call(CFIP_TEST_MODE='invalid')
        assert result.get('success') is False and 'fixture configuration rejected' in result.get('error',''),result
    def missing_backend():
        result,_=call(CF_IP_AUTO_BIN=str(tmp/'missing-backend'))
        assert result.get('success') is False,result
    def held_lock():
        lock.mkdir(exist_ok=True);(lock/'pid').write_text(str(os.getpid()))
        try:
            result,_=call()
            assert result.get('success') is False,result
            assert not (tmp/'marker').exists(),'contending run reached context mutation'
        finally:
            (lock/'pid').unlink(missing_ok=True);lock.rmdir()
    def parallel_start():
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            runs=list(pool.map(lambda _:call(),range(8)))
        accepted=[result for result,_ in runs if result.get('success') is True]
        assert len(accepted)==1,accepted
        answer=accepted[0]
        assert answer.get('acknowledged') is True and answer.get('accepted') is True,answer
        assert (lock/'pid').read_text().strip()==str(answer['pid']),answer
        assert max(elapsed for _,elapsed in runs)<10,runs
        assert not list(runtime.glob('rpc-run.*')),'startup IPC directory leaked after replies'
    def no_protocol():
        old=tmp/'old-backend'
        old.write_text('''#!/bin/sh
printf '%s\n' '{"success":true}'
''')
        old.chmod(0o755)
        result,_=call(CF_IP_AUTO_BIN=str(old))
        assert result.get('success') is False and result.get('unconfirmed') is True and result.get('accepted') is None and result.get('running') is None,result
    def malformed_protocol():
        malformed=tmp/'malformed-backend'
        malformed.write_text('''#!/usr/bin/env bash
reply="$(jq -cn --arg requestId "$CFIP_RUN_REQUEST_ID" --argjson pid "$$" '{success:true,action:"run",running:true,runId:"fixture-run",acknowledged:true,accepted:true,requestId:$requestId,pid:$pid}')"
case "$RPC_BAD_ACK" in
 incomplete) printf '%s\\n' "$reply" | jq -c 'del(.action,.running)' >&3 ;;
 multi) printf '%s%s\\n' "$reply" "$reply" >&3 ;;
 oversized) { printf '%s' "$reply"; head -c 20000 /dev/zero | tr '\\000' ' '; printf '\\n'; } >&3 ;;
 wrong-id) printf '%s\\n' '{"success":true,"action":"run","running":true,"runId":"fixture-run","accepted":true,"acknowledged":true,"pid":123,"requestId":"wrong"}' >&3 ;;
esac
''')
        malformed.chmod(0o755)
        for mode in ('multi','oversized','wrong-id','incomplete'):
            result,_=call(CF_IP_AUTO_BIN=str(malformed),RPC_BAD_ACK=mode)
            assert result.get('success') is False and result.get('unconfirmed') is True,(mode,result)
    def channel_failure():
        tools=tmp/'tools';tools.mkdir()
        broken=tools/'bash';broken.write_text('#!/bin/sh\nexit 23\n');broken.chmod(0o755)
        channel=tmp/'channel-runtime'
        result,_=call(PATH=str(tools)+os.pathsep+env['PATH'],CF_IP_RUNTIME_DIR=str(channel))
        assert result.get('success') is False and result.get('error')=='startup_channel_failed',result
        assert not list(channel.glob('rpc-run.*')),'failed channel helper leaked startup directory'
        assert not (tmp/'marker').exists(),'failed channel reached context mutation'
    def startup_timeout():
        slow=tmp/'slow-runtime';slow.mkdir()
        started=time.monotonic()
        result,elapsed=call(CFIP_TEST_MODE='slow',CFIP_RPC_RUN_WAIT_SECONDS='1',CF_IP_RUNTIME_DIR=str(slow),CFIP_TEST_MARKER=str(tmp/'slow-marker'))
        assert result.get('success') is False and result.get('unconfirmed') is True and result.get('accepted') is None and result.get('running') is None,result
        assert elapsed<3,elapsed
        # Both fixture config reads sleep three seconds. Wait past the attempted
        # acknowledgement; a closed reader must prevent context mutation.
        while time.monotonic()-started<7:time.sleep(.1)
        assert not (tmp/'slow-marker').exists(),'timed-out startup reached context mutation'
        assert not (slow/'cf-ip-auto-v2.lock').exists(),'timed-out startup leaked the run lock'
        assert not list(slow.glob('run-*')),'timed-out startup allocated run payload directories'
        assert not list(slow.glob('rpc-run.*')),'timed-out startup leaked IPC directory'
    try:
        check('invalid configuration is reported before running success',rejected_config)
        check('missing backend cannot report running success',missing_backend)
        check('configured shared lock rejects RPC run',held_lock)
        check('backend without acknowledgement cannot report running success',no_protocol)
        check('malformed, oversized and mismatched acknowledgements are rejected',malformed_protocol)
        check('startup channel helper failure refuses run without scratch',channel_failure)
        check('bounded timeout prevents delayed context mutation',startup_timeout)
        check('eight concurrent RPCs admit one acknowledged lock owner',parallel_start)
    finally:
        (tmp/'release').touch()
        time.sleep(2) # allow already-launched fixture children to consume release
        for record in (tmp/'pids').iterdir():
            pid=int(record.name)
            try:
                group=os.getpgid(pid)
                command=subprocess.check_output(['ps','-p',str(pid),'-o','command='],text=True).strip()
                if group in {p.pid for p in processes} and str(backend) in command:
                    os.killpg(group,signal.SIGTERM)
            except (ProcessLookupError,subprocess.CalledProcessError):pass
    print(json.dumps(dict(status='FAIL' if failures else 'PASS',scope='actual shell RPC and CLI run/lock/start ordering with fixture config/context',results=results,failures=failures),indent=2))
    raise SystemExit(bool(failures))
