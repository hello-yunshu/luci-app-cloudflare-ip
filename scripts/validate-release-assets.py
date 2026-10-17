#!/usr/bin/env python3
"""Bind uploaded release files to package bytes recorded by exact-run evidence."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import sys
from pathlib import Path, PurePosixPath
sys.path.insert(0, str(Path(__file__).resolve().parent))
from package_identity import validate_metadata

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("qualification_validator", HERE / "validate-qualification-evidence.py")
assert SPEC and SPEC.loader
QUAL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(QUAL)
PACKAGE_SPEC = importlib.util.spec_from_file_location("package_inspector", HERE / "openwrt-package-metadata.py")
assert PACKAGE_SPEC and PACKAGE_SPEC.loader
PACKAGE = importlib.util.module_from_spec(PACKAGE_SPEC)
PACKAGE_SPEC.loader.exec_module(PACKAGE)


def require(ok: bool, message: str) -> None:
    if not ok:
        raise ValueError(message)


def validate(manifest: dict, release_dir: Path, expected_commit: str, expected_run_id: int,
             version: str, release: int, contract_path: Path, apk_bin: str | None = None,
             expected_run_attempt: int | None = None) -> list[Path]:
    QUAL.validate(manifest, expected_commit, 2, True, expected_run_id, contract_path, expected_run_attempt)
    assets = manifest["assetFiles"]
    by_format: dict[str, tuple[dict, str]] = {}
    for item in assets:
        path = item["path"]
        # The evidence path is preserved for provenance; lookup uses its unique basename.
        pure = PurePosixPath(path)
        require(not pure.is_absolute() and all(part not in ("", ".", "..") for part in pure.parts), "unsafe asset path")
        name = pure.name
        fmt = Path(name).suffix[1:]
        require(fmt not in by_format, "duplicate package format")
        by_format[fmt] = (item, name)
    require(set(by_format) == {"ipk", "apk"}, "release must bind one IPK and one APK")
    results: list[Path] = []
    for fmt in ("ipk", "apk"):
        item, name = by_format[fmt]
        meta = item["package"]
        require(meta["version"] == version and meta["release"] == release, f"{fmt} package version/release mismatch")
        require(meta["name"] == "luci-app-cloudflare-ip" and meta["format"] == fmt, f"{fmt} package identity mismatch")
        require(meta["architecture"] in (("all",) if fmt == "ipk" else ("all", "noarch")), f"unexpected {fmt} architecture")
        validate_metadata(meta, name, {"version": version, "release": release})
        matches = [p for p in release_dir.iterdir() if p.is_file() and p.name == name]
        require(all(not p.is_symlink() for p in matches), "symlink release asset")
        require(len(matches) == 1, f"release directory does not contain exactly the evidence asset {name}")
        file = matches[0]
        raw = file.read_bytes()
        require(len(raw) == item["size"], f"asset size mismatch: {name}")
        require(hashlib.sha256(raw).hexdigest() == item["sha256"], f"asset SHA-256 mismatch: {name}")
        actual = PACKAGE.inspect(file, fmt, apk_bin or str(HERE / "apk-metadata.sh"), "luci-app-cloudflare-ip")
        require(actual["sha256"] == item["sha256"] and actual["size"] == item["size"], "package changed during evidence validation")
        require(actual["package"] == meta, f"{fmt} actual package metadata differs from evidence")
        results.append(file)
    package_files = [p for p in release_dir.rglob("*") if p.suffix in (".ipk", ".apk")]
    require(set(package_files) == set(results), "release directory contains an extra or substituted package")
    return results


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("release_dir", type=Path)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--run-attempt", type=int, required=True)
    parser.add_argument("--run-id", type=int, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--release", type=int, required=True)
    parser.add_argument("--apk-bin", help="real apk tool (defaults to read-only Linux adapter)")
    parser.add_argument("--contract", type=Path, default=HERE.parent / "contracts/rill-runtime.json")
    args = parser.parse_args()
    try:
        manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
        files = validate(manifest, args.release_dir, args.commit, args.run_id, args.version, args.release, args.contract, args.apk_bin, args.run_attempt)
        print("release assets are bound to qualification evidence: " + ", ".join(p.name for p in files))
    except (OSError, json.JSONDecodeError, ValueError, KeyError, TypeError, PACKAGE.subprocess.CalledProcessError, PACKAGE.tarfile.TarError) as exc:
        print(f"release asset binding invalid: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
