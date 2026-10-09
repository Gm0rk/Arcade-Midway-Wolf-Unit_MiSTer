# Simulation

Verilator 5. None of these folders is part of the core's file list.

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

`sim_top.sv` is the board, the DCS sound board and the real SDRAM
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

`-wav FILE` writes the sound board's DAC words (16-bit mono, 31250 Hz).
`tools/dcs_trace.py dac` compares them with MAME's (`tools/lua/dcs_trace.lua`
with `DCS_DAC`, same presses): the streams agree word for word as long as
the 34010 sends its sound commands in the same half buffer as MAME's.

## `dcs/` - the sound board against MAME's DSP

`tb_dcs.cpp` runs the DCS board (`rtl/dcs_audio.sv`, `rtl/adsp2105`) on its
own: the sound ROMs from the set's ROM image behind a fixed-latency channel
0, and the host side (latch writes, resets) played back from MAME, each at
the same instruction as there. `run_ref.sh` makes MAME trace the DSP from
power-on (`tools/lua/dcs_trace.lua`: every instruction with the registers
before it), drops the main loop's waits for the DAC buffer on the way (they
are most of the trace; the simulator drops them the same way, `-raw` keeps
them on both sides for short runs) and writes the events. `tools/dcs_trace.py
compare` then checks the simulator's trace instruction by instruction, every
register included, `dac` the DAC words.

`-host FILE` plays the host side by time instead, from a MAME run without
the trace (`dcs_trace.lua` with only `DCS_HOST` and `DCS_DAC`, full speed):
the way to check minutes of game sound. Commands then reach the DSP at
nearly, not exactly, MAME's instruction, so one that lands on the edge of
the main loop's check can be taken a half buffer apart.

```
sim/dcs/run_ref.sh wtunit ROMDIR mk3 ref/dcs 560 500 400:IN0:0010:5,500:IN2:0001:5
make -C sim/dcs
sim/dcs/obj_dir/Vdcs_audio simroms/mk3.rom ref/dcs/events.txt out/dcs.txt -samples out/dac.txt
python3 tools/dcs_trace.py compare ref/dcs/ref.txt out/dcs.txt
python3 tools/dcs_trace.py dac ref/dcs/dac.txt out/dac.txt
```

`run_ref.sh` arguments: end frame, the frame from which MAME logs every
register (before it only the latch, about five times faster; the PCs are
compared all the way), presses as `WU_PRESS`. MAME traces about 250,000
instructions a second (50,000 with the registers), so an emulated second of
the 10 MHz DSP takes a minute or more.

## `finish/` - the finishing move player

`tb_finish.cpp` runs `rtl/wunit_finish.sv` on its own: it writes a FINISH
HIM into the player through main RAM writes as the game makes them (state
variable, the player blocks, the fighters' objects and X positions, the
FINISH HIM state), picks a move and prints what the player then holds on
IN0 / IN1, one line a frame, and its OSD messages. `tools/finishing_moves.py
--mame ... --rtl sim/finish/obj_dir/Vwunit_finish` plays those frames in
MAME at the FINISH HIM of a real game (`tools/lua/finishing_moves.lua`) and
reads the game's result, for every move of a set, with either player
winning.

```
make -C sim/finish
sim/finish/obj_dir/Vwunit_finish -umk3 -opt 8 -char 15 -slot 0      # Kitana, Fatality 1
python3 tools/finishing_moves.py --mame wtunit ROMDIR umk3 out/finish --dists label \
        --rtl sim/finish/obj_dir/Vwunit_finish
```

`-opt` is the OSD's character option (its alphabetical list), `-char` the
winner's character as the game numbers it (`tools/finishing_moves.py`'s
`CHARS`), `-slot` the move (0-5, 6 the Mercy); `-table`, `-winner 2`,
`-left` (the winner faces left), `-nofinish` and `-kstate` change the rest.

## `crt/` - the analog CRT stage

`tb_crt.cpp` runs `rtl/video/wunit_crt.sv` (centred sync, CRT V-Size, CRT
Adjust, Auto-Width) on its own with the Wolf Unit raster (506 dots x 289
lines, the picture on dots 101-500 of lines 20-273, a dot every 12 clocks)
and a test picture whose colours say where each dot came from (R the
picture line, G/B the column). It prints each output frame (clocks, lines,
VSync lines, picture lines, shortest and longest line) and checks the last
frames against the settings: whole lines in order and the board's frame
time in PVM mode with 289 - 3n lines, the board's line timing in Cabinet
mode with the picture on 254 + 3n lines.

```
make -C sim/crt
sim/crt/obj_dir/Vwunit_crt -vsize 3 -frames 34              # PVM, 3 steps taller
sim/crt/obj_dir/Vwunit_crt -vsize -7 -cabinet -frames 34    # Cabinet, 7 steps shorter
sim/crt/obj_dir/Vwunit_crt -vsize 7 -change 30 0 -frames 60 # back to 0, ramping down
```

`-hsize`, `-hpos`, `-vshift`, `-autow`, `-off` set the rest of CRT Adjust,
`-vtot 277|263` the 57 / 60 Hz Video Timing frame. `-log FILE` writes every
output line (dots, a hash of them, first and last dot); built with
`-DNO_VSIZE` the testbench drives a stage without the V-Size ports, so two
builds of the stage can be compared line for line.

## `movelist/` - the Move List window

`tb_movelist.cpp` runs `rtl/wunit_movelist.sv` on its own with the Wolf
Unit raster (as `crt/`, the board's outputs changing with each dot) and a
test picture, and writes the picture that goes out to a PPM file.
`check.py` runs it for every page and compares each dot with the page as
`tools/move_list.py` lays it out (the test picture dimmed, the characters
in the OSD font on the grid), and once with the window off, where the
picture must come out unchanged.

```
make -C sim/movelist
python3 sim/movelist/check.py              # every page
sim/movelist/obj_dir/Vwunit_movelist 12 shang.ppm
```
