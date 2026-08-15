"""Shared repo-root git/hash helpers for `verification/` scripts.

`run_git()` and `sha256_of()` are the subprocess-wrapper and content-hashing
logic shared, near-identically, by `check_records.py` and `cross_check.py`.
Both scripts resolve the same `REPO_ROOT` (the parent of `verification/`) and
shell out to `git` against it; centralizing that here means a future change
(e.g. how a git failure is surfaced, or the hash algorithm) only needs to
happen once instead of being replayed -- and silently drifting -- across
multiple files.

`VENV_PYTHON` and `reexec_into_venv_if_needed()` are the analogous shared
home for the "re-exec under `.venv/bin/python3` when the ambient interpreter
can't import cocotb" handshake used by both `cross_check.py` and
`verification/gate-level/gate_level_cross_check.py` -- see issue #25 for the
real bug this handshake had (a `.resolve()`-based interpreter comparison that
made "already in the venv" always true) and issue #39 for why the two
near-identical copies were consolidated here. The guard env-var name is a
required parameter so each caller keeps its own distinct opt-out
(`CROSS_CHECK_NO_REEXEC` / `GATE_LEVEL_NO_REEXEC`).

This module is a plain sibling import (`from _repo_utils import REPO_ROOT,
run_git, sha256_of`), not a cocotb test module or a standalone entry point.

`verification/test_check_records.py` has its own `_git`/`_sha256_text` and is
deliberately NOT migrated to this module: those operate against an arbitrary
fixture repo path with a pinned test committer identity and hash text rather
than file bytes, not `REPO_ROOT` -- a legitimately different helper, not a
duplicate.
"""

from __future__ import annotations

import hashlib
import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
VENV_PYTHON = REPO_ROOT / ".venv" / "bin" / "python3"


def run_git(*args: str) -> str:
    """Run `git <args>` with cwd=REPO_ROOT; raise `CalledProcessError` on
    non-zero exit (`check=True`). Returns stdout with trailing whitespace
    stripped."""
    return subprocess.run(
        ["git", *args], cwd=REPO_ROOT, capture_output=True, text=True, check=True
    ).stdout.strip()


def sha256_of(path: Path) -> str:
    """Return `sha256:<hex digest>` of `path`'s bytes."""
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def reexec_into_venv_if_needed(script_path: Path, no_reexec_env: str) -> None:
    """Re-exec `script_path` under `.venv/bin/python3` when the current
    interpreter cannot import cocotb but the provisioned venv can.

    `scripts/setup-env.sh` installs cocotb/klt into `<repo>/.venv`, and the
    host's default `python3` is frequently a newer interpreter than cocotb
    supports. Without this, an entry point invoked via a bare `python3`
    fails on a correctly-provisioned checkout with an ImportError that tells
    the reader nothing useful. Re-exec is skipped when cocotb already
    imports, when no venv exists, or when we are already the venv's python
    (so this can never loop).

    `script_path` should be the caller's own `Path(__file__)` -- the process
    is re-exec'd running that exact file. `no_reexec_env` is the name of the
    environment variable this call uses as its own re-exec guard; callers
    must pass a name distinct from any other script sharing this helper
    (e.g. `"CROSS_CHECK_NO_REEXEC"`) so each script's guard is independent.
    """
    try:
        import cocotb_tools.runner  # noqa: F401

        return
    except ImportError:
        pass

    if not VENV_PYTHON.exists():
        return
    # Compare the interpreter *directory*, not the resolved binary: a venv's
    # `bin/python3` is a symlink chain that ends at the same system
    # interpreter `sys.executable` resolves to from *outside* the venv too
    # (`.venv/bin/python3` -> `python3.12` -> `/usr/bin/python3.12`), so
    # comparing *resolved* paths (on either or both sides) falsely reports
    # "already in the venv" and skips the re-exec even when running under
    # the ambient interpreter. Compare the unresolved parent directories
    # instead -- when actually invoked as `.venv/bin/python3`,
    # `sys.executable` is that literal (unresolved) path.
    if Path(sys.executable).parent == VENV_PYTHON.parent:
        return
    if os.environ.get(no_reexec_env) == "1":
        return

    os.environ[no_reexec_env] = "1"
    print(
        f"note: cocotb is not importable under {sys.executable}; "
        f"re-executing under {VENV_PYTHON}",
        file=sys.stderr,
        flush=True,
    )
    os.execv(str(VENV_PYTHON), [str(VENV_PYTHON), str(script_path.resolve()), *sys.argv[1:]])
