#!/usr/bin/env python3
"""Report proxy upstream drift, enforcing it only where the claim boundary depends on it.

An upstream may set ``"blocking": false`` in the baseline when the CFI contract
does not depend on that upstream's runtime behaviour — for example adapters that
only write configuration and never claim a running-service hot apply. Drift on
those upstreams is still reported in the run summary, it just no longer stops a
release. Upstreams without the field keep the strict behaviour.

Lookup failures are reported and never block either: this script is a canary,
and a GitHub API hiccup must not turn into a release outage.
"""

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


def short_ref(kind, ref):
    return ref[:12] if kind == "branch" else ref


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
    warnings = []
    for item in baseline["upstreams"]:
        blocking = item.get("blocking", True)
        try:
            ref = current_ref(item)
            drift = ref != item["observedRef"]
            report["upstreams"].append({
                "name": item["name"],
                "repo": item["repo"],
                "kind": item["kind"],
                "observedRef": item["observedRef"],
                "currentRef": ref,
                "drift": drift,
                "blocking": blocking,
                "qualification": item["qualification"],
            })
            if drift:
                message = f"{item['name']}: {item['observedRef']} -> {ref}"
                (errors if blocking else warnings).append(message)
        except (KeyError, ValueError, urllib.error.URLError, TimeoutError) as exc:
            report["upstreams"].append({
                "name": item.get("name", "unknown"),
                "repo": item.get("repo", ""),
                "kind": item.get("kind", ""),
                "observedRef": item.get("observedRef", ""),
                "currentRef": None,
                "drift": None,
                "blocking": blocking,
                "qualification": item.get("qualification", ""),
                "lookupError": type(exc).__name__,
            })
            warnings.append(f"{item.get('name', 'unknown')}: lookup failed ({type(exc).__name__})")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    summary = [
        "## Proxy upstream compatibility canary",
        "",
        "This job detects upstream ref changes and runs local adapter contract tests. It does not install or claim runtime compatibility for a newly released plugin/core.",
        "",
        "| Component | Current upstream ref | Baseline | Blocks release | Qualification boundary |",
        "|---|---|---|---|---|",
    ]
    for row in report["upstreams"]:
        kind = row["kind"]
        if row["currentRef"] is None:
            shown = "lookup failed"
            mark = ""
        else:
            shown = short_ref(kind, row["currentRef"])
            if row["drift"]:
                mark = " **DRIFT**" if row["blocking"] else " **DRIFT (info)**"
            else:
                mark = ""
        baseline_ref = short_ref(kind, row["observedRef"])
        enforced = "yes" if row["blocking"] else "no"
        summary.append(
            f"| {row['name']} | `{shown}`{mark} | `{baseline_ref}` | {enforced} | {row['qualification']} |"
        )
    if errors:
        summary.extend(["", "### Requalification required — blocks the release", ""])
        summary.extend(f"- {error}" for error in errors)
    if warnings:
        summary.extend(["", "### Reported only — does not block the release", ""])
        summary.extend(f"- {warning}" for warning in warnings)
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
