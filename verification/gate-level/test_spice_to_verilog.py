#!/usr/bin/env python3
"""Self-test for `verification/gate-level/spice_to_verilog.py`.

That script is the only thing standing between "we simulated the routed
layout" and "we simulated something that merely looks like it". A converter
that silently drops instances, mis-binds a positional SPICE argument to the
wrong pin, or quietly stops noticing that its output no longer matches the
extraction report would produce a *passing* gate-level run against the wrong
netlist -- a failure mode with no test failure attached to it. So each
property the conversion relies on gets an executable case here.

Two independent halves, both dependency-free (no PDK, no simulator, so this
runs in CI exactly as `verification/test_check_records.py` does):

1. **Synthetic fixture cases** -- a hand-written miniature SPICE
   abstraction + LEF are written to a temp dir and the *real*
   `spice_to_verilog.py` is run against them as a subprocess. Covers pin
   binding, power-pin dropping, structural port-direction derivation, bus
   reassembly, and the three validation classes (`--check`): a two-output
   short, an undriven cell input, and a mismatch against the extraction
   report.

2. **Committed-artifact consistency** -- the checked-in
   `modexp_post_route.v` is parsed and its instance count, per-cell-type
   instance counts, cell-type set, and top-level port bits are asserted
   against `layout/lvs/modexp_layout_extract_report.json` and
   `layout/lvs/modexp_layout_abstracted.spice`. This is what catches a
   *stale* committed netlist: if the layout extraction is ever re-run and
   the netlist is not regenerated, this fails.

Usage:
    python3 verification/gate-level/test_spice_to_verilog.py
Exit codes: 0 all cases behave as specified, 1 at least one did not.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent
CONVERTER = HERE / "spice_to_verilog.py"
COMMITTED_NETLIST = HERE / "modexp_post_route.v"
EXTRACT_REPORT = REPO_ROOT / "layout" / "lvs" / "modexp_layout_extract_report.json"
ABSTRACTED_SPICE = REPO_ROOT / "layout" / "lvs" / "modexp_layout_abstracted.spice"

# --------------------------------------------------------------------------
# Synthetic fixture: a two-flop shift register plus an inverter, with the
# same shape as the real extraction -- `$N` internal nets, labelled
# top-level pins, alphabetically-ordered .SUBCKT pin lists including power
# pins, and one bus port.
# --------------------------------------------------------------------------
FIXTURE_SPICE = """* extracted by klt extract --deck sky130

* cell tiny
.SUBCKT tiny clk d_in[0] d_in[1] q_out[0] q_out[1] rst_n
Xdff0 clk d_in[0] \\$10 rst_n \\$99 \\$98 \\$98
+ sky130_fd_sc_hd__dfrtp_1
Xdff1 clk \\$10 q_out[0] rst_n \\$99 \\$98 \\$98
+ sky130_fd_sc_hd__dfrtp_1
Xinv0 d_in[1] \\$99 \\$98 \\$98 q_out[1]
+ sky130_fd_sc_hd__clkinv_1
.ENDS tiny

* cell sky130_fd_sc_hd__dfrtp_1
.SUBCKT sky130_fd_sc_hd__dfrtp_1 CLK D Q RESET_B VGND VPB VPWR
.ENDS sky130_fd_sc_hd__dfrtp_1

* cell sky130_fd_sc_hd__clkinv_1
.SUBCKT sky130_fd_sc_hd__clkinv_1 A VGND VPB VPWR Y
.ENDS sky130_fd_sc_hd__clkinv_1
"""

FIXTURE_LEF = """VERSION 5.7 ;

MACRO sky130_fd_sc_hd__dfrtp_1
  PIN CLK
    DIRECTION INPUT ;
  END CLK
  PIN D
    DIRECTION INPUT ;
  END D
  PIN Q
    DIRECTION OUTPUT ;
  END Q
  PIN RESET_B
    DIRECTION INPUT ;
  END RESET_B
  PIN VGND
    DIRECTION INOUT ;
  END VGND
  PIN VPB
    DIRECTION INOUT ;
  END VPB
  PIN VPWR
    DIRECTION INOUT ;
  END VPWR
