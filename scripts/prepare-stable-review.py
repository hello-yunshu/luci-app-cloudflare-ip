#!/usr/bin/env python3
"""Prepare a byte-bound Stable review receipt. Never publishes or grants approval."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
from package_identity import source

ROOT = Path(__file__).resolve().parents[1]
NEGATIVES = {'wrong expected commit', 'wrong run', 'wrong attempt', 'noneligible',
             'asset path traversal', 'swapped digests', 'runtime pin',
             'same length changed byte', 'extra package', 'symlink asset'}


def prepare(manifest_path, preflight_path, negatives_path, candidate, repository):
    raw = manifest_path.read_bytes()
    manifest = json.loads(raw)
    preflight = json.loads(preflight_path.read_bytes())
    negatives = json.loads(negatives_path.read_bytes())
    identity = source()
    if identity['channel'] != 'stable' or identity['version'].endswith('-dev'):
        raise ValueError('review requires a final Stable candidate identity')
    if not re.fullmatch(r'[0-9a-f]{40}', candidate):
        raise ValueError('exact candidate SHA required')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
        raise ValueError('invalid repository')
    expected = {key: manifest[key] for key in ('commit', 'runId', 'runAttempt')}
    digest = hashlib.sha256(raw).hexdigest()
    if manifest.get('releaseEligible') is not True:
        raise ValueError('software qualification is incomplete')
    for receipt in (preflight, negatives):
        if receipt.get('status') != 'PASS' or receipt.get('manifestSha256') != digest or any(receipt.get(k) != v for k, v in expected.items()):
            raise ValueError('preflight receipt is not bound to this exact qualification')
    cases = negatives.get('cases', [])
    if len(cases) != len(NEGATIVES) or {c.get('case') for c in cases} != NEGATIVES or any(c.get('status') != 'PASS' for c in cases):
        raise ValueError('current-byte rejection matrix is incomplete')
    tested = manifest['commit']
    if not isinstance(tested, str) or not re.fullmatch(r'[0-9a-f]{40}', tested):
        raise ValueError('exact tested SHA required')
    def tree(commit):
        return subprocess.check_output(['git', 'rev-parse', '--verify', '--end-of-options', commit + '^{tree}'], text=True).strip()
    candidate_tree, tested_tree = tree(candidate), tree(tested)
    if candidate_tree != tested_tree:
        raise ValueError('tested merge tree differs from candidate tree')
    tag = identity['tag']
    refs = json.loads(subprocess.check_output(['gh', 'api', f'repos/{repository}/git/matching-refs/tags/{tag}'], text=True))
    if not isinstance(refs, list) or any(r.get('ref') == 'refs/tags/' + tag for r in refs):
        raise ValueError('candidate tag is already occupied or could not be checked')
    policy_path = ROOT / 'docs/audits/g6-g7-evidence/device-policy-20261024.json'
    policy = json.loads(policy_path.read_bytes())
    if policy['deviceValidation'].get('blocksG6G7Completion') is not False:
        raise ValueError('device acceptance policy has not been decided')
    contract = json.loads((ROOT / 'contracts/rill-runtime.json').read_bytes())
    return dict(schemaVersion=1, status='PREPARED_FOR_REVIEW', repository=repository,
        candidateCommit=candidate, testedCommit=tested, tree=candidate_tree,
        runId=manifest['runId'], runAttempt=manifest['runAttempt'],
        qualificationManifestSha256=digest, identity=identity, tagAvailable=True,
        assets=manifest['assetFiles'], runtimeContract=contract,
        devicePolicy=policy, actualDeviceCoverage='See separate candidate deployment receipt; software results do not imply device PASS',
        publication='NOT AUTHORIZED / NOT RUN', automaticStablePromotion='DISABLED',
        approvalRequired='Approve this exact SHA, tag, run/attempt, package digests, Runtime pins, support scope and rollback plan before merge/tag/Release/feed actions')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--manifest', type=Path, required=True)
    p.add_argument('--preflight', type=Path, required=True)
    p.add_argument('--negatives', type=Path, required=True)
    p.add_argument('--candidate', required=True)
    p.add_argument('--repository', required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    if a.output.exists():
        p.error('review receipt already exists')
    try:
        receipt = prepare(a.manifest, a.preflight, a.negatives, a.candidate, a.repository)
        with a.output.open('x') as stream:
            json.dump(receipt, stream, indent=2)
            stream.write('\n')
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as exc:
        p.exit(1, f'Stable review rejected: {exc}\n')
    print('Stable review prepared; publication remains separately gated')


if __name__ == '__main__':
    main()
