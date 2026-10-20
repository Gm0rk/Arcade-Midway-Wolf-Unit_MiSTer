# Changelog

What changed in the Arcade-Midway-Wolf-Unit core, newest build first. Each build's changes are grouped by type: **Added**, **Changed**, **Fixed**, **Removed**, **Docs & tools**. Per-file detail for every build is in [COMMIT.md](COMMIT.md); hardware test results are tracked in [docs/Testing.md](docs/Testing.md).

Build numbers count the core's development builds in order. Released RBF files are named by date.

## Build 33 (2026-10-19)

**Docs & tools**
- README: the Games table is in alphabetical order with a title screen and a gameplay picture for each game; the status note adds that there are no releases until testing is complete; the link to the extra content document stays after the table.
- Every game's page starts with a link back to the README and the game's two pictures.

## Build 32 (2026-10-18)

**Added**
- Every game's page opens with an "Extra content" section: that game's overview from the extra content document, with a link to the full list.

**Docs & tools**
- `tools/extra_content.py` keeps the game pages' sections in step with `docs/Extra-Content.md` (`--write`, `--check`).

## Build 31 (2026-10-18)

**Docs & tools**
- New page `docs/Extra-Content.md`: everything the core adds, core-wide and game by game, linked from the README.
- UMK3 page: the Scorpion voice cut-off is said to happen in MAME, with the original board reported by MAME's developers.

## Build 30 (2026-10-18)

**Changed**
- Secret Menu (MK3, UMK3): "Open EJB Menu (Attract Mode)" has the note "Hidden Alternate Test Menu" under it.
- UMK3: the Secret Menu option "UMK3 Patched ROM" is now **Scorpion - Smoke Voice Fix**, with a gap above it and a note under it: "Get over here!" and "Come here!" cut off Fix. Same option and patches as before: the voice fix, and the Character Endings item back in the EJB menu.

**Docs & tools**
- UMK3 page: the section is "Scorpion - Smoke Voice Fix". Testing.md: Secret Menu page tests MK3-26 and UMK3-27; UMK3 test count corrected.

## Build 29 (2026-10-17)

**Docs & tools**
- This changelog, back to Build 1. Kept up to date with every build.

## Build 28 (2026-10-17)

