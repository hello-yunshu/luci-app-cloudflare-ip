#!/usr/bin/env python3
"""Independent source mutation, metadata, build expansion and sync regressions."""
import copy
import hashlib
import importlib.util
import json
import os
import platform
import contextlib
import io
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from package_identity import source, filename, validate_metadata, split_version, targets, build_version
spec=importlib.util.spec_from_file_location('sync_contract',ROOT/'scripts/check_rill_dependency.py')
sync=importlib.util.module_from_spec(spec);spec.loader.exec_module(sync)


class Contracts(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        (self.root/'package/luci-app-cloudflare-ip').mkdir(parents=True)
        (self.root/'contracts').mkdir()
        shutil.copy(ROOT/'release-channel.json',self.root/'release-channel.json')
        shutil.copy(ROOT/'VERSION',self.root/'VERSION')
        shutil.copy(ROOT/'contracts/package-artifacts.json',self.root/'contracts/package-artifacts.json')
        self.make=self.root/'package/luci-app-cloudflare-ip/Makefile'
        self.make.write_text((ROOT/'package/luci-app-cloudflare-ip/Makefile').read_text())

    def test_single_authority_future_versions_and_metadata(self):
        baseline_release=source()['release']
        baseline_make=self.make.read_text()
        for version,release in [('3.2.0',7),('6.0.2',23),('9.8.7',105)]:
            text=baseline_make.replace('PKG_RELEASE:='+str(baseline_release),'PKG_RELEASE:='+str(release))
            self.make.write_text(text); (self.root/'VERSION').write_text(version+'\n'); identity=source(self.root)
            self.assertEqual(identity['tag'],f'v{version}-{release}')
            for fmt in ('ipk','apk'):
                meta=dict(name=identity['name'],version=version,release=release,packageVersion=identity['packageVersion'],format=fmt,architecture='all' if fmt=='ipk' else 'noarch')
                validate_metadata(meta,filename(meta),identity)
                bad=dict(meta,packageVersion=f'{version}-r{release+1}')
                with self.assertRaises(ValueError):filename(bad)
                with self.assertRaises(ValueError):validate_metadata(meta,filename(meta),dict(identity,release=release+1))
            # Product changes do not alter the Runtime package channel contract.
            self.assertEqual(json.loads((ROOT/'contracts/rill-runtime.json').read_text())['openwrtPackage']['channel'],'stable')

    def test_invalid_authorities_and_channels(self):
        original=self.make.read_text();current=source(); original_version=(self.root/'VERSION').read_text()
        for value in ('-1','0','01','true','5;touch /tmp/no'):
            self.make.write_text(original.replace('PKG_RELEASE:='+str(current['release']),'PKG_RELEASE:='+value))
            with self.assertRaises(ValueError):source(self.root)
        self.make.write_text(original+'\nPKG_VERSION:=7.0.0\n')
        with self.assertRaises(ValueError):source(self.root)
        for value in ('01.2.3','bad','1.0','1.0.0;bad'):
            self.make.write_text(original); (self.root/'VERSION').write_text(value+'\n')
            with self.assertRaises(ValueError):source(self.root)
        self.make.write_text(original); (self.root/'VERSION').write_text(original_version)
        for channel in ('stable','prerelease'):
            (self.root/'release-channel.json').write_text(json.dumps(dict(schemaVersion=1,channel=channel,reason='explicit policy')))
            self.assertEqual(source(self.root)['channel'],channel)
        (self.root/'release-channel.json').write_text('{}')
        with self.assertRaises(ValueError):source(self.root)

    def test_raw_metadata_and_architecture_rejection(self):
        self.assertEqual(build_version('3.2.0-dev','apk'),'3.2.0.1')
        self.assertEqual(build_version('3.2.0-dev','ipk'),'3.2.0-dev')
        self.assertEqual(split_version('3.2.0-r7','ipk'),('3.2.0',7))
        self.assertEqual(split_version('3.2.0-7','ipk'),('3.2.0',7))
        for fmt,raw in [('apk','3.2.0-7'),('ipk','3.2.0-r0'),('apk','3.2.0-r01')]:
            with self.assertRaises(ValueError):split_version(raw,fmt)
        identity=source()
        meta=dict(identity,format='ipk',architecture='noarch')
        with self.assertRaises(ValueError):filename(meta)
        meta.update(architecture='all',release=True)
        with self.assertRaises(ValueError):filename(meta)

    def test_reject_ambiguous_package_metadata(self):
        spec=importlib.util.spec_from_file_location('metadata',ROOT/'scripts/openwrt-package-metadata.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        with self.assertRaises(ValueError):module.parse_control(b'Package: a\nVersion: 1\nVersion: 2\n')
        record={'name':source()['name'],'version':source()['packageVersion'],'arch':'noarch'}
        with self.assertRaises(ValueError):module.find_apk_record([record,record],source()['name'])
        self.assertEqual(module.find_apk_record({'info':record,'paths':[{'name':source()['name'],'size':1}]},source()['name'])['version'],source()['packageVersion'])

    def test_target_registry_rejects_duplicate_and_missing_public_format(self):
        values=targets(self.root)
        for changes in [values+[values[0]], [dict(t,public=False) for t in values]]:
            (self.root/'contracts/package-artifacts.json').write_text(json.dumps(dict(schemaVersion=1,targets=changes)))
            with self.assertRaises(ValueError):targets(self.root)

    def test_sync_extensions_noop_update_and_failed_write(self):
        package=self.root/'runtime-package'
        for name in ['metadata','package/rill-runtime']:(package/name).mkdir(parents=True)
        contract=json.loads((ROOT/'contracts/rill-runtime.json').read_text())
        resolved=contract['resolved']; pkg=contract['openwrtPackage']
        package_meta={'name':'rill-runtime','version':pkg['packageVersion'],'release':pkg['packageRelease'],'canonicalRecipe':'package/rill-runtime/Makefile','binary':pkg['binary']}
        upstream={'version':resolved['version'],'tag':resolved['tag'],'commit':resolved['upstreamCommit'],'sourceType':'immutable-git-commit'}
        metadata_path=package/'metadata/rill-runtime.json'
        metadata_path.write_text(json.dumps({'upstream':upstream,'package':package_meta}))
        recipe=package/'package/rill-runtime/Makefile'
        recipe.write_text(f"PKG_VERSION:={pkg['packageVersion']}\nPKG_RELEASE:={pkg['packageRelease']}\nPKG_SOURCE_VERSION:={resolved['upstreamCommit']}\n")
        # This test synthesizes a fully qualified package state. The checked-in
        # contract correctly keeps its package commit null while qualification
        # is pending; give the isolated fixture its own immutable commit.
        contract['openwrtPackage']['commit']='a'*40
        contract['extension']={'future':True};contract['resolved']['future']='keep'
        contract['packageMigration']['extraEvidence']={'historical':'keep'}
        destination=self.root/'contract.json';destination.write_text(json.dumps(contract))
        proof_raw=b'validated schema 4 fixture'
        contract['qualification'].update(status='PASS',runId=42,runAttempt=1,manifestSha256=hashlib.sha256(proof_raw).hexdigest())
        destination.write_text(json.dumps(contract))
        run=contract['qualification']['runId']; head=contract['openwrtPackage']['commit']
        def api(path):
            return {'workflow_runs':[dict(id=run,conclusion='success',run_attempt=1)]}
        def proof(*args):
            return {'schemaVersion':4,'upstream':upstream,'package':package_meta}, proof_raw, []
        with contextlib.redirect_stdout(io.StringIO()),patch.object(sync,'CONTRACT',destination),patch.object(sync,'api',api),patch.object(sync,'fetch_manifest',proof),patch.object(sync.subprocess,'run',return_value=subprocess.CompletedProcess([],0,head+'\n','')):
            before=destination.read_bytes();sync.sync(package);self.assertEqual(before,destination.read_bytes())
            contract['qualification']['runId']=run+1;destination.write_text(json.dumps(contract))
            sync.sync(package);after=json.loads(destination.read_text())
            self.assertEqual(after['packageMigration'],contract['packageMigration']);self.assertEqual(after['extension'],contract['extension']);self.assertEqual(after['resolved']['future'],'keep')
            self.assertEqual(after['qualification']['runId'],run)
            meta=json.loads(metadata_path.read_text());meta['package']['release']=17;metadata_path.write_text(json.dumps(meta))
            recipe.write_text(recipe.read_text().replace('PKG_RELEASE:='+str(pkg['packageRelease']),'PKG_RELEASE:=17'))
            package_meta['release']=17
            sync.sync(package);self.assertEqual(json.loads(destination.read_text())['openwrtPackage']['packageRelease'],17)
            before=destination.read_bytes();meta['package']['release']=0;metadata_path.write_text(json.dumps(meta))
            with self.assertRaises(ValueError):sync.sync(package)
            self.assertEqual(before,destination.read_bytes())
            meta['package']['release']=17;metadata_path.write_text(json.dumps(meta))
            forced=json.loads(destination.read_text());forced['qualification']['runId']=run+1;destination.write_text(json.dumps(forced));before=destination.read_bytes()
            with patch.object(sync.os,'replace',side_effect=OSError('injected atomic rename failure')):
                with self.assertRaises(OSError):sync.sync(package)
            self.assertEqual(before,destination.read_bytes())
            self.assertFalse(list(destination.parent.glob('.rill-contract-*')))
            with patch.object(sync,'api',return_value={'workflow_runs':[]}):
                self.assertEqual(sync.sync(package),0)
            self.assertEqual(before,destination.read_bytes())
            bad=json.loads(destination.read_text());bad['schemaVersion']=99;destination.write_text(json.dumps(bad));before=destination.read_bytes()
            with self.assertRaises(ValueError):sync.sync(package)
            self.assertEqual(before,destination.read_bytes())

    def test_actual_make_macro_renders_version_surfaces(self):
        # Use GNU Make's actual double expansion and the real Build/Compile body.
        original=source(); self.make.write_text(self.make.read_text().replace('PKG_RELEASE:='+str(original['release']),'PKG_RELEASE:=23'))
        (self.root/'VERSION').write_text('3.2.0\n')
        package=self.root/'package/luci-app-cloudflare-ip'
        shutil.copytree(ROOT/'package/luci-app-cloudflare-ip/root',package/'root')
        shutil.copytree(ROOT/'package/luci-app-cloudflare-ip/htdocs',package/'htdocs')
        (self.root/'include').mkdir();(self.root/'rules.mk').write_text('')
        (self.root/'include/package.mk').write_text('define BuildPackage\n$(if $(filter luci-app-cloudflare-ip,$(1)),all:\n\t$(Build/Prepare)\n\t$(Build/Compile))\nendef\n')
        runner=self.root/'runner.mk'
        runner.write_text(f'TOPDIR:={self.root}\nINCLUDE_DIR:={self.root}/include\nPKG_BUILD_DIR:={self.root}/build\nCP:=cp -r\ninclude {self.make}\n')
        # sed -i is GNU on SDK hosts. Keep production macro unchanged and use
        # a minimal GNU-sed adapter for this macOS test environment.
        env=dict(os.environ)
        if platform.system() == 'Darwin':
            bindir=self.root/'bin';bindir.mkdir()
            sed=bindir/'sed';sed.write_text("#!/bin/sh\nif [ \"$1\" = -i ]; then shift; exec /usr/bin/sed -i '' \"$@\"; fi\nexec /usr/bin/sed \"$@\"\n");sed.chmod(0o755)
            env['PATH']=str(bindir)+os.pathsep+env['PATH']
        result=subprocess.run(['make','-f',str(runner),'all'],cwd=package,capture_output=True,text=True,env=env)
        if result.returncode and 'invalid command code' in result.stderr:
            self.fail('GNU sed is required for the build macro test')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        identity=source(self.root)
        for name in ['root/usr/bin/cf-ip-auto-v2','root/usr/bin/cf-ip-auto-legacy','root/usr/libexec/rpcd/cf_ip','htdocs/luci-static/resources/cloudflare-ip/utils.js']:
            text=(self.root/'build'/name).read_text();self.assertNotIn('@PKG_',text)
            self.assertIn(identity['version'],text)
        rpc=(self.root/'build/root/usr/libexec/rpcd/cf_ip').read_text()
        ui=(self.root/'build/htdocs/luci-static/resources/cloudflare-ip/utils.js').read_text()
        self.assertIn(identity['packageVersion'],rpc);self.assertIn(identity['packageVersion'],ui)
        response=subprocess.check_output(['sh',str(self.root/'build/root/usr/libexec/rpcd/cf_ip'),'call','version'],text=True)
        self.assertEqual(json.loads(response)['package_version'],identity['packageVersion'])
        if platform.system() == 'Darwin' and 'version 3.' in subprocess.check_output(['bash','--version'],text=True):
            self.skipTest('The macOS system Bash 3.2 lacks associative arrays used by the OpenWrt Bash 5 CLI')
        cli_env=dict(env,CFIP_LIB_DIR=str(self.root/'build/root/usr/libexec/cf-ip'),CFIP_RUNTIME_DIR=str(self.root/'runtime'),CFIP_STATUS_DIR=str(self.root/'state'))
        cli=json.loads(subprocess.check_output(['bash',str(self.root/'build/root/usr/bin/cf-ip-auto-v2'),'--version'],text=True,env=cli_env))
        self.assertEqual(cli['package_version'],identity['packageVersion'])
        self.assertEqual(cli['engine_schema'],2);self.assertEqual(cli['runtime_api_version'],3)
        shutil.rmtree(self.root/'build')
        (package/'root/usr/libexec/rpcd/cf_ip').unlink()
        failed=subprocess.run(['make','-f',str(runner),'all'],cwd=package,capture_output=True,text=True,env=env)
        self.assertNotEqual(failed.returncode,0,'missing version template must fail the build')


if __name__=='__main__':unittest.main(verbosity=2)
