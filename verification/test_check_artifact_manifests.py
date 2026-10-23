#!/usr/bin/env python3
"""Self-test for `verification/check_artifact_manifests.py`.

Builds a throwaway git repo per case, runs the real checker against it with
`--repo-root`, and asserts the exit code: a clean manifest and an empty repo
pass; bad schema, non-`artifact:` uri, bucket / URL strings, and a committed
blob matching an entry's sha256 all fail.

Usage: python3 verification/test_check_artifact_manifests.py
Exit codes: 0 all pass, 1 otherwise.
"""

from __future__ import annotations

import copy
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

CHECKER = Path(__file__).resolve().parent / "check_artifact_manifests.py"
BLOB = b"raw evidence bytes\n"
SHA = hashlib.sha256(BLOB).hexdigest()
GOOD = {
    "schema_version": 1,
    "entries": [{
        "sha256": SHA, "size": len(BLOB), "kind": "evidence",
        "producer": {"tool": "klt", "version": "0", "loom.repo": "o/r", "commit": None},
        "uri": f"artifact:evidence/o__r/{SHA[:2]}/{SHA}", "name": "r/a.jsonl",
    }],
}
failures: list[str] = []


def run_case(label: str, want_rc: int, manifest=None, raw=None, tracked: dict | None = None) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        subprocess.run(["git", "init", "-q", str(root)], check=True)
        if manifest is not None or raw is not None:
            d = root / "manifests" / "artifacts"
            d.mkdir(parents=True)
            (d / "t.manifest.json").write_text(raw if raw is not None else json.dumps(manifest))
        for rel, data in (tracked or {}).items():
            (root / rel).write_bytes(data)
        subprocess.run(["git", "-C", str(root), "add", "-A"], check=True)
        rc = subprocess.run(
            [sys.executable, str(CHECKER), "--repo-root", str(root)], capture_output=True
        ).returncode
    ok = rc == want_rc
    print(("PASS " if ok else "FAIL ") + f"{label} (rc={rc}, want {want_rc})")
    if not ok:
        failures.append(label)


def mutated(fn) -> dict:
    m = copy.deepcopy(GOOD)
    fn(m)
    return m


def main() -> int:
    run_case("no manifests", 0)
    run_case("good manifest", 0, GOOD)
    run_case("non-artifact uri", 1, mutated(lambda m: m["entries"][0].update(uri="file:///x")))
    run_case("s3 uri", 1, mutated(lambda m: m["entries"][0].update(uri="s3://b/k")))
    run_case("broker url in name", 1, mutated(lambda m: m["entries"][0].update(name="https://broker/x")))
    run_case("arn in name", 1, mutated(lambda m: m["entries"][0].update(name="arn:aws:s3:::b")))
    run_case("unknown field", 1, mutated(lambda m: m["entries"][0].update(extra=1)))
    run_case("missing field", 1, mutated(lambda m: m["entries"][0].pop("size")))
    run_case("bad sha256", 1, mutated(lambda m: m["entries"][0].update(sha256="zz")))
    run_case("bad schema_version", 1, mutated(lambda m: m.update(schema_version=2)))
    run_case("not json", 1, raw="{nope")
    run_case("committed blob matches entry", 1, GOOD, tracked={"leak.jsonl": BLOB})
    run_case("committed unrelated file ok", 0, GOOD, tracked={"other.txt": b"different"})
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
