#!/usr/bin/env python3
"""Evidence-record linter for `verification/records/`.

This is the enforcement half of the convention documented in
`verification/README.md` -- **that document is authoritative**; if this
script and the README ever disagree, fix the script.

Zero dependencies beyond the Python 3 standard library and `git`. Reads
tracked files only (`git ls-files`), so untracked scratch runs are never
linted.

Checks, per record `verification/records/<experiment>/records/<record-id>.md`:

1. **Filename / Record ID grammar** -- the filename stem and the metadata
   block's `record_id` must both match `YYYYMMDD-HHMMSS-<7-40 hex chars>`
   and must agree with each other.
2. **Required fields present** -- the `<!-- record-meta ... -->` JSON block
   must be valid JSON with the required keys (see `REQUIRED_META_KEYS`), and
   every field in `REQUIRED_PROSE_FIELDS` must appear as a non-empty
   top-level markdown bullet (`- **Field**: <non-empty value>`).
3. **Supersedes integrity** -- `supersedes` is `null`/`"none"`, a single
   record id (legacy scalar spelling), or a list of record ids (one fresh
   record clearing several live ancestors). Every id must name a record
   that exists in the same experiment directory, must not repeat within
   the list, and must not be the record itself. The **Supersedes** prose
   bullet must name the same set of ids as the metadata (free prose around
   the ids is fine; an id the bullet explicitly says it does *not*
   supersede is commentary, not a claim). Bullet ids are read from the
   first line plus continuation lines only while the list visibly wraps
   (previous line ends in `,` `;` `&` `and` `or`); ids on an unseparated
   continuation line are treated as explanatory prose and are not
   cross-checked. The append-only rule requires this: the frozen records
   `drc-lvs/20260817-002327-4dd3bfa` and `drc-lvs/20260817-002415-4dd3bfa`
   name other record ids in continuation prose.
4. **Provenance hash freshness** -- for every record that is *not*
   superseded by another record (a "live" record), every
   `provenance.inputs[].content_hash` is recomputed from the working tree
   and must match. A live record whose cited source has since changed is a
   stale record -- exactly the case this check exists to catch. Superseded
   records are exempt (they are frozen history, not a claim about current
   sources).
5. **Append-only** -- every path under `verification/records/` must be
   either untracked-before (a pure addition) or unchanged, relative to the
   merge-base with `origin/main` (or `--base-ref`). Any modification,
   rename, or deletion fails. If the base ref cannot be resolved, this
   check prints SKIP unless `--require-append-only` is given.

Usage:
    python3 verification/check_records.py
    python3 verification/check_records.py --require-append-only
    python3 verification/check_records.py --base-ref origin/main

Exit codes: 0 pass, 1 a check failed.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

from _repo_utils import REPO_ROOT, run_git, sha256_of

RECORDS_ROOT = REPO_ROOT / "verification" / "records"

def normalize_supersedes(value) -> list[str]:
    """Return the ids a record supersedes as a list.

    `None`/`"none"` -> `[]`, `str` -> `[str]`, `list` -> itself (an empty list
    means none). Anything else, or a non-string/empty element, raises
    `ValueError` so callers report a lint error rather than crash.
    """
    if value is None or value == "none":
        return []
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        for item in value:
            if not isinstance(item, str) or not item.strip():
                raise ValueError(f"list elements must be non-empty strings, got {item!r}")
            if item == "none":
                raise ValueError("`none` is not valid inside a supersedes list")
        return list(value)
    raise ValueError(
        f"must be null, \"none\", a record id, or a list of record ids, "
        f"got {type(value).__name__}"
    )


RECORD_ID_RE = re.compile(r"^\d{8}-\d{6}-[0-9a-f]{7,40}$")

# Record ids mentioned anywhere in a **Supersedes** bullet's value, and the
# phrasing ("does **not** supersede", "not superseded by", ...) that marks a
# mention as commentary about a record this record explicitly does NOT
# retire. Committed records do name non-targets this way (frozen history,
# append-only), so the bullet-vs-meta check exempts ids that appear after
# such a cue instead of failing on them.
_SUPERSEDES_BULLET_ID_RE = re.compile(r"\b\d{8}-\d{6}-[0-9a-f]{7,40}\b")
_NEGATED_SUPERSEDE_RE = re.compile(r"not\*{0,2}\s*supersede", re.IGNORECASE)
_LIST_WRAP_RE = re.compile(r"(?:[,;&]|\b(?:and|or))\s*$", re.IGNORECASE)
_SENTENCE_BREAK_RE = re.compile(r"[.;]\s|[.;]$")

REQUIRED_META_KEYS = (
    "record_id",
    "experiment",
    "supersedes",
    "git_revision",
    "provenance",
)
REQUIRED_PROVENANCE_KEYS = ("klt_version", "pdk", "deck", "inputs")

REQUIRED_PROSE_FIELDS = (
    "Record ID",
    "Claim",
    "Design provenance",
    "Run configuration",
    "Statistical convention",
    "Result",
    "klt provenance",
    "Links",
    "Timestamp / author",
    "Supersedes",
)

_PLACEHOLDER_VALUES = {"", "tbd", "todo", "fixme", "(fill in)", "(fill me in)"}


class LintError(Exception):
    pass


def _tracked_record_files() -> list[Path]:
    out = run_git("ls-files", "--", "verification/records/**/records/*.md")
    return sorted(REPO_ROOT / line for line in out.splitlines() if line.strip())


def _extract_meta_block(text: str, path: Path) -> dict:
    match = re.search(r"<!--\s*record-meta\s*(.*?)-->", text, re.DOTALL)
    if not match:
        raise LintError(f"{path}: missing `<!-- record-meta ... -->` block")
    try:
        return json.loads(match.group(1))
    except json.JSONDecodeError as exc:
        raise LintError(f"{path}: record-meta block is not valid JSON: {exc}") from exc


def _extract_prose_fields(text: str) -> dict:
    """Map required-field name -> value of its top-level bullet
    (`- **Field**: value`). A field is "present" if either the bullet line
    itself has content after the colon, or -- for fields whose detail lives
    in an indented sub-list (e.g. `Result`, `Links`) -- at least one
    indented, non-blank line follows before the next top-level bullet or a
    blank line breaks the block."""
    lines = text.splitlines()
    fields: dict[str, str] = {}
    i = 0
    while i < len(lines):
        stripped = lines[i].strip()
        m = re.match(r"^-\s+\*\*(.+?)\*\*:\s*(.*)$", stripped)
        if not m:
            i += 1
            continue
        name = m.group(1).strip()
        value = m.group(2).strip()
        j = i + 1
        sub_content = []
        while j < len(lines):
            nxt = lines[j]
            if not nxt.strip():
                break  # blank line ends this field's block
            if re.match(r"^-\s+\*\*.+?\*\*:", nxt.strip()) and not nxt.startswith((" ", "\t")):
                break  # next top-level bullet
            if nxt.startswith((" ", "\t")):
                sub_content.append(nxt.strip())
                j += 1
                continue
            break
        if not value and sub_content:
            value = " ".join(sub_content)
        elif value and sub_content:
            # The bullet line has text: continuation lines still belong to
            # the value while a list is visibly wrapping (the previous line
            # ends in a list separator, e.g. a wrapped `Supersedes` id
            # list). Once a line ends without one, what follows is
            # explanatory prose and stays out of the value.
            parts = [value]
            for line in sub_content:
                if not _LIST_WRAP_RE.search(parts[-1]):
                    break
                parts.append(line)
            value = " ".join(parts)
        fields[name] = value
        i = j if j > i + 1 else i + 1
    return fields


def check_supersedes_bullet(path: Path, bullet: str | None, meta_ids: list[str]) -> list[str]:
    """The **Supersedes** bullet vs the record-meta `supersedes`.

    The bullet is the human-readable half of the supersedes chain and the
    meta is the machine-readable half (and the half the freshness exemption
    reads), so the two must name the same records. Ids are compared as a
    *set*: the minter writes `A, B` but hand-written bullets may carry free
    prose around the ids (`` `A` (freshness -- rerun) ...``), and the ids
    may sit on the indented continuation lines `_extract_prose_fields`
    joins. An id mentioned *after* a negation cue in the same sentence ("... does **not**
    supersede `<id>`") names a record this record explicitly does not
    retire and is exempt from the comparison; the exemption is scoped per occurrence, so
    an id affirmed elsewhere in the bullet is still claimed. Returns a list of lint
    errors, empty when the halves agree.
    """
    if bullet is None or bullet.strip().lower() in _PLACEHOLDER_VALUES:
        return []  # presence/placeholder already reported by the required-field check
    cues = list(_NEGATED_SUPERSEDE_RE.finditer(bullet))

    def negated(id_start: int) -> bool:
        # An id is negated only if a cue precedes it within the same
        # sentence; a sentence break re-opens affirmative claims.
        prior = [c for c in cues if c.end() <= id_start]
        if not prior:
            return False
        return _SENTENCE_BREAK_RE.search(bullet, prior[-1].end(), id_start) is None

    ids = list(_SUPERSEDES_BULLET_ID_RE.finditer(bullet))
    # Exemption is per occurrence: an id affirmed in one sentence stays
    # claimed even if a later sentence negates (or merely mentions) it, and
    # an affirmed id is not retracted by a separate negated mention.
    claimed = {m.group(0) for m in ids if not negated(m.start())}
    meta_set = set(meta_ids)
    errors = []
    missing = sorted(meta_set - claimed)
    if missing:
        errors.append(
            f"{path}: **Supersedes** bullet does not name meta supersedes "
            f"id(s) {', '.join(missing)} -- bullet and record-meta must "
            f"list the same records"
        )
    extra = sorted(claimed - meta_set)
    if extra:
        errors.append(
            f"{path}: **Supersedes** bullet names {', '.join(extra)}, which "
            f"the record-meta `supersedes` does not -- bullet and "
            f"record-meta must list the same records"
        )
    return errors


def lint_record(path: Path, all_record_ids_by_experiment: dict) -> list[str]:
    errors = []
    text = path.read_text(encoding="utf-8")
    experiment = path.parent.parent.name  # .../<experiment>/records/<id>.md
    stem = path.stem

    if not RECORD_ID_RE.match(stem):
        errors.append(f"{path}: filename `{path.name}` is not a valid record-id")

    try:
        meta = _extract_meta_block(text, path)
    except LintError as exc:
        errors.append(str(exc))
        return errors  # nothing further to check without metadata

    for key in REQUIRED_META_KEYS:
        if key not in meta:
            errors.append(f"{path}: record-meta missing required key `{key}`")

    if meta.get("record_id") != stem:
        errors.append(
            f"{path}: record-meta record_id `{meta.get('record_id')}` "
            f"disagrees with filename `{stem}`"
        )

    provenance = meta.get("provenance", {})
    if not isinstance(provenance, dict):
        errors.append(f"{path}: record-meta `provenance` must be an object")
        provenance = {}
    for key in REQUIRED_PROVENANCE_KEYS:
        if key not in provenance:
            errors.append(f"{path}: record-meta.provenance missing required key `{key}`")

    inputs = provenance.get("inputs")
    if not inputs:
        errors.append(f"{path}: record-meta.provenance.inputs is missing or empty")
        inputs = []
    for item in inputs:
        if not isinstance(item, dict) or "path" not in item or "content_hash" not in item:
            errors.append(
                f"{path}: record-meta.provenance.inputs entries need `path` and `content_hash`"
            )

    prose = _extract_prose_fields(text)
    for field in REQUIRED_PROSE_FIELDS:
        value = prose.get(field)
        if value is None:
            errors.append(f"{path}: missing required field bullet `- **{field}**:`")
        elif value.strip().lower() in _PLACEHOLDER_VALUES:
            errors.append(f"{path}: required field `{field}` is empty/placeholder")

    try:
        supersedes = normalize_supersedes(meta.get("supersedes"))
    except ValueError as exc:
        errors.append(f"{path}: invalid `supersedes`: {exc}")
        supersedes = []
    else:
        known_ids = all_record_ids_by_experiment.get(experiment, set())
        seen: set[str] = set()
        for target in supersedes:
            if target in seen:
                errors.append(f"{path}: supersedes lists `{target}` more than once")
            seen.add(target)
            if target == path.stem:
                errors.append(f"{path}: supersedes itself (`{target}`)")
            elif target not in known_ids:
                errors.append(
                    f"{path}: supersedes `{target}`, which has no record "
                    f"in `{experiment}/records/`"
                )
        errors.extend(check_supersedes_bullet(path, prose.get("Supersedes"), supersedes))

    return errors


def check_hash_freshness(path: Path, superseded_ids: set) -> list[str]:
    errors = []
    text = path.read_text(encoding="utf-8")
    try:
        meta = _extract_meta_block(text, path)
    except LintError:
        return errors  # already reported by lint_record

    record_id = meta.get("record_id")
    if record_id in superseded_ids:
        return errors  # frozen history, exempt from freshness

    for item in meta.get("provenance", {}).get("inputs", []) or []:
        rel_path = item.get("path")
        recorded_hash = item.get("content_hash")
        if not rel_path or not recorded_hash:
            continue
        src = REPO_ROOT / rel_path
        if not src.exists():
            errors.append(
                f"{path}: input `{rel_path}` no longer exists in the working tree"
            )
            continue
        current_hash = sha256_of(src)
        if current_hash != recorded_hash:
            errors.append(
                f"{path}: provenance hash for `{rel_path}` is stale -- "
                f"recorded {recorded_hash}, current {current_hash} "
                f"(source changed since this record; mint a new record)"
            )
    return errors


def check_append_only(base_ref: str, require: bool) -> list[str]:
    try:
        merge_base = run_git("merge-base", base_ref, "HEAD")
    except subprocess.CalledProcessError as exc:
        detail = (exc.stderr or str(exc)).strip()
        msg = f"append-only check: could not resolve base ref `{base_ref}` ({detail})"
        if require:
            return [msg]
        print(f"SKIP: {msg}")
        return []

    try:
        diff = run_git(
            "diff", "--name-status", merge_base, "HEAD", "--", "verification/records/"
        )
    except subprocess.CalledProcessError as exc:
        detail = (exc.stderr or str(exc)).strip()
        msg = f"append-only check: `git diff` failed ({detail})"
        if require:
            return [msg]
        print(f"SKIP: {msg}")
        return []

    errors = []
    for line in diff.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        status = parts[0]
        if status.startswith("A"):
            continue  # pure addition -- allowed
        paths = parts[1:]
        errors.append(
            f"append-only violation: `{status}` on {', '.join(paths)} "
            f"relative to {base_ref} -- records/artifacts must only be added"
        )
    if not errors:
        print(f"OK: no append-only violations relative to {base_ref} ({merge_base[:12]})")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base-ref",
        default="origin/main",
        help="ref to diff against for the append-only check (default: origin/main)",
    )
    parser.add_argument(
        "--require-append-only",
        action="store_true",
        help="fail (instead of SKIP) if the append-only base ref cannot be resolved",
    )
    args = parser.parse_args()

    all_errors: list[str] = []

    # NOTE: an empty/absent records tree must NOT short-circuit -- deleting
    # every record is itself the most severe append-only violation there is,
    # and reporting only "the directory is gone" would let it through with a
    # misleading diagnosis. Record it as an error and keep going so the
    # append-only check below still runs and names the deleted paths.
    record_files = _tracked_record_files() if RECORDS_ROOT.exists() else []
    if not RECORDS_ROOT.exists():
        all_errors.append(f"{RECORDS_ROOT.relative_to(REPO_ROOT)} does not exist")
    elif not record_files:
        all_errors.append(
            "no tracked records under verification/records/**/records/*.md"
        )

    print(f"== linting {len(record_files)} record(s) ==")
    for error in all_errors:
        print(f"  - {error}")

    all_ids_by_experiment: dict[str, set] = {}
    metas_by_path: dict[Path, dict] = {}
    for path in record_files:
        experiment = path.parent.parent.name
        stem = path.stem
        all_ids_by_experiment.setdefault(experiment, set()).add(stem)
        try:
            metas_by_path[path] = _extract_meta_block(
                path.read_text(encoding="utf-8"), path
            )
        except LintError:
            metas_by_path[path] = {}

    superseded_ids: set[str] = set()
    for meta in metas_by_path.values():
        try:
            superseded_ids.update(normalize_supersedes(meta.get("supersedes")))
        except ValueError:
            pass  # reported by lint_record

    for path in record_files:
        errors = lint_record(path, all_ids_by_experiment)
        errors += check_hash_freshness(path, superseded_ids)
        if errors:
            print(f"FAIL: {path.relative_to(REPO_ROOT)}")
            for e in errors:
                print(f"  - {e}")
        else:
            print(f"OK:   {path.relative_to(REPO_ROOT)}")
        all_errors.extend(errors)

    print()
    print("== append-only check ==")
    append_errors = check_append_only(args.base_ref, args.require_append_only)
    for e in append_errors:
        print(f"  - {e}")
    all_errors.extend(append_errors)

    print()
    if all_errors:
        print(f"FAIL: {len(all_errors)} record-lint error(s)")
        return 1
    print("PASS: all records valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
