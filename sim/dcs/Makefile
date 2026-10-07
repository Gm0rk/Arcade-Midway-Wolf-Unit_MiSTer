# DCS sound board against MAME: make && ./obj_dir/Vdcs_audio <image> <events> <out> [options]
# (see ../README.md)

RTL  = ../../rtl
SRCS = $(RTL)/adsp2105/adsp2105.sv $(RTL)/dcs_audio.sv

obj_dir/Vdcs_audio: tb_dcs.cpp $(SRCS)
	verilator --cc --exe --build -O3 --x-assign fast --x-initial fast --noassert \
		-Wno-fatal -Wno-WIDTH --public-flat-rw \
		--top-module dcs_audio $(SRCS) tb_dcs.cpp \
		-CFLAGS "-O2 -std=c++17" -o Vdcs_audio

clean:
	rm -rf obj_dir
