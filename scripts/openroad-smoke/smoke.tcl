# Toolchain smoke test for issue #13 (run by scripts/openroad-smoke-test.sh).
#
# Proves the pinned openroad/orfs container's `openroad` binary actually
# executes -- not merely that it answers `-version` -- by driving a real,
# small slice of the P&R Tcl API: reading the sky130hd platform LEF (which
# the openroad/orfs image ships), linking a trivial hand-written netlist
# (smoke_top.v), initializing a floorplan against it, and writing a DEF.
#
# This is deliberately NOT a P&R measurement run: the netlist is one
# hand-written standard-cell instance, not synthesized RTL, and none of its
# numbers (die area, utilization, instance count) are evidence about this
# repo's actual design. Real P&R measurements against rtl/modexp.v belong to
# issue #7.
read_lef $::env(PLATFORM_DIR)/lef/sky130_fd_sc_hd.tlef
read_lef $::env(PLATFORM_DIR)/lef/sky130_fd_sc_hd_merged.lef
read_verilog /workspace/smoke_top.v
link_design smoke_top

initialize_floorplan -die_area {0 0 200 200} \
                      -core_area {10 10 190 190} \
                      -site unithd

set die [ord::get_die_area]
puts "SMOKE-OK: die_area=$die"
puts "SMOKE-OK: block=[[ord::get_db_block] getName]"

write_def /workspace/smoke.def
puts "SMOKE-OK: wrote smoke.def"
