#!/usr/bin/env python3
"""Build a golden-reference SPICE netlist (subckt-call form) for `klt lvs`
from a klt-synthesize gate-level Verilog netlist, reusing the per-cell
SUBCKT pin order klt extract --abstract-cells already wrote for the layout
side (so both sides bind positional X-card arguments to the same pin order
for the same cell type). A cell type used in the synthesis netlist but
absent from the routed layout (e.g. a cell OpenROAD's placer/resizer
upsized/downsized to a different drive-strength variant, so the *original*
type is no longer instantiated anywhere in the GDS) falls back to that
type's own PIN order straight from the sky130_fd_sc_hd LEF -- there is no
layout-side instance of it to stay positionally consistent with.

Usage:
    build_reference_netlist.py <verilog_netlist> <layout_abstracted_spice> \
        <sky130_fd_sc_hd.lef> <output_spice>

The top cell is $DESIGN, else the stem of the repo's single `rtl/*.v` file;
with neither there is no default and the script exits with an error. The repo
root is $REPO_ROOT, else `git rev-parse --show-toplevel`.
"""
import os
import re
import subprocess
import sys
from collections import OrderedDict
from pathlib import Path


def find_repo_root():
    """$REPO_ROOT, else this file's `git rev-parse --show-toplevel`; None if
    neither resolves. Independent of how deep this file sits in the tree."""
    if os.environ.get("REPO_ROOT"):
        return Path(os.environ["REPO_ROOT"])
    git = subprocess.run(
        ["git", "-C", str(Path(__file__).resolve().parent), "rev-parse", "--show-toplevel"],
        capture_output=True, text=True,
    )
    return Path(git.stdout.strip()) if git.returncode == 0 else None


REPO_ROOT = find_repo_root()
if REPO_ROOT is None:
    sys.exit("FATAL: not inside a git work tree and REPO_ROOT is not set")
# spice_lef_parsing.py lives in <repo>/scripts unless $SPICE_LEF_PARSING_DIR
# says otherwise (e.g. a vendored copy under scripts/common).
sys.path.insert(0, os.environ.get("SPICE_LEF_PARSING_DIR") or str(REPO_ROOT / "scripts"))

from spice_lef_parsing import parse_lef_macros, parse_subckt_headers  # noqa: E402

POWER_PINS = {"VPWR", "VGND", "VPB", "VNB"}


def design_name():
    """$DESIGN, else the stem of the repo's one `rtl/*.v`; exits if neither."""
    if os.environ.get("DESIGN"):
        return os.environ["DESIGN"]
    rtl = sorted((REPO_ROOT / "rtl").glob("*.v"))
    if len(rtl) != 1:
        sys.exit(f"error: DESIGN not set and {REPO_ROOT / 'rtl'} does not hold exactly one .v file")
    return rtl[0].stem


def parse_lef_pins(lef_path, cell_type):
    """Return the PIN-declaration-order pin list for one MACRO in a LEF file,
    or None if the LEF has no MACRO for it."""
    macro = parse_lef_macros(lef_path, [cell_type]).get(cell_type)
    return None if macro is None else list(macro.keys())


def parse_verilog(v_path):
    """Return (top_module_name, [(cell_type, inst_name, {pin: net}), ...]).

    Whitespace/line-wrapping-agnostic on purpose: `klt synthesize`'s Yosys
    output wraps each `.PORT(NET)` on its own line with a standalone closing
    `  );`, while OpenROAD's own `write_verilog` (the as-built netlist export,
    klayout-tools#997) puts the first port on the instantiation line itself
    and closes with `);` glued to the last port -- two different but both
    syntactically valid Verilog instantiation stylings of the same construct.
    Matching on `\\s` (which spans newlines) rather than a fixed line
    template handles both without caring which tool wrote the file.
    """
    with open(v_path) as f:
        text = f.read()

    m = re.search(r"\bmodule\s+(\w+)\s*\(", text)
    top_name = m.group(1) if m else None

    # Match "<celltype> <instname> (.PORT(NET), .PORT(NET) ... );" with
    # arbitrary whitespace/newlines between tokens.
    inst_re = re.compile(
        r"\b(sky130_fd_sc_hd__\w+)\s+(\S+)\s*\("
        r"\s*((?:\.\w+\([^()]*\)\s*,?\s*)+)\)\s*;",
    )
    port_re = re.compile(r"\.(\w+)\(([^()]*)\)")

    instances = []
    for match in inst_re.finditer(text):
        cell_type, inst_name, body = match.group(1), match.group(2), match.group(3)
        ports = {}
        for m2 in port_re.finditer(body):
            ports[m2.group(1)] = m2.group(2).strip()
        instances.append((cell_type, inst_name, ports))
    return top_name, instances


