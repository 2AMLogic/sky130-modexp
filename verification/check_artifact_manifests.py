#!/usr/bin/env python3
"""Validate `manifests/artifacts/*.manifest.json` (fleet artifact store).

Checks, per manifest:
  - schema: `klt artifact` manifest v1 (`schema_version`, `entries[]` with
    exactly `sha256`, `size`, `kind`, `producer`, `uri`, optional `name` /
    `media_type`);
  - every `uri` starts with `artifact:`;
  - no storage location leaks: no `s3://`, `arn:aws:` or `http(s)://` string
    anywhere in the file (the broker URL must never be committed);
  - no entry's bytes are also committed: a tracked file whose sha256 equals
    an entry's `sha256` fails the check.

Usage:
    python3 verification/check_artifact_manifests.py [--repo-root DIR]
Exit codes: 0 clean (or no manifests), 1 at least one violation.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

MANIFEST_GLOB = "manifests/artifacts/*.manifest.json"
REQUIRED = {"sha256", "size", "kind", "producer", "uri"}
OPTIONAL = {"name", "media_type"}
PRODUCER_KEYS = {"tool", "version", "loom.repo", "commit"}
LEAK = re.compile(r"s3://|arn:aws:|https?://", re.IGNORECASE)
SHA256 = re.compile(r"^[0-9a-f]{64}$")


def check_manifest(text: str) -> list[str]:
    errors: list[str] = []
    if LEAK.search(text):
        errors.append("contains a storage/broker location (s3://, arn:aws:, http(s)://)")
    try:
        doc = json.loads(text)
    except json.JSONDecodeError as exc:
        return errors + [f"not valid JSON: {exc}"]
    if not isinstance(doc, dict) or set(doc) != {"schema_version", "entries"}:
        return errors + ["top level must be exactly {schema_version, entries}"]
    if doc["schema_version"] != 1:
        errors.append("schema_version must be 1")
    entries = doc["entries"]
    if not isinstance(entries, list) or not entries:
        return errors + ["entries must be a non-empty list"]
    for i, e in enumerate(entries):
        where = f"entries[{i}]"
        if not isinstance(e, dict):
            errors.append(f"{where}: not an object")
            continue
        keys = set(e)
        if not REQUIRED <= keys or keys - REQUIRED - OPTIONAL:
            errors.append(f"{where}: keys {sorted(keys)} do not match the v1 schema")
            continue
        if not (isinstance(e["sha256"], str) and SHA256.match(e["sha256"])):
            errors.append(f"{where}: sha256 is not 64 lowercase hex digits")
        if not (isinstance(e["size"], int) and not isinstance(e["size"], bool) and e["size"] >= 0):
            errors.append(f"{where}: size must be a non-negative integer")
        if e["kind"] != "evidence":
            errors.append(f"{where}: kind must be 'evidence'")
        if not (isinstance(e["uri"], str) and e["uri"].startswith("artifact:")):
            errors.append(f"{where}: uri must start with 'artifact:'")
        prod = e["producer"]
        if not isinstance(prod, dict) or set(prod) != PRODUCER_KEYS:
            errors.append(f"{where}: producer keys must be {sorted(PRODUCER_KEYS)}")
    return errors


def committed_blob_collisions(root: Path, entries: list[dict]) -> list[str]:
    """Tracked files whose sha256 matches a manifest entry (bytes in git)."""
    by_sha = {e["sha256"]: e for e in entries}
    sizes = {e["size"] for e in entries}
    out = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z"], capture_output=True, check=True
    ).stdout
    hits = []
    for rel in filter(None, out.decode("utf-8", "surrogateescape").split("\0")):
        p = root / rel
        try:
            if not p.is_file() or p.is_symlink() or p.stat().st_size not in sizes:
                continue
            digest = hashlib.sha256(p.read_bytes()).hexdigest()
        except OSError:
            continue
        if digest in by_sha:
            hits.append(f"{rel} is committed but its bytes belong in the artifact store")
    return hits


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parent.parent)
    root = ap.parse_args().repo_root.resolve()

    failures = 0
    entries: list[dict] = []
    manifests = sorted(root.glob(MANIFEST_GLOB))
    for m in manifests:
        text = m.read_text(encoding="utf-8")
        errs = check_manifest(text)
        for err in errs:
            print(f"FAIL {m.relative_to(root)}: {err}")
        failures += len(errs)
        if not errs:
            entries += json.loads(text)["entries"]
    if entries:
        for hit in committed_blob_collisions(root, entries):
            print(f"FAIL {hit}")
            failures += 1
    if failures:
        return 1
    print(f"check_artifact_manifests: OK ({len(manifests)} manifest(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
