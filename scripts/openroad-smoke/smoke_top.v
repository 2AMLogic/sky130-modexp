// Toolchain smoke-test fixture for scripts/openroad-smoke-test.sh (issue
// #13). A trivial, hand-written gate-level netlist (one sky130_fd_sc_hd
// buffer) -- not synthesized, not this repo's RTL, and not a measurement.
// It exists only to give OpenROAD's `link_design`/`initialize_floorplan` a
// structurally valid network to exercise, so the smoke test proves the
// pinned toolchain actually runs its Tcl engine end to end (LEF parse,
// netlist link, floorplan init, DEF write) rather than merely answering
// `-version`. P&R measurements against this repo's own `rtl/modexp.v` are
// issue #7's job, not this one's.
module smoke_top (input a, output y);
  sky130_fd_sc_hd__buf_2 buf0 (.A(a), .X(y));
endmodule
