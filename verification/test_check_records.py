#!/usr/bin/env python3
"""Self-test for `verification/check_records.py`.

The record linter is the only thing standing between "append-only evidence"
as a documented intention and append-only evidence as an enforced property.
A linter that silently stops catching a violation class is worse than no
linter, so each violation class the convention names in
`verification/README.md` gets an executable negative test here.

Method: build a throwaway git repo in a temp dir, copy the *real*
`check_records.py` into its `verification/` directory (the linter resolves
its repo root from `__file__`, so the copy lints the fixture repo), and run
it as a subprocess exactly the way `npm run lint` and CI do. Nothing is
monkeypatched, so this exercises the shipped entry point rather than a
stand-in.

Zero dependencies beyond the Python 3 standard library and `git`.

Usage:
    python3 verification/test_check_records.py
Exit codes: 0 all cases behave as specified, 1 at least one did not.
"""

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
LINTER = SCRIPT_DIR / "check_records.py"
REPO_UTILS = SCRIPT_DIR / "_repo_utils.py"

BASE_REF = "refs/heads/fixture-base"

DUMMY_RTL = "module dut(input wire clk); endmodule\n"


def _sha256_text(text: str) -> str:
    return "sha256:" + hashlib.sha256(text.encode("utf-8")).hexdigest()


def _git(repo: Path, *args: str) -> str:
    result = subprocess.run(
        [
            "git",
            "-c",
            "user.name=record-linter-selftest",
            "-c",
            "user.email=selftest@example.invalid",
            "-c",
            "commit.gpgsign=false",
            *args,
        ],
        cwd=repo,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"git {' '.join(args)} failed in {repo}: {result.stderr.strip()}"
        )
    return result.stdout


def make_record(
    record_id: str,
    experiment: str,
    *,
    inputs: list[tuple[str, str]],
    supersedes: str | None = None,
    omit_field: str | None = None,
    omit_provenance_key: str | None = None,
) -> str:
    """Render a record that satisfies the convention in
    `verification/README.md`, optionally omitting one required prose field
    so a negative case can be built from it."""
    meta = {
        "record_id": record_id,
        "experiment": experiment,
        "supersedes": supersedes,
        "git_revision": "0" * 40,
        "provenance": {
            "klt_version": "0.0.0-selftest",
            "pdk": {"name": "n/a", "version": "n/a"},
            "deck": {"content_hash": "n/a"},
            "inputs": [
                {"path": path, "content_hash": content_hash}
                for path, content_hash in inputs
            ],
        },
    }
    if omit_provenance_key is not None:
        meta["provenance"].pop(omit_provenance_key)
    fields = [
        ("Record ID", record_id),
        ("Claim", "`docs/baseline.md#the-measurement` -- fixture claim"),
        ("Design provenance", "rtl (`rtl/dut.v` @ `" + "0" * 40 + "`)"),
        ("Run configuration", "fixture run, no real simulator invoked"),
        ("Statistical convention", "N/A (fixture)"),
        ("Result", "**Overall: PASS** (fixture)"),
        ("klt provenance", "klt 0.0.0-selftest; PDK: n/a; deck content_hash: n/a"),
        ("Links", "Design under test: `rtl/dut.v`"),
        ("Timestamp / author", "2026-01-01T00:00:00Z, selftest"),
        ("Supersedes", supersedes or "none"),
    ]
    bullets = "\n".join(
        f"- **{name}**: {value}" for name, value in fields if name != omit_field
    )
    return (
        "<!-- record-meta\n"
        + json.dumps(meta, indent=2)
        + "\n-->\n\n"
        + f"# Record {record_id}\n\n"
        + bullets
        + "\n"
    )


