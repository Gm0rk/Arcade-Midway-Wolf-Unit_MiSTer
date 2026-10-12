#!/usr/bin/env python3
# ============================================================================
#  openice_secrets.py - the secret players and codes of 2 On 2 Open Ice
#  Challenge
#
#  Read out of the program ROM:
#
#    - the secret players: "Enter initials for record keeping?" asks for
#      three initials, a birth month and a day; the game looks them up in a
#      zero-terminated list of 32-bit pointers, each to a record that starts
#      with the three initials (0-25 A-Z, 1Ah space) and the month and day
#      as bytes. The list is found by the lookup:
#          MOVI list,A6 ; CLR A0 ; MOVI entered,A14
#      Some entries cannot be typed (initials 64h, an unused slot; a 78h
#      initial); some are listed twice. 161 players remain.
#    - the codes: a process per player matches the player's controls (7
#      bits: U D L R Shoot Pass Turbo) against lists of input sequences,
#      each a list of states (16-bit words, the last one negative, then the
#      routine to call). Each state must come within 15 frames of the last;
#      a state of 0 means all released. Two lists, each found by
#          MOVK 3,A9 ; MOVI list,A10
#      the first (13 codes) runs on the "Tonight's Game" screen, the second
#      (12) from the end of that screen until the first face-off's help
#      windows. The effects are not named in the ROM: NAMES below gives the
#      names published for the arcade game, by sequence (the sequences are
#      the ROM's; where a published one differs, the ROM's was checked in
#      MAME 0.289). One code is in no published list: "Turbo Checks Off"
#      names what its flag does in the program (Turbo + Pass without the
#      puck gives the plain move), not checked in play.
#
#  Both revisions (1.21, 1.2A) have the same tables. The core shows them in
#  the Secret Codes window (tools/move_list.py, from openice_secrets.txt,
#  which --write makes), each player with the full name (FULL_NAMES).
#
#  Usage:
#    openice_secrets.py PROGRAM.BIN     the image's tables
#    openice_secrets.py --write PROGRAM.BIN
#                                       write openice_secrets.txt
#    openice_secrets.py --check PROGRAM.BIN
#                                       the text file against an image
#
#  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
# ============================================================================

import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TXT = os.path.join(HERE, "openice_secrets.txt")
ROM_BIT = 0xFF800000            # 34010 bit address of the program ROM's byte 0
MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

U, D, L, R, S, P, T = 1, 2, 4, 8, 0x10, 0x20, 0x40
CIRCLE_CW = [U, U | R, R, D | R, D, D | L, L, U | L, U]          # Up round to Up, clockwise


def held(b, seq):
    return [b | s for s in seq]


# the codes' names, by their sequences (in list order)
NAMES = {
    (U | P | T,): "Big Heads",
    (U | S | P, U, U | S | P, U, U | S | P, U): "Huge Heads",
    (T, 0, T, 0, U, 0, S, 0, S, 0, U, 0): "Tiny Heads",
    (D | S, P): "Normal Heads",
    (P, 0, P, 0, T, 0, S, 0, P): "Big Goalie Heads",
    tuple(held(P, CIRCLE_CW + CIRCLE_CW[::-1][1:])): "Huge Goalie Heads",
    tuple(held(S, CIRCLE_CW[:1] + CIRCLE_CW[::-1][1:])): "Tiny Goalie Heads",
    (S, 0, T, 0, P): "Normal Goalie Heads",
    (U, 0, U, 0, D, 0, D, 0, T): "Big Puck",
    (D, D | R, R, U | R, U) + tuple(held(T, [U, U | R, R, D | R, D])): "Baby Size Players",
    (L, U | L, U, U | R, R, U | R, U, U | L, L, D | L, D, D | R, R): "Fat Heads (others)",
    (P | T, P, P | T, P, S | P, P, S | P, P, S | P, P, P | T, P): "Dark Rink",
    (L | T, L, L | T, L, L | T, L, L | S, L, L | S, L, L | P, L, L | P, L, L | P): "Top Display Off",
    (D | T, U | S): "Throwing Off",
    (D, 0, D, 0, D, 0, D, 0, D, 0, P): "Super Goalies",
    (R | S | P | T,): "Tournament Mode",
    tuple(CIRCLE_CW + CIRCLE_CW[1:]): "Computer Assistance Off",
    (T, 0, S, 0, S) + tuple(CIRCLE_CW): "Unlimited Turbo",
    (L | T, L, L | T, L, L | T, L, D | L, D, D | R, R, R | T, R, R | T, R): "Turbo Checks Off",
    (S | T, 0, S | T, 0, R, 0, S | T, 0, D, 0): "Speed Up",
    (S, 0, S, 0, S, 0, S, 0, S, 0, T, 0, S, 0, S, 0, S, 0, S, 0, P, 0): "Better Shooting",
    (P, 0, T, 0, P, 0, T, 0, P, 0, P, 0, P, 0, P, 0, P, 0, T): "Better Passing",
    (U | P | T, P | T, U | P | T, P | T, U | P | T, P | T, L | P | T, P | T, R | P | T, P | T,
     R | P | T, P | T): "Better Checking",
    (S | P, 0, S | P, 0, P, 0, P, 0, S, 0, S, 0, T, 0, T, 0, T): "Better Puck Handling",
    (R, 0, R, 0, R, 0, R, 0, T, 0, L, 0, L, 0, T, 0, R, 0): "Fast Turbo Recovery",
}


