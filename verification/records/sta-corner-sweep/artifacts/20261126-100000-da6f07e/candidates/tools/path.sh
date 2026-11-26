#!/usr/bin/env bash
# usage: path.sh <name> [corner]  -> worst setup path detail
R=$(cd "$(dirname "$0")/.." && pwd); N=$1; C=${2:-ss_n40C_1v28}; P=$HOME/.ciel/sky130A/libs.ref/sky130_fd_sc_hd
cat > $R/.scratch/$N/path.tcl <<TCL
read_lef $P/techlef/sky130_fd_sc_hd__nom.tlef
read_lef $P/lef/sky130_fd_sc_hd.lef
read_def $R/.scratch/$N/layout/modexp.def
read_liberty $P/lib/sky130_fd_sc_hd__$C.lib
create_clock -name clk -period 10.0 [get_ports clk]
report_checks -path_delay max -format full -fields {fanout} -digits 2
exit
TCL
openroad -no_splash -exit $R/.scratch/$N/path.tcl