def main():
    if len(sys.argv) != 5:
        print(__doc__)
        sys.exit(1)
    v_path, layout_spice_path, lef_path, out_path = sys.argv[1:5]

    design = design_name()
    layout_pins = parse_subckt_headers(Path(layout_spice_path))
    if design not in layout_pins:
        sys.exit(f"error: no `.SUBCKT {design}` in {layout_spice_path}")
    top_pins_layout = layout_pins.pop(design)  # reuse layout's own top pin order/names

    top_name, instances = parse_verilog(v_path)
    if top_name != design:
        print(f"warning: top module is '{top_name}', expected '{design}'", file=sys.stderr)

    used_cell_types = OrderedDict()
    for cell_type, _inst, _ports in instances:
        used_cell_types[cell_type] = True

    pin_order_by_type = {}
    lef_fallback_types = []
    for cell_type in used_cell_types:
        if cell_type in layout_pins:
            pin_order_by_type[cell_type] = layout_pins[cell_type]
            continue
        lef_pins = parse_lef_pins(lef_path, cell_type)
        if lef_pins is None:
            print(f"error: no pin order for '{cell_type}' (not in layout, not in LEF)", file=sys.stderr)
            sys.exit(1)
        pin_order_by_type[cell_type] = lef_pins
        lef_fallback_types.append(cell_type)

    unconnected_pins = []

    with open(out_path, "w") as out:
        out.write("* golden reference netlist, built from klt synthesize's gate-level\n")
        out.write("* Verilog netlist (verification/records/place-and-route/artifacts/\n")
        out.write("* 20260814-203901-c741877/modexp_synth_tied.v) --\n")
        out.write("* see layout/lvs/README.md for how this file is produced and its\n")
        out.write("* documented scope (pre-CTS logical netlist; VPWR/VGND/VPB/VNB tied\n")
        out.write("* to one ideal global net per name, since the gate netlist carries no\n")
        out.write("* power connectivity at all).\n")
        if lef_fallback_types:
            out.write(
                "* Cell types resolved from the LEF, not the layout side (absent\n"
                f"* from the routed GDS -- resized during P&R): {', '.join(lef_fallback_types)}\n"
            )
        out.write("\n")

        out.write(f".SUBCKT {design} {' '.join(top_pins_layout)}\n")
        for cell_type, inst_name, ports in instances:
            pin_order = pin_order_by_type[cell_type]
            args = []
            for pin in pin_order:
                if pin in ports:
                    args.append(ports[pin])
                elif pin in POWER_PINS:
                    args.append(pin)  # one ideal global net per power-pin name
                else:
                    # Unconnected non-power pin (e.g. sky130_fd_sc_hd__conb_1's
                    # unused HI output when only the LO tie is needed) -- a
                    # fresh, unique floating net, not tied to anything else.
                    unconn_net = f"_unconn_{inst_name}_{pin}_"
                    args.append(unconn_net)
                    unconnected_pins.append((inst_name, cell_type, pin))
            out.write(f"X{inst_name} {' '.join(args)} {cell_type}\n")
        out.write(f".ENDS {design}\n\n")

        for cell_type in used_cell_types:
            pin_order = pin_order_by_type[cell_type]
            out.write(f".SUBCKT {cell_type} {' '.join(pin_order)}\n")
            out.write(f".ENDS {cell_type}\n\n")

    print(
        f"wrote {out_path}: {len(instances)} instances, "
        f"{len(used_cell_types)} distinct cell types "
        f"({len(lef_fallback_types)} LEF-fallback)"
    )
    if unconnected_pins:
        print(f"{len(unconnected_pins)} unconnected non-power pin(s), each given a fresh floating net:")
        for inst_name, cell_type, pin in unconnected_pins:
            print(f"  {inst_name} ({cell_type}).{pin}")


if __name__ == "__main__":
    main()
