# Extra content

What this core adds to the Wolf Unit games, core-wide and game by game.
Four of the seven games have extras of their own; WWF WrestleMania and
Rampage World Tour get only the core-wide ones. Every extra is started
from the OSD and does nothing until you pick it. Each game's page in this
folder has the details: controls, how to enter the codes, the full lists.

## Contents

- [At a glance](#at-a-glance)
- [Core-wide](#core-wide)
- [Mortal Kombat 3](#mortal-kombat-3)
- [Ultimate Mortal Kombat 3](#ultimate-mortal-kombat-3)
- [WWF WrestleMania](#wwf-wrestlemania)
- [2 On 2 Open Ice Challenge](#2-on-2-open-ice-challenge)
- [NBA Hangtime and NBA Maximum Hangtime](#nba-hangtime-and-nba-maximum-hangtime)
- [Rampage World Tour](#rampage-world-tour)

## At a glance

| Extra | Mortal Kombat 3 | Ultimate Mortal Kombat 3 | 2 On 2 Open Ice Challenge | NBA Hangtime / Maximum Hangtime |
|---|---|---|---|---|
| Hidden menu opened from the OSD | EJB Menu | EJB Menu | - | Secret Midway Menu |
| Kombat Kodes entered for you | 19 | 47 | - | - |
| Ultimate Kombat Kodes (unlock a fighter) | 1 | 3 | - | - |
| Finishing Moves entered for you | Yes | Yes | - | - |
| Move List window | 15 fighters | 23 fighters | - | - |
| Secret Codes lists | - | - | 161 players, 25 codes | up to 40 players, 47 NBA players, 13 codes |
| Patched ROM option | - | Scorpion - Smoke Voice Fix | - | - |

## Core-wide

All seven games share one OSD layout and the video, DIP switch and control
extras below.

| Extra | What it adds | Where |
|---|---|---|
| Same OSD layout | Video Settings, the game's items, DIP Switches, Secret Menu (Mortal Kombat 3 and Ultimate Mortal Kombat 3) or Secret Midway Menu (Hangtimes), Service Mode, Pause when OSD is Open, Reset, Reset and close OSD | Main page |
| Video Timing | The board's own 54.7 Hz, or 57 Hz / 60 Hz frames for TVs that cannot hold 54.7 Hz. Only blank lines are dropped; games run about 4 % (57 Hz) or 10 % (60 Hz) faster, and the sound board keeps its own clock | Video Settings |
| CRT Adjust | H-Size, H-Position, V-Shift and Auto-Width for analog CRTs, on a sync centred for a standard 15 kHz screen. HDMI shows the adjusted picture too | Video Settings (Scandoubler Fx off) |
| CRT V-Size (experimental) | Picture height in steps of 3 lines. PVM mode shows every line once with more or fewer lines per frame; Cabinet mode keeps the board's timing and redraws the picture | Video Settings (CRT Adjust on) |
| DIP Switches page | MAME's switches as OSD options in alphabetical order, MAME's defaults first, plus Service Credit and Tilt buttons. No switches are stored in the MRAs | DIP Switches |
| Service Mode | Opens the game's operator menu; the Test button does the same | Main page |
| Pause when OSD is Open | The game waits while the OSD is up (On by default); a Pause button works too | Main page, controller |
| Reset and Reset and close OSD | A reset, and a reset that also closes the OSD | Main page |
| Save Settings | The CMOS is kept as NVRAM: settings, audits and high scores survive power-off | OSD |
| Start, Coin, Test, Pause | On every controller, after each game's own buttons | Controller |
| Windows over the game | The Move List and Secret Codes lists are drawn over the paused game on its own logo; four games use them | OSD |
| Merged ROM sets | One zip per game holds every revision and every MRA falls back to it (NBA Maximum Hangtime runs from nbahangt.zip) | ROM folder |

## Mortal Kombat 3

In every revision (2.1, 2.0, 1.0, p4.0): the EJB Menu, 20 Kombat Kodes (19
plus the Ultimate Kombat Kode), a Move List for 15 fighters and the
Finishing Moves. [Details](Mortal-Kombat-3.md).

| Extra | What it does | Where in the OSD |
|---|---|---|
| Open EJB Menu (Attract Mode) | Enters the developers' test menu code for you in attract mode: extra audits, the full credits (an unfinished "Hello" screen on 1.0 and p4.0), Character Endings, the "Penacho/Miller" Galaga-style game and SMOKE / UN-SMOKE | Secret Menu |
| Kombat Kodes | 19 kodes entered on the VS screen: 12 Fight, 4 Round 1 Winner Battles (Motaro, Shao Kahn, Noob Saibot, Smoke) and 3 Messages. Pick one in a two-player game and the core presses the buttons at the next VS screen | Kombat Kodes |
| Ultimate Kombat Kode | Smoke (10902-22234), entered on the game-over screen; Smoke becomes playable and the game keeps it in its CMOS | Kombat Kodes page |
| Move List | Each fighter's special moves with Shang Tsung's morphs, and their finishing moves with input and distance, over the MK3 logo; the game waits while it is up. Shows the revision's own moves (2.x or 1.x) | Move List |
| Finishing Moves | Pick the fighter; at FINISH HIM the core enters the move on the winner's controls, turned to the side the winner faces: Fatalities, Stage Fatality, Animality, Friendship, Babality and the Mercy (entered for whoever won; Cyrax has none on MK3 1.x) | Finishing Moves |

## Ultimate Mortal Kombat 3

The most extras of any game, in every revision (1.2, 1.1, 1.0): the EJB
Menu, a voice fix, 50 Kombat Kodes (47 plus the 3 Ultimate Kombat Kodes), a
Move List for 23 fighters and the Finishing Moves.
[Details](Ultimate-Mortal-Kombat-3.md).

| Extra | What it does | Where in the OSD |
|---|---|---|
| Open EJB Menu (Attract Mode) | Enters the developers' test menu code for you in attract mode (the OSD notes it as the Hidden Alternate Test Menu): extra audits, the full credits, the "Penacho/Miller" Galaga-style game, the hidden characters on and off and a fatality demonstration | Secret Menu |
| Scorpion - Smoke Voice Fix | Off by default; changing it restarts the game. Scorpion's "Get over here!" and "Come here!" no longer cut off after "Get ov..." when the spear's blood sounds come (the game's own sound priority does it, the same in MAME). The same patched program copy gives the EJB menu back the Character Endings item UMK3 left out, and each ending shows its story before the cast roll | Secret Menu |
| Kombat Kodes | 47 kodes entered on the VS screen: 18 Fight, 4 Round 1 Winner Battles, 16 Kombat Zone (the fight's stage) and 9 Messages. Pick one in a two-player game and the core presses the buttons at the next VS screen | Kombat Kodes |
| Ultimate Kombat Kodes | Mileena (22264-22264), Ermac (12344-44321) and Classic Sub-Zero (81835-81835), entered on the game-over screen; the game unlocks the fighter and keeps it in its CMOS | Kombat Kodes page |
| Move List | All 23 fighters, the hidden ones too: special moves with Shang Tsung's morphs, and finishing moves with input and distance, over the UMK3 logo; the game waits while it is up | Move List |
| Finishing Moves | Pick the fighter; at FINISH HIM the core enters the move on the winner's controls, turned to the side the winner faces: Fatalities, Stage Fatality (Subway, The Pit 3, Bell Tower, Scorpion's Lair), Animality, Friendship, Babality and the Mercy (entered for whoever won) | Finishing Moves |

## WWF WrestleMania

No game-specific extras: it gets the core-wide ones, in all four sets (rev
1.30, 1.20, 1.1, proto 2.01). Its DIP Switches page also has the Realtime
Clock switch, which should stay at No because the game's real-time clock is
not emulated. The 12-press code in the credits does nothing in the game, so
the core does not offer it. [Details](WWF-WrestleMania.md).

## 2 On 2 Open Ice Challenge

One extra, Secret Codes, which lists the game's 161 secret players and 25
codes over the game's logo while the game waits. The lists come from the
program ROM (the same in rev 1.21 and 1.2A); you still enter the players
and codes yourself. The game has no hidden menu.
[Details](2-On-2-Open-Ice-Challenge.md).

| Page (OSD Secret Codes) | What it lists |
|---|---|
| Secret Players 1-3 | 161 secret players: initials and birthday to enter, and who each one is |
| Tonight's Game | 13 joystick-and-button codes: big, huge, tiny and normal heads for players and goalies, Big Puck, Baby Size Players, Fat Heads, Dark Rink, Top Display Off |
| Face-off | 12 codes for the time before the first face-off: Throwing Off, Super Goalies, Tournament Mode, Computer Assistance Off, Unlimited Turbo, Turbo Checks Off, Speed Up, the four Better codes and Fast Turbo Recovery |

## NBA Hangtime and NBA Maximum Hangtime

Two extras, the same in all ten sets of both games: the Secret Midway Menu
and the Secret Codes lists. The lists follow the version of the set (the
MRA tells the core which it is), so some names exist only in Maximum
Hangtime. [Details](NBA-Hangtime.md).

| Extra | What it does | Where in the OSD |
|---|---|---|
| Secret Midway Menu | An Off / On option that goes back to Off at once; the core enters the hidden code for you once the OSD is closed. Shows the staff statistics pages: dunks, play time, game averages, team picks and the stored initials with their PINs. A button turns the page and the game restarts after the last | Main page |
| Secret Codes, Page 1 | Up to 40 secret players (Midway staff and guests) with their PINs and who each one is, and 13 match-up codes: Tournament Mode, Baby Players, No Music, Goaltending Called, Max Blocking, Quick Hands, Max Power, Max Speed, Hyper Speed, Stealth Turbo, Unlimited Turbo, No Pushing, Fast Passing | Secret Codes |
| Secret Codes, Page 2 | Up to 47 hidden NBA players and who each one is (all PIN 0000) | Secret Codes |

The Secret Codes lists are drawn over the game's own logo while the game
waits; you enter the players and codes yourself.

## Rampage World Tour

No game-specific extras: it gets the core-wide ones, in both sets (rev 1.3
and 1.1). The game's secret and hidden levels are part of normal play, not
a menu, so there is nothing to open from the OSD.
[Details](Rampage-World-Tour.md).
