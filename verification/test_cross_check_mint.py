#!/usr/bin/env python3
"""Self-test for `cross_check.py`'s record minting (`--supersedes`/`--author`).

1. `mint_record()` driven directly against a throwaway git repo and the same
   stubbed `klt artifact put` `test_artifact_store.py` uses, so no real
   simulation runs and nothing is stored in the fleet artifact store. Asserts
   `supersedes` reaches both the `record-meta` JSON and the **Supersedes**
   prose bullet, that `--author` text replaces the previously hardcoded
   author line, and that omitting `supersedes` still yields `null` / `none`.

2. The real CLI, invoked as a subprocess, rejecting bad record arguments
   *before* it runs anything: an unknown `--supersedes` id, a repeated
   `--supersedes` id, and a `--mint-record` without `--author` must exit
   nonzero having invoked no `klt` (a recording stub is first on `$PATH`)
   and having written no record or manifest. `klt artifact put` stores
   objects permanently, so this ordering is the whole point -- validation
   must not happen after a run.

3. The same CLI carrying a *repeated* `--supersedes` (two valid ids) all
   the way to a minted record (issue #421): a `klt` stub that simulates a
   passing `functional-verification` WIDTH and stores artifacts lets the
   subprocess run to completion against a throwaway repo, proving the
   argparse append wiring end to end -- the minted metadata is a two-id
   list and the bullet names both.

Usage: python3 verification/test_cross_check_mint.py
Exit codes: 0 all pass, 1 otherwise.
"""

from __future__ import annotations

import ast
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

