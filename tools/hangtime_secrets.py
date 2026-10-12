#!/usr/bin/env python3
# ============================================================================
#  hangtime_secrets.py - the secret players and match-up codes of NBA
#  Hangtime and NBA Maximum Hangtime
#
#  Both games read two tables out of their program ROM:
#
#    - the secret players: entered at "Enter Name" as a name and a PIN.
#      20 bytes an entry, 10 16-bit words: the name's six letters (1-26
#      A-Z, 1Bh !, 1Dh SPC, 0 past the end), then the PIN's four keys
#      (1-10 the digits 0-9, 0Bh SPC). The table starts with JAPPLE and
#      runs to the first word that is no letter. Staff and guests first,
#      then the hidden NBA players (PIN 0000, from PIPPEN on). A key of 0
#      cannot be typed: such an entry is in the table but out of reach
#      (MDOC, PIN "20", in NBA Hangtime and Maximum Hangtime 1.0 / 0.9).
#    - the match-up codes: entered on the "Tonight's Matchup" screen, Turbo,
#      Shoot and Pass stepping the three digits. Found by the code that
#      checks them:
#          MOVI table,A2 ; MOVI 13,A3 ; MOVE *A2(0),A14,0
#      an entry is the code (BCD), then a 32-bit flag, one bit an effect.
#      The effects (EFFECTS below) are not named in the ROM: the names are
#      the ones published for the game, each flag checked in MAME 0.289.
#      With human players on both teams a code takes effect only when a
#      player of each team enters it; Tournament Mode (flag 1) is refused
#      with a single human player.
#
#  The core shows both lists in the Secret Codes window (tools/move_list.py
#  lays out the pages from hangtime_secrets.txt, which --write makes), each
#  entry with the person's full name (FULL_NAMES below). The ROM has no
#  full names (the game shows a surname plate): they come from the games'
#  own credits, the surname each one wears in the game (MAME 0.289), and the
#  published code lists (exotica.org.uk Lost in Translation, Dan Amrich's
#  bunnyears.net, GameFAQs). The surnames settle a few: WESLEY wears
#  PERSON (Wesley Person, so PERSON is Chuck Person), MCKEE wears MCKEY,
#  KEVINE EDWARDS, BUCK WILLIAMS. MURRAY's first name is in none of them
#  (Tracy or Lamond): only the surname is given. MARIUS is the credits'
#  Marius Mateescu (GameFAQs has Marius Enge); MDOC is the credits' M.Doc.
#  mra_gen.py puts the set's variant (VARIANTS below; 0: unknown) in config
#  byte 14, which picks the pages.
#
#  Usage:
#    hangtime_secrets.py PROGRAM.BIN       the image's tables and variant
#    hangtime_secrets.py --write NBAHANGT.BIN NBAMHT.BIN NBAMHTL10.BIN NBAMHTP.BIN
#                                          write hangtime_secrets.txt (one
#                                          image of each variant, in order)
#    hangtime_secrets.py --check           the text file against itself
#                                          (variants, codes) and the pages
#
#  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
# ============================================================================

import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TXT = os.path.join(HERE, "hangtime_secrets.txt")
ROM_BIT = 0xFF800000            # 34010 bit address of the program ROM's byte 0

# the variants the core knows (config byte 14), with the sets that have them
VARIANTS = {
    1: ("NBA Hangtime", "all versions", "nbahangt, nbahangtm13, nbahangtl12, nbahangtm12, nbahangtl11, nbahangtm11"),
    2: ("NBA Maximum Hangtime", "L1.03", "nbamht"),
    3: ("NBA Maximum Hangtime", "L1.0, M1.0", "nbamhtl10, nbamhtm10"),
    4: ("NBA Maximum Hangtime", "L0.9", "nbamhtp"),
}

# the effects by flag bit (0x0001 ... 0x1000)
EFFECTS = ["Tournament Mode", "Baby Players", "No Music", "Goaltending Called", "Max Blocking",
           "Quick Hands", "Max Power", "Max Speed", "Hyper Speed", "Stealth Turbo",
           "Unlimited Turbo", "No Pushing", "Fast Passing"]

