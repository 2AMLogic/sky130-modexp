# flow/report-power.tcl -- OpenROAD/OpenSTA `report_power` on the committed
# routed layout/modexp.def at ONE corner (issue #205, T1 item 8).
#
# Usage (from the repo root):
#   { echo "set pdk $HOME/.ciel/sky130A"; cat flow/report-power.tcl; } > /tmp/report-power.tcl
#   PDK_ROOT=$HOME/.ciel openroad -no_init -exit /tmp/report-power.tcl
# (`pdk` is a Tcl variable, not an env var, because the dockerized `openroad`
# wrapper does not forward the environment into the container.)
#
# Method and limits (stated again in the characterization report):
#   * corner: tt_025C_1v80 (the nominal corner of flow/par-modexp.json);
#   * clock: 100 MHz (10 ns), the ratified Phase 2 target, on port `clk`;
#   * activity: a STATED DEFAULT, not a simulated one -- every non-clock pin
#     (inputs, flop outputs, combinational nets) is assigned 0.1
#     transitions/clock with 0.5 duty via `set_power_activity -global`. The
#     clock net keeps its clock-derived activity. No VCD is read, so this is
#     not the activity of any real workload;
#   * parasitics: none annotated (no SPEF, no estimate_parasitics), so wire
#     capacitance is absent from the switching term. This understates
#     switching power; it is an estimate, not a signoff power number.
set lib "$pdk/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"
read_lef "$pdk/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__nom.tlef"
read_lef "$pdk/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef"
read_def layout/modexp.def
read_liberty $lib
create_clock -name clk -period 10.0 [get_ports clk]
set_power_activity -global -activity 0.1 -duty 0.5
puts "POWER_METHOD corner=tt_025C_1v80 clock_period_ns=10.0 global_activity=0.1 duty=0.5 parasitics=none"
report_power
report_power_metric
