# Ultimate Mortal Kombat 3

MRA sets: umk3 (rev 1.2), with rev 1.1 and rev 1.0 in `_alternatives`.
Use the MRAs of the same release as the core: they tell it where the game
keeps its state and carry the patched program copy for EJB Character
Endings.

## Contents

- [Controls](#controls)
- [EJB Menu](#ejb-menu)
- [EJB Character Endings](#ejb-character-endings)
- [Kombat Kodes](#kombat-kodes)
- [Ultimate Kombat Kodes](#ultimate-kombat-kodes)
- [Finishing Moves](#finishing-moves)

## Controls

High Punch, Block, High Kick, Low Punch, Low Kick, Run; two players.

## EJB Menu

The developers' test menu, in every revision. OSD "Open EJB Menu" while
the game is in attract mode (by hand: P1 Block x5, P2 Block x10, P1 Block
x3, P2 Block x1, P1 Block x2, P2 Block x2, P1 Block x3, P2 Block x3). It
adds extra audits, the full credits, the "Penacho/Miller" Galaga-style
game, the hidden characters (Mileena, Ermac, Classic Sub-Zero) on/off and
a fatality demonstration.

## EJB Character Endings

OSD option. UMK3 dropped Mortal Kombat 3's Character Endings item from its
EJB menu, but the item and its submenu (Kano to Smoke) are still in the
ROM, and the endings' stories are the game's own. With the option on, the
EJB menu has the item back and each ending shows its story before the cast
roll. The core runs a patched copy of the program ROM that the MRA loads
next to the original; changing the option restarts the game.

## Kombat Kodes

On the VS screen before a two-player fight each player steps three icons
with Low Punch, Block and Low Kick; the six digits (player 1's three, then
player 2's) switch something on for the fight. The OSD page "Kombat Kodes"
enters them for you, sorted into Fight, Round 1 Winner Battles, Kombat
Zone, Messages and Ultimate Kombat Kodes (Back from a category returns to
the main menu).

Pick a kode at any time in a two-player game; a message says it is
waiting, and at the next VS screen the core presses the buttons as the two
players would. The game then shows the kode's message under the fighters.
A kode picked when the VS screen is nearly over waits for the next one.
With "Pause when OSD is open" on (the default), the game waits while you
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

## Finishing Moves

The OSD page "Finishing Moves" enters finishing moves for you. Choose the
fighter under "Character"; the page then lists that fighter's moves
(Fatality 1 and 2, Stage Fatality, Animality, Friendship, Babality: the
ones it has) with where to stand, and the Mercy every fighter shares.

At FINISH HIM, stand at the distance the line gives, open the OSD and pick
the move: the core enters it on the winner's controls, player 1 or 2,
turned to the side the winner faces. With "Pause when OSD is open" on (the
default) FINISH HIM waits while you choose. The fighter must be the
winner's (a message says so if not), and the game's own rules still apply:

- Stage Fatality: on the Subway, The Pit 3, the Bell Tower or Scorpion's
  Lair
- Friendship and Babality: only if the winner did not press Block in the
  last round
- Mercy: in round 3, when each player has won a round; the loser gets back
  up with a little energy. An Animality needs a Mercy in the same round
  first: Mercy, beat the opponent again, then the Animality
- Kabal's Fatality 1 also needs room behind the opponent (not at the edge
  of the screen)

Distances (between the fighters, the screen is 400 pixels wide):

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
