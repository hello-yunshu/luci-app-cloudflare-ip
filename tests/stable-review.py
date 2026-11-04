#!/usr/bin/env python3
"""Review preparation cannot accept stale receipts, missing negatives or occupied tags."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('review', ROOT / 'scripts/prepare-stable-review.py')
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)


class ReviewBoundary(unittest.TestCase):
    def check_case(self, mutation=None, trees=None, refs=None, tag_tree=None):
        with tempfile.TemporaryDirectory() as temp:
            paths = [Path(temp) / name for name in ('manifest.json', 'preflight.json', 'negatives.json')]
            manifest = dict(commit='a' * 40, runId=123, runAttempt=1, releaseEligible=True, assetFiles=[])
            raw = json.dumps(manifest).encode()
            receipt = dict(status='PASS', commit=manifest['commit'], runId=123, runAttempt=1,
                           manifestSha256=hashlib.sha256(raw).hexdigest())
            negatives = dict(receipt, cases=[dict(case=name, status='PASS') for name in review.NEGATIVES])
            if mutation:
                mutation(receipt, negatives)
            paths[0].write_bytes(raw)
            paths[1].write_text(json.dumps(receipt))
            paths[2].write_text(json.dumps(negatives))
            answers = trees or ['c' * 40, 'c' * 40]
            extra = [json.dumps(refs or [])]
            if (refs or []) and tag_tree:
                extra.append(json.dumps({'tree': {'sha': tag_tree}}))
            with patch.object(review.subprocess, 'check_output', side_effect=answers + extra):
                return review.prepare(*paths, 'b' * 40, 'hello-yunshu/luci-app-cloudflare-ip')

    def test_prepared_receipt_never_grants_publication(self):
        result = self.check_case()
        self.assertEqual(result['status'], 'PREPARED_FOR_REVIEW')
        self.assertEqual(result['publication'], 'NOT AUTHORIZED / NOT RUN')
        self.assertEqual(result['automaticStablePromotion'], 'DISABLED')
        self.assertEqual(result['tagState'], 'available')

    def test_existing_tag_at_same_tree_is_release_reuse(self):
        tag = [{'ref': 'refs/tags/' + review.source()['tag'],
                'object': {'type': 'commit', 'sha': 'e' * 40}}]
        result = self.check_case(refs=tag, tag_tree='c' * 40)
        self.assertEqual(result['tagState'], 'existing-equivalent')
        self.assertEqual(result['tagAvailable'], False)
        self.assertEqual(result['tagCommit'], 'e' * 40)

    def test_stale_receipts_and_missing_or_failed_negatives_reject(self):
        changes = [lambda p, n: p.update(runAttempt=2), lambda p, n: p.update(manifestSha256='0' * 64),
                   lambda p, n: n['cases'].pop(), lambda p, n: n['cases'][0].update(status='FAIL')]
        for change in changes:
            with self.subTest(change=change), self.assertRaises(ValueError):
                self.check_case(change)

    def test_tree_mismatch_rejects(self):
        with self.assertRaises(ValueError):
            self.check_case(trees=['c' * 40, 'd' * 40])

    def test_occupied_tag_with_different_tree_is_recorded(self):
        tag = [{'ref': 'refs/tags/' + review.source()['tag'],
                'object': {'type': 'commit', 'sha': 'e' * 40}}]
        result = self.check_case(refs=tag, tag_tree='d' * 40)
        self.assertEqual(result['tagState'], 'occupied-different')
        self.assertEqual(result['tagAvailable'], False)
        self.assertEqual(result['tagConflict'], True)
        self.assertEqual(result['tagCommit'], 'e' * 40)


if __name__ == '__main__':
    unittest.main()
