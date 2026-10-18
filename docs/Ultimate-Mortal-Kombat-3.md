# Ultimate Mortal Kombat 3

MRA sets: umk3 (rev 1.2), with rev 1.1 and rev 1.0 in `_alternatives`.
Use the MRAs of the same release as the core: they tell it where the game
keeps its state and carry the patched program copy for EJB Character
Endings.

## Contents

- [OSD](#osd)
- [Controls](#controls)
- [EJB Menu](#ejb-menu)
- [EJB Character Endings](#ejb-character-endings)
- [Kombat Kodes](#kombat-kodes)
- [Ultimate Kombat Kodes](#ultimate-kombat-kodes)
- [Move List](#move-list)
- [Finishing Moves](#finishing-moves)

## OSD

The main page, in order:

- Video Settings
- Kombat Kodes (below)
- Move List (below)
- Finishing Moves (below)
- DIP Switches: Attract Sound, Bill Validator, Blood, Coinage, Coinage
  Source, Counters, Service Credit, Test Switch, Tilt, Violence
- Secret Menu: Open EJB Menu (Attract Mode), EJB Character Endings
- Service Mode, Pause when OSD is Open
- Reset, Reset and close OSD

The DIP switches start at MAME's settings (Powerup Test, not on the page,
stays Off). With Coinage Source at CMOS
(the default) the game takes its coinage from its own adjustments, not
from the Coinage switch.

## Controls

High Punch, Low Punch, High Kick, Low Kick, Block, Run; two players.

## EJB Menu

The developers' test menu, in every revision. OSD Secret Menu, "Open EJB
Menu (Attract Mode)" while the game is in attract mode (by hand: P1 Block
x5, P2 Block x10, P1 Block x3, P2 Block x1, P1 Block x2, P2 Block x2, P1
Block x3, P2 Block x3). It adds extra audits, the full credits, the
"Penacho/Miller" Galaga-style game, the hidden characters (Mileena, Ermac,
Classic Sub-Zero) on/off and a fatality demonstration.

## EJB Character Endings

OSD Secret Menu option. UMK3 dropped Mortal Kombat 3's Character Endings
item from its EJB menu, but the item and its submenu (Kano to Smoke) are
still in the ROM, and the endings' stories are the game's own. With the
option on, the EJB menu has the item back and each ending shows its story
before the cast roll. The core runs a patched copy of the program ROM that
the MRA loads next to the original; changing the option restarts the game.

## Kombat Kodes

On the VS screen before a two-player fight each player steps three icons
with Low Punch, Block and Low Kick; the six digits (player 1's three, then
player 2's) switch something on for the fight. The OSD page "Kombat Kodes"
enters them for you, sorted into Fight, Round 1 Winner Battles, Kombat
Zone and Messages (Back from a category returns to the main menu); the
Ultimate Kombat Kodes are on the page itself, under the categories.

Pick a kode at any time in a two-player game; a message says it is
waiting, and at the next VS screen the core presses the buttons as the two
players would. The game then shows the kode's message under the fighters.
A kode picked when the VS screen is nearly over waits for the next one.
With "Pause when OSD is Open" on (the default), the game waits while you
choose, so you can also open the OSD once the VS screen is up.

Every kode on the page comes from the game's own kode table, the same in
all revisions. Kodes listed for the home versions (239-494, 978-243,
972-279, 432-234) are not in the arcade game.

| Kode | Message / effect |
|---|---|
| 100-100 | Throwing disabled |
| 020-020 | Blocking disabled |
| 987-123 | No powerbars |
| 466-466 | Unlimited run |
| 688-422 | Dark Kombat |
| 460-460 | Randper Kombat (fighters morph at random; the game also takes 444-444) |
| 985-125 | Psycho Kombat: Dark and Randper Kombat, flickering powerbars, unlimited run, no blocking, fast uppercut recovery |
| 033-000 / 000-033 | Player 1 / player 2 half power |
| 707-000 / 000-707 | Player 1 / player 2 quarter power |
| 044-440 | "Unikoriv Referri: Sans Power": both players start with a sliver of energy |
| 788-322 | Fast uppercut recovery |
| 010-010 | Throwing encouraged |
| 300-300 | Silent Kombat (no music) |
| 227-227 | Explosive Kombat (2 on 2 mode only) |
| 022-220 | Explosive Kombat with throwing disabled (2 on 2 mode only) |
| 642-468 | "You are entering the Land of Rellim": the hidden Galaga-style game |
| 969-141 / 033-564 / 769-342 / 205-205 | The winner of the round battles Motaro / Shao Kahn / Noob Saibot / Smoke |
| 880-088 ... 050-050 | Kombat Zone: the fight's stage (16 stages, listed on the page) |
| 987-666, 282-282, 123-926 | Messages: "Hold flippers during casino run", "No Fear = EB button, skydive, max countdown", "There is no knowledge that is not power" |
| 999-999 | The game's revision |
| 550-550, 717-313, 448-844, 122-221, 004-400 | More messages: "See the Mortal Kombat live tour !!", "Rain can be found in the Graveyard", and three signed by the team |

## Ultimate Kombat Kodes

At game over, while Mileena, Ermac or Classic Sub-Zero is still locked,
the game asks for an Ultimate Kombat Kode: ten icons, each player stepping
five with High Punch, Low Punch, Block, Low Kick and High Kick. Pick one on
the Kombat Kodes page before the game ends and the core enters it on that
screen; the game unlocks the character and keeps it in its CMOS (use OSD
"Save Settings" to keep it on the SD card). Once nobody is left to unlock
the game stops asking, and a kode picked then just waits.

| Kode | Unlocks |
|---|---|
| 22264-22264 | Mileena |
| 12344-44321 | Ermac |
| 81835-81835 | Classic Sub-Zero |

## Move List

OSD "Move List": pick a fighter (the option steps through them in
alphabetical order). The core shows that fighter's moves over the UMK3
logo, and the game waits while the window is up; set the option back to
Off to play on. Stepping to the next fighter with the window up shows
that fighter's moves. The window lists:

- Special moves (with Shang Tsung's morphs), from MAME's command list
- Finishing moves: name, input and how far to stand (see Distances
  below), the Mercy last

All 23 fighters have a page, the hidden ones too.

How the inputs read (the window and the OSD lines alike):

| Notation | Meaning |
|---|---|
| F B U D | the joystick, F toward the opponent (DF, DB, UF, UB: diagonals) |
| HP LP HK LK BL RN | High / Low Punch, High / Low Kick, Block, Run |
| `D F HP` | one after the other |
| `A+B` | together: `D+RN` is Run with Down held |
| `(X) ...` | hold X through what follows, let go at the end: `(LP) F D D F` is hold Low Punch, F D D F, let go |
| `(X) ..., Y` | let go of X, then Y; `Y+X` after the comma: X is still held |
| Hold LK 2s | hold for two seconds, let go |
| (air) / Air: | also in the air / in the air only |
| (tap) | tap the button fast |
| (2P) | in two-player games only |

## Finishing Moves

OSD page "Finishing Moves" enters finishing moves for you. Pick the
fighter under "Character"; the lines below it list that fighter's moves
(Fatality 1 and 2, Stage Fatality, Animality, Friendship, Babality: the
ones it has), each by name and input, and the Mercy (the same input for
every fighter).
The game does not name its fatalities; the names here say what each one
shows. The Move List window has where to stand for each.

At FINISH HIM, stand at the distance the Move List gives, open the OSD and
pick the move: the core enters it on the winner's controls, player 1 or 2,
turned to the side the winner faces. With "Pause when OSD is Open" on (the
default) FINISH HIM waits while you choose. The fighter must be the
winner's (a message says so if not; the Mercy is entered for whoever won,
whichever fighter is picked), and the game's own rules still apply:

- Stage Fatality: on the Subway, The Pit 3, the Bell Tower or Scorpion's
  Lair
- Friendship and Babality: only if the winner did not press Block in the
  last round
- Mercy: in round 3, when each player has won a round; the loser gets back
  up with a little energy. An Animality needs a Mercy in the same round
  first: Mercy, beat the opponent again, then the Animality
- Kabal's Fatality 1 also needs room behind the opponent (not at the edge
  of the screen)

Distances (the Move List's Distance column; between the fighters, the
screen is 400 pixels wide):

| Word | Where the winner stands |
|---|---|
| Close | next to the opponent (under about 90 pixels) |
| Sweep | where a sweep reaches (about 90-130) |
| Outside sweep | just out of sweep reach (about 130-165) |
| Half screen | about a jump away (about 165-260) |
| Full screen | farther |

Two words joined by a dash are a range from the first to the second
(Close-sweep: close or at sweep distance; Sweep-half: anywhere from sweep
to half screen). Not close is sweep distance or farther, Past sweep is
outside sweep or farther, Half or full is half screen or farther, and
Anywhere is any distance.

The moves come from the game's own move tables, the same in every
revision.
