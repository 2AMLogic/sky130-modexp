# Characterization report (T1 item 8)

The audited artifact for T1 item 8. `klt signoff` binds the sibling
`item-8-characterization.json` attestation to the exact bytes of this file;
`gen_characterization_envelope.py --check` fails CI if this file changes
without the envelope and the manifest pin being regenerated. Paths are
repo-root-relative.

This report **aggregates committed evidence; it measures nothing itself**
except the power estimate in section 4, whose own record is appended under
`verification/records/power-estimate/`. Every verdict names the record it
rests on. It compares no figure with any external design's numbers
(`docs/baseline.md`).

Design under test: `modexp`, `WIDTH=16` primary, sky130A
(`open_pdks f6eeac7dad085ffcc829ccfd721f7b4ce39edcf7`), routed layout
`layout/modexp.def` (`sha256:a35b956766144fe5df7addabf77a35b1df6645edaf62e05ec2d1891eaaa0b87a`).

## 1. Spec rows (`spec/modexp.md`, ratified table)

A row the ratified spec leaves without a bound is reported as **reported, no
ratified bound**; it is not graded pass or fail.

| Spec row | Ratified bound | Measured | Verdict | Record |
|---|---|---|---|---|
| Operation | `base^exp mod m`, square-and-multiply | Implemented; exercised by the correctness rows below | pass | `verification/records/width-cross-check/records/20260815-073109-564b598.md` |
| `WIDTH` | 16 primary; 4/6/8 verified bit-exact | `WIDTH` = 4, 6, 8, 16 verified; 32 deferred (Decision 1) | pass | `verification/records/width-cross-check/records/20260815-073109-564b598.md` |
| Correctness | bit-exact vs `pow(b, e, m)`, randomized | RTL: 2000/2000 match, 0 mismatches (500 per `WIDTH`). Zero-delay gate-level: 2/2 tests pass. SDF-annotated gate-level: pass (partial annotation, see item 7) | pass | `verification/records/width-cross-check/records/20260815-073109-564b598.md`, `verification/records/gate-level-sim/records/20260923-054800-e26f603.md`, `verification/records/gate-level-sim/records/20261016-010100-713829b.md` |
| Cell count @ `WIDTH=16` | none (Decision 3) | 717 instances / 7144.352 µm² from `klt synthesize` under the pinned klt; the routed layout follows the frozen 683-cell netlist | reported, no ratified bound | `verification/records/synthesis-baseline/records/20261015-205100-4d8d397.md`, `verification/records/synthesis-baseline/records/20261015-210722-a4653a5.md` |
| Clock | 100 MHz (Phase 2 target) | Closes at 10 of 18 corners; binding corner `ss_n40C_1v28` at 22.80 MHz (section 2) | **fail**, disclosed | `verification/records/sta-corner-sweep/records/20260923-093000-28a7c96.md` |
| Signoff | DRC + LVS clean on the OpenROAD-produced GDS | DRC: `status: clean`, 0 violations. LVS: `status: mismatch` | DRC pass, LVS **fail** | `layout/drc/modexp-drc-report.json`, `layout/lvs/modexp_lvs_report.json`, `spec/decision-records/0006-lvs-item-4-stays-unmet-for-the-current-pin-and-every-pr-run-commits-its-as-built-netlist.md`, `spec/decision-records/0010-lvs-evidence-regenerated-with-the-pinned-klt-power-connectivity-measured-mismatch.md` |
| Area | none (Decision 4) | Section 3 | reported, no ratified bound | `verification/records/place-and-route/records/20261015-205402-4d8d397.md` |

The stretch column (Montgomery variant, `WIDTH=32`, 500 MHz, formal
equivalence) is not claimed; Decisions 1, 2 and 5 of `spec/modexp.md` carry
the deferrals.

## 2. Fmax across the 18-corner set

Source: `verification/records/sta-corner-sweep/artifacts/20260923-093000-28a7c96/sta-corner-sweep-results.json`
(record `20260923-093000-28a7c96`), one `klt sta` envelope over the
committed routed DEF, clock constraint 10.0 ns (100 MHz). This is the same
envelope T1 item 5 cites. Setup slack is at the 100 MHz constraint; Fmax is
the frequency at which that corner's worst setup slack reaches zero.

