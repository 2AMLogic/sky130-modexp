#!/usr/bin/env python3
"""Deep randomized cross-check of the **post-route-derived gate-level
netlist** against Python's `pow(base, exp, mod)`, reusing
`verification/cross_check_tb.py` unmodified.

Why this exists alongside `run-gate-level-sim.sh`
-------------------------------------------------
`run-gate-level-sim.sh` drives the committed suite (`test_modexp.py`: 7
directed vectors + 40 randomized) through `klt functional-verification`,
which is the entry point `CLAUDE.md` asks this repo to dogfood. But the RTL
side of this repo's correctness claim is broader than that: the recorded
`width-cross-check` evidence is 500 randomized cases per `WIDTH`. Running
only the 47-case klt suite at gate level would be a silent narrowing of the
case count relative to the RTL claim.

This script closes that gap for `WIDTH=16` -- the only width the gate-level
netlist *can* be run at, since it is a fixed physical layout of one
elaboration, not a parameterized module. It drives Icarus through cocotb's
own `Runner` API (the same way `verification/cross_check.py` does, and for a
related reason: `klt functional-verification`'s request schema has no field
for simulator `+define+` macros, which a run against PDK cell models
requires -- see `verification/gate-level/README.md`).

Determinism and the transcript-equality check
---------------------------------------------
The per-width seed is derived exactly as `cross_check.py` derives it
(`PINNED_BASE_SEED * 1000 + width`), so this run draws the *identical*
vector stream the recorded RTL `width-16` transcript was produced from.
`cross_check_tb.py` writes one JSON line per vector with no timing or
timestamp fields, so a gate-level netlist that behaves identically to the
RTL produces a **byte-identical** transcript. `--compare-rtl <path>` asserts
exactly that, which is a far sharper equivalence claim than "both runs
passed".

Usage:
    gate_level_cross_check.py [--cases 500] [--transcript-dir DIR] \
        [--compare-rtl verification/records/width-cross-check/artifacts/<id>/width-16.jsonl]
"""

from __future__ import annotations

import argparse
import filecmp
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent
VERIFICATION_DIR = REPO_ROOT / "verification"

NETLIST = HERE / "modexp_post_route.v"
DEFINES = HERE / "sky130_fd_sc_hd_sim_defines.v"

# Kept deliberately identical to verification/cross_check.py's constants so
# the two runs draw the same vector stream at the same WIDTH.
PINNED_BASE_SEED = 20260807
DEFAULT_CASES = 500
NETLIST_WIDTH = 16

sys.path.insert(0, str(VERIFICATION_DIR))

from _repo_utils import reexec_into_venv_if_needed  # noqa: E402


