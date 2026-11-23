#!/usr/bin/env python3
"""Self-test for `verification/_repo_utils.py`.

`_repo_utils.py` is the single home for the repo-root resolution and content
hashing every `verification/` entry point uses (issue #329). That makes it
the one place those contracts are worth testing: once a checker is a bare
`from _repo_utils import REPO_ROOT`, a per-checker nested-copy harness would
be re-testing `find_repo_root()` through a subprocess wrapper rather than
testing anything checker-specific. So the contracts live here, once:

1. `$REPO_ROOT` wins over git, and is returned resolved.
2. With `$REPO_ROOT` unset, the root is `git rev-parse --show-toplevel` run
   from *this module's own directory* -- not the caller's cwd, and not the
   importing script's depth. Proved by copying `_repo_utils.py` one
   directory deeper into a fixture repo and importing it from outside that
   repo entirely.
3. `strict=True` (the default) exits when neither resolves; `strict=False`
   returns `None` instead. The two CLIs that offer `--repo-root`
   (`check_pins.py`, `check_artifact_manifests.py`) depend on the second:
   importing `find_repo_root` must not kill the process before argparse has
   seen the flag.
4. `REPO_ROOT` / `VENV_PYTHON` resolve lazily, so importing only
   `find_repo_root` from outside a git work tree succeeds.
5. `sha256_of()` hashes file bytes, `sha256:`-prefixed by default and bare
   hex under `prefix=False` -- the two forms the committed pins files and
   artifact manifests compare against, from one implementation.
6. The lazily resolved attributes stay patchable: assigning
   `_repo_utils.REPO_ROOT` redirects `run_git()` -- the fixture-isolation
   contract `test_cross_check_mint.py` depends on, and exactly what a
   cache-only read silently deadened (PR #333 review).
7. `resolve_klt()` implements the documented `klt` precedence (issue #382,
   consolidating the two drivers' private copies, issues #350/#376): `$KLT`
   verbatim when set and non-empty -- even when the path does not exist, so
   a typo'd pin fails loudly at the `klt` invocation it drives instead of
   silently falling back -- then the `klt` beside the running interpreter,
   then `klt` on `$PATH`, then `None` (each caller owns its own FATAL
   wording for the `None` case, pinned in the callers' own self-tests).
8. `klt_error_message()` unwraps klt's `--format json` stderr error
   envelope to the bare message and passes anything else (a traceback, a
   crash before the envelope) through tail-truncated via `tail()`, which
   keeps the *end* -- where simulator diagnostics put the actual failure.

Usage: python3 verification/test_repo_utils.py
Exit codes: 0 all cases behave as specified, 1 at least one did not.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

MODULE = Path(__file__).resolve().parent / "_repo_utils.py"

failures: list[str] = []


def record(label: str, ok: bool, detail: str = "") -> None:
    print(f"{'PASS' if ok else 'FAIL'}: {label}")
    if not ok:
        failures.append(label)
        if detail:
            print("  " + detail.strip().replace("\n", "\n  "))


def run_probe(module_dir: Path, code: str, *, cwd: Path, repo_root: str | None) -> tuple[int, str]:
    """Run `code` in a fresh interpreter with `module_dir` on `sys.path`.

    A subprocess is the only honest way to test import-time behaviour: the
    strict branch calls `sys.exit()`, and the lazy resolution is memoized
    per process.
    """
    env = {k: v for k, v in os.environ.items() if k not in ("REPO_ROOT", "PYTHONPATH")}
    if repo_root is not None:
        env["REPO_ROOT"] = repo_root
    prog = f"import sys; sys.path.insert(0, {str(module_dir)!r})\n" + code
    res = subprocess.run(
        [sys.executable, "-c", prog], cwd=cwd, env=env, capture_output=True, text=True
    )
    return res.returncode, res.stdout + res.stderr


def case_env_wins_and_is_resolved() -> None:
    """$REPO_ROOT beats the git lookup, and comes back resolved."""
    with tempfile.TemporaryDirectory(prefix="repo-utils-selftest-") as tmp:
        target = Path(tmp) / "elsewhere"
        (target / "sub").mkdir(parents=True)
        # Deliberately unresolved: a trailing `sub/..` must collapse.
        rc, out = run_probe(
            MODULE.parent,
            "from _repo_utils import REPO_ROOT; print(REPO_ROOT)",
            cwd=Path(tmp),
            repo_root=str(target / "sub" / ".."),
        )
        ok = rc == 0 and out.strip() == str(target.resolve())
        record("$REPO_ROOT wins over git and is returned resolved", ok, f"exit {rc}: {out}")


def case_nested_copy_uses_its_own_git_toplevel() -> None:
    """The module copied one directory deeper, imported from outside the
    fixture repo, still resolves that repo's toplevel."""
    with tempfile.TemporaryDirectory(prefix="repo-utils-selftest-") as tmp:
        repo = Path(tmp) / "fixture"
        (repo / "common").mkdir(parents=True)
        subprocess.run(["git", "init", "--quiet", str(repo)], check=True)
        shutil.copyfile(MODULE, repo / "common" / "_repo_utils.py")
        rc, out = run_probe(
            repo / "common",
            "from _repo_utils import REPO_ROOT; print(REPO_ROOT)",
            cwd=Path(tmp),  # outside the fixture repo on purpose
            repo_root=None,
        )
        want = str(Path(subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()))
        ok = rc == 0 and out.strip() == want
        record(
            "nested copy resolves the enclosing repo, not its parent dir or the cwd",
            ok,
            f"exit {rc}, want {want}: {out}",
        )
        # The copy's own parent directory is NOT the answer: if it were, the
        # assertion above would be vacuous.
        record(
            "fixture is shaped so the parent-dir answer would differ",
            want != str(repo / "common") and want != str(Path(tmp)),
            f"toplevel {want}",
        )


