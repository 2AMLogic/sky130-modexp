# Roadmap

`sky130-modexp` takes an RSA modular-exponentiation core from RTL to a
DRC/LVS-clean GDS on sky130 with the open digital flow, and reports every
place where klayout-tools (`klt`) gets in the way.

Status as of 2026-11-13, `main` @ `421e4b5`.

This page is the hand-written direction. `WORK_PLAN.md` is the generated
label snapshot, `WORK_LOG.md` the merge history, and
`verification/signoff/tier-report.json` the graded verdict of record; where
they disagree with this page on a fact, they win.

## Where it stands

The graded T1 report (`verification/signoff/tier-report.json`, regenerated
by `verification/signoff/run-signoff.sh`, checked in CI) reads **9 of 11
items met, 1 not applicable, 1 unmet**:

| T1 item | Verdict | Evidence |
|---|---|---|
| 1 Design sources | met | `rtl/modexp.v`, attested envelope (PR #269) |
| 2 Layout | met | `layout/modexp.gds` with its as-built netlist `layout/modexp.v` (#232) |
| 3 DRC clean | met | `layout/drc/modexp-drc-report.json`, 0 violations; deck gaps listed in `docs/signoff-claim.md` |
| 4 LVS clean | met | `status: match`, `power_connectivity: match` (#233, DR-0012) |
| 5 Full corner verification | **unmet** (`check_failed`) | 100 MHz closes at 10 of 18 corners; binding corner `ss_n40C_1v28` |
| 6 Statistical claims | not applicable | bound statement, no statistical spec row (PR #289) |
| 7 Post-layout verification | met | SDF-annotated gate-level regression (#236); `TIMINGCHECK` not annotated, disclosed |
| 8 Characterization report | met | `verification/signoff/evidence/characterization.md` |
| 9 Testbenches shipped | met | attested envelope (PR #269) |
| 10 Repo hygiene | met | attested envelope (PR #269) |
| 11 Power delivery (structural) | met | `layout/erc/modexp-erc-supply-report.json` plus item 4's power verdict (#235) |

Item 5 is the whole remaining gap, and it is a design limit rather than a
tool gap. Decision records 0002, 0004, 0005, 0007, 0011 and 0013 to 0016
record what was tried: a bit-serial re-spin closes 17 of 18 corners and was
declined (DR-0007); seven single-cycle carry-save Montgomery kernels reach
between 62 and 86 MHz at the binding corner and none closes 100 MHz. DR-0017
prices the next candidate, two pipelined column halves, at two cycles per
Montgomery iteration, and proposes a contingent supersession of DR-0001's
latency clause. DR-0017 is `proposed`; no RTL for it exists.

On the ladder in `spec/modexp.md`: RTL + bit-exact verification, synthesis
baseline, and DRC/LVS-clean GDS are evidenced; "place-and-route with timing
closure" is not, for the reason above. Shuttle seat and measured silicon
have not started (`measurements/` is empty).

## Now

Can start today. **Nothing can merge today**: CI on `main` has been red
since the `421e4b5` resync (#311), every open PR inherits that red, and the
fix (PR #313) is approved and held for a human merge.

1. **Land the CI fix.** PR #313 for #311. Done when the
   `Loom guard-hook regression suites` job is green on `main`. Waits on a
   human merge, not on agent work.
2. **Re-run the parked PRs on a green base.** PRs #309 (#308), #317 (#314),
   #318 (#315), #323 (#319), #324 (#321), #325 (#320). Done when each is
   updated from `main` after item 1 and its CI is green, or its review
   findings are answered. Blocked by #311.
3. **Bring the item 8 report in line with the item 4 verdict.** The Signoff
   row of `verification/signoff/evidence/characterization.md`, and the item
   8 row of `verification/signoff/README.md`, still report LVS `mismatch`
   and cite DR-0006/DR-0010. Done when both state the DR-0012 verdict, the
   envelope is regenerated, and `gen_characterization_envelope.py --check`
   and `run-signoff.sh --check` pass. No issue yet (seed 1).
4. **Correct the README status paragraph.** `README.md` still says a "fully
   clean DRC/LVS verdict" is open and cites "17/18 corners" for the shipped
   layout. Done when the paragraph matches `tier-report.json` (LVS met;
   10 of 18 corners on the committed layout) and links this page. No issue
   yet (seed 2).

## Next

- **Mint a fresh width-cross-check record through the artifact store**
  (#224). Done when a real `cross_check.py --mint-record` run writes a
  manifest whose every `uri` starts `artifact:` and `klt artifact verify`
  exits 0. Unblocked by #315 (PR #318), then by the operator's hold on #224.
- **Port the last two cocotb-Runner drivers to `klt
  functional-verification`** (#316, #322). Done when
  `gate_level_cross_check.py` runs through one `klt` request and reproduces
  the RTL `width-16` transcript byte for byte. #322 supersedes a
  signoff-cited record, so it follows #224's minting path.
- **Re-qualify the 18-corner P&R rebuild sweep** under open_pdks `f6eeac7`
  (#201). Done when a new `place-and-route` record supersedes
  `20260816-072918-d8eafca`, produced by one multi-corner `klt` request on
  the batch backend, never a hand loop. Blocked: the batch runner image has
  no `openroad` binary (park record on #201).
- **Finish parametrizing the flow tooling** (#211): the one remaining file,
  `flow/run-corner-sweep.sh`, is hash-pinned by that same live record.
  Unblocked by #201's superseding record, or by the operator choosing
  another option on #211.

## Later

- **Pipelined column halves (DR-0017).** Question first: is DR-0017
  ratified? If so, its own gates apply in order: a single-corner probe at
  `ss_n40C_1v28`, then RTL passing the bit-exact suite at every verified
  `WIDTH`, then the 18-corner sweep on both parasitic bases, then the cycle
  count re-measured.
- **Source of `R^2 mod m`.** DR-0017 leaves it unpriced. Question: a
  caller-supplied input (an interface change needing its own record) or
  on-chip modular doublings (the path that already fails in one cycle)?
- **Interleaved two-product exponentiation.** DR-0017 lists it unpriced; it
  would also remove the `popcount(exp_in)` latency dependence. Question:
  what does the second state set cost in cells and cycles?
- **`WIDTH=32`.** `spec/modexp.md` Decision 1 defers it until a bit-exact
  run at 32 passes with 0 mismatches. Question: does it pass unchanged, and
  can the record be minted (see #224)?
- **Shuttle seat, measured silicon.** Question: does item 5 close, or is
  the block submitted with the disclosed FAIL of DR-0004?

## Blocked and waiting

- **Human merge:** PR #313 (guard-hook wiring in `.claude/settings.json`).
- **Operator decisions:** DR-0017 ratification (EE key, market key, then
  operator; no tracking issue is open for it); #310 (remove the retired LVS
  control leg); #211 (how to handle the hash-pinned sweep script); #224
  (when the first mint campaign runs); #75 (merge-risk hold digest).
- **Infrastructure:** #201 (batch runner image lacks `openroad`); #184
  (audit host lacks Python and Icarus).
- **Tracker hygiene:** the body of epic #12 predates the current graded
  report; read `tier-report.json`, not the issue text.

## Not planned

- Lowering the 100 MHz target or dropping corners to make item 5 pass
  (DR-0004, DR-0007).
- Landing the 17-of-18 bit-serial re-spin (DR-0007).
- Any number-to-number comparison with externally published cell counts
  (`docs/baseline.md`, `CLAUDE.md`).
