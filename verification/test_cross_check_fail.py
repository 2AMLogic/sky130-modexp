#!/usr/bin/env python3
"""Self-test for `cross_check.py`'s failing-WIDTH diagnosability (issue #361).

Before the fix, a WIDTH whose klt verdict was not `pass` came back as bare
counts: the failing testcase name, cocotb's assertion text, klt's stderr and
the run dir klt wrote (`results_*.xml`, simulator logs) were all discarded by
the temp-build-root cleanup. This drives the real CLI as a subprocess against
a stubbed `klt` (+ stub `iverilog`, so nothing simulates) and asserts:

1. A run with one failing WIDTH (and one passing) exits 1 -- the counts line
   and RESULT/exit code are byte-for-byte the contract from before -- while
   the failing testcase name, its `error_type`/`error_message` and a bounded
   stderr tail are now printed, and that WIDTH's run dir + transcript survive
   the cleanup. A passing WIDTH's artifacts are still deleted: only failing
   evidence is kept.
2. An all-pass run exits 0 with no extra output and removes the whole build
   root, exactly as before.
3. `_failing_tests_block` stays bounded: a huge assertion message is
   tail-truncated to the same limit `klt_error_message` (in
   `_repo_utils`, issue #382) uses, keeping the end where the actual
   failure text is.

`--mint-record` is intentionally not exercised here: it runs only on an
all-pass gate (`overall_ok`), so the keep-failing-artifacts cleanup path can
never race it -- the transcripts it stores are copied before `finally`, and
its staging dir lives under REPO_ROOT, never inside the build root.

Usage: python3 verification/test_cross_check_fail.py
Exit codes: 0 all pass, 1 otherwise.
"""

from __future__ import annotations

import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

import cross_check  # noqa: E402

failures: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    print(("PASS " if ok else "FAIL ") + label + (f" -- {detail}" if not ok and detail else ""))
    if not ok:
        failures.append(label)


def _write_exec(path: Path, text: str) -> Path:
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return path


# A `klt` that answers `--version`, then for `functional-verification` reads
# the request's WIDTH from the `-o` run dir, writes the transcript the real
# testbench would (`CROSS_CHECK_TRANSCRIPT`), prints the response envelope on
# stdout and exits 0/3 per $STUB_VERDICT. The failing envelope carries the
# fields `parse_results_xml` produces for a failed testcase (name, status,
# error_type, error_message) -- exactly what the fix must surface.
STUB_KLT = r'''#!/usr/bin/env python3
import json, os, sys

argv = sys.argv[1:]
if argv[:1] == ["--version"]:
    print("klt 0.0-stub")
    sys.exit(0)

out_dir = argv[argv.index("-o") + 1]
width = json.load(open(os.path.join(out_dir, "request.json")))["parameters"]["WIDTH"]
cases = int(os.environ["CROSS_CHECK_CASES"])
transcript = os.environ["CROSS_CHECK_TRANSCRIPT"]
verdict_spec = os.environ["STUB_VERDICT"]  # "pass" | "fail" | "fail:<WIDTH>"
if verdict_spec.startswith("fail:"):
    verdict = "fail" if width == int(verdict_spec.split(":", 1)[1]) else "pass"
else:
    verdict = verdict_spec
mismatch_at = int(os.environ.get("STUB_MISMATCH_AT", "-1"))

with open(transcript, "w") as f:
    for i in range(cases):
        got = f"mismatch-{i}" if (verdict == "fail" and i == mismatch_at) else "ok"
        f.write(json.dumps({"width": width, "case": i, "got": got, "want": "ok"}) + "\n")

base = {
    "schema_version": 1, "engine": "icarus", "hdl_toplevel": "modexp",
    "testbench": "cross_check_tb", "coverage": None, "trace": None,
    "environment": {},
}
if verdict == "pass":
    base.update({
        "status": "pass", "test_count": 1, "passed_count": 1,
        "failed_count": 0, "skipped_count": 0,
        "tests": [{"name": "cross_check_tb.cross_check", "status": "passed",
                   "sim_time_ns": 1.0, "real_time_s": 0.1}],
    })
    print(json.dumps(base))
    sys.exit(0)

base.update({
    "status": "fail", "test_count": 1, "passed_count": 0,
    "failed_count": 1, "skipped_count": 0,
    "tests": [{"name": "cross_check_tb.cross_check", "status": "failed",
               "sim_time_ns": 1.0, "real_time_s": 0.1,
               "error_type": "AssertionError",
               "error_message": os.environ["STUB_FAIL_MESSAGE"]}],
})
print(json.dumps(base))
sys.stderr.write(os.environ.get("STUB_STDERR", ""))
sys.exit(3)
'''

# `_tool_versions` runs `iverilog -V` with check=True before anything else.
STUB_IVERILOG = '''#!/usr/bin/env python3
import sys
if sys.argv[1:2] == ["-V"]:
    print("Icarus Verilog 0.0-stub")
sys.exit(0)
'''


def _cli(
    args: list[str], stub_bin: Path, scratch: Path, extra_env: dict[str, str] | None = None
) -> subprocess.CompletedProcess:
    env = {
        **os.environ,
        "PATH": f"{stub_bin}{os.pathsep}{os.environ['PATH']}",
        "CROSS_CHECK_NO_REEXEC": "1",
        "STUB_VERDICT": "pass",
        "STUB_FAIL_MESSAGE": "unreached",
        "TMPDIR": str(scratch),  # `mkdtemp` build root lands where the test can inspect it
    }
    env.update(extra_env or {})
    return subprocess.run(
        [sys.executable, str(SCRIPT_DIR / "cross_check.py"), *args],
        capture_output=True, text=True, env=env,
    )


