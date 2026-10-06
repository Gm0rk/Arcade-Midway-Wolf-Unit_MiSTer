# Midway Wolf Unit for [MiSTer](https://github.com/MiSTer-devel/Main_MiSTer/wiki)

An FPGA implementation of the Midway Wolf Unit arcade board (1994-1997), the
TMS34010-based platform behind Mortal Kombat 3, Ultimate Mortal Kombat 3, WWF
WrestleMania, 2 On 2 Open Ice Challenge, NBA Hangtime and Rampage World Tour.

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
| Mortal Kombat 3 | mk3 (rev 2.1) + rev 2.0, 1.0, p4.0 | Awaiting hardware test, no sound yet |
| Ultimate Mortal Kombat 3 | umk3 (rev 1.2) + rev 1.1, 1.0 | Awaiting hardware test, no sound yet |
| WWF WrestleMania | wwfmania (rev 1.30) + rev 1.20, 1.1, proto 2.01 | Awaiting hardware test, no sound yet |
| 2 On 2 Open Ice Challenge | openice (rev 1.21) + rev 1.2A | Awaiting hardware test, no sound yet |
| NBA Hangtime | nbahangt (L1.3) + M1.3, L1.2, M1.2, L1.1, M1.1 | Awaiting hardware test, no sound yet |
| NBA Maximum Hangtime | nbamht (L1.03) + L1.0, M1.0, L0.9 | Awaiting hardware test, no sound yet |
| Rampage World Tour | rmpgwt (rev 1.3) + rev 1.1 | Awaiting hardware test, no sound yet |

Verified on hardware: `[░░░░░░░░░░░░░░░░░░░░]` 0 / 7

The DCS sound board is not in the core yet, so every game is silent; the
games still see a sound board that answers them and run normally.

The security chip is the development PIC every Wolf game accepts besides
its own, so the serial number on the boot screen is not the one printed on
the original board.

## Features

- Analog sync centred on a standard 15 kHz screen; CRT Adjust (H-Size,
  H-Position, V-Shift) and CRT Auto-Width for analog CRT output
- Video Timing in the OSD: the board's own 54.7 Hz, or 57 Hz / 60 Hz frames
  for TVs that do not hold 54.7 Hz. Only blank lines are dropped, so the
  whole picture is still sent; games run about 4 % (57 Hz) or 10 % (60 Hz)
  faster
- CMOS saved as NVRAM: settings, audits and high scores survive power-off
  (OSD "Save Settings")
- DIP switches in the OSD, taken from MAME
- Up to four players (Open Ice, NBA Hangtime) or three (Rampage)
- Pause (button or OSD), service mode switch; Service Credit and Tilt in the OSD

## Controls

| Game | Buttons |
|---|---|
| Mortal Kombat 3 / Ultimate MK3 | High Punch, Block, High Kick, Low Punch, Low Kick, Run |
| WWF WrestleMania | Punch, Defense, Power Punch, Kick, Power Kick |
| Open Ice / NBA Hangtime | Turbo, Shoot / Block, Pass / Steal; up to 4 players |
| Rampage World Tour | Jump, Punch, Kick; up to 3 players |

Every game also has Start, Coin, Test (service mode) and Pause. Service
Credit and Tilt are OSD items on the Controls page.

On the first start the CMOS is empty: the game restores its factory settings
and shows "Errors detected - any button to continue". Press a button, then
use OSD "Save Settings" to keep the CMOS.

## ROMs

ROM sets follow MAME 0.289. Put the zips (merged sets are fine, files are
found by CRC) in `games/mame`; NBA Maximum Hangtime uses `nbahangt.zip`. The
MRA files go in `_Arcade`, the core in `_Arcade/cores`. A 32 MB SDRAM module
is needed (the largest games use 25 MB of ROM).

## Credits and references

- MAME Wolf Unit driver and T-Unit video: Alex Pasadyn, Zsolt Vasvari,
  Ernesto Corvi, Aaron Giles (thanks to Kurt Mahan); MAME TMS34010 core, DCS
  and Midway IC emulation (Aaron Giles) - the reference for this core's
  behaviour
- Texas Instruments TMS34010 User's Guide
- SDRAM controller and MiSTer framework: Sorgelig and the MiSTer-devel team
- CRT Adjust: Umberto Parisi (rmonic79), with Andrea Bogazzi (@asturur)
- [Template_MiSTer](https://github.com/MiSTer-devel/Template_MiSTer),
  [MiSTer-CRT-Adjust](https://github.com/rmonic79/MiSTer-CRT-Adjust)

## License

GPL-3.0-or-later. Third-party modules keep their own licenses (see
`rtl/crt_adjust`).
