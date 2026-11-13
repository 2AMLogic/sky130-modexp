#!/usr/bin/env python3
"""Deterministic multi-`WIDTH` Icarus cross-check for `rtl/modexp.v`.

Reproduces the claim `docs/baseline.md` makes: `modexp.v` is bit-exact
against Python `pow(base, exp, mod)` across `WIDTH` = 4, 6, 8, 16 at 500
random cases each, 0 mismatches.

Every simulator run here goes through `klt functional-verification` -- one
request per `WIDTH`, each carrying a `request.parameters` object
(`{"WIDTH": <n>}`) that klt forwards to both `Runner.build(parameters=...)`
and `Runner.test(parameters=...)`. This script never imports
`cocotb_tools.runner` itself.

That was not always true. Until the pin in `docs/environment.md` reached
`klayout-tools==0.8.0`, the `klt.functional_verification.request/1` schema
had no field to override a Verilog `parameter`, so a checked-in request
(`verification/request-modexp.json`) could only elaborate the design's
default `WIDTH=16` and this script drove Icarus directly via cocotb's own
`Runner` API. That gap was filed under the friction protocol against
`2AMLogic/klayout-tools` (generic, no design detail), `verification/README.md`
recorded the stopgap with an explicit exit condition -- retire the bypass
once `klt` gains a parameter override -- and the pinned klt now has it. The
bypass is gone; what this script still owns is everything klt's request
contract has no field for:

- deriving a distinct, deterministic per-`WIDTH` seed from `--seed`;
- passing the case count and transcript path to the testbench, which travel
  as `CROSS_CHECK_*` environment variables the klt subprocess inherits;
- reading the per-vector transcripts back and comparing `got` against
  `want`;
- `--mint-record` and the artifact manifests.

Nothing here reimplements Yosys/synthesis; `klt synthesize` is still used
unmodified for the cell-count baseline.

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
        `verification/README.md` for the record convention). The per-WIDTH
        transcripts go to the artifact store (`klt artifact put`) and only
        a manifest under `manifests/artifacts/` is committed; fails closed
        (nonzero, nothing written) if the store is unavailable. Only do this
        deliberately -- do not wire --mint-record into CI, which would mint
        a new record on every PR.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from _repo_utils import REPO_ROOT, reexec_into_venv_if_needed, run_git, sha256_of

SCRIPT_DIR = Path(__file__).resolve().parent
RTL_SOURCE = REPO_ROOT / "rtl" / "modexp.v"
TESTBENCH_SOURCE = SCRIPT_DIR / "cross_check_tb.py"

DEFAULT_WIDTHS = (4, 6, 8, 16)
DEFAULT_CASES = 500
# Pinned base seed for the recorded evidence claim. Do not change this value
# without minting a fresh record -- it is what makes reruns reproduce the
# same vectors documented in docs/baseline.md.
PINNED_BASE_SEED = 20260807
# Git-ignored scratch dir where --mint-record stages bytes for `klt artifact put`.
ARTIFACT_STAGING_DIR = ".artifact-staging"

sys.path.insert(0, str(SCRIPT_DIR))

from artifact_store import ArtifactStoreError, store_files  # noqa: E402


class CrossCheckError(RuntimeError):
    """A `klt functional-verification` run could not be carried out at all.

    Distinct from a run that completed and *failed*: that comes back in the
    klt response envelope as `status: "fail"` and is reported per-`WIDTH`
    like any other mismatch. This is "the request never produced a verdict"
    -- klt missing, the request rejected, or stdout that is not the
    documented JSON envelope.
    """


def _resolve_klt() -> str:
    """Path to the `klt` executable this run drives its simulations through.

    Prefers the one *beside the running interpreter* over `$PATH`: the venv
    `scripts/setup-env.sh` provisions holds the pinned klt **and** the
    cocotb it imports, and `reexec_into_venv_if_needed` has already put us
    inside it. Picking `$PATH`'s klt instead could reach a different release
    whose own interpreter cannot import that cocotb at all.

    Fails with an actionable message, not a `FileNotFoundError` traceback.
    """
    beside = Path(sys.executable).parent / "klt"
    if beside.is_file() and os.access(beside, os.X_OK):
        return str(beside)
    found = shutil.which("klt")
    if found is not None:
        return found
    print(
        "FATAL: no `klt` executable beside "
        f"{sys.executable} or on $PATH -- the cross-check drives Icarus "
        "through `klt functional-verification`.\n"
        "  -> provision the pinned environment first:\n"
        "       ./scripts/setup-env.sh\n"
        "     then re-run. See docs/environment.md for the pinned\n"
        "     klt/cocotb/Python versions and the toolchain this needs.",
        file=sys.stderr,
    )
    raise SystemExit(1)


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


def _git_revision() -> str:
    try:
        return run_git("rev-parse", "HEAD")
    except subprocess.CalledProcessError:
        return "unknown"


def _tool_versions(klt: str) -> dict:
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
            [klt, "--version"], capture_output=True, text=True, check=True
        ).stdout.strip()
        # `klt --version` prints "klt <version>"; keep just the version.
        versions["klt"] = out.removeprefix("klt ").strip() if out else "unknown"
    except (FileNotFoundError, subprocess.CalledProcessError):
        versions["klt"] = "not found"

    return versions


def build_request(width: int, seed: int) -> dict:
    """The `klt functional-verification` request for one `WIDTH`.

    `parameters` is what retired this script's old direct-`Runner` bypass:
    klt forwards the mapping verbatim to `Runner.build(parameters=...)` and
    `Runner.test(parameters=...)`, and cocotb's Icarus backend turns it into
    `-Pmodexp.WIDTH=<n>` at elaboration. Every path is absolute so the
    request does not depend on where klt resolves request-relative paths
    from.

    `options.random_seed` pins cocotb's *own* `random` module seeding and is
    deliberately set to the same per-`WIDTH` value as `CROSS_CHECK_SEED`,
    which is a separate knob: the transcript's vectors come from the
    testbench's own `random.Random(CROSS_CHECK_SEED)` instance, never from
    cocotb's global state. Pinning both leaves nothing in the run drawing
    from OS entropy.
    """
    return {
        "schema": "klt.functional_verification.request/1",
        "engine": "icarus",
        "sources": [str(RTL_SOURCE)],
        "hdl_toplevel": "modexp",
        "parameters": {"WIDTH": width},
        "testbench": {
            "module": TESTBENCH_SOURCE.stem,
            "testcase": None,
            "search_path": str(SCRIPT_DIR),
        },
        "options": {
            "coverage": False,
            "timescale": ["1ns", "1ps"],
            "random_seed": seed,
        },
    }


def run_width(
    width: int, cases: int, seed: int, build_root: Path, klt: str
) -> dict:
    """Elaborate `rtl/modexp.v` at `WIDTH=width` through `klt
    functional-verification` and run the cross-check testbench against it.

    Returns a summary dict. Raises `CrossCheckError` when the run produced
    no verdict at all; a run that produced a *failing* verdict comes back in
    the summary with `klt_pass` false.
    """
    run_dir = build_root / f"klt-width{width}"
    run_dir.mkdir(parents=True, exist_ok=True)
    transcript_path = build_root / f"width-{width}.jsonl"
    request_path = run_dir / "request.json"
    request_path.write_text(
        json.dumps(build_request(width, seed), indent=2) + "\n", encoding="utf-8"
    )

    # The case count and the transcript path have no field in the request
    # contract, so they travel as environment variables: klt sets no
    # `extra_env` of its own, and cocotb's Runner hands the simulator
    # subprocess the ambient environment this call constructs.
    env = dict(os.environ)
    env.update(
        {
            "CROSS_CHECK_SEED": str(seed),
            "CROSS_CHECK_CASES": str(cases),
            "CROSS_CHECK_TRANSCRIPT": str(transcript_path),
        }
    )

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
    # klt exits 0 on a passing regression and 3 on a failing one; both print
    # the response envelope on stdout. Any other exit is a request that never
    # produced a verdict (bad schema, missing source, no simulator, no
    # cocotb), and `--format json` puts that error envelope on *stderr*, so
    # stdout is empty -- hence the diagnostic is recovered from stderr.
    try:
        envelope = json.loads(completed.stdout)
    except json.JSONDecodeError:
        raise CrossCheckError(
            f"`klt functional-verification` (WIDTH={width}) exited "
            f"{completed.returncode} without a response envelope on stdout: "
            f"{_klt_error_message(completed.stderr)}"
        ) from None

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
        "klt_pass": envelope.get("status") == "pass"
        and envelope.get("test_count", 0) > 0,
        "klt_status": envelope.get("status"),
        "transcript_path": transcript_path,
    }


def mint_record(run_summaries: list[dict], tool_versions: dict) -> Path:
    """Store this run's transcripts in the artifact store, write a
    manifest under manifests/artifacts/, and write a new append-only .md
    record linking it. Raises `ArtifactStoreError` (writing nothing) if the
    store is unavailable -- raw bytes are never committed. Returns the
    record's path."""
    now = datetime.datetime.now(datetime.timezone.utc)
    short_sha = _git_revision()[:7]
    record_id = f"{now:%Y%m%d-%H%M%S}-{short_sha}"

    experiment_dir = REPO_ROOT / "verification" / "records" / "width-cross-check"
    records_dir = experiment_dir / "records"
    manifest_rel = f"manifests/artifacts/width-cross-check-{record_id}.manifest.json"

    # Stage in the git-ignored scratch dir, store, and only then write
    # anything tracked: a store failure leaves no manifest and no record.
    staging = REPO_ROOT / ARTIFACT_STAGING_DIR / record_id
    staging.mkdir(parents=True, exist_ok=True)
    try:
        staged = []
        for summary in run_summaries:
            dest = staging / summary["transcript_path"].name
            shutil.copyfile(summary["transcript_path"], dest)
            staged.append((dest, f"width-cross-check/{record_id}/{dest.name}"))
        entries = store_files(staged, REPO_ROOT / manifest_rel)
    finally:
        shutil.rmtree(staging, ignore_errors=True)
    records_dir.mkdir(parents=True, exist_ok=True)

    input_hashes = [
        {"path": "rtl/modexp.v", "content_hash": sha256_of(RTL_SOURCE)},
        {
            "path": "verification/cross_check_tb.py",
            "content_hash": sha256_of(TESTBENCH_SOURCE),
        },
    ]

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
        f"    - `{e['name']}`: {e['size']} bytes, sha256 `{e['sha256']}`"
        for e in entries
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
- **Run configuration**: `verification/cross_check.py`, which drives one
  `klt functional-verification` request per WIDTH (klt {tool_versions["klt"]},
  `request.parameters: {{"WIDTH": <n>}}`) over cocotb {tool_versions["cocotb"]}
  + Icarus ({tool_versions["iverilog"]}); one `random.Random` instance per
  WIDTH seeded from `--seed` (base {PINNED_BASE_SEED}).
