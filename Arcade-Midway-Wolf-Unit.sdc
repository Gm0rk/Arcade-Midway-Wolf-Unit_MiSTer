derive_pll_clocks
derive_clock_uncertainty

# core specific constraints

# TMS34010 (rtl/tms34010): its logic runs on every other clk_sys cycle
# (cpu_ce in rtl/midway_wunit.sv) and every register inside it changes only on
# an enabled edge, so paths from one of its registers to another have two
# clocks. Paths into it from the rest of the board keep the normal check.
set_multicycle_path -setup -end 2 -from [get_registers {*|tms34010:cpu|*}] -to [get_registers {*|tms34010:cpu|*}]
set_multicycle_path -hold  -end 1 -from [get_registers {*|tms34010:cpu|*}] -to [get_registers {*|tms34010:cpu|*}]

# HQ2x blender (sys/hq2x.sv, Blend, in the framework's scandoubler): every
# register in it loads on clk_en, the scandoubler's ce_x4i. With this core's
# pixel, one every 12 clk_sys cycles, ce_x4i comes every 3 cycles: at
# 3, 6 and 9 clocks into each pixel and at its start; the HSync edge that
# also restarts that count comes on a pixel boundary (the board's and the
# centred sync both change on the pixel enable, and a line is 506 pixels),
# so it lands on the same phase. Paths from one of its registers to another
# therefore have three clocks; two are claimed.
set_multicycle_path -setup -end 2 -from [get_registers {*|Hq2x:Hq2x|Blend:blender|*}] -to [get_registers {*|Hq2x:Hq2x|Blend:blender|*}]
set_multicycle_path -hold  -end 1 -from [get_registers {*|Hq2x:Hq2x|Blend:blender|*}] -to [get_registers {*|Hq2x:Hq2x|Blend:blender|*}]
