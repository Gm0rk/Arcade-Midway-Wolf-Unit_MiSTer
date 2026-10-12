# Midway Wolf Unit for [MiSTer](https://github.com/MiSTer-devel/Main_MiSTer/wiki)

> **AI disclosure:** this core was developed with the help of an AI assistant
> (Claude, by Anthropic).

An FPGA implementation of the Midway Wolf Unit arcade board (1994-1997), the
TMS34010-based platform behind Mortal Kombat 3, Ultimate Mortal Kombat 3, WWF
WrestleMania, 2 On 2 Open Ice Challenge, NBA Hangtime and Rampage World Tour.

> **Status:** the core is currently undergoing testing. It can be compiled and is playable in its
> current state, but bugs are expected. Issues and pull requests are not
> accepted at the moment.

## Contents

- [Hardware](#hardware)
- [Games](#games)
- [Features](#features)
- [CRT Adjust](#crt-adjust)
- [Controls](#controls)
- [ROMs](#roms)
- [Credits and references](#credits-and-references)
- [License](#license)

## Hardware

| | |
|---|---|
| Main CPU | TMS34010 graphics system processor, 50 MHz master clock (6.25 MHz instruction clock) |
| Main RAM | 512 KB |
| Video | 512 x 512 x 16-bit frame store; DMA blitter with 1-8 bits per pixel, compressed rows, X/Y scaling, X/Y flip and clipping on all four edges |
| Palette | 32768 colours from 15-bit RGB |
| Display | 8 MHz pixel clock, 400 x 254 visible, 54.7 Hz |
| Sound | DCS: ADSP-2105 DSP at 10 MHz, 8K words of RAM, up to 8 MB of sound ROM, 16-bit DAC |
| Security | PIC16C57 giving the game ID and serial number |
| CMOS | 48 KB, battery backed |

## Games

| Game | MRA set | Status |
|---|---|---|
| [Mortal Kombat 3](docs/Mortal-Kombat-3.md) | mk3 (rev 2.1) + rev 2.0, 1.0, p4.0 | Awaiting hardware test |
| [Ultimate Mortal Kombat 3](docs/Ultimate-Mortal-Kombat-3.md) | umk3 (rev 1.2) + rev 1.1, 1.0 | Awaiting hardware test |
| [WWF WrestleMania](docs/WWF-WrestleMania.md) | wwfmania (rev 1.30) + rev 1.20, 1.1, proto 2.01 | Awaiting hardware test |
| [2 On 2 Open Ice Challenge](docs/2-On-2-Open-Ice-Challenge.md) | openice (rev 1.21) + rev 1.2A | Awaiting hardware test |
| [NBA Hangtime](docs/NBA-Hangtime.md) | nbahangt (L1.3) + M1.3, L1.2, M1.2, L1.1, M1.1 | Awaiting hardware test |
| [NBA Maximum Hangtime](docs/NBA-Hangtime.md) | nbamht (L1.03) + L1.0, M1.0, L0.9 | Awaiting hardware test |
| [Rampage World Tour](docs/Rampage-World-Tour.md) | rmpgwt (rev 1.3) + rev 1.1 | Awaiting hardware test |

Each game's page in `docs/` has its controls and the features that only it
has (hidden menus, Kombat Kodes, finishing moves).

Verified on hardware: `[░░░░░░░░░░░░░░░░░░░░]` 0 / 7

The [hardware test plan](docs/Testing.md) lists what each game has to pass
before it counts as verified, with the results so far.

The security chip is the development PIC every Wolf game accepts besides
its own, so the serial number on the boot screen is not the one printed on
the original board.

## Features

- DCS sound: the ADSP-2105 runs each game's own sound program from its
  sound ROMs, 16-bit mono at 31.25 kHz
- Analog sync centred on a standard 15 kHz screen; CRT Adjust (H-Size,
  H-Position, V-Shift), CRT Auto-Width and CRT V-Size (experimental) for
  analog CRT output (below)
- Video Timing in the OSD: the board's own 54.7 Hz, or 57 Hz / 60 Hz frames
  for TVs that do not hold 54.7 Hz. Only blank lines are dropped, so the
  whole picture is still sent; games run about 4 % (57 Hz) or 10 % (60 Hz)
  faster (the sound board keeps its own clock: music plays at its normal
  pitch and tempo)
- CMOS saved as NVRAM: settings, audits and high scores survive power-off
  (OSD "Save Settings")
- DIP switches in the OSD, taken from MAME, with Service Credit and Tilt
- Up to four players (Open Ice, NBA Hangtime) or three (Rampage)
- Pause (button or OSD), service mode switch
- Game extras entered from the OSD: hidden developer menus (MK3, UMK3, NBA
  Hangtime), UMK3's cut Character Endings restored, Kombat Kodes and
  finishing moves (MK3, UMK3); see each game's page
- Move List (MK3, UMK3): every fighter's special moves and finishing moves,
  picked by fighter in the OSD and shown over the game's logo
- Secret Codes (NBA Hangtime, Maximum Hangtime, Open Ice): every secret
  player, with who each one is, and every code the game has, shown over
  the game's logo from the OSD

## CRT Adjust

For an analog CRT (Video Settings, with no Scandoubler Fx): turn
"CRT Adjust" on and the picture can be sized and moved without the screen
losing sync. H-Size, H-Position and V-Shift work as their names say;
Auto-Width makes the picture fill a standard line's width and H-Size trims
from there.

"CRT V-Size" (experimental) changes the picture's height, 3 lines a step,
"+" taller. "CRT V-Size Mode" picks how:

- PVM: every line of the picture is shown once, with more or fewer lines
  in a frame. The line rate moves about 1 % a step, which broadcast
  monitors (PVM, BVM) follow; an arcade monitor or a TV may not
- Cabinet: the timing stays exactly the board's, and the picture is redrawn
  taller or shorter, blending neighbouring lines (slightly softer
  vertically). Safe on any monitor

A taller picture grows downwards; use V-Shift to centre it again. V-Size
uses the blank lines around the picture, so it has most room with the
board's own 54.7 Hz Video Timing: at 57 Hz the largest Cabinet steps lose
the bottom lines, and 60 Hz has hardly any blank lines to spare. Going
taller in PVM mode also leaves less room for V-Shift.

With CRT Adjust on, HDMI shows the adjusted picture too; turn it off for
the untouched HDMI picture.

## Controls

Each game's buttons are on its page in `docs/`. Every game also has Start,
Coin, Test (service mode) and Pause. Service Credit and Tilt are OSD items
on the DIP Switches page.

On the first start the CMOS is empty: the game restores its factory settings
and shows "Errors detected - any button to continue". Press a button, then
use OSD "Save Settings" to keep the CMOS.

## ROMs

ROMs are not included in this repository; use your own dumps of the
games. Sets follow MAME 0.289, and merged sets are recommended: one zip per
game holds every revision, so all its MRAs work from it (NBA Maximum
Hangtime is in `nbahangt.zip`). Files are found by CRC. Put the zips in
`games/mame`, the MRA files in `_Arcade` and the core in `_Arcade/cores`.
A 32 MB SDRAM module is needed (the largest games use 25 MB of ROM).

## Credits and references

- MAME Wolf Unit driver and T-Unit video: Alex Pasadyn, Zsolt Vasvari,
  Ernesto Corvi, Aaron Giles (thanks to Kurt Mahan); MAME TMS34010 core, DCS
  and Midway IC emulation (Aaron Giles) - the reference for this core's
  behaviour
- Texas Instruments TMS34010 User's Guide
- SDRAM controller and MiSTer framework: Sorgelig and the MiSTer-devel team
- CRT Adjust and CRT V-Size: Umberto Parisi (rmonic79), with Andrea Bogazzi
  (@asturur)
- Move List special moves: MAME's command.dat (Command List by Fabricio
  Coroquer, revised by AntoPISA); window font: the MiSTer OSD's
  (Main_MiSTer); backgrounds: the games' own logos (Midway)
- [Template_MiSTer](https://github.com/MiSTer-devel/Template_MiSTer),
  [MiSTer-CRT-Adjust](https://github.com/rmonic79/MiSTer-CRT-Adjust)

## License

GPL-3.0-or-later. Third-party modules keep their own licenses (see
`rtl/crt_adjust`).
