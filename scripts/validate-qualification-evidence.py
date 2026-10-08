#!/usr/bin/env python3
"""Single qualification predicate shared by CI evidence and release promotion."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

HEX40 = re.compile(r"^[0-9a-fA-F]{40}$")
HEX64 = re.compile(r"^[0-9a-fA-F]{64}$")


def fail(message: str) -> int:
    print(f"qualification evidence invalid: {message}", file=sys.stderr)
    return 1


def require(value: object, condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def validate(
    manifest: dict,
    expected_commit: str | None,
    require_assets: int | None,
    require_release_eligible: bool = False,
    expected_run_id: int | None = None,
    contract_path: Path | None = None,
) -> None:
    require(manifest, isinstance(manifest, dict), "manifest must be an object")
    if require_release_eligible:
        require(expected_commit, isinstance(expected_commit, str) and bool(HEX40.fullmatch(expected_commit)), "strict release validation requires the exact expected commit SHA")
        require(expected_run_id, isinstance(expected_run_id, int) and not isinstance(expected_run_id, bool) and expected_run_id > 0, "strict release validation requires the exact positive source workflow run ID")
    require(manifest.get("schemaVersion"), manifest.get("schemaVersion") == 1, "schemaVersion must be 1")
    commit = manifest.get("commit")
    require(commit, isinstance(commit, str) and bool(HEX40.fullmatch(commit)), "commit must be a 40-digit SHA")
    if expected_commit is not None:
        require(commit, commit == expected_commit, "manifest commit does not match expected exact SHA")
    eligible = manifest.get("releaseEligible")
    require(eligible, isinstance(eligible, bool), "releaseEligible must be boolean")
    require(manifest.get("qualificationState"), isinstance(manifest.get("qualificationState"), str), "qualificationState missing")
    if require_release_eligible:
        require(eligible, eligible is True, "releaseEligible must be true")
        require(manifest.get("qualificationState"), manifest.get("qualificationState") == "automated-qualification", "qualificationState is not automated-qualification")
        run_id = manifest.get("runId")
        require(run_id, isinstance(run_id, int) and not isinstance(run_id, bool) and run_id > 0, "runId must be a positive integer")
        if expected_run_id is not None:
            require(run_id, run_id == expected_run_id, "manifest runId does not match the source qualification workflow run")
    if not eligible:
        require(require_release_eligible, not require_release_eligible, "releaseEligible is false")
        return
    require(manifest.get("qualificationState"), manifest["qualificationState"] == "automated-qualification", "qualificationState is not automated-qualification")
    migration = manifest.get("packageMigration")
    require(migration, isinstance(migration, dict), "package migration evidence missing")
    require(migration.get("legacyVersion"), migration.get("legacyVersion") == "2.6.0-r2", "wrong legacy package version")
    require(migration.get("sourceTag"), migration.get("sourceTag") == "v2.6.0-2", "wrong migration source tag")
    require(migration.get("sourceSHA"), isinstance(migration.get("sourceSHA"), str) and bool(HEX40.fullmatch(migration["sourceSHA"])), "wrong migration source SHA")
    require(migration.get("currentSHA"), migration.get("currentSHA") == commit, "migration evidence does not match qualification SHA")
    for field in ("ipk", "apk"):
        require(field, migration.get(field) == "PASS", f"package migration {field} is not PASS")
    for field in ("baseOnlyUpgrade", "baseAddonToBaseUpgrade", "addonRemovalSafe", "r3ToR4", "runtimeAbsent", "runtimePresent"):
        require(field, migration.get(field) is True, f"package migration {field} is not true")
    rill = manifest.get("rill")
    require(rill, isinstance(rill, dict), "rill evidence missing")
    require(rill.get("schemaVersion"), rill.get("schemaVersion") == 1, "rill schemaVersion must be 1")
    package = rill.get("package")
    require(package, isinstance(package, dict), "package evidence missing")
    require(package.get("repository"), package.get("repository") == "hello-yunshu/rill-openwrt-packages", "wrong package repository")
    require(package.get("commit"), isinstance(package.get("commit"), str) and bool(HEX40.fullmatch(package["commit"])), "wrong package commit")
    package_run = package.get("qualificationRunId")
    require(package_run, isinstance(package_run, int) and not isinstance(package_run, bool) and package_run > 0, "qualification run id must be a positive integer")
    require(package.get("qualificationManifestSha256"), isinstance(package.get("qualificationManifestSha256"), str) and bool(HEX64.fullmatch(package["qualificationManifestSha256"])), "wrong qualification manifest digest")
    require(rill.get("stablePackageQualification"), rill.get("stablePackageQualification") == "PASS", "Stable package qualification is not PASS")
    require(rill.get("previewRuntimeIntegration"), rill.get("previewRuntimeIntegration") == "PASS", "Preview Runtime integration is not PASS")
    for field in ("stableCommit", "previewCommit"):
        require(field, isinstance(rill.get(field), str) and bool(HEX40.fullmatch(rill[field])), f"wrong {field}")
    require("stableCommit", rill["stableCommit"] != rill["previewCommit"], "Stable and Preview commits must differ")
    runtime = rill.get("runtime")
    require(runtime, isinstance(runtime, dict), "runtime evidence missing")
    require(runtime.get("version"), isinstance(runtime.get("version"), str), "runtime version missing")
    require(runtime.get("tag"), isinstance(runtime.get("tag"), str), "runtime tag missing")
    require(runtime.get("commit"), isinstance(runtime.get("commit"), str) and bool(HEX40.fullmatch(runtime["commit"])), "wrong runtime commit")
    archive = runtime.get("sourceArchiveSha256")
    require(archive, archive == "not-applicable-preview" or (isinstance(archive, str) and bool(HEX64.fullmatch(archive))), "wrong source archive digest")
    require(runtime.get("binarySha256"), isinstance(runtime.get("binarySha256"), str) and bool(HEX64.fullmatch(runtime["binarySha256"])), "wrong Runtime binary digest")
    integration = rill.get("integration")
    require(integration, isinstance(integration, dict), "integration evidence missing")
    require(integration.get("status"), integration.get("status") == "pass", "integration status is not pass")
    require(integration.get("sameRelease"), integration.get("sameRelease") is True, "sameRelease must be true")
    assets = manifest.get("assetFiles")
    require(assets, isinstance(assets, list), "assetFiles must be an array")
    if require_assets is not None:
        require(assets, len(assets) == require_assets, f"expected {require_assets} release assets")
    for asset in assets:
        require(asset, isinstance(asset, dict) and isinstance(asset.get("sha256"), str) and bool(HEX64.fullmatch(asset["sha256"])), "missing asset digest")
    if require_release_eligible:
        seen_paths: set[str] = set()
        formats: set[str] = set()
        for asset in assets:
            path = asset.get("path")
            require(path, isinstance(path, str) and path and "\\" not in path, "asset path must be a normalized relative POSIX path")
            require(path, not any(ord(ch) < 32 or ord(ch) == 127 for ch in path), "asset path contains control characters")
            parts = path.split("/")
            require(path, not path.startswith("/") and all(part not in ("", ".", "..") for part in parts), "asset path must not be absolute or contain traversal")
            require(path, path not in seen_paths, "duplicate asset path")
            seen_paths.add(path)
            name = Path(path).name
            require(name, name not in {Path(p).name for p in seen_paths if p != path}, "duplicate asset basename")
            require(name, name.startswith("luci-app-cloudflare-ip_") or name.startswith("luci-app-cloudflare-ip-"), "unknown release package")
            require(name, "-rill" not in name and not name.startswith("rill-runtime"), "addon/runtime package is not a public release asset")
            suffix = Path(name).suffix
            require(suffix, suffix in (".ipk", ".apk"), "release asset must be IPK or APK")
            fmt = suffix[1:]
            require(fmt, fmt not in formats, "expected exactly one asset per package format")
            formats.add(fmt)
            require(asset.get("size"), isinstance(asset.get("size"), int) and not isinstance(asset.get("size"), bool) and asset["size"] > 0, "asset size must be a positive integer")
            package_meta = asset.get("package")
            require(package_meta, isinstance(package_meta, dict), "asset package metadata missing")
            require(package_meta, package_meta.get("name") == "luci-app-cloudflare-ip", "wrong asset package name")
            require(package_meta, package_meta.get("format") == fmt, "asset format does not match filename")
            require(package_meta, isinstance(package_meta.get("version"), str) and bool(re.fullmatch(r"[0-9][A-Za-z0-9.+~_-]*", package_meta["version"])), "invalid package version")
            require(package_meta, isinstance(package_meta.get("release"), int) and not isinstance(package_meta.get("release"), bool) and package_meta["release"] > 0, "invalid package release")
            require(package_meta, isinstance(package_meta.get("architecture"), str) and package_meta["architecture"] in ("all", "noarch"), "invalid package architecture")
            require(package_meta, package_meta.get("packageVersion") == (f"{package_meta['version']}-r{package_meta['release']}" if fmt == "apk" else f"{package_meta['version']}-{package_meta['release']}"), "packageVersion does not match version/release")
            if fmt == "ipk":
                expected_name = f"luci-app-cloudflare-ip_{package_meta['version']}-{package_meta['release']}_{package_meta['architecture']}.ipk"
            else:
                expected_name = f"luci-app-cloudflare-ip-{package_meta['version']}-r{package_meta['release']}.apk"
            require(name, name == expected_name, "asset filename does not match package metadata")
        require(formats, formats == {"ipk", "apk"}, "release assets must contain exactly one IPK and one APK")
    if require_release_eligible:
        require(contract_path, contract_path is not None, "strict release validation requires the pinned contract")
        contract = json.loads(contract_path.read_text(encoding="utf-8"))
        migration_contract = contract.get("packageMigration", {})
        require(migration, migration.get("legacyVersion") == migration_contract.get("legacyVersion"), "legacy package version does not match contract")
        require(migration, migration.get("sourceTag") == migration_contract.get("sourceTag"), "migration source tag does not match contract")
        require(migration, migration.get("sourceSHA") == migration_contract.get("sourceSHA"), "migration source SHA does not match contract")
        require(package, package.get("commit") == contract.get("openwrtPackage", {}).get("commit"), "Rill package commit does not match contract")
        require(package_run, package_run == contract.get("qualification", {}).get("runId"), "Rill package qualification run does not match contract")
        require(rill, rill.get("stableCommit") == contract.get("resolved", {}).get("upstreamCommit"), "Stable Runtime commit does not match contract")
        require(manifest, manifest.get("stableSourceArchiveSha256") == contract.get("resolved", {}).get("sourceArchiveSha256"), "Stable Runtime archive digest does not match contract")
        require(rill, rill.get("previewCommit") == contract.get("preview", {}).get("commit"), "Preview Runtime commit does not match contract")
        require(runtime, runtime.get("version") == contract.get("openwrtPackage", {}).get("packageVersion"), "Runtime version does not match contract")
        require(runtime, runtime.get("tag") == contract.get("preview", {}).get("channel"), "Runtime tag/channel does not match contract")
        require(runtime, runtime.get("commit") == contract.get("preview", {}).get("commit"), "Runtime commit does not match contract")
        require(runtime, runtime.get("sourceArchiveSha256") == "not-applicable-preview", "Preview Runtime must identify its source archive as not applicable")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--commit")
    parser.add_argument("--require-assets", type=int)
    parser.add_argument("--require-release-eligible", action="store_true", help="enforce the complete publication gate")
    parser.add_argument("--run-id", type=int, help="expected source qualification workflow run ID")
    parser.add_argument("--contract", type=Path, default=Path(__file__).resolve().parents[1] / "contracts/rill-runtime.json")
    args = parser.parse_args()
    try:
        data = json.loads(args.manifest.read_text(encoding="utf-8"))
        validate(data, args.commit, args.require_assets, args.require_release_eligible, args.run_id, args.contract)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        return fail(str(exc))
    if args.require_release_eligible:
        print(f"release qualification passed: {args.manifest}")
    elif data.get("releaseEligible") is not True:
        print(f"diagnostic only: releaseEligible={data.get('releaseEligible')!r}; this evidence is not publishable")
    else:
        print(f"qualification evidence valid: {args.manifest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
