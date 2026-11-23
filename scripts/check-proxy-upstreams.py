#!/usr/bin/env python3
"""Report proxy upstream drift. Drift never blocks a release.

A changed upstream ref is not evidence that functionality fails: it only means
the recorded qualification no longer describes the current upstream build. This
script therefore reports drift in the job summary and exits 0. Releases block on
signals that do describe failure — a failing adapter contract, an invalid
qualification manifest, or an immutable tag collision.

Only a broken baseline (missing field, unsupported upstream kind) is treated as
an error, because that is a defect in this repository rather than news about an
upstream.
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


REQUIRED_FIELDS = {
    "release": ("name", "repo", "kind", "observedRef", "qualification"),
    "branch": ("name", "repo", "kind", "branch", "observedRef", "qualification"),
}


def baseline_defect(item):
    """Return a description of what is wrong with this entry, or None.

    Checked before any network call so that a malformed entry is reported as a
    repository defect instead of surfacing later as a KeyError on a lookup that
    happened to succeed.
    """
    kind = item.get("kind")
    if kind not in REQUIRED_FIELDS:
        return f"unsupported upstream kind: {kind!r}"
    missing = [field for field in REQUIRED_FIELDS[kind] if not item.get(field)]
    if missing:
        return "missing field(s): " + ", ".join(missing)
    return None


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
    drift = []
    lookups = []
    for item in baseline["upstreams"]:
        name = item.get("name", "unknown")
        defect = baseline_defect(item)
        if defect:
            errors.append(f"{name}: {defect}")
            continue
        try:
            ref = current_ref(item)
        except (urllib.error.URLError, TimeoutError) as exc:
            lookups.append(f"{name}: lookup failed ({type(exc).__name__})")
            report["upstreams"].append({
                "name": name,
                "repo": item.get("repo", ""),
                "kind": item.get("kind", ""),
                "observedRef": item.get("observedRef", ""),
                "currentRef": None,
                "drift": None,
                "qualification": item.get("qualification", ""),
                "lookupError": type(exc).__name__,
            })
            continue
        except (KeyError, ValueError) as exc:
            errors.append(f"{name}: invalid baseline entry ({type(exc).__name__}) - {exc}")
            continue
        changed = ref != item["observedRef"]
        report["upstreams"].append({
            "name": name,
            "repo": item["repo"],
            "kind": item["kind"],
            "observedRef": item["observedRef"],
            "currentRef": ref,
            "drift": changed,
            "qualification": item["qualification"],
        })
        if changed:
            drift.append(f"{name}: {item['observedRef']} -> {ref}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    summary = [
        "## Proxy upstream compatibility canary",
        "",
        "This job only compares refs. Real compatibility is asserted by the `upstream-schema` job, which checks the UCI coordinates CFI depends on against the default configuration the upstream package actually ships.",
        "",
        "Drift is reported only. A version change is not evidence that functionality fails, so it never blocks a release; blocking comes from failing adapter contracts, an invalid qualification manifest or an immutable tag collision.",
        "",
        "| Component | Current upstream ref | Baseline | Qualification boundary |",
        "|---|---|---|---|",
    ]
    for row in report["upstreams"]:
        kind = row["kind"]
        if row["currentRef"] is None:
            shown = "lookup failed"
            mark = ""
        else:
            shown = short_ref(kind, row["currentRef"])
            mark = " **DRIFT**" if row["drift"] else ""
        baseline_ref = short_ref(kind, row["observedRef"])
        summary.append(
            f"| {row['name']} | `{shown}`{mark} | `{baseline_ref}` | {row['qualification']} |"
        )
    if drift:
        summary.extend(["", "### Upstream drift reported — does not block the release", ""])
        summary.extend(f"- {entry}" for entry in drift)
    if lookups:
        summary.extend(["", "### Lookup failures — does not block the release", ""])
        summary.extend(f"- {entry}" for entry in lookups)
    if errors:
        summary.extend(["", "### Baseline defects — blocks the release", ""])
        summary.extend(f"- {entry}" for entry in errors)
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
