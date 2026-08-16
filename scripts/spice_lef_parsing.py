#!/usr/bin/env python3
"""Shared SPICE `.SUBCKT` header and LEF `MACRO`/`PIN` parsing.

`layout/lvs/build_reference_netlist.py` (gate-level Verilog -> SPICE, for
`klt lvs`) and `verification/gate-level/spice_to_verilog.py` (the converse:
`klt extract --abstract-cells` SPICE -> Verilog) both need, from the same two
input formats, "recover each cell type's pin order/direction so positional
SPICE args or named Verilog ports bind correctly". This module holds that
shared parsing logic once, so a format quirk fixed on one side (e.g. a SPICE
net name needing `unescape()`, or a LEF with unusual `PIN`/`END` spacing)
does not silently go unfixed on the other.

Two entry points:

* `parse_subckt_headers()` -- every `.SUBCKT <name> <pins...>` header in a
  SPICE file (or its already-read text), including the top one, joining `+`
  continuation lines and dropping `*` comments/blank lines first.
* `parse_lef_macros()` -- `{cell_type: {pin: direction}}` for a requested set
  of cell types, from a LEF's `MACRO ... PIN ... DIRECTION ... END` blocks.
  Cell types requested but not found in the LEF are simply absent from the
  returned dict; whether that is fatal is a caller decision (the two callers
  need different behavior here: `spice_to_verilog.py` treats any missing
  requested type as fatal, `build_reference_netlist.py` only reaches the LEF
  as a per-type fallback and reports its own error message).
"""

from __future__ import annotations

import re
from collections import OrderedDict
from pathlib import Path
from typing import Iterable, Union


def unescape(name: str) -> str:
    """`klt extract` writes SPICE-escaped names (`\\$1921`); recover the
    underlying net/instance/pin name."""
    return name.replace("\\", "")


def logical_lines(text: str):
    """Yield SPICE logical lines, joining `+` continuations and dropping
    `*` comment lines and blank lines."""
    pending: "list[str] | None" = None
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line.strip():
            continue
        if line.lstrip().startswith("*"):
            continue
        if line.startswith("+"):
            if pending is None:
                raise ValueError(f"continuation line with nothing to continue: {raw!r}")
            pending.append(line[1:].strip())
            continue
        if pending is not None:
            yield " ".join(pending)
        pending = [line.strip()]
    if pending is not None:
        yield " ".join(pending)


def parse_subckt_headers(text_or_path: Union[str, Path]) -> "OrderedDict[str, list[str]]":
    """Return {name: [pins...]} for every `.SUBCKT` header block in a SPICE
    file, including the top-level one.

    `text_or_path` is either a `pathlib.Path` (read from disk) or a `str`
    holding already-read SPICE text -- so a caller that already has the text
    in hand (or a synthetic fixture, e.g. in a test) does not need to
    round-trip through a temp file. Pin names are run through `unescape()`,
    same as `spice_to_verilog.py`'s net-name handling elsewhere.
    """
    text = text_or_path.read_text() if isinstance(text_or_path, Path) else text_or_path

    headers: "OrderedDict[str, list[str]]" = OrderedDict()
    for line in logical_lines(text):
        if not line.startswith(".SUBCKT "):
            continue
        tokens = line[len(".SUBCKT "):].split()
        name, pins = tokens[0], [unescape(t) for t in tokens[1:]]
        headers[name] = pins
    return headers


def parse_lef_macros(lef_path: Union[str, Path], cell_types: Iterable[str]) -> "dict[str, OrderedDict[str, str]]":
    """Return {cell_type: {pin: 'INPUT'|'OUTPUT'|'INOUT'}} for `cell_types`
    found in a LEF's `MACRO ... END` blocks (declaration order preserved per
    macro). A cell type in `cell_types` with no matching `MACRO` is simply
    absent from the returned dict."""
    text = Path(lef_path).read_text()
    wanted = set(cell_types)
    out: "dict[str, OrderedDict[str, str]]" = {}
    macro_re = re.compile(r"^MACRO (\S+)$\n(.*?)^END \1$", re.MULTILINE | re.DOTALL)
    pin_re = re.compile(r"^\s*PIN (\S+)$\n(.*?)^\s*END \1$", re.MULTILINE | re.DOTALL)
    for macro in macro_re.finditer(text):
        name = macro.group(1)
        if name not in wanted:
            continue
        dirs: "OrderedDict[str, str]" = OrderedDict()
        for pin in pin_re.finditer(macro.group(2)):
            m = re.search(r"^\s*DIRECTION (\w+)", pin.group(2), re.MULTILINE)
            dirs[pin.group(1)] = m.group(1).upper() if m else "INPUT"
        out[name] = dirs
    return out