# who each secret player is, by "initials month day" (_ for a space). The
# ROM holds no names (the game shows the player's photo and a surname
# plate): the surnames are the plates as the game shows them (each entry
# entered in MAME 0.289); the first names come from the game's credits
# (Midway staff), Chris Blaney's GameFAQs FAQ, and for the NHL players
# their birthdays, which the entries carry. A few birthdays are off by the
# game's own data (Bernie Nicholls, Pierre Turgeon): the list shows the
# game's. "Evil Haeger" is the FAQ's name for the third Haeger entry.
FULL_NAMES = {
    'MDM JAN 18': 'Mark Messier',
    'P_N DEC 9': 'Petr Nedved',
    'J_M NOV 20': 'John MacLean',
    'S_R JUN 7': 'Stephane Richer',
    'J_J JAN 5': 'Joe Juneau',
    'P_B FEB 7': 'Peter Bondra',
    'EBL FEB 28': 'Eric Lindros',
    'RJB AUG 9': "Rod Brind'Amour",
    'K_M FEB 8': 'Kirk Muller',
    'SAT JUL 15': 'Steve Thomas',
    'GJM MAR 23': 'Gord Murphy',
    'SEM JUN 11': 'Scott Mellanby',
    'B_B JAN 21': 'Brian Bradley',
    'P_K DEC 23': 'Petr Klima',
    'J_J FEB 15': 'Jaromir Jagr',
    'L_R FEB 17': 'Luc Robitaille',
    'JSS JUL 7': 'Joe Sakic',
    'WLC OCT 25': 'Wendel Clark',
    'PML FEB 22': 'Pat LaFontaine',
    'A_M FEB 18': 'Alexander Mogilny',
    'VFD DEC 17': 'Vincent Damphousse',
    'MLR FEB 1': 'Mark Recchi',
    'RJB DEC 28': 'Ray Bourque',
    'CMN JUN 6': 'Cam Neely',
    'AWC JUL 23': 'Andrew Cassels',
    'GMS FEB 1': 'Geoff Sanderson',
    'ALD FEB 7': 'Alexandre Daigle',
    'SVF DEC 13': 'Sergei Fedorov',
    'SGY MAY 9': 'Steve Yzerman',
    'DRG JUN 25': 'Doug Gilmour',
    'DJA SEP 29': 'Dave Andreychuk',
    'B_H AUG 9': 'Brett Hull',
    'BFS JAN 23': 'Brendan Shanahan',
    'BIN FEB 24': 'Bernie Nicholls',
    'CKC JAN 25': 'Chris Chelios',
    'T_S JUL 3': 'Teemu Selanne',
    'KMT MAR 28': 'Keith Tkachuk',
    'MTM JUN 7': 'Mike Modano',
    'KJH SEP 9': 'Kevin Hatcher',
    'PVB MAR 31': 'Pavel Bure',
    'TJL APR 11': 'Trevor Linden',
    'TWF JUN 29': 'Theoren Fleury',
    'S_O AUG 3': 'Sandis Ozolinsh',
    'URD JAN 12': 'Ulf Dahlen',
    'W_G JAN 26': 'Wayne Gretzky',
    'JPK MAY 18': 'Jari Kurri',
    'PTK OCT 16': 'Paul Kariya',
    'TJK SEP 14': 'Tom Kurvers',
    'IAK SEP 13': 'Igor Kravchuk',
    'SPC AUG 13': 'Shayne Corson',
    'JSR JAN 17': 'Jeremy Roenick',
    'BFC DEC 18': 'Bob Corkum',
    'ARO AUG 27': 'Adam Oates',
    'DJP JAN 17': 'Derek Plante',
    'PFH MAR 9': 'Phil Housley',
    'D_S FEB 4': 'Denis Savard',
    'DRG DEC 11': 'Dave Gagner',
    'PDC JUN 1': 'Paul Coffey',
    'D_C FEB 8': 'Dino Ciccarelli',
    'DDW JAN 21': 'Doug Weight',
    'JWA OCT 11': 'Jason Arnott',
    'JDB JUN 15': 'Jesse Belanger',
    'R_T APR 9': 'Rick Tocchet',
    'P_T AUG 29': 'Pierre Turgeon',
    'CPL JUL 16': 'Claude Lemieux',
    'S_S APR 1': 'Scott Stevens',
    'RVF AUG 23': 'Ray Ferraro',
    'BJL MAR 3': 'Brian Leetch',
    'R_B JAN 9': 'Radek Bonk',
    'MBR MAY 5': 'Mikael Renberg',
    'E_D JUN 14': 'Eric Desjardins',
    'M_L OCT 5': 'Mario Lemieux',
    'O_N SEP 22': 'Owen Nolan',
    'EKT JAN 25': 'Esa Tikkanen',
    'R_H APR 12': 'Roman Hamrlik',
    'M_S FEB 13': 'Mats Sundin',
    'S_C JAN 19': 'Sylvain Cote',
    'A_Z OCT 1': 'Alexei Zhamnov',
    'D_H APR 4': 'Dale Hawerchuk',
    'DGB JUN 18': 'Doug Bodger',
    'D_K FEB 11': 'Derek King',
    'J_N SEP 10': 'Joe Nieuwendyk',
    'MAM AUG 7': 'Martin Martinez',
    'JEH JUL 13': 'Jack Haeger',
    'DOZ DEC 31': 'Bill Dabelstein',
    'CET NOV 28': 'Josh Tsui',
    'MDP JAN 13': 'Mark Penacho',
    'MAC JUL 7': 'Mary Ann Rohn',
    'CCP NOV 15': 'Carlos Pesina',
    'DJT OCT 20': 'Jim Tianis',
    'MJW JAN 9': 'Mike Waldron',
    'MXV OCT 14': 'Mike Vinikour',
    'WBD AUG 17': 'Warren Davis',
    'EJB FEB 22': 'Ed Boon',
    'TOB AUG 24': 'John Tobias',
    'SAB AUG 29': 'Steve Beran',
    'PGC APR 11': 'Pat Cox',
    'JPG JAN 23': 'Jim Gentile',
    'SAL FEB 1': 'Sal Divita',
    'NIK NOV 17': 'Nik Ehrlich',
    'EF_ JUN 10': 'Eddie Ferrier',
    'OEG NOV 5': 'Eugene Geer',
    'TWG DEC 7': 'Tony Goskie',
    'JJH MAY 3': 'Jennifer Hedrick',
    'JWH SEP 20': 'Jon Hey',
    'MJL FEB 28': 'Mike Lynch',
    'DLM AUG 6': 'Dave Michicich',
    'JMC AUG 5': 'John Carlton',
    'BRE APR 20': 'Brian Eddy',
    'ML_ MAY 25': 'Mark Loffredo',
    'CMM JUL 2': 'Cary Mednick',
    'EPJ JAN 27': 'Eugene Jarvis',
    'OTT JAN 11': 'Mike Ossian',
    'JBF JUL 17': 'Joan Faux',
    'LM_ APR 18': 'Luis Mangubat',
    'JMS JUL 29': 'Jason Skiles',
    'AL_ AUG 31': 'Al Lasko',
    'JR_ MAY 22': 'Jim Rohn',
    'RMG AUG 11': 'Ray Gay',
    'BAR DEC 5': 'Ted Barber',
    'ZAB MAY 28': 'Dave Zabloudil',
    'CLW JUL 9': 'Christa Woss',
    'PGD DEC 17': 'Paul Dussault',
    'JAH JAN 6': 'Jack A. Haeger',
    'JKF FEB 25': 'Jennifer Fedesna',
    'BMF MAY 9': 'Bridgitte Fedesna',
    'MJT MAR 22': 'Mark Turmell',
    'AJT OCT 23': 'Art Tianis',
    'JDG MAY 31': 'Jim Greene',
    'SNO JAN 3': 'Sheridan Oursler',
    'EJK APR 10': 'Ed Keenan',
    'MVB APR 18': 'Matt Booty',
    'MJD AUG 19': 'Matt Davis',
    'RSC SEP 16': 'Steve Correll',
    'JML NOV 4': 'John Lowes',
    'GWS JUN 11': 'Glenn Shipp',
    'ARM JUL 19': 'Tony Metke',
    'REM MAR 26': 'Ray Macika',
    'WKW MAY 30': 'Ken Williams',
    'JMS FEB 22': 'Jake Simpson',
    'JRN JUN 18': 'John Newcomer',
    'XC_ AUG 9': 'Xion Cooper',
    'ME_ MAY 12': 'Chris Bobrowski',
    'AL_ NOV 23': 'Andy Lycke',
    'TV_ OCT 3': 'Ted Valavanis',
    'FRS APR 13': 'Ross Shaffer',
    'KMS APR 15': 'Kevin Stevens',
    'ZBZ APR 22': 'Zarley Zalapski',
    'C_J SEP 26': 'Craig Janney',
    'G_H MAR 31': 'Gordie Howe',
    'MJC JUN 6': 'Matt Cooney',
    'J_R SEP 15': 'Kevin Daley',
    'SID FEB 12': 'Sidney Strong',
    'PJF DEC 23': 'Pat Foley',
    'RS_ SEP 27': 'Rebecca Scott',
    'HAB MAR 24': 'Heather Beach',
    'JNC JUN 4': 'Jay Cohen',
    'JBJ NOV 4': 'Jeff Johnson',
    'JTP DEC 15': 'Jeff Peters',
    'DJT JUN 4': 'Dan Thompson',
    'JH_ JUL 13': 'Evil Haeger',
}


