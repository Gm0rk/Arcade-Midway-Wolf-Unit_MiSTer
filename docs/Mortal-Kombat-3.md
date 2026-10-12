# Mortal Kombat 3

MRA sets: mk3 (rev 2.1), with rev 2.0, rev 1.0 and rev 1 chip label p4.0
in `_alternatives`. Use the MRAs of the same release as the core: they tell
it where the game keeps its state and which finishing moves the set has.

## Contents

- [OSD](#osd)
- [Controls](#controls)
- [EJB Menu](#ejb-menu)
- [Kombat Kodes](#kombat-kodes)
- [Ultimate Kombat Kode](#ultimate-kombat-kode)
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
- Secret Menu: Open EJB Menu (Attract Mode)
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
Block x3, P2 Block x3). It adds extra audits, the full credits, Character
Endings, the "Penacho/Miller" Galaga-style game and SMOKE / UN-SMOKE
(Smoke playable or not). Revisions 1.0 and p4.0 have an unfinished "Hello"
screen in place of the credits.

## Kombat Kodes

On the VS screen before a two-player fight each player steps three icons
with Low Punch, Block and Low Kick; the six digits (player 1's three, then
player 2's) switch something on for the fight. The OSD page "Kombat Kodes"
enters them for you, sorted into Fight, Round 1 Winner Battles and
Messages (Back from a category returns to the main menu); the Ultimate
Kombat Kode is on the page itself, under the categories. MK3 has no
Kombat Zone (stage) kodes; UMK3 added them.

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
| 460-460 | Randper Kombat (fighters morph at random) |
| 985-125 | Psycho Kombat: Dark and Randper Kombat, flickering powerbars, unlimited run, no blocking, fast uppercut recovery |
| 033-000 / 000-033 | Player 1 / player 2 half power |
| 707-000 / 000-707 | Player 1 / player 2 quarter power |
| 642-468 | "You are entering the Land of Rellim": the hidden Galaga-style game |
| 969-141 / 033-564 / 769-342 / 205-205 | The winner of the round battles Motaro / Shao Kahn / Noob Saibot / Smoke |
| 987-666, 282-282, 123-926 | Messages: "Hold flippers during casino run", "No Fear = EB button, skydive, max countdown", "There is no knowledge that is not power" |

## Ultimate Kombat Kode

At game over, while Smoke is still locked, the game asks for the Ultimate
Kombat Kode: ten icons, each player stepping five with High Punch, Low
Punch, Block, Low Kick and High Kick. Pick it on the Kombat Kodes page
before the game ends and the core enters it on that screen; Smoke becomes
playable and the game keeps that in its CMOS (use OSD "Save Settings" to
keep it on the SD card). Once Smoke is unlocked the game stops asking, and
a kode picked then just waits.

| Kode | Unlocks |
|---|---|
| 10902-22234 | Smoke |

The EJB Menu's SMOKE item unlocks Smoke too (UN-SMOKE locks him again, as
does a factory reset before revision 2.1).

## Move List

OSD "Move List": pick a fighter (the option steps through them in
alphabetical order). The core shows that fighter's moves over the MK3
logo, and the game waits while the window is up; set the option back to
Off to play on. Stepping to the next fighter with the window up shows
that fighter's moves. The window lists:

- Special moves (with Shang Tsung's morphs), from MAME's command list
- Finishing moves: name, input and how far to stand (see Distances
  below), the Mercy last

The moves are the set's: revision 2.x or revision 1.x (1.0, p4.0), as
the MRA's finishing moves table says.

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
ones it has), each by name and input, and the Mercy every fighter shares.
The game does not name its fatalities; the names here say what each one
shows. The Move List window has where to stand for each.

At FINISH HIM, stand at the distance the Move List gives, open the OSD and
pick the move: the core enters it on the winner's controls, player 1 or 2,
turned to the side the winner faces. With "Pause when OSD is Open" on (the
default) FINISH HIM waits while you choose. The fighter must be the
winner's (a message says so if not), and the game's own rules still apply:

- Stage Fatality: on the Subway, The Pit 3 or the Bell Tower
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

The moves come from the game's own move tables. Revisions 2.0 and 2.1
have the same moves as Ultimate MK3; revision 1.0 and the p4.0 chip set
have older ones: other fatalities, the same Stage Fatality for everybody,
a Babality for Kano only, no Friendships (the game has them switched off),
and a Mercy that also works from sweep distance.