def build_fixture_repo(tmp: Path) -> Path:
    """A minimal repo with one valid record committed, and `BASE_REF`
    pointing at that commit so the append-only check has a base to diff."""
    repo = tmp / "fixture"
    (repo / "rtl").mkdir(parents=True)
    (repo / "verification" / "records" / "demo" / "records").mkdir(parents=True)

    (repo / "rtl" / "dut.v").write_text(DUMMY_RTL, encoding="utf-8")
    shutil.copyfile(LINTER, repo / "verification" / "check_records.py")
    shutil.copyfile(REPO_UTILS, repo / "verification" / "_repo_utils.py")

    record = make_record(
        "20260101-000000-abc1234",
        "demo",
        inputs=[("rtl/dut.v", _sha256_text(DUMMY_RTL))],
    )
    (
        repo / "verification" / "records" / "demo" / "records" / "20260101-000000-abc1234.md"
    ).write_text(record, encoding="utf-8")

    _git(repo, "init", "--quiet")
    _git(repo, "add", "-A")
    _git(repo, "commit", "--quiet", "-m", "fixture: initial record")
    _git(repo, "update-ref", BASE_REF, "HEAD")
    return repo


def run_linter(repo: Path) -> tuple[int, str]:
    result = subprocess.run(
        [
            sys.executable,
            str(repo / "verification" / "check_records.py"),
            "--base-ref",
            BASE_REF,
            "--require-append-only",
        ],
        cwd=repo,
        capture_output=True,
        text=True,
    )
    return result.returncode, result.stdout + result.stderr


def record_path(repo: Path, experiment: str, record_id: str) -> Path:
    return (
        repo / "verification" / "records" / experiment / "records" / f"{record_id}.md"
    )


# --- cases -----------------------------------------------------------------
# Each case mutates a fresh fixture repo and returns nothing; the harness
# asserts the expected exit code and a substring of the linter's output.


def case_valid(repo: Path) -> None:
    """Control: an untouched fixture must pass, or every negative case below
    would pass for the wrong reason."""


def case_missing_required_field(repo: Path) -> None:
    new_id = "20260102-000000-abc1234"
    path = record_path(repo, "demo", new_id)
    path.write_text(
        make_record(
            new_id,
            "demo",
            inputs=[("rtl/dut.v", _sha256_text(DUMMY_RTL))],
            omit_field="Claim",
        ),
        encoding="utf-8",
    )
    _git(repo, "add", "-A")
    _git(repo, "commit", "--quiet", "-m", "fixture: record missing Claim")


def case_missing_required_meta_key(repo: Path) -> None:
    new_id = "20260102-000000-abc1234"
    record_path(repo, "demo", new_id).write_text(
        make_record(
            new_id,
            "demo",
            inputs=[("rtl/dut.v", _sha256_text(DUMMY_RTL))],
            omit_provenance_key="klt_version",
        ),
        encoding="utf-8",
    )
    _git(repo, "add", "-A")
    _git(repo, "commit", "--quiet", "-m", "fixture: record missing klt_version")


def case_edited_existing_record(repo: Path) -> None:
    path = record_path(repo, "demo", "20260101-000000-abc1234")
    path.write_text(
        path.read_text(encoding="utf-8").replace("fixture claim", "edited claim"),
        encoding="utf-8",
    )
    _git(repo, "add", "-A")
    _git(repo, "commit", "--quiet", "-m", "fixture: edit an existing record")


def case_deleted_existing_record(repo: Path) -> None:
    _git(
        repo,
        "rm",
        "--quiet",
        "verification/records/demo/records/20260101-000000-abc1234.md",
    )
    _git(repo, "commit", "--quiet", "-m", "fixture: delete an existing record")


def case_stale_provenance_hash(repo: Path) -> None:
    (repo / "rtl" / "dut.v").write_text(
        DUMMY_RTL + "// the RTL changed after the record was minted\n",
        encoding="utf-8",
    )
    _git(repo, "add", "-A")
    _git(repo, "commit", "--quiet", "-m", "fixture: change the cited source")


def case_superseded_record_exempt_from_freshness(repo: Path) -> None:
    """A superseded record is frozen history: it may legitimately cite a
    source that has since changed. Only the live record must be fresh."""
    new_rtl = DUMMY_RTL + "// v2\n"
    (repo / "rtl" / "dut.v").write_text(new_rtl, encoding="utf-8")
    new_id = "20260103-000000-abc1234"
    record_path(repo, "demo", new_id).write_text(
        make_record(
            new_id,
            "demo",
            inputs=[("rtl/dut.v", _sha256_text(new_rtl))],
            supersedes="20260101-000000-abc1234",
        ),
        encoding="utf-8",
    )
    _git(repo, "add", "-A")
    _git(repo, "commit", "--quiet", "-m", "fixture: supersede the first record")


