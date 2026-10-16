"""Synthetic byte-binding fixtures; not package or installation evidence."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from package_identity import ROOT, filename, source


def assets_for(identity=None):
    identity = identity or source()
    result = []
    for fmt in ('ipk', 'apk'):
        meta = {k:identity[k] for k in ('name','version','release','packageVersion')}
        meta.update(format=fmt, architecture='all' if fmt == 'ipk' else 'noarch')
        raw = f'synthetic {fmt} byte-binding payload'.encode()
        result.append(dict(path=f'build-{fmt}/{filename(meta)}', package=meta,
                           size=len(raw), sha256=hashlib.sha256(raw).hexdigest()))
    return result


def manifest(assets=None):
    c = json.loads((ROOT / 'contracts/rill-runtime.json').read_text())
    commit = '0123456789abcdef0123456789abcdef01234567'
    migration = dict(c['packageMigration'], currentSHA=commit, ipk='PASS', apk='PASS')
    migration.update({k:True for k in ('baseOnlyUpgrade','baseAddonToBaseUpgrade','addonRemovalSafe','r3ToR4','runtimeAbsent','runtimePresent')})
    return dict(schemaVersion=1, commit=commit, runId=42, jobs={}, artifacts=[],
                assetFiles=assets if assets is not None else assets_for(),
                qualificationState='automated-qualification', releaseEligible=True,
                packageMigration=migration, stableSourceArchiveSha256=c['resolved']['sourceArchiveSha256'],
                rill=dict(schemaVersion=1, package=dict(repository=c['openwrtPackage']['repository'],
                    commit=c['openwrtPackage']['commit'],qualificationRunId=c['qualification']['runId'],qualificationManifestSha256='c'*64),
                    stablePackageQualification='PASS',previewRuntimeIntegration='PASS',
                    stableCommit=c['resolved']['upstreamCommit'], previewCommit=c['preview']['commit'],
                    runtime=dict(version=c['openwrtPackage']['packageVersion'],tag=c['preview']['channel'],commit=c['preview']['commit'],sourceArchiveSha256='not-applicable-preview',binarySha256='f'*64),
                    integration=dict(status='pass',sameRelease=True)))