def resolve_pdk_verilog() -> tuple[Path, Path, str]:
    """Return (primitives.v, sky130_fd_sc_hd.v, pdk_version) via `klt pdk find`."""
    klt = REPO_ROOT / ".venv" / "bin" / "klt"
    klt_cmd = str(klt) if klt.exists() else "klt"
    out = subprocess.run(
        [klt_cmd, "pdk", "find", "--pdk", "sky130A", "--format", "json"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    doc = json.loads(out)
    hd = Path(doc["assets"]["libs_ref"]) / "sky130_fd_sc_hd" / "verilog"
    return hd / "primitives.v", hd / "sky130_fd_sc_hd.v", doc["version"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cases", type=int, default=DEFAULT_CASES)
    parser.add_argument("--seed", type=int, default=PINNED_BASE_SEED)
    parser.add_argument("--transcript-dir", type=Path, default=None)
    parser.add_argument(
        "--compare-rtl",
        type=Path,
        default=None,
        help=(
            "assert this run's transcript is byte-identical to the given RTL "
            "cross-check transcript (same seed, same case count)"
        ),
    )
    args = parser.parse_args()

    try:
        from cocotb_tools.runner import get_results, get_runner
    except ImportError:
        print(
            "FATAL: cocotb is not importable -- run ./scripts/setup-env.sh first.",
            file=sys.stderr,
        )
        return 1
    if shutil.which("iverilog") is None:
        print("FATAL: `iverilog` is not on $PATH.", file=sys.stderr)
        return 1
    if not NETLIST.exists():
        print(
            f"FATAL: {NETLIST} not found -- generate it first with\n"
            f"  ./verification/gate-level/run-gate-level-sim.sh",
            file=sys.stderr,
        )
        return 1

    primitives_v, cells_v, pdk_version = resolve_pdk_verilog()
    for f in (primitives_v, cells_v):
        if not f.is_file():
            print(f"FATAL: PDK Verilog model not found: {f}", file=sys.stderr)
            return 1

    if args.transcript_dir is not None:
        build_root = args.transcript_dir.resolve()
        build_root.mkdir(parents=True, exist_ok=True)
        keep = True
    else:
        build_root = Path(tempfile.mkdtemp(prefix="modexp-gate-level-"))
        keep = False

    seed = args.seed * 1000 + NETLIST_WIDTH
    transcript = build_root / f"gate-level-width-{NETLIST_WIDTH}.jsonl"
    build_dir = build_root / "sim_build_gate_level"

    print("== post-route gate-level cross-check ==", flush=True)
    print(f"netlist:  {NETLIST.relative_to(REPO_ROOT)}", flush=True)
    print(f"cells:    {cells_v}", flush=True)
    print(f"pdk:      {pdk_version}", flush=True)
    print(f"width:    {NETLIST_WIDTH} (fixed -- the layout is one elaboration)", flush=True)
    print(f"cases:    {args.cases}   seed: {seed}", flush=True)
    print(flush=True)

    try:
        runner = get_runner("icarus")
        runner.build(
            sources=[str(DEFINES), str(primitives_v), str(cells_v), str(NETLIST)],
            hdl_toplevel="modexp",
            build_dir=str(build_dir),
            always=True,
            clean=True,
            timescale=("1ns", "1ps"),
        )
        results_xml = runner.test(
            test_module="cross_check_tb",
            hdl_toplevel="modexp",
            seed=seed,
            extra_env={
                "CROSS_CHECK_SEED": str(seed),
                "CROSS_CHECK_CASES": str(args.cases),
                "CROSS_CHECK_TRANSCRIPT": str(transcript),
                "PYTHONPATH": str(VERIFICATION_DIR),
            },
            build_dir=str(build_dir),
            test_dir=str(build_dir),
            results_xml=str(build_dir / "results.xml"),
            timescale=("1ns", "1ps"),
        )
        num_tests, num_failures = get_results(results_xml)

        mismatches = 0
        total = 0
        with open(transcript, encoding="utf-8") as f:
            for line in f:
                if not line.strip():
                    continue
                total += 1
                vec = json.loads(line)
                if vec["got"] != vec["want"]:
                    mismatches += 1
                    if mismatches <= 5:
                        print(f"  MISMATCH: {vec}")

        ok = num_failures == 0 and num_tests > 0 and mismatches == 0 and total == args.cases
        print()
        print(f"{total - mismatches}/{total} match, {mismatches} mismatches")

        if args.compare_rtl is not None:
            rtl_path = args.compare_rtl
            if not rtl_path.is_absolute():
                rtl_path = REPO_ROOT / rtl_path
            if not rtl_path.exists():
                print(f"FATAL: --compare-rtl file not found: {rtl_path}", file=sys.stderr)
                ok = False
            elif filecmp.cmp(str(transcript), str(rtl_path), shallow=False):
                print(
                    f"transcript is BYTE-IDENTICAL to the RTL transcript "
                    f"{rtl_path.relative_to(REPO_ROOT)}"
                )
            else:
                print(
                    f"transcript DIFFERS from the RTL transcript "
                    f"{rtl_path.relative_to(REPO_ROOT)}",
                    file=sys.stderr,
                )
                ok = False

        print("RESULT:", "PASS" if ok else "FAIL")
        return 0 if ok else 1
    finally:
        if keep:
            print(f"\n(transcript + build kept at {build_root})")
        else:
            shutil.rmtree(build_root, ignore_errors=True)


if __name__ == "__main__":
    reexec_into_venv_if_needed(Path(__file__), "GATE_LEVEL_NO_REEXEC")
    raise SystemExit(main())