**Fixed**
- UMK3: Scorpion's "Get over here!" and "Come here!" no longer cut off after "Get ov..." when the spear hits, with **UMK3 Patched ROM** set to On. Off by default: the cut-off is the game's own sound priority (the blood sounds take the voice's channel), the same in MAME and in all three UMK3 revisions.

**Changed**
- Secret Menu option "EJB Character Endings" is now **UMK3 Patched ROM**. It runs both patches: the cut Character Endings and the Scorpion voice fix.

**Docs & tools**
- UMK3 page: Patched ROM section. Testing.md: UMK3-26 (the spear).
- `tools/lua/fight_sound.lua`: plays a UMK3 fight in MAME and logs the sound commands and DAC words. `dcs_trace.lua` can inject sound commands; the DCS test bench has a real-time host mode.

## Build 27 (2026-10-17)

**Fixed**
- Timing: the clk_sys paths that failed Build 26's compile (worst -2.701 ns) are shortened or constrained. The compile now meets timing (worst setup +0.363 ns at the slow 100 C corner, clk_sys Fmax 99.47 MHz at the 96 MHz target).
- Nothing the games see changes. The sound DSP runs the same clocks per instruction; the blitter, SDRAM, Move List, CRT V-Size and finishing move blocks give the same results.

## Build 26 (2026-10-16)

**Fixed**
- Finishing Moves: the Mercy is entered for whoever won, whatever the Character option. It did nothing on MK3 rev 1.0 / p4.0 with Character at Cyrax, the default.
- MK3 1.x: Cyrax has no Mercy, so his Move List page has no Mercy row, and picking a move the winner does not have shows "The winner has no such move".
- SDRAM: the next command after a write waits 2 clocks more (it was under the chips' tRC and tDAL).
- A reset in the middle of play (USER button, OSD Reset) can no longer leave the DDR3 port hung by cutting a burst short.
- Sound: a command byte written in the clock the DSP reads its input latch is kept instead of lost.
- VRAM, palette read and blitter graphics-fetch handshakes are reset from one end only.

**Docs & tools**
- New SDRAM and VRAM test benches (`sim/sdram`, `sim/vram`).
- README: which CRT V-Size steps lose bottom lines at 57 Hz and 60 Hz.
- Testing.md: C13 (reset in a fight), C14 (an hour of play), MK3-25 (the Mercy on rev 1.0).

## Build 25 (2026-10-12)

**Changed**
- UMK3: DIP Switches in alphabetical order, like the other games (Attract Sound, Bill Validator, Blood, Coinage, Coinage Source, Counters, Service Credit, Test Switch, Tilt, Violence).

## Build 24 (2026-10-11)

**Changed**
- MK3 / UMK3 controller button order: High Punch, Low Punch, High Kick, Low Kick, Block, Run, Start, Coin, Test, Pause. The default pad mapping stays on the same physical buttons. MRAs regenerated.

## Build 23 (2026-10-11)

**Added**
- DIP Switches page for every game: MAME's switches as OSD options with MAME's defaults first, plus Service Credit and Tilt.
- Secret Codes pages with full names, drawn over each game's logo (NBA Hangtime and Maximum Hangtime: Page 1 / Page 2; 2 On 2 Open Ice Challenge: Secret Players 1-3). New logos for Open Ice, NBA Hangtime and Maximum Hangtime.

**Changed**
- OSD rearranged for every game: Video Settings, the game's items, DIP Switches, Secret Menu or Secret Midway Menu, Service Mode, Pause when OSD is Open, Reset, Reset and close OSD.
- Secret Midway Menu (Hangtimes) is an Off / On option that returns to Off once the code starts.

**Removed**
- The Controls page, and the DIP switches from every MRA (the OSD has them now).

**Docs & tools**
- OSD sections on the game pages; OSD and DIP tests for every game in Testing.md. Secret players' names come with their sources.

## Build 22 (2026-10-11)

**Added**
- MK3 / UMK3 Move List picked by fighter (Off or a fighter) and drawn over the game's own logo.
- MK3 / UMK3 DIP Switches page: MAME's switches as OSD options, plus Service Credit and Tilt.
- MK3 / UMK3 Secret Menu page: Open EJB Menu and EJB Character Endings.
- "Reset and close OSD" on the other games' main pages.

**Changed**
- MK3 / UMK3 OSD rearranged: Video Settings, Kombat Kodes, Move List, Finishing Moves, DIP Switches, Secret Menu, Service Mode, Pause when OSD is Open, Reset, Reset and close OSD.
- Ultimate Kombat Kodes listed on the Kombat Kodes page.

**Removed**
- DIP switches from the MK3 / UMK3 MRAs.

**Docs & tools**
- `tools/movelist_logo.py` writes the logos. Docs and Testing.md follow the new layout (MK3-23, 24; UMK3-24, 25).

## Build 21 (2026-10-10)

**Added**
- 2 On 2 Open Ice Challenge: Secret Codes from the OSD (secret players, Tonight's Game and face-off codes) shown over the paused game. WWF WrestleMania and Rampage World Tour have no codes.

**Docs & tools**
- `tools/openice_secrets.py` reads the lists from the program ROM. Open Ice page and tests OI-13 to 15.

## Build 20 (2026-10-10)

**Added**
- NBA Hangtime / NBA Maximum Hangtime: Secret Codes from the OSD (secret players and match-up codes) shown over the paused game.

**Docs & tools**
- `tools/hangtime_secrets.py` reads the lists from the program ROMs. NBA Hangtime page and tests NBA-19 to 21, NBAM-16 to 18.

## Build 19 (2026-10-09)

**Docs & tools**
- README: status note below the introduction (under testing, bugs expected, issues and pull requests not accepted for now).

## Build 18 (2026-10-09)

**Docs & tools**
- `docs/Testing.md`: the hardware test plan (core-wide and per-game tests, Pass / Fail, progress table), linked from the README.

## Build 17 (2026-10-09)

**Added**
- MK3 / UMK3 Move List: a window drawn over the dimmed, paused game with the picked fighter's special moves, Shang Tsung's morphs and finishing moves, with inputs and distances.

**Changed**
- Finishing move lines in the OSD show the move's name and input.

## Build 16 (2026-10-09)

**Fixed**
- Coin, Start, Test and Pause in WWF WrestleMania, 2 On 2 Open Ice Challenge, NBA Hangtime, NBA Maximum Hangtime and Rampage World Tour. They were read at the MK3 bit numbers, so there was no coin or start outside MK3 / UMK3.

## Build 15 (2026-10-09)

**Docs & tools**
- README ROMs section: merged sets recommended; ROMs are not in the repository.

## Build 14 (2026-10-09)

**Docs & tools**
- README split into a short overview plus one page per game in `docs/` (controls, hidden menus, Kombat Kodes, finishing moves).

## Build 13 (2026-10-08)

**Docs & tools**
- README: AI disclosure below the title.

## Build 12 (2026-10-08)

**Added**
- MK3's Ultimate Kombat Kode: Smoke (10902-22234), entered at game over. The Ultimate Kombat Kodes page now shows on MK3 too.

## Build 11 (2026-10-07)

**Docs & tools**
- README: table of contents. Committed and pushed as bd316d9.

## Build 10 (2026-10-07)

**Added**
- CRT V-Size (experimental): vertical size for analog CRTs, with PVM and Cabinet modes, in Video Settings with CRT Adjust on. Core-side; `sys/` untouched.

## Build 9 (2026-10-07)

**Fixed**
- Synthesis: Quartus error 10106 because the OSD string had passed 5000 bytes. The constant loop limit is now 16384.

## Build 8 (2026-10-07)

**Added**
- Finishing Moves for MK3 and UMK3 from the OSD: the picked character's move is entered on the round winner's controls at FINISH HIM, turned to the side the winner faces.

## Build 7 (2026-10-07)

**Changed**
- Kombat Kodes sorted into categories: Fight, Round 1 Winner Battles, Kombat Zone, Messages, Ultimate Kombat Kodes.

## Build 6 (2026-10-07)

**Added**
- The DCS sound board (ADSP-2105 core following MAME's driver): the games have sound.

**Removed**
- The silent DCS placeholder.

## Build 5 (2026-10-06)

**Added**
- Kombat Kodes for MK3 and UMK3 from the OSD (50 kodes).

## Build 4 (2026-10-06)

**Added**
- Hidden menus from the OSD: Open EJB Menu (MK3 / UMK3), Open Secret Midway Menu (NBA Hangtime / Maximum Hangtime).
- UMK3's cut Character Endings, in a patched program copy the MRA loads (EJB Character Endings).

## Build 3 (2026-10-06)

**Fixed**
- Timing closure at 96 MHz (Build 2 failed setup by 6.1 ns): the blitter does one multiply or wide sum per clock and the VRAM read completion is registered.
- UMK3 VOLUME ADJUST screen: the blitter's completion timer now counts from the command write, as MAME's does. It started late and the screen drew wrong.

**Changed**
- UMK3: MAME's palette-ring penalty (100 machine cycles per write to the ring pointers).

## Build 2 (2026-10-06)

**Fixed**
- Synthesis failure from Build 1 (Quartus error 10028: the blitter's divider register had two drivers).

## Build 1 (2026-10-06)

**Added**
- First build of the Wolf Unit core, from Arcade-Midway-Y-Unit at Build 13.
- Wolf board: memory map, 512 KB main RAM in SDRAM behind a cache, 48 KB NVRAM, I/O block, control register, security PIC simulation.
- The blitter, video and VRAM blocks for the T-Unit graphics.
- 7 games, 25 MRAs from MAME 0.289's midwunit.cpp (silent sound placeholder).