# who each secret player is (the name as entered, _ for SPC)
FULL_NAMES = {
    # Midway staff and guests
    "AMRICH": "Dan Amrich", "BARDO": "Steve Bardo", "CARLOS": "Carlos Pesina",
    "DANIEL": "Dan Thompson", "DANR": "Dan Roan", "DIVITA": "Sal Divita",
    "EDDIE": "Eddie Ferrier", "EUGENE": "Eugene Geer", "HEITH": "Heith Bettleman",
    "JAMIE": "Jamie Rivett", "JAPPLE": "Jeff Johnson", "JASON": "Jason Skiles",
    "JC": "John Carlton", "JFER": "Jennifer Hedrick", "JIGGET": "Dan Jiggetts",
    "JONHEY": "Jon Hey", "K_DAY": "Kevin Day", "KOMBAT": "Ed Boon",
    "MARIUS": "Marius Mateescu", "MARTY": "Marty Martinez", "MATT_B": "Matt Bettleman",
    "MDOC": "M.Doc", "MEDNIK": "Cary Mednick", "MINIFE": "Marcus Minifee",
    "MORRIS": "Willie Morris Jr.", "MORTAL": "John Tobias", "MUNDAY": "Larry Munday",
    "MXV": "Mike Vinikour", "NFUNK": "Neil Funk", "NICK": "Nick Ehrlich",
    "NOBUD": "Bud Fletcher", "NORTH": "Mike North", "PATF": "Pat Fitzgerald",
    "PERRY": "Matthew Perry", "QUIN": "Kevin Quinn", "ROOT": "John Root",
    "SHAWN": "Shawn Liptak", "SNO": "Sheridan Oursler", "TURMEL": "Mark Turmell",
    "ZIRIN": "Jonathan Zirin",
    # NBA players
    "AHRDWY": "Anfernee Hardaway", "ALVINR": "Alvin Robertson", "BENJMN": "Benoit Benjamin",
    "BENOIT": "David Benoit", "BSCOTT": "Byron Scott", "BUCK": "Buck Williams",
    "CHAPMN": "Rex Chapman", "CLIFFR": "Cliff Robinson", "DAVIDR": "David Robinson",
    "DOUGLS": "Sherman Douglas", "DREAM": "Hakeem Olajuwon", "ELLIOT": "Sean Elliott",
    "EWING": "Patrick Ewing", "FINLEY": "Michael Finley", "GHILL": "Grant Hill",
    "GILIAM": "Armon Gilliam", "GLENNR": "Glenn Robinson", "HGRANT": "Horace Grant",
    "JOHNSN": "Larry Johnson", "KEMP": "Shawn Kemp", "KEVINE": "Kevin Edwards",
    "KIDD": "Jason Kidd", "KSMITH": "Kenny Smith", "MALONE": "Karl Malone",
    "MCKEE": "Derrick McKey", "MCLOUD": "George McCloud", "MILLER": "Reggie Miller",
    "MOTUMB": "Dikembe Mutombo", "MOURNG": "Alonzo Mourning", "MURDCK": "Eric Murdock",
    "MURRAY": "Murray", "MURSAN": "Gheorghe Muresan", "OAKLEY": "Charles Oakley",
    "OMILLR": "Oliver Miller", "PERSON": "Chuck Person", "PIPPEN": "Scottie Pippen",
    "RICE": "Glen Rice", "RODMAN": "Dennis Rodman", "RUFFIN": "Trevor Ruffin",
    "SMITS": "Rik Smits", "SPUD": "Spud Webb", "STACKH": "Jerry Stackhouse",
    "STARKS": "John Starks", "TMILLS": "Terry Mills", "WEBB": "Spud Webb",
    "WEBBER": "Chris Webber", "WESLEY": "Wesley Person",
}


def full_name(name):
    """who a secret player is (name as entered, SPC as a space or _)"""
    return FULL_NAMES[name.replace(" ", "_")]


NAME_KEY = {**{i: chr(64 + i) for i in range(1, 27)}, 0x1B: "!", 0x1D: " "}
PIN_KEY = {**{i: str(i - 1) for i in range(1, 11)}, 0x0B: " "}


