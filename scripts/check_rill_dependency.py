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
    if not isinstance(data, dict) or any(not isinstance(data.get(section), dict) for section in ("policy", "resolved", "preview", "openwrtPackage", "qualification", "packageMigration")):
        return ["invalid Runtime contract object sections"]
    if data.get("schemaVersion") != 2:
        errors.append("schemaVersion must be 2")
    if any(data.get("policy", {}).get(k) != v for k,v in {"major": 1, "track": "latest-qualified-stable"}.items()):
        errors.append("policy must be latest-qualified-stable major 1")
    resolved = data.get("resolved", {})
    preview = data.get("preview", {})
    package = data.get("openwrtPackage", {})
    qualification = data.get("qualification", {})
    migration = data.get("packageMigration", {})
    version = resolved.get("version")
    if not isinstance(version, str) or not SEMVER.fullmatch(version):
        errors.append("resolved.version must be Stable 1.x")
    if resolved.get("tag") != f"v{version}":
        errors.append("resolved.tag must match resolved.version")
    if not SHA1.fullmatch(str(resolved.get("upstreamCommit", ""))):
        errors.append("resolved.upstreamCommit must be SHA-1")
    if not SHA256.fullmatch(str(resolved.get("sourceArchiveSha256", ""))):
        errors.append("resolved.sourceArchiveSha256 must be SHA-256")
    if preview.get("repository") != "hello-yunshu/rill-ml" or not SHA1.fullmatch(str(preview.get("commit", ""))):
        errors.append("preview repository/commit is not immutable")
    if preview.get("channel") != "preview-exact-commit":
        errors.append("preview channel must be preview-exact-commit")
    if preview.get("featureSchemaVersion") != 2 or preview.get("modelGeneration") != 2:
        errors.append("preview feature schema/model generation must be v2")
    if package.get("repository") != "hello-yunshu/rill-openwrt-packages":
        errors.append("openwrtPackage.repository is not canonical")
    if not SHA1.fullmatch(str(package.get("commit", ""))):
        errors.append("openwrtPackage.commit must be immutable")
    preview_version = package.get("packageVersion")
    if package.get("package") != "rill-runtime-preview" or not isinstance(preview_version, str) or not SEMVER.fullmatch(preview_version):
        errors.append("Preview Runtime package must have its own valid Stable 1.x version identity")
    if type(package.get("packageRelease")) is not int or package["packageRelease"] <= 0:
        errors.append("Preview Runtime package release must be positive")
    if package.get("binary") != "/usr/bin/rill-runtime":
        errors.append("canonical Runtime binary drifted")
    if type(qualification.get("runId")) is not int or qualification["runId"] <= 0 or qualification.get("workflow") != "qualify.yml":
        errors.append("qualification requires an exact positive run ID and workflow")
    if "runAttempt" in qualification and (type(qualification["runAttempt"]) is not int or qualification["runAttempt"] <= 0 or not SHA256.fullmatch(str(qualification.get("manifestSha256", "")))):
        errors.append("qualification attempt requires a positive attempt and exact manifest SHA-256")
    if qualification.get("required") is not True or qualification.get("verdict") != "PASS":
        errors.append("qualification is not required and PASS")
    historical = {"legacyVersion": "2.6.0-r2", "sourceTag": "v2.6.0-2", "sourceSHA": "652476bd3cdc410bc16e3a47ee96b685c84acbbb"}
    if any(migration.get(k) != v for k, v in historical.items()):
        errors.append("package migration source is not pinned to the audited tag and exact SHA")
    if package_dir:
        makefile = package_dir / "package/rill-runtime-preview/Makefile"
        metadata = package_dir / "metadata/rill-runtime-preview.json"
        if not makefile.is_file() or not metadata.is_file():
            errors.append("package checkout is missing Runtime metadata")
        else:
            make = makefile.read_text(encoding="utf-8")
            meta = json.loads(metadata.read_text(encoding="utf-8"))
            upstream = meta.get("upstream", {})
            release = package.get("packageRelease")
            if meta.get("package", {}).get("release") != release or f"PKG_RELEASE:={release}\n" not in make:
                errors.append("package release does not match contract")
            if f"PKG_VERSION:={preview_version}\n" not in make or upstream.get("version") != preview_version:
                errors.append("Preview package version does not match its independent contract")
            if upstream.get("commit") != preview.get("commit") or f"PKG_SOURCE_VERSION:={preview.get('commit')}" not in make:
                errors.append("Preview package upstream commit does not match contract")
            if meta.get("channel") != "preview-exact-commit" or meta.get("package", {}).get("name") != "rill-runtime-preview":
                errors.append("Preview package metadata is not canonical")
            try:
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
    errors = check_data(old, None)
    if errors:
        raise ValueError("existing contract requires explicit repair/migration: " + "; ".join(errors))
    releases = api("repos/hello-yunshu/rill-ml/releases?per_page=100")
    stable = [r for r in releases if not r.get("draft") and not r.get("prerelease") and SEMVER.fullmatch(str(r.get("tag_name", ""))[1:])]
    if not stable:
        raise RuntimeError("no published Stable Rill 1.x release")
    latest = max(stable, key=lambda r: tuple(int(x) for x in r["tag_name"][1:].split(".")))
    metadata = json.loads((package_dir / "metadata/rill-runtime.json").read_text(encoding="utf-8"))
    preview_metadata = json.loads((package_dir / "metadata/rill-runtime-preview.json").read_text(encoding="utf-8"))
    upstream = metadata.get("upstream", {})
    version = str(latest["tag_name"])[1:]
    if upstream.get("version") != version:
        print(f"WAIT: package qualification is not ready for latest Stable {version}; package has {upstream.get('version')}")
        return 0
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
    qualified_preview = evidence["previewPackage"]
    if evidence["upstream"]["commit"] != upstream["commit"] or evidence["upstream"]["archiveSha256"] != upstream["archiveSha256"]:
        raise ValueError("qualified Stable source differs from package metadata")
    if qualified_preview["upstream"]["commit"] != preview_metadata["upstream"]["commit"]:
        raise ValueError("qualified Preview source differs from package metadata")
    if any(qualified_preview[key] != preview_metadata["package"][key] for key in ("name", "version", "release", "binary")):
        raise ValueError("qualified Preview package differs from package metadata")
    preview_upstream = preview_metadata.get("upstream", {})
    preview_package = preview_metadata.get("package", {})
    contract = {"schemaVersion": 2, "policy": {"major": 1, "track": "latest-qualified-stable"}, "resolved": {"version": version, "tag": latest["tag_name"], "upstreamCommit": upstream["commit"], "sourceArchiveSha256": upstream["archiveSha256"]}, "preview": {"repository": "hello-yunshu/rill-ml", "commit": preview_upstream.get("commit", ""), "channel": preview_metadata.get("channel", "preview-exact-commit"), "featureSchemaVersion": 2, "modelGeneration": 2}, "openwrtPackage": {"repository": "hello-yunshu/rill-openwrt-packages", "commit": package_commit, "package": preview_package.get("name", "rill-runtime-preview"), "packageVersion": preview_package.get("version", version), "packageRelease": preview_package["release"], "binary": preview_package.get("binary", "/usr/bin/rill-runtime")}, "qualification": {"required": True, "workflow": "qualify.yml", "runId": passed["id"], "runAttempt": attempt, "manifestSha256": hashlib.sha256(evidence_raw).hexdigest(), "verdict": "PASS"}}
    candidate = copy.deepcopy(old)
    # Only owned dependency fields may change; preserve migration and extensions,
    # including nested fields introduced by a newer compatible writer.
    for section, updates in contract.items():
        if isinstance(updates, dict):
            if not isinstance(candidate.get(section), dict):
                raise ValueError(f"invalid existing contract section: {section}")
            candidate[section].update(updates)
        else:
            candidate[section] = updates
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
    print(f"PASS: qualified rill-runtime {data['resolved']['version']} from {data['openwrtPackage']['commit']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
