# Blitter test: rtl/wunit_dma.sv against MAME's dma_w / dma_draw (mame_dma.h)
#   make && ./obj_dir/Vwunit_dma [tests] [seed]

RTL = ../../rtl

obj_dir/Vwunit_dma: tb_dma.cpp mame_dma.h $(RTL)/wunit_dma.sv
	verilator --cc --exe --build -O3 -Wno-fatal -Wno-WIDTH \
		--top-module wunit_dma $(RTL)/wunit_dma.sv tb_dma.cpp \
		-CFLAGS "-O2 -std=c++17" -o Vwunit_dma

clean:
	rm -rf obj_dir
