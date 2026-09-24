#!/usr/bin/env python3
"""Self-test for `verification/check_pins.py`.

A checker that silently stops catching a violation is worse than no checker
(`verification/test_check_records.py`'s own words), so each drift class
`check_pins.py` claims to catch gets an executable negative case here, plus
positive controls that a consistent re-pin passes and that the deliberately
out-of-scope copies (frozen artifacts, rationale prose, externally pinned
rows) do not trip it.

Method: copy the *real* `scripts/setup-env.sh` and `docs/environment.md`
into a temp fixture root, apply one mutation, and run the real checker as a
subprocess with `--repo-root` pointing at the fixture -- exactly the entry
point `npm run lint` uses. Starting from the real files means the baseline
positive control is also a check of the committed repo.

Usage:
    python3 verification/test_check_pins.py
Exit codes: 0 all cases behave as specified, 1 at least one did not.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Callable

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
CHECKER = SCRIPT_DIR / "check_pins.py"
SCRIPT_REL = Path("scripts/setup-env.sh")
DOC_REL = Path("docs/environment.md")


def _pin(name: str) -> str:
    text = (REPO_ROOT / SCRIPT_REL).read_text(encoding="utf-8")
    m = re.search(rf'^{name}="([^"]*)"', text, re.MULTILINE)
    if not m:
        raise RuntimeError(f"{SCRIPT_REL} has no {name}=; self-test fixture cannot be built")
    return m.group(1)


KLT_REV = _pin("KLT_REV")
VOLARE = _pin("VOLARE_SKY130_VERSION")
YW_VER = _pin("YOWASP_YOSYS_VERSION")
YW_SHA = _pin("YOWASP_YOSYS_WASM_SHA256")
FAKE_REV = "0123456789abcdef0123456789abcdef01234567"
FAKE_SHA = "f" * 64


def _table_span(doc: str) -> tuple[int, int]:
    start = doc.index("## Pinned versions")
    table = doc.index("\n|", start)
    end = doc.index("\n\n", table)
    return start, end


def _edit_table(doc: str, fn: Callable[[str], str]) -> str:
    s, e = _table_span(doc)
    return doc[:s] + fn(doc[s:e]) + doc[e:]


def _edit_row(doc: str, row_prefix: str, fn: Callable[[str], str]) -> str:
    def per_table(table: str) -> str:
        out = []
        for ln in table.split("\n"):
            out.append(fn(ln) if ln.startswith(row_prefix) else ln)
        return "\n".join(out)

    return _edit_table(doc, per_table)


def _set_script(script: str, name: str, value: str) -> str:
    return re.sub(rf'^{name}="[^"]*"', f'{name}="{value}"', script, count=1, flags=re.MULTILINE)


Mutation = Callable[[Path], None]


def _mut_script(fn: Callable[[str], str]) -> Mutation:
    def apply(root: Path) -> None:
        p = root / SCRIPT_REL
        p.write_text(fn(p.read_text(encoding="utf-8")), encoding="utf-8")

    return apply


def _mut_doc(fn: Callable[[str], str]) -> Mutation:
    def apply(root: Path) -> None:
        p = root / DOC_REL
        p.write_text(fn(p.read_text(encoding="utf-8")), encoding="utf-8")

    return apply


def _both(*muts: Mutation) -> Mutation:
    def apply(root: Path) -> None:
        for m in muts:
            m(root)

    return apply


def _frozen_artifact(root: Path) -> None:
    art = root / "verification/records/x/artifacts/20260101-000000-abc1234"
    art.mkdir(parents=True)
    (art / "rerun-pinned-synthesis.sh").write_text(
        f'EXPECTED_WASM_SHA256="{YW_SHA}"\nYOWASP_YOSYS_VERSION="{YW_VER}"\n',
        encoding="utf-8",
    )


# (name, mutation, expected exit code, substring expected in output or None)
CASES: list[tuple[str, Mutation, int, str | None]] = [
    ("baseline: committed files are consistent", lambda r: None, 0, None),
    (
        "KLT_REV bumped in script only",
        _mut_script(lambda s: _set_script(s, "KLT_REV", FAKE_REV)),
        1,
        "KLT_REV=",
    ),
    (
        "VOLARE_SKY130_VERSION bumped in doc table only",
        _mut_doc(lambda d: _edit_table(d, lambda t: t.replace(VOLARE, FAKE_REV))),
        1,
        "VOLARE_SKY130_VERSION=",
    ),
    (
        "KLT_REV left stale in one table row (signoff-report leg)",
        _mut_doc(
            lambda d: _edit_row(d, "| `klayout-tools` (`klt`, signoff", lambda ln: ln.replace(KLT_REV, FAKE_REV))
        ),
        1,
        "stale or unsynced pin",
    ),
    (
        "YOWASP_YOSYS_VERSION bumped in script only",
        _mut_script(lambda s: _set_script(s, "YOWASP_YOSYS_VERSION", "0.69.0.0.post1")),
        1,
        "YOWASP_YOSYS_VERSION=",
    ),
    (
        "yowasp-yosys spec stale in one table cell only",
        _mut_doc(
            lambda d: _edit_table(
                d,
                lambda t: t.replace(f'pip install "yowasp-yosys=={YW_VER}"', 'pip install "yowasp-yosys==0.67.0.0.post9"'),
            )
        ),
        1,
        "yowasp-yosys==0.67.0.0.post9",
    ),
    (
        "YOWASP_YOSYS_WASM_SHA256 changed in script only",
        _mut_script(lambda s: _set_script(s, "YOWASP_YOSYS_WASM_SHA256", FAKE_SHA)),
        1,
        "YOWASP_YOSYS_WASM_SHA256=",
    ),
    (
        "YOWASP_YOSYS_WASM_SHA256 changed in doc only",
        _mut_doc(lambda d: _edit_table(d, lambda t: t.replace(YW_SHA, FAKE_SHA))),
        1,
        "stale or unsynced pin",
    ),
    (
        "script value is a prefix of the doc value (token boundary)",
        _mut_script(lambda s: _set_script(s, "YOWASP_YOSYS_VERSION", YW_VER[:-1])),
        1,
        "YOWASP_YOSYS_VERSION=",
    ),
    (
        "required pin removed from the script's pin block",
        _mut_script(lambda s: re.sub(r'^KLT_REV="[^"]*"\n', "", s, flags=re.MULTILINE)),
        1,
        "required pin KLT_REV",
    ),
    (
        "pin block marker missing from script",
        _mut_script(lambda s: s.replace("# --- pinned versions", "# --- versions")),
        2,
        "pinned versions",
    ),
    (
        "'## Pinned versions' section missing from doc",
        _mut_doc(lambda d: d.replace("## Pinned versions", "## Versions")),
        2,
        "Pinned versions",
    ),
    (
        "positive: consistent re-pin of every hash pin passes",
        _both(
            _mut_script(lambda s: _set_script(_set_script(s, "KLT_REV", FAKE_REV), "YOWASP_YOSYS_WASM_SHA256", FAKE_SHA)),
            _mut_doc(lambda d: _edit_table(d, lambda t: t.replace(KLT_REV, FAKE_REV).replace(YW_SHA, FAKE_SHA))),
        ),
        0,
        None,
    ),
    (
        "positive: externally pinned row (T1 tier checklist) is exempt from the reverse check",
        _mut_doc(
            lambda d: _edit_row(
                d, "| T1 tier checklist", lambda ln: re.sub(r"[0-9a-f]{40}", "a" * 40, ln)
            )
        ),
        0,
        None,
    ),
    (
        "positive: rationale prose naming an old pin is out of scope",
        _mut_doc(lambda d: d.replace("**Pin rationale", f"Old pin `{'b' * 40}`.\n\n**Pin rationale", 1)),
        0,
        None,
    ),
    (
        "positive: frozen artifact restating a pin may diverge after a re-pin",
        _both(
            _frozen_artifact,
            _mut_script(lambda s: _set_script(s, "YOWASP_YOSYS_WASM_SHA256", FAKE_SHA)),
            _mut_doc(lambda d: _edit_table(d, lambda t: t.replace(YW_SHA, FAKE_SHA))),
        ),
        0,
        None,
    ),
]


def run_case(mutation: Mutation) -> tuple[int, str]:
    with tempfile.TemporaryDirectory(prefix="check-pins-selftest-") as tmp:
        root = Path(tmp)
        for rel in (SCRIPT_REL, DOC_REL):
            (root / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPO_ROOT / rel, root / rel)
        mutation(root)
        res = subprocess.run(
            [sys.executable, str(CHECKER), "--repo-root", str(root)],
            capture_output=True,
            text=True,
        )
        return res.returncode, res.stdout + res.stderr


def main() -> int:
    failures = 0
    for name, mutation, want_rc, want_text in CASES:
        rc, out = run_case(mutation)
        ok = rc == want_rc and (want_text is None or want_text in out)
        print(f"{'PASS' if ok else 'FAIL'}: {name} (exit {rc}, want {want_rc})")
        if not ok:
            failures += 1
            print("  checker output:\n    " + out.strip().replace("\n", "\n    "))
    total = len(CASES)
    print(f"test_check_pins: {total - failures}/{total} cases behave as specified")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
