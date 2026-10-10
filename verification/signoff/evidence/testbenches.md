# Testbench inventory (T1 item 9)

The audited artifact for T1 item 9. `klt signoff` binds the sibling
`item-9-testbenches.json` attestation to the exact bytes of this file.
Paths are repo-root-relative. Environment: `./scripts/setup-env.sh &&
source .venv/bin/activate` (cocotb 2.0.1, Icarus Verilog), per
`docs/environment.md`, which also pins the PDK revision (`sky130A`,
`open_pdks` `c6d73a35f524070e85faff4a6a9eef49553ebc2b`).

## Claimed measurements and their testbenches

| Claim | Testbench | Cold-start invocation |
|---|---|---|
| Bit-exact `base^exp mod m` vs Python `pow`, RTL, `WIDTH=16` | `verification/test_modexp.py` (+ `verification/_dut.py`) | `klt functional-verification verification/request-modexp.json --format json` |
| Same, at `WIDTH` = 4, 6, 8, 16, 500 pinned-seed random cases each | `verification/cross_check_tb.py`, driven by `verification/cross_check.py` | `python3 verification/cross_check.py` (`npm run test`; run by CI job `cross-check`) |
| Same suite, unmodified, against the gate-level netlist derived from the routed layout, with net-delay SDF back-annotation | `verification/test_modexp.py` via `verification/gate-level/` (`gate_level_cross_check.py`, `request-modexp-gate-level.json`) | `./verification/gate-level/run-gate-level-sim.sh` (local; needs the sky130A PDK) |
| The gate-level netlist converter | `verification/gate-level/test_spice_to_verilog.py` | `python3 verification/gate-level/test_spice_to_verilog.py` (in `npm run lint`) |
| Evidence-record linter and pin-sync checker | `verification/test_check_records.py`, `verification/test_check_pins.py` | `npm run lint` (CI job `records`) |

## Claimed measurements with no testbench in the cocotb sense

DRC, LVS, `klt sta` corner timing and place-and-route metrics are
tool-run checks, not testbenches: their requests are committed
(`flow/*.json`, `layout/drc`, `layout/lvs`) and their results are
append-only records under `verification/records/`. They are out of this
inventory's claim.

## What CI runs

CI runs the RTL cross-check and the lint/self-tests. It does not run the
gate-level simulation, which needs the PDK and is run locally and recorded
(`verification/records/gate-level-sim/`).
