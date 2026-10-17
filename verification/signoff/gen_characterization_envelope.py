#!/usr/bin/env python3
"""Generate (or check) the T1 item 8 characterization envelope.

The audited artifact is `verification/signoff/evidence/characterization.md`.
This script hashes it and writes the `kind: "generic"` attestation
`evidence/item-8-characterization.json`, then pins the same hash in
`block-manifest.json` (evidence."8"). The envelope shape mirrors
`item-9-testbenches.json`.

Usage:
    python3 verification/signoff/gen_characterization_envelope.py          # write
    python3 verification/signoff/gen_characterization_envelope.py --check  # verify

`--check` writes nothing; it exits 1 if the committed envelope or the
manifest pin differs from what the report's current bytes produce, i.e. the
report was edited without regenerating. CI runs it in the `signoff` job.
Standard library only.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPORT = Path("verification/signoff/evidence/characterization.md")
ENVELOPE = Path("verification/signoff/evidence/item-8-characterization.json")
MANIFEST = Path("verification/signoff/block-manifest.json")

SUMMARY = (
    "aggregated characterization report: every row of the ratified spec table "
    "with a verdict (or 'no ratified bound') and its record id; Fmax and "
    "setup/hold slack at all 18 corners; synthesized and routed area; one "
    "power estimate at tt_025C_1v80 with its method, activity assumption and "
    "limits stated. Figures are not compared with any external design."
)


def report_hash() -> str:
    return "sha256:" + hashlib.sha256((ROOT / REPORT).read_bytes()).hexdigest()


def build_envelope(content_hash: str) -> dict:
    return {
        "schema_version": 1,
        "kind": "generic",
        "status": "pass",
        "t1_item": 8,
        "summary": SUMMARY,
        "source": REPORT.as_posix(),
        "provenance": {
            "klt_version": "0.7.0",
            "klayout_version": None,
            "pdk": None,
            "deck": None,
            "input": {"content_hash": content_hash, "path": "characterization.md"},
        },
    }


def dump(obj: dict) -> str:
    return json.dumps(obj, indent=2) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--check", action="store_true", help="verify, write nothing")
    args = ap.parse_args()

    h = report_hash()
    want_env = dump(build_envelope(h))
    manifest = json.loads((ROOT / MANIFEST).read_text())
    pin = {"file": ENVELOPE.as_posix(), "content_hash": h}

    if args.check:
        problems = []
        env_path = ROOT / ENVELOPE
        if not env_path.exists() or env_path.read_text() != want_env:
            problems.append(f"{ENVELOPE} does not match the current {REPORT}")
        if manifest.get("evidence", {}).get("8") != pin:
            problems.append(f"{MANIFEST} evidence.8 pin does not match the current {REPORT}")
        if problems:
            for p in problems:
                print(f"FAIL: {p}", file=sys.stderr)
            print(
                "  Regenerate with: python3 verification/signoff/gen_characterization_envelope.py\n"
                "  then ./verification/signoff/run-signoff.sh, and commit all of it.",
                file=sys.stderr,
            )
            return 1
        print(f"OK: item 8 envelope and manifest pin match {REPORT} ({h})")
        return 0

    (ROOT / ENVELOPE).write_text(want_env)
    manifest.setdefault("evidence", {})["8"] = pin
    # Keep numeric item order so the manifest diff stays small.
    manifest["evidence"] = dict(sorted(manifest["evidence"].items(), key=lambda kv: int(kv[0])))
    (ROOT / MANIFEST).write_text(dump(manifest))
    print(f"wrote {ENVELOPE} and evidence.8 in {MANIFEST} ({h})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
