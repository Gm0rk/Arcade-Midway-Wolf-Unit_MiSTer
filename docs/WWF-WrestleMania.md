# WWF WrestleMania

MRA sets: wwfmania (rev 1.30), with rev 1.20, rev 1.1 and proto 2.01 in
`_alternatives`.

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
