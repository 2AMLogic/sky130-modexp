#!/usr/bin/env python3
"""Self-test for `cross_check.py`'s record minting (`--supersedes`/`--author`).

Two halves:

1. `mint_record()` driven directly against a throwaway git repo and the same
   stubbed `klt artifact put` `test_artifact_store.py` uses, so no real
   simulation runs and nothing is stored in the fleet artifact store. Asserts
   `supersedes` reaches both the `record-meta` JSON and the **Supersedes**
   prose bullet, that `--author` text replaces the previously hardcoded
   author line, and that omitting `supersedes` still yields `null` / `none`.

2. The real CLI, invoked as a subprocess, rejecting bad record arguments
   *before* it runs anything: an unknown `--supersedes` id and a
   `--mint-record` without `--author` must exit nonzero having invoked no
   `klt` (a recording stub is first on `$PATH`) and having written no record
   or manifest. `klt artifact put` stores objects permanently, so this
   ordering is the whole point -- validation must not happen after a run.

Usage: python3 verification/test_cross_check_mint.py
Exit codes: 0 all pass, 1 otherwise.
"""

from __future__ import annotations

import json
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

import _repo_utils  # noqa: E402
import cross_check  # noqa: E402
from test_artifact_store import STUB  # noqa: E402

# A `klt` that appends its argv to $KLT_CALL_LOG and nothing else: used to
# prove the CLI's argument validation runs before any store call.
RECORDING_STUB = """#!/usr/bin/env python3
import os, sys
open(os.environ["KLT_CALL_LOG"], "a").write(" ".join(sys.argv[1:]) + "\\n")
sys.exit(0)
"""

TOOL_VERSIONS = {"klt": "0.0-stub", "cocotb": "2.0.1", "iverilog": "stub"}

failures: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    print(("PASS " if ok else "FAIL ") + label + (f" -- {detail}" if not ok and detail else ""))
    if not ok:
        failures.append(label)


def _write_exec(path: Path, text: str) -> Path:
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return path


def _init_repo(root: Path) -> None:
    git = ["git", "-C", str(root)]
    subprocess.run(["git", "init", "-q", "-b", "main", str(root)], check=True)
    subprocess.run(git + ["config", "user.email", "t@example.invalid"], check=True)
    subprocess.run(git + ["config", "user.name", "test"], check=True)
    (root / "rtl").mkdir()
    (root / "rtl" / "modexp.v").write_text("// stub design\n")
    subprocess.run(git + ["add", "-A"], check=True)
    subprocess.run(git + ["commit", "-qm", "base"], check=True)


def _mint(root: Path, klt: Path, **kwargs) -> Path:
    """Run `mint_record` with the module's repo-root globals pointed at
    `root` and `klt` first on `$PATH`, then restore the real ones."""
    saved_globals = (
        cross_check.REPO_ROOT,
        cross_check.RTL_SOURCE,
        cross_check.TESTBENCH_SOURCE,
        _repo_utils.REPO_ROOT,
    )
    saved_env = {k: os.environ.get(k) for k in ("PATH", "KLT_ARTIFACT_BROKER")}
    transcripts = root / "transcripts"
    transcripts.mkdir(exist_ok=True)
    summaries = []
    for width in (4, 16):
        t = transcripts / f"width-{width}.jsonl"
        t.write_text(json.dumps({"width": width, "got": 1, "want": 1}) + "\n")
        summaries.append(
            {"width": width, "cases": 500, "seed": 1, "mismatches": 0,
             "cocotb_pass": True, "transcript_path": t}
        )
    try:
        cross_check.REPO_ROOT = root
        cross_check.RTL_SOURCE = root / "rtl" / "modexp.v"
        cross_check.TESTBENCH_SOURCE = SCRIPT_DIR / "cross_check_tb.py"
        _repo_utils.REPO_ROOT = root
        os.environ["PATH"] = f"{klt.parent}{os.pathsep}{saved_env['PATH']}"
        os.environ["KLT_ARTIFACT_BROKER"] = "stub-broker"
        return cross_check.mint_record(summaries, TOOL_VERSIONS, **kwargs)
    finally:
        (
            cross_check.REPO_ROOT,
            cross_check.RTL_SOURCE,
            cross_check.TESTBENCH_SOURCE,
            _repo_utils.REPO_ROOT,
        ) = saved_globals
        for k, v in saved_env.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


def _meta(record: Path) -> dict:
    text = record.read_text(encoding="utf-8")
    block = text.split("<!-- record-meta", 1)[1].split("-->", 1)[0]
    return json.loads(block)