# A `klt` that *simulates*: a passing `functional-verification` (writes
# exactly $CROSS_CHECK_CASES matching vectors to $CROSS_CHECK_TRANSCRIPT and
# prints a pass envelope) plus the same `artifact put` the plain STUB serves,
# so the real CLI can run to completion -- and to `--mint-record` -- against
# a throwaway repo without a simulator (issue #421).
SIM_KLT_STUB = """#!/usr/bin/env python3
import hashlib, json, os, sys
a = sys.argv[1:]
if a[:1] == ["--version"]:
    print("klt 0.0-simstub")
    sys.exit(0)
if a[:1] == ["functional-verification"]:
    cases = int(os.environ["CROSS_CHECK_CASES"])
    with open(os.environ["CROSS_CHECK_TRANSCRIPT"], "w") as f:
        for i in range(cases):
            f.write(json.dumps({"width": 0, "got": i, "want": i}) + "\\n")
    print(json.dumps({"status": "pass", "test_count": 1}))
    sys.exit(0)
if a[:2] != ["artifact", "put"]:
    sys.exit(2)
if a[2] == "--help":
    sys.exit(0)
manifest, name, path = a[a.index("--manifest") + 1], a[a.index("--name") + 1], a[-1]
data = open(path, "rb").read()
sha = hashlib.sha256(data).hexdigest()
try:
    doc = json.load(open(manifest))
except FileNotFoundError:
    doc = {"schema_version": 1, "entries": []}
doc["entries"].append({"sha256": sha, "size": len(data), "kind": "evidence",
    "producer": {"tool": "klt", "version": "0", "loom.repo": "o/r", "commit": None},
    "uri": "artifact:evidence/o__r/" + sha[:2] + "/" + sha, "name": name})
json.dump(doc, open(manifest, "w"))
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


def _run_width_keys() -> set[str]:
    """Keys `run_width()` returns, extracted statically from `cross_check.py`
    so the check costs no simulation run."""
    tree = ast.parse((SCRIPT_DIR / "cross_check.py").read_text(encoding="utf-8"))
    keys: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == "run_width":
            for sub in ast.walk(node):
                if isinstance(sub, ast.Return) and isinstance(sub.value, ast.Dict):
                    keys |= {k.value for k in sub.value.keys if isinstance(k, ast.Constant)}
    if not keys:
        raise AssertionError("no returned dict literal found in run_width()")
    return keys


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
             "observed": 500, "transcript_error": None,
             "klt_pass": True, "klt_status": "pass", "transcript_path": t,
             "klt_run_dir": t.parent / f"klt-width{width}",
             "klt_failing_tests": [], "klt_stderr_tail": ""}
        )
    missing = _run_width_keys() - set(summaries[0])
    check("mint fixture keys cover run_width() keys", not missing,
          f"fixture is missing {sorted(missing)}")
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

        # Several live ancestors at once -> list form; one id stays scalar.
        id2 = meta2["record_id"]
        multi = _mint(root, klt, author="third (issue #336)", supersedes=[prior_id, id2])
        meta3 = _meta(multi)
        text3 = multi.read_text(encoding="utf-8")
        check("multi-supersede mint: metadata carries a list",
              meta3["supersedes"] == [prior_id, id2], repr(meta3["supersedes"]))
        check("multi-supersede mint: bullet lists both ids",
              f"- **Supersedes**: {prior_id}, {id2}" in text3)
        single = _meta(_mint(root, klt, author="fourth (issue #336)", supersedes=[prior_id]))
        check("one-element list mints the legacy scalar",
              single["supersedes"] == prior_id, repr(single["supersedes"]))

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

        dup = _cli(
            [
                "--mint-record", "--author", "x",
                "--supersedes", "20991231-235959-0000000",
                "--supersedes", "20991231-235959-0000000",
            ],
            klt_dir, log,
        )
        check("repeated --supersedes id exits nonzero", dup.returncode != 0,
              f"rc={dup.returncode}")
        check(
            "repeated --supersedes FATAL names the rule",
            "FATAL: --supersedes given the same record id twice" in dup.stderr,
            dup.stderr[-200:],
        )

        check("no klt invocation", not log.exists(),
              log.read_text() if log.exists() else "")
        after_records = {p.name for p in real_records.glob("*.md")} if real_records.exists() else set()
        after_manifests = {p.name for p in manifests.glob("*")} if manifests.exists() else set()
        check("no record written", after_records == before_records)
        check("no manifest written", after_manifests == before_manifests)


def test_cli_mints_repeated_supersedes() -> None:
    """`--supersedes` twice, end to end through the real CLI (issue #421):
    the argparse `append` wiring must reach `mint_record` as a two-element
    list, landing in the metadata as a list and naming both ids in the
    **Supersedes** bullet."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "repo"
        root.mkdir()
        _init_repo(root)
        prior_a = "20260101-000000-aaa1111"
        prior_b = "20260101-000000-bbb2222"
        recs = root / "verification" / "records" / cross_check.EXPERIMENT_SLUG / "records"
        recs.mkdir(parents=True)
        for rid in (prior_a, prior_b):
            (recs / f"{rid}.md").write_text(f"<!-- record-meta -->\n# {rid}\n")

        klt_dir = root / "stub-bin"
        klt_dir.mkdir()
        klt = _write_exec(klt_dir / "klt", SIM_KLT_STUB)
        env = {
            **os.environ,
            "PATH": f"{klt_dir}{os.pathsep}{os.environ['PATH']}",
            "KLT": str(klt),
            "REPO_ROOT": str(root),
            "KLT_ARTIFACT_BROKER": "stub-broker",
            "CROSS_CHECK_NO_REEXEC": "1",
        }
        proc = subprocess.run(
            [
                sys.executable, str(SCRIPT_DIR / "cross_check.py"),
                "--widths", "4", "--cases", "2",
                "--mint-record", "--author", "cli-test (issue #421)",
                "--supersedes", prior_a, "--supersedes", prior_b,
            ],
            capture_output=True, text=True, env=env,
        )
        out = proc.stdout + proc.stderr
        check("repeated --supersedes CLI run passes", proc.returncode == 0, out[-400:])
        check("repeated --supersedes CLI mints a record", "Minted record:" in out, out[-200:])

        minted = [p for p in recs.glob("*.md") if p.stem not in (prior_a, prior_b)]
        check("exactly one new record file", len(minted) == 1,
              ", ".join(p.name for p in minted))
        if len(minted) == 1:
            meta = _meta(minted[0])
            text = minted[0].read_text(encoding="utf-8")
            check(
                "minted meta supersedes is the two-id list",
                meta["supersedes"] == [prior_a, prior_b],
                repr(meta["supersedes"]),
            )
            check(
                "minted bullet names both ids",
                f"- **Supersedes**: {prior_a}, {prior_b}" in text,
            )
        check(
            "manifest written for the minted record",
            len(list((root / "manifests" / "artifacts").glob("*.manifest.json"))) == 1,
        )


def main() -> int:
    test_mint_with_supersedes()
    test_cli_rejects_bad_record_args()
    test_cli_mints_repeated_supersedes()
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
