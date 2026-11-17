#!/usr/bin/env python3
"""Self-test for `cross_check.py`'s no-`klt` FATAL (issues #376, #382).

The `$KLT` / interpreter-adjacent / `$PATH` precedence legs this file used
to carry now live with the one implementation they test,
`_repo_utils.resolve_klt()` (see `verification/test_repo_utils.py`;
issue #382 consolidated the two drivers' line-identical private copies).
What stays here is the part specific to this script: when nothing
resolves anywhere, the gate must die with its own actionable FATAL
message and exit status 1 -- byte for byte the pre-existing contract.
The helper deliberately returns `None` instead of owning that message so
each driver keeps its own wording (this one names the cross-check and
its provisioning recipe; `gate_level_cross_check.py` says "this script").

The FATAL is exercised by driving the real `main()` with `sys.executable`
redirected into a throwaway directory (so the interpreter-adjacent leg is
under the test's control) and a `$PATH` whose only entry holds no `klt`;
no real `klt` is ever invoked.

Usage: python3 verification/test_cross_check_klt_resolution.py
Exit codes: 0 all pass, 1 otherwise.
"""

from __future__ import annotations

import contextlib
import io
import os
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


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="klt-resolution-") as td:
        tmp = Path(td)
        # `empty-bin` is the only $PATH entry and holds no `klt`; the
        # redirected interpreter's directory holds no `klt` beside it
        # either. Nothing anywhere resolves.
        (tmp / "empty-bin").mkdir()
        fake_root = tmp / "repo"
        stderr = io.StringIO()
        saved_env = dict(os.environ)
        saved_executable = sys.executable
        saved_argv = list(sys.argv)
        try:
            os.environ["PATH"] = str(tmp / "empty-bin")
            os.environ.pop("KLT", None)
            sys.executable = str(fake_root / ".venv" / "bin" / "python")
            sys.argv = ["cross_check.py"]
            with contextlib.redirect_stderr(stderr):
                cross_check.main()
        except SystemExit as exc:
            check("no klt anywhere exits 1", exc.code == 1, f"code={exc.code!r}")
            check(
                "no-klt FATAL message unchanged",
                "FATAL: no `klt` executable" in stderr.getvalue()
                and "./scripts/setup-env.sh" in stderr.getvalue(),
                stderr.getvalue()[-200:],
            )
        else:
            check("no klt anywhere exits 1", False, "main() returned without exiting")
        finally:
            os.environ.clear()
            os.environ.update(saved_env)
            sys.executable = saved_executable
            sys.argv = saved_argv

    print()
    if failures:
        print(f"{len(failures)} check(s) FAILED")
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
