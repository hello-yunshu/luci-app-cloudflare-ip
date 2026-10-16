#!/usr/bin/env python3
"""Inspect package identity directly from OpenWrt IPK/APK artifacts."""
from __future__ import annotations
import argparse
import hashlib
import json
import re
import subprocess
import sys
import tarfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from package_identity import split_version as decode_version, validate_metadata, source


def parse_control(raw: bytes) -> dict[str, str]:
    fields: dict[str, str] = {}
    for line in raw.decode("utf-8", errors="strict").splitlines():
        if not line or line[:1].isspace() or ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip().lower()
        if key in fields:
            raise ValueError("duplicate IPK control field")
        fields[key] = value.strip()
    return fields


def ipk_control(path: Path, data: bytes | None = None) -> dict[str, str]:
    data = path.read_bytes() if data is None else data
    import io

    # OpenWrt SDKs use both Debian ar IPKs and the newer gzip-tar IPK
    # container. In both formats the control archive is a nested tar file.
    if data.startswith(b"!<arch>\n"):
        offset = 8
        members: dict[str, bytes] = {}
        while offset < len(data):
            header = data[offset:offset + 60]
            if len(header) != 60 or header[58:60] != b"`\n":
                raise ValueError("invalid IPK ar member header")
            name = header[:16].decode("ascii", errors="strict").strip().rstrip("/")
            size = int(header[48:58].decode("ascii").strip())
            offset += 60
            if size < 0 or name in members:
                raise ValueError("invalid/duplicate IPK archive member")
            payload = data[offset:offset + size]
            if len(payload) != size:
                raise ValueError("truncated IPK ar member")
            members[name] = payload
            offset += size + (size & 1)
    else:
        try:
            with tarfile.open(fileobj=io.BytesIO(data), mode="r:*") as archive:
                members = {}
                for member in archive.getmembers():
                    name = Path(member.name).name
                    if name.startswith("control.tar") and member.isfile():
                        if name in members:
                            raise ValueError("duplicate IPK control archive")
                        stream = archive.extractfile(member)
                        if stream is None:
                            raise ValueError("unreadable IPK control archive")
                        members[name] = stream.read()

        except tarfile.TarError as exc:
            raise ValueError("IPK is neither an ar archive nor a tar container") from exc

    control_archives = [payload for name, payload in members.items() if name.startswith("control.tar")]
    if len(control_archives) != 1:
        raise ValueError("IPK must contain exactly one control archive")
    with tarfile.open(fileobj=io.BytesIO(control_archives[0]), mode="r:*") as archive:
        candidates = [m for m in archive.getmembers() if Path(m.name).name == "control" and m.isfile()]
        if len(candidates) != 1:
            raise ValueError("IPK must contain exactly one control record")
        stream = archive.extractfile(candidates[0])
        if stream is None:
            raise ValueError("could not read IPK control record")
        return parse_control(stream.read())


def find_apk_record(value: object, expected_name: str) -> dict[str, str] | None:
    records = []
    def visit(item):
        if isinstance(item, list):
            for child in item:
                visit(child)
        elif isinstance(item, dict):
            name = item.get("name", item.get("N"))
            if name == expected_name:
                version = item.get("version", item.get("V"))
                arch = item.get("architecture", item.get("arch", item.get("A")))
                if version is None and arch is None:
                    return  # A payload file may have the same name as the package.
                if not isinstance(version, str) or not isinstance(arch, str):
                    raise ValueError("incomplete APK identity")
                records.append({"package": name, "version": version, "architecture": arch})
                return
            for key, child in item.items():
                if key == expected_name and isinstance(child, dict) and "name" not in child and "N" not in child:
                    visit(dict(child, name=expected_name))
                else:
                    visit(child)
    visit(value)
    if len(records) > 1:
        raise ValueError("duplicate APK package identity")
    return records[0] if records else None


def apk_record(path: Path, apk_bin: str, expected_name: str) -> dict[str, str]:
    result = subprocess.run([apk_bin, "--allow-untrusted", "adbdump", "--format", "json", str(path)], check=True, capture_output=True, text=True)
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise ValueError("apk adbdump did not return JSON metadata") from exc
    record = find_apk_record(data, expected_name)
    if record is None:
        raise ValueError("APK metadata does not contain the expected package name/version/architecture")
    return record


def split_version(value: str, package_type: str) -> tuple[str, str]:
    version, release = decode_version(value, package_type)
    return version, str(release)


def inspect(path: Path, package_type: str, apk_bin: str, expected_name: str) -> dict:
    if path.is_symlink() or not path.is_file():
        raise ValueError("package must be a regular non-symlink file")
    raw = path.read_bytes()
    if package_type == "ipk":
        fields = ipk_control(path, raw)
        record = {"package": fields.get("package"), "version": fields.get("version"), "architecture": fields.get("architecture")}
    else:
        record = apk_record(path, apk_bin, expected_name)
    if record.get("package") != expected_name:
        raise ValueError(f"unexpected package name: {record.get('package')!r}")
    if not all(isinstance(record.get(key), str) and record[key] for key in ("package", "version", "architecture")):
        raise ValueError("package metadata is incomplete")
    version, release = split_version(record["version"], package_type)
    if path.read_bytes() != raw:
        raise ValueError("package changed while metadata was inspected")
    return {
        "schemaVersion": 1,
        "sha256": hashlib.sha256(raw).hexdigest(),
        "size": len(raw),
        "package": {
            "name": record["package"],
            "version": version,
            "release": int(release),
            "architecture": record["architecture"],
            "format": package_type,
            "packageVersion": record["version"],
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("package", type=Path)
    parser.add_argument("--format", choices=("ipk", "apk"), required=True)
    parser.add_argument("--apk-bin", default="apk")
    parser.add_argument("--package-name", default="luci-app-cloudflare-ip")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--source-root", type=Path, help="require source identity and canonical filename")
    args = parser.parse_args()
    try:
        result = inspect(args.package, args.format, args.apk_bin, args.package_name)
        if args.source_root:
            validate_metadata(result["package"], args.package.name, source(args.source_root))
        rendered = json.dumps(result, sort_keys=True) + "\n"
        if args.output:
            args.output.write_text(rendered, encoding="utf-8")
        else:
            sys.stdout.write(rendered)
    except (OSError, ValueError, subprocess.CalledProcessError, tarfile.TarError) as exc:
        print(f"package metadata invalid: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
