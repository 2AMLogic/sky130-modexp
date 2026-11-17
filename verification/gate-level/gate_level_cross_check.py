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
elaboration, not a parameterized module. It drives Icarus through `klt
functional-verification`, the same engine entry point the committed suite
uses: the two cell-model defines travel under `options.defines`
(`{"FUNCTIONAL": null, "UNIT_DELAY": "#1"}` -- the same macros the
committed gate-level requests carry; see `verification/gate-level/README.md`)
and the shared testbench is reached via `testbench.search_path`, exactly the
way the probe behind `2AMLogic/sky130-modexp#316` verified it at the pinned
klt. What klt's request contract has no field for -- the case count, the
per-`WIDTH` seed and the transcript path -- travels as `CROSS_CHECK_*`
environment variables the klt subprocess inherits, the same channel
`verification/cross_check.py` uses for its per-`WIDTH` runs. Every driver in
this repo now goes through klt except
`verification/repro_out_of_domain_mismatch.py`, which stays unported
deliberately: a frozen one-off measurement tool for a decision record,
outside the correctness-gating regression, so it carries none of this gate's
"drive engines through klt" weight (`#316` settled that as *not ported*).

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
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
VERIFICATION_DIR = HERE.parent

NETLIST = HERE / "modexp_post_route.v"

# Kept deliberately identical to verification/cross_check.py's constants so
# the two runs draw the same vector stream at the same WIDTH.
PINNED_BASE_SEED = 20260807
DEFAULT_CASES = 500
NETLIST_WIDTH = 16

# The same two defines the committed gate-level requests carry under
# `options.defines`. cocotb serialises every *valued* define as an SV
# literal and cannot serialise a valueless macro at all (klayout-tools#2884),
# so klt 0.8.0 emits `FUNCTIONAL` as a plain `-DFUNCTIONAL` build arg and
# `UNIT_DELAY=#1` as a raw `-D`.
CELL_MODEL_DEFINES: dict[str, str | None] = {
    "FUNCTIONAL": None,
    "UNIT_DELAY": "#1",
}

# Locating the sibling helper module is the one thing that must be relative
# to this file; the repo root itself then comes from `_repo_utils`, so
# `$REPO_ROOT` is honoured and the path depth of this file is irrelevant.
sys.path.insert(0, str(VERIFICATION_DIR))

from _repo_utils import REPO_ROOT, reexec_into_venv_if_needed  # noqa: E402


def _resolve_klt() -> str | None:
    """Resolve the `klt` binary this run drives its simulation through.

    `$KLT` wins when set (the documented pin-check recipe in
    `docs/environment.md`), then the one *beside the running interpreter*
    (the venv `scripts/setup-env.sh` provisions holds the pinned klt **and**
    the cocotb it imports -- `reexec_into_venv_if_needed` has already put us
    inside it), then `$PATH`. Returns `None` when nothing resolves; `main()`
    turns that into the pre-flight FATAL.
    """
    override = os.environ.get("KLT")
    if override:
        candidate = Path(override)
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    beside = Path(sys.executable).parent / "klt"
    if beside.is_file() and os.access(beside, os.X_OK):
        return str(beside)
    return shutil.which("klt")


