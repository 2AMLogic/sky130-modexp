# 0001: Input domain, out-of-domain behavior, interface contract, corner matrix, T1 mapping, and operating conditions

- **Status**: ratified
- **Date**: 2026-08-07
- **Decided by**: Builder (issue #6), extending `spec/modexp.md`

## Context

`spec/modexp.md` is ratified and authoritative, and this record does not
propose relaxing or amending any decision in it — per that document's own
Decision 3 ("update this document with a new decision record entry rather
than editing this one"), this is that successor record. It closes six
open gaps identified in issue #6:

1. The ratified Correctness row (`spec/modexp.md` line 20, restated as an
   absolute gate in the Constraints section, line 100) is unconditional —
   *"bit-exact vs `pow(b, e, m)`, randomized, on every commit"* — with no
   input-domain qualifier. `rtl/modexp.v`'s header comment carries an
   undocumented precondition instead: *"base_in < mod_in and mod_in > 1"*.
   This record ratifies the qualifier the spec was missing, backed by a
   reproducible measurement (below) rather than an assertion.
2. There is no ratified statement of what the block guarantees when that
   precondition is violated.
3. There is no ratified interface/port contract — the entire handshake,
   reset, and stability contract currently lives only in an `rtl/modexp.v`
   source comment and in the state-machine code itself.
4. There is no ratified `sky130_fd_sc_hd` corner matrix, despite the T1
   evidence checklist (`design-signoff` skill /
   `2AMLogic/klayout-tools/docs/design-evidence-tiers.md`, item 5) requiring
   one.
5. `spec/modexp.md`'s maturity ladder does not reference the four-tier
   evidence ladder the program actually grades blocks on, and two of that
   ladder's T1 items (schematic, post-layout simulation) have no stated
   digital reading.
6. No operating temperature/supply range is ratified, so the corner matrix
   in (4) has nothing to be consistent with.

**All numbers in this record are design targets pending a testbench** (per
`spec/modexp.md`'s own framing for its Decision 2/4) except where explicitly
marked *measured* — a measured figure below was produced by directly
re-running the cited reproduction command against `rtl/modexp.v` on this
branch, not asserted from the issue text.

## Decision 1 — Input domain

**Options considered:**

- **(a) Leave the spec unqualified**, treating the `rtl/modexp.v` source
  comment as sufficient documentation of the precondition. Rejected: a
  source comment is not ratified spec text, so a Builder or auditor
  checking the Correctness row literally has no authoritative answer, and
  `verification/test_modexp.py`'s stimulus generator silently enforcing the
  same domain (`mod = rng.randint(2, hi)`, `base = rng.randint(0, mod-1)`)
  means the regression that is supposed to gate every commit never tests
  the claim the spec actually makes.
- **(b) Widen the RTL to be correct for all inputs** (e.g. rework `mm_red`'s
  two-subtraction reduction to handle an unreduced multiplicand). Rejected
  for this record: that is an RTL change with its own cell-count and
  correctness-reverification cost, which is exactly the kind of decision
  `spec/modexp.md`'s Decision 3 reserves for a Phase 2 cell-count/timing
  cycle, not a documentation-scoped decision record. Recorded as a possible
  future direction, not committed to here.
- **(c) Qualify the Correctness row and the Constraints section's restatement
  of it, without editing `spec/modexp.md`'s text**, to state the domain
  explicitly. **Chosen.**

**Decision (ratified qualification, cited by and extending
`spec/modexp.md`, not replacing its text):**

> Bit-exact correctness against `pow(base, exp, mod)` — as stated in
> `spec/modexp.md`'s Correctness row and restated in its Constraints
> section — holds for inputs satisfying **`base_in < mod_in` and
> `mod_in > 1`** (the standard RSA message/modulus constraint). Outside
> that domain, see Decision 2 below. The pre-existing unqualified wording
> in `spec/modexp.md` overclaimed: as ratified, the design is not bit-exact
> against `pow` for arbitrary inputs, only for inputs in this domain, and no
> revision of `spec/modexp.md`'s own text is needed to say so — this record
> is the qualifier.

**Rationale — measured, not asserted:**

Re-running the reproduction recipe below against `rtl/modexp.v` on this
branch, WIDTH=8, 400 pseudo-random `(base, exp, mod)` triples with
`mod ∈ [2, 255]` and `base ∈ [mod, 255]` (i.e. `base >= mod`, out of the
domain above), seed 7:

```
WIDTH=8, base >= mod, 400 random cases, seed=7: 138 mismatches out of 400
  modexp(base=244, exp=29, mod=95) = 54, pow(...) = 9
  modexp(base=166, exp=217, mod=25) = 38, pow(...) = 6
  modexp(base=228, exp=63, mod=17) = 122, pow(...) = 5
  modexp(base=223, exp=203, mod=149) = 255, pow(...) = 106
  modexp(base=183, exp=73, mod=76) = 155, pow(...) = 31
  ...
```

138/400 mismatches (34.5%), captured by re-running
`verification/repro_out_of_domain_mismatch.py` (added by this record) on
this branch's `rtl/modexp.v`. Reproduce with:

```bash
python3 verification/repro_out_of_domain_mismatch.py
```

Within the domain in Decision 1's text, the design is already known-correct:
`docs/baseline.md` records 0 mismatches across `WIDTH` = 4, 6, 8, 16 at 500
random in-domain cases each via a deterministic Icarus cross-check, and
`verification/test_modexp.py`'s own randomized suite (which only ever
samples `base < mod`) passes on every commit. So the qualified claim in this
decision is exactly as strong as the ratified spec's original wording
intended — it is the *unqualified* claim that was never true.

**Consequences:** a Builder or auditor checking "is the Correctness row
satisfied" now has a ratified domain to check against instead of an
unwritten assumption. `verification/test_modexp.py` continues to test
exactly the domain this decision ratifies (no test change required by this
record). A future widening of the RTL to be domain-free (option (b) above)
would need its own decision record superseding this one's domain
qualification, plus a re-run of this reproduction showing 0 mismatches.

## Decision 2 — Out-of-domain behavior

**Options considered:**

- **(a) Undefined, caller's responsibility.** Cheapest — this is already the
  fielded RTL behavior, so choosing it costs zero additional cells or
  cycles. Its risk: a consumer might assume "garbage, but still `< mod_in`"
  is a safe fallback. The measurement above shows that assumption is false
  — e.g. `modexp(base=223, exp=203, mod=149)` returns **255**, which is not
  `< 149`; `modexp(base=228, exp=63, mod=17)` returns **122**, not `< 17`.
  So this option is only safe if paired with an explicit statement that the
  output is not range-bounded out of domain.
- **(b) An input-legality output flag** (e.g. an added `input_valid` output,
  combinationally asserting `base_in < mod_in && mod_in > 1`). Would let a
  consumer detect the violation without pre-checking inputs itself. Cost:
  unmeasured in this record (a WIDTH-bit magnitude comparator plus one
  output register — small relative to the existing design, but "small" is
  not a number and this record does not assert one; per `spec/modexp.md`
  Decision 3, any RTL/cell-count change is Phase 2 scope, not this record's).
  Would also need its own bit-exact regression update.
- **(c) An input pre-reduction stage** (reduce `base_in mod mod_in` before
  the main loop, and special-case `mod_in ∈ {0, 1}`). Would make the block
  correct (or at least well-defined) for a wider input set. Cost: an
  additional datapath stage — comparable in kind to the existing modular
  multiplier's reduction logic (`mm_red` in `rtl/modexp.v`), unmeasured in
  cells or cycles here, and it changes the exact latency formula in
  Decision 3. Also does not, by itself, resolve `mod_in ∈ {0, 1}` cleanly:
  `mod_in = 0` has no reference to be bit-exact against (`pow(b, e, 0)`
  raises in Python), so no RTL change makes that case "bit-exact" — only
  "well-defined," which is a different and weaker claim.

**Chosen: (a), undefined/caller's-responsibility, for Phase 2** — with the
range-boundedness caveat stated as ratified text, not left implicit.

**Decision:**

> For inputs outside Decision 1's domain (`base_in >= mod_in`, or
> `mod_in ∈ {0, 1}`), `modexp` provides **no correctness guarantee and no
> range guarantee**. `result` may not satisfy `result < mod_in`, and is
> **not** to be treated as "garbage but still a valid residue" by any
> consumer — the measurement above demonstrates outputs exceeding
> `mod_in`. Two useful facts about specific out-of-domain points, offered
> as documentation and not as guarantees: `mod_in = 1` happens to agree
> with `pow(base, exp, 1) == 0` for all sampled cases (both `base < mod`
> and `base >= mod`); `mod_in = 0` returns the unreduced product of the
> square-and-multiply computation (e.g. `modexp(5, 3, 0) = 125`), which has
> no Python `pow` reference value to be bit-exact against, so this case is
> intrinsically outside any bit-exact claim, not merely unverified.
>
> Options (b) (a legality flag) and (c) (input pre-reduction) remain
> available as future Phase 2 RTL work; neither is undertaken by this
> record, and either would require its own decision record plus a
> cell-count/cycle-cost measurement and a bit-exact regression update, per
> `spec/modexp.md` Decision 3.

**Rationale:** a properly-constructed RSA message is always `< modulus`,
and an RSA modulus is always `> 1`, by construction of the protocol this
block accelerates — so a correctly-integrated caller does not naturally
reach this domain. The cost of guarding against *misuse* is a Phase 2
tradeoff, not a documentation-scoped one, and `spec/modexp.md`'s ratified
scope for Phase 2 is cell-count/timing work on the existing core (Decision
3 and Decision 5 of that document), not a datapath redesign. Recording the
gap precisely (rather than silently) is this record's job; closing it, if
ever undertaken, is Phase 2 RTL work with its own record.

**Consequences:** any future consumer of `modexp` (including a future
integration issue) must pre-validate `base_in < mod_in && mod_in > 1`
itself if it cannot guarantee the domain by construction — this block will
not do it and will not fail safely (bounded output) if the caller doesn't.

## Decision 3 — Interface contract

**Options considered:**

- **(a) Leave the contract implicit** in the `rtl/modexp.v` header comment
  and state machine, as today. Rejected — issue #6's own dependents (the
  P&R issue and the gate-level-simulation issue) both need a `clock_port`
  name and a reset/timing contract without re-deriving it from source.
- **(b) Ratify a port table plus handshake/reset/stability contract in this
  record.** **Chosen.**

**Decision — port table** (every port of `modexp` as declared in
`rtl/modexp.v`; `WIDTH` is the module parameter, 16 primary per
`spec/modexp.md`'s ratified table):

| Port | Direction | Width | Domain | Function |
|---|---|---|---|---|
| `clk` | in | 1 | — | System clock. All sequential logic is `posedge clk`. |
| `rst_n` | in | 1 | `{0,1}`, active-low | Reset. See Reset contract below. |
| `start` | in | 1 | pulse | Assert for exactly one `clk` cycle, with `base_in`/`exp_in`/`mod_in` valid on that same cycle, to launch a computation. Sampled only while idle — see Handshake. |
| `base_in` | in | `WIDTH` | `[0, 2^WIDTH - 1]`; for a bit-exact guarantee, `base_in < mod_in` (Decision 1) | RSA base/message operand. |
| `exp_in` | in | `WIDTH` | `[0, 2^WIDTH - 1]` | Exponent operand. |
| `mod_in` | in | `WIDTH` | `[0, 2^WIDTH - 1]`; for a bit-exact guarantee, `mod_in > 1` (Decision 1) | Modulus operand. |
| `done` | out | 1 | pulse | Asserted for exactly one `clk` cycle, the cycle `result` becomes valid. |
| `result` | out | `WIDTH` | `[0, 2^WIDTH - 1]`; in-domain, `< mod_in` | `base_in ** exp_in mod mod_in`, valid the cycle `done` pulses; holds the previous result at all other times, including during a computation. |

**Reset contract:** `rst_n` is asynchronous-assert / effectively-
synchronous-observe, as coded (`always @(posedge clk or negedge rst_n)` in
`rtl/modexp.v`): any `negedge rst_n` immediately forces `state <= S_IDLE`,
`done <= 0`, `result <= 0`, and clears every internal register, independent
of `clk`. The RTL performs **no internal synchronizer** on the *release*
(rising) edge of `rst_n` — the block's contract assumes the integrator
supplies an `rst_n` whose release is already synchronized to `clk` (the
conventional external responsibility for this reset style); it does not
provide that synchronization itself. Guaranteed immediately after reset:
the core is idle (`state == S_IDLE`), `done == 0`, `result == 0`, and ready
to accept `start`.

**Handshake:** `base_in`/`exp_in`/`mod_in` need only be valid on the single
`clk` edge at which `start` is sampled high while idle — they are captured
into internal registers (`base_r`/`exp_r`/`mod_r` in `rtl/modexp.v`) and
need not remain stable afterward. `done` is a single-cycle pulse (the
`always` block's `done <= 1'b0;` default, overridden to `1'b1` only in the
`S_FINISH` state) the cycle `result` becomes valid.

**`start`-while-busy:** `start` is examined only in the `S_IDLE` case of
`rtl/modexp.v`'s state machine — a `start` pulse asserted during any other
state is silently dropped, not queued, and there is no `busy`/`ready`
output a caller can consult. This is reciprocally a hazard, not just an
"ignored input": if a caller holds `start` asserted continuously across the
cycle the core returns to `S_IDLE` (immediately after `S_FINISH`), the core
restarts immediately using whatever `base_in`/`exp_in`/`mod_in` are present
on the input ports at that moment — with no guarantee they match the
operands that produced the just-completed result. Upholding the one-cycle
pulse discipline on `start` is entirely the caller's responsibility,
unchecked by the RTL. This record documents the hazard; it does not add a
`busy` output to close it (that is RTL scope, per Decision 2's framing).

**Latency — exact, and data-dependent:** measured directly from the state
machine and cross-checked by simulation (`WIDTH=4`, five directed cases,
0 discrepancies against the formula below):

```
cycles(WIDTH, exp_in) = WIDTH*(WIDTH + 3) + popcount(exp_in)*(WIDTH + 2) + 2
```

counted from the `clk` edge at which `start` is sampled to the `clk` edge
at which `done` pulses. This ranges from `WIDTH*(WIDTH+3) + 2` cycles
(`exp_in == 0`, no multiply phases run) to `WIDTH*(2*WIDTH+5) + 2` cycles
(`exp_in` all-ones, every multiply phase runs) — `O(WIDTH^2)` at both
bounds, consistent with `verification/test_modexp.py`'s own
characterization of the core. **The latency is a side channel**: an
observer counting cycles to `done` learns `popcount(exp_in)` — partial
information about whichever operand this port is bound to in a given RSA
integration (which may be the private exponent). No constant-time
countermeasure is undertaken by this record; `spec/modexp.md`'s Phase 2
scope (Decision 3/5) is cell-count and timing-closure work on the existing
core, not a side-channel-hardened redesign. Recording the side channel
precisely is this record's job.

**Consequences:** downstream issues needing a `clock_port` name, a reset
contract, or a latency bound (the P&R and gate-level-simulation issues
referenced in issue #6's Dependencies section) can consume this table
directly instead of re-deriving it from `rtl/modexp.v`.

## Decision 4 — Corner matrix

**Options considered:**

- **(a) All eighteen installed `sky130_fd_sc_hd` liberty corners.**
  Exhaustive and guess-free: since these are discrete, pre-characterized
  files (not a continuous sweep an engineer interpolates), "cover all of
  them" requires no judgment call about which corner is actually
  worst-case for a given metric — a judgment call this record is not
  positioned to make correctly without an actual OpenSTA run (none exists
  yet; see Decision 5). **Chosen.**
- **(b) A hand-picked reduced subset** (e.g. nominal plus two "extreme"
  corners chosen by inspection of corner names). Rejected as the ratified
  requirement: guessing which of the eighteen is the true worst-case for
  setup/hold without running OpenSTA risks silently missing the actual
  worst corner, which is exactly the kind of unverified claim
  `spec/modexp.md`'s Constraints section and `CLAUDE.md` warn against. A
  reduced subset may still be useful for fast iteration once P&R exists,
  but that is an execution-time choice for issue #7, not a ratified
  requirement of this record.
- **(c) No ratified corner requirement beyond the nominal point.** Rejected
  — this is the status quo gap issue #6 reports (T1 item 5 requires a
  corner matrix; nominal-only does not satisfy it).

**Decision:** the ratified corner matrix for this block's timing and
gate-level functional results (T1 item 5) is all eighteen
`sky130_fd_sc_hd` liberty corners installed under the resolved sky130A PDK
(`libs.ref/sky130_fd_sc_hd/lib/`), confirmed present in this environment at
the time of this record:

```
sky130_fd_sc_hd__ff_100C_1v65.lib   sky130_fd_sc_hd__ss_100C_1v40.lib
sky130_fd_sc_hd__ff_100C_1v95.lib   sky130_fd_sc_hd__ss_100C_1v60.lib
sky130_fd_sc_hd__ff_n40C_1v56.lib   sky130_fd_sc_hd__ss_n40C_1v28.lib
sky130_fd_sc_hd__ff_n40C_1v65.lib   sky130_fd_sc_hd__ss_n40C_1v35.lib
sky130_fd_sc_hd__ff_n40C_1v76.lib   sky130_fd_sc_hd__ss_n40C_1v40.lib
sky130_fd_sc_hd__ff_n40C_1v95.lib   sky130_fd_sc_hd__ss_n40C_1v44.lib
sky130_fd_sc_hd__ff_n40C_1v95_ccsnoise.lib   sky130_fd_sc_hd__ss_n40C_1v60.lib
sky130_fd_sc_hd__tt_025C_1v80.lib   sky130_fd_sc_hd__ss_n40C_1v60_ccsnoise.lib
sky130_fd_sc_hd__tt_100C_1v80.lib   sky130_fd_sc_hd__ss_n40C_1v76.lib
```

The Decision 2 (of `spec/modexp.md`) 100 MHz Phase 2 target is held at the
**nominal corner, `tt_025C_1v80`** — the same corner already used, without
being separately ratified, by `docs/baseline.md`'s synthesis-baseline
recipe. Full closure across all eighteen corners is a T1 sign-off
requirement (Decision 5 below), not a per-commit Phase 2 gate: as context
for why this is tractable to defer without ambiguity, `klt synthesize`'s
contract fixes `timing` at `null` by design ("deferred to a future
OpenROAD/OpenSTA step" — see its `--help` text) — synthesis in this repo is
untimed by construction, so **no timing number of any kind, at any corner,
exists yet in this repo**; the entire corner axis lives in
`klt place-and-route`'s OpenSTA stage, which issue #7 introduces.

**Consequences:** issue #7 (place-and-route) and issue #9
(gate-level-simulation re-verification) can target this named corner set
directly. A future OpenSTA run across all eighteen corners becomes the
measured Fmax-per-corner table `spec/modexp.md` Decision 2's "achievable
Fmax" revisit trigger already anticipates; the nominal-corner 100 MHz
figure remains the one Decision 2 is held to until that run lands.

## Decision 5 — T1 evidence mapping

**Options considered:**

- **(a) Leave the T1 checklist unmapped**, letting each future issue infer
  its own digital reading of "schematic," "layout," and "post-layout
  simulation." Rejected — issue #6 reports this as a live gap; a
  P&R/gate-level-sim issue re-deriving its own reading independently risks
  two issues disagreeing about what "T1" means for this block.
- **(b) Map every T1 item to this block's digital flow explicitly, stating
  satisfied / not-yet-satisfied / not-applicable per item.** **Chosen.**

**Decision — per-item digital mapping** (`design-evidence-tiers.md`'s T1
checklist, items 1–10, `2AMLogic/klayout-tools`):

| # | T1 item | Digital reading for `modexp` | Status |
|---|---|---|---|
| 1 | Schematic + derived netlist | RTL (`rtl/modexp.v`) plays the schematic role; the Yosys-mapped gate netlist from `klt synthesize` plays the "netlist derived from them" role. The *generator* (RTL + the `docs/baseline.md` `klt synthesize` recipe) is committed, satisfying the checklist's "or generator" clause; the mapped netlist itself is regenerated on demand rather than checked in as a static artifact. | Satisfied (regenerable) |
| 2 | Layout | The merged GDS produced by `klt place-and-route` (OpenROAD). | Not yet produced — issue #7 |
| 3 | DRC clean | `klt drc` JSON report (`status: clean`, deck identified) against item 2's GDS. | Not yet produced — depends on #2 |
| 4 | LVS clean | `klt extract` on item 2's GDS, compared via `klt lvs` against the item-1 gate netlist. | Not yet produced — depends on #1/#2 |
| 5 | Full PVT corner sim vs. ratified spec | OpenSTA results (from `klt place-and-route`'s OpenSTA stage) across all eighteen corners named in Decision 4, checked against `spec/modexp.md`'s Clock row (100 MHz, held at `tt_025C_1v80` per Decision 4), with per-corner pass/fail recorded. | Not yet produced — issue #7 introduces the OpenSTA stage this requires |
| 6 | Statistical claims / Monte Carlo | **Not applicable.** `modexp` is a purely digital, bit-exact design. None of `spec/modexp.md`'s ratified spec rows (Operation, `WIDTH`, Correctness, Cell count, Clock, Signoff, Area) is a statistical, accuracy, offset, or matching claim of the kind Monte Carlo evidence validates. This block cannot produce T1 item 6 evidence because there is no statistical spec row for it to validate — stated explicitly here so a future tier claim does not leave this silently unaddressed. | Not applicable |
| 7 | Post-layout simulation | Gate-level simulation of the routed netlist (via `klt extract` from item 2's GDS, or the P&R stage's netlist output) driven through the existing `verification/test_modexp.py` cocotb suite via `klt functional-verification`. Initial post-layout simulation is **functional-only** (zero/unit-delay), not timing-annotated: it validates that the routed netlist's *logical* behavior still matches the pre-route RTL's bit-exact behavior, not gate/wire delay — timing correctness is item 5's job (static timing, not delay-annotated simulation). SDF back-annotation is not currently a defined capability of this toolchain's flow; if attempted and found missing, that is exactly the kind of tool-gap `CLAUDE.md`'s friction protocol calls for filing against `2AMLogic/klayout-tools`. | Not yet produced — issue #9 |
| 8 | Characterization report | A single aggregated document (e.g. an addition to `docs/baseline.md`, or a new `docs/characterization.md`) combining the cell count (already recorded), the item-5 corner-matrix timing table, and the item-3/4 DRC/LVS status once all exist. | Not yet produced — depends on #2–#5 |
| 9 | Testbenches shipped | `verification/test_modexp.py` + `verification/request-modexp.json`, cold-start via `klt functional-verification verification/request-modexp.json --format json` (`verification/README.md`). Gap: the sky130A PDK revision is documented in prose (`docs/baseline.md`'s `volare`-fetch recipe) but not machine-pinned in a checked-in lockfile as of this record — flagged, not fixed here (out of this record's scope). | Satisfied, with a noted hygiene gap |
| 10 | Repo hygiene | `README.md` states what the block is; `spec/modexp.md` is the spec table; `docs/baseline.md` and `verification/README.md` document reproduction; `LICENSE` (Apache-2.0) is present. Gap: no `.github/workflows/` CI exists as of this record's date, so "CI that at minimum keeps the harness and evidence formats valid" is **not** satisfied. Flagged, not fixed here — a CI-workflow issue is a natural, separately-scoped follow-up. | Partially satisfied |

**Rationale:** stating satisfied/not-yet/not-applicable per item, rather
than a single "T1 status" summary, is what lets a future tier claim be
checked item-by-item instead of asserted wholesale — matching the "Every
requirement below names an artifact that either exists, is fresh, and
passes — or doesn't" framing `design-evidence-tiers.md` itself uses.

**Consequences:** this block cannot claim T1 today (items 2–5, 7, 8 are
unsatisfied and item 10 is partial); it can name exactly what closes the
gap, and issues #7 and #9 (per issue #6's own Dependencies section) are the
consumers of items 2, 3, 4, 5, and 7 respectively.

## Decision 6 — Operating conditions

**Options considered:**

- **(a) Ratify only the nominal point** (`tt_025C_1v80`: 25 °C, 1.8 V) as
  the operating condition, treating the Decision 4 corner matrix as
  verification-only bookkeeping with no corresponding "operating range"
  claim. Rejected — this is exactly the gap issue #6 reports: "every later
  timing or functional result picks its own [range] and none of them
  compose" without a ratified range for the corner matrix to be checked
  against.
- **(b) Ratify the range already spanned by the Decision 4 corner matrix**
  as the block's operating conditions: −40 °C to 100 °C, nominal supply
  1.8 V with the corner set's characterized excursions (down to 1.28 V on
  the slow leg, up to 1.95 V on the fast leg). **Chosen.**
- **(c) A narrower commercial range** (e.g. 0–70 °C). Rejected as
  arbitrary — nothing in `spec/modexp.md` or the installed PDK's own
  corner selection motivates narrowing it, and doing so would mean
  discarding already-available, already-installed liberty corners from
  Decision 4 for no stated benefit.

**Decision:** this block's ratified operating conditions are **−40 °C to
100 °C**, nominal core supply **1.8 V**, with the corner-level supply
excursions characterized by the specific `sky130_fd_sc_hd` corners named in
Decision 4 (1.28 V–1.95 V across the slow/fast process legs). This is
deliberately the same range the corner matrix already covers, not an
independently chosen number — Decision 4 and Decision 6 are kept mutually
consistent by construction rather than one being derived from the other by
a future reader, which is the specific composition failure issue #6 flags.

**Rationale:** the installed `sky130_fd_sc_hd` corner set (Decision 4) is
exactly this range; ratifying a different range would either strand some
of the installed, already-available corners as "out of the ratified
operating range" for no reason, or require sourcing corners the PDK does
not ship.

**Consequences:** any future spec row with a PVT-dependent claim (e.g. a
timing closure result) is checked against this range by construction of
Decision 4's corner matrix — no separate reconciliation step is needed.

## Numbers in this record

Every specific figure in this record is one of: (1) a measurement, captured
by directly re-running the cited command against `rtl/modexp.v` on this
branch (the 138/400 mismatch count, the latency formula, the corner-file
list); or (2) a design target restated from `spec/modexp.md` (the 100 MHz
Phase 2 clock target), which remains, as that document already states,
"Neither has been attempted as of ratification" until the first OpenROAD
timing-closure run reports an achievable Fmax. No number in this record is
asserted without one of those two provenances.

No comparison to any external standard-cell library's cell count appears
in this record, consistent with `CLAUDE.md`'s overclaim-trap section and
`docs/baseline.md`.