def _build_root(scratch: Path) -> Path | None:
    roots = sorted(scratch.glob("modexp-cross-check-*"))
    return roots[0] if roots else None


def test_failing_width_keeps_evidence_and_prints_detail() -> None:
    """WIDTH=4 passes, WIDTH=8 fails: exit 1, counts unchanged, detail
    printed, failing run's evidence kept, passing run's evidence deleted."""
    with tempfile.TemporaryDirectory() as tmp:
        scratch = Path(tmp) / "scratch"
        scratch.mkdir()
        stub_bin = Path(tmp) / "stub-bin"
        stub_bin.mkdir()
        _write_exec(stub_bin / "klt", STUB_KLT)
        _write_exec(stub_bin / "iverilog", STUB_IVERILOG)

        proc = _cli(
            ["--widths", "4", "8", "--cases", "40"],
            stub_bin,
            scratch,
            extra_env={
                "STUB_VERDICT": "fail:8",  # only WIDTH=8 gets a failing verdict
                "STUB_FAIL_MESSAGE": "39/40 vectors match, 1 mismatch (seed=20260807008)",
                "STUB_STDERR": "STUB-KLT-STDERR-MARKER: cocotb assertion log tail\n",
                "STUB_MISMATCH_AT": "7",
            },
        )
        out = proc.stdout
        # 1. Gate verdict and exit code unchanged.
        check("mixed run exits 1", proc.returncode == 1, f"rc={proc.returncode}")
        check("passing WIDTH counts line unchanged",
              "WIDTH=4: PASS -- 40/40 match, 0 mismatches" in out, out[-400:])
        check("failing WIDTH counts line unchanged",
              "WIDTH=8: FAIL -- 39/40 match, 1 mismatches" in out, out[-400:])
        check("failing WIDTH names klt status",
              "klt status='fail'" in out, out[-400:])
        check("RESULT: FAIL reported", "RESULT: FAIL" in out, out[-200:])

        # 2. klt's own verdict detail now surfaces (the fix's point).
        check("failing testcase name printed",
              "cross_check_tb.cross_check" in out, out[-600:])
        check("error_type printed", "AssertionError" in out, out[-600:])
        check("cocotb assertion text printed",
              "39/40 vectors match, 1 mismatch" in out, out[-600:])
        check("stderr tail printed",
              "STUB-KLT-STDERR-MARKER" in out, out[-600:])

        # 3. The failing run's evidence survives; the passing run's does not.
        root = _build_root(scratch)
        check("build root kept for diagnosis", root is not None)
        if root is not None:
            check("kept note printed",
                  "(failing-run artifacts kept -- diagnose before deleting):" in out,
                  out[-400:])
            check("failing run dir kept", (root / "klt-width8").is_dir())
            check("failing transcript kept", (root / "width-8.jsonl").is_file())
            check("passing run dir deleted", not (root / "klt-width4").exists())
            check("passing transcript deleted", not (root / "width-4.jsonl").exists())
            kept_lines = [
                line.strip()
                for line in out.splitlines()
                if line.strip().startswith(str(root)) and "klt-width8" in line
            ]
            check("kept run dir path printed", kept_lines == [str(root / "klt-width8")],
                  str(kept_lines))
            check("kept transcript path printed",
                  str(root / "width-8.jsonl") in out, out[-400:])


def test_all_pass_cleans_up_unchanged() -> None:
    """All-pass run: exit 0, no diagnosability output, build root removed."""
    with tempfile.TemporaryDirectory() as tmp:
        scratch = Path(tmp) / "scratch"
        scratch.mkdir()
        stub_bin = Path(tmp) / "stub-bin"
        stub_bin.mkdir()
        _write_exec(stub_bin / "klt", STUB_KLT)
        _write_exec(stub_bin / "iverilog", STUB_IVERILOG)

        proc = _cli(["--widths", "4", "--cases", "5"], stub_bin, scratch)
        check("all-pass run exits 0", proc.returncode == 0, f"rc={proc.returncode}")
        check("all-pass run reports PASS",
              "RESULT: PASS" in proc.stdout, proc.stdout[-200:])
        check("no failing-testcase output on a green run",
              "failing testcase(s)" not in proc.stdout, proc.stdout[-300:])
        check("no keep note on a green run",
              "(failing-run artifacts kept" not in proc.stdout, proc.stdout[-300:])
        check("build root fully removed on a green run", _build_root(scratch) is None)


def test_failing_tests_block_is_bounded() -> None:
    """`_failing_tests_block` tail-truncates to `klt_error_message`'s limit."""
    huge = "x" * 5000 + "the-actual-failure"
    entries = [{
        "name": "cross_check_tb.cross_check",
        "error_type": "AssertionError",
        "error_message": huge,
    }]
    block = cross_check._failing_tests_block(entries)
    check("block bounded to the shared limit",
          len(block) <= 600, f"len={len(block)}")
    check("block keeps the end (where the failure text is)",
          block.endswith("the-actual-failure"), block[-60:])
    check("block carries the testcase name prefix",
          "cross_check_tb.cross_check" in block, block[:80])
    empty = cross_check._failing_tests_block([])
    check("no failing entries renders empty", empty == "", repr(empty))


def main() -> int:
    test_failing_width_keeps_evidence_and_prints_detail()
    test_all_pass_cleans_up_unchanged()
    test_failing_tests_block_is_bounded()
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