def _nongit_dir(tmp: Path) -> Path | None:
    """A directory holding a copy of the module and provably not in a repo."""
    d = tmp / "loose"
    d.mkdir()
    shutil.copyfile(MODULE, d / "_repo_utils.py")
    probe = subprocess.run(
        ["git", "-C", str(d), "rev-parse", "--show-toplevel"], capture_output=True, text=True
    )
    return d if probe.returncode != 0 else None


def case_strict_modes_outside_a_git_tree() -> None:
    """strict=True exits; strict=False returns None; and importing only
    `find_repo_root` does not resolve anything at all."""
    with tempfile.TemporaryDirectory(prefix="repo-utils-selftest-") as tmp:
        loose = _nongit_dir(Path(tmp))
        if loose is None:
            record("temp dir is outside any git work tree (precondition)", False,
                   "the system temp dir is inside a git repo; cannot test the no-git branch")
            return
        record("temp dir is outside any git work tree (precondition)", True)

        rc, out = run_probe(
            loose,
            "from _repo_utils import REPO_ROOT; print(REPO_ROOT)",
            cwd=Path(tmp), repo_root=None,
        )
        record(
            "strict REPO_ROOT access exits with a FATAL message outside a git tree",
            rc != 0 and "not inside a git work tree" in out,
            f"exit {rc}: {out}",
        )

        rc, out = run_probe(
            loose,
            "from _repo_utils import find_repo_root\n"
            "print('NONE' if find_repo_root(strict=False) is None else 'SOMETHING')",
            cwd=Path(tmp), repo_root=None,
        )
        record(
            "find_repo_root(strict=False) returns None instead of exiting",
            rc == 0 and out.strip() == "NONE",
            f"exit {rc}: {out}",
        )

        rc, out = run_probe(
            loose,
            "from _repo_utils import find_repo_root\nprint('IMPORTED')",
            cwd=Path(tmp), repo_root=None,
        )
        record(
            "importing find_repo_root alone never resolves the root (lazy attributes)",
            rc == 0 and out.strip() == "IMPORTED",
            f"exit {rc}: {out}",
        )

        rc, out = run_probe(
            loose,
            "import _repo_utils; _repo_utils.VENV_PYTHON",
            cwd=Path(tmp), repo_root=None,
        )
        record(
            "VENV_PYTHON is lazy too and reports the same FATAL",
            rc != 0 and "not inside a git work tree" in out,
            f"exit {rc}: {out}",
        )

        rc, out = run_probe(
            loose,
            "import _repo_utils\n"
            "try:\n"
            "    _repo_utils.NOT_A_THING\n"
            "except AttributeError as exc:\n"
            "    print('ATTRIBUTEERROR')\n",
            cwd=Path(tmp), repo_root=None,
        )
        record(
            "an unknown module attribute still raises AttributeError",
            rc == 0 and out.strip() == "ATTRIBUTEERROR",
            f"exit {rc}: {out}",
        )


