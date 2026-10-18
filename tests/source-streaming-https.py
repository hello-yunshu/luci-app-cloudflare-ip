#!/usr/bin/env python3
"""Real curl/local TLS: source disk cap, deadline, redirects and cache preservation."""
import hashlib
import http.server
import json
import os
from pathlib import Path
import ssl
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(os.environ.get('CFIP_TEST_SOURCE', ROOT / 'package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/source.sh'))
VALID = b'104.18.1.1\n104.18.1.2\n'
EXACT = VALID + b'#' + b'x' * (2048-len(VALID)-1)

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, *_):
        pass
    def do_GET(self):
        try:
            route = '/' + self.server.mode if self.path == '/list' else self.path
            if route in ('/redirect', '/downgrade'):
                target = f'https://localhost:{self.server.server_port}/valid' if route == '/redirect' else 'http://localhost:1/blocked'
                self.send_response(302)
                self.send_header('Location', target)
                self.send_header('Content-Length', '0')
                self.end_headers()
                return
            self.send_response(200)
            if route == '/large':
                self.send_header('Transfer-Encoding', 'chunked')
                self.end_headers()
                for _ in range(256):
                    block = b'104.18.1.1\n' * 400
                    self.wfile.write(f'{len(block):x}\r\n'.encode() + block + b'\r\n')
                    self.wfile.flush()
                self.wfile.write(b'0\r\n\r\n')
            elif route == '/slow':
                self.send_header('Content-Length', '10000')
                self.end_headers()
                for _ in range(20):
                    self.wfile.write(b'1')
                    self.wfile.flush()
                    time.sleep(.2)
            else:
                body = EXACT if route == '/exact' else EXACT+b'x' if route == '/over' else VALID
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
            pass

with tempfile.TemporaryDirectory(prefix='cfip-source-tls-') as directory:
    tmp = Path(directory)
    subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
                    '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost',
                    '-keyout', str(tmp/'key.pem'), '-out', str(tmp/'cert.pem')], check=True, capture_output=True)
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    server.daemon_threads = True
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(tmp/'cert.pem', tmp/'key.pem')
    server.socket = context.wrap_socket(server.socket, server_side=True)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    shell = r'''
set -euo pipefail
source "$CFIP_COMMON"
source "$CFIP_TEST_SOURCE"
curl() {
 local rc=0 f bytes
 command curl "$@" || rc=$?
 for f in "$CFIP_SOURCE_RUNTIME_DIR"/*/fetch.*; do
  [[ -f "$f" ]] || continue
  bytes="$(wc -c <"$f")"
  printf '%s\n' "$bytes" >>"$CFIP_SIZE_LOG"
 done
 return "$rc"
}
cfip_source_fetch_remote tls "$CFIP_URL" ip-text ipv4 community "$CFIP_RESULT"
'''
    env = dict(os.environ, CFIP_COMMON=str(ROOT/'package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/common.sh'),
               CFIP_TEST_SOURCE=str(SOURCE), CFIP_STATUS_DIR=str(tmp/'status'), CFIP_RUNTIME_DIR=str(tmp/'runtime'),
               CFIP_SOURCE_RUNTIME_DIR=str(tmp/'runtime/sources'), CFIP_SOURCE_CACHE_DIR=str(tmp/'cache'),
               CFIP_SOURCE_MAX_BYTES='2048', CFIP_SOURCE_TOTAL_TIMEOUT='1', CFIP_SOURCE_CONNECT_TIMEOUT='1',
               CFIP_SOURCE_CURL_MAX_FILESIZE_SUPPORTED='false', CURL_CA_BUNDLE=str(tmp/'cert.pem'),
               CFIP_SIZE_LOG=str(tmp/'sizes'), CFIP_RESULT=str(tmp/'result.json'), NO_PROXY='localhost,127.0.0.1', no_proxy='localhost,127.0.0.1')
    results = []
    try:
        expected_raw = VALID
        for endpoint in ('valid', 'exact', 'over', 'large', 'slow', 'redirect', 'downgrade'):
            server.mode = endpoint
            started = time.monotonic()
            run = subprocess.run(['bash', '-c', shell], env=dict(env, CFIP_URL=f'https://localhost:{server.server_port}/list'), capture_output=True, text=True, timeout=10)
            elapsed = time.monotonic()-started
            assert run.returncode == 0, (endpoint, run.stderr, run.stdout)
            records = json.loads((tmp/'result.json').read_text())
            assert len(records) == 2, (endpoint, records)
            raw = tmp/'cache/tls/last-good.txt'
            if endpoint == 'exact': expected_raw = EXACT
            elif endpoint in ('valid', 'redirect'): expected_raw = VALID
            assert raw.read_bytes() == expected_raw, endpoint
            meta = json.loads((tmp/'runtime/sources/tls/metadata.json').read_text())
            expected_cache = endpoint in ('over', 'large', 'slow', 'downgrade')
            assert meta['fromCache'] == expected_cache, (endpoint, meta)
            peak = max(map(int, (tmp/'sizes').read_text().split()))
            results.append(dict(endpoint=endpoint, elapsedSeconds=round(elapsed, 3), maxObservedTempBytes=peak, fromCache=meta['fromCache'], lastError=meta['lastError']))
            assert peak <= 2049, f'{endpoint}: unbounded temporary source download: {peak} bytes > cap + one byte'
            assert elapsed < 6, (endpoint, elapsed)
        assert not list((tmp/'runtime/sources/tls').glob('fetch.*')), 'temporary files leaked'
        print(json.dumps({'status':'PASS', 'transport':'actual curl + locally trusted TLS, no certificate bypass', 'sourceSha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(), 'cases':results}, indent=2))
    finally:
        server.shutdown()
        server.server_close()