- **Statistical convention**: N = {run_summaries[0]["cases"]} random cases per WIDTH,
  drawn deterministically (fixed seed, no repetition), 0-mismatch pass/fail
  (not a distribution claim)
- **Result**:
{result_lines}
  - **Overall: PASS** ({total_cases - total_mismatches}/{total_cases} across all WIDTHs)
- **klt provenance**: klt {tool_versions["klt"]} (the driven entry point for
  every simulator run in this record, see Run configuration); PDK: n/a (no PDK
  dependency, RTL/behavioral simulation only); deck content_hash: n/a; input
  content_hash(es): see `provenance.inputs` in the metadata block above
- **Links**:
  - Driver: `verification/cross_check.py`
  - Testbench: `verification/cross_check_tb.py`
  - Design under test: `rtl/modexp.v`
  - Artifact manifest: `{manifest_rel}` (bytes in the artifact store,
    verify with `klt artifact verify`)
  - Transcripts (name, size, sha256):
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

    klt = _resolve_klt()
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

    tool_versions = _tool_versions(klt)
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
                summary = run_width(width, args.cases, width_seed, build_root, klt)
            except CrossCheckError as exc:
                print(f"WIDTH={width}: FAIL -- {exc}")
                overall_ok = False
                continue
            summaries.append(summary)
            status = "PASS" if summary["mismatches"] == 0 and summary["klt_pass"] else "FAIL"
            if status == "FAIL":
                overall_ok = False
            # A run can be 0-mismatch and still not a pass -- e.g. the
            # testbench raised before writing every vector. Naming klt's own
            # verdict keeps that case from reading as a clean result.
            verdict = (
                ""
                if summary["klt_pass"]
                else f", klt status={summary['klt_status']!r}"
            )
            print(
                f"WIDTH={width}: {status} -- "
                f"{summary['cases'] - summary['mismatches']}/{summary['cases']} "
                f"match, {summary['mismatches']} mismatches "
                f"(seed={width_seed}{verdict})",
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
            try:
                record_path = mint_record(summaries, tool_versions)
            except ArtifactStoreError as exc:
                print(f"\nFATAL: no record minted -- {exc}", file=sys.stderr)
                return 1
            print(f"\nMinted record: {record_path.relative_to(REPO_ROOT)}")
    finally:
        if keep_build:
            print(f"\n(build artifacts kept at {build_root})")
        else:
            shutil.rmtree(build_root, ignore_errors=True)

    return 0 if overall_ok else 1


if __name__ == "__main__":
    reexec_into_venv_if_needed(Path(__file__), "CROSS_CHECK_NO_REEXEC")
    raise SystemExit(main())