def words(rom):
    return struct.unpack("<%dH" % (len(rom) // 2), rom)


def secret_players(rom):
    """[(name, pin)] in table order; pin None when it cannot be typed"""
    w = words(rom)
    start = None
    key = [ord(c) - 64 for c in "JAPPLE"]
    for i in range(len(w) - 10):
        if list(w[i:i + 6]) == key:
            start = i
            break
    if start is None:
        raise SystemExit("no secret player table (JAPPLE)")
    out = []
    i = start
    while 1 <= w[i] <= 0x1F and all(x <= 0x1F for x in w[i:i + 10]):
        ent = w[i:i + 10]
        name = "".join(NAME_KEY.get(x, "?") for x in ent[:6] if x)
        pin = "".join(PIN_KEY.get(x, "?") for x in ent[6:])
        out.append((name, None if "?" in pin else pin))
        i += 10
    return out


def matchup_codes(rom):
    """[(code, flag)] as the check routine reads them"""
    w = words(rom)
    for i in range(len(w) - 7):
        if w[i] == 0x09E2 and w[i + 3] == 0x09C3 and w[i + 5] == 0xB44E and w[i + 6] == 0:
            tbl = w[i + 1] | (w[i + 2] << 16)
            n = w[i + 4]
            b = (tbl - ROM_BIT) // 16
            return [("%03X" % w[b + 3 * k], w[b + 3 * k + 1] | (w[b + 3 * k + 2] << 16)) for k in range(n)]
    raise SystemExit("no match-up code check (MOVI table,A2 ; MOVI n,A3)")


def effect(flag):
    return EFFECTS[flag.bit_length() - 1]


# ----------------------------------------------------------------------------
# hangtime_secrets.txt
# ----------------------------------------------------------------------------

def load():
    """{variant: [(name, pin)]}, [(code, effect)]"""
    var, codes, cur = {}, [], None
    for line in open(TXT, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line.strip() or line.startswith("#"):
            continue
        m = re.match(r"\[(\w+)(?: (\d))?\]$", line)
        if m:
            cur = int(m.group(2)) if m.group(1) == "players" else "codes"
            if cur != "codes":
                var[cur] = []
            continue
        if cur == "codes":
            c, e = line.split(" ", 1)
            codes.append((c, e))
        else:
            name, pin = line[:6].rstrip(), line[7:]
            var[cur].append((name.replace("_", " "), pin.replace("_", " ")))
    return var, codes


def write(images):
    L = ["# hangtime_secrets.txt - written by tools/hangtime_secrets.py --write; do",
         "# not edit. The secret players each variant accepts (name padded to 6,",
         "# PIN; _ is SPC), in table order; then the match-up codes and their effects.",
         ""]
    codes0 = None
    for v, rom in enumerate(images, 1):
        L.append(f"[players {v}]")
        for name, pin in secret_players(rom):
            if pin is not None:
                L.append(f"{name.replace(' ', '_'):6s} {pin.replace(' ', '_')}")
        L.append("")
        c = matchup_codes(rom)
        if codes0 is not None and c != codes0:
            raise SystemExit(f"variant {v}: other match-up codes")
        codes0 = c
    L.append("[codes]")
    L += [f"{c} {effect(f)}" for c, f in codes0]
    open(TXT, "w").write("\n".join(L) + "\n")


def variant(rom):
    """the variant of a program image (0: none of them)"""
    var, codes = load()
    mine = [(n, p) for n, p in secret_players(rom) if p is not None]
    for v, t in var.items():
        if t == mine and [(c, effect(f)) for c, f in matchup_codes(rom)] == codes:
            return v
    return 0


def config(family, rom):
    """Config byte 14 for a set (mra_gen.py): its variant, 0 elsewhere"""
    if family != "nbahangt":
        return 0
    v = variant(rom)
    if not v:
        print("hangtime_secrets: no variant matches", file=sys.stderr)
    return v


def main():
    a = sys.argv[1:]
    if a[:1] == ["--write"] and len(a) == 1 + len(VARIANTS):
        write([open(p, "rb").read() for p in a[1:]])
        print(f"written {TXT}")
        return
    if a == ["--check"]:
        var, codes = load()
        err = []
        if sorted(var) != sorted(VARIANTS):
            err.append("variants")
        if len(codes) != len(EFFECTS) or [e for _, e in codes] != EFFECTS:
            err.append("codes")
        unnamed = sorted({n for t in var.values() for n, _ in t if n.replace(" ", "_") not in FULL_NAMES})
        if unnamed:
            err.append("no full name: " + ", ".join(unnamed))
        print("hangtime_secrets.txt: " + ("OK" if not err else "differs: " + ", ".join(err)))
        sys.exit(1 if err else 0)
    if len(a) == 1:
        rom = open(a[0], "rb").read()
        for name, pin in secret_players(rom):
            print(f"{name:6s} {pin if pin is not None else '(cannot be typed)'}")
        for c, f in matchup_codes(rom):
            print(f"{c} {effect(f)}")
        print(f"variant: {variant(rom) if os.path.exists(TXT) else '?'}")
        return
    print("usage: see the header of " + sys.argv[0], file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    main()
