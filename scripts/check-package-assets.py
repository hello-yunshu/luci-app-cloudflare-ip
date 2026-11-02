#!/usr/bin/env python3
"""Check actual SDK bytes/metadata and explicit public target selection."""
from __future__ import annotations
import argparse
import importlib.util
import json
from pathlib import Path
import sys

from package_identity import ROOT, source, validate_metadata, targets, artifact_names

spec = importlib.util.spec_from_file_location('package_inspector', ROOT / 'scripts/openwrt-package-metadata.py')
assert spec and spec.loader
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


def check(directory: Path, release_dir: bool = False, apk_bin: str | None = None) -> list[dict]:
    authority = source()
    if release_dir:
        groups = [(directory, None)]
    else:
        expected = set(artifact_names())
        actual = {p.name for p in directory.iterdir() if p.is_dir()}
        if actual != expected:
            raise ValueError('SDK artifact target set differs from registry')
        groups = [(directory / name, target) for name, target in zip(artifact_names(), targets())]
    results = []
    for folder, target in groups:
        files = [p for p in folder.rglob('*') if p.suffix in ('.ipk', '.apk')]
        for p in files:
            if p.is_symlink() or not p.is_file() or any(a.is_symlink() for a in p.parents if a == directory or directory in a.parents):
                raise ValueError('unsafe package path')
            if not p.name.startswith(('luci-app-cloudflare-ip', 'rill-runtime-preview')):
                raise ValueError('extra unknown package')
        main = [p for p in files if p.name.startswith('luci-app-cloudflare-ip') and '-rill' not in p.name]
        formats = [p.suffix[1:] for p in main]
        wanted = [target['pkgtype']] if target else ['ipk', 'apk']
        if sorted(formats) != sorted(wanted):
            raise ValueError('missing, duplicate, extra or wrong-format base package')
        if release_dir and len(files) != len(main):
            raise ValueError('extra package in public release')
        for p in main:
            metadata = package.inspect(p, p.suffix[1:], apk_bin or str(ROOT / 'scripts/apk-metadata.sh'), authority['name'])
            validate_metadata(metadata['package'], p.name, authority)
            if not release_dir:
                sidecar = Path(str(p) + '.metadata.json')
                if sidecar.is_symlink() or json.loads(sidecar.read_text()) != metadata:
                    raise ValueError('SDK sidecar differs from actual package bytes/metadata')
            results.append({'path': str(p.relative_to(directory)), **metadata})
    if release_dir:
        expected = {p['path']:p['sha256'] for p in results}
        records = []
        for line in (directory / 'sha256sums.txt').read_text().splitlines():
            parts = line.split('  ')
            if len(parts) != 2 or '/' in parts[1] or '\\' in parts[1]:
                raise ValueError('invalid relative checksum record')
            records.append(tuple(parts))
        if len(records) != len(expected) or {name:digest for digest,name in records} != expected:
            raise ValueError('missing, duplicate, extra or replaced checksum')
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--release-dir', action='store_true')
    parser.add_argument('--apk-bin')
    args = parser.parse_args()
    try:
        print(json.dumps(check(args.directory, args.release_dir, args.apk_bin), indent=2))
    except (OSError, ValueError, package.subprocess.CalledProcessError, package.tarfile.TarError) as error:
        parser.exit(1, f'package asset contract invalid: {error}\n')


if __name__ == '__main__':
    main()