END sky130_fd_sc_hd__dfrtp_1

MACRO sky130_fd_sc_hd__clkinv_1
  PIN A
    DIRECTION INPUT ;
  END A
  PIN VGND
    DIRECTION INOUT ;
  END VGND
  PIN VPB
    DIRECTION INOUT ;
  END VPB
  PIN VPWR
    DIRECTION INOUT ;
  END VPWR
  PIN Y
    DIRECTION OUTPUT ;
  END Y
END sky130_fd_sc_hd__clkinv_1

END LIBRARY
"""

FIXTURE_REPORT = {
    "pin_count": 6,
    "net_count": 8,
    "nets": [
        {"name": n}
        for n in ("clk", "d_in[0]", "d_in[1]", "q_out[0]", "q_out[1]", "rst_n", "$10", "$99", "$98")
    ],
    "abstracted_cells": [
        {"cell": "sky130_fd_sc_hd__dfrtp_1", "instance_count": 2},
        {"cell": "sky130_fd_sc_hd__clkinv_1", "instance_count": 1},
    ],
}


def run_converter(workdir: Path, spice: str, report: dict | None, extra=()):
    """Run the real converter as a subprocess. Returns (exit_code, stdout+stderr, verilog_text)."""
    spice_path = workdir / "layout.spice"
    lef_path = workdir / "cells.lef"
    out_path = workdir / "out.v"
    spice_path.write_text(spice)
    lef_path.write_text(FIXTURE_LEF)
    argv = [
        sys.executable, str(CONVERTER), str(spice_path), str(lef_path), str(out_path),
        "--top", "tiny",
    ]
    if report is not None:
        report_path = workdir / "report.json"
        report_path.write_text(json.dumps(report))
        argv += ["--report", str(report_path)]
    argv += list(extra)
    proc = subprocess.run(argv, capture_output=True, text=True)
    verilog = out_path.read_text() if out_path.exists() else ""
    return proc.returncode, proc.stdout + proc.stderr, verilog


# --------------------------------------------------------------------------
# Synthetic cases
# --------------------------------------------------------------------------
def case_happy_path():
    """Baseline: clean conversion, no validation problems, correct shape."""
    with tempfile.TemporaryDirectory(prefix="s2v-selftest-") as tmp:
        rc, out, v = run_converter(Path(tmp), FIXTURE_SPICE, FIXTURE_REPORT, ["--check"])
    problems = []
    if rc != 0:
        problems.append(f"exit {rc}, expected 0 -- output:\n{out}")
    if "validation: OK" not in out:
        problems.append("did not report a clean validation")

    # Structural port derivation: q_out is driven by cell outputs -> output;
    # everything else -> input. The bus is reassembled, not left as bits.
    for want in (
        "input  wire clk;" .replace(";", ""),
        "input  wire [1:0] d_in",
        "input  wire rst_n",
        "output wire [1:0] q_out",
    ):
        if want not in v:
            problems.append(f"missing port declaration {want!r}")

    # Pin binding: positional SPICE args bound by the .SUBCKT pin order.
    if ".CLK(clk)" not in v or ".D(d_in[0])" not in v or ".Q(n10)" not in v:
        problems.append("dff0's pins are not bound to the expected nets")
    if ".RESET_B(rst_n)" not in v:
        problems.append("dff0.RESET_B is not bound to rst_n")
    # Power pins dropped entirely.
    for banned in (".VPWR(", ".VGND(", ".VPB(", ".VNB("):
        if banned in v:
            problems.append(f"power pin {banned} was emitted; it must be dropped")
    # `$`-prefixed extracted net names are remapped to legal identifiers.
    if "$" in v:
        problems.append("a raw `$`-prefixed extracted net name leaked into the Verilog")
    if "wire n10;" not in v:
        problems.append("internal net $10 was not declared as wire n10")
    # A power-only net must not be declared as a signal wire.
    if "wire n98;" in v or "wire n99;" in v:
        problems.append("a power-only net was declared as a signal wire")
    return problems


def case_multi_driver():
    """Two cell outputs on one net is a short -- must be reported."""
    spice = FIXTURE_SPICE.replace(
        "Xinv0 d_in[1] \\$99 \\$98 \\$98 q_out[1]",
        "Xinv0 d_in[1] \\$99 \\$98 \\$98 \\$10",
    )
    with tempfile.TemporaryDirectory(prefix="s2v-selftest-") as tmp:
        rc, out, _v = run_converter(Path(tmp), spice, None, ["--check"])
    problems = []
    if rc == 0:
        problems.append("exit 0 with --check, expected nonzero")
    if "has 2 drivers" not in out:
        problems.append(f"did not name the two-driver short -- output:\n{out}")
    return problems


def case_floating_input():
    """A cell input on a net nothing drives must be reported."""
    spice = FIXTURE_SPICE.replace(
        "Xdff1 clk \\$10 q_out[0] rst_n",
        "Xdff1 clk \\$77 q_out[0] rst_n",
    )
    with tempfile.TemporaryDirectory(prefix="s2v-selftest-") as tmp:
        rc, out, _v = run_converter(Path(tmp), spice, None, ["--check"])
    problems = []
    if rc == 0:
        problems.append("exit 0 with --check, expected nonzero")
    if "is undriven but read by" not in out:
        problems.append(f"did not name the floating net -- output:\n{out}")
    return problems


def case_report_mismatch():
    """A per-cell-type instance count that disagrees with the extraction
    report must be reported -- this is the check that makes a silently
    dropped instance impossible to miss."""
    report = json.loads(json.dumps(FIXTURE_REPORT))
    report["abstracted_cells"][0]["instance_count"] = 3
    with tempfile.TemporaryDirectory(prefix="s2v-selftest-") as tmp:
        rc, out, _v = run_converter(Path(tmp), FIXTURE_SPICE, report, ["--check"])
    problems = []
    if rc == 0:
        problems.append("exit 0 with --check, expected nonzero")
    if "instance count for sky130_fd_sc_hd__dfrtp_1" not in out:
        problems.append(f"did not name the count disagreement -- output:\n{out}")
    return problems


def case_pin_count_mismatch():
    """A top-level pin count disagreeing with the report must be reported."""
    report = json.loads(json.dumps(FIXTURE_REPORT))
    report["pin_count"] = 7
    with tempfile.TemporaryDirectory(prefix="s2v-selftest-") as tmp:
        rc, out, _v = run_converter(Path(tmp), FIXTURE_SPICE, report, ["--check"])
    problems = []
    if rc == 0:
        problems.append("exit 0 with --check, expected nonzero")
    if "top-level pin count" not in out:
        problems.append(f"did not name the pin-count disagreement -- output:\n{out}")
    return problems


def case_pin_arity_mismatch():
    """An X card whose positional-argument count disagrees with its cell's
    .SUBCKT arity must be a hard error, never a silent partial binding."""
    spice = FIXTURE_SPICE.replace(
        "Xinv0 d_in[1] \\$99 \\$98 \\$98 q_out[1]",
        "Xinv0 d_in[1] \\$99 \\$98 q_out[1]",
    )
    with tempfile.TemporaryDirectory(prefix="s2v-selftest-") as tmp:
        rc, out, _v = run_converter(Path(tmp), spice, None)
    problems = []
    if rc == 0:
        problems.append("exit 0, expected a hard failure")
    if "positional nets but its `.SUBCKT` declares" not in out:
        problems.append(f"did not name the arity mismatch -- output:\n{out}")
    return problems


# --------------------------------------------------------------------------
# Committed-artifact consistency (no PDK, no simulator)
# --------------------------------------------------------------------------
_INST_RE = re.compile(r"^  (sky130_fd_sc_hd__\w+) (\S+) \($", re.MULTILINE)
_PORT_RE = re.compile(r"^    (input|output)\s+wire\s*(?:\[(\d+):(\d+)\])?\s*(\w+)", re.MULTILINE)


def case_committed_netlist_matches_extraction():
    problems = []
    for path in (COMMITTED_NETLIST, EXTRACT_REPORT, ABSTRACTED_SPICE):
        if not path.exists():
            return [f"{path} not found"]

    text = COMMITTED_NETLIST.read_text()
    report = json.loads(EXTRACT_REPORT.read_text())

    instances = _INST_RE.findall(text)
    by_type = Counter(cell for cell, _inst in instances)
    expected = {c["cell"]: c["instance_count"] for c in report["abstracted_cells"]}
    total_expected = sum(expected.values())

    if len(instances) != total_expected:
        problems.append(
            f"committed netlist has {len(instances)} instances, extraction "
            f"report says {total_expected}"
        )
    if dict(by_type) != expected:
        for cell in sorted(set(expected) | set(by_type)):
            if expected.get(cell) != by_type.get(cell):
                problems.append(
                    f"instance count for {cell}: netlist {by_type.get(cell)}, "
                    f"report {expected.get(cell)}"
                )
    if len(set(inst for _c, inst in instances)) != len(instances):
        problems.append("committed netlist has duplicate instance names")

    # Top-level port bits must equal the extraction's own pin count and the
    # abstracted SPICE's own top .SUBCKT pin list.
    port_bits = 0
    for _dir, msb, lsb, _name in _PORT_RE.findall(text):
        port_bits += 1 if msb == "" else abs(int(msb) - int(lsb)) + 1
    if port_bits != report["pin_count"]:
        problems.append(
            f"committed netlist declares {port_bits} port bits, extraction "
            f"report says pin_count={report['pin_count']}"
        )

    spice_text = ABSTRACTED_SPICE.read_text()
    m = re.search(r"^\.SUBCKT modexp (.*?)$(\n^\+.*$)*", spice_text, re.MULTILINE)
    if not m:
        problems.append("could not find `.SUBCKT modexp` in the abstracted SPICE")
    else:
        spice_top = m.group(0).replace("\n+", " ")[len(".SUBCKT modexp "):].split()
        if len(spice_top) != report["pin_count"]:
            problems.append(
                f"abstracted SPICE top .SUBCKT declares {len(spice_top)} pins, "
                f"report says {report['pin_count']}"
            )

    # The netlist header must not have drifted from the artifact it cites.
    if "modexp_layout_abstracted.spice" not in text:
        problems.append("committed netlist header does not cite its source extraction")
    return problems


CASES = (
    ("happy path: clean conversion, correct shape", case_happy_path),
    ("validation: two-output short is reported", case_multi_driver),
    ("validation: undriven cell input is reported", case_floating_input),
    ("validation: per-cell instance count vs extraction report", case_report_mismatch),
    ("validation: top-level pin count vs extraction report", case_pin_count_mismatch),
    ("hard error: X-card arity vs .SUBCKT arity", case_pin_arity_mismatch),
    ("committed modexp_post_route.v matches the extraction", case_committed_netlist_matches_extraction),
)


def main() -> int:
    if not CONVERTER.exists():
        print(f"FATAL: {CONVERTER} not found", file=sys.stderr)
        return 1

    print(f"== spice_to_verilog.py self-test ({len(CASES)} cases) ==")
    failures = 0
    for name, fn in CASES:
        problems = fn()
        if problems:
            failures += 1
            print(f"FAIL: {name}")
            for p in problems:
                print(f"  - {p}")
        else:
            print(f"OK:   {name}")

    print()
    if failures:
        print(f"FAIL: {failures}/{len(CASES)} self-test case(s) did not behave as specified")
        return 1
    print(f"PASS: all {len(CASES)} self-test cases behaved as specified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