def case_bad_record_id_grammar(repo: Path) -> None:
    bad = record_path(repo, "demo", "not-a-record-id")
    bad.write_text(
        make_record(
            "not-a-record-id",
            "demo",
            inputs=[("rtl/dut.v", _sha256_text(DUMMY_RTL))],
        ),
        encoding="utf-8",
    )
    _git(repo, "add", "-A")
    _git(repo, "commit", "--quiet", "-m", "fixture: malformed record id")


def case_dangling_supersedes(repo: Path) -> None:
    new_id = "20260104-000000-abc1234"
    record_path(repo, "demo", new_id).write_text(
        make_record(
            new_id,
            "demo",
            inputs=[("rtl/dut.v", _sha256_text(DUMMY_RTL))],
            supersedes="20250101-000000-deadbee",
        ),
        encoding="utf-8",
    )
    _git(repo, "add", "-A")
    _git(repo, "commit", "--quiet", "-m", "fixture: supersedes a nonexistent record")


def case_new_record_is_a_pure_addition(repo: Path) -> None:
    """Adding a record must NOT trip the append-only check -- otherwise the
    convention would forbid the very thing it exists to allow."""
    new_id = "20260105-000000-abc1234"
    record_path(repo, "demo", new_id).write_text(
        make_record(
            new_id, "demo", inputs=[("rtl/dut.v", _sha256_text(DUMMY_RTL))]
        ),
        encoding="utf-8",
    )
    _git(repo, "add", "-A")
    _git(repo, "commit", "--quiet", "-m", "fixture: add a new record")


CASES = [
    # (name, mutation, expected_exit, expected_substring)
    ("valid record passes", case_valid, 0, "PASS: all records valid"),
    (
        "record missing a required prose field fails",
        case_missing_required_field,
        1,
        "missing required field bullet `- **Claim**:`",
    ),
    (
        "record missing a required provenance key fails",
        case_missing_required_meta_key,
        1,
        "provenance missing required key `klt_version`",
    ),
    (
        "edited existing record fails (append-only)",
        case_edited_existing_record,
        1,
        "append-only violation",
    ),
    (
        "deleted existing record fails (append-only)",
        case_deleted_existing_record,
        1,
        "append-only violation",
    ),
    (
        "stale provenance hash fails",
        case_stale_provenance_hash,
        1,
        "is stale",
    ),
    (
        "superseded record is exempt from hash freshness",
        case_superseded_record_exempt_from_freshness,
        0,
        "PASS: all records valid",
    ),
    (
        "malformed record id fails",
        case_bad_record_id_grammar,
        1,
        "is not a valid record-id",
    ),
    (
        "supersedes naming a nonexistent record fails",
        case_dangling_supersedes,
        1,
        "which has no record",
    ),
    (
        "adding a new record is allowed",
        case_new_record_is_a_pure_addition,
        0,
        "no append-only violations",
    ),
]


def main() -> int:
    if not LINTER.exists():
        print(f"FATAL: {LINTER} not found", file=sys.stderr)
        return 1
    if not REPO_UTILS.exists():
        print(f"FATAL: {REPO_UTILS} not found", file=sys.stderr)
        return 1

    print(f"== check_records.py self-test ({len(CASES)} cases) ==")
    failures = 0
    for name, mutate, expected_exit, expected_substring in CASES:
        with tempfile.TemporaryDirectory(prefix="record-linter-selftest-") as tmpdir:
            repo = build_fixture_repo(Path(tmpdir))
            mutate(repo)
            exit_code, output = run_linter(repo)

            problems = []
            if exit_code != expected_exit:
                problems.append(f"exit {exit_code}, expected {expected_exit}")
            if expected_substring not in output:
                problems.append(f"output missing {expected_substring!r}")

            if problems:
                failures += 1
                print(f"FAIL: {name}")
                for problem in problems:
                    print(f"  - {problem}")
                print("  --- linter output ---")
                for line in output.splitlines():
                    print(f"  | {line}")
            else:
                print(f"OK:   {name}")

    print()
    if failures:
        print(f"FAIL: {failures}/{len(CASES)} self-test case(s) did not behave as specified")
        return 1
    print(f"PASS: all {len(CASES)} self-test cases behaved as specified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
