# Hardware test plan

What has to work on a real MiSTer before the core is done. Each test is
marked **Pass** or **Fail** in its Result column; an empty Result is not
tested yet. A game counts as verified on the main page when every test in
its section passes; the core is done when all seven games and the
core-wide tests pass.

The core-wide tests need doing once, on any game (UMK3 is a good one: it
uses every part of the board). The tests under each game are about that
game; its alternative sets only need to boot and play.

## Contents

- [Progress](#progress)
- [Before you start](#before-you-start)
- [Core-wide](#core-wide)
- [Mortal Kombat 3](#mortal-kombat-3)
- [Ultimate Mortal Kombat 3](#ultimate-mortal-kombat-3)
- [WWF WrestleMania](#wwf-wrestlemania)
- [2 On 2 Open Ice Challenge](#2-on-2-open-ice-challenge)
- [NBA Hangtime](#nba-hangtime)
- [NBA Maximum Hangtime](#nba-maximum-hangtime)
- [Rampage World Tour](#rampage-world-tour)

## Progress

| Section | Passed | Tests | Status |
|---|---|---|---|
| Core-wide | 0 | 12 | Not started |
| Mortal Kombat 3 | 0 | 24 | Not started |
| Ultimate Mortal Kombat 3 | 0 | 25 | Not started |
| WWF WrestleMania | 0 | 14 | Not started |
| 2 On 2 Open Ice Challenge | 0 | 16 | Not started |
| NBA Hangtime | 0 | 22 | Not started |
| NBA Maximum Hangtime | 0 | 19 | Not started |
| Rampage World Tour | 0 | 12 | Not started |

Status: Not started, In progress, Verified (every test passes).

## Before you start

- Merged ROM sets in `games/mame`, the MRAs in `_Arcade`, the core in
  `_Arcade/cores`, a 32 MB SDRAM module
- MAME 0.289 at hand to compare a picture or a sound against when in doubt
- The first start of each game shows "Errors detected - any button to
  continue" (empty CMOS): that is expected, not a failure. Press a button,
  then OSD "Save Settings"
- Two controllers for the fighting games, four for Open Ice and NBA
  Hangtime (three for Rampage); a keyboard can stand in for the extra
  players

## Core-wide

| # | Test | Pass when | Result |
|---|---|---|---|
| C1 | Load a game from its MRA | The game starts; no ROM error from the MRA | |
| C2 | HDMI picture | Whole picture, nothing cut off or doubled at the edges, colours as in MAME | |
| C3 | Aspect Ratio, Scale, Scandoubler Fx | Each setting changes the HDMI picture as named, no loss of picture | |
| C4 | Video Timing 57 Hz and 60 Hz | Whole picture on a display that takes it, game a little faster, music at normal pitch; back to Native 54.7 Hz the same | |
| C5 | Analog video (15 kHz) | Stable picture, centred on the screen | |
| C6 | CRT Adjust: H-Size, H-Position, V-Shift, Auto-Width | Each moves or sizes the picture as named, the screen keeps sync | |
| C7 | CRT V-Size, PVM and Cabinet, a few steps each way | Taller / shorter as asked; Cabinet keeps sync on any CRT; PVM keeps sync on a PVM/BVM | |
| C8 | Sound over 10 minutes (HDMI and analog audio) | Music, effects and speech as in MAME, no crackle, dropouts or drift | |
| C9 | Pause button | Pauses and resumes the game | |
| C10 | "Pause when OSD is Open" On / Off | On: the game waits while the OSD is open. Off: it keeps running | |
| C11 | OSD Reset, then Reset and close OSD | The game restarts both times; the second closes the OSD | |
| C12 | Save Settings, then reload the core | Changed operator settings and high scores are still there, no CMOS error | |

## Mortal Kombat 3

Main set: mk3 (rev 2.1).

| # | Test | Pass when | Result |
|---|---|---|---|
| MK3-1 | Boot | Self-test passes, attract mode starts | |
| MK3-2 | Attract mode, 10 minutes | Pictures, music and speech right, no hang | |
| MK3-3 | Coin and Start, both players | Credits go up, each player starts a game | |
| MK3-4 | All six buttons and the joystick, both players | Every input works (service mode switch test, or in a fight) | |
| MK3-5 | Service mode (Test button, then OSD Service Mode) | Operator menu opens from both, switch test shows the inputs, exits back to the game | |
| MK3-6 | OSD Service Credit, Tilt (DIP Switches page) | A credit is added; the game registers the tilt | |
| MK3-7 | DIP Switches page: Blood off | No blood in a fight | |
| MK3-8 | Two-player fight, and a one-player run through several opponents | No hang, no picture or sound faults | |
| MK3-9 | EJB Menu (OSD Secret Menu, in attract mode) | The menu opens; SMOKE / UN-SMOKE and Character Endings work | |
| MK3-10 | Kombat Kode 100-100 from the OSD | "Throwing disabled" on the next VS screen | |
| MK3-11 | Kombat Kode 969-141 | The round's winner battles Motaro | |
| MK3-12 | Ultimate Kombat Kode 10902-22234 at game over | Smoke unlocked; still there after Save Settings and a reload | |
| MK3-13 | Fatality from the Finishing Moves page, player 1 winning | The move happens at the distance the Move List gives | |
| MK3-14 | The same with player 2 winning | The move happens | |
| MK3-15 | Mercy, then Animality (round 3) | Both happen | |
| MK3-16 | Friendship or Babality | It happens | |
| MK3-17 | Move List: pick a fighter | The fighter's moves over the MK3 logo, text easy to read, the game waits; the next fighter in the option shows that fighter's; Off resumes | |
| MK3-18 | Finishing move lines show name and buttons | Lines match the fighter picked under Character | |
| MK3-19 | Rev 1.0: a fatality from the Finishing Moves page | The move happens | |
| MK3-20 | Set rev 2.0 | Boots and plays a fight | |
| MK3-21 | Set rev 1.0 | Boots and plays a fight; Move List title says rev 1 | |
| MK3-22 | Set rev 1 chip label p4.0 | Boots and plays a fight | |
| MK3-23 | OSD main page | Video Settings, Kombat Kodes, Move List, Finishing Moves, DIP Switches, Secret Menu, Service Mode, Pause when OSD is Open, Reset, Reset and close OSD; DIP Switches: Attract Sound, Bill Validator, Blood, Coinage, Coinage Source, Counters, Service Credit, Test Switch, Tilt, Violence, in that order | |
| MK3-24 | DIP Switches page: Coinage Source Dipswitch, Coinage USA-Free Play | Free play: Start without coins; back to CMOS, coins needed again | |

## Ultimate Mortal Kombat 3

Main set: umk3 (rev 1.2).

| # | Test | Pass when | Result |
|---|---|---|---|
| UMK3-1 | Boot | Self-test passes, attract mode starts | |
| UMK3-2 | Attract mode, 10 minutes | Pictures, music and speech right, no hang | |
| UMK3-3 | Coin and Start, both players | Credits go up, each player starts a game | |
| UMK3-4 | All six buttons and the joystick, both players | Every input works | |
| UMK3-5 | Service mode (Test button, then OSD Service Mode) | Operator menu opens from both, switch test shows the inputs, exits | |
| UMK3-6 | OSD Service Credit, Tilt (DIP Switches page) | A credit is added; the game registers the tilt | |
| UMK3-7 | DIP Switches page: Blood off | No blood in a fight | |
| UMK3-8 | Two-player fight, and a one-player run through several opponents | No hang, no picture or sound faults | |
| UMK3-9 | 2 on 2 mode | A team fight plays through | |
| UMK3-10 | EJB Menu (OSD Secret Menu, in attract mode) | The menu opens; the hidden fighters switch on and off | |
| UMK3-11 | Secret Menu: EJB Character Endings On | The game restarts; the EJB menu has Character Endings; an ending shows its story | |
| UMK3-12 | Kombat Kode 100-100 | "Throwing disabled" on the next VS screen | |
| UMK3-13 | Kombat Zone kode (any stage) | The fight is on that stage | |
| UMK3-14 | Ultimate Kombat Kodes: Mileena, Ermac, Classic Sub-Zero | Each unlocks its fighter; kept after Save Settings and a reload | |
| UMK3-15 | Fatality, player 1 winning | The move happens at the distance the Move List gives | |
| UMK3-16 | Fatality, player 2 winning | The move happens | |
| UMK3-17 | Stage Fatality (Subway, The Pit 3, Bell Tower or Scorpion's Lair) | It happens | |
| UMK3-18 | Mercy, then Animality (round 3) | Both happen | |
| UMK3-19 | Friendship and Babality | Both happen | |
| UMK3-20 | Move List: pick a fighter, a hidden fighter too | The fighter's moves over the UMK3 logo, text easy to read, the game waits; Off resumes | |
| UMK3-21 | Finishing move lines show name and buttons | Lines match the fighter picked under Character | |
| UMK3-22 | Set rev 1.1 | Boots and plays a fight | |
| UMK3-23 | Set rev 1.0 | Boots and plays a fight | |
| UMK3-24 | OSD main page | Video Settings, Kombat Kodes, Move List, Finishing Moves, DIP Switches, Secret Menu, Service Mode, Pause when OSD is Open, Reset, Reset and close OSD; DIP Switches: Attract Sound, Bill Validator, Blood, Coinage, Coinage Source, Counters, Service Credit, Test Switch, Tilt, Violence, in that order | |
| UMK3-25 | DIP Switches page: Coinage Source Dipswitch, Coinage USA-Free Play | Free play: Start without coins; back to CMOS, coins needed again | |

## WWF WrestleMania

Main set: wwfmania (rev 1.30).

| # | Test | Pass when | Result |
|---|---|---|---|
| WWF-1 | Boot | Self-test passes, attract mode starts | |
| WWF-2 | Attract mode, 10 minutes | Pictures, music and speech right, no hang | |
| WWF-3 | Coin and Start, both players | Credits go up, each player starts a game | |
| WWF-4 | All five buttons and the joystick, both players | Every input works | |
| WWF-5 | Service mode (Test button, then OSD Service Mode) | Operator menu opens from both, switch test shows the inputs, exits | |
| WWF-6 | OSD Service Credit, Tilt (DIP Switches page) | A credit is added; the game registers the tilt | |
| WWF-7 | DIP Switches page: Coinage Source Dipswitch, Coinage Free Play | Free play: Start without coins; back to CMOS, coins needed again | |
| WWF-8 | Two-player match | Plays to the end, no faults | |
| WWF-9 | One-player run through several matches | No hang, no picture or sound faults | |
| WWF-10 | High score / initials kept after Save Settings and a reload | Still there | |
| WWF-11 | Set rev 1.20 | Boots and plays a match | |
| WWF-12 | Set rev 1.1 | Boots and plays a match | |
| WWF-13 | Set proto 2.01 | Boots and plays a match | |
| WWF-14 | OSD main page | Video Settings, DIP Switches, Service Mode, Pause when OSD is Open, Reset, Reset and close OSD; DIP Switches: Bill Validator, Coinage, Coinage Source, Counters, Powerup Test, Realtime Clock, Service Credit, Test Switch, Tilt, in that order | |

## 2 On 2 Open Ice Challenge

Main set: openice (rev 1.21).

| # | Test | Pass when | Result |
|---|---|---|---|
| OI-1 | Boot | Self-test passes, attract mode starts | |
| OI-2 | Attract mode, 10 minutes | Pictures, music and speech right, no hang | |
| OI-3 | Coin and Start, all four players | Credits go up, each player joins | |
| OI-4 | All three buttons and the joystick, all four players | Every input works | |
| OI-5 | Service mode (Test button, then OSD Service Mode) | Operator menu opens from both, switch test shows the inputs, exits | |
| OI-6 | OSD Service Credit, Tilt (DIP Switches page) | A credit is added; the game registers the tilt | |
| OI-7 | DIP Switches page: Head Size Large | Big heads in play | |
| OI-8 | Four-player game | Plays through, no faults | |
| OI-9 | Full one-player game (all periods) | No hang, no picture or sound faults | |
| OI-10 | Initials / records kept after Save Settings and a reload | Still there | |
| OI-11 | Turbo meter and fights | Turbo drains and refills, checks and fights play | |
| OI-12 | Set rev 1.2A | Boots and plays | |
| OI-13 | OSD Secret Codes: Secret Players 1-3, Tonight's Game, Face-off | Each list shows over the Open Ice logo, text easy to read, the players with their names; the game waits; Off resumes | |
| OI-14 | A secret player from the list (e.g. MJT MAR 22) | Joins the team (TURMELL) | |
| OI-15 | A code from the list (e.g. Big Puck, `U U D D T` on Tonight's Game) | The effect shows in the game | |
| OI-16 | OSD main page | Video Settings, Secret Codes, DIP Switches, Service Mode, Pause when OSD is Open, Reset, Reset and close OSD; DIP Switches: Attract Sound, Bill Validator, Cabinet, Coinage, Coinage Source, Counters, Head Size, Service Credit, Test Switch, Tilt, in that order | |

## NBA Hangtime

Main set: nbahangt (L1.3).

| # | Test | Pass when | Result |
|---|---|---|---|
| NBA-1 | Boot | Self-test passes, attract mode starts | |
| NBA-2 | Attract mode, 10 minutes | Pictures, music and speech right, no hang | |
| NBA-3 | Coin and Start, all four players | Credits go up, each player joins | |
| NBA-4 | All three buttons and the joystick, all four players | Every input works | |
| NBA-5 | Service mode (Test button, then OSD Service Mode) | Operator menu opens from both, switch test shows the inputs, exits | |
| NBA-6 | OSD Service Credit, Tilt (DIP Switches page) | A credit is added; the game registers the tilt | |
| NBA-7 | DIP Switches page: Coinage Source Dipswitch, Coinage Free Play | Free play: Start without coins; back to CMOS, coins needed again | |
| NBA-8 | Four-player game | Plays through, no faults | |
| NBA-9 | Full one-player game (all quarters) | No hang, no picture or sound faults | |
| NBA-10 | Initials and PIN record | Kept after Save Settings and a reload; the record loads at the next game | |
| NBA-11 | Create a player | The created player plays | |
| NBA-12 | OSD Secret Midway Menu On, in attract mode | The statistics pages show; the option is back at Off; after the last page the game restarts | |
| NBA-13 | Turbo and dunks | Turbo works, dunks and alley-oops play | |
| NBA-14 | Set M1.3 | Boots and plays | |
| NBA-15 | Set L1.2 | Boots and plays | |
| NBA-16 | Set M1.2 | Boots and plays | |
| NBA-17 | Set L1.1 | Boots and plays | |
| NBA-18 | Set M1.1 | Boots and plays | |
| NBA-19 | OSD Secret Codes: Page 1, then Page 2 | Each list shows over the NBA Hangtime logo, text easy to read, every player with the full name; the game waits; Off resumes | |
| NBA-20 | A secret player from the list (e.g. JAPPLE 6660) | Joins the squad, shown with "HIDDEN ATTRIBUTES" | |
| NBA-21 | A match-up code from the list (e.g. 025) | The effect shows in the game (tiny players) | |
| NBA-22 | OSD main page | Video Settings, Secret Codes, DIP Switches, Secret Midway Menu, Service Mode, Pause when OSD is Open, Reset, Reset and close OSD; DIP Switches: Cabinet, Coinage, Coinage Source, Counters, Country, Powerup Test, Service Credit, Test Switch, Tilt, in that order | |

## NBA Maximum Hangtime

Main set: nbamht (L1.03), from `nbahangt.zip`.

| # | Test | Pass when | Result |
|---|---|---|---|
| NBAM-1 | Boot from `nbahangt.zip` | Self-test passes, attract mode starts | |
| NBAM-2 | Attract mode, 10 minutes | Pictures, music and speech right, no hang | |
| NBAM-3 | Coin and Start, all four players | Credits go up, each player joins | |
| NBAM-4 | All three buttons and the joystick, all four players | Every input works | |
| NBAM-5 | Service mode (Test button, then OSD Service Mode) | Operator menu opens from both, switch test shows the inputs, exits | |
| NBAM-6 | OSD Service Credit, Tilt (DIP Switches page) | A credit is added; the game registers the tilt | |
| NBAM-7 | DIP Switches page: Coinage Source Dipswitch, Coinage Free Play | Free play: Start without coins; back to CMOS, coins needed again | |
| NBAM-8 | Four-player game | Plays through, no faults | |
| NBAM-9 | Full one-player game (all quarters) | No hang, no picture or sound faults | |
| NBAM-10 | Initials and PIN record | Kept after Save Settings and a reload | |
| NBAM-11 | Create a player | The created player plays | |
| NBAM-12 | OSD Secret Midway Menu On, in attract mode | The statistics pages show; the option is back at Off; after the last page the game restarts | |
| NBAM-13 | Set L1.0 | Boots and plays | |
| NBAM-14 | Set M1.0 | Boots and plays | |
| NBAM-15 | Set L0.9 | Boots and plays | |
| NBAM-16 | OSD Secret Codes: Page 1, then Page 2 | Each list shows over the Maximum Hangtime logo, text easy to read; the game waits; Off resumes; the title names L1.03 | |
| NBAM-17 | A secret player with SPC in it (MATT_B 0184) | Joins the squad, shown with "HIDDEN ATTRIBUTES" | |
| NBAM-18 | A match-up code from the list (e.g. 025) | The effect shows in the game (tiny players) | |
| NBAM-19 | OSD main page | As NBA-22, in that order | |

## Rampage World Tour

Main set: rmpgwt (rev 1.3).

| # | Test | Pass when | Result |
|---|---|---|---|
| RWT-1 | Boot | Self-test passes, attract mode starts | |
| RWT-2 | Attract mode, 10 minutes | Pictures, music and speech right, no hang | |
| RWT-3 | Coin and Start, all three players | Credits go up, each player joins | |
| RWT-4 | Jump, Punch, Kick and the joystick, all three players | Every input works | |
| RWT-5 | Service mode (Test button, then OSD Service Mode) | Operator menu opens from both, switch test shows the inputs, exits | |
| RWT-6 | OSD Service Credit, Tilt (DIP Switches page) | A credit is added; the game registers the tilt | |
| RWT-7 | DIP Switches page: Coinage Source Dipswitch, Coinage USA-Free Play | Free play: Start without coins; back to CMOS, coins needed again | |
| RWT-8 | Three-player game | Plays through, no faults | |
| RWT-9 | One-player game through several cities | No hang, no picture or sound faults | |
| RWT-10 | High scores kept after Save Settings and a reload | Still there | |
| RWT-11 | Set rev 1.1 | Boots and plays | |
| RWT-12 | OSD main page | Video Settings, DIP Switches, Service Mode, Pause when OSD is Open, Reset, Reset and close OSD; DIP Switches: Bill Validator, Coinage, Coinage Source, Counters, Powerup Test, Service Credit, Test Switch, Tilt, in that order | |
