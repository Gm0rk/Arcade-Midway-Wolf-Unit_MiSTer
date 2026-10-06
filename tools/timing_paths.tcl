# --------------------------------------------------------------------------
#
# timing_paths.tcl - the 1000 worst setup paths of the last compilation
#
# Reads the timing netlist Quartus left in db/ (no recompile) and writes
# output_files/worst_paths.txt: a summary of the 1000 worst setup paths
# (enough to show every failing group, not only the worst one), then
# the full detail of the 10 worst.
#
# Run from the project folder:
#   quartus_sta -t tools/timing_paths.tcl
#
# --------------------------------------------------------------------------

set revision "Arcade-Midway-Wolf-Unit"

project_open $revision -revision $revision
create_timing_netlist
read_sdc
update_timing_netlist

report_timing -setup -npaths 1000 -nworst 1 -detail summary \
	-file output_files/worst_paths.txt
report_timing -setup -npaths 10 -nworst 1 -detail full_path \
	-file output_files/worst_paths.txt -append

delete_timing_netlist
project_close
puts "timing_paths.tcl: output_files/worst_paths.txt written"
