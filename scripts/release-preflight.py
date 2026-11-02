#!/usr/bin/env python3
"""Offline validation of already collected qualification and release bytes.

No network, Git, tag, Release, feed or upload operations are performed. APK metadata
inspection uses the explicitly supplied local tool.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
from package_identity import source

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('release_binding',HERE/'validate-release-assets.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('manifest',type=Path)
    p.add_argument('packages',type=Path)
    p.add_argument('--commit',required=True)
    p.add_argument('--run-id',type=int,required=True)
    p.add_argument('--run-attempt',type=int,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--apk-bin',required=True,help='local apk tool or explicitly offline adapter')
    a=p.parse_args()
    if a.output.exists():p.error('receipt already exists; choose a new output path')
    try:
        raw=a.manifest.read_bytes();manifest=json.loads(raw)
        authority=source()
        files=module.validate(manifest,a.packages,a.commit,a.run_id,authority['version'],
            authority['release'],HERE.parent/'contracts/rill-runtime.json',a.apk_bin,a.run_attempt)
        receipt=dict(schemaVersion=1,status='PASS',scope='offline-package-preflight',
            commit=a.commit,runId=a.run_id,runAttempt=a.run_attempt,
            manifestSha256=hashlib.sha256(raw).hexdigest(),
            assets=[dict(name=f.name,size=f.stat().st_size,sha256=hashlib.sha256(f.read_bytes()).hexdigest()) for f in files],
            publication='NOT RUN',deviceAcceptance='NOT EVALUATED')
        with a.output.open('x') as out:json.dump(receipt,out,indent=2);out.write('\n')
    except (OSError,ValueError,KeyError,TypeError,module.PACKAGE.subprocess.CalledProcessError,module.PACKAGE.tarfile.TarError) as exc:
        p.exit(1,f'offline preflight rejected: {exc}\n')
    print(f'offline preflight passed; receipt: {a.output}')


if __name__=='__main__':main()
