"""Synthetic byte-binding fixtures; not package or installation evidence."""
from __future__ import annotations
import copy
import hashlib
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from package_identity import ROOT, filename, source
from qualification_jobs import REQUIRED_JOBS
from migration_matrix import SCENARIOS


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
    assets = assets if assets is not None else assets_for()
    matrices=[]
    for asset in assets:
        kind=asset['package']['format']; inputs={}
        for role in ('legacyBase','legacyAddon','currentBase','currentAddon','recentBase'):
            record=copy.deepcopy(asset);record.pop('path',None);meta=record['package']
            if role.endswith('Addon'):meta['name']='luci-app-cloudflare-ip-rill'
            if role.startswith('legacy') or role=='recentBase':
                meta.update(version='2.6.0',release=3 if role=='recentBase' else 2)
                meta['packageVersion']=f"{meta['version']}-r{meta['release']}"
            inputs[role]=record
        matrices.append(dict(schemaVersion=1,packageManager=kind,inputs=inputs,offlineLifecycle=dict(status="PASS",packagePayloadRemoved=True,dependenciesPreserved=True,userDataPreserved=True,reinstalled=True,evidenceDirectory=kind+"-uninstall-reinstall",scope="offline package manager; online hooks not evaluated"),ownershipConflict=dict(guardedAdmission=kind=="apk",admissionExitCode=65 if kind=="apk" else 0,rawManagerStateMutated=kind=="apk",id="owner-conflict",status="PASS",exitCode=1,rejected=True,foreignOwnerPreserved=True,preexistingPayloadPreserved=True,installedStatePreserved=True,userDataPreserved=True,evidenceDirectory=kind+"-negative-owner-conflict"),negativeInstalls=[dict(id=case,status="PASS",exitCode=1,rejected=True,installedStatePreserved=True,payloadPreserved=True,userDataPreserved=True,evidenceDirectory=kind+"-negative-"+case) for case in ("missing","truncated")],scenarios=[
            dict(id=k,**{'from':old,'to':new},addon=addon,status='PASS',runtimeAbsent=True,runtimePresent=True,userDataPreserved=True,evidenceDirectory=kind+'-'+k)
            for k,(old,new,addon) in SCENARIOS.items()]))
    migration['currentMatrices']=matrices
    return dict(schemaVersion=1, commit=commit, runId=42, runAttempt=1, jobs={name:dict(result="success") for name in REQUIRED_JOBS}, artifacts=[],
                assetFiles=assets,
                qualificationState='automated-qualification', releaseEligible=True,
                packageMigration=migration, stableSourceArchiveSha256=c['resolved']['sourceArchiveSha256'],
                rill=dict(schemaVersion=1, package=dict(repository=c['openwrtPackage']['repository'],
                    commit=c['openwrtPackage']['commit'],qualificationRunId=c['qualification']['runId'],qualificationManifestSha256='c'*64),
                    stablePackageQualification='PASS',previewRuntimeIntegration='PASS',
                    stableCommit=c['resolved']['upstreamCommit'], previewCommit=c['preview']['commit'],
                    runtime=dict(version=c['openwrtPackage']['packageVersion'],tag=c['preview']['channel'],commit=c['preview']['commit'],sourceArchiveSha256='not-applicable-preview',binarySha256='f'*64),
                    integration=dict(status='pass',sameRelease=True)))
