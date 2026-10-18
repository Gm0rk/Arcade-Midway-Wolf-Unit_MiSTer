# NBA Hangtime and NBA Maximum Hangtime

MRA sets: nbahangt (L1.3), with M1.3, L1.2, M1.2, L1.1 and M1.1 in
`_alternatives`; nbamht (NBA Maximum Hangtime, L1.03), with L1.0, M1.0 and
L0.9. NBA Maximum Hangtime uses `nbahangt.zip`. Use the MRAs of the same
release as the core: they tell it which version of the game a set is, for
the Secret Codes list.

## Contents

- [Extra content](#extra-content)
- [OSD](#osd)
- [Controls](#controls)
- [Secret Midway Menu](#secret-midway-menu)
- [Secret Codes](#secret-codes)

<!-- extra-content: this section is copied from Extra-Content.md by tools/extra_content.py -->

## Extra content

Two extras, the same in all ten sets of both games: the Secret Midway Menu
and the Secret Codes lists. The lists follow the version of the set (the
MRA tells the core which it is), so some names exist only in Maximum
Hangtime.

| Extra | What it does | Where in the OSD |
|---|---|---|
| Secret Midway Menu | An Off / On option that goes back to Off at once; the core enters the hidden code for you once the OSD is closed. Shows the staff statistics pages: dunks, play time, game averages, team picks and the stored initials with their PINs. A button turns the page and the game restarts after the last | Main page |
| Secret Codes, Page 1 | Up to 40 secret players (Midway staff and guests) with their PINs and who each one is, and 13 match-up codes: Tournament Mode, Baby Players, No Music, Goaltending Called, Max Blocking, Quick Hands, Max Power, Max Speed, Hyper Speed, Stealth Turbo, Unlimited Turbo, No Pushing, Fast Passing | Secret Codes |
| Secret Codes, Page 2 | Up to 47 hidden NBA players and who each one is (all PIN 0000) | Secret Codes |

The Secret Codes lists are drawn over the game's own logo while the game
waits; you enter the players and codes yourself.

The core-wide extras every game gets, and the other games' extras:
[Extra content](Extra-Content.md).

<!-- /extra-content -->

## OSD

The main page, in order: Video Settings; Secret Codes (below); DIP
Switches (Cabinet, Coinage, Coinage Source, Counters, Country, Powerup
Test, Service Credit, Test Switch, Tilt); Secret Midway Menu (below);
Service Mode; Pause when OSD is Open; Reset and Reset and close OSD. The
DIP switches start at MAME's settings (Bill Validator, not on the page,
stays Off). With Coinage Source at CMOS (the default) the game takes its
coinage from its own adjustments, not from the Coinage switch.

## Controls

Turbo, Shoot / Block, Pass / Steal; up to four players.

## Secret Midway Menu

Statistics pages meant for Midway's staff, in every revision of both
games: dunks, play time, game averages, team picks, the stored initials
with their PINs. OSD "Secret Midway Menu" On, best in attract mode (by
hand: both players hold Up and all three buttons, then Down; on the design
team screen that follows, P1 Turbo x2, P2 Shoot x3, P2 Pass x2, P1 Shoot,
P1 Pass, P2 Turbo x2, P1 Turbo x4). A button turns the page; after the
last page the game restarts.

The OSD item is an Off / On option: set it On and it goes back to Off at
once; the core enters the code as soon as the game runs again (the OSD
closed).

## Secret Codes

Both games hide secret players behind a name and PIN, and have codes for
the "Tonight's Matchup" screen. OSD "Secret Codes" shows them over the
game's logo (NBA Hangtime's or Maximum Hangtime's), and the game waits
while the list is up:

- Page 1: the secret players (Midway staff and guests) with their PINs
  and who each one is, and the match-up codes
- Page 2: the hidden NBA players with who each one is (all with PIN 0000)

Set it back to Off to play on. The lists are the ones in the set's program
ROM; you enter the codes yourself.

### Secret players

Pick "Enter Name" after pressing Start. Type the name on the letter grid
(END after a name shorter than six letters; `_` in a name or PIN is the
SPC key), then the four PIN keys. The player joins your squad, shown with
"HIDDEN ATTRIBUTES".

| Name | PIN | Who | | Name | PIN | Who |
|---|---|---|---|---|---|---|
| AMRICH | 2020 | Dan Amrich | | MATT_B | 0184 (Maximum Hangtime) | Matt Bettleman |
| BARDO | 6000 | Steve Bardo | | MDOC | 2000 (Maximum Hangtime L1.03) | M.Doc |
| CARLOS | 1010 | Carlos Pesina | | MEDNIK | 6000 | Cary Mednick |
| DANIEL | 0604 | Dan Thompson | | MINIFE | 6000 | Marcus Minifee |
| DANR | 0000 | Dan Roan | | MORRIS | 6000 | Willie Morris Jr. |
| DIVITA | 0201 | Sal Divita | | MORTAL | 0004 | John Tobias |
| EDDIE | 6213 | Eddie Ferrier | | MUNDAY | 5432 | Larry Munday |
| EUGENE | 6767 | Eugene Geer | | MXV | 1014 | Mike Vinikour |
| HEITH | 1079 (Maximum Hangtime) | Heith Bettleman | | NFUNK | 0101 | Neil Funk |
| JAMIE | 1000 | Jamie Rivett | | NICK | 7000 | Nick Ehrlich |
| JAPPLE | 6660 | Jeff Johnson | | NOBUD | 1010 | Bud Fletcher |
| JASON | 0729 (Maximum Hangtime: 072_) | Jason Skiles | | NORTH | 5050 | Mike North |
| JC | 0000 | John Carlton | | PATF | 2000 | Pat Fitzgerald |
| JFER | 0503 | Jennifer Hedrick | | PERRY | 3500 | Matthew Perry |
| JIGGET | 1010 | Dan Jiggetts | | QUIN | 0330 | Kevin Quinn |
| JONHEY | 6000 | Jon Hey | | ROOT | 6000 | John Root |
| K_DAY | 4242 (Maximum Hangtime, not L0.9) | Kevin Day | | SHAWN | 0123 | Shawn Liptak |
| KOMBAT | 0004 | Ed Boon | | SNO | 0103 | Sheridan Oursler |
| MARIUS | 1005 | Marius Mateescu | | TURMEL | 0322 | Mark Turmell |
| MARTY | 1010 | Marty Martinez | | ZIRIN | 1010 (Maximum Hangtime) | Jonathan Zirin |

MDOC is in the other versions' tables too, but with a PIN no key can give,
so it cannot be entered there; the list leaves it out.

Hidden NBA players, PIN 0000 (both games unless noted):

| Name | Player | | Name | Player |
|---|---|---|---|---|
| AHRDWY | Anfernee Hardaway | | MCKEE | Derrick McKey (Maximum Hangtime) |
| ALVINR | Alvin Robertson (Maximum Hangtime) | | MCLOUD | George McCloud (Maximum Hangtime) |
| BENJMN | Benoit Benjamin (Maximum Hangtime) | | MILLER | Reggie Miller |
| BENOIT | David Benoit (Maximum Hangtime) | | MOTUMB | Dikembe Mutombo |
| BSCOTT | Byron Scott (Maximum Hangtime) | | MOURNG | Alonzo Mourning |
| BUCK | Buck Williams (Maximum Hangtime) | | MURDCK | Eric Murdock (Maximum Hangtime) |
| CHAPMN | Rex Chapman (Maximum Hangtime) | | MURRAY | Murray (Maximum Hangtime) |
| CLIFFR | Cliff Robinson | | MURSAN | Gheorghe Muresan |
| DAVIDR | David Robinson | | OAKLEY | Charles Oakley (Maximum Hangtime) |
| DOUGLS | Sherman Douglas (Maximum Hangtime) | | OMILLR | Oliver Miller (Maximum Hangtime) |
| DREAM | Hakeem Olajuwon | | PERSON | Chuck Person (Maximum Hangtime) |
| ELLIOT | Sean Elliott | | PIPPEN | Scottie Pippen |
| EWING | Patrick Ewing | | RICE | Glen Rice |
| FINLEY | Michael Finley (Maximum Hangtime) | | RODMAN | Dennis Rodman |
| GHILL | Grant Hill | | RUFFIN | Trevor Ruffin (Maximum Hangtime) |
| GILIAM | Armon Gilliam (Maximum Hangtime) | | SMITS | Rik Smits |
| GLENNR | Glenn Robinson | | SPUD | Spud Webb (Maximum Hangtime) |
| HGRANT | Horace Grant | | STACKH | Jerry Stackhouse |
| JOHNSN | Larry Johnson | | STARKS | John Starks |
| KEMP | Shawn Kemp | | TMILLS | Terry Mills (Maximum Hangtime) |
| KEVINE | Kevin Edwards (Maximum Hangtime) | | WEBB | Spud Webb (NBA Hangtime) |
| KIDD | Jason Kidd | | WEBBER | Chris Webber |
| KSMITH | Kenny Smith (Maximum Hangtime) | | WESLEY | Wesley Person (Maximum Hangtime) |
| MALONE | Karl Malone | |  |  |

The ROM holds no names: the game shows a surname plate. The names come
from the games' credits, the surname plates (each entry entered in MAME),
and the published code lists (exotica.org.uk, Dan Amrich's bunnyears.net,
GameFAQs). The plates settle a few: WESLEY wears PERSON (Wesley Person, so
PERSON is Chuck Person), MCKEE wears MCKEY. MURRAY's first name is in none
of them (Tracy or Lamond Murray), so only the surname is given. In the OSD
list a name too long for its column shows its first name as an initial.

### Match-up codes

On "Tonight's Matchup", tap Turbo, Shoot and Pass to set the three digits
under your team (each tap adds one). The game reads them when the screen
ends.

| Code | Effect |
|---|---|
| 111 | Tournament Mode (no power-ups or computer assistance) |
| 025 | Baby Players |
| 048 | No Music |
| 937 | Goaltending Called |
| 616 | Max Blocking |
| 709 | Quick Hands |
| 802 | Max Power |
| 284 | Max Speed |
| 552 | Hyper Speed |
| 273 | Stealth Turbo |
| 461 | Unlimited Turbo |
| 390 | No Pushing |
| 120 | Fast Passing |

With human players on both teams, a code takes effect only if a player of
each team enters it. Tournament Mode needs two or more human players. The
codes are the same in every version of both games; the game does not name
them, so the effects are the names published for it.
