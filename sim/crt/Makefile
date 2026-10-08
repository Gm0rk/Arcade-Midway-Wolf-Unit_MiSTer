# The analog CRT stage on its own: make && ./obj_dir/Vwunit_crt [options]
# (see ../README.md)

RTL  = ../../rtl
SRCS = $(RTL)/video/wunit_crt.sv $(RTL)/video/sync_center.sv \
       $(RTL)/crt_adjust/crt_adjust.sv $(RTL)/crt_adjust/crt_vsize.sv

obj_dir/Vwunit_crt: tb_crt.cpp $(SRCS)
	verilator --cc --exe --build -O3 --x-assign fast --x-initial fast --noassert \
		-Wno-fatal -Wno-WIDTH -Wno-PINCONNECTEMPTY \
		--top-module wunit_crt $(SRCS) tb_crt.cpp \
		-CFLAGS "-O2 -std=c++17" -o Vwunit_crt

clean:
	rm -rf obj_dir
