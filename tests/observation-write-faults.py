#!/usr/bin/env python3
"""Actual CFST observation parser: fail closed and retain existing output on I/O faults."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LIB = os.environ.get('CFIP_TEST_LIB_DIR', str(ROOT/'package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip'))
BASH = os.environ.get('CFIP_TEST_BASH', 'bash')
results = []
failures = []

def snapshot(path):
    if path.is_symlink():
        return {'kind': 'symlink', 'target': os.readlink(path)}
    if path.is_dir():
        return {'kind': 'directory', 'files': {p.name: p.read_text() for p in path.iterdir()}}
    if path.is_file():
        return {'kind': 'file', 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    return {'kind': 'absent'}

with tempfile.TemporaryDirectory(prefix='cfip-observe-faults-') as directory:
    root = Path(directory)
    worker = root/'worker'
    worker.write_text(r'''set -uo pipefail
source "$CFIP_TEST_LIB_DIR/common.sh"
source "$CFIP_TEST_LIB_DIR/observe.sh"
jq(){
 if [[ "$CFIP_TEST_CASE" == row-json && "$*" == *'candidateId:'* ]]; then return 23; fi
 command jq "$@"
}
mv(){
 if [[ "$CFIP_TEST_CASE" == row-rename && ( "${1:-}" == */next.json || "${1:-}" == *.next ) ]]; then return 29; fi
 command mv "$@"
}
printf(){
 if [[ "$CFIP_TEST_CASE" == initial-write && ( "${1:-}" == '[]' || "${1:-}" == '[]\n' ) ]]; then return 23; fi
 builtin printf "$@"
}
mktemp(){ [[ "$CFIP_TEST_CASE" != temporary-allocation ]] || return 23; command mktemp "$@"; }
if [[ "$CFIP_TEST_CASE" == final-write ]]; then cfip_atomic_write(){ return 31; }; fi
if cfip_parse_cfst "$CFIP_TEST_OUTPUT" tcp 8 "$CFIP_TEST_CSV:ipv4"; then exit 0; else exit $?; fi
''')
    for name in ['success', 'row-json', 'row-rename', 'initial-write', 'final-write', 'temporary-allocation', 'output-directory', 'output-symlink']:
        case = root/name
        case.mkdir()
        scratch = case/'scratch'
        scratch.mkdir()
        output = case/'observations.json'
        external = case/'external'
        external.write_text('external target retained\n')
        if name == 'output-directory':
            output.mkdir()
            (output/'user-marker').write_text('retained\n')
        elif name == 'output-symlink':
            output.symlink_to(external)
        else:
            output.write_text('[{"previous":true}]\n')
        csv = case/'input.csv'
        csv.write_text('IP,Sent,Received,Loss,Latency,Download,Colo\n104.16.1.1,4,4,0,5,20, SJC \n')
        before = snapshot(output)
        run = subprocess.run([BASH, str(worker)], env=dict(os.environ, TMPDIR=str(scratch), CFIP_TEST_LIB_DIR=LIB, CFIP_TEST_CASE=name, CFIP_TEST_OUTPUT=str(output), CFIP_TEST_CSV=str(csv)), capture_output=True, text=True, timeout=12)
        after = snapshot(output)
        try:
            if name == 'success':
                assert run.returncode == 0, run.stderr
                rows = json.loads(output.read_text())
                assert len(rows) == 1 and rows[0]['ip'] == '104.16.1.1' and rows[0]['colo'] == 'SJC', rows
            else:
                assert run.returncode != 0, 'parser reported success after controlled failure'
                assert before == after, 'failure replaced the previous output or unsafe target'
            assert external.read_text() == 'external target retained\n'
            assert not list(scratch.iterdir()), 'normal failure leaked parser workspace'
            results.append(dict(case=name, status='PASS', returncode=run.returncode, before=before, after=after))
        except (AssertionError, ValueError) as error:
            failures.append(dict(case=name, error=str(error), returncode=run.returncode, stderr=run.stderr[-1200:], before=before, after=after))
print(json.dumps(dict(status='FAIL' if failures else 'PASS', scope='actual observation parser with controlled filesystem/tool faults; conditional caller disables errexit', results=results, failures=failures), indent=2))
raise SystemExit(bool(failures))
