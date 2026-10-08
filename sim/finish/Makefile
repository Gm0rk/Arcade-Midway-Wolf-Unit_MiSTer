# Finishing move player on its own: make && ./obj_dir/Vwunit_finish [options]
# (see ../README.md)

RTL  = ../../rtl
SRCS = $(RTL)/wunit_finish.sv

obj_dir/Vwunit_finish: tb_finish.cpp $(SRCS) $(RTL)/wunit_finish_moves.vh
	verilator --cc --exe --build -O2 --x-assign fast --x-initial fast --noassert \
		-Wno-fatal -Wno-WIDTH -I$(RTL) \
		--top-module wunit_finish $(SRCS) tb_finish.cpp \
		-CFLAGS "-O2 -std=c++17" -o Vwunit_finish

clean:
	rm -rf obj_dir
