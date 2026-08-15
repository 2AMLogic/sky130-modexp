"""cocotb testbench module for the deterministic multi-`WIDTH` cross-check.

Driven directly by `verification/cross_check.py` via cocotb's own `Runner`
API (`cocotb_tools.runner`), **not** by `klt functional-verification` --
the checked-in klt request (`verification/request-modexp.json`) only
elaborates the default `WIDTH=16`, because the `functional-verification`
request contract has no Verilog parameter override. That gap is filed as a
friction-protocol issue against `klayout-tools`; see `verification/README.md`.

One test, `test_cross_check`: draws `CROSS_CHECK_CASES` randomized
`(base, exp, mod)` vectors from a `random.Random(CROSS_CHECK_SEED)` instance
-- deterministic, so the identical seed always produces the identical vector
sequence -- runs each through the DUT, and asserts bit-exactness against
Python's own `pow(base, exp, mod)`. Width-adaptive via `len(dut.result)`,
exactly like `test_modexp.py`'s randomized test.

Every vector is also appended to `CROSS_CHECK_TRANSCRIPT` as one JSON line
(sorted keys, no non-deterministic fields such as timing), so two runs with
the same seed produce byte-identical transcript files -- the artifact an
evidence record snapshots.
"""

import json
import os
import random
import sys

import cocotb
from cocotb.clock import Clock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _dut import reset as _reset  # noqa: E402
from _dut import run_modexp as _run_modexp  # noqa: E402


@cocotb.test()
async def test_cross_check(dut):
    """Randomized bit-exact cross-check, parameterized entirely through env
    vars set by `verification/cross_check.py`:

    - `CROSS_CHECK_SEED` -- integer seed for `random.Random`.
    - `CROSS_CHECK_CASES` -- number of vectors to draw.
    - `CROSS_CHECK_TRANSCRIPT` -- path to write the per-vector JSONL
      transcript to.
    """
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await _reset(dut)

    width = len(dut.result)
    hi = (1 << width) - 1
    seed = int(os.environ["CROSS_CHECK_SEED"])
    cases = int(os.environ["CROSS_CHECK_CASES"])
    transcript_path = os.environ["CROSS_CHECK_TRANSCRIPT"]

    rng = random.Random(seed)
    mismatches = []
    with open(transcript_path, "w", encoding="utf-8") as transcript:
        for case in range(cases):
            mod = rng.randint(2, hi)
            base = rng.randint(0, mod - 1)
            exp = rng.randint(0, hi)
            got = await _run_modexp(dut, base, exp, mod)
            want = pow(base, exp, mod)
            if got != want:
                mismatches.append((case, base, exp, mod, got, want))
            transcript.write(
                json.dumps(
                    {
                        "width": width,
                        "case": case,
                        "base": base,
                        "exp": exp,
                        "mod": mod,
                        "got": got,
                        "want": want,
                    },
                    sort_keys=True,
                )
                + "\n"
            )

    assert not mismatches, (
        f"{len(mismatches)}/{cases} mismatches at WIDTH={width}: "
        f"{mismatches[:5]}{'...' if len(mismatches) > 5 else ''}"
    )
