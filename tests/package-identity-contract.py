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
        shutil.copy(ROOT/'contracts/package-artifacts.json',self.root/'contracts/package-artifacts.json')
        self.make=self.root/'package/luci-app-cloudflare-ip/Makefile'
        self.make.write_text((ROOT/'package/luci-app-cloudflare-ip/Makefile').read_text())

    def test_single_authority_future_versions_and_metadata(self):
        for version,release in [('3.2.0',7),('6.0.2',23),('9.8.7',105)]:
            text=(ROOT/'package/luci-app-cloudflare-ip/Makefile').read_text()
            original=source(); text=text.replace('PKG_VERSION:='+original['version'],'PKG_VERSION:='+version).replace('PKG_RELEASE:='+str(original['release']),'PKG_RELEASE:='+str(release))
            self.make.write_text(text); identity=source(self.root)
            self.assertEqual(identity['tag'],f'v{version}-{release}')
            for fmt in ('ipk','apk'):
                meta=dict(name=identity['name'],version=version,release=release,packageVersion=identity['packageVersion'],format=fmt,architecture='all' if fmt=='ipk' else 'noarch')
                validate_metadata(meta,filename(meta),identity)
                bad=dict(meta,packageVersion=f'{version}-r{release+1}')
                with self.assertRaises(ValueError):filename(bad)
                with self.assertRaises(ValueError):validate_metadata(meta,filename(meta),dict(identity,release=release+1))
            # Product changes do not alter the protocol or historical pins.
            self.assertEqual(json.loads((ROOT/'contracts/rill-runtime.json').read_text())['preview']['modelGeneration'],2)

    def test_invalid_authorities_and_channels(self):
        original=self.make.read_text();current=source()
        for value in ('-1','0','01','true','5;touch /tmp/no'):
            self.make.write_text(original.replace('PKG_RELEASE:='+str(current['release']),'PKG_RELEASE:='+value))
            with self.assertRaises(ValueError):source(self.root)
        self.make.write_text(original+'\nPKG_VERSION:=7.0.0\n')
        with self.assertRaises(ValueError):source(self.root)
        for value in ('01.2.3','bad','1.0','1.0.0;bad'):
            self.make.write_text(original.replace('PKG_VERSION:='+current['version'],'PKG_VERSION:='+value))
            with self.assertRaises(ValueError):source(self.root)
        self.make.write_text(original)
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
        for name in ['metadata','package/rill-runtime-preview']:(package/name).mkdir(parents=True)
        contract=json.loads((ROOT/'contracts/rill-runtime.json').read_text())
        resolved=contract['resolved']; preview=contract['preview']; pkg=contract['openwrtPackage']
        (package/'metadata/rill-runtime.json').write_text(json.dumps({'upstream':{'version':resolved['version'],'commit':resolved['upstreamCommit'],'archiveSha256':resolved['sourceArchiveSha256']}}))
        (package/'metadata/rill-runtime-preview.json').write_text(json.dumps({'channel':preview['channel'],'upstream':{'version':pkg['packageVersion'],'commit':preview['commit']},'package':{'name':pkg['package'],'version':pkg['packageVersion'],'release':pkg['packageRelease'],'binary':pkg['binary']}}))
        (package/'package/rill-runtime-preview/Makefile').write_text(f"PKG_VERSION:={pkg['packageVersion']}\nPKG_RELEASE:={pkg['packageRelease']}\nPKG_SOURCE_VERSION:={preview['commit']}\n")
        contract['extension']={'future':True};contract['preview']['future']='keep'
        contract['packageMigration']['extraEvidence']={'historical':'keep'}
        destination=self.root/'contract.json';destination.write_text(json.dumps(contract))
        proof_raw=b'validated schema 3 fixture'
        contract['qualification'].update(runAttempt=1,manifestSha256=hashlib.sha256(proof_raw).hexdigest())
        destination.write_text(json.dumps(contract))
        run=contract['qualification']['runId']; head=contract['openwrtPackage']['commit']
        def api(path):
            if '/releases?' in path:return [dict(tag_name=contract['resolved']['tag'],draft=False,prerelease=False)]
            return {'workflow_runs':[dict(id=run,conclusion='success',run_attempt=1)]}
        def proof(*args):
            return {'upstream':resolved | {'commit':resolved['upstreamCommit'],'archiveSha256':resolved['sourceArchiveSha256']},
                    'previewPackage':{**json.loads((package/'metadata/rill-runtime-preview.json').read_text())['package'],
                                      'upstream':{'commit':preview['commit']}}}, proof_raw, []
        with contextlib.redirect_stdout(io.StringIO()),patch.object(sync,'CONTRACT',destination),patch.object(sync,'api',api),patch.object(sync,'fetch_manifest',proof),patch.object(sync.subprocess,'run',return_value=subprocess.CompletedProcess([],0,head+'\n','')):
            before=destination.read_bytes();sync.sync(package);self.assertEqual(before,destination.read_bytes())
            contract['qualification']['runId']=run+1;destination.write_text(json.dumps(contract))
            sync.sync(package);after=json.loads(destination.read_text())
            self.assertEqual(after['packageMigration'],contract['packageMigration']);self.assertEqual(after['extension'],contract['extension']);self.assertEqual(after['preview']['future'],'keep')
            self.assertEqual(after['qualification']['runId'],run)
            with patch.object(sync,'api',return_value=[]):
                before=destination.read_bytes()
                with self.assertRaises(RuntimeError):sync.sync(package)
                self.assertEqual(before,destination.read_bytes())
            # Positive future package releases derive from metadata/recipe, not a fixed 2.
            meta_path=package/'metadata/rill-runtime-preview.json';meta=json.loads(meta_path.read_text());meta['package']['release']=17;meta_path.write_text(json.dumps(meta))
            recipe=package/'package/rill-runtime-preview/Makefile';recipe.write_text(recipe.read_text().replace('PKG_RELEASE:='+str(pkg['packageRelease']),'PKG_RELEASE:=17'))
            sync.sync(package);self.assertEqual(json.loads(destination.read_text())['openwrtPackage']['packageRelease'],17)
            before=destination.read_bytes();meta['package']['release']=0;meta_path.write_text(json.dumps(meta))
            with self.assertRaises(ValueError):sync.sync(package)
            self.assertEqual(before,destination.read_bytes())
            meta['package']['release']=17;meta_path.write_text(json.dumps(meta))
            forced=json.loads(destination.read_text());forced['qualification']['runId']=run+1;destination.write_text(json.dumps(forced));before=destination.read_bytes()
            with patch.object(sync.os,'replace',side_effect=OSError('injected atomic rename failure')):
                with self.assertRaises(OSError):sync.sync(package)
            self.assertEqual(before,destination.read_bytes())
            self.assertFalse(list(destination.parent.glob('.rill-contract-*')))
            def no_qualification(path):
                return api(path) if '/releases?' in path else {'workflow_runs':[]}
            with patch.object(sync,'api',no_qualification):sync.sync(package)
            self.assertEqual(before,destination.read_bytes())
            bad=json.loads(destination.read_text());bad['schemaVersion']=99;destination.write_text(json.dumps(bad));before=destination.read_bytes()
            with self.assertRaises(ValueError):sync.sync(package)
            self.assertEqual(before,destination.read_bytes())

    def test_actual_make_macro_renders_version_surfaces(self):
        # Use GNU Make's actual double expansion and the real Build/Compile body.
        original=source(); self.make.write_text(self.make.read_text().replace('PKG_VERSION:='+original['version'],'PKG_VERSION:=3.2.0').replace('PKG_RELEASE:='+str(original['release']),'PKG_RELEASE:=23'))
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
        for name in ['root/usr/bin/cf-ip-auto','root/usr/bin/cf-ip-auto-v2','root/usr/bin/cf-ip-auto-legacy','root/usr/libexec/rpcd/cf_ip','htdocs/luci-static/resources/cloudflare-ip/utils.js']:
            text=(self.root/'build'/name).read_text();self.assertNotIn('@PKG_',text)
            self.assertIn(identity['version'],text)
        rpc=(self.root/'build/root/usr/libexec/rpcd/cf_ip').read_text()
        ui=(self.root/'build/htdocs/luci-static/resources/cloudflare-ip/utils.js').read_text()
        self.assertIn(identity['packageVersion'],rpc);self.assertIn(identity['packageVersion'],ui)
        response=subprocess.check_output(['sh',str(self.root/'build/root/usr/libexec/rpcd/cf_ip'),'call','version'],text=True)
        self.assertEqual(json.loads(response)['package_version'],identity['packageVersion'])
        cli_env=dict(env,CFIP_LIB_DIR=str(self.root/'build/root/usr/libexec/cf-ip'),CFIP_RUNTIME_DIR=str(self.root/'runtime'),CFIP_STATUS_DIR=str(self.root/'state'))
        cli=json.loads(subprocess.check_output(['bash',str(self.root/'build/root/usr/bin/cf-ip-auto-v2'),'--version'],text=True,env=cli_env))
        self.assertEqual(cli['package_version'],identity['packageVersion'])
        self.assertEqual(cli['engine_schema'],2);self.assertEqual(cli['runtime_api_version'],3)
        shutil.rmtree(self.root/'build')
        (package/'root/usr/libexec/rpcd/cf_ip').unlink()
        failed=subprocess.run(['make','-f',str(runner),'all'],cwd=package,capture_output=True,text=True,env=env)
        self.assertNotEqual(failed.returncode,0,'missing version template must fail the build')


if __name__=='__main__':unittest.main(verbosity=2)
