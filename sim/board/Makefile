# Full-board simulation: make && ./obj_dir/Vsim_top <rom dir> <set> <out> <frames> [options]
# (ROM images from tools/wunit_roms.py)

RTL  = ../../rtl
SRCS = $(RTL)/tms34010/tms34010_pkg.sv $(RTL)/tms34010/tms34010_muldiv.sv \
       $(RTL)/tms34010/tms34010_gfx.sv $(RTL)/tms34010/tms34010.sv \
       $(RTL)/wunit_dma.sv $(RTL)/wunit_vram.sv $(RTL)/wunit_video.sv $(RTL)/wunit_pic.sv \
       $(RTL)/midway_wunit.sv $(RTL)/dcs_stub.sv $(RTL)/sdram.sv ../altsyncram.sv sim_top.sv

obj_dir/Vsim_top: tb_board.cpp $(SRCS)
	verilator --cc --exe --build -O3 --x-assign fast --x-initial fast --noassert \
		-Wno-fatal -Wno-WIDTH -Wno-BLKSEQ -DSDRAM_SIM -I$(RTL)/tms34010 \
		--top-module sim_top $(SRCS) tb_board.cpp \
		-CFLAGS "-O2 -std=c++17" -o Vsim_top

clean:
	rm -rf obj_dir
