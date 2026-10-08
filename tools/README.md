# Tools

| File | Use |
|---|---|
| `mra_gen.py` | Writes `mra/` from MAME's `midwunit.cpp`; `--check ROMDIR` assembles every MRA from the zips the way Main_MiSTer does (md5 included) and compares it with MAME's regions; `--regions DIR` also compares with region dumps taken from MAME |
| `wunit_roms.py` | ROM image and configuration of a set, for the board simulation |
| `cut_content.py` | Program ROM patches for content a game left unreachable (UMK3: Character Endings in the EJB menu), found in the ROM by pattern; `mra_gen.py` puts them in the MRA as a patched copy of the program. `cut_content.py umk3 PROGRAM.BIN` lists them |
| `kombat_kodes.py` | MK3 / UMK3 Kombat Kodes: finds the game's state variable the core's kode player watches (`mra_gen.py` puts it in the MRA's config bytes 12-13) and checks the core's kodes (OSD page and the player's table) against the game's own kode tables. `kombat_kodes.py PROGRAM.BIN mk3\|umk3` lists an image's kodes, `--core` the core's |
| `finishing_moves.py` | MK3 / UMK3 finishing moves: reads them out of a program ROM's move tables (`finishing_moves.py PROGRAM.BIN mk3\|umk3` lists them and the core table they match; `mra_gen.py` puts that in the MRA's config byte 14), writes the core's programs (`--write UMK3.BIN MK3R10.BIN`: `rtl/wunit_finish_moves.vh` and the OSD lines), checks the OSD page (`--check`), lists the core's moves (`--list`), and plays them in MAME (`--mame WTUNIT ROMDIR SET OUTDIR [--rtl sim/finish/obj_dir/Vwunit_finish] [--winner 2] [--chars N,..] [--slots N,..] [--dists D,..\|label]`: every move at every distance, or at each end of its window and the middle (`label`); with `--rtl`, what the core's player holds frame by frame) |
| `frame_compare.py` | Compares simulator frames with MAME's (`--scan`), writes side-by-side PNGs |
| `dcs_trace.py` | The DCS sound DSP against MAME (`sim/dcs`): collapses MAME's trace and writes the host events for the simulator, compares the simulator's trace with it instruction by instruction, compares DAC word streams |
| `timing_paths.tcl` | `quartus_sta -t tools/timing_paths.tcl`: the 1000 worst setup paths of the last compile, without recompiling |
| `lua/dump_regions.lua` | MAME: dumps every ROM region it loaded |
| `lua/ref_trace.lua` | MAME: frames at chosen points, CRT controller / sound latch / blitter / control writes, timed button presses |
| `lua/bus_log.lua` | MAME: palette, blitter register, sound latch and UMK3 palette-ring writes with the time into the frame and the PC, in the format of the simulator's `-buslog` |
| `lua/finishing_moves.lua` | MAME: a two-player MK3 / UMK3 game to FINISH HIM, then each finishing move at each distance, with the game's result (for `finishing_moves.py --mame`) |
| `lua/dcs_trace.lua` | MAME: the DCS DSP's trace from power-on with its registers, the host's latch and reset writes, the DAC words |

## MAME reference build

MAME 0.289, headless subset with both Midway boards:

```
make SUBTARGET=wtunit SOURCES=src/mame/williams/midwunit.cpp,src/mame/williams/midtunit.cpp \
     NO_X11=1 NO_USE_XINPUT=1 NO_USE_PULSEAUDIO=1 NO_USE_PIPEWIRE=1 NO_USE_PORTAUDIO=1 \
     NO_USE_MIDI=1 USE_QTDEBUG=0 NOWERROR=1 TOOLS=0 -j2
```

Two local changes. The first, so its frames can be compared with the core's:
the serial PIC simulation (`src/mame/williams/midwayic.cpp`, `generate_serial_data`)
uses 0 for bytes 12 and 13 instead of `machine().rand()`, as the core does.
The two `rand()` calls stay, so nothing else draws different numbers.

A second, switchable change: with `WU_NO_UMK3_HACK` set in the environment,
`init_umk3` leaves out MAME's UMK3 palette-ring write penalty
(`umk3_palette_hack_w`), to see what the penalty does to the timing. Without
the variable MAME runs as released.

Reference runs always start from an empty CMOS: give MAME a fresh
`-nvram_directory` (`sim/board/run_ref.sh` does).

UMK3, NBA Hangtime and Rampage run their dumped PIC code in MAME, so their
boot screens show the real board's serial number; the core shows the
simulation's (123456).
