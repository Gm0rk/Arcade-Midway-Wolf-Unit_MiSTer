# Midway Wolf Unit for [MiSTer](https://github.com/MiSTer-devel/Main_MiSTer/wiki)

An FPGA implementation of the Midway Wolf Unit arcade board (1994-1997), the
TMS34010-based platform behind Mortal Kombat 3, Ultimate Mortal Kombat 3, WWF
WrestleMania, 2 On 2 Open Ice Challenge, NBA Hangtime and Rampage World Tour.

## Contents

- [Hardware](#hardware)
- [Games](#games)
- [Features](#features)
- [Hidden menus and cut content](#hidden-menus-and-cut-content)
- [Kombat Kodes](#kombat-kodes)
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
| Mortal Kombat 3 | mk3 (rev 2.1) + rev 2.0, 1.0, p4.0 | Awaiting hardware test |
| Ultimate Mortal Kombat 3 | umk3 (rev 1.2) + rev 1.1, 1.0 | Awaiting hardware test |
| WWF WrestleMania | wwfmania (rev 1.30) + rev 1.20, 1.1, proto 2.01 | Awaiting hardware test |
| 2 On 2 Open Ice Challenge | openice (rev 1.21) + rev 1.2A | Awaiting hardware test |
| NBA Hangtime | nbahangt (L1.3) + M1.3, L1.2, M1.2, L1.1, M1.1 | Awaiting hardware test |
| NBA Maximum Hangtime | nbamht (L1.03) + L1.0, M1.0, L0.9 | Awaiting hardware test |
| Rampage World Tour | rmpgwt (rev 1.3) + rev 1.1 | Awaiting hardware test |

Verified on hardware: `[░░░░░░░░░░░░░░░░░░░░]` 0 / 7

The security chip is the development PIC every Wolf game accepts besides
its own, so the serial number on the boot screen is not the one printed on
the original board.

## Features

- DCS sound: the ADSP-2105 runs each game's own sound program from its
  sound ROMs, 16-bit mono at 31.25 kHz
- Analog sync centred on a standard 15 kHz screen; CRT Adjust (H-Size,
  H-Position, V-Shift) and CRT Auto-Width for analog CRT output
- Video Timing in the OSD: the board's own 54.7 Hz, or 57 Hz / 60 Hz frames
  for TVs that do not hold 54.7 Hz. Only blank lines are dropped, so the
  whole picture is still sent; games run about 4 % (57 Hz) or 10 % (60 Hz)
  faster (the sound board keeps its own clock: music plays at its normal
  pitch and tempo)
- CMOS saved as NVRAM: settings, audits and high scores survive power-off
  (OSD "Save Settings")
- DIP switches in the OSD, taken from MAME
- Up to four players (Open Ice, NBA Hangtime) or three (Rampage)
- Pause (button or OSD), service mode switch; Service Credit and Tilt in the OSD
- Hidden menus opened from the OSD, and cut content restored (below)
- Kombat Kodes for MK3 and UMK3 entered from the OSD (below)

## Hidden menus and cut content

Some games hide menus behind button codes. The OSD can enter the code for
you; the menu then works with the normal controls.

- **EJB Menu** (Mortal Kombat 3, Ultimate MK3, every revision): the
  developers' test menu. OSD "Open EJB Menu" while the game is in attract
  mode (by hand: P1 Block x5, P2 Block x10, P1 Block x3, P2 Block x1, P1
  Block x2, P2 Block x2, P1 Block x3, P2 Block x3). It adds extra audits,
  the full credits, the "Penacho/Miller" Galaga-style game and, in MK3,
  Character Endings and Smoke on/off; in UMK3, the hidden characters
  (Mileena, Ermac, Classic Sub-Zero) on/off and a fatality demonstration.
  MK3 revisions 1.0 and p4.0 have an unfinished "Hello" screen in place of
  the credits.
- **EJB Character Endings** (Ultimate MK3, OSD option): UMK3 dropped MK3's
  Character Endings item from its EJB menu, but the item and its submenu
  (Kano to Smoke) are still in the ROM, and the endings' stories are the
  game's own. With the option on, the EJB menu has the item back and each
  ending shows its story before the cast roll. The core runs a patched
  copy of the program ROM that the MRA loads next to the original;
  changing the option restarts the game.
- **Secret Midway Menu** (NBA Hangtime, NBA Maximum Hangtime, every
  revision): statistics pages meant for Midway's staff (dunks, play time,
  game averages, team picks, the stored initials with their PINs). OSD
  "Open Secret Midway Menu", best in attract mode (by hand: both players
  hold Up and all three buttons, then Down; on the design team screen that
  follows, P1 Turbo x2, P2 Shoot x3, P2 Pass x2, P1 Shoot, P1 Pass, P2
  Turbo x2, P1 Turbo x4). A button turns the page; after the last page the
  game restarts.

## Kombat Kodes

Mortal Kombat 3 and Ultimate MK3 take Kombat Kodes on the VS screen before
a two-player fight: each player steps three icons with Low Punch, Block and
Low Kick, and the six digits (player 1's three, then player 2's) switch
something on for the fight. The OSD page "Kombat Kodes" enters them for
you. Pick a kode at any time in a two-player game; a message says it is
waiting, and at the next VS screen the core presses the buttons as the two
players would. The game then shows the kode's message under the fighters.
A kode picked when the VS screen is nearly over waits for the next one.
With "Pause when OSD is open" on (the default), the game waits while you
choose, so you can also open the OSD once the VS screen is up.

Every kode on the page comes from the game's own kode table, the same in
all arcade revisions. Kodes listed for the home versions (239-494,
978-243, 972-279, 432-234) are not in the arcade games. On MK3 the page
shows only MK3's kodes.

| Kode | Message / effect | Game |
|---|---|---|
| 100-100 | Throwing disabled | both |
| 020-020 | Blocking disabled | both |
| 987-123 | No powerbars | both |
| 466-466 | Unlimited run | both |
| 688-422 | Dark Kombat | both |
| 460-460 | Randper Kombat (fighters morph at random; UMK3 also takes 444-444) | both |
| 985-125 | Psycho Kombat: Dark and Randper Kombat, flickering powerbars, unlimited run, no blocking, fast uppercut recovery | both |
| 033-000 / 000-033 | Player 1 / player 2 half power | both |
| 707-000 / 000-707 | Player 1 / player 2 quarter power | both |
| 044-440 | "Unikoriv Referri: Sans Power": both players start with a sliver of energy | UMK3 |
| 788-322 | Fast uppercut recovery | UMK3 |
| 010-010 | Throwing encouraged | UMK3 |
| 300-300 | Silent Kombat (no music) | UMK3 |
| 227-227 | Explosive Kombat (2 on 2 mode only) | UMK3 |
| 022-220 | Explosive Kombat with throwing disabled (2 on 2 mode only) | UMK3 |
| 642-468 | "You are entering the Land of Rellim": the hidden Galaga-style game | both |
| 969-141 / 033-564 / 769-342 / 205-205 | The winner of the round battles Motaro / Shao Kahn / Noob Saibot / Smoke | both |
| 880-088 ... 050-050 | Kombat Zone: the fight's stage (16 stages, listed on the page) | UMK3 |
| 987-666, 282-282, 123-926 | Messages: "Hold flippers during casino run", "No Fear = EB button, skydive, max countdown", "There is no knowledge that is not power" | both |
| 999-999 | The game's revision | UMK3 |
| 550-550, 717-313, 448-844, 122-221, 004-400 | More messages: "See the Mortal Kombat live tour !!", "Rain can be found in the Graveyard", and three signed by the team | UMK3 |

**Ultimate Kombat Kodes** (Ultimate MK3). At game over, while Mileena,
Ermac or Classic Sub-Zero is still locked, the game asks for an Ultimate
Kombat Kode: ten icons, each player stepping five with High Punch, Low
Punch, Block, Low Kick and High Kick. Pick one on the page before the game
ends and the core enters it on that screen; the game unlocks the character
and keeps it in its CMOS (use OSD "Save Settings" to keep it on the SD
card).

| Kode | Unlocks |
|---|---|
| 22264-22264 | Mileena |
| 12344-44321 | Ermac |
| 81835-81835 | Classic Sub-Zero |

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
