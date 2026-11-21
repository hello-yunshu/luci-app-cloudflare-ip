#!/usr/bin/env python3
"""Report proxy upstream drift without claiming an unrun runtime test."""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


def current_ref(item):
    repo = item["repo"]
    if item["kind"] == "release":
        url = f"https://api.github.com/repos/{repo}/releases/latest"
        request = urllib.request.Request(url)
        request.add_header("User-Agent", "proxy-compatibility-canary")
        token = os.environ.get("GITHUB_TOKEN")
        if token:
            request.add_header("Authorization", f"Bearer {token}")
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)["tag_name"]
    if item["kind"] == "branch":
        url = f"https://api.github.com/repos/{repo}/branches/{item['branch']}"
        request = urllib.request.Request(url)
        request.add_header("User-Agent", "proxy-compatibility-canary")
        token = os.environ.get("GITHUB_TOKEN")
        if token:
            request.add_header("Authorization", f"Bearer {token}")
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)["commit"]["sha"]
    raise ValueError(f"unsupported upstream kind: {item['kind']}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    baseline = json.loads(args.baseline.read_text(encoding="utf-8"))
    report = {
        "schemaVersion": 1,
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "baselinePolicy": baseline["policy"],
        "upstreams": [],
    }
    errors = []
    for item in baseline["upstreams"]:
        try:
            ref = current_ref(item)
            drift = ref != item["observedRef"]
            row = {
                "name": item["name"],
                "repo": item["repo"],
                "kind": item["kind"],
                "observedRef": item["observedRef"],
                "currentRef": ref,
                "drift": drift,
                "qualification": item["qualification"],
            }
            if drift:
                errors.append(f"{item['name']}: {item['observedRef']} -> {ref}")
            report["upstreams"].append(row)
        except (KeyError, ValueError, urllib.error.URLError, TimeoutError) as exc:
            errors.append(f"{item.get('name', 'unknown')}: lookup failed ({type(exc).__name__})")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    summary = [
        "## Proxy upstream compatibility canary",
        "",
        "This job detects upstream ref changes and runs local adapter contract tests. It does not install or claim runtime compatibility for a newly released plugin/core.",
        "",
        "| Component | Current upstream ref | Baseline | Qualification boundary |",
        "|---|---|---|---|",
    ]
    for row in report["upstreams"]:
        short = row["currentRef"][:12] if row["kind"] == "branch" else row["currentRef"]
        baseline_ref = row["observedRef"][:12] if row["kind"] == "branch" else row["observedRef"]
        drift_mark = " **DRIFT**" if row["drift"] else ""
        summary.append(f"| {row['name']} | `{short}`{drift_mark} | `{baseline_ref}` | {row['qualification']} |")
    if errors:
        summary.extend(["", "### Requalification required", ""])
        summary.extend(f"- {error}" for error in errors)
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as stream:
            stream.write("\n".join(summary) + "\n")
    print("\n".join(summary))
    if errors:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
