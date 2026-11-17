#!/usr/bin/env python3
"""Self-test for `gate_level_cross_check.py`'s `klt` resolution.

`_resolve_klt()` must resolve `klt` as `$KLT` if set and non-empty (even
when the path does not exist -- the invocation must fail loudly, not
silently fall back), else the `klt` beside the running interpreter (in
production the venv `scripts/setup-env.sh` provisions, entered by
`reexec_into_venv_if_needed`), else `klt` on `$PATH` -- the same precedence
the shell runners implement (`docs/environment.md`'s `KLT` row, PR #345).
`resolve_pdk_verilog()` must drive the `klt pdk find` query through
whatever binary the resolver returned. Each leg is exercised by a stub
`klt` whose `pdk find` JSON carries a distinguishable sentinel `version`,
so the test can tell which candidate actually ran. A `$KLT` pointing at a
nonexistent path must raise rather than silently fall through to the
interpreter-beside or `$PATH` candidates -- the silent fallback is the bug
this pins against.

The interpreter's `sys.executable` is redirected into a throwaway
directory so the interpreter-beside leg (the production `.venv` leg) is
under the test's control, and no real `klt` is ever invoked.

Usage: python3 verification/test_gate_level_klt_resolution.py
Exit codes: 0 all pass, 1 otherwise.
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
GATE_LEVEL_DIR = SCRIPT_DIR / "gate-level"
sys.path.insert(0, str(GATE_LEVEL_DIR))

import gate_level_cross_check as gl  # noqa: E402

VERSION_ENV = "9.9-env-stub"
VERSION_VENV = "5.5-venv-stub"
VERSION_PATH = "7.7-path-stub"

failures: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    print(("PASS " if ok else "FAIL ") + label + (f" -- {detail}" if not ok and detail else ""))
    if not ok:
        failures.append(label)


def _write_klt_stub(path: Path, libs_ref: Path, version: str) -> Path:
    """A `klt` whose `pdk find --pdk sky130A --format json` prints a JSON doc
    with the given sentinel `version` and `libs_ref`. Any other invocation is
    a hard stub error, so the test also pins the exact subcommand shape."""
    text = (
        "#!/usr/bin/env python3\n"
        "import json, sys\n"
        "assert sys.argv[1:] == ['pdk', 'find', '--pdk', 'sky130A',"
        " '--format', 'json'], sys.argv\n"
        f"print(json.dumps({{'assets': {{'libs_ref': {str(libs_ref)!r}}},"
        f" 'version': {version!r}}}))\n"
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(0o755)
    return path


def _resolve(klt: str | None, fake_root: Path, env: dict[str, str]):
    """Call the real `_resolve_klt()` + `resolve_pdk_verilog()` pair with
    `sys.executable` pointed at `fake_root`'s `.venv` python (the resolver
    looks beside the running interpreter, which in production is the
    provisioned venv's bin), `KLT` set to `klt` (or removed when None), and
    `env` (e.g. a stub-first `$PATH`) layered over the current environment."""
    saved_env = dict(os.environ)
    saved_executable = sys.executable
    try:
        os.environ.update(env)
        if klt is None:
            os.environ.pop("KLT", None)
        else:
            os.environ["KLT"] = klt
        sys.executable = str(fake_root / ".venv" / "bin" / "python")
        resolved = gl._resolve_klt()
        assert resolved is not None, "_resolve_klt() returned None"
        return gl.resolve_pdk_verilog(resolved)
    finally:
        os.environ.clear()
        os.environ.update(saved_env)
        sys.executable = saved_executable


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="klt-resolution-") as td:
        tmp = Path(td)
        libs_env = tmp / "libs_env"
        libs_venv = tmp / "libs_venv"
        libs_path = tmp / "libs_path"
        fake_root = tmp / "repo"
        env_klt = _write_klt_stub(tmp / "env-bin" / "klt", libs_env, VERSION_ENV)
        venv_klt = _write_klt_stub(
            fake_root / ".venv" / "bin" / "klt", libs_venv, VERSION_VENV
        )
        path_klt = _write_klt_stub(tmp / "path-bin" / "klt", libs_path, VERSION_PATH)
        stub_path = {"PATH": f"{tmp / 'path-bin'}{os.pathsep}{os.environ['PATH']}"}

        # $KLT wins over both an existing .venv klt and one on $PATH.
        prim, cells, ver = _resolve(str(env_klt), fake_root, stub_path)
        check(
            "$KLT stub's version is reported",
            ver == VERSION_ENV,
            f"got {ver!r}",
        )
        check(
            "$KLT stub's libs_ref supplies the verilog paths",
            prim == libs_env / "sky130_fd_sc_hd" / "verilog" / "primitives.v"
            and cells == libs_env / "sky130_fd_sc_hd" / "verilog" / "sky130_fd_sc_hd.v",
            f"got {prim}, {cells}",
        )

        # Empty $KLT is treated as unset: .venv leg still wins over $PATH.
        prim, cells, ver = _resolve("", fake_root, stub_path)
        check(
            'KLT="" is treated as unset (.venv leg used)',
            ver == VERSION_VENV,
            f"got {ver!r}",
        )

        # $KLT unset, no .venv: `klt` on $PATH -- unchanged behaviour.
        prim, cells, ver = _resolve(None, tmp / "repo-no-venv", stub_path)
        check(
            "unset KLT with no .venv falls to $PATH",
            ver == VERSION_PATH,
            f"got {ver!r}",
        )

        # $KLT unset, .venv present: .venv wins over $PATH -- unchanged
        # behaviour.
        prim, cells, ver = _resolve(None, fake_root, stub_path)
        check(
            "unset KLT with .venv prefers .venv over $PATH",
            ver == VERSION_VENV,
            f"got {ver!r}",
        )

        # A $KLT pointing at a nonexistent path must fail loudly even though
        # a working `klt` is available on $PATH -- no silent fallback.
        try:
            _resolve(str(tmp / "no-such" / "klt"), fake_root, stub_path)
        except (OSError, subprocess.SubprocessError):
            check(
                "nonexistent $KLT raises instead of falling back",
                True,
            )
        else:
            check(
                "nonexistent $KLT raises instead of falling back",
                False,
                "resolved and ran without raising",
            )

    print()
    if failures:
        print(f"{len(failures)} check(s) FAILED")
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