def full_name(initials, month, day):
    """who a secret player is (initials with spaces or _, month name, day)"""
    return FULL_NAMES[f"{initials.replace(' ', '_')} {month} {day}"]


def words(rom):
    return struct.unpack("<%dH" % (len(rom) // 2), rom)


def secret_players(rom):
    """[(initials, month, day)] that can be typed, first of each in list order"""
    w = words(rom)
    for i in range(len(w) - 6):
        if w[i] == 0x09E6 and w[i + 3] == 0x5600 and w[i + 4] == 0x09EE:
            lst = w[i + 1] | (w[i + 2] << 16)
            break
    else:
        raise SystemExit("no secret player lookup (MOVI list,A6 ; CLR A0 ; MOVI entered,A14)")
    out, seen, p = [], set(), (lst - ROM_BIT) // 8
    while True:
        ptr = struct.unpack_from("<I", rom, p)[0]
        if ptr == 0:
            return out
        q = (ptr - ROM_BIT) // 8
        a, b, c, m, d = rom[q:q + 5]
        p += 4
        if max(a, b, c) > 0x1A or not 1 <= m <= 12 or not 1 <= d <= 31:
            continue
        e = ("".join(chr(65 + x) if x < 26 else " " for x in (a, b, c)), m, d)
        if e not in seen:
            seen.add(e)
            out.append(e)


def code_lists(rom):
    """[[sequence]]: the Tonight's Game list, then the face-off list"""
    w = words(rom)
    lists = []
    for i in range(len(w) - 4):
        if w[i] == 0x1869 and w[i + 1] == 0x09EA:
            lst = w[i + 2] | (w[i + 3] << 16)
            seqs, p = [], (lst - ROM_BIT) // 16
            while w[p] | w[p + 1]:
                q = ((w[p] | (w[p + 1] << 16)) - ROM_BIT) // 16
                s = []
                while not w[q] & 0x8000:
                    s.append(w[q])
                    q += 1
                seqs.append(tuple(s))
                p += 2
            lists.append(seqs)
    if len(lists) != 2:
        raise SystemExit(f"{len(lists)} code lists (MOVK 3,A9 ; MOVI list,A10), expected 2")
    return lists


def state(v):
    """a state as typed: direction, then the buttons, joined by +"""
    d = {U: "U", D: "D", L: "L", R: "R", U | L: "UL", U | R: "UR", D | L: "DL", D | R: "DR"}.get(v & 15, "")
    b = [n for m, n in ((S, "S"), (P, "P"), (T, "T")) if v & m]
    return "+".join(([d] if d else []) + b)


def notation(seq):
    """a sequence for the window: the states in order (releases left out);
    a run of joystick moves with one button held throughout is (X) moves"""
    seq = [v for v in seq if v]
    out, i = [], 0
    while i < len(seq):
        b = seq[i] & 0x70
        j = i
        while j < len(seq) and seq[j] & 0x70 == b and seq[j] & 15:
            j += 1
        if b and j - i >= 3:
            out.append("(" + state(b) + ")")
            out += [state(v & 15) for v in seq[i:j]]
            i = j
        else:
            out.append(state(seq[i]))
            i += 1
    return " ".join(out)


def tables(rom):
    players = secret_players(rom)
    codes = []
    for k, seqs in enumerate(code_lists(rom)):
        for s in seqs:
            if s not in NAMES:
                raise SystemExit(f"unnamed code: {notation(s)}")
            codes.append(("game" if k == 0 else "faceoff", NAMES[s], notation(s)))
    return players, codes


def write(rom):
    players, codes = tables(rom)
    L = ["# openice_secrets.txt - written by tools/openice_secrets.py --write; do not",
         "# edit. The secret players (initials, _ is a space; month; day), then the",
         "# codes: where they are entered, name, inputs (tools/openice_secrets.py).",
         "", "[players]"]
    L += [f"{i.replace(' ', '_')} {MONTHS[m - 1]} {d}" for i, m, d in players]
    L += ["", "[codes]"]
    L += [f"{w}|{n}|{s}" for w, n, s in codes]
    open(TXT, "w").write("\n".join(L) + "\n")


def load():
    """[(initials, month name, day)], [(where, name, inputs)]"""
    players, codes, cur = [], [], None
    for line in open(TXT, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        if line.startswith("["):
            cur = line[1:-1]
            continue
        if cur == "players":
            i, m, d = line.split()
            players.append((i.replace("_", " "), m, int(d)))
        else:
            codes.append(tuple(line.split("|")))
    return players, codes


def main():
    a = sys.argv[1:]
    if a[:1] == ["--write"] and len(a) == 2:
        write(open(a[1], "rb").read())
        print(f"written {TXT}")
        return
    if a[:1] == ["--check"] and len(a) == 2:
        players, codes = tables(open(a[1], "rb").read())
        mine = ([(i, MONTHS[m - 1], d) for i, m, d in players], codes)
        ok = load() == mine
        unnamed = [f"{i} {m} {d}" for i, m, d in mine[0] if f"{i.replace(' ', '_')} {m} {d}" not in FULL_NAMES]
        if unnamed:
            print("no full name: " + ", ".join(unnamed))
            ok = False
        print("openice_secrets.txt: " + ("OK" if ok else "differs"))
        sys.exit(0 if ok else 1)
    if len(a) == 1:
        players, codes = tables(open(a[0], "rb").read())
        print(f"{len(players)} secret players")
        for i, m, d in players:
            print(f"  {i} {MONTHS[m - 1]} {d}")
        for w, n, s in codes:
            print(f"{w:8s} {n:24s} {s}")
        return
    print("usage: see the header of " + sys.argv[0], file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    main()
