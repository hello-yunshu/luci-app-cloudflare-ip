#!/usr/bin/env python3
"""Pin the enforcement policy of scripts/check-proxy-upstreams.py.

Policy under test: upstream drift and lookup failures are *reported only* and
never fail the run. A release is blocked by signals that describe failure -- a
failing adapter contract, an invalid qualification manifest, an immutable tag
collision -- not by the mere fact that an upstream published a new version.

The single thing this script may still fail on is a defect in this repository's
own baseline: a missing field or an unsupported upstream kind. These cases exist
so that adding blocking authority back is a visible, reviewed decision rather
than an accident.
"""

import importlib.util
import io
import json
import sys
import tempfile
import unittest
import urllib.error
from contextlib import redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / 'scripts' / 'check-proxy-upstreams.py'

UPSTREAMS = [
    {'name': 'OpenClashLike', 'repo': 'owner/one', 'kind': 'release',
     'observedRef': 'v1', 'qualification': 'CFI drives the provider controller'},
    {'name': 'BranchTracked', 'repo': 'owner/two', 'kind': 'branch', 'branch': 'master',
     'observedRef': 'a' * 40, 'qualification': 'config writes only'},
]


def load_module():
    spec = importlib.util.spec_from_file_location('proxy_upstreams', SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ProxyUpstreamPolicy(unittest.TestCase):

    def run_case(self, resolver, upstreams=UPSTREAMS):
        module = load_module()
        module.current_ref = resolver
        with tempfile.TemporaryDirectory() as tmp:
            baseline = Path(tmp) / 'baseline.json'
            baseline.write_text(json.dumps(
                {'schemaVersion': 1, 'policy': 'test policy', 'upstreams': upstreams}), encoding='utf-8')
            output = Path(tmp) / 'report.json'
            argv = sys.argv
            sys.argv = ['check-proxy-upstreams.py', '--baseline', str(baseline), '--output', str(output)]
            stream = io.StringIO()
            try:
                with redirect_stdout(stream):
                    code = module.main()
            finally:
                sys.argv = argv
            return code, stream.getvalue(), json.loads(output.read_text(encoding='utf-8'))

    def test_matching_refs_pass_and_report_no_drift(self):
        code, summary, report = self.run_case(lambda item: item['observedRef'])
        self.assertEqual(code, 0)
        self.assertTrue(all(row['drift'] is False for row in report['upstreams']))
        self.assertNotIn('DRIFT', summary)

    def test_upstream_drift_is_reported_and_still_passes(self):
        code, summary, report = self.run_case(
            lambda item: 'v2' if item['kind'] == 'release' else 'b' * 40)
        self.assertEqual(code, 0)
        self.assertIn('**DRIFT**', summary)
        self.assertIn('does not block the release', summary)
        rows = {row['name']: row for row in report['upstreams']}
        self.assertTrue(rows['OpenClashLike']['drift'])
        self.assertTrue(rows['BranchTracked']['drift'])
        self.assertEqual(rows['BranchTracked']['currentRef'], 'b' * 40)

    def test_drift_carries_no_blocking_verdict(self):
        """The report must not grow a per-upstream gating field again."""
        _, _, report = self.run_case(lambda item: 'v2')
        for row in report['upstreams']:
            self.assertNotIn('blocking', row)

    def test_lookup_failure_is_reported_and_does_not_block(self):
        def explode(item):
            raise urllib.error.URLError('temporary failure')

        code, summary, report = self.run_case(explode)
        self.assertEqual(code, 0)
        self.assertIn('lookup failed', summary)
        self.assertTrue(all(row['currentRef'] is None for row in report['upstreams']))
        self.assertTrue(all('lookupError' in row for row in report['upstreams']))

    def test_malformed_baseline_entry_fails_the_run(self):
        """A repository defect is still fatal -- that is not upstream news."""
        broken = [
            dict(UPSTREAMS[0]),
            {'name': 'BadKind', 'repo': 'owner/x', 'kind': 'tag',
             'observedRef': 'v1', 'qualification': 'unsupported kind'},
            {'name': 'NoRef', 'repo': 'owner/y', 'kind': 'release',
             'qualification': 'observedRef missing'},
        ]
        code, summary, report = self.run_case(lambda item: item['observedRef'], upstreams=broken)
        self.assertEqual(code, 1)
        self.assertIn('Baseline defects', summary)
        self.assertIn('BadKind', summary)
        self.assertIn('NoRef', summary)
        self.assertIn('observedRef', summary)
        # Valid entries are still reported; defective ones are skipped, not guessed.
        self.assertEqual([row['name'] for row in report['upstreams']], ['OpenClashLike'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
