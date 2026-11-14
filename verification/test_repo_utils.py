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

Usage: python3 verification/test_repo_utils.py
Exit codes: 0 all cases behave as specified, 1 at least one did not.
"""

from __future__ import annotations

import hashlib
import os
import shutil
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


def main() -> int:
    if not MODULE.exists():
        print(f"FATAL: {MODULE} not found", file=sys.stderr)
        return 1
    case_env_wins_and_is_resolved()
    case_nested_copy_uses_its_own_git_toplevel()
    case_strict_modes_outside_a_git_tree()
    case_sha256_prefix_contract()
    print(f"test_repo_utils: {len(failures)} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
