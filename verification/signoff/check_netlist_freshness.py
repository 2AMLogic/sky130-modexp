#!/usr/bin/env python3
"""Freshness check for the derived gate-level netlists (T1 item 1).

Used as the `derived[].check` command in `inventory-item1.json`: exits 0 iff
the named netlist is still the one derived from the current `rtl/modexp.v`.

This is a hash-binding check, not a re-synthesis: re-running Yosys needs the
sky130A PDK, which CI does not fetch (see `.github/workflows/ci.yml`), and the
mapper is not reproducible across hosts (`docs/environment.md`, "Yosys and the
embedded ABC build"). What it does prove, offline and deterministically:

1. `rtl/modexp.v` still hashes to the `rtl_sha256` the netlist was derived
   from (editing the RTL without re-deriving fails here);
2. the netlist file still hashes to its pinned `netlist_sha256` (editing the
   netlist by hand fails here);
3. where the netlist's own `klt synthesize` envelope is committed, its
   `provenance.input.content_hash` -- written by the tool at synthesis time,
   independent of the pins file -- equals the current RTL hash.

Usage: check_netlist_freshness.py <key>   (key from netlist-derivations.json)
"""
import json
import sys
from pathlib import Path

# Locating the sibling helper module is the one thing that must be relative
# to this file; the repo root itself then comes from `_repo_utils`, so
# `$REPO_ROOT` is honoured and the path depth of this file is irrelevant.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from _repo_utils import REPO_ROOT, sha256_of  # noqa: E402

PINS = REPO_ROOT / "verification/signoff/netlist-derivations.json"


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    # Reachable since the root honours `$REPO_ROOT` (issue #329): a root
    # pointed at the wrong checkout should say so, not raise.
    if not PINS.exists():
        print(f"FAIL: no pins file at {PINS}", file=sys.stderr)
        return 2
    pins = json.loads(PINS.read_text())
    entry = pins["derived"].get(argv[1])
    if entry is None:
        print(f"FAIL: no derivation pinned for {argv[1]!r}", file=sys.stderr)
        return 1
    rtl_now = sha256_of(REPO_ROOT / pins["rtl"], prefix=False)
    net_now = sha256_of(REPO_ROOT / entry["path"], prefix=False)
    bad = []
    if rtl_now != entry["rtl_sha256"]:
        bad.append(f"{pins['rtl']} is {rtl_now}, netlist was derived from {entry['rtl_sha256']}")
    if net_now != entry["netlist_sha256"]:
        bad.append(f"{entry['path']} is {net_now}, pinned {entry['netlist_sha256']}")
    if entry.get("record_envelope"):
        env = json.loads((REPO_ROOT / entry["record_envelope"]).read_text())
        rec = env["provenance"]["input"]["content_hash"].removeprefix("sha256:")
        if rec != rtl_now:
            bad.append(f"{entry['record_envelope']} records input {rec}, RTL is {rtl_now}")
    if bad:
        print(f"FAIL: {argv[1]} is stale:", *bad, sep="\n  ", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
