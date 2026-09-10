// Compile-time defines for simulating against the sky130_fd_sc_hd Verilog
// cell models with SDF back-annotation. This file carries no design
// content -- it exists only because `klt functional-verification`'s
// request schema (`klt.functional_verification.request/1`) has no field
// for simulator build arguments / `+define+` macros (filed upstream; see
// `verification/gate-level/README.md`). Icarus compiles all
// `request.sources` into a single compilation unit in the order given, so
// listing this file *first* makes both macros visible to every later
// source, which is exactly what a `+define+` would have done.
//
// `FUNCTIONAL` is deliberately left UNDEFINED here -- the inverse of
// `verification/gate-level/sky130_fd_sc_hd_sim_defines.v` (Leg 1). SDF
// back-annotation (`options.sdf`) requires the cell models' `specify`-block
// timing branch, since that is the only branch an SDF's `IOPATH`/
// `INTERCONNECT` entries annotate. `klt functional-verification` rejects
// `options.sdf` combined with a `FUNCTIONAL` define as a request error, by
// design.
//
// `USE_POWER_PINS` stays undefined, matching Leg 1 (no PDN in this design).
