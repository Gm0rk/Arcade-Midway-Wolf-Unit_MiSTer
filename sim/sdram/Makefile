# SDRAM controller timing: make && ./obj_dir/Vsdram [clocks] [seed]
# (see ../README.md)

RTL  = ../../rtl
SRCS = $(RTL)/sdram.sv

obj_dir/Vsdram: tb_sdram.cpp $(SRCS)
	verilator --cc --exe --build -O2 --x-assign fast --x-initial fast --noassert \
		-Wno-fatal -Wno-WIDTH -DSDRAM_SIM --public-flat-rw \
		--top-module sdram $(SRCS) tb_sdram.cpp \
		-CFLAGS "-O2 -std=c++17" -o Vsdram

clean:
	rm -rf obj_dir
