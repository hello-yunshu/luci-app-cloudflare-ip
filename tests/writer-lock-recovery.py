#!/usr/bin/env python3
"""Deterministic stale-PID race in actual writer lock functions, no proxy actions."""
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import tempfile
import time
ROOT=Path(__file__).resolve().parents[1]
CLI=os.environ.get('CFIP_TEST_CLI',str(ROOT/'package/luci-app-cloudflare-ip/root/usr/bin/cf-ip-auto-v2'))
results=[];failures=[]
POSIX_SHELL=os.environ.get('CFIP_TEST_POSIX_SHELL',shutil.which('dash') or 'sh')
with tempfile.TemporaryDirectory(prefix='cfip-writer-lock-') as directory:
    root=Path(directory);runtime=root/'runtime';runtime.mkdir()
    lock=runtime/'cf-ip-auto-v2.lock';lock.mkdir();(lock/'pid').write_text('2147483000\n')
    worker=root/'worker'
    worker.write_text('''#!/usr/bin/env bash
source "$CFIP_TEST_CLI"
kill(){
 if [[ "$1" == -0 && "${2:-}" == 2147483000 ]]; then
  : >"$CFIP_TEST_ROOT/seen-$CFIP_TEST_ACTOR"
  for _ in {1..12}; do [[ ! -f "$CFIP_TEST_ROOT/release-$CFIP_TEST_ACTOR" ]] || break; sleep 1; done
 fi
 builtin kill "$@"
}
if acquire_lock; then
 printf '%s' "$$" >"$CFIP_TEST_ROOT/accepted-$CFIP_TEST_ACTOR"
 for _ in {1..15}; do [[ ! -f "$CFIP_TEST_ROOT/finish" ]] || break; sleep 1; done
 release_lock
else : >"$CFIP_TEST_ROOT/refused-$CFIP_TEST_ACTOR"; fi
''');worker.chmod(0o755)
    env=dict(os.environ,CFIP_TEST_CLI=CLI,CFIP_TEST_ROOT=str(root),CFIP_RUNTIME_DIR=str(runtime),CF_IP_RUNTIME_DIR=str(runtime),CFIP_LIB_DIR=str(ROOT/'package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip'),CFIP_LOG_FILE=str(root/'log'))
    processes=[]
    def launch(actor):
        p=subprocess.Popen(['bash',str(worker)],env=dict(env,CFIP_TEST_ACTOR=actor),stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True);processes.append(p);return p
    def wait_for(predicate,seconds=10):
        end=time.monotonic()+seconds
        while time.monotonic()<end:
            if predicate():return
            time.sleep(.05)
        raise AssertionError('fixture barrier timed out')
    try:
        a=launch('A');wait_for(lambda:(root/'seen-A').exists() or a.poll() is not None)
        b=launch('B');wait_for(lambda:(root/'seen-B').exists() or b.poll() is not None)
        (root/'release-A').touch()
        wait_for(lambda:(root/'accepted-A').exists() or a.poll() is not None)
        (root/'release-B').touch()
        wait_for(lambda:(root/'accepted-B').exists() or b.poll() is not None)
        admitted=[p.name for p in root.glob('accepted-*')]
        try:
            assert len(admitted)==1,dict(admitted=admitted,currentPid=(lock/'pid').read_text())
            results.append(dict(case='simultaneous stale PID recovery has one writer',status='PASS',admitted=admitted))
        except AssertionError as error:failures.append(dict(case='simultaneous stale PID recovery',error=str(error)))
    finally:
        (root/'finish').touch();(root/'release-A').touch();(root/'release-B').touch()
        for p in processes:
            try:p.communicate(timeout=5)
            except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGTERM);p.communicate(timeout=3)
    # A failed owner-PID write must never be accepted as a successful lock.
    if lock.exists():
        for p in lock.iterdir():p.unlink()
        lock.rmdir()
    faulty=root/'faulty'
    faulty.write_text('''#!/usr/bin/env bash
source "$CFIP_TEST_CLI"
mkdir(){
 command mkdir "$@" || return $?
 if [[ "${*: -1}" == "$CFIP_LOCK_DIR" ]]; then command mkdir "$CFIP_LOCK_DIR/pid"; fi
}
if acquire_lock; then printf accepted; else printf refused; fi
''');faulty.chmod(0o755)
    run=subprocess.run(['bash',str(faulty)],env=env,capture_output=True,text=True,timeout=8)
    if run.stdout=='refused':results.append(dict(case='failed owner PID write refuses writer',status='PASS'))
    else:failures.append(dict(case='failed owner PID write',stdout=run.stdout,stderr=run.stderr))
    actor=root/'actor'
    actor.write_text('''#!/usr/bin/env bash
case "$CFIP_TEST_ENTRY" in
 cli) . "$CFIP_TEST_CLI" ;;
 init) . "$CFIP_TEST_INIT"; acquire_lock(){ cf_ip_shared_lock_acquire; }; release_lock(){ cf_ip_shared_lock_release; } ;;
 rpc) set -- __source_only__; . "$CFIP_TEST_RPC"; acquire_lock(){ cf_ip_rpc_lock_acquire; }; release_lock(){ cf_ip_rpc_lock_release; } ;;
esac
if acquire_lock; then printf 'accepted'; release_lock; else printf 'refused'; fi
''');actor.chmod(0o755)
    def run_actor(path,kind='cli',shell='bash',**extra):
        path.mkdir(exist_ok=True)
        return subprocess.run([shell,str(actor)],env=dict(env,CFIP_TEST_ENTRY=kind,CFIP_TEST_INIT=str(ROOT/'package/luci-app-cloudflare-ip/root/etc/init.d/cf_ip'),CFIP_TEST_RPC=str(ROOT/'package/luci-app-cloudflare-ip/root/usr/libexec/rpcd/cf_ip'),CFIP_RUNTIME_DIR=str(path),CF_IP_RUNTIME_DIR=str(path),**extra),capture_output=True,text=True,timeout=8)
    def check(name,fn):
        try:fn();results.append(dict(case=name,status='PASS'))
        except (AssertionError,subprocess.TimeoutExpired) as error:failures.append(dict(case=name,error=str(error)))
    def recover(kind,shell):
        path=root/('recover-'+kind);path.mkdir();owned=path/'cf-ip-auto-v2.lock';owned.mkdir();(owned/'pid').write_text('2147483000\n')
        first=run_actor(path,kind,shell)
        assert first.stdout=='accepted',(first.stdout,first.stderr)
        assert not owned.exists(),'release retained PID directory'
        inode=(path/'.cf-ip-writer-gate').stat().st_ino
        again=run_actor(path,kind,shell)
        assert again.stdout=='accepted',(again.stdout,again.stderr)
        assert (path/'.cf-ip-writer-gate').stat().st_ino==inode,'gate inode was replaced'
    for kind,shell in [('cli','bash'),('init',POSIX_SHELL),('rpc',POSIX_SHELL)]:check(kind+' stale recovery, release and stable gate inode',lambda kind=kind,shell=shell:recover(kind,shell))
    def rejected(name,pid=None,unknown=False,symlink=False,missing_tool=False):
        path=root/name;path.mkdir();owned=path/'cf-ip-auto-v2.lock'
        if pid is not None:
            owned.mkdir();(owned/'pid').write_text(pid)
            if unknown:(owned/'user-data').write_text('retained')
        marker=path/'outside';marker.write_text('outside retained')
        if symlink:(path/'.cf-ip-writer-gate').symlink_to(marker)
        extra=dict(CFIP_FLOCK=str(path/'missing-flock')) if missing_tool else {}
        run=run_actor(path,**extra)
        assert run.stdout=='refused',(run.stdout,run.stderr)
        if pid is not None:assert (owned/'pid').read_text()==pid,'refusal changed PID metadata'
        if unknown:assert (owned/'user-data').read_text()=='retained'
        assert marker.read_text()=='outside retained'
    for name,pid in [('live-owner',str(os.getpid())),('zero-owner','0'),('malformed-owner','1;false'),('negative-owner','-1')]:check(name+' preserved',lambda name=name,pid=pid:rejected(name,pid))
    check('unknown stale-lock payload preserved',lambda:rejected('unknown-data','2147483000',unknown=True))
    check('symlink gate refused without target modification',lambda:rejected('symlink-gate',symlink=True))
    check('missing flock refuses writer',lambda:rejected('missing-tool',missing_tool=True))
    def killed_gate():
        path=root/'killed-gate';path.mkdir()
        holder=root/'gate-holder'
        holder.write_text('''#!/usr/bin/env bash
source "$CFIP_LIB_DIR/writer-lock.sh"
_cf_ip_writer_gate_enter "$CFIP_RUNTIME_DIR" || exit 1
: >"$CFIP_RUNTIME_DIR/held"
sleep 20
''');holder.chmod(0o755)
        p=subprocess.Popen(['bash',str(holder)],env=dict(env,CFIP_RUNTIME_DIR=str(path)),stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
        try:
            wait_for(lambda:(path/'held').exists() or p.poll() is not None)
            assert (path/'held').exists(),'gate holder failed'
            inode=(path/'.cf-ip-writer-gate').stat().st_ino
            os.killpg(p.pid,signal.SIGKILL);p.communicate(timeout=3)
            run=run_actor(path)
            assert run.stdout=='accepted',(run.stdout,run.stderr)
            assert (path/'.cf-ip-writer-gate').stat().st_ino==inode,'KILL recovery replaced gate inode'
        finally:
            if p.poll() is None:os.killpg(p.pid,signal.SIGKILL);p.communicate(timeout=3)
    check('KILL releases actual kernel gate without replacing its inode',killed_gate)
    def partial_pid_write():
        path=root/'partial-pid';path.mkdir()
        partial=root/'partial'
        partial.write_text('''#!/usr/bin/env bash
source "$CFIP_TEST_CLI"
printf(){
 if [[ "${2:-}" == "$$" ]]; then builtin printf '%s' partial; return 23; fi
 builtin printf "$@"
}
if acquire_lock; then builtin printf bad; exit 1; fi
[[ ! -e "$CFIP_LOCK_DIR" ]] || exit 2
unset -f printf
if acquire_lock; then builtin printf recovered; release_lock; else exit 3; fi
''');partial.chmod(0o755)
        run=subprocess.run(['bash',str(partial)],env=dict(env,CFIP_RUNTIME_DIR=str(path),CF_IP_RUNTIME_DIR=str(path)),capture_output=True,text=True,timeout=8)
        assert run.returncode==0 and run.stdout=='recovered',(run.returncode,run.stdout,run.stderr)
    check('partial owner PID write is refused, cleaned and retryable',partial_pid_write)

    def failed_tool():
        path=root/'failed-tool';path.mkdir()
        broken=root/'broken-flock';broken.write_text('#!/bin/sh\nexit 23\n');broken.chmod(0o755)
        code='source "$CFIP_TEST_CLI"; if acquire_lock; then exit 1; else printf "%s:%s" "$CF_IP_WRITER_LOCK_ERROR" "$CF_IP_WRITER_LOCK_RC"; fi'
        run=subprocess.run(['bash','-c',code],env=dict(env,CFIP_RUNTIME_DIR=str(path),CF_IP_RUNTIME_DIR=str(path),CFIP_FLOCK=str(broken)),capture_output=True,text=True,timeout=8)
        assert run.stdout=='flock_failed:23',(run.stdout,run.stderr)
        assert not (path/'cf-ip-auto-v2.lock').exists(),'failed gate tool admitted PID namespace'
    check('kernel tool failure is distinct from contention and retains exit code',failed_tool)
    print(json.dumps(dict(status='FAIL' if failures else 'PASS',scope='actual lock acquisition with controlled PID-check scheduling and PID-write fault',results=results,failures=failures),indent=2))
    raise SystemExit(bool(failures))
