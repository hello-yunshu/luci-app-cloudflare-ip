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


def parse_control(raw: bytes) -> dict[str, str]:
    fields: dict[str, str] = {}
    for line in raw.decode("utf-8", errors="strict").splitlines():
        if not line or line[:1].isspace() or ":" not in line:
            continue
        key, value = line.split(":", 1)
        fields[key.strip().lower()] = value.strip()
    return fields


def ipk_control(path: Path) -> dict[str, str]:
    data = path.read_bytes()
    if not data.startswith(b"!<arch>\n"):
        raise ValueError("IPK is not an ar archive")
    offset = 8
    members: dict[str, bytes] = {}
    while offset < len(data):
        header = data[offset:offset + 60]
        if len(header) != 60 or header[58:60] != b"`\n":
            raise ValueError("invalid IPK ar member header")
        name = header[:16].decode("ascii", errors="strict").strip().rstrip("/")
        size = int(header[48:58].decode("ascii").strip())
        offset += 60
        payload = data[offset:offset + size]
        if len(payload) != size:
            raise ValueError("truncated IPK ar member")
        members[name] = payload
        offset += size + (size & 1)
    control_name = next((n for n in members if n.startswith("control.tar")), None)
    if not control_name:
        raise ValueError("IPK has no control archive")
    import io
    with tarfile.open(fileobj=io.BytesIO(members[control_name]), mode="r:*") as archive:
        candidates = [m for m in archive.getmembers() if Path(m.name).name == "control" and m.isfile()]
        if len(candidates) != 1:
            raise ValueError("IPK must contain exactly one control record")
        stream = archive.extractfile(candidates[0])
        if stream is None:
            raise ValueError("could not read IPK control record")
        return parse_control(stream.read())


def find_apk_record(value: object, expected_name: str) -> dict[str, str] | None:
    if isinstance(value, list):
        for item in value:
            found = find_apk_record(item, expected_name)
            if found:
                return found
    elif isinstance(value, dict):
        name = value.get("name", value.get("N"))
        if name == expected_name:
            version = value.get("version", value.get("V"))
            arch = value.get("architecture", value.get("arch", value.get("A")))
            if isinstance(version, str) and isinstance(arch, str):
                return {"package": name, "version": version, "architecture": arch}
        if expected_name in value and isinstance(value[expected_name], dict):
            inner = value[expected_name]
            version = inner.get("version", inner.get("V"))
            arch = inner.get("architecture", inner.get("arch", inner.get("A")))
            if isinstance(version, str) and isinstance(arch, str):
                return {"package": expected_name, "version": version, "architecture": arch}
        for item in value.values():
            found = find_apk_record(item, expected_name)
            if found:
                return found
    return None


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
    patterns = [r"^(.+)-r([0-9]+)$", r"^(.+)-([0-9]+)$"] if package_type == "apk" else [r"^(.+)-([0-9]+)$"]
    for pattern in patterns:
        match = re.fullmatch(pattern, value)
        if match:
            return match.group(1), match.group(2)
    raise ValueError(f"package version does not encode a release number: {value}")


def inspect(path: Path, package_type: str, apk_bin: str, expected_name: str) -> dict:
    if package_type == "ipk":
        fields = ipk_control(path)
        record = {"package": fields.get("package"), "version": fields.get("version"), "architecture": fields.get("architecture")}
    else:
        record = apk_record(path, apk_bin, expected_name)
    if record.get("package") != expected_name:
        raise ValueError(f"unexpected package name: {record.get('package')!r}")
    if not all(isinstance(record.get(key), str) and record[key] for key in ("package", "version", "architecture")):
        raise ValueError("package metadata is incomplete")
    version, release = split_version(record["version"], package_type)
    raw = path.read_bytes()
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
    args = parser.parse_args()
    try:
        result = inspect(args.package, args.format, args.apk_bin, args.package_name)
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
