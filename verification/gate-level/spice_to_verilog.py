#!/usr/bin/env python3
"""Derive a simulatable, structural Verilog netlist of the **routed layout**
from `klt extract --abstract-cells`'s SPICE abstraction of that layout.

This is the converse of `layout/lvs/build_reference_netlist.py` (which goes
gate-level Verilog -> SPICE for `klt lvs`), and it exists for the same
reason: `klt place-and-route` has no post-route gate-level netlist export at
all (its `--help` offers only `def_path`/`gds_path`), so the only artifact in
this repo that describes the *actual routed layout*'s cell instances and
connectivity is the LVS-side extraction `klt extract --abstract-cells`
produced in issue #8:

    layout/lvs/modexp_layout_abstracted.spice   (718 instances, 59 cell types)

Pointing a gate-level simulation at the *pre*-route synthesis netlist
(`.../modexp_synth_tied.v`, 683 instances + 1 tie cell) and calling the
result "post-route" would be an overclaim: that netlist is the input to P&R,
not its output, and it is missing all 35 CTS/timing-fixup cells and all 5
gate resizes the routed layout actually contains. So the layout extraction is
the only honest starting point, and this script turns it into Verilog.

What the conversion does
------------------------
* Reads the `.SUBCKT modexp ... .ENDS` block's `X<instance>` cards, binding
  each positional argument to the pin name from that cell type's own
  `.SUBCKT <cell> <pins...>` declaration (the same per-type pin order
  `build_reference_netlist.py` reuses on the reference side).
* Emits one named-port `sky130_fd_sc_hd__<cell>` instantiation per `X` card,
  against the PDK's own behavioural/timing Verilog cell models.
* **Drops the power pins** (`VPWR`/`VGND`/`VPB`/`VNB`). The sky130_fd_sc_hd
  Verilog models declare those ports only under `USE_POWER_PINS`; compiled
  without it they are internal `supply1`/`supply0` nets. Before issue #81's
  PDN this was also the only defensible choice for the *rail* itself: the
  GDS had no PDN, so the extracted rail connectivity was fragmented per
  placement row and not a meaningful power network to simulate. It remains
  correct with a PDN too -- `USE_POWER_PINS` stays undefined either way.
* **Recognizes real top-level `VDD`/`VSS` power ports** (issue #83, once a
  PDN gives the layout a continuous power grid reaching the die boundary --
  `flow/par-modexp.json`'s `power.power_net`/`ground_net`, always exactly
  these two names for this repo). Such a pin is dropped from the emitted
  module's port list (same spirit as the per-cell power pins above -- this
  is a rail, not a functional I/O signal) and declared `supply1`/`supply0`
  instead of an ordinary `wire`, so anything structurally wired to it
  (e.g. a synthesis-inserted tie-high cell whose output the router merged
  directly onto the `VDD` strap -- electrically identical, a legitimate
  layout optimization, not a short) reads a well-defined constant instead
  of an undriven top-level input's `x`. A no-PDN layout has no such pin at
  all, so this is a no-op for it -- the case above is unchanged.
* Derives top-level **port directions structurally** from the netlist plus
  the standard-cell LEF's own `DIRECTION` declarations -- a top pin driven by
  some cell's output pin is an `output`, anything else is an `input`. Nothing
  is read from `rtl/modexp.v`; the RTL is only used by the self-test as an
  independent cross-check.

Validation (all reported, and `--check` turns them into a nonzero exit)
---------------------------------------------------------------------
* instance count / distinct-cell-type count / per-type instance counts must
  agree with `layout/lvs/modexp_layout_extract_report.json`;
* every net must have at most one driver (a two-output short would be a real
  extraction or layout finding);
* every net read by a cell input must have a driver (a cell output or a
  top-level input port), otherwise it is reported as floating.

Usage:
    spice_to_verilog.py <layout_abstracted.spice> <sky130_fd_sc_hd.lef> \
        <output.v> [--report <extract_report.json>] [--top <cell>] \
        [--check] [--quiet]

Self-test: `python3 verification/gate-level/test_spice_to_verilog.py`.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import OrderedDict, defaultdict
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from spice_lef_parsing import (  # noqa: E402
    logical_lines,
    parse_lef_macros,
    parse_subckt_headers,
    unescape,
)

POWER_PINS = ("VPWR", "VGND", "VPB", "VNB")

# Real top-level power/ground ports a PDN-equipped layout's `klt extract` can
# report (issue #83) -- the names are this repo's own PDN configuration
# (`flow/par-modexp.json`'s `power.power_net`/`ground_net`), always exactly
# these two, never a design-chosen alternative. Mapped to the Verilog net
# type that gives every reader of the (power-pin-dropped, no
# `USE_POWER_PINS`) emitted netlist a well-defined constant value matching
# what the rail physically is, instead of an undriven top-level input's `x`.
TOP_POWER_PINS = {"VDD": "supply1", "VSS": "supply0"}

DEFAULT_TOP_CELL = "modexp"


# --------------------------------------------------------------------------
# SPICE parsing
# --------------------------------------------------------------------------
def parse_spice(path: Path, top_cell: str = DEFAULT_TOP_CELL):
    """Return (top_pins, instances, subckt_pins).

    * `top_pins`   -- ordered pin list of the top `.SUBCKT modexp` block.
    * `instances`  -- [(instance_name, cell_type, {pin: net}), ...] in file
                      order, from the top block's `X` cards.
    * `subckt_pins`-- {cell_type: [pin, ...]} for every non-top `.SUBCKT`.
    """
    instances: list[tuple[str, str, "OrderedDict[str, str]"]] = []

    # Pass 1: every `.SUBCKT` header (shared parser), so per-cell pin order
    # is known before the `X` cards that use it are bound (the top block
    # comes first in klt extract's output, the cell declarations after it),
    # then split into the top block's pins vs. every other cell's.
    text = path.read_text()
    all_headers = parse_subckt_headers(text)
    top_pins = all_headers.get(top_cell, [])
    subckt_pins: "OrderedDict[str, list[str]]" = OrderedDict(
        (name, pins) for name, pins in all_headers.items() if name != top_cell
    )

    if not top_pins:
        raise ValueError(f"{path}: no `.SUBCKT {top_cell}` block found")

    # Pass 2: the top block's instance cards.
    in_top = False
    for line in logical_lines(text):
        if line.startswith(".SUBCKT "):
            in_top = line[len(".SUBCKT "):].split()[0] == top_cell
            continue
        if line.startswith(".ENDS"):
            in_top = False
            continue
        if not in_top or not line.startswith("X"):
            continue
        tokens = line.split()
        inst_name = unescape(tokens[0][1:])  # strip the leading 'X'
        cell_type = unescape(tokens[-1])
        nets = [unescape(t) for t in tokens[1:-1]]
        pins = subckt_pins.get(cell_type)
        if pins is None:
            raise ValueError(
                f"{path}: instance {inst_name} uses cell type {cell_type}, "
                f"which has no `.SUBCKT` declaration"
            )
        if len(pins) != len(nets):
            raise ValueError(
                f"{path}: instance {inst_name} ({cell_type}) has {len(nets)} "
                f"positional nets but its `.SUBCKT` declares {len(pins)} pins"
            )
        instances.append((inst_name, cell_type, OrderedDict(zip(pins, nets))))

    return top_pins, instances, subckt_pins


# --------------------------------------------------------------------------
# Verilog identifier mapping
# --------------------------------------------------------------------------
_PLAIN_ID_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_$]*$")
_BUS_BIT_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_$]*)\[(\d+)\]$")
_EXTRACTED_NET_RE = re.compile(r"^\$(\d+)$")


def verilog_net_name(name: str) -> str:
    """Map an extracted SPICE net name to a legal Verilog identifier.

    `klt extract` names unlabelled internal nets `$<n>`; those become
    `n<n>`. Labelled nets (the top-level pins, which carry their drawn label
    text) pass through unchanged when already legal, including `bus[i]`
    forms, and are escaped otherwise.
    """
    m = _EXTRACTED_NET_RE.match(name)
    if m:
        return f"n{m.group(1)}"
    if _PLAIN_ID_RE.match(name) or _BUS_BIT_RE.match(name):
        return name
    return "\\" + name + " "


def report_net_spelling(name: str) -> str:
    """Re-derive `klt extract`'s own JSON-report spelling of a net name.

    `conv.*`'s net names are always the *unescaped* form (`parse_spice`
    unescapes every SPICE token via `spice_lef_parsing.unescape`). The JSON
    report's `nets[].name` (and `devices[].nets[...]`, `parasitics.nets[]`)
    instead carries the same SPICE-escaped spelling the abstracted SPICE
    deck's own node references use -- an unlabelled net's `$<n>` placeholder
    backslash-escapes its leading `$` (`\\$<n>`) so a downstream SPICE reader
    never mistakes it for an inline comment. This mirrors this repo's pinned
    `klt`'s own escaping (klayout-tools#1162, schema_version 3); this
    function does the same transform in reverse of `unescape` so the two
    spellings compare equal.
    """
    return "\\" + name if name.startswith("$") else name


def repo_relative(path: Path) -> str:
    """Path relative to the enclosing git working tree, when there is one.

    The derived netlist is a *committed* artifact, so its header must not
    embed a machine-specific absolute path: two checkouts regenerating it
    from the same extraction must produce byte-identical output (the
    evidence record pins its content hash).
    """
    resolved = path.resolve()
    for parent in [resolved, *resolved.parents]:
        if (parent / ".git").exists():
            try:
                return resolved.relative_to(parent).as_posix()
            except ValueError:
                break
    return resolved.name


# --------------------------------------------------------------------------
# Conversion
# --------------------------------------------------------------------------
class Conversion:
    def __init__(self, top_pins, instances, subckt_pins, pin_dirs,
                 top_cell=DEFAULT_TOP_CELL):
        self.top_cell = top_cell
        self.top_pins = top_pins
        self.instances = instances
        self.subckt_pins = subckt_pins
        self.pin_dirs = pin_dirs

        self.cell_types = OrderedDict()
        for _inst, cell_type, _ports in instances:
            self.cell_types[cell_type] = self.cell_types.get(cell_type, 0) + 1

        self.problems: list[str] = []
        self._analyse()

    # -- net roles ---------------------------------------------------------
    def _analyse(self):
        top_pin_set = set(self.top_pins)
        drivers = defaultdict(list)     # net -> [(inst, pin)] cell outputs
        readers = defaultdict(list)     # net -> [(inst, pin)] cell inputs
        power_nets = set()
        signal_nets = set()

        for inst, cell_type, ports in self.instances:
            dirs = self.pin_dirs[cell_type]
            for pin, net in ports.items():
                if pin in POWER_PINS:
                    power_nets.add(net)
                    continue
                signal_nets.add(net)
                direction = dirs.get(pin)
                if direction is None:
                    self.problems.append(
                        f"{inst} ({cell_type}): pin {pin} has no LEF DIRECTION"
                    )
                    direction = "INPUT"
                if direction == "OUTPUT":
                    drivers[net].append((inst, pin))
                else:
                    readers[net].append((inst, pin))

        self.drivers = drivers
        self.readers = readers
        self.power_nets = power_nets
        self.signal_nets = signal_nets

        # Real top-level power/ground ports (issue #83): a top pin named
        # VDD/VSS *and* actually reached via at least one instance's power
        # pin -- the second condition means a hypothetical layout that
        # happens to label an ordinary signal pin "VDD" without it being a
        # true rail is never misclassified. Empty for a no-PDN layout (no
        # such pin exists in `self.top_pins` at all), so every check below
        # is a no-op there, preserving the pre-#83 no-PDN behavior exactly.
        self.top_power_pins = sorted(
            p for p in top_pin_set if p in TOP_POWER_PINS and p in power_nets
        )
        top_power_pin_set = set(self.top_power_pins)

        # Top-level port directions, derived structurally.
        self.port_direction = {}
        for pin in self.top_pins:
            self.port_direction[pin] = "output" if drivers.get(pin) else "input"

        # Multiply-driven nets: two cell outputs on one net is a short.
        self.multi_driven = sorted(n for n, d in drivers.items() if len(d) > 1)
        for net in self.multi_driven:
            names = ", ".join(f"{i}.{p}" for i, p in drivers[net])
            self.problems.append(f"net {net} has {len(drivers[net])} drivers: {names}")

        # Floating: read by a cell input, driven by neither a cell output nor
        # a top-level input port.
        self.floating = sorted(
            n
            for n in readers
            if n not in drivers and not (n in top_pin_set and self.port_direction[n] == "input")
        )
        for net in self.floating:
            names = ", ".join(f"{i}.{p}" for i, p in readers[net])
            self.problems.append(f"net {net} is undriven but read by: {names}")

        # A net used as both a power pin and a signal pin would be a rail
        # short -- *unless* it is a recognized top-level power port, where
        # this is expected: e.g. a synthesis-inserted tie-high cell whose
        # output the router merged directly onto the VDD strap (DC
        # equivalent, a legitimate layout optimization, not a short).
        self.power_signal_overlap = sorted((power_nets & signal_nets) - top_power_pin_set)
        for net in self.power_signal_overlap:
            self.problems.append(f"net {net} is used as both a power pin and a signal pin")

        # Unused top-level pins (connected to nothing). A recognized
        # top-level power port is, by construction, connected via the power
        # network even though it never appears in `drivers`/`readers`
        # (those only track non-power-pin connections), so it is excluded
        # here rather than reported as floating.
        self.unconnected_top_pins = sorted(
            p
            for p in self.top_pins
            if p not in top_power_pin_set and not drivers.get(p) and not readers.get(p)
        )
        for pin in self.unconnected_top_pins:
            self.problems.append(f"top-level pin {pin} is connected to no cell pin")

    # -- port grouping -----------------------------------------------------
    def ports(self):
        """Return [(direction, name, msb_or_None, lsb_or_None), ...], scalars
        and buses, in a stable (declaration) order."""
        scalars: list[tuple[str, str]] = []
        buses: "OrderedDict[str, list[int]]" = OrderedDict()
        bus_dir: dict[str, str] = {}
        top_power_pin_set = set(self.top_power_pins)
        for pin in sorted(self.top_pins):
            if pin in top_power_pin_set:
                continue
            m = _BUS_BIT_RE.match(pin)
            direction = self.port_direction[pin]
            if m:
                base, idx = m.group(1), int(m.group(2))
                buses.setdefault(base, []).append(idx)
                if base in bus_dir and bus_dir[base] != direction:
                    self.problems.append(
                        f"bus {base} has mixed pin directions "
                        f"({bus_dir[base]} and {direction})"
                    )
                bus_dir[base] = direction
            else:
                scalars.append((direction, pin))

        out = []
        for direction, name in scalars:
            out.append((direction, name, None, None))
        for base, idxs in buses.items():
            lo, hi = min(idxs), max(idxs)
            if sorted(idxs) != list(range(lo, hi + 1)):
                self.problems.append(f"bus {base} has non-contiguous bit indices")
            out.append((bus_dir[base], base, hi, lo))
        out.sort(key=lambda t: (t[0] != "input", t[1]))
        return out

    # -- emission ----------------------------------------------------------
    def to_verilog(self, header_lines) -> str:
        ports = self.ports()
        port_names = {name for _d, name, _m, _l in ports}

        # Nets needing a `wire` declaration: every signal net that is not a
        # top-level port bit, not power-only, and not a recognized top-level
        # power port (those get a `supply1`/`supply0` declaration below
        # instead, so anything wired to them reads a well-defined constant).
        # Grouped into scalars and bus ranges the same way top-level ports
        # are grouped above (`ports()`): `--def-net-names` can label an
        # *internal* net `mm_p[3]`, not just a top-level port, and
        # declaring one `wire mm_p[3];` per bit would have Icarus parse each
        # as a SystemVerilog unpacked-array declaration of a *different*
        # size for the same name `mm_p` -- a redeclaration error on the
        # second bit, not the intended single multi-bit net.
        top_power_pin_set = set(self.top_power_pins)
        declared_scalars: list[str] = []
        declared_buses: "OrderedDict[str, list[int]]" = OrderedDict()
        for net in self.signal_nets:
            if net in port_names or net in top_power_pin_set:
                continue
            m = _BUS_BIT_RE.match(net)
            if m and m.group(1) in port_names:
                continue
            if m:
                declared_buses.setdefault(m.group(1), []).append(int(m.group(2)))
            else:
                declared_scalars.append(net)

        lines: list[str] = []
        for line in header_lines:
            lines.append(f"// {line}" if line else "//")
        lines.append("")
        lines.append("`default_nettype none")
        lines.append("")
        lines.append(f"module {self.top_cell} (")
        decls = []
        for direction, name, msb, lsb in ports:
            kw = "input  wire" if direction == "input" else "output wire"
            rng = "" if msb is None else f" [{msb}:{lsb}]"
            decls.append(f"    {kw}{rng} {name}")
        lines.append(",\n".join(decls))
        lines.append(");")
        lines.append("")
        for pin in self.top_power_pins:
            lines.append(f"  {TOP_POWER_PINS[pin]} {verilog_net_name(pin)};")
        for net in sorted(set(declared_scalars)):
            lines.append(f"  wire {verilog_net_name(net)};")
        for base in sorted(declared_buses):
            idxs = declared_buses[base]
            lo, hi = min(idxs), max(idxs)
            if sorted(idxs) != list(range(lo, hi + 1)):
                self.problems.append(f"bus {base} has non-contiguous bit indices")
            lines.append(f"  wire [{hi}:{lo}] {base};")
        lines.append("")
        for inst, cell_type, port_map in self.instances:
            conns = [
                f".{pin}({verilog_net_name(net)})"
                for pin, net in port_map.items()
                if pin not in POWER_PINS
            ]
            lines.append(f"  {cell_type} {inst} (")
            lines.append("      " + ",\n      ".join(conns))
            lines.append("  );")
        lines.append("")
        lines.append("endmodule")
        lines.append("")
        lines.append("`default_nettype wire")
        lines.append("")
        return "\n".join(lines)


# --------------------------------------------------------------------------
# Cross-check against the klt extract report
# --------------------------------------------------------------------------
def check_against_report(conv: Conversion, report_path: Path) -> list[str]:
    report = json.loads(report_path.read_text())
    errors: list[str] = []

    expected = {c["cell"]: c["instance_count"] for c in report.get("abstracted_cells", [])}
    got = dict(conv.cell_types)
    if expected != got:
        for cell in sorted(set(expected) | set(got)):
            if expected.get(cell) != got.get(cell):
                errors.append(
                    f"instance count for {cell}: report says {expected.get(cell)}, "
                    f"netlist has {got.get(cell)}"
                )
    total_expected = sum(expected.values())
    if len(conv.instances) != total_expected:
        errors.append(
            f"total instance count {len(conv.instances)} != report total {total_expected}"
        )
    if report.get("pin_count") != len(conv.top_pins):
        errors.append(
            f"top-level pin count {len(conv.top_pins)} != report pin_count "
            f"{report.get('pin_count')}"
        )

    # Every net named in the report must be one this netlist knows about
    # (the reverse does not hold: the report also lists nets carrying no cell
    # pin at all, e.g. isolated rail fragments).
    #
    # `report_net_spelling` re-applies the escaping `klt extract`'s own JSON
    # response now uses for `nets[].name` (since klayout-tools#1162, this
    # repo's pinned `klt` schema_version 3): an unlabelled net's placeholder
    # name is written SPICE-escaped (`\$1568`, matching the abstracted
    # SPICE's own `NetlistSpiceWriter` node-reference spelling) rather than
    # the older, plain `$1568`. `conv.*`'s own net names are always the
    # *unescaped* form (`parse_spice` unescapes every SPICE token), so the
    # comparison below must re-escape before comparing -- otherwise every
    # unlabelled net in the design (there are hundreds) would spuriously
    # read as "absent from the report."
    known = conv.signal_nets | conv.power_nets | set(conv.top_pins)
    report_nets = {n["name"] for n in report.get("nets", [])}
    stray = sorted({n for n in known if report_net_spelling(n) not in report_nets})
    if stray:
        errors.append(
            f"{len(stray)} net(s) in the netlist are absent from the extract "
            f"report's nets[]: {', '.join(stray[:5])}"
        )
    return errors


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("spice", type=Path, help="klt extract --abstract-cells SPICE output")
    parser.add_argument("lef", type=Path, help="sky130_fd_sc_hd.lef (for pin DIRECTIONs)")
    parser.add_argument("output", type=Path, help="Verilog netlist to write")
    parser.add_argument("--top", default=DEFAULT_TOP_CELL,
                        help=f"top cell name (default: {DEFAULT_TOP_CELL})")
    parser.add_argument("--report", type=Path, default=None,
                        help="klt extract --format json report, cross-checked if given")
    parser.add_argument("--check", action="store_true",
                        help="exit nonzero if any validation problem is reported")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)

    try:
        top_pins, instances, subckt_pins = parse_spice(args.spice, args.top)
    except ValueError as exc:
        print(f"FATAL: {exc}", file=sys.stderr)
        return 1
    used_types = OrderedDict((c, None) for _i, c, _p in instances)
    pin_dirs = parse_lef_macros(args.lef, used_types)
    missing_macros = set(used_types) - set(pin_dirs)
    if missing_macros:
        raise ValueError(
            f"{args.lef}: no MACRO for cell type(s): {', '.join(sorted(missing_macros))}"
        )

    # The extraction's per-cell-type pin set must agree with the LEF's, or the
    # named-port instantiations below would bind the wrong pins.
    pin_set_errors = []
    for cell_type in used_types:
        spice_signal = {p for p in subckt_pins[cell_type] if p not in POWER_PINS}
        lef_signal = {p for p in pin_dirs[cell_type] if p not in POWER_PINS}
        if spice_signal != lef_signal:
            pin_set_errors.append(
                f"{cell_type}: extracted signal pins {sorted(spice_signal)} != "
                f"LEF signal pins {sorted(lef_signal)}"
            )

    conv = Conversion(top_pins, instances, subckt_pins, pin_dirs, args.top)

    report_errors = []
    if args.report:
        report_errors = check_against_report(conv, args.report)

    header = [
        "AUTOGENERATED -- do not edit by hand.",
        "",
        "Structural Verilog netlist of the ROUTED LAYOUT (layout/modexp.gds),",
        f"derived from {repo_relative(args.spice)}",
        "by verification/gate-level/spice_to_verilog.py.",
        "",
        f"{len(instances)} standard-cell instances, {len(conv.cell_types)} distinct",
        f"cell types, {len(top_pins)} top-level pins.",
        "",
        "Power pins (VPWR/VGND/VPB/VNB) are intentionally absent: compile the",
        "sky130_fd_sc_hd models WITHOUT `USE_POWER_PINS`.",
    ]
    if conv.top_power_pins:
        header += [
            f"This layout has a real PDN -- {', '.join(conv.top_power_pins)} are",
            "genuine top-level power/ground pins in the extraction, so they are",
            "likewise dropped from this module's own port list and declared",
            "supply1/supply0 instead of an ordinary wire (see issue #83), giving",
            "anything structurally wired to them a well-defined constant instead",
            "of an undriven top-level input's `x`.",
        ]
    else:
        header += [
            "This GDS has no PDN, so extracted rail connectivity is fragmented",
            "per placement row and is not a power network worth simulating --",
            "see verification/gate-level/README.md for the full scope statement.",
        ]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(conv.to_verilog(header))

    problems = pin_set_errors + conv.problems + report_errors
    if not args.quiet:
        print(
            f"wrote {args.output}: {len(instances)} instances, "
            f"{len(conv.cell_types)} distinct cell types, "
            f"{len(top_pins)} top-level pins, "
            f"{len(conv.signal_nets)} signal nets, "
            f"{len(conv.power_nets)} power-pin nets"
        )
        outs = [p for p in conv.ports() if p[0] == "output"]
        ins = [p for p in conv.ports() if p[0] == "input"]
        print(f"  ports: {len(ins)} input, {len(outs)} output (directions derived from LEF)")
        if conv.top_power_pins:
            print(
                f"  top-level power ports: {', '.join(conv.top_power_pins)} "
                "(dropped from ports, declared supply1/supply0)"
            )
        if args.report:
            print(f"  cross-checked against {args.report}")
        if problems:
            print(f"  {len(problems)} validation problem(s):")
            for p in problems:
                print(f"    - {p}")
        else:
            print("  validation: OK (no shorts, no floating inputs, counts agree)")

    if problems and args.check:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
