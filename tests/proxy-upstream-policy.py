#!/usr/bin/env python3
"""Pin the enforcement policy of scripts/check-proxy-upstreams.py.

The canary reports drift for every upstream, but only blocks the release for
upstreams whose baseline entry is not marked ``"blocking": false``. Lookup
failures never block. These cases exist so that relaxing or tightening that
policy is a visible, reviewed decision rather than an accident.
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
    {'name': 'BlockingOne', 'repo': 'owner/blocking', 'kind': 'release',
     'observedRef': 'v1', 'qualification': 'claims a runtime transaction'},
    {'name': 'InfoOne', 'repo': 'owner/info', 'kind': 'release',
     'observedRef': 'v1', 'blocking': False, 'qualification': 'writes config only'},
]


def load_module():
    spec = importlib.util.spec_from_file_location('proxy_upstreams', SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ProxyUpstreamPolicy(unittest.TestCase):

    def run_case(self, resolver):
        module = load_module()
        module.current_ref = resolver
        with tempfile.TemporaryDirectory() as tmp:
            baseline = Path(tmp) / 'baseline.json'
            baseline.write_text(json.dumps(
                {'schemaVersion': 1, 'policy': 'test policy', 'upstreams': UPSTREAMS}), encoding='utf-8')
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

    def test_blocking_upstream_drift_fails_the_run(self):
        code, summary, report = self.run_case(
            lambda item: 'v2' if item['name'] == 'BlockingOne' else item['observedRef'])
        self.assertEqual(code, 1)
        self.assertIn('Requalification required', summary)
        row = next(row for row in report['upstreams'] if row['name'] == 'BlockingOne')
        self.assertTrue(row['blocking'])
        self.assertTrue(row['drift'])

    def test_non_blocking_upstream_drift_is_reported_but_passes(self):
        code, summary, report = self.run_case(
            lambda item: 'v2' if item['name'] == 'InfoOne' else item['observedRef'])
        self.assertEqual(code, 0)
        self.assertIn('Reported only', summary)
        self.assertIn('DRIFT (info)', summary)
        self.assertNotIn('Requalification required', summary)
        row = next(row for row in report['upstreams'] if row['name'] == 'InfoOne')
        self.assertFalse(row['blocking'])
        self.assertTrue(row['drift'])

    def test_lookup_failure_is_reported_and_does_not_block(self):
        def explode(item):
            raise urllib.error.URLError('temporary failure')

        code, summary, report = self.run_case(explode)
        self.assertEqual(code, 0)
        self.assertIn('lookup failed', summary)
        self.assertTrue(all(row['currentRef'] is None for row in report['upstreams']))
        self.assertTrue(all('lookupError' in row for row in report['upstreams']))


if __name__ == '__main__':
    unittest.main(verbosity=2)
