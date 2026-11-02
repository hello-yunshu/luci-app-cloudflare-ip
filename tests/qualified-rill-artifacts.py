#!/usr/bin/env python3
"""Consumer uses the pinned authoritative verifier; transport negatives live upstream."""
import importlib.util
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock,patch

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('qualified',ROOT/'scripts/qualified_rill_artifacts.py')
qualified=importlib.util.module_from_spec(spec);spec.loader.exec_module(qualified)


class QualifiedConsumer(unittest.TestCase):
    def test_channel_versions_are_independent_but_bounded(self):
        spec=importlib.util.spec_from_file_location('contract_check',ROOT/'scripts/check_rill_dependency.py')
        check=importlib.util.module_from_spec(spec);spec.loader.exec_module(check)
        contract=json.loads((ROOT/'contracts/rill-runtime.json').read_text())
        contract['openwrtPackage']['packageVersion']='1.8.0'
        self.assertEqual(check.check_data(contract,None),[])
        contract['openwrtPackage']['packageVersion']='2.0.0'
        self.assertTrue(check.check_data(contract,None))

    def test_old_package_checkout_without_byte_verifier_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError,'schema 3'):
                qualified.upstream(Path(directory))

    def test_preview_client_delegates_all_byte_verification_to_pinned_authority(self):
        fetch=Mock(return_value=(Path('/fixture/package.ipk'),{'binarySha256':'a'*64}))
        authority=SimpleNamespace(fetch_qualified=fetch)
        contract={'fixture':'consumer identity'};package=Path('/fixture/pinned-package')
        with patch.object(qualified,'upstream',return_value=authority):
            qualified.fetch_preview(contract,package,'25.12.5','aarch64_generic','apk',Path('/fixture/output'),'fixture-apk')
        fetch.assert_called_once_with(contract,package,'25.12.5','aarch64_generic','apk',Path('/fixture/output'),'fixture-apk',channel='preview')


if __name__=='__main__':unittest.main(verbosity=2)
