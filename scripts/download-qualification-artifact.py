#!/usr/bin/env python3
"""Download one exact-attempt artifact into a caller-selected logical directory."""
import argparse
import json
import re
import subprocess


def scoped_name(base, run_id, attempt):
    if not isinstance(base, str) or not re.fullmatch(r'[A-Za-z0-9_.-]+', base):
        raise ValueError('invalid artifact base name')
    if any(type(v) is not int or v <= 0 for v in (run_id, attempt)):
        raise ValueError('run ID and attempt must be positive integers')
    return f'{base}-run-{run_id}-attempt-{attempt}'


def download(repo, run_id, attempt, commit, base, directory):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo):
        raise ValueError('invalid repository')
    if not re.fullmatch(r'[a-f0-9]{40}', commit):
        raise ValueError('exact commit required')
    name = scoped_name(base, run_id, attempt)
    def api(path):
        return json.loads(subprocess.check_output(['gh', 'api', path], text=True))
    source = api(f'repos/{repo}/actions/runs/{run_id}/attempts/{attempt}')
    if source.get('head_sha') != commit or source.get('run_attempt') != attempt or source.get('id') != run_id:
        raise ValueError('source workflow run/attempt/SHA mismatch')
    pages = json.loads(subprocess.check_output(['gh', 'api', '--paginate', '--slurp',
        f'repos/{repo}/actions/runs/{run_id}/artifacts?per_page=100'], text=True))
    matches = [a for page in pages for a in page['artifacts'] if a['name'] == name]
    if len(matches) != 1 or matches[0].get('expired') is not False:
        raise ValueError('missing, duplicate or expired exact-attempt artifact')
    subprocess.run(['gh', 'run', 'download', str(run_id), '--repo', repo,
                    '--name', name, '--dir', directory], check=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--repo', required=True)
    p.add_argument('--run-id', required=True, type=int)
    p.add_argument('--run-attempt', required=True, type=int)
    p.add_argument('--commit', required=True)
    p.add_argument('--name', required=True)
    p.add_argument('--dir', required=True)
    a = p.parse_args()
    try:
        download(a.repo, a.run_id, a.run_attempt, a.commit, a.name, a.dir)
    except (ValueError, KeyError, subprocess.CalledProcessError) as exc:
        p.exit(1, f'qualification artifact rejected: {exc}\n')


if __name__ == '__main__':
    main()
