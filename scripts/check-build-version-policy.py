#!/usr/bin/env python3
"""Validate version eligibility for a build context; publication has stricter gates."""
import os
import sys
from package_identity import source


def validate(identity, ref, event, base):
    release_context = (ref == 'refs/heads/main' or ref.startswith('refs/heads/release/')
                       or (event == 'pull_request' and (base == 'main' or base.startswith('release/'))))
    development = identity['version'].endswith('-dev')
    if development and (release_context or identity['channel'] == 'stable'):
        raise ValueError('development version is not eligible for a release context or Stable channel')
    # A feature branch may inherit the final candidate version for exact-SHA tests.
    # This grants build eligibility only, never permission to publish that branch.


if __name__ == '__main__':
    try:
        validate(source(), os.environ['GITHUB_REF'], os.environ['GITHUB_EVENT_NAME'],
                 os.environ.get('GITHUB_BASE_REF', ''))
    except (ValueError, KeyError, OSError) as exc:
        print(f'build version policy rejected: {exc}', file=sys.stderr)
        raise SystemExit(1)
    print('source version is eligible for this build context')
