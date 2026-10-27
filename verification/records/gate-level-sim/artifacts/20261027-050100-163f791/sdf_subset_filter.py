#!/usr/bin/env python3
"""Reduce a raw OpenSTA write_sdf file to the INTERCONNECT-only subset.

Drops (a) INTERCONNECT entries whose destination is an ANTENNA_<N>.DIODE pin
and (b) every IOPATH entry, then structurally removes the (ABSOLUTE ...) /
(DELAY ...) / (CELL ...) shells those deletions empty.  Paren balance is
verified on input and output.  Prints the counts as JSON.
Usage: sdf_subset_filter.py RAW.sdf OUT.sdf
"""
import json
import re
import sys

raw, out = sys.argv[1], sys.argv[2]
lines = open(raw, encoding="utf-8").read().split("\n")


def balance(ls):
    return sum(l.count("(") - l.count(")") for l in ls)


assert balance(lines) == 0, "raw SDF is not paren-balanced"
count = lambda ls, pat: sum(1 for l in ls if re.match(r"\s*\(" + pat + r"\b", l))
before = {k: count(lines, k) for k in ("INTERCONNECT", "IOPATH", "TIMINGCHECK")}
anti = re.compile(r"^\s*\(INTERCONNECT\s+\S+\s+ANTENNA_\d+\.DIODE\s")
dropped_antenna = sum(1 for l in lines if anti.match(l))
kept = [l for l in lines if not anti.match(l) and not re.match(r"\s*\(IOPATH\s", l)]


def drop_empty(ls, opener):
    """Remove `opener` blocks that hold nothing but their own closing paren."""
    res, i, n = [], 0, 0
    while i < len(ls):
        if ls[i].strip() == opener and i + 1 < len(ls) and ls[i + 1].strip() == ")":
            i += 2
            n += 1
            continue
        res.append(ls[i])
        i += 1
    return res, n


shells = 0
changed = True
while changed:
    changed = False
    for opener in ("(ABSOLUTE", "(DELAY", "(CELL"):
        kept, n = drop_empty(kept, opener)
        shells += n
        changed |= n > 0
    # a CELL left with only its header lines is content-free
    res, i = [], 0
    while i < len(kept):
        if kept[i].strip() == "(CELL" and i + 3 < len(kept) \
                and kept[i + 1].strip().startswith("(CELLTYPE") \
                and kept[i + 2].strip().startswith("(INSTANCE") \
                and kept[i + 3].strip() == ")":
            i += 4
            shells += 1
            changed = True
            continue
        res.append(kept[i])
        i += 1
    kept = res

assert balance(kept) == 0, "filtered SDF is not paren-balanced"
after = {k: count(kept, k) for k in ("INTERCONNECT", "IOPATH", "TIMINGCHECK")}
open(out, "w", encoding="utf-8").write("\n".join(kept))
print(json.dumps({"raw": before, "antenna_interconnect_dropped": dropped_antenna,
                  "empty_shells_removed": shells, "filtered": after}, indent=1))