def resolve_pdk_verilog(klt: str) -> tuple[Path, Path, str]:
    """Return (primitives.v, sky130_fd_sc_hd.v, pdk_version) via `klt pdk find`."""
    out = subprocess.run(
        [klt, "pdk", "find", "--pdk", "sky130A", "--format", "json"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    doc = json.loads(out)
    hd = Path(doc["assets"]["libs_ref"]) / "sky130_fd_sc_hd" / "verilog"
    return hd / "primitives.v", hd / "sky130_fd_sc_hd.v", doc["version"]


def build_request(primitives_v: Path, cells_v: Path, seed: int) -> dict:
    """The `klt functional-verification` request for the deep run.

    Every path is absolute so the request does not depend on where klt
    resolves request-relative paths from. `options.random_seed` pins
    cocotb's *own* `random` module seeding; the transcript's vectors come
    from the testbench's own `random.Random(CROSS_CHECK_SEED)` instance,
    never from cocotb's global state (see `cross_check.py`'s
    `build_request` for the same reasoning on the RTL side).
    """
    return {
        "schema": "klt.functional_verification.request/1",
        "engine": "icarus",
        "sources": [str(primitives_v), str(cells_v), str(NETLIST)],
        "hdl_toplevel": "modexp",
        "testbench": {
            "module": "cross_check_tb",
            "testcase": None,
            "search_path": str(VERIFICATION_DIR),
        },
        "options": {
            "coverage": False,
            "timescale": ["1ns", "1ps"],
            "random_seed": seed,
            "defines": dict(CELL_MODEL_DEFINES),
        },
    }


def _klt_error_message(stderr: str, limit: int = 600) -> str:
    """klt's own diagnostic for a run that produced no verdict.

    Under `--format json` klt writes `{"schema_version": 1, "error":
    {"command": ..., "message": ...}}` to **stderr**; unwrap it to the bare
    message so the failure reads as one line instead of a nested document.
    Anything else (a traceback, a crash before the envelope) is passed
    through tail-truncated rather than swallowed.
    """
    text = (stderr or "").strip()
    try:
        message = json.loads(text)["error"]["message"]
    except (json.JSONDecodeError, KeyError, TypeError):
        return text[-limit:] if len(text) > limit else text
    return str(message)


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

    klt = _resolve_klt()
    if klt is None:
        print(
            "FATAL: no `klt` executable beside "
            f"{sys.executable} or on $PATH -- this script drives Icarus "
            "through `klt functional-verification`.\n"
            "  -> run ./scripts/setup-env.sh first.",
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

    primitives_v, cells_v, pdk_version = resolve_pdk_verilog(klt)
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
    run_dir = build_root / "klt-gate-level"

    print("== post-route gate-level cross-check ==", flush=True)
    print(f"netlist:  {NETLIST.relative_to(REPO_ROOT)}", flush=True)
    print(f"cells:    {cells_v}", flush=True)
    print(f"pdk:      {pdk_version}", flush=True)
    print(f"klt:      {klt} (functional-verification)", flush=True)
    print(f"width:    {NETLIST_WIDTH} (fixed -- the layout is one elaboration)", flush=True)
    print(f"cases:    {args.cases}   seed: {seed}", flush=True)
    print(flush=True)

    try:
        run_dir.mkdir(parents=True, exist_ok=True)
        request_path = run_dir / "request.json"
        request_path.write_text(
            json.dumps(build_request(primitives_v, cells_v, seed), indent=2) + "\n",
            encoding="utf-8",
        )

        # The case count, the per-WIDTH seed and the transcript path have no
        # field in the request contract, so they travel as environment
        # variables: klt sets no extra environment of its own, and the
        # simulator subprocess inherits the ambient environment of this call.
        env = dict(os.environ)
        env.update(
            {
                "CROSS_CHECK_SEED": str(seed),
                "CROSS_CHECK_CASES": str(args.cases),
                "CROSS_CHECK_TRANSCRIPT": str(transcript),
            }
        )

        # klt exits 0 on a passing regression and 3 on a failing one; both
        # print the response envelope on stdout. Any other exit is a request
        # that never produced a verdict (bad schema, missing source, no
        # simulator, no cocotb), and `--format json` puts that error envelope
        # on *stderr*, so stdout is empty -- hence the diagnostic is
        # recovered from stderr.
        completed = subprocess.run(
            [
                klt,
                "functional-verification",
                str(request_path),
                "--format",
                "json",
                "-o",
                str(run_dir),
            ],
            capture_output=True,
            text=True,
            env=env,
        )
        try:
            envelope = json.loads(completed.stdout)
        except json.JSONDecodeError:
            print(
                f"FATAL: `klt functional-verification` exited "
                f"{completed.returncode} without a response envelope on "
                f"stdout: {_klt_error_message(completed.stderr)}",
                file=sys.stderr,
            )
            return 1

        if not transcript.is_file():
            print(
                f"FATAL: klt reported status={envelope.get('status')!r} but "
                f"wrote no transcript at {transcript}",
                file=sys.stderr,
            )
            return 1

        num_tests = envelope.get("test_count", 0)
        num_failures = envelope.get("failed_count", 0)

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

        ok = (
            envelope.get("status") == "pass"
            and num_tests > 0
            and num_failures == 0
            and mismatches == 0
            and total == args.cases
        )
        print()
        print(
            f"klt:      status={envelope.get('status')!r} "
            f"tests={num_tests} failed={num_failures}"
        )
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
