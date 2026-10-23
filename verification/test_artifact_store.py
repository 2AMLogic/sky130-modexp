#!/usr/bin/env python3
"""Self-test for `verification/artifact_store.py` using a stubbed `klt`.

Fail-closed cases: unset broker, `klt` without `artifact put`, broker refusal.
Each must raise `ArtifactStoreError` and leave no manifest behind. Positive
cases: a store writes `artifact:` URIs, and a second file merges into the
same manifest.

Usage: python3 verification/test_artifact_store.py
Exit codes: 0 all pass, 1 otherwise.
"""

from __future__ import annotations

import hashlib
import json
import os
import stat
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from artifact_store import ArtifactStoreError, store_files  # noqa: E402

STUB = '''#!/usr/bin/env python3
import hashlib, json, os, sys
mode = os.environ.get("STUB_MODE", "ok")
a = sys.argv[1:]
if a[:3] != ["artifact", "put", "--help"] and a[:2] != ["artifact", "put"]:
    sys.exit(2)
if a[2] == "--help":
    sys.exit(2 if mode == "noput" else 0)
if mode == "refuse":
    print("broker_refused: 403 not_granted", file=sys.stderr)
    sys.exit(1)
manifest, name, path = a[a.index("--manifest") + 1], a[a.index("--name") + 1], a[-1]
data = open(path, "rb").read()
sha = hashlib.sha256(data).hexdigest()
try:
    doc = json.load(open(manifest))
except FileNotFoundError:
    doc = {"schema_version": 1, "entries": []}
doc["entries"].append({"sha256": sha, "size": len(data), "kind": "evidence",
    "producer": {"tool": "klt", "version": "0", "loom.repo": "o/r", "commit": None},
    "uri": "artifact:evidence/o__r/" + sha[:2] + "/" + sha, "name": name})
json.dump(doc, open(manifest, "w"))
'''

failures: list[str] = []


def check(label: str, ok: bool) -> None:
    print(("PASS " if ok else "FAIL ") + label)
    if not ok:
        failures.append(label)


def expect_error(label: str, manifest: Path, files, klt: str, env: dict) -> None:
    try:
        store_files(files, manifest, klt=klt, env=env)
    except ArtifactStoreError:
        check(f"{label}: raises", True)
    else:
        check(f"{label}: raises", False)
    check(f"{label}: no manifest written", not manifest.exists())


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_p = Path(tmp)
        klt = tmp_p / "klt"
        klt.write_text(STUB)
        klt.chmod(klt.stat().st_mode | stat.S_IXUSR)
        f1, f2 = tmp_p / "a.jsonl", tmp_p / "b.jsonl"
        f1.write_bytes(b"one\n")
        f2.write_bytes(b"two\n")
        base = {"PATH": os.environ["PATH"], "KLT_ARTIFACT_BROKER": "stub-broker"}
        files = [(f1, "x/a.jsonl")]

        m = tmp_p / "m1" / "x.manifest.json"
        expect_error("unset broker", m, files, str(klt), {"PATH": base["PATH"]})
        expect_error("klt without artifact put", m, files, str(klt), {**base, "STUB_MODE": "noput"})
        expect_error("broker refusal", m, files, str(klt), {**base, "STUB_MODE": "refuse"})
        expect_error("klt missing", m, files, str(tmp_p / "nope"), base)

        entries = store_files(files, m, klt=str(klt), env=base)
        check("store returns one entry", len(entries) == 1)
        check("uri is artifact:", entries[0]["uri"].startswith("artifact:"))
        check("sha256 matches bytes", entries[0]["sha256"] == hashlib.sha256(b"one\n").hexdigest())

        store_files([(f2, "x/b.jsonl")], m, klt=str(klt), env=base)
        doc = json.loads(m.read_text())
        check("second file merges into manifest", len(doc["entries"]) == 2)

        before = m.read_text()
        try:
            store_files([(f1, "x/c.jsonl")], m, klt=str(klt), env={**base, "STUB_MODE": "refuse"})
        except ArtifactStoreError:
            pass
        check("failed store leaves existing manifest untouched", m.read_text() == before)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
