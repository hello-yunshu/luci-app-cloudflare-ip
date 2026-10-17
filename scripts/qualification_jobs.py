#!/usr/bin/env python3
"""Required CI job predicate, shared by evidence generation and promotion."""
import json
import sys

REQUIRED_JOBS = (
    'package-identity', 'host-contract', 'legacy-contract', 'rpc-luci-contract',
    'openwrt-package', 'package-migration', 'rill-runtime-integration',
    'package-release-guard', 'workflow-lint', 'real-cfst-smoke',
    'release-asset-contract', 'docker-replay',
)


def require_success(jobs):
    if not isinstance(jobs, dict) or set(jobs) != set(REQUIRED_JOBS):
        raise ValueError('qualification job set differs from required jobs')
    for name in REQUIRED_JOBS:
        job = jobs[name]
        if not isinstance(job, dict) or job.get('result') != 'success':
            raise ValueError(f'required qualification job {name} did not succeed')


if __name__ == '__main__':
    try:
        require_success(json.load(sys.stdin))
    except (ValueError, TypeError) as exc:
        print(f'qualification jobs rejected: {exc}', file=sys.stderr)
        raise SystemExit(1)
    print('all required qualification jobs succeeded')
