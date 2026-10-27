#!/usr/bin/env python3
"""Exercise release rejection gates against current SDK bytes and real metadata."""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from package_identity import source

spec = importlib.util.spec_from_file_location('binding', ROOT / 'scripts/validate-release-assets.py')
binding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(binding)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('manifest', type=Path)
    p.add_argument('packages', type=Path)
    p.add_argument('--commit', required=True)
    p.add_argument('--run-id', type=int, required=True)
    p.add_argument('--run-attempt', type=int, required=True)
    p.add_argument('--apk-bin', required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    if a.output.exists():
        p.error('receipt already exists')
    manifest = json.loads(a.manifest.read_bytes())
    identity = source()

    def validate(m, directory, **expected):
        return binding.validate(m, directory, expected.get('commit', a.commit),
            expected.get('run', a.run_id), identity['version'], identity['release'],
            ROOT / 'contracts/rill-runtime.json', a.apk_bin,
            expected.get('attempt', a.run_attempt))

    originals = validate(manifest, a.packages)
    cases = []

    def reject(label, change=None, mutate=None, **expected):
        # Fresh isolated copies protect the canonical packages, even on rejection.
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            for file in originals:
                shutil.copyfile(file, directory / file.name)
            changed = copy.deepcopy(manifest)
            if change:
                change(changed)
            if mutate:
                mutate(directory)
            try:
                validate(changed, directory, **expected)
            except ValueError as exc:
                cases.append(dict(case=label, status='PASS', rejection=str(exc)))
            else:
                raise AssertionError(f'invalid release accepted: {label}')

    reject('wrong expected commit', commit='0' * 40 if a.commit != '0' * 40 else '1' * 40)
    reject('wrong run', run=a.run_id + 1)
    reject('wrong attempt', attempt=a.run_attempt + 1)
    reject('noneligible', lambda m: m.update(releaseEligible=False))
    reject('asset path traversal', lambda m: m['assetFiles'][0].update(path='../bad.ipk'))

    def swap(m):
        first, second = m['assetFiles']
        first['sha256'], second['sha256'] = second['sha256'], first['sha256']
    reject('swapped digests', swap)
    reject('runtime pin', lambda m: m['rill']['package'].update(commit='0' * 40))

    def tamper(directory):
        file = directory / originals[0].name
        raw = bytearray(file.read_bytes())
        raw[len(raw) // 2] ^= 1
        file.write_bytes(raw)
    reject('same length changed byte', mutate=tamper)
    reject('extra package', mutate=lambda d: (d / 'unexpected.ipk').write_bytes(b'extra'))

    def symlink(directory):
        file = directory / originals[0].name
        file.unlink()
        file.symlink_to(originals[0].resolve())
    reject('symlink asset', mutate=symlink)
    # Re-read canonical originals after every negative; never derive release hashes
    # from the temporary mutation directories.
    validate(manifest, a.packages)
    receipt = dict(schemaVersion=1, status='PASS',
        scope='current SDK bytes with unmocked IPK/APK metadata inspection',
        commit=a.commit, runId=a.run_id, runAttempt=a.run_attempt,
        manifestSha256=hashlib.sha256(a.manifest.read_bytes()).hexdigest(),
        cases=cases, deviceAccess=False, publication='NOT RUN')
    with a.output.open('x') as stream:
        json.dump(receipt, stream, indent=2)
        stream.write('\n')
    print(f'PASS: {len(cases)} current-byte rejection cases; real metadata positive passed')


if __name__ == '__main__':
    main()
