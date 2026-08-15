"""Shared repo-root git/hash helpers for `verification/` scripts.

`run_git()` and `sha256_of()` are the subprocess-wrapper and content-hashing
logic shared, near-identically, by `check_records.py` and `cross_check.py`.
Both scripts resolve the same `REPO_ROOT` (the parent of `verification/`) and
shell out to `git` against it; centralizing that here means a future change
(e.g. how a git failure is surfaced, or the hash algorithm) only needs to
happen once instead of being replayed -- and silently drifting -- across
multiple files.

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
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


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