def case_patching_repo_root_redirects_run_git() -> None:
    """`_repo_utils.REPO_ROOT = fixture` must redirect `run_git()`.

    `run_git` reads the module attribute before the memoized resolver, so
    assigning the attribute stays the fixture-isolation mechanism
    `test_cross_check_mint.py` uses. A read that only consults
    `_repo_root()` keeps running git against the real repo while the patch
    looks effective -- the regression PR #333's review caught, invisible
    to a test that never asserts on the value.
    """
    real = subprocess.run(
        ["git", "-C", str(MODULE.parent), "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    with tempfile.TemporaryDirectory(prefix="repo-utils-selftest-") as tmp:
        repo = Path(tmp) / "fixture"
        repo.mkdir()
        subprocess.run(["git", "init", "--quiet", str(repo)], check=True)
        want = subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        record("fixture root differs from this checkout's root (precondition)",
               want != real, f"fixture {want}, real {real}")
        rc, out = run_probe(
            MODULE.parent,
            "import _repo_utils\n"
            f"_repo_utils.REPO_ROOT = {str(repo)!r}\n"
            "print(_repo_utils.run_git('rev-parse', '--show-toplevel'))\n",
            cwd=Path(tmp),  # outside the fixture repo, like the real callers
            repo_root=None,
        )
        record("patching _repo_utils.REPO_ROOT redirects run_git()",
               rc == 0 and out.strip() == want, f"exit {rc}, want {want}: {out}")
        # Control, the direction the regression was measured in: without the
        # patch the same probe resolves this checkout, not the fixture.
        rc2, out2 = run_probe(
            MODULE.parent,
            "import _repo_utils\n"
            "print(_repo_utils.run_git('rev-parse', '--show-toplevel'))\n",
            cwd=Path(tmp),
            repo_root=None,
        )
        record("unpatched run_git() resolves the real repo, not the fixture",
               rc2 == 0 and out2.strip() == real, f"exit {rc2}, want {real}: {out2}")


def case_sha256_prefix_contract() -> None:
    """One algorithm, two serializations: prefixed and bare hex."""
    sys.path.insert(0, str(MODULE.parent))
    from _repo_utils import sha256_of

    with tempfile.TemporaryDirectory(prefix="repo-utils-selftest-") as tmp:
        f = Path(tmp) / "payload.bin"
        payload = b"the bytes that get hashed\n\x00\xff"
        f.write_bytes(payload)
        want = hashlib.sha256(payload).hexdigest()
        record("sha256_of() returns sha256:<hex> by default",
               sha256_of(f) == f"sha256:{want}", sha256_of(f))
        record("sha256_of(prefix=False) returns bare hex",
               sha256_of(f, prefix=False) == want, sha256_of(f, prefix=False))
        record("both forms are the same digest",
               sha256_of(f) == "sha256:" + sha256_of(f, prefix=False))
        record("prefix is keyword-only (a positional second arg is rejected)",
               _rejects_positional(sha256_of, f))


def _rejects_positional(fn, arg) -> bool:
    try:
        fn(arg, False)
    except TypeError:
        return True
    return False


def case_resolve_klt_precedence() -> None:
    """`resolve_klt()` precedence: `$KLT` verbatim (even nonexistent) ->
    beside-interpreter -> `$PATH` -> `None`.

    These are the legs both cross-check drivers used to carry as private
    `_resolve_klt()` copies kept in sync by prose (issues #350/#376); one
    implementation means one place to test them (issue #382). Exercised
    against stub binaries -- the resolver only ever checks existence,
    never executes -- with `sys.executable` redirected into a throwaway
    directory so the interpreter-beside leg is under the test's control.
    """
    sys.path.insert(0, str(MODULE.parent))
    from _repo_utils import resolve_klt

    def _write_exec_stub(path: Path) -> Path:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("#!/bin/sh\nexit 111  # stub klt; never meant to run\n")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)
        return path

    def _resolve(klt: str | None, fake_root: Path, path_env: str) -> str | None:
        saved_env = dict(os.environ)
        saved_executable = sys.executable
        try:
            os.environ["PATH"] = path_env
            if klt is None:
                os.environ.pop("KLT", None)
            else:
                os.environ["KLT"] = klt
            sys.executable = str(fake_root / ".venv" / "bin" / "python")
            return resolve_klt()
        finally:
            os.environ.clear()
            os.environ.update(saved_env)
            sys.executable = saved_executable

    with tempfile.TemporaryDirectory(prefix="repo-utils-resolve-klt-") as td:
        tmp = Path(td)
        fake_root = tmp / "repo"
        env_klt = _write_exec_stub(tmp / "env-bin" / "klt")
        venv_klt = _write_exec_stub(fake_root / ".venv" / "bin" / "klt")
        path_klt = _write_exec_stub(tmp / "path-bin" / "klt")
        stub_path = f"{tmp / 'path-bin'}{os.pathsep}{os.environ['PATH']}"

        # $KLT wins over both an interpreter-adjacent klt and one on $PATH.
        resolved = _resolve(str(env_klt), fake_root, stub_path)
        record("$KLT is returned verbatim, ahead of the venv and $PATH",
               resolved == str(env_klt), f"got {resolved!r}")

        # A nonexistent $KLT is still returned verbatim: no existence
        # check, no silent fallback. The failure belongs to the klt
        # invocation it drives, so a typo'd pin fails loudly instead of
        # quietly running whatever else happens to be installed.
        resolved = _resolve(str(tmp / "no-such" / "klt"), fake_root, stub_path)
        record("nonexistent $KLT is returned verbatim (no fallback)",
               resolved == str(tmp / "no-such" / "klt"), f"got {resolved!r}")

        # Empty $KLT is treated as unset: interpreter-adjacent leg wins.
        resolved = _resolve("", fake_root, stub_path)
        record('KLT="" is treated as unset (interpreter-adjacent leg used)',
               resolved == str(venv_klt), f"got {resolved!r}")

        # $KLT unset, interpreter-adjacent present: it wins over $PATH.
        resolved = _resolve(None, fake_root, stub_path)
        record("unset KLT prefers the interpreter-adjacent klt over $PATH",
               resolved == str(venv_klt), f"got {resolved!r}")

        # $KLT unset, no interpreter-adjacent klt: `klt` on $PATH.
        resolved = _resolve(None, tmp / "repo-no-venv", stub_path)
        record("unset KLT with no interpreter-adjacent klt falls to $PATH",
               resolved == str(path_klt), f"got {resolved!r}")

        # Nothing anywhere: the helper contract is `None`; each caller
        # turns that into its own actionable FATAL (kept pinned by the
        # callers' own self-tests).
        (tmp / "empty-bin").mkdir()
        resolved = _resolve(None, tmp / "repo-no-venv", str(tmp / "empty-bin"))
        record("nothing anywhere resolves to None (callers own the FATAL)",
               resolved is None, f"got {resolved!r}")


def case_klt_error_message_unwrap_and_tail() -> None:
    """`klt_error_message()` unwraps klt's stderr error envelope to the
    bare message; anything else passes through tail-truncated via
    `tail()`, which keeps the end where the failure text is."""
    sys.path.insert(0, str(MODULE.parent))
    from _repo_utils import klt_error_message, tail

    envelope = json.dumps({
        "schema_version": 1,
        "error": {"command": "functional-verification",
                  "message": "boom: no simulator"},
    })
    record("klt stderr error envelope unwraps to the bare message",
           klt_error_message(envelope) == "boom: no simulator",
           klt_error_message(envelope))

    not_json = "traceback " + "x" * 2000 + "the-actual-failure"
    got = klt_error_message(not_json)
    record("non-envelope stderr passes through tail-truncated",
           got == tail(not_json, 600) and got.endswith("the-actual-failure"),
           got[-60:])

    record("empty stderr yields an empty diagnostic",
           klt_error_message("") == "", repr(klt_error_message("")))

    no_error = json.dumps({"schema_version": 1, "status": "pass"})
    record("valid JSON without an error envelope passes through",
           klt_error_message(no_error) == no_error, klt_error_message(no_error))

    record("tail bounds the length and keeps the end",
           tail("a" * 5000 + "end", 600) == "a" * 597 + "end"
           and tail("short", 600) == "short",
           tail("a" * 5000 + "end", 600)[-60:])


def case_read_transcript_counts_and_completeness() -> None:
    """`read_transcript()` / `transcript_completeness_error()` (issue #418):
    a missing file is None (never zero mismatches); rows are counted once;
    only an exact expected count is complete."""
    sys.path.insert(0, str(MODULE.parent))
    from _repo_utils import read_transcript, transcript_completeness_error

    with tempfile.TemporaryDirectory() as tmp:
        t = Path(tmp) / "t.jsonl"
        record("missing transcript reads as None", read_transcript(t) is None)
        record("missing transcript is incomplete",
               transcript_completeness_error(None, 3) is not None)
        rows = [{"got": "a", "want": "a"}, {"got": "b", "want": "a"},
                {"got": "a", "want": "a"}]
        t.write_text("\n".join(json.dumps(r) for r in rows) + "\n\n")
        got = read_transcript(t)
        record("counts rows and mismatches, skips blank lines",
               got is not None and got["total"] == 3 and got["mismatches"] == 1
               and got["examples"] == [rows[1]], repr(got))
        record("exact count is complete", transcript_completeness_error(got, 3) is None)
        record("short is incomplete", transcript_completeness_error(got, 4) is not None)
        record("overlong is incomplete", transcript_completeness_error(got, 2) is not None)


def main() -> int:
    if not MODULE.exists():
        print(f"FATAL: {MODULE} not found", file=sys.stderr)
        return 1
    case_env_wins_and_is_resolved()
    case_nested_copy_uses_its_own_git_toplevel()
    case_strict_modes_outside_a_git_tree()
    case_patching_repo_root_redirects_run_git()
    case_sha256_prefix_contract()
    case_resolve_klt_precedence()
    case_klt_error_message_unwrap_and_tail()
    case_read_transcript_counts_and_completeness()
    print(f"test_repo_utils: {len(failures)} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
