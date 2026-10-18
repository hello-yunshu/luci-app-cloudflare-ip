#!/usr/bin/env python3
"""Actual local HTTP/curl readback, with init mocked; no LAN/procd qualification."""
import http.server
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
ROOT = Path(__file__).resolve().parents[1]
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def do_GET(self):
        self.send_response(500 if self.server.mode=='http-error' else 200); self.end_headers()
        try:
            if self.server.mode=='slow': time.sleep(2)
            if self.server.mode == 'stale' or (self.server.mode=='root-stale' and not self.path.startswith('/generations/')): body=b'{"runId":"stale"}'
            elif self.server.mode == 'oversized': body=b'x'*100000
            else: body=(self.server.directory/self.path.lstrip('/')).read_bytes()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError): pass
with tempfile.TemporaryDirectory(prefix='cfip-publisher-http-') as d:
    tmp=Path(d); (tmp/'runtime').mkdir()
    init=tmp/'init';init.write_text('#!/bin/sh\nexit 0\n');init.chmod(0o755)
    selected=tmp/'selected.json';selected.write_text('[{"ip":"104.18.1.1","family":"ipv4"}]')
    server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);server.daemon_threads=True;server.directory=tmp/'publish'
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    script='''set -euo pipefail
source "$CFIP_COMMON"
source "$CFIP_PUBLISHER"
cfip_publish_result "$CFIP_SELECTED"
'''
    env=dict(os.environ,CFIP_COMMON=str(ROOT/'package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh'),CFIP_PUBLISHER=os.environ.get('CFIP_TEST_PUBLISHER',str(ROOT/'package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/publisher.sh')),CFIP_SELECTED=str(selected),CFIP_RUNTIME_DIR=str(tmp/'runtime'),CFIP_PUBLISH_DIR=str(tmp/'publish'),CFIP_PUBLISH_STATUS_FILE=str(tmp/'status.json'),CFIP_PUBLISH_INIT=str(init),CFIP_PUBLISH_ENABLED='true',CFIP_PUBLISH_BIND='127.0.0.1',CFIP_PUBLISH_PORT=str(server.server_port),CFIP_PUBLISH_READY_ATTEMPTS='1',CFIP_RUN_ID='actual-http-test',http_proxy='http://127.0.0.1:1',all_proxy='http://127.0.0.1:1',NO_PROXY='',no_proxy='')
    results=[]
    try:
        for mode in ('valid','root-stale','stale','oversized','http-error','slow'):
            server.mode=mode
            before={name:(tmp/'publish'/name).read_bytes() for name in ('ip.txt','best-ipv4.txt','best-ipv6.txt','result.json')} if (tmp/'publish/result.json').exists() else None
            run=subprocess.run(['bash','-c',script],env=env,capture_output=True,text=True,timeout=10)
            status=json.loads((tmp/'status.json').read_text())
            if mode=='valid': assert run.returncode==0 and status['success'],(mode,run.stderr,status)
            else:
                assert run.returncode!=0 and not status['success'],f'{mode}: init exit 0 was incorrectly treated as readiness: {status}'
                assert before=={name:(tmp/'publish'/name).read_bytes() for name in before},'failed publication changed public bytes'
            assert not list((tmp/'runtime').glob('publisher-readback.*')), 'readback temporary file leaked'
            if mode=='valid':
                saved=(tmp/'status.json').read_bytes()
                query_script='source "$CFIP_COMMON"; source "$CFIP_PUBLISHER"; cfip_publisher_status_json'
                for check_mode in ('valid','stale','valid'):
                    server.mode=check_mode
                    query=subprocess.run(['bash','-c',query_script],env=env,capture_output=True,text=True,timeout=5)
                    queried=json.loads(query.stdout)
                    assert queried['success']==(check_mode=='valid'),queried
                    assert (tmp/'status.json').read_bytes()==saved,'status query rewrote stored observation'
                other=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);other.daemon_threads=True
                other.directory=tmp/'publish';other.mode='valid'
                threading.Thread(target=other.serve_forever,daemon=True).start()
                try:
                    server.mode='stale'
                    query=subprocess.run(['bash','-c',query_script],env=dict(env,CFIP_PUBLISH_PORT=str(other.server_port)),capture_output=True,text=True,timeout=5)
                    queried=json.loads(query.stdout)
                    assert queried['success'] and queried['port']==other.server_port,queried
                    assert (tmp/'status.json').read_bytes()==saved
                    results.append({'mode':'configured-port-change-query','ready':True,'storedObservationUnchanged':True})
                finally:
                    other.shutdown();other.server_close()
                server.mode='valid'
                noop_stop=subprocess.run(['bash','-c',script],env=dict(env,CFIP_PUBLISH_ENABLED='false'),capture_output=True,text=True,timeout=5)
                stopped=json.loads((tmp/'status.json').read_text())
                assert noop_stop.returncode!=0 and stopped['error']=='publisher_still_responding',stopped
                results.append({'mode':'noop-stop-with-live-listener','exitCode':noop_stop.returncode,'status':stopped})
            results.append({'mode':mode,'exitCode':run.returncode,'status':status})
        print(json.dumps({'status':'PASS','scope':'Actual loopback HTTP/curl with mocked init; LAN membership/procd/rebind not evaluated','cases':results},indent=2))
    finally:
        server.shutdown();server.server_close()
