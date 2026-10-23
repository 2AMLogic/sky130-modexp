#!/usr/bin/env python3
"""Check that `scripts/setup-env.sh`'s pin constants match `docs/environment.md`.

`scripts/setup-env.sh` provisions the environment from a block of pin
constants (`KLT_REV`, `CIEL_SKY130_VERSION`, `YOWASP_YOSYS_VERSION`,
`YOWASP_YOSYS_WASM_SHA256`, ...). `docs/environment.md`'s "## Pinned
versions" table restates those values for readers. The table is part of the
pin's mechanism, not a description of it: a reader who trusts the table
while the script provisions something else is running an unidentified tool
while believing the environment is pinned (issue #141). This checker makes
the two copies agree (issue #148).

Checks, all pure text -- no network, no PDK, no tools:

1. The pin block in `scripts/setup-env.sh` (between the
   `# --- pinned versions` marker and the next `# ----` rule) exists and
   defines every name in `REQUIRED_PINS`. Renaming or deleting one fails
   rather than silently shrinking what is checked.
2. Every constant in that block appears, as a whole token, in the
   "## Pinned versions" table. A pin bumped in the script but not the doc
   fails here.
3. Every git-revision / sha256-shaped hex token, and every
   `yowasp-yosys==<version>` spec, in that table equals some pin constant.
   A pin bumped in the doc but not the script -- or bumped in one table row
   but left stale in another -- fails here. Rows whose component is pinned
   somewhere other than `scripts/setup-env.sh` (`EXTERNALLY_PINNED_ROWS`)
   are exempt from this direction only.
4. The signoff-report-leg `klayout-tools` row is a separate pin from
   `KLT_REV`. Its SHA must equal `SIGNOFF_KLT_SHA` in
   `verification/signoff/run-signoff.sh`, and every
   `klayout-tools @ git+...@<sha>` install in `.github/workflows/ci.yml`
   must name `SIGNOFF_KLT_SHA` or `KLT_REV`, with `SIGNOFF_KLT_SHA` present
   (the three-way sync, issue #218). The row is exempt from check 3 only for
   that SHA; the evidence-leg row stays checked against `KLT_REV`.

Deliberately OUT of scope: frozen evidence artifacts that restate a pin,
e.g. the `rerun-pinned-synthesis.sh` scripts under
`verification/records/*/artifacts/`. An artifact is frozen at the build it
measured; after a re-pin it SHOULD diverge from the live pin, and the
append-only record convention forbids editing it anyway. Do not extend this
checker to force those copies equal to the live pin -- that would make every
legitimate re-pin a lint failure. The rationale prose under the table
(which names previous pins on purpose) is out of scope for the same reason.

Usage:
    python3 verification/check_pins.py [--repo-root DIR]
`--repo-root` defaults to $REPO_ROOT, else `git rev-parse --show-toplevel`
(run from this file's directory), so the same bytes work from any depth.
Exit codes: 0 consistent, 1 at least one mismatch, 2 a file or section is
missing / unparseable.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path


def default_repo_root() -> Path | None:
    """$REPO_ROOT, else this file's `git rev-parse --show-toplevel`; None if
    neither resolves. Independent of how deep this file sits in the tree."""
    if os.environ.get("REPO_ROOT"):
        return Path(os.environ["REPO_ROOT"])
    git = subprocess.run(
        ["git", "-C", str(Path(__file__).resolve().parent), "rev-parse", "--show-toplevel"],
        capture_output=True, text=True,
    )
    return Path(git.stdout.strip()) if git.returncode == 0 else None


SCRIPT_REL = Path("scripts/setup-env.sh")
DOC_REL = Path("docs/environment.md")
SIGNOFF_REL = Path("verification/signoff/run-signoff.sh")
CI_REL = Path(".github/workflows/ci.yml")
SIGNOFF_ROW_MARK = "signoff-report leg"
SIGNOFF_ASSIGN = re.compile(r'^SIGNOFF_KLT_SHA="([0-9a-f]{40})"', re.MULTILINE)
CI_KLT_INSTALL = re.compile(r"klayout-tools @ git\+\S*?@([0-9a-f]{40})")

REQUIRED_PINS = (
    "KLT_REV",
    "CIEL_VERSION",
    "CIEL_SKY130_VERSION",
    "YOWASP_YOSYS_VERSION",
    "YOWASP_YOSYS_WASM_SHA256",
)

# Table rows (matched by a prefix of the first cell) whose hex tokens are
# pinned outside scripts/setup-env.sh, so check 3 does not apply to them.
EXTERNALLY_PINNED_ROWS = (
    # Pinned by the committed byte-identical copy of the checklist; see
    # verification/signoff/README.md.
    "T1 tier checklist",
)

PIN_BLOCK_START = re.compile(r"^#\s*---\s*pinned versions\b", re.IGNORECASE)
PIN_BLOCK_END = re.compile(r"^#\s*-{4,}\s*$")
ASSIGNMENT = re.compile(r'^([A-Z][A-Z0-9_]*)="([^"$`\\]*)"\s*(?:#.*)?$')
TABLE_HEADING = re.compile(r"^##\s+Pinned versions\s*$")
HEX_TOKEN = re.compile(r"(?<![0-9A-Za-z])(?:[0-9a-f]{64}|[0-9a-f]{40})(?![0-9A-Za-z])")
YOWASP_SPEC = re.compile(r"yowasp-yosys==([0-9A-Za-z.+_-]*[0-9A-Za-z])")


class ParseError(Exception):
    pass


def parse_pin_block(text: str) -> dict[str, str]:
    lines = text.splitlines()
    start = next((i for i, ln in enumerate(lines) if PIN_BLOCK_START.match(ln)), None)
    if start is None:
        raise ParseError(f"{SCRIPT_REL}: no '# --- pinned versions' marker")
    end = next(
        (i for i in range(start + 1, len(lines)) if PIN_BLOCK_END.match(lines[i])),
        None,
    )
    if end is None:
        raise ParseError(f"{SCRIPT_REL}: pinned-versions block has no closing '# ----' rule")
    pins: dict[str, str] = {}
    for ln in lines[start + 1 : end]:
        m = ASSIGNMENT.match(ln.strip())
        if m:
            pins[m.group(1)] = m.group(2)
    return pins


def parse_pinned_table(text: str) -> list[str]:
    lines = text.splitlines()
    heading = next((i for i, ln in enumerate(lines) if TABLE_HEADING.match(ln)), None)
    if heading is None:
        raise ParseError(f"{DOC_REL}: no '## Pinned versions' section")
    rows: list[str] = []
    for ln in lines[heading + 1 :]:
        if ln.startswith("|"):
            rows.append(ln)
        elif rows or ln.startswith("#"):
            break
    # Drop the header row and the |---| separator.
    body = [r for r in rows[1:] if not re.match(r"^\|\s*:?-{3,}", r)]
    if not body:
        raise ParseError(f"{DOC_REL}: '## Pinned versions' has no table rows")
    return body


def _first_cell(row: str) -> str:
    return row.strip().strip("|").split("|", 1)[0].strip().strip("`")


def _contains_token(haystack: str, value: str) -> bool:
    pattern = (
        r"(?<![0-9A-Za-z_.-])"
        + re.escape(value)
        + r"(?![0-9A-Za-z_-])(?!\.[0-9A-Za-z])"
    )
    return re.search(pattern, haystack) is not None


def check(repo_root: Path) -> tuple[list[str], list[str]]:
    """Return (errors, notes). Raises ParseError on structural problems."""
    script_path = repo_root / SCRIPT_REL
    doc_path = repo_root / DOC_REL
    signoff_path = repo_root / SIGNOFF_REL
    ci_path = repo_root / CI_REL
    for p in (script_path, doc_path, signoff_path, ci_path):
        if not p.is_file():
            raise ParseError(f"missing file: {p.relative_to(repo_root)}")

    pins = parse_pin_block(script_path.read_text(encoding="utf-8"))
    rows = parse_pinned_table(doc_path.read_text(encoding="utf-8"))
    table = "\n".join(rows)
    errors: list[str] = []
    notes: list[str] = []

    for name in REQUIRED_PINS:
        if name not in pins:
            errors.append(f"{SCRIPT_REL}: required pin {name} is not defined in the pinned-versions block")

    for name, value in pins.items():
        if not value:
            errors.append(f"{SCRIPT_REL}: pin {name} is empty")
        elif not _contains_token(table, value):
            errors.append(
                f"{name}={value!r} (from {SCRIPT_REL}) does not appear in "
                f"{DOC_REL}'s '## Pinned versions' table"
            )
        else:
            notes.append(f"ok: {name} = {value}")

    m = SIGNOFF_ASSIGN.search(signoff_path.read_text(encoding="utf-8"))
    if not m:
        raise ParseError(f"{SIGNOFF_REL}: no SIGNOFF_KLT_SHA=\"<40 hex>\" assignment")
    signoff_sha = m.group(1)
    signoff_rows = [r for r in rows if SIGNOFF_ROW_MARK in _first_cell(r)]
    if len(signoff_rows) != 1:
        errors.append(
            f"{DOC_REL}: expected exactly one '{SIGNOFF_ROW_MARK}' klayout-tools row, found {len(signoff_rows)}"
        )
    for row in signoff_rows:
        toks = set(HEX_TOKEN.findall(row))
        if toks != {signoff_sha}:
            errors.append(
                f"{DOC_REL}: signoff-leg row names {sorted(toks)}, but {SIGNOFF_REL} "
                f"pins SIGNOFF_KLT_SHA={signoff_sha}"
            )
        else:
            notes.append(f"ok: SIGNOFF_KLT_SHA = {signoff_sha}")
    ci_shas = CI_KLT_INSTALL.findall(ci_path.read_text(encoding="utf-8"))
    if signoff_sha not in ci_shas:
        errors.append(f"{CI_REL}: no klayout-tools install at SIGNOFF_KLT_SHA={signoff_sha} (from {SIGNOFF_REL})")
    for sha in sorted(set(ci_shas)):
        if sha != signoff_sha and sha != pins.get("KLT_REV"):
            errors.append(
                f"{CI_REL}: klayout-tools install at {sha} matches neither SIGNOFF_KLT_SHA nor KLT_REV (stale or unsynced pin)"
            )

    pin_values = set(pins.values())
    for row in rows:
        component = _first_cell(row)
        if component.startswith(EXTERNALLY_PINNED_ROWS) or SIGNOFF_ROW_MARK in component:
            continue
        for tok in sorted(set(HEX_TOKEN.findall(row))):
            if tok not in pin_values:
                errors.append(
                    f"{DOC_REL}: row '{component}' names {tok}, which matches no "
                    f"pin constant in {SCRIPT_REL} (stale or unsynced pin)"
                )
        for ver in sorted(set(YOWASP_SPEC.findall(row))):
            if ver != pins.get("YOWASP_YOSYS_VERSION"):
                errors.append(
                    f"{DOC_REL}: row '{component}' names yowasp-yosys=={ver}, but "
                    f"{SCRIPT_REL} pins YOWASP_YOSYS_VERSION="
                    f"{pins.get('YOWASP_YOSYS_VERSION')!r}"
                )
    return errors, notes


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    default_root = default_repo_root()
    ap.add_argument("--repo-root", type=Path, default=default_root, required=default_root is None,
                    help="default: $REPO_ROOT, else `git rev-parse --show-toplevel`")
    args = ap.parse_args(argv)
    try:
        errors, notes = check(args.repo_root.resolve())
    except ParseError as exc:
        print(f"check_pins: ERROR: {exc}", file=sys.stderr)
        return 2
    for n in notes:
        print(f"check_pins: {n}")
    if errors:
        for e in errors:
            print(f"check_pins: FAIL: {e}", file=sys.stderr)
        return 1
    print(f"check_pins: PASS ({len(notes)} pins consistent between {SCRIPT_REL} and {DOC_REL})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
