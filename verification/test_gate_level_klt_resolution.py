#!/usr/bin/env python3
"""Self-test for `gate_level_cross_check.py`'s `klt` usage (issue #382).

The `$KLT` / interpreter-adjacent / `$PATH` precedence legs this file used
to carry now live with the one implementation they test,
`_repo_utils.resolve_klt()` (see `verification/test_repo_utils.py`; issue
#382 consolidated the two drivers' line-identical private copies). What
stays here is the part specific to this script: `resolve_pdk_verilog()`
must drive the `klt pdk find` query through whatever binary the shared
resolver returns, and derive the cell-model verilog paths from its JSON
answer.

The leg is exercised by a stub `klt` whose `pdk find` output carries a
distinguishable sentinel `version` and `libs_ref`, reached via `$KLT` --
the documented pin-check recipe (`docs/environment.md`'s `KLT` row) --
so the test also pins the exact `pdk find` subcommand shape. Any other
invocation is a hard stub error, and no real `klt` is ever invoked.

Usage: python3 verification/test_gate_level_klt_resolution.py
Exit codes: 0 all pass, 1 otherwise.
"""

from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
GATE_LEVEL_DIR = SCRIPT_DIR / "gate-level"
sys.path.insert(0, str(GATE_LEVEL_DIR))

import gate_level_cross_check as gl  # noqa: E402

VERSION_STUB = "9.9-pin-stub"

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


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="klt-resolution-") as td:
        tmp = Path(td)
        libs_stub = tmp / "libs_stub"
        stub = _write_klt_stub(tmp / "pin-bin" / "klt", libs_stub, VERSION_STUB)

        saved_env = dict(os.environ)
        try:
            # The documented pin-check recipe: `$KLT` names the binary.
            os.environ["KLT"] = str(stub)
            resolved = gl.resolve_klt()
            check(
                "the shared resolver returns the $KLT pin verbatim",
                resolved == str(stub),
                f"got {resolved!r}",
            )
            prim, cells, ver = gl.resolve_pdk_verilog(resolved)
        finally:
            os.environ.clear()
            os.environ.update(saved_env)

        check(
            "resolve_pdk_verilog drives the pinned stub (sentinel version)",
            ver == VERSION_STUB,
            f"got {ver!r}",
        )
        check(
            "the stub's libs_ref supplies the verilog paths",
            prim == libs_stub / "sky130_fd_sc_hd" / "verilog" / "primitives.v"
            and cells == libs_stub / "sky130_fd_sc_hd" / "verilog" / "sky130_fd_sc_hd.v",
            f"got {prim}, {cells}",
        )

    print()
    if failures:
        print(f"{len(failures)} check(s) FAILED")
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
