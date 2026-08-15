"""Reproduction harness for the out-of-domain mismatch measurement cited in
`spec/decision-records/0001-input-domain-interface-and-corner-matrix.md`.

Drives `rtl/modexp.v` at `WIDTH=8` with `base_in >= mod_in` -- deliberately
*violating* the design's documented precondition (`rtl/modexp.v`'s header
comment: "base_in < mod_in and mod_in > 1") -- across 400 pseudo-random
cases, seed 7, and reports the mismatch count against Python's own
`pow(base, exp, mod)`. Unlike `test_modexp.py`'s `test_modexp_random`, this
harness does not `assert` per case, so it runs to completion and prints a
full transcript instead of stopping at the first failure.

This is intentionally a separate file from `test_modexp.py`: it exercises a
precondition violation *on purpose*, so it must never be added to
`request-modexp.json` or otherwise run as part of the correctness-gating
regression the ratified spec (`spec/modexp.md`) holds every commit to. It is
a one-off measurement tool for the decision record above, not a testbench in
the T1-evidence sense.

Usage (from the repo root, with `iverilog` and `cocotb` on `PATH`):

    python3 verification/repro_out_of_domain_mismatch.py

Runs directly against cocotb's `Runner` API (not through `klt
functional-verification`) because the `klt` request schema does not yet
plumb a Verilog parameter override (see `test_modexp.py`'s module
docstring) and this reproduction needs `WIDTH=8`, not the request's default
`WIDTH=16`.
"""

import os
import random
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb_tools.runner import get_runner

REPO_ROOT = Path(__file__).resolve().parent.parent
RTL_SOURCE = REPO_ROOT / "rtl" / "modexp.v"
WIDTH = 8
NUM_CASES = 400
SEED = 7

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _dut import reset as _reset  # noqa: E402
from _dut import run_modexp as _run_modexp  # noqa: E402


@cocotb.test()
async def out_of_domain_mismatch_transcript(dut):
    """base_in >= mod_in, WIDTH=8, 400 random cases, seed 7 -- no assert."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)

    hi = (1 << WIDTH) - 1
    rng = random.Random(SEED)
    mismatches = []
    for _ in range(NUM_CASES):
        mod = rng.randint(2, hi)
        base = rng.randint(mod, hi)  # out of domain: base >= mod
        exp = rng.randint(0, hi)
        got = await _run_modexp(dut, base, exp, mod)
        want = pow(base, exp, mod)
        if got != want:
            mismatches.append((base, exp, mod, got, want))

    print(
        f"WIDTH={WIDTH}, base >= mod, {NUM_CASES} random cases, seed={SEED}: "
        f"{len(mismatches)} mismatches out of {NUM_CASES}"
    )
    for base, exp, mod, got, want in mismatches[:10]:
        print(f"  modexp(base={base}, exp={exp}, mod={mod}) = {got}, pow(...) = {want}")
    if len(mismatches) > 10:
        print(f"  ... and {len(mismatches) - 10} more")


def main():
    runner = get_runner("icarus")
    runner.build(
        verilog_sources=[str(RTL_SOURCE)],
        hdl_toplevel="modexp",
        parameters={"WIDTH": WIDTH},
        always=True,
        timescale=("1ns", "1ps"),
        build_dir=str(REPO_ROOT / "verification" / "sim_build_repro"),
    )
    runner.test(
        test_module="repro_out_of_domain_mismatch",
        hdl_toplevel="modexp",
        test_dir=str(REPO_ROOT / "verification"),
        results_xml="repro_results.xml",
        timescale=("1ns", "1ps"),
    )


if __name__ == "__main__":
    main()