| Corner | Fmax (MHz) | Setup slack (ns) | Hold slack (ns) | 100 MHz |
|---|---|---|---|---|
| ff_100C_1v65 | 233.606 | 5.71928 | 0.2886 | closes |
| ff_100C_1v95 | 301.929 | 6.68796 | 0.22954 | closes |
| ff_n40C_1v56 | 178.825 | 4.40793 | 0.32615 | closes |
| ff_n40C_1v65 | 207.112 | 5.17169 | 0.2885 | closes |
| ff_n40C_1v76 | 240.865 | 5.84829 | 0.2535 | closes |
| ff_n40C_1v95 | 295.366 | 6.61437 | 0.21354 | closes |
| ff_n40C_1v95_ccsnoise | 295.366 | 6.61437 | 0.21354 | closes |
| tt_025C_1v80 | 177.534 | 4.36728 | 0.34559 | closes |
| tt_100C_1v80 | 182.58 | 4.52294 | 0.35414 | closes |
| ss_100C_1v40 | 61.6053 | -6.23238 | 1.0114 | fails |
| ss_100C_1v60 | 90.2278 | -1.08306 | 0.70005 | fails |
| **ss_n40C_1v28 (binding)** | **22.7963** | **-33.8669** | 2.06884 | fails |
| ss_n40C_1v35 | 33.0805 | -20.2293 | 1.49805 | fails |
| ss_n40C_1v40 | 40.9362 | -14.4282 | 1.23763 | fails |
| ss_n40C_1v44 | 47.4957 | -11.0545 | 1.0908 | fails |
| ss_n40C_1v60 | 75.7193 | -3.20668 | 0.71521 | fails |
| ss_n40C_1v60_ccsnoise | 75.7193 | -3.20668 | 0.71521 | fails |
| ss_n40C_1v76 | 105.745 | 0.54332 | 0.54051 | closes |

100 MHz closes at 10 of 18 corners; hold is non-negative at all 18. The
binding (slowest) corner is `ss_n40C_1v28`. A later run of the same sweep
(`verification/records/sta-corner-sweep/records/20261015-205405-4d8d397.md`)
reproduces every figure above bit-for-bit on the re-pinned PDK.

The item 5 disclosure is carried here verbatim from
`verification/signoff/README.md`, not restated:

> This is a disclosed, bounded FAIL carried against an unamended ratified Clock row, ratified as `spec/decision-records/0004-…`; it is deliberately **not** closed by lowering the target, and the decision record prices the measured route to 18/18.

The follow-on decisions are `spec/decision-records/0005-the-priced-exit-was-run-and-does-not-reproduce.md`
and `spec/decision-records/0007-the-17-of-18-bit-serial-re-spin-is-declined-not-planned.md`
(status `proposed`, ratification pending).

## 3. Area

| Quantity | Value | Source |
|---|---|---|
| Synthesized cell area (`klt synthesize`, unconstrained) | 7144.352 µm² (717 instances; sequential 3254.3712 µm²) | `verification/records/synthesis-baseline/records/20261015-205100-4d8d397.md` |
| Die area (routed layout) | 21969.2 µm² | `verification/records/place-and-route/records/20261015-205402-4d8d397.md` |
| Core area (routed layout) | 19398.6 µm², utilization 39.3124 % | `verification/records/place-and-route/records/20261015-205402-4d8d397.md` |
| Routed components | 3074 (265 tapcells, 2087 fillers) | `verification/records/place-and-route/records/20261015-205402-4d8d397.md` |

The synthesized and the routed figures are different quantities (the routed
layout follows the frozen 683-cell netlist and adds tap and filler cells);
they are not interchangeable. No area bound is ratified (Decision 4).

## 4. Power

One new measurement, recorded as
`verification/records/power-estimate/records/20261017-192500-8c11c62.md`.

| Item | Value |
|---|---|
| Method | OpenROAD `report_power` (`flow/report-power.tcl`) on the routed `layout/modexp.def`, `openroad 26Q3-1510-g6cb3f2b704` |
| Corner | `tt_025C_1v80` only |
| Clock | 100 MHz (10 ns) on `clk` |
| Activity | stated default: `set_power_activity -global -activity 0.1 -duty 0.5` on every non-clock pin; no VCD, no workload |
| Parasitics | none annotated (no SPEF, no `estimate_parasitics`) |
| Total | **1.07 mW** (internal 0.875 mW, switching 0.193 mW, leakage 3.2 nW) |
| Split | sequential 0.584 mW (54.7 %), clock network 0.393 mW (36.8 %), combinational 0.091 mW (8.5 %) |

Limits: this is an estimate under an assumed activity, not the power of a
real workload and not a signoff number. Wire capacitance is absent from the
switching term, so switching power is understated. One corner only; power at
the other 17 corners is out of scope here. There is no ratified power bound,
so the figure is **reported, no ratified bound**.

For reference, the item 5 `klt sta` envelope carries `estimated_power_mw`
at every corner under OpenSTA's default activity (0.9307 mW at
`tt_025C_1v80`, 0.3169 mW to 1.137 mW across the 18 corners). Those values
use a different, unstated-to-the-user activity default and are not the
figure above.

## 5. What this report does not cover

- Statistical (Monte Carlo) behaviour: the ratified spec has no statistical
  row (T1 item 6, stated in `verification/signoff/README.md`).
- Silicon measurements (`measurements/`).
- Any comparison with an external design's published numbers
  (`docs/baseline.md`).
