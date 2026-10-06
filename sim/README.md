# Simulation

Verilator 5. Neither folder is part of the core's file list.

## `dma/` - blitter against MAME's code

`mame_dma.h` is MAME 0.289's `dma_w` / `dma_draw` with the template
arguments made run-time arguments. `tb_dma.cpp` drives `rtl/wunit_dma.sv`
through its register interface with random blits (every mode, 1-8 bpp,
skip compression, start / end skip in both forms, scaling, X/Y flip, both
clip banks, out-of-range offsets), a graphics ROM with random latency and a
model of the VRAM controller reading the row buffer, then compares the frame
store and the completion time with MAME's.

```
make && ./obj_dir/Vwunit_dma 3000 1              # tests, seed
./obj_dir/Vwunit_dma replay <seed> <18 registers> # one blit, as a failure prints it
```

## `board/` - the whole board

`sim_top.sv` is the board, the sound board placeholder and the real SDRAM
controller; `tb_board.cpp` adds an SDRAM chip model on the controller's
pins, a DDR3 bridge model and video capture. Frames come out as MAME's
`screen:pixels()` does, so `tools/frame_compare.py` compares them directly.

```
python3 tools/wunit_roms.py --mame MAME_SRC --roms ROMDIR --out simroms umk3
make -C sim/board
sim/board/obj_dir/Vsim_top simroms umk3 out/umk3 1,60,120,150,200 -press 150:in0:0010:5
sim/board/run_ref.sh wtunit ROMDIR ref umk3 1,60,120,150,200 150:IN0:0010:5
python3 tools/frame_compare.py --scan out/umk3 ref/umk3
```

Frame numbers line up with MAME's frame notifier (simulator frame n = MAME
frame n). `altsyncram.sv` is a behavioural model of the one megafunction the
core instantiates.

When a picture goes wrong in the simulator but not in MAME:

- `-buslog FILE A B` logs the CPU's palette, blitter register, sound latch
  and UMK3 palette-ring writes in frames A-B, each with the time into the
  frame and the PC, plus the blitter's interrupt (with the CPU's cycle debt)
  and the moment it has drawn; `tools/lua/bus_log.lua` writes the same from
  MAME
- `-pctrace FILE -pcframes A B` lists the PC of every instruction (and
  interrupt) retired in frames A-B; MAME's debugger gives the matching list
  (`-debug -debugger none`, `trace FILE,maincpu` from a Lua frame notifier)
- `-nopalring` leaves out the UMK3 palette-ring penalty, to compare with a
  MAME run under `WU_NO_UMK3_HACK`

The OSD's hidden-menu items: `-code F` enters the game's hidden menu code
from frame F (EJB Menu, Secret Midway Menu), `-alt` runs the patched
program copy (EJB Character Endings; `wunit_roms.py` adds the copy to the
image and its place to the .cfg). `-kode N@F` picks Kombat Kode N at frame F
(the OSD's "Kombat Kodes" line on status bit 18 + N, as
`tools/kombat_kodes.py --core` lists them); the player waits for its screen
through the state variable in the .cfg (`kode_state`) and the run prints its
OSD messages. The kode screens need a game in progress, so give the presses
too: MAME's frame numbers carry over (a fresh CMOS wants a button at frame
400, then coins, starts and the fighters, e.g. `-press 1300:in2:0001:5`).
