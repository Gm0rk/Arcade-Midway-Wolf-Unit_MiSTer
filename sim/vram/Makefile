# VRAM controller against the DDRAM port's rules, through resets:
# make && ./obj_dir/Vwunit_vram [clocks] [reset interval]   (see ../README.md)

RTL  = ../../rtl
SRCS = $(RTL)/wunit_vram.sv

obj_dir/Vwunit_vram: tb_vram.cpp $(SRCS)
	verilator --cc --exe --build -O2 --x-assign fast --x-initial fast --noassert \
		-Wno-fatal -Wno-WIDTH --public-flat-rw \
		--top-module wunit_vram $(SRCS) tb_vram.cpp \
		-CFLAGS "-O2 -std=c++17" -o Vwunit_vram

clean:
	rm -rf obj_dir
