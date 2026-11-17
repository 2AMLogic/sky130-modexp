#!/usr/bin/env python3
"""Validate `manifests/artifacts/*.manifest.json` (fleet artifact store).

Checks, per manifest:
  - schema: `klt artifact` manifest v1 (`schema_version`, `entries[]` with
    exactly `sha256`, `size`, `kind`, `producer`, `uri`, optional `name` /
    `media_type`);
  - every `uri` starts with `artifact:`;
  - no storage location leaks: no `s3://`, `arn:aws:` or `http(s)://` string
    anywhere in the file (the broker URL must never be committed);
  - no entry's bytes are *newly* committed: a tracked file whose sha256
    equals an entry's `sha256` fails the check when that file was added or
    modified relative to the merge-base with `--base-ref`.

Why the collision check is scoped to the diff, not to every tracked file
-----------------------------------------------------------------------
The rule exists to stop a *new* run's raw bytes being committed beside the
manifest that is supposed to replace them. Scoping it to the merge-base diff
keeps exactly that: anything this branch adds or modifies is still checked,
and a copy or rename of legacy bytes to a new path still fails (the diff is
taken with `--no-renames`, so the new path counts as an addition).

What it deliberately stops catching is evidence that already existed,
unchanged, at the merge-base. `verification/records/*/artifacts/` holds
transcripts committed before the artifact-store convention landed, and they
are frozen, append-only evidence (`verification/README.md`, "Artifact store":
manifest-forward only). A deterministic re-run reproduces those bytes exactly
-- that is what the pinned seed is for -- so under the unscoped rule every
new manifest collided with them and no superseding record could ever pass
lint. Un-scoped, the rule did not protect the repo from a new duplicate; it
made correct new evidence unmintable.

Limit of the rule: this is a PR-time gate. On `main` itself the merge-base
with `origin/main` is `HEAD`, so the diff is empty and nothing is reported --
the same property `check_records.py`'s append-only check already has. The
gate is the pull request, not the branch it has already merged into.

Usage:
    python3 verification/check_artifact_manifests.py [--repo-root DIR]
                                                     [--base-ref REF]
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


def _git(root: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(root), *args], capture_output=True, text=False
    )


def candidate_paths(root: Path, base_ref: str) -> list[str]:
    """Repo-relative tracked paths the collision check should consider.

    Normally the files this branch added or modified since its merge-base
    with `base_ref` -- see the module docstring for why the check is scoped
    that way. Renames are disabled so a legacy blob copied or moved to a new
    path is reported as an addition and still checked.

    Falls back to *every* tracked file (the strict, pre-scoping behavior)
    when the merge-base or the diff cannot be computed -- an unresolvable
    base ref must never silently exempt anything. The fallback prints a
    notice so a skipped scoping is visible in the log.
    """
    merge_base = _git(root, "merge-base", base_ref, "HEAD")
    if merge_base.returncode != 0:
        detail = merge_base.stderr.decode("utf-8", "replace").strip() or "no detail"
        print(
            f"NOTICE: could not resolve base ref `{base_ref}` ({detail}) -- "
            "checking every tracked file for collisions"
        )
        return _tracked_paths(root)

    base = merge_base.stdout.decode("utf-8", "replace").strip()
    diff = _git(
        root, "diff", "--name-only", "--no-renames", "-z", "--diff-filter=AM", base
    )
    if diff.returncode != 0:
        detail = diff.stderr.decode("utf-8", "replace").strip() or "no detail"
        print(
            f"NOTICE: `git diff` against {base[:12]} failed ({detail}) -- "
            "checking every tracked file for collisions"
        )
        return _tracked_paths(root)
    return _split_z(diff.stdout)


def _tracked_paths(root: Path) -> list[str]:
    out = _git(root, "ls-files", "-z")
    out.check_returncode()
    return _split_z(out.stdout)


def _split_z(raw: bytes) -> list[str]:
    return [p for p in raw.decode("utf-8", "surrogateescape").split("\0") if p]


def committed_blob_collisions(
    root: Path, entries: list[dict], base_ref: str
) -> list[str]:
    """Added/modified tracked files whose sha256 matches a manifest entry."""
    by_sha = {e["sha256"]: e for e in entries}
    sizes = {e["size"] for e in entries}
    hits = []
    for rel in candidate_paths(root, base_ref):
        p = root / rel
        try:
            if not p.is_file() or p.is_symlink() or p.stat().st_size not in sizes:
                continue
            digest = hashlib.sha256(p.read_bytes()).hexdigest()
        except OSError:
            continue
        if digest in by_sha:
            hits.append(
                f"{rel} is committed but its bytes belong in the artifact store"
            )
    return hits


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parent.parent)
    ap.add_argument(
        "--base-ref",
        default="origin/main",
        help=(
            "ref whose merge-base with HEAD scopes the committed-blob "
            "collision check (default: origin/main). If it cannot be "
            "resolved, every tracked file is checked instead."
        ),
    )
    args = ap.parse_args()
    root = args.repo_root.resolve()

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
        for hit in committed_blob_collisions(root, entries, args.base_ref):
            print(f"FAIL {hit}")
            failures += 1
    if failures:
        return 1
    print(f"check_artifact_manifests: OK ({len(manifests)} manifest(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
