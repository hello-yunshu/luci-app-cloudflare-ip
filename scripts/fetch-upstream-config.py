#!/usr/bin/env python3
"""Materialise the upstream packages' real shipped default configuration.

The adapter contract tests run against fixtures that this repository authors.
That makes them blind to upstream changes: a fixture always contains the option
CFI expects. This script fetches the configuration the upstream package actually
ships, so tests/upstream-schema-contract.sh can assert CFI's assumptions against
reality instead of against itself.

Refs come from proxy-upstream-baseline.json, so what is fetched is exactly the
build the baseline claims was qualified.
"""

import argparse
import io
import json
import os
import re
import sys
import tarfile
import urllib.error
import urllib.request
from pathlib import Path

API = "https://api.github.com"


def request(url, accept="application/vnd.github+json"):
    req = urllib.request.Request(url, headers={"Accept": accept, "User-Agent": "cfip-upstream-schema"})
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    return urllib.request.urlopen(req, timeout=60)


def get_json(url, accept="application/vnd.github+json"):
    with request(url, accept) as response:
        return json.load(response)


def get_bytes(url, accept="application/vnd.github+json"):
    with request(url, accept) as response:
        return response.read()


def ar_members(blob):
    """Yield (name, payload) from a classic `!<arch>` archive."""
    if not blob.startswith(b"!<arch>\n"):
        raise ValueError("not an ar archive")
    offset = 8
    while offset + 60 <= len(blob):
        header = blob[offset:offset + 60]
        name = header[0:16].decode("ascii", "replace").strip().rstrip("/")
        size = int(header[48:58].decode("ascii").strip())
        offset += 60
        yield name, blob[offset:offset + size]
        offset += size + (size % 2)


def tar_members(blob):
    with tarfile.open(fileobj=io.BytesIO(blob)) as archive:
        for member in archive.getmembers():
            if not member.isfile():
                continue
            yield member.name.lstrip("./"), archive.extractfile(member).read()


def ipk_payload(blob, member):
    """Return `member` from an .ipk, accepting both packaging layouts."""
    outer = {}
    try:
        outer = dict(tar_members(blob))
    except (tarfile.TarError, OSError):
        try:
            outer = dict(ar_members(blob))
        except ValueError as exc:
            raise RuntimeError(f"unrecognised .ipk container: {exc}") from exc

    if member in outer:
        return outer[member]
    # A data.tar.gz directly containing the member (some feeds ship it bare).
    for name, payload in outer.items():
        if name.startswith("data.tar"):
            for inner_name, inner_payload in tar_members(payload):
                if inner_name == member:
                    return inner_payload
    raise RuntimeError(f"{member} not found in package (have: {', '.join(sorted(outer))})")


def fetch_release_member(source, ref):
    release = get_json(f"{API}/repos/{source['repo']}/releases/tags/{ref}")
    pattern = re.compile(source["asset"])
    matches = [asset for asset in release.get("assets", []) if pattern.search(asset["name"])]
    if not matches:
        names = ", ".join(asset["name"] for asset in release.get("assets", []))
        raise RuntimeError(f"{source['asset']} matched no asset in {source['repo']}@{ref} (assets: {names})")

    # Upstream ships one package per OpenWrt release line, all built from the
    # same source version. They must carry identical content for the file we
    # depend on; if they diverge we refuse to guess which one to trust.
    payloads = []
    for asset in matches:
        blob = get_bytes(asset["url"], accept="application/octet-stream")
        payloads.append((asset["name"], ipk_payload(blob, source["member"])))
    first = payloads[0][1]
    differing = sorted(name for name, payload in payloads if payload != first)
    if differing:
        raise RuntimeError(f"{source['member']} differs between packaging variants: {', '.join(differing)}")
    return first, ", ".join(sorted(name for name, _ in payloads))


def fetch_source_file(source, ref):
    url = f"{API}/repos/{source['repo']}/contents/{source['path']}?ref={ref}"
    return get_bytes(url, accept="application/vnd.github.raw"), f"{source['path']}@{ref[:12]}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", required=True, type=Path)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--dir", required=True, type=Path)
    args = parser.parse_args()

    sources = json.loads(args.sources.read_text(encoding="utf-8"))
    baseline = {item["name"]: item for item in json.loads(args.baseline.read_text(encoding="utf-8"))["upstreams"]}

    args.dir.mkdir(parents=True, exist_ok=True)
    failures = []
    rows = []
    for entry in sources["upstreams"]:
        name = entry["name"]
        recorded = baseline.get(name)
        if recorded is None:
            failures.append(f"{name}: no entry in the baseline, so the qualified ref is unknown")
            continue
        ref = recorded["observedRef"]
        source = entry["source"]
        try:
            if source["kind"] == "release-ipk":
                payload, origin = fetch_release_member(source, ref)
            elif source["kind"] == "source-file":
                payload, origin = fetch_source_file(source, ref)
            else:
                raise RuntimeError(f"unsupported source kind: {source['kind']}")
        except (urllib.error.URLError, RuntimeError, KeyError) as exc:
            failures.append(f"{name}: {exc}")
            continue
        target = args.dir / entry["dest"]
        target.write_bytes(payload)
        rows.append((name, ref, origin, len(payload)))
        print(f"fetched {name} -> {target.name} ({origin}, {len(payload)} bytes)")

    report = {"refs": {name: ref for name, ref, _, _ in rows},
              "files": {entry["dest"]: entry["name"] for entry in sources["upstreams"]}}
    (args.dir / "sources.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as stream:
            stream.write("## Upstream package defaults fetched\n\n| Component | Ref | Source | Bytes |\n|---|---|---|---|\n")
            for name, ref, origin, size in rows:
                stream.write(f"| {name} | `{ref}` | `{origin}` | {size} |\n")

    for failure in failures:
        print(f"error: {failure}", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
