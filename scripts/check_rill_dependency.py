#!/usr/bin/env python3
"""Validate Cloudflare IP's immutable qualified Rill Runtime contract."""

from __future__ import annotations

import argparse
import hashlib
import copy
import os
import tempfile
import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from qualified_rill_artifacts import fetch_manifest

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "contracts/rill-runtime.json"
SHA1 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
SEMVER = re.compile(r"^1\.\d+\.\d+$")


def check(package_dir: Path | None) -> list[str]:
    return check_data(json.loads(CONTRACT.read_text(encoding="utf-8")), package_dir)


def check_data(data: dict, package_dir: Path | None) -> list[str]:
    errors: list[str] = []
    if not isinstance(data, dict) or any(not isinstance(data.get(section), dict) for section in ("policy", "resolved", "openwrtPackage", "qualification", "packageMigration", "legacyRuntime")):
        return ["invalid Runtime contract object sections"]
    if data.get("schemaVersion") != 3:
        errors.append("schemaVersion must be 3")
    if any(data.get("policy", {}).get(k) != v for k,v in {"major": 1, "track": "latest-qualified-stable"}.items()):
        errors.append("policy must be latest-qualified-stable major 1")
    resolved = data.get("resolved", {})
    package = data.get("openwrtPackage", {})
    qualification = data.get("qualification", {})
    migration = data.get("packageMigration", {})
    legacy = data.get("legacyRuntime", {})
    version = resolved.get("version")
    if not isinstance(version, str) or not SEMVER.fullmatch(version):
        errors.append("resolved.version must be Stable 1.x")
    if not isinstance(resolved.get("tag"), str) or not resolved["tag"]:
        errors.append("resolved.tag must identify the immutable Stable source")
    if not SHA1.fullmatch(str(resolved.get("upstreamCommit", ""))):
        errors.append("resolved.upstreamCommit must be SHA-1")
    elif resolved.get("tag") not in (f"v{version}", f"stable-main-{resolved['upstreamCommit'][:7]}"):
        errors.append("resolved.tag is not a Stable release tag or commit-derived stable-main pin")
    if resolved.get("sourceType") != "immutable-git-commit":
        errors.append("resolved.sourceType must be immutable-git-commit")
    if package.get("repository") != "hello-yunshu/rill-openwrt-packages":
        errors.append("openwrtPackage.repository is not canonical")
    if package.get("commit") is not None and not SHA1.fullmatch(str(package.get("commit", ""))):
        errors.append("openwrtPackage.commit must be immutable")
    package_version = package.get("packageVersion")
    if package.get("package") != "rill-runtime" or package.get("channel") != "stable" or not isinstance(package_version, str) or not SEMVER.fullmatch(package_version):
        errors.append("canonical Runtime package must be rill-runtime on the Stable channel")
    elif package_version != version:
        errors.append("Stable package version must match the resolved Runtime version")
    if type(package.get("packageRelease")) is not int or package["packageRelease"] <= 0:
        errors.append("Stable Runtime package release must be positive")
    if package.get("binary") != "/usr/bin/rill-runtime":
        errors.append("canonical Runtime binary drifted")
    if qualification.get("workflow") != "qualify.yml" or qualification.get("required") is not True or qualification.get("manifestSchemaVersion") != 4:
        errors.append("qualification must require the schema 4 Stable package workflow")
    if qualification.get("status") == "PASS":
        if not SHA1.fullmatch(str(package.get("commit", ""))):
            errors.append("qualified contract requires immutable package commit")
        if type(qualification.get("runId")) is not int or qualification["runId"] <= 0 or type(qualification.get("runAttempt")) is not int or qualification["runAttempt"] <= 0:
            errors.append("qualified contract requires exact positive run ID and attempt")
        if not SHA256.fullmatch(str(qualification.get("manifestSha256", ""))):
            errors.append("qualified contract requires exact manifest SHA-256")
    elif qualification.get("status") != "PENDING":
        errors.append("qualification status must be PENDING or PASS")
    if legacy != {"package": "rill-runtime-preview", "channel": "legacy-preview", "migration": "explicit-uninstall-required"}:
        errors.append("legacy Preview package must remain an explicit migration conflict")
    historical = {"legacyVersion": "2.6.0-r2", "sourceTag": "v2.6.0-2", "sourceSHA": "652476bd3cdc410bc16e3a47ee96b685c84acbbb"}
    if any(migration.get(k) != v for k, v in historical.items()):
        errors.append("package migration source is not pinned to the audited tag and exact SHA")
    if package_dir:
        makefile = package_dir / "package/rill-runtime/Makefile"
        metadata = package_dir / "metadata/rill-runtime.json"
        if not makefile.is_file() or not metadata.is_file():
            errors.append("package checkout is missing Runtime metadata")
        else:
            make = makefile.read_text(encoding="utf-8")
            meta = json.loads(metadata.read_text(encoding="utf-8"))
            upstream = meta.get("upstream", {})
            release = package.get("packageRelease")
            meta_package = meta.get("package", {})
            if meta_package.get("release") != release or f"PKG_RELEASE:={release}\n" not in make:
                errors.append("package release does not match contract")
            version_file = package_dir / "VERSION"
            versioned_recipe = any(line.startswith("PKG_VERSION:=") and "$(RILL_VERSION_FILE)" in line
                                   for line in make.splitlines())
            version_matches = (version_file.is_file() and version_file.read_text(encoding="utf-8").strip() == package_version
                               if versioned_recipe else f"PKG_VERSION:={package_version}" in make.splitlines())
            if not version_matches or upstream.get("version") != package_version:
                errors.append("Stable package version does not match its upstream identity")
            if upstream.get("commit") != resolved.get("upstreamCommit") or f"PKG_SOURCE_VERSION:={resolved.get('upstreamCommit')}" not in make:
                errors.append("Stable package upstream commit does not match contract")
            if meta_package.get("name") != "rill-runtime" or meta_package.get("binary") != package.get("binary"):
                errors.append("Stable package metadata is not canonical")
            if upstream.get("tag") != resolved.get("tag"):
                errors.append("Stable package source tag does not match contract")
            try:
                if package.get("commit") is not None:
                    head = subprocess.run(["git", "-C", str(package_dir), "rev-parse", "HEAD"], check=True, capture_output=True, text=True).stdout.strip()
                    if head != package.get("commit"):
                        errors.append("package checkout HEAD does not match contract")
            except (OSError, subprocess.CalledProcessError) as error:
                errors.append(f"cannot resolve package checkout HEAD: {error}")
    return errors


