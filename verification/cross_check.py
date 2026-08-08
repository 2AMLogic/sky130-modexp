#!/usr/bin/env python3
"""Deterministic multi-`WIDTH` Icarus cross-check for `rtl/modexp.v`.

Reproduces the claim `docs/baseline.md` makes: `modexp.v` is bit-exact
against Python `pow(base, exp, mod)` across `WIDTH` = 4, 6, 8, 16 at 500
random cases each, 0 mismatches.

Why this script exists instead of another `klt functional-verification`
invocation: that command's request schema
(`klt.functional_verification.request/1`) has no field to override a
Verilog `parameter`, so `verification/request-modexp.json` can only
elaborate the design's default `WIDTH=16`. This script elaborates each
`WIDTH` itself via cocotb's own `Runner` API (`cocotb_tools.runner`), which
*does* support a `parameters=` override, driving Icarus directly. This is
the documented klt gap -- filed as a friction-protocol issue against
`2AMLogic/klayout-tools` (generic, no design detail) and linked from
`verification/README.md`. Nothing here reimplements Yosys/synthesis; `klt
synthesize` is still used unmodified for the cell-count baseline.

Reproducibility: every `WIDTH` draws its vectors from a `random.Random`
seeded with a value derived from `--seed` (default: a pinned constant, never
the current time or OS entropy) and that `WIDTH`. Re-running with the same
seed reproduces byte-identical per-vector transcripts -- see
`test_cross_check` in `cross_check_tb.py`, which writes the transcript and
contains no non-deterministic fields (no timestamps, no wall-clock timing).

Usage:
    python3 verification/cross_check.py
        Run the full WIDTH=4,6,8,16 x 500-case cross-check and report a
        transcript summary. Exit 0 iff every case at every WIDTH matches.
        This is what `npm run test` invokes.

    python3 verification/cross_check.py --mint-record
        Also write a new append-only evidence record under
        `verification/records/width-cross-check/` (see
        `verification/README.md` for the record convention). Only do this
        deliberately -- do not wire --mint-record into CI, which would mint
        a new record on every PR.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
RTL_SOURCE = REPO_ROOT / "rtl" / "modexp.v"
TESTBENCH_SOURCE = SCRIPT_DIR / "cross_check_tb.py"
VENV_PYTHON = REPO_ROOT / ".venv" / "bin" / "python3"

DEFAULT_WIDTHS = (4, 6, 8, 16)
DEFAULT_CASES = 500
# Pinned base seed for the recorded evidence claim. Do not change this value
# without minting a fresh record -- it is what makes reruns reproduce the
# same vectors documented in docs/baseline.md.
PINNED_BASE_SEED = 20260807

sys.path.insert(0, str(SCRIPT_DIR))


def _reexec_into_venv_if_needed() -> None:
    """Re-exec under `.venv/bin/python3` when the current interpreter cannot
    import cocotb but the provisioned venv can.

    `scripts/setup-env.sh` installs cocotb/klt into `<repo>/.venv`, and the
    host's default `python3` is frequently a newer interpreter than cocotb
    supports. Without this, `npm run test` -- which invokes a bare `python3`
    -- fails on a correctly-provisioned checkout with an ImportError that
    tells the reader nothing useful. Re-exec is skipped when cocotb already
    imports, when no venv exists, or when we are already the venv's python
    (so this can never loop).
    """
    try:
        import cocotb_tools.runner  # noqa: F401

        return
    except ImportError:
        pass

    if not VENV_PYTHON.exists():
        return
    if Path(sys.executable).resolve() == VENV_PYTHON.resolve():
        return
    if os.environ.get("CROSS_CHECK_NO_REEXEC") == "1":
        return

    os.environ["CROSS_CHECK_NO_REEXEC"] = "1"
    print(
        f"note: cocotb is not importable under {sys.executable}; "
        f"re-executing under {VENV_PYTHON}",
        file=sys.stderr,
        flush=True,
    )
    os.execv(str(VENV_PYTHON), [str(VENV_PYTHON), str(Path(__file__).resolve()), *sys.argv[1:]])


def _require_cocotb() -> None:
    """Fail with an actionable message, not an ImportError traceback."""
    try:
        import cocotb_tools.runner  # noqa: F401
    except ImportError:
        print(
            "FATAL: cocotb is not importable under "
            f"{sys.executable} (python {sys.version_info.major}."
            f"{sys.version_info.minor}).\n"
            "  -> provision the pinned environment first:\n"
            "       ./scripts/setup-env.sh\n"
            "     then re-run. See docs/environment.md for the pinned\n"
            "     cocotb/Python versions and the toolchain this needs.",
            file=sys.stderr,
        )
        raise SystemExit(1) from None


def _sha256(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def _git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=REPO_ROOT, capture_output=True, text=True, check=True
    ).stdout.strip()


def _git_revision() -> str:
    try:
        return _git("rev-parse", "HEAD")
    except subprocess.CalledProcessError:
        return "unknown"


def _tool_versions() -> dict:
    versions = {}
    try:
        out = subprocess.run(
            ["iverilog", "-V"], capture_output=True, text=True, check=True
        ).stdout
        versions["iverilog"] = out.splitlines()[0].strip() if out else "unknown"
    except (FileNotFoundError, subprocess.CalledProcessError):
        versions["iverilog"] = "not found"

    try:
        import cocotb

        versions["cocotb"] = cocotb.__version__
    except Exception:
        versions["cocotb"] = "unknown"

    try:
        out = subprocess.run(
            ["klt", "--version"], capture_output=True, text=True, check=True
        ).stdout.strip()
        # `klt --version` prints "klt <version>"; keep just the version.
        versions["klt"] = out.removeprefix("klt ").strip() if out else "unknown"
    except (FileNotFoundError, subprocess.CalledProcessError):
        versions["klt"] = "not found"

    return versions


def run_width(width: int, cases: int, seed: int, build_root: Path) -> dict:
    """Elaborate `rtl/modexp.v` at `WIDTH=width` and run the cross-check
    testbench against it. Returns a summary dict; raises on any mismatch.
    """
    from cocotb_tools.runner import get_results, get_runner

    build_dir = build_root / f"sim_build_width{width}"
    transcript_path = build_root / f"width-{width}.jsonl"

    runner = get_runner("icarus")
    runner.build(
        sources=[str(RTL_SOURCE)],
        hdl_toplevel="modexp",
        parameters={"WIDTH": width},
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
            "CROSS_CHECK_CASES": str(cases),
            "CROSS_CHECK_TRANSCRIPT": str(transcript_path),
        },
        build_dir=str(build_dir),
        test_dir=str(build_dir),
        results_xml=str(build_dir / "results.xml"),
        timescale=("1ns", "1ps"),
    )
    num_tests, num_failures = get_results(results_xml)

    mismatches = 0
    if transcript_path.exists():
        with open(transcript_path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                vec = json.loads(line)
                if vec["got"] != vec["want"]:
                    mismatches += 1

    return {
        "width": width,
        "cases": cases,
        "seed": seed,
        "mismatches": mismatches,
        "cocotb_pass": num_failures == 0 and num_tests > 0,
        "transcript_path": transcript_path,
    }


def mint_record(run_summaries: list[dict], tool_versions: dict) -> Path:
    """Copy this run's transcripts into verification/records/width-cross-check/
    and write a new append-only .md record. Returns the record's path."""
    now = datetime.datetime.now(datetime.timezone.utc)
    short_sha = _git_revision()[:7]
    record_id = f"{now:%Y%m%d-%H%M%S}-{short_sha}"

    experiment_dir = REPO_ROOT / "verification" / "records" / "width-cross-check"
    artifacts_dir = experiment_dir / "artifacts" / record_id
    records_dir = experiment_dir / "records"
    artifacts_dir.mkdir(parents=True, exist_ok=True)
    records_dir.mkdir(parents=True, exist_ok=True)

    input_hashes = [
        {"path": "rtl/modexp.v", "content_hash": _sha256(RTL_SOURCE)},
        {
            "path": "verification/cross_check_tb.py",
            "content_hash": _sha256(TESTBENCH_SOURCE),
        },
    ]

    for summary in run_summaries:
        dest = artifacts_dir / summary["transcript_path"].name
        shutil.copyfile(summary["transcript_path"], dest)

    total_cases = sum(s["cases"] for s in run_summaries)
    total_mismatches = sum(s["mismatches"] for s in run_summaries)
    widths = [s["width"] for s in run_summaries]

    meta = {
        "record_id": record_id,
        "experiment": "width-cross-check",
        "supersedes": None,
        "git_revision": _git_revision(),
        "provenance": {
            "klt_version": tool_versions["klt"],
            "pdk": {"name": "n/a", "version": "n/a"},
            "deck": {"content_hash": "n/a"},
            "inputs": input_hashes,
        },
    }

    result_lines = "\n".join(
        f"  - WIDTH={s['width']}: {s['cases'] - s['mismatches']}/{s['cases']} "
        f"PASS, {s['mismatches']} mismatches (seed={s['seed']})"
        for s in run_summaries
    )
    links_lines = "\n".join(
        f"    - `verification/records/width-cross-check/artifacts/{record_id}/"
        f"width-{s['width']}.jsonl`"
        for s in run_summaries
    )

    body = f"""<!-- record-meta
{json.dumps(meta, indent=2)}
-->

# Record {record_id}

- **Record ID**: {record_id}
- **Claim**: `docs/baseline.md#the-measurement` -- `modexp.v` is bit-exact
  against Python `pow(base, exp, mod)` across WIDTH = {", ".join(str(w) for w in widths)}
  at {run_summaries[0]["cases"]} random cases each, 0 mismatches.
- **Design provenance**: rtl (`rtl/modexp.v` @ `{_git_revision()}`)
- **Run configuration**: `verification/cross_check.py`, cocotb {tool_versions["cocotb"]}
  + Icarus ({tool_versions["iverilog"]}), one `random.Random` instance per
  WIDTH seeded from `--seed` (base {PINNED_BASE_SEED}); klt not used to drive
  this run (see klt provenance below and the parameter-override gap noted
  in `verification/README.md`).
- **Statistical convention**: N = {run_summaries[0]["cases"]} random cases per WIDTH,
  drawn deterministically (fixed seed, no repetition), 0-mismatch pass/fail
  (not a distribution claim)
- **Result**:
{result_lines}
  - **Overall: PASS** ({total_cases - total_mismatches}/{total_cases} across all WIDTHs)
- **klt provenance**: klt {tool_versions["klt"]} (informational -- this run
  bypasses klt for elaboration, see Run configuration); PDK: n/a (no PDK
  dependency, RTL/behavioral simulation only); deck content_hash: n/a; input
  content_hash(es): see `provenance.inputs` in the metadata block above
- **Links**:
  - Driver: `verification/cross_check.py`
  - Testbench: `verification/cross_check_tb.py`
  - Design under test: `rtl/modexp.v`
  - Transcripts:
{links_lines}
- **Timestamp / author**: {now.strftime("%Y-%m-%dT%H:%M:%SZ")}, loom-builder (issue #5)
- **Supersedes**: none
"""

    record_path = records_dir / f"{record_id}.md"
    record_path.write_text(body, encoding="utf-8")
    return record_path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--widths",
        type=int,
        nargs="+",
        default=list(DEFAULT_WIDTHS),
        help=f"WIDTH values to check (default: {list(DEFAULT_WIDTHS)})",
    )
    parser.add_argument(
        "--cases",
        type=int,
        default=DEFAULT_CASES,
        help=f"random cases per WIDTH (default: {DEFAULT_CASES})",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=PINNED_BASE_SEED,
        help=(
            "base seed (default: pinned constant "
            f"{PINNED_BASE_SEED}; do not override when producing recorded "
            "evidence -- only for exploratory runs)"
        ),
    )
    parser.add_argument(
        "--mint-record",
        action="store_true",
        help="also write a new evidence record under verification/records/",
    )
    parser.add_argument(
        "--transcript-dir",
        type=Path,
        default=None,
        help=(
            "write the per-WIDTH JSONL vector transcripts (and sim build "
            "dirs) into this directory instead of a temp dir that is deleted "
            "on exit. Used to diff two runs' transcripts and prove the seed "
            "is pinned rather than defaulted."
        ),
    )
    args = parser.parse_args()

    if not RTL_SOURCE.exists():
        print(f"FATAL: {RTL_SOURCE} not found", file=sys.stderr)
        return 1

    _require_cocotb()
    if shutil.which("iverilog") is None:
        print(
            "FATAL: `iverilog` is not on $PATH -- the cross-check drives "
            "Icarus.\n"
            "  -> 'brew install icarus-verilog' (macOS) or "
            "'apt-get install iverilog' (Debian/Ubuntu);\n"
            "     ./scripts/setup-env.sh reports this too. See "
            "docs/environment.md.",
            file=sys.stderr,
        )
        return 1

    tool_versions = _tool_versions()
    print("== multi-WIDTH cross-check ==", flush=True)
    print(f"git revision: {_git_revision()}", flush=True)
    print(f"tool versions: {tool_versions}", flush=True)
    print(
        f"widths: {args.widths}  cases/width: {args.cases}  base seed: {args.seed}",
        flush=True,
    )
    print(flush=True)

    if args.transcript_dir is not None:
        build_root = args.transcript_dir.resolve()
        build_root.mkdir(parents=True, exist_ok=True)
        keep_build = True
    else:
        build_root = Path(tempfile.mkdtemp(prefix="modexp-cross-check-"))
        keep_build = os.environ.get("CROSS_CHECK_KEEP_BUILD") == "1"
    summaries = []
    overall_ok = True
    try:
        for width in args.widths:
            # Distinct, deterministic per-width seed derived from the base
            # seed so different widths never draw identical vector streams.
            width_seed = args.seed * 1000 + width
            try:
                summary = run_width(width, args.cases, width_seed, build_root)
            except AssertionError as exc:
                print(f"WIDTH={width}: FAIL -- {exc}")
                overall_ok = False
                continue
            summaries.append(summary)
            status = "PASS" if summary["mismatches"] == 0 and summary["cocotb_pass"] else "FAIL"
            if status == "FAIL":
                overall_ok = False
            print(
                f"WIDTH={width}: {status} -- "
                f"{summary['cases'] - summary['mismatches']}/{summary['cases']} "
                f"match, {summary['mismatches']} mismatches (seed={width_seed})",
                flush=True,
            )

        if not summaries:
            print("\nFATAL: no WIDTH runs completed")
            return 1

        total_cases = sum(s["cases"] for s in summaries)
        total_mismatches = sum(s["mismatches"] for s in summaries)
        print()
        print(
            f"TOTAL: {total_cases - total_mismatches}/{total_cases} match, "
            f"{total_mismatches} mismatches across WIDTH={args.widths}"
        )
        print("RESULT:", "PASS" if overall_ok else "FAIL")

        if overall_ok and args.mint_record:
            record_path = mint_record(summaries, tool_versions)
            print(f"\nMinted record: {record_path.relative_to(REPO_ROOT)}")
    finally:
        if keep_build:
            print(f"\n(build artifacts kept at {build_root})")
        else:
            shutil.rmtree(build_root, ignore_errors=True)

    return 0 if overall_ok else 1


if __name__ == "__main__":
    _reexec_into_venv_if_needed()
    raise SystemExit(main())
