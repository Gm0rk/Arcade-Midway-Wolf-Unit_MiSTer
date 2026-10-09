# The Move List window on its own: make && ./obj_dir/Vwunit_movelist [options]
# (see ../README.md)

RTL  = ../../rtl
SRCS = $(RTL)/wunit_movelist.sv
HEX  = $(abspath $(RTL))/wunit_movelist

obj_dir/Vwunit_movelist: tb_movelist.cpp $(SRCS) $(HEX)_row.hex $(HEX)_seg.hex $(HEX)_text.hex $(HEX)_font.hex
	verilator --cc --exe --build -O3 --x-assign fast --x-initial fast --noassert \
		-Wno-fatal -Wno-WIDTH \
		-GROW_HEX='"$(HEX)_row.hex"' -GSEG_HEX='"$(HEX)_seg.hex"' \
		-GTEXT_HEX='"$(HEX)_text.hex"' -GFONT_HEX='"$(HEX)_font.hex"' \
		--top-module wunit_movelist $(SRCS) tb_movelist.cpp \
		-CFLAGS "-O2 -std=c++17" -o Vwunit_movelist

clean:
	rm -rf obj_dir
