#!/usr/bin/env python3
"""Source authority and package metadata rules (independent of release numbers)."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ARTIFACT_VERSION = re.compile(r'(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-dev|\.1)?')
VERSION = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-dev)?")
NAME = 'luci-app-cloudflare-ip'


def positive_release(value: object) -> int:
    if type(value) is not int or value <= 0:
        raise ValueError('release must be a positive integer')
    return value


def source(root: Path = ROOT) -> dict:
    text = (root / 'package/luci-app-cloudflare-ip/Makefile').read_text()
    def field(name: str) -> str:
        values = re.findall(rf'^{name}:=(\S+)\s*$', text, re.M)
        if len(values) != 1:
            raise ValueError(f'expected exactly one {name}')
        return values[0]
    version, release_raw = field('PKG_VERSION'), field('PKG_RELEASE')
    if not VERSION.fullmatch(version) or not re.fullmatch(r'[1-9][0-9]*', release_raw):
        raise ValueError('invalid source version/release')
    if field('PKG_NAME') != NAME:
        raise ValueError('unexpected source package name')
    channel = json.loads((root / 'release-channel.json').read_text())
    if not isinstance(channel, dict) or type(channel.get('schemaVersion')) is not int or channel.get('schemaVersion') != 1 or channel.get('channel') not in ('prerelease', 'stable') or not isinstance(channel.get('reason'), str) or not channel['reason'].strip():
        raise ValueError('invalid release channel')
    release = int(release_raw)
    return dict(name=NAME, version=version, release=release, channel=channel['channel'],
                tag=f'v{version}-{release}', packageVersion=f'{version}-r{release}')


def split_version(raw: str, fmt: str) -> tuple[str, int]:
    if fmt not in ('ipk', 'apk') or not isinstance(raw, str):
        raise ValueError('invalid package format/version')
    # Preserve historical IPK -N compatibility; current SDK packages use -rN; APK requires -rN.
    match = re.fullmatch(r'(.+)-r([1-9][0-9]*)', raw)
    if match is None and fmt == 'ipk':
        match = re.fullmatch(r'(.+)-([1-9][0-9]*)', raw)
    if match is None or not ARTIFACT_VERSION.fullmatch(match[1]):
        raise ValueError('package version does not encode a valid source version/release')
    return match[1], int(match[2])


def filename(meta: dict) -> str:
    fmt, arch, raw = meta.get('format'), meta.get('architecture'), meta.get('packageVersion')
    version, release = split_version(raw, fmt)
    if meta.get('name') != NAME or meta.get('version') != version or type(meta.get('release')) is not int or meta['release'] != release:
        raise ValueError('package metadata identity mismatch')
    if arch not in (('all',) if fmt == 'ipk' else ('all', 'noarch')):
        raise ValueError('unexpected package architecture')
    return f'{NAME}_{raw}_{arch}.ipk' if fmt == 'ipk' else f'{NAME}-{raw}.apk'


def build_version(version: str, fmt: str) -> str:
    # Preserve the established SDK development mapping; never use it for promotion.
    return version[:-4] + '.1' if fmt == 'apk' and version.endswith('-dev') else version


def validate_metadata(meta: dict, actual_name: str, authority: dict | None = None) -> None:
    if actual_name != filename(meta):
        raise ValueError('asset filename does not match actual package metadata')
    if authority and (meta['version'], meta['release']) != (build_version(authority['version'], meta['format']), authority['release']):
        raise ValueError('package metadata differs from source authority')


def require_upgrade(old: str, new: str, fmt: str, executable: str) -> None:
    """Use the real manager's ordering, never a guessed lexical/semver comparison."""
    split_version(old, fmt); split_version(new, fmt)
    if fmt == 'ipk':
        result = subprocess.run([executable, 'compare-versions', new, '>>', old], check=False)
        valid = result.returncode == 0
    else:
        result = subprocess.run([executable, 'version', '-t', new, old], capture_output=True, text=True, check=True)
        valid = result.stdout.strip() == '>'
    if not valid:
        raise ValueError('candidate is not a strict package-manager upgrade')


def targets(root: Path = ROOT) -> list[dict]:
    policy = json.loads((root / 'contracts/package-artifacts.json').read_text())
    if not isinstance(policy, dict):
        raise ValueError('invalid package target registry object')
    values = policy.get('targets')
    if not isinstance(policy, dict) or type(policy.get('schemaVersion')) is not int or policy.get('schemaVersion') != 1 or not isinstance(values, list) or not values:
        raise ValueError('invalid package target registry')
    seen = set()
    for t in values:
        if (not isinstance(t, dict) or set(t) != {'branch', 'pkgtype', 'arch', 'rust_target', 'public'}
            or t['pkgtype'] not in ('ipk', 'apk') or type(t['public']) is not bool
            or not all(isinstance(t[k], str) and re.fullmatch(r'[A-Za-z0-9_.-]+', t[k]) for k in ('branch', 'arch', 'rust_target'))):
            raise ValueError('invalid package target')
        key = (t['branch'], t['pkgtype'])
        if key in seen:
            raise ValueError('duplicate artifact target')
        seen.add(key)
    if sorted(t['pkgtype'] for t in values if t['public']) != ['apk', 'ipk']:
        raise ValueError('public policy must select exactly one IPK and APK')
    return values


def artifact_names(root: Path = ROOT, public_only: bool = False) -> list[str]:
    return [f"{NAME}-{t['pkgtype']}-{t['branch']}" for t in targets(root) if not public_only or t['public']]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--field', choices=('name', 'version', 'release', 'channel', 'tag', 'packageVersion'))
    parser.add_argument('--build-version', action='store_true')
    parser.add_argument('--matrix', action='store_true')
    parser.add_argument('--public-artifacts', action='store_true')
    parser.add_argument('--upgrade-from')
    parser.add_argument('--format', choices=('ipk', 'apk'))
    parser.add_argument('--manager')
    args = parser.parse_args()
    try:
        if args.matrix:
            print(json.dumps({"include": targets(args.root)})); return
        if args.public_artifacts:
            print("\n".join(artifact_names(args.root, True))); return
        identity = source(args.root)
        if args.build_version:
            if not args.format: parser.error('--build-version requires --format')
            print(build_version(identity['version'], args.format)); return
        if args.upgrade_from:
            if not args.format or not args.manager:
                parser.error('--upgrade-from requires --format and --manager')
            require_upgrade(args.upgrade_from, identity['packageVersion'], args.format, args.manager)
        print(identity[args.field] if args.field else json.dumps(identity, sort_keys=True))
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        parser.exit(1, f'package identity invalid: {exc}\n')


if __name__ == '__main__':
    main()
