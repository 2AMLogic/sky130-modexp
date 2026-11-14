"""Shared repo-root git/hash helpers for `verification/` scripts.

`run_git()` and `sha256_of()` are the subprocess-wrapper and content-hashing
logic shared, near-identically, by `check_records.py` and `cross_check.py`.
Both scripts resolve the same `REPO_ROOT` (the parent of `verification/`) and
shell out to `git` against it; centralizing that here means a future change
(e.g. how a git failure is surfaced, or the hash algorithm) only needs to
happen once instead of being replayed -- and silently drifting -- across
multiple files.

Every `verification/` entry point that needs the repo root or a content hash
imports it from here (issue #329): `check_records.py`, `cross_check.py`,
`check_pins.py`, `check_artifact_manifests.py`,
`repro_out_of_domain_mismatch.py`, `gate-level/gate_level_cross_check.py`,
`signoff/check_netlist_freshness.py` and
`signoff/gen_characterization_envelope.py`. Scripts in a subdirectory of
`verification/` reach this module with the two-line `sys.path.insert` +
`# noqa: E402` preamble `gate-level/gate_level_cross_check.py` uses. That
preamble locates the *sibling module* by relative path, which is
unavoidable; the *repo root* still comes from `find_repo_root()` below, so
`$REPO_ROOT` is honoured no matter how deep the importing script sits.

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
duplicate. The self-tests' fixture-building helpers generally are outside
this module's remit for the same reason.
"""

from __future__ import annotations

import hashlib
import os
import subprocess
import sys
from pathlib import Path

def find_repo_root(*, strict: bool = True) -> Path | None:
    """`$REPO_ROOT` if set, else `git rev-parse --show-toplevel` run from this
    file's directory. Independent of how deep this file sits in the tree, so
    a byte-identical copy vendored under e.g. `common/` resolves the
    consuming repo's root, not its own parent directory.

    `strict=True` (the default) exits the process when neither resolves --
    the right answer for a script whose every path is relative to the root.
    `strict=False` returns `None` instead, for a CLI that offers an explicit
    `--repo-root` the caller can supply as the fallback (`check_pins.py`,
    `check_artifact_manifests.py`); those must not die at import time when
    the answer is about to arrive on the command line."""
    if os.environ.get("REPO_ROOT"):
        return Path(os.environ["REPO_ROOT"]).resolve()
    git = subprocess.run(
        ["git", "-C", str(Path(__file__).resolve().parent), "rev-parse", "--show-toplevel"],
        capture_output=True, text=True,
    )
    if git.returncode != 0:
        if not strict:
            return None
        sys.exit("FATAL: not inside a git work tree and REPO_ROOT is not set")
    return Path(git.stdout.strip())


_REPO_ROOT_CACHE: Path | None = None


def _repo_root() -> Path:
    """Memoized `find_repo_root()`, for this module's own use and to back the
    lazily resolved `REPO_ROOT` / `VENV_PYTHON` module attributes."""
    global _REPO_ROOT_CACHE
    if _REPO_ROOT_CACHE is None:
        _REPO_ROOT_CACHE = find_repo_root()
    return _REPO_ROOT_CACHE


def __getattr__(name: str):
    """Resolve `REPO_ROOT` / `VENV_PYTHON` on first access (PEP 562).

    `from _repo_utils import REPO_ROOT` behaves exactly as an eager
    module-level constant would, including the `strict` exit above. Deferring
    it matters for the importers that do NOT want the root this way: a CLI
    taking `--repo-root` imports only `find_repo_root` and so never triggers
    a resolution that would exit before argparse has seen the flag."""
    if name == "REPO_ROOT":
        return _repo_root()
    if name == "VENV_PYTHON":
        return _repo_root() / ".venv" / "bin" / "python3"
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


def run_git(*args: str) -> str:
    """Run `git <args>` with cwd=REPO_ROOT; raise `CalledProcessError` on
    non-zero exit (`check=True`). Returns stdout with trailing whitespace
    stripped."""
    return subprocess.run(
        ["git", *args], cwd=_repo_root(), capture_output=True, text=True, check=True
    ).stdout.strip()


def sha256_of(path: Path, *, prefix: bool = True) -> str:
    """Return the sha256 of `path`'s bytes, as `sha256:<hex>` by default.

    `prefix=False` returns the bare hex digest, for the callers that compare
    against pinned bare-hex values (`signoff/netlist-derivations.json`, the
    `entries[].sha256` of an artifact manifest). The algorithm lives here
    once either way -- the prefix is a serialization detail of the data being
    compared, not a reason for a second implementation."""
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return f"sha256:{digest}" if prefix else digest


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

    venv_python = _repo_root() / ".venv" / "bin" / "python3"
    if not venv_python.exists():
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
    if Path(sys.executable).parent == venv_python.parent:
        return
    if os.environ.get(no_reexec_env) == "1":
        return

    os.environ[no_reexec_env] = "1"
    print(
        f"note: cocotb is not importable under {sys.executable}; "
        f"re-executing under {venv_python}",
        file=sys.stderr,
        flush=True,
    )
    os.execv(str(venv_python), [str(venv_python), str(script_path.resolve()), *sys.argv[1:]])