def api(path: str):
    # gh scopes the workflow's GH_TOKEN and handles authenticated redirects.
    return json.loads(subprocess.check_output(["gh", "api", path], text=True))


def sync(package_dir: Path) -> int:
    old = json.loads(CONTRACT.read_text(encoding="utf-8"))
    old_errors = check_data(old, None)
    if old_errors:
        raise ValueError("existing Runtime contract is invalid: " + "; ".join(old_errors))
    migration = old.get("packageMigration")
    if not isinstance(migration, dict):
        raise ValueError("existing package migration pin is missing")
    metadata = json.loads((package_dir / "metadata/rill-runtime.json").read_text(encoding="utf-8"))
    upstream = metadata.get("upstream", {})
    package_meta = metadata.get("package", {})
    version = str(upstream.get("version", ""))
    if not SEMVER.fullmatch(version) or package_meta.get("name") != "rill-runtime":
        raise ValueError("canonical Runtime metadata is not a Stable single-package identity")
    if upstream.get("sourceType") != "immutable-git-commit" or not SHA1.fullmatch(str(upstream.get("commit", ""))):
        raise ValueError("Stable Runtime source must be pinned to an immutable Git commit")
    if upstream.get("tag") != f"stable-main-{upstream['commit'][:7]}":
        raise ValueError("Stable Runtime source tag does not match its immutable commit")
    package_commit = subprocess.run(["git", "-C", str(package_dir), "rev-parse", "HEAD"], check=True, capture_output=True, text=True).stdout.strip()
    runs = api(f"repos/hello-yunshu/rill-openwrt-packages/actions/workflows/qualify.yml/runs?head_sha={package_commit}&status=completed&per_page=100").get("workflow_runs", [])
    passed = next((run for run in runs if run.get("conclusion") == "success"), None)
    if not passed:
        print(f"WAIT: no successful qualify.yml run for package commit {package_commit}")
        return 0
    attempt = passed.get("run_attempt")
    if type(attempt) is not int or attempt <= 0:
        raise ValueError("successful qualification run has no exact attempt identity")
    evidence, evidence_raw, _ = fetch_manifest(passed["id"], attempt, package_commit, package_dir)
    qualified_package = evidence.get("package", {})
    qualified_upstream = evidence.get("upstream", {})
    if qualified_upstream.get("commit") != upstream.get("commit") or (upstream.get("archiveSha256") and qualified_upstream.get("archiveSha256") != upstream.get("archiveSha256")):
        raise ValueError("qualified Stable source differs from package metadata")
    if any(qualified_package.get(key) != package_meta.get(field) for key, field in (("name", "name"), ("version", "version"), ("release", "release"), ("binary", "binary"))):
        raise ValueError("qualified Stable package differs from package metadata")
    if qualified_upstream.get("sourceType") != upstream.get("sourceType") or qualified_upstream.get("tag") != upstream.get("tag"):
        raise ValueError("qualified Stable source type/tag differs from package metadata")
    resolved = {"version": version, "tag": upstream["tag"], "upstreamCommit": upstream["commit"], "sourceType": upstream["sourceType"]}
    contract = {
        "schemaVersion": 3,
        "policy": {"major": 1, "track": "latest-qualified-stable"},
        "resolved": resolved,
        "openwrtPackage": {
            "repository": "hello-yunshu/rill-openwrt-packages",
            "commit": package_commit,
            "package": "rill-runtime",
            "packageVersion": package_meta["version"],
            "packageRelease": package_meta["release"],
            "channel": "stable",
            "binary": package_meta.get("binary", "/usr/bin/rill-runtime"),
        },
        "qualification": {
            "required": True,
            "workflow": "qualify.yml",
            "manifestSchemaVersion": 4,
            "status": "PASS",
            "runId": passed["id"],
            "runAttempt": attempt,
            "manifestSha256": hashlib.sha256(evidence_raw).hexdigest(),
        },
        "legacyRuntime": {"package": "rill-runtime-preview", "channel": "legacy-preview", "migration": "explicit-uninstall-required"},
    }
    candidate = copy.deepcopy(old)
    for key, value in contract.items():
        if key in {"resolved", "openwrtPackage", "qualification", "legacyRuntime"} and isinstance(candidate.get(key), dict):
            candidate[key].update(value)
        else:
            candidate[key] = value
    errors = check_data(candidate, package_dir)
    if errors:
        raise ValueError("; ".join(errors))
    if candidate == old:
        print("No qualified Runtime contract change.")
        return 0
    raw = json.dumps(candidate, indent=2) + "\n"
    descriptor, temporary = tempfile.mkstemp(prefix=".rill-contract-", dir=CONTRACT.parent)
    try:
        os.fchmod(descriptor, CONTRACT.stat().st_mode & 0o777)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
        if check_data(json.loads(Path(temporary).read_text()), package_dir):
            raise ValueError("serialized Runtime contract failed validation")
        os.replace(temporary, CONTRACT)
    finally:
        Path(temporary).unlink(missing_ok=True)
    print(json.dumps(candidate, indent=2))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package-dir", type=Path)
    parser.add_argument("--sync", action="store_true", help="resolve latest qualified Stable 1.x and update the contract")
    args = parser.parse_args()
    if args.sync:
        if not args.package_dir:
            parser.error("--sync requires --package-dir")
        try:
            return sync(args.package_dir)
        except (OSError, ValueError, KeyError, RuntimeError, subprocess.CalledProcessError) as error:
            print(f"FAIL: {error}", file=sys.stderr)
            return 1
    errors = check(args.package_dir)
    if errors:
        for error in errors:
            print(f"FAIL: {error}", file=sys.stderr)
        return 1
    data = json.loads(CONTRACT.read_text(encoding="utf-8"))
    qualification = data["qualification"]
    if qualification.get("status") == "PENDING":
        print(f"WAIT: stable rill-runtime {data['openwrtPackage']['packageVersion']}-r{data['openwrtPackage']['packageRelease']} awaits schema 4 qualification for package commit {data['openwrtPackage']['commit']}")
    else:
        print(f"PASS: qualified stable rill-runtime {data['resolved']['version']} from {data['openwrtPackage']['commit']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
