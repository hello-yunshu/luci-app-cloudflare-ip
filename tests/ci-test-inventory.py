#!/usr/bin/env python3
"""Fail when a local test is neither wired into CI nor explicitly excluded.

The check is intentionally path-based: a test counts as covered when a workflow
mentions it directly, or when a workflow glob expands to it. Helper files and
runtime-only suites are listed below with a reason so the exclusion stays
reviewable.
"""
from __future__ import annotations

import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTS = os.path.join(ROOT, "tests")
WORKFLOWS = os.path.join(ROOT, ".github", "workflows")

# Non-test files, or tests whose execution environment is not available in CI.
EXCLUDED = {
    "tests/fixtures/cfst/malformed.csv": "test fixture data",
    "tests/fixtures/cfst/mixed-normal.csv": "test fixture data",
    "tests/fixtures/cfst/tcp-normal.csv": "test fixture data",
    "tests/fixtures/sources/best-cf-domain-sample.txt": "test fixture data",
    "tests/fixtures/sources/best-cf-ipv4-sample.txt": "test fixture data",
    "tests/helpers/flock-kernel.py": "helper imported by shell tests",
    "tests/legacy/_helpers.sh": "helper sourced by legacy tests",
    "tests/openclash-rpc-render.cjs": "invoked by tests/openclash-rpc-contract.sh",
    "tests/package_contract_fixtures.py": "fixture module imported by CI tests",
    "tests/package-identity-contract.py": (
        "invoked by tests/package-release-bump-contract.sh, which runs in "
        "the host-contract CI job"
    ),
    "tests/real-package-identity.py": (
        "standalone validator for downloaded SDK package bytes; the CI "
        "openwrt-package/package-migration jobs exercise the same artifacts"
    ),
    "tests/publisher-procd-rebind.sh": (
        "requires a live procd/uhttpd runtime with bindable loopback ports; "
        "no current CI job starts init, so it is tracked outside CI"
    ),
    "tests/publisher-uhttpd-readback.sh": (
        "requires a live uhttpd listener in an isolated OpenWrt runtime; "
        "the rootfs-contract job starts no init, so it is tracked outside CI"
    ),
}

EXTS = (".sh", ".py", ".cjs")


def test_files() -> list[str]:
    found = []
    for root, _dirs, files in os.walk(TESTS):
        for name in files:
            if not name.endswith(EXTS):
                continue
            rel = os.path.relpath(os.path.join(root, name), ROOT).replace(os.sep, "/")
            found.append(rel)
    return sorted(found)


def workflow_text() -> str:
    chunks = []
    for path in sorted(glob.glob(os.path.join(WORKFLOWS, "*.yml"))):
        with open(path, encoding="utf-8") as handle:
            chunks.append(handle.read())
    return "\n".join(chunks)


def referenced_paths(text: str) -> tuple[set[str], set[str]]:
    explicit = set()
    missing = set()
    for match in re.finditer(r"tests/[A-Za-z0-9_./*-]+", text):
        token = match.group(0).rstrip(".,;:)")
        if "*" in token:
            for hit in glob.glob(os.path.join(ROOT, token)):
                if os.path.isfile(hit):
                    explicit.add(os.path.relpath(hit, ROOT).replace(os.sep, "/"))
            continue
        if token.endswith("/"):
            continue
        if os.path.isfile(os.path.join(ROOT, token)):
            explicit.add(token)
        elif os.path.isdir(os.path.join(ROOT, token)):
            continue
        else:
            missing.add(token)
    return explicit, missing


def main() -> int:
    files = test_files()
    text = workflow_text()
    explicit, missing = referenced_paths(text)
    leftovers = []
    for rel in files:
        if rel in explicit:
            continue
        if rel in EXCLUDED:
            continue
        leftovers.append(rel)

    print("CI test inventory")
    print("  local test files: %d" % len(files))
    print("  referenced by workflows: %d" % len(explicit))
    print("  documented exclusions: %d" % len(EXCLUDED))
    if missing:
        print("  referenced but missing:")
        for rel in sorted(missing):
            print("    %s" % rel)
    if leftovers:
        print("  not wired into CI:")
        for rel in leftovers:
            print("    %s" % rel)
    else:
        print("  all executable tests are wired or documented")

    if missing or leftovers:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
