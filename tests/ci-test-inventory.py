#!/usr/bin/env python3
"""Fail when a local test is neither wired into CI nor explicitly excluded.

Only executable configuration counts as coverage: paths are collected from
``run:`` steps (inline or block scalars) and ``with:`` mappings. Comments,
``paths:`` triggers and free-form text elsewhere in a workflow intentionally do
not count, so a test that is merely mentioned cannot hide a missing invocation.

Helper files and runtime-only suites are listed below with a reason so the
exclusion stays reviewable.
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
    "tests/startup-race.sh": (
        "invoked by tests/startup-race-container.sh inside the startup-race "
        "CI container"
    ),
    "tests/package_contract_fixtures.py": "fixture module imported by CI tests",
    "tests/package-identity-contract.py": (
        "invoked by tests/package-release-bump-contract.sh, which runs in "
        "the host-contract CI job"
    ),
    "tests/real-package-identity.py": (
        "standalone validator for downloaded SDK package bytes; the CI "
        "openwrt-package/package-migration jobs exercise the same artifacts"
    ),
}

EXTS = (".sh", ".py", ".cjs")
KEY = re.compile(r"^(?:- )?(run|with)\s*:\s*(.*)$")
BLOCK = {"|", ">", "|-", ">-", "|+", ">+"}


def indentation(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def strip_trailing_comment(line: str) -> str:
    """Drop a YAML/shell comment that is not inside quotes."""
    quote = None
    for index, char in enumerate(line):
        if quote:
            if char == quote:
                quote = None
        elif char in ("'", '"'):
            quote = char
        elif char == "#" and (index == 0 or line[index - 1].isspace()):
            return line[:index]
    return line


def executable_text(text: str) -> str:
    """Return only the text that a workflow actually executes."""
    lines = text.splitlines()
    chunks: list[str] = []
    index = 0
    while index < len(lines):
        line = lines[index]
        match = KEY.match(line.strip())
        if not match:
            index += 1
            continue
        base = indentation(line)
        value = match.group(2).strip()
        if value in BLOCK:
            index += 1
            while index < len(lines):
                nested = lines[index]
                stripped = nested.strip()
                if stripped and indentation(nested) <= base:
                    break
                if stripped and not stripped.startswith("#"):
                    chunks.append(strip_trailing_comment(stripped))
                index += 1
            continue
        if value:
            chunks.append(strip_trailing_comment(value))
            index += 1
            continue
        # "run:"/"with:" with a nested mapping.
        index += 1
        while index < len(lines):
            nested = lines[index]
            stripped = nested.strip()
            if stripped and indentation(nested) <= base:
                break
            if stripped and not stripped.startswith("#"):
                chunks.append(strip_trailing_comment(stripped))
            index += 1
    return "\n".join(chunks)


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
            chunks.append(executable_text(handle.read()))
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


SELF_TEST_WORKFLOW = """\
name: self-test
on: [push]
jobs:
  sample:
    runs-on: ubuntu-latest
    steps:
      # tests/commented-out.sh must not count: this is a YAML comment.
      - name: run tests/mentioned-in-name.sh
        run: |
          # bash tests/commented-in-block.sh
          bash tests/inline.sh
      - name: inline with a trailing comment
        run: bash tests/real.sh # tests/trailing-comment.sh
      - name: upload
        with:
          path: tests/artifact.sh
"""


def self_test() -> int:
    parsed = executable_text(SELF_TEST_WORKFLOW)
    explicit, missing = referenced_paths(parsed)
    for hidden in (
        "tests/commented-out.sh",
        "tests/mentioned-in-name.sh",
        "tests/commented-in-block.sh",
        "tests/trailing-comment.sh",
    ):
        if hidden in explicit or hidden in missing:
            print("self-test failed: comment/name-only path counted: %s" % hidden)
            return 1
    for wired in ("tests/inline.sh", "tests/real.sh", "tests/artifact.sh"):
        if wired not in explicit and wired not in missing:
            print("self-test failed: executable path not counted: %s" % wired)
            return 1
    print("ci-test-inventory self-test: PASS")
    return 0


def main() -> int:
    if "--self-test" in sys.argv[1:]:
        return self_test()

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
        for rel in sorted(leftovers):
            print("    %s" % rel)
    else:
        print("  all executable tests are wired or documented")

    if missing or leftovers:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
