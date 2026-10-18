#!/usr/bin/env python3
"""Concurrent actual HTTP consumers pin a generation and verify artifact bytes."""
import functools
import hashlib
import http.server
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request
ROOT=Path(__file__).resolve().parents[1]
class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self,*_): pass
with tempfile.TemporaryDirectory(prefix='cfip-generation-http-') as d:
    tmp=Path(d);(tmp/'runtime').mkdir();(tmp/'publish').mkdir()
    init=tmp/'init';init.write_text('#!/bin/sh\nexit 0\n');init.chmod(0o755)
    for name,ip in [('a','104.18.1.1'),('b','104.18.9.1')]: (tmp/name).write_text(json.dumps([{'ip':ip,'family':'ipv4'}]))
    server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Handler,directory=str(tmp/'publish')));server.daemon_threads=True
    threading.Thread(target=server.serve_forever,daemon=True).start()
    env=dict(os.environ,CFIP_COMMON=str(ROOT/'package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh'),CFIP_PUBLISHER=str(ROOT/'package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/publisher.sh'),CFIP_RUNTIME_DIR=str(tmp/'runtime'),CFIP_PUBLISH_DIR=str(tmp/'publish'),CFIP_PUBLISH_STATUS_FILE=str(tmp/'status'),CFIP_PUBLISH_INIT=str(init),CFIP_PUBLISH_ENABLED='true',CFIP_PUBLISH_BIND='127.0.0.1',CFIP_PUBLISH_PORT=str(server.server_port),CFIP_PUBLISH_READY_ATTEMPTS='1',CFIP_INPUT_A=str(tmp/'a'),CFIP_INPUT_B=str(tmp/'b'))
    script='''set -euo pipefail
source "$CFIP_COMMON"; source "$CFIP_PUBLISHER"
for i in {1..10}; do
 CFIP_RUN_ID="http-$i"
 if ((i % 2)); then cfip_publish_result "$CFIP_INPUT_A"; else cfip_publish_result "$CFIP_INPUT_B"; fi
done
'''
    stop=threading.Event();errors=[];counts={'coherent':0,'retried404':0};lock=threading.Lock()
    base=f'http://127.0.0.1:{server.server_port}'
    opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
    def fetch(path):
        with opener.open(base+path,timeout=3) as response: return response.read()
    def reader():
        while not stop.is_set():
            try:
                root=json.loads(fetch('/result.json'));prefix=root['generationPath']
                manifest=json.loads(fetch(prefix+'/result.json'))
                assert manifest==root,'pinned result changed within its generation'
                for name,identity in manifest['artifacts'].items():
                    body=fetch(prefix+'/'+name)
                    assert len(body)==identity['sizeBytes'] and hashlib.sha256(body).hexdigest()==identity['sha256'],(prefix,name)
                with lock: counts['coherent']+=1
                time.sleep(.005)
            except urllib.error.HTTPError as error:
                if error.code==404:
                    with lock: counts['retried404']+=1
                    time.sleep(.005)
                else: errors.append(str(error));return
            except Exception as error: errors.append(repr(error));return
    readers=[threading.Thread(target=reader,daemon=True) for _ in range(2)]
    for thread in readers:thread.start()
    try:
        run=subprocess.run(['bash','-c',script],env=env,capture_output=True,text=True,timeout=40)
        assert run.returncode==0,run.stderr
    finally:
        stop.set()
        for thread in readers:thread.join(timeout=5)
        server.shutdown();server.server_close()
    assert not errors,errors
    assert counts['coherent']>=5,counts
    assert all(not thread.is_alive() for thread in readers),'reader did not finish'
    print(json.dumps({'status':'PASS','scope':'actual loopback HTTP, two consumers, ten publications, fixture init','observations':counts},indent=2))
