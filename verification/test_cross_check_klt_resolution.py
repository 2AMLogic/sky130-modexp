#!/usr/bin/env python3
"""Self-test for `cross_check.py`'s `klt` resolution (issue #376).

`_resolve_klt()` must resolve `klt` as `$KLT` if set and non-empty (even
when the path does not exist -- the invocation must fail loudly, not
silently fall back), else the `klt` beside the running interpreter (in
production the venv `scripts/setup-env.sh` provisions, entered by
`reexec_into_venv_if_needed`), else `klt` on `$PATH` -- the same
precedence `verification/gate-level/gate_level_cross_check.py` implements
(issue #350) and the shell runners document (`docs/environment.md`'s `KLT`
row). This is what lets the documented pin-check recipe
(`KLT=/tmp/v/bin/klt ...`) reach the correctness gate: `npm run test`
drives this script. When nothing resolves, the existing actionable FATAL
message and `SystemExit(1)` must be unchanged.

Each leg is exercised against stub `klt` binaries (the resolver only ever
checks existence, never executes, so no real `klt` is invoked), with
`sys.executable` redirected into a throwaway directory so the
interpreter-beside leg is under the test's control. A `$KLT` pointing at
a nonexistent path must be returned verbatim -- no existence check, no
silent fallback to the interpreter-beside or `$PATH` candidates: the bug
this pins against is exactly that fallback swallowing a typo'd pin.

Usage: python3 verification/test_cross_check_klt_resolution.py
Exit codes: 0 all pass, 1 otherwise.
"""

from __future__ import annotations

import contextlib
import io
import os
import stat
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


def _write_exec_stub(path: Path) -> Path:
    """A stand-in `klt` executable. `_resolve_klt()` never runs the binary
    it resolves, so a marker script is enough to satisfy its `is_file()` +
    `os.access(X_OK)` probes."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("#!/bin/sh\nexit 111  # stub klt; never meant to run\n")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return path


def _resolve(klt: str | None, fake_root: Path, path_env: str):
    """Call the real `_resolve_klt()` with `sys.executable` pointed at
    `fake_root`'s `.venv` python (the resolver looks beside the running
    interpreter, which in production is the provisioned venv's bin), `KLT`
    set to `klt` (or removed when None), and `PATH` set to `path_env`
    (e.g. a stub-only `$PATH`). Returns the resolved path, or re-raises
    the `SystemExit` the no-klt leg raises."""
    saved_env = dict(os.environ)
    saved_executable = sys.executable
    try:
        os.environ["PATH"] = path_env
        if klt is None:
            os.environ.pop("KLT", None)
        else:
            os.environ["KLT"] = klt
        sys.executable = str(fake_root / ".venv" / "bin" / "python")
        return cross_check._resolve_klt()
    finally:
        os.environ.clear()
        os.environ.update(saved_env)
        sys.executable = saved_executable


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="klt-resolution-") as td:
        tmp = Path(td)
        fake_root = tmp / "repo"
        env_klt = _write_exec_stub(tmp / "env-bin" / "klt")
        venv_klt = _write_exec_stub(fake_root / ".venv" / "bin" / "klt")
        path_klt = _write_exec_stub(tmp / "path-bin" / "klt")
        stub_path = f"{tmp / 'path-bin'}{os.pathsep}{os.environ['PATH']}"

        # $KLT wins over both an interpreter-adjacent klt and one on $PATH.
        resolved = _resolve(str(env_klt), fake_root, stub_path)
        check(
            "$KLT is returned verbatim, ahead of the venv and $PATH",
            resolved == str(env_klt),
            f"got {resolved!r}",
        )

        # A nonexistent $KLT is still returned verbatim: no existence
        # check, no silent fallback. The failure belongs to the klt
        # invocation it drives, so a typo'd pin fails loudly instead of
        # quietly running whatever else happens to be installed.
        resolved = _resolve(str(tmp / "no-such" / "klt"), fake_root, stub_path)
        check(
            "nonexistent $KLT is returned verbatim (no fallback)",
            resolved == str(tmp / "no-such" / "klt"),
            f"got {resolved!r}",
        )

        # Empty $KLT is treated as unset: interpreter-adjacent leg wins.
        resolved = _resolve("", fake_root, stub_path)
        check(
            'KLT="" is treated as unset (interpreter-adjacent leg used)',
            resolved == str(venv_klt),
            f"got {resolved!r}",
        )

        # $KLT unset, interpreter-adjacent present: it wins over $PATH --
        # unchanged behaviour.
        resolved = _resolve(None, fake_root, stub_path)
        check(
            "unset KLT prefers the interpreter-adjacent klt over $PATH",
            resolved == str(venv_klt),
            f"got {resolved!r}",
        )

        # $KLT unset, no interpreter-adjacent klt: `klt` on $PATH --
        # unchanged behaviour.
        resolved = _resolve(None, tmp / "repo-no-venv", stub_path)
        check(
            "unset KLT with no interpreter-adjacent klt falls to $PATH",
            resolved == str(path_klt),
            f"got {resolved!r}",
        )

        # Nothing anywhere: the actionable FATAL and SystemExit(1), byte
        # for byte the pre-existing contract. `empty-bin` is the only $PATH
        # entry and holds no `klt`.
        (tmp / "empty-bin").mkdir()
        stderr = io.StringIO()
        got: str | None = None
        try:
            with contextlib.redirect_stderr(stderr):
                got = _resolve(None, tmp / "repo-no-venv", str(tmp / "empty-bin"))
        except SystemExit as exc:
            check("no klt anywhere exits 1", exc.code == 1, f"code={exc.code!r}")
            check(
                "no-klt FATAL message unchanged",
                "FATAL: no `klt` executable" in stderr.getvalue(),
                stderr.getvalue()[-200:],
            )
        else:
            check("no klt anywhere exits 1", False, f"resolved to {got!r}")

    print()
    if failures:
        print(f"{len(failures)} check(s) FAILED")
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