def test_mint_with_supersedes() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _init_repo(root)
        bin_dir = root / "stub-bin"
        bin_dir.mkdir()
        klt = _write_exec(bin_dir / "klt", STUB)

        record = _mint(root, klt, author="test-author (issue #315)")
        meta = _meta(record)
        text = record.read_text(encoding="utf-8")
        check("plain mint: supersedes is null in metadata", meta["supersedes"] is None,
              repr(meta["supersedes"]))
        check("plain mint: Supersedes bullet is 'none'", "- **Supersedes**: none" in text)
        check("plain mint: --author text is the author line",
              "test-author (issue #315)" in text)
        check("plain mint: hardcoded author line is gone",
              "loom-builder (issue #5)" not in text)
        check("plain mint: manifest written",
              len(list((root / "manifests" / "artifacts").glob("*.manifest.json"))) == 1)

        # The record just minted is a valid --supersedes target for the next.
        prior_id = meta["record_id"]
        superseding = _mint(root, klt, author="other (issue #315)", supersedes=prior_id)
        meta2 = _meta(superseding)
        text2 = superseding.read_text(encoding="utf-8")
        check("superseding mint: metadata carries the id",
              meta2["supersedes"] == prior_id, repr(meta2["supersedes"]))
        check("superseding mint: Supersedes bullet carries the id",
              f"- **Supersedes**: {prior_id}" in text2)
        check("superseding mint: author line carries --author",
              "other (issue #315)" in text2)
        check("superseding mint: prior record untouched", record.exists())

        # resolve_supersedes is what main() calls; exercise both answers.
        saved = (cross_check.REPO_ROOT, _repo_utils.REPO_ROOT)
        try:
            cross_check.REPO_ROOT = root
            _repo_utils.REPO_ROOT = root
            ok = cross_check.resolve_supersedes(prior_id) == record
            check("resolve_supersedes returns the record path", ok)
            try:
                cross_check.resolve_supersedes("20991231-235959-0000000")
            except ValueError:
                check("resolve_supersedes rejects an unknown id", True)
            else:
                check("resolve_supersedes rejects an unknown id", False)
        finally:
            cross_check.REPO_ROOT, _repo_utils.REPO_ROOT = saved


def _cli(args: list[str], klt_dir: Path, log: Path) -> subprocess.CompletedProcess:
    env = {
        **os.environ,
        "PATH": f"{klt_dir}{os.pathsep}{os.environ['PATH']}",
        "KLT_CALL_LOG": str(log),
        "KLT_ARTIFACT_BROKER": "stub-broker",
        "CROSS_CHECK_NO_REEXEC": "1",
    }
    return subprocess.run(
        [sys.executable, str(SCRIPT_DIR / "cross_check.py"), *args],
        capture_output=True, text=True, env=env,
    )


def test_cli_rejects_bad_record_args() -> None:
    """Against the real repo -- these must bail out before touching it."""
    repo_root = _repo_utils.REPO_ROOT
    real_records = repo_root / "verification" / "records" / cross_check.EXPERIMENT_SLUG / "records"
    manifests = repo_root / "manifests" / "artifacts"
    with tempfile.TemporaryDirectory() as tmp:
        klt_dir = Path(tmp)
        _write_exec(klt_dir / "klt", RECORDING_STUB)
        log = klt_dir / "calls.log"

        before_records = {p.name for p in real_records.glob("*.md")} if real_records.exists() else set()
        before_manifests = {p.name for p in manifests.glob("*")} if manifests.exists() else set()

        unknown = _cli(
            ["--mint-record", "--author", "x", "--supersedes", "20991231-235959-0000000"],
            klt_dir, log,
        )
        check("unknown --supersedes exits nonzero", unknown.returncode != 0,
              f"rc={unknown.returncode}")
        check("unknown --supersedes names the id in stderr",
              "20991231-235959-0000000" in unknown.stderr, unknown.stderr[-300:])

        no_author = _cli(["--mint-record"], klt_dir, log)
        check("--mint-record without --author exits nonzero", no_author.returncode != 0,
              f"rc={no_author.returncode}")
        check("--mint-record without --author names --author",
              "--author" in (no_author.stderr + no_author.stdout))

        orphan = _cli(["--supersedes", "whatever"], klt_dir, log)
        check("--supersedes without --mint-record exits nonzero", orphan.returncode != 0,
              f"rc={orphan.returncode}")

        check("no klt invocation", not log.exists(),
              log.read_text() if log.exists() else "")
        after_records = {p.name for p in real_records.glob("*.md")} if real_records.exists() else set()
        after_manifests = {p.name for p in manifests.glob("*")} if manifests.exists() else set()
        check("no record written", after_records == before_records)
        check("no manifest written", after_manifests == before_manifests)


def main() -> int:
    test_mint_with_supersedes()
    test_cli_rejects_bad_record_args()
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
