# WWF WrestleMania

MRA sets: wwfmania (rev 1.30), with rev 1.20, rev 1.1 and proto 2.01 in
`_alternatives`.

<!-- extra-content: this section is copied from Extra-Content.md by tools/extra_content.py -->

## Extra content

No game-specific extras: it gets the core-wide ones, in all four sets (rev
1.30, 1.20, 1.1, proto 2.01). Its DIP Switches page also has the Realtime
Clock switch, which should stay at No because the game's real-time clock is
not emulated. The 12-press code in the credits does nothing in the game, so
the core does not offer it.

The core-wide extras every game gets, and the other games' extras:
[Extra content](Extra-Content.md).

<!-- /extra-content -->

## OSD

The main page, in order: Video Settings; DIP Switches (Bill Validator,
Coinage, Coinage Source, Counters, Powerup Test, Realtime Clock, Service
Credit, Test Switch, Tilt); Service Mode; Pause when OSD is Open; Reset
and Reset and close OSD. The DIP switches start at MAME's settings
(Country, not on the page, stays USA). With Coinage Source at CMOS (the
default) the game takes its coinage from its own adjustments, not from the
Coinage switch.

## Controls

Punch, Defense, Power Punch, Kick, Power Kick; two players.

## Notes

- The game keeps a real-time clock that is not emulated (MAME does not
  emulate it either): leave the Realtime Clock switch at No.
- A 12-press code during the credits sets a flag in the game, but nothing
  in the game reads it, so the core does not offer it.
