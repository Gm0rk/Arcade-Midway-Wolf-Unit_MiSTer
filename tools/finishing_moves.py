#!/usr/bin/env python3
# ============================================================================
#  finishing_moves.py - the finishing moves of the MK3 / UMK3 program ROMs
#
#  The core's finishing move player (rtl/wunit_finish.sv) enters a picked
#  move on the winner's controls. Its programs (rtl/wunit_finish_moves.vh)
#  come from the games' own move tables, read here out of the program ROM:
#
#    - a button event (press of HP LP BL HK LK RN U D L R, release of HP LP
#      BL HK LK RN) is looked up in a table of 32-bit pointers, one list per
#      event, one entry per character (found by the dispatch code:
#          MOVI press,A4 ; MOVE A3,A3 ; JRNE +3 ; MOVI release,A4
#      ), each pointing at a stub that loads the character's move table
#      (MOVI table,A14) and joins the matcher
#    - a move table entry is 22 words: the buttons allowed to be held as it
#      fires (P1, P2 masks of the IN1:IN0 word), a type, a condition routine
#      (distance, round, ...), the move's handler, the frames the sequence
#      may take, then the sequence twice (facing right, facing left): codes
#      0-5 HP LP BL HK LK RN in the button history, 6-9 U D L R in the
#      joystick history, newest first, 0 ends
#    - the finishing moves are the entries whose handler is shared by many
#      characters: by type 3 the Mercy, 6 Friendship, 7 Babality, 4/5
#      Animality; the Stage Fatality's condition first reads the stage
#      (MOVE @stage,A0,0 ; JREQ ; CMPI ...); the two most common type 2
#      handlers are Fatality 1 and 2 (in address order)
#    - a condition that starts with MOVI m,A0 ; MOVI m',A1 ; CALL to the
#      exact-buttons check wants exactly those buttons held as the move
#      fires; one that starts with a call to a joystick check (BTST n,A0 on
#      the joystick bits) wants that direction held
#
#  From that, each move becomes a program for the player: the sequence
#  tapped (4 frames each, 4 apart) and the firing input; Block held through
#  a joystick sequence with Up in it (so the fighter does not jump), let go
#  before the end where the move does not allow it held; a released
#  button held 66 frames before its sequence (the Mercy wants Run held 48);
#  buttons and directions the condition wants held, held. tools/lua/
#  finishing_moves.lua plays every program in MAME at each distance; the
#  distances in WHERE below are what it measured.
#
#  The games have two tables: UMK3 (all revisions) and MK3 2.0 / 2.1 share
#  one (MK3 has its first 15 characters, and Kano a second way into his
#  Animality, not used), MK3 1.0 and the p4.0 chip set have their own
#  (other fatalities, one Stage Fatality for everybody, no Babalities).
#  mra_gen.py writes which one a set has into config byte 14.
#
#  Usage:
#    finishing_moves.py PROGRAM.BIN mk3|umk3   the image's moves, the table
#                                              it matches
#    finishing_moves.py --write UMK3.BIN MK3R10.BIN
#                                              write rtl/wunit_finish_moves.vh
#                                              and print the OSD lines
#    finishing_moves.py --check                the OSD page against the
#                                              programs and the labels
#    finishing_moves.py --list                 the core's moves
#    finishing_moves.py --mame WTUNIT ROMDIR SET OUTDIR [--winner 1|2]
#        [--chars N,..] [--slots N,..] [--dists D,..|label]
#        [--rtl sim/finish/obj_dir/Vwunit_finish]
#                                              play the moves in MAME (MAME's
#                                              wtunit binary, a set of SETS):
#                                              at each distance, or at each
#                                              end of WHERE and its middle
#                                              (label); --rtl plays what the
#                                              core's player puts out
#
#  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
# ============================================================================

import os
import re
import struct
import sys

ROM_BIT = 0xFF800000            # 34010 bit address of the program ROM's byte 0
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOP = os.path.join(REPO, "Arcade-Midway-Wolf-Unit.sv")
VH = os.path.join(REPO, "rtl", "wunit_finish_moves.vh")

# the game's character numbers
CHARS = ["Kano", "Sonya", "Jax", "Nightwolf", "Sub-Zero", "Stryker", "Sindel", "Sektor", "Cyrax",
         "Kung Lao", "Kabal", "Sheeva", "Shang Tsung", "Liu Kang", "Smoke", "Kitana", "Jade",
         "Mileena", "Scorpion", "Reptile", "Ermac", "Classic Sub-Zero", "Human Smoke"]
NCHAR = {"mk3": 15, "umk3": 23}
SLOTS = ["Fatality 1", "Fatality 2", "Stage Fatality", "Animality", "Friendship", "Babality", "Mercy"]
MERCY = 6
TABLES = {1: "UMK3, MK3 2.x", 2: "MK3 1.x"}
HOLDW = 66                      # frames a released button is held before its sequence

CODE = {0: "HP", 1: "LP", 2: "BL", 3: "HK", 4: "LK", 5: "RN", 6: "U", 7: "D", 8: "L", 9: "R"}
EVENT = ["HP", "LP", "BL", "HK", "LK", "RN", "U", "D", "L", "R"]
MASK = {"HP": 0x10, "BL": 0x20, "HK": 0x40, "LP": 0x10000, "LK": 0x20000, "RN": 0x40000}
DIR = {"L": "B", "R": "F"}      # facing right
JOY = ("U", "D", "L", "R")

# the step encoding (rtl/wunit_finish.sv): [15:13] op, [9:0] U D F B HP LP HK LK BL RN
INPUT_BIT = {"U": 9, "D": 8, "F": 7, "B": 6, "HP": 5, "LP": 4, "HK": 3, "LK": 2, "BL": 1, "RN": 0}
OP_TAP, OP_HOLD, OP_REL, OP_WAIT, OP_TIME = 1, 2, 3, 4, 5


class NoMatch(Exception):
    pass


class Rom:
    def __init__(self, rom):
        self.w = struct.unpack("<%dH" % (len(rom) // 2), rom[:len(rom) // 2 * 2])
        hits = []
        w = self.w
        for i in range(len(w) - 8):
            if w[i] == 0x09E4 and w[i + 3] == 0x4C63 and w[i + 4] == 0xCB03 and w[i + 5] == 0x09E4:
                hits.append((w[i + 1] | (w[i + 2] << 16), w[i + 6] | (w[i + 7] << 16)))
        if len(hits) != 1:
            raise NoMatch(f"move dispatch: {len(hits)} matches")
        self.press, self.release = hits[0]

    def i(self, bit):
        return (bit - ROM_BIT) // 16

    def ok(self, bit, n=1):
        return 0 <= self.i(bit) and self.i(bit) + n < len(self.w) and bit % 16 == 0

    def d32(self, bit):
        i = self.i(bit)
        return self.w[i] | (self.w[i + 1] << 16)

    def table_of(self, stub):
        """the move table a character's stub loads into A14"""
        if not self.ok(stub, 16):
            return None
        i = self.i(stub)
        for k in range(12):
            if self.w[i + k] == 0x09EE:
                return self.w[i + k + 1] | (self.w[i + k + 2] << 16)
        return None

    def entries(self):
        out = []
        for kind, disp, events in (("press", self.press, 10), ("release", self.release, 6)):
            for ev in range(events):
                lst = self.d32(disp + 32 * ev)
                for c in range(len(CHARS)):
                    if not self.ok(lst + 32 * c, 2):
                        continue
                    stub = self.d32(lst + 32 * c)
                    t = self.table_of(stub) if stub else None
                    n = 0
                    while t is not None and self.ok(t, 22) and self.d32(t) != 0 and n < 40:
                        e = self.w[self.i(t):self.i(t) + 22]
                        out.append(dict(kind=kind, event=ev, char=c, addr=t, m0=e[0] | (e[1] << 16), type=e[4],
                                        cond=e[5] | (e[6] << 16), hnd=e[7] | (e[8] << 16), lim=e[9],
                                        seq=e[10:16], seq_left=e[16:22]))
                        t += 0x160
                        n += 1
        return out

    def is_stage_cond(self, c):
        if not self.ok(c, 5):
            return False
        i = self.i(c)
        return self.w[i] == 0x05A0 and (self.w[i + 3] >> 8) == 0xCA and self.w[i + 4] == 0x0B40

    def call_target(self, at):
        """target of the CALLR / JR (long) / CALLA / JA at `at`, else None"""
        i = self.i(at)
        op = self.w[i]
        if op in (0x0D3F, 0xC000):
            d = self.w[i + 1] - (0x10000 if self.w[i + 1] & 0x8000 else 0)
            return (at + 0x20 + d * 16) & 0xFFFFFFFF
        if op in (0x0D5F, 0xC080):
            return self.w[i + 1] | (self.w[i + 2] << 16)
        return None

    def never(self, c):
        """the condition can never pass: no path from it reaches SETC (it
        follows the few instructions condition routines use; anything else
        counts as a pass)"""
        seen = set()
        todo = [c]
        while todo:
            a = todo.pop()
            while True:
                if a in seen or not self.ok(a, 3):
                    break
                seen.add(a)
                w = self.w[self.i(a)]
                nxt = []
                if w == 0x0DE0:                                   # SETC
                    return False
                if w in (0x0960, 0x0320):                         # RETS, CLRC
                    if w == 0x0960:
                        break
                    size = 1
                elif w in (0x0D5F, 0x0D3F):                       # CALLA, CALLR
                    size = 3 if w == 0x0D5F else 2
                elif (w & 0xFFF0) in (0x09E0, 0x05A0, 0x07A0, 0x0B60) or (w & 0xFFE0) == 0x0B80:
                    size = 3                                      # MOVI L, MOVE @, CMPI L, ANDI
                elif (w & 0xFFF0) in (0x09C0, 0x0B40) or (w & 0xFE00) == 0xB400 or (w & 0xFE00) == 0xB600:
                    size = 2                                      # MOVI W, CMPI W, MOVE *Rs(d)
                elif (w & 0xF000) == 0xC000:                      # jumps
                    cond = (w >> 8) & 15
                    lo = w & 0xFF
                    if lo == 0x00:
                        d = self.w[self.i(a) + 1]
                        t, size = (a + 0x20 + (d - (0x10000 if d & 0x8000 else 0)) * 16) & 0xFFFFFFFF, 2
                    elif lo == 0x80:
                        t, size = self.d32(a + 16), 3
                    else:
                        t, size = (a + 0x10 + (lo - (0x100 if lo & 0x80 else 0)) * 16) & 0xFFFFFFFF, 1
                    if cond == 0:
                        a = t
                        continue
                    nxt.append(t)
                elif (w & 0xFC00) in (0x1C00, 0x4800, 0x4C00, 0x1800, 0x1000, 0x1400) or w in (0x01E0, 0x01C0):
                    size = 1                                      # BTST K, CMP, MOVE Rs,Rd, MOVK, ADDK, SUBK, PUSHST, POPST
                else:
                    return False
                todo += nxt
                a += size * 16
        return True

    def held_exact(self, c):
        """buttons the condition wants held (exactly) as the move fires"""
        if not self.ok(c, 8):
            return 0
        i = self.i(c)
        w = self.w
        if w[i] != 0x09E0 or w[i + 3] != 0x09E1:
            return 0
        t = self.call_target(c + 0x60)
        # the check: MOVE @p1obj,A4,1 ; CMP A4,A8 ; JREQ +1 ; MOVE A1,A0 ;
        # CALLR buttons ; CMP A2,A0 ; JRNE
        if t is None or not self.ok(t, 8):
            return 0
        j = self.i(t)
        if w[j + 3:j + 7] != (0x4888, 0xCA01, 0x4C20, 0x0D3F) or w[j + 8] != 0x4840:
            return 0
        return (w[i + 1] | (w[i + 2] << 16)) & 0x00070070

    def held_dir(self, c):
        """a direction the condition wants held as the move fires"""
        if not self.ok(c, 3) or self.w[self.i(c)] != 0x0D5F:
            return None
        t = self.call_target(c)
        if t is None or not self.ok(t, 4):
            return None
        j = self.i(t)
        b = self.w[j + 2]
        # CALLR joystick bits ; BTST n,A0 ; JRNE
        if self.w[j] != 0x0D3F or (b & 0xFC1F) != 0x1C00 or (self.w[j + 3] >> 8) != 0xCB:
            return None
        return {0: "U", 1: "D", 2: "B", 3: "F"}.get(31 - ((b >> 5) & 31))


def classify(rom, ents):
    """{handler: slot} for the finishing moves"""
    from collections import Counter
    hm = {}
    def top(es, n=1):
        c = Counter(e["hnd"] for e in es if e["hnd"] not in hm)
        return [h for h, k in c.most_common(n) if k >= 3]
    for h in top([e for e in ents if e["type"] == 3]):
        hm[h] = MERCY
    for h in top([e for e in ents if rom.is_stage_cond(e["cond"])]):
        hm[h] = 2
    for t, slot in ((6, 4), (7, 5)):
        for h in top([e for e in ents if e["type"] == t]):
            hm[h] = slot
    for h in top([e for e in ents if e["type"] in (4, 5)]):
        hm[h] = 3
    for k, h in enumerate(sorted(top([e for e in ents if e["type"] == 2], 2))):
        hm[h] = k
    return hm


def codes(ws):
    s = []
    for x in ws:
        if x == 0:
            break
        s.append(CODE.get(x, "?"))
    return list(reversed(s))


PERIOD = 8                      # frames from one tap to the next
FAST = {6: "t:3/3", 4: "t:2/2"} # shorter taps, for sequences that need them


def before(e):
    """the sequence's inputs before the firing one"""
    s = codes(e["seq"])
    trig = EVENT[e["event"]]
    joy = bool(s) and s[0] in JOY
    if e["kind"] == "press" and s and (joy == (trig in JOY)) and s[-1] == trig:
        s = s[:-1]
    return s


def period(e):
    """the tap period the entry's time limit allows: the frames from its
    first input to the firing one (a release fires at the end of the last
    gap)"""
    for p in (PERIOD, 6, 4):
        if p * len(before(e)) <= e["lim"]:
            return p
    return None


def slack(e):
    """frames the entry's time limit leaves over its sequence"""
    p = period(e)
    return -1 if p is None else e["lim"] - p * len(before(e))


def delay(e, earlier):
    """frames to wait before the firing input so that no earlier entry of
    the same table (checked first) takes the sequence's tail as its own:
    an earlier entry whose sequence is a tail of this one's fires only if
    the input comes within its time limit"""
    s = codes(e["seq"])
    p = period(e)
    d = 0
    for x in earlier:
        t = codes(x["seq"])
        if not t or len(t) > len(s) or s[len(s) - len(t):] != t or (x["m0"] & e["m0"] & 0x00070070) == 0:
            continue
        # x's first matched input is tapped p * len(before(x)) before the firing one
        d = max(d, x["lim"] - p * len(before(x)) + 3)
    return d


def program(rom, e, wait=0):
    """the player's program for a move table entry (facing right)"""
    fast = [FAST[period(e)]] if period(e) != PERIOD else []
    s = codes(e["seq"])
    trig = EVENT[e["event"]]
    if e["kind"] == "release":
        return " ".join(fast + [f"hold:{trig}", f"w:{HOLDW}"] + [DIR.get(x, x) for x in s] + [f"rel:{trig}"])
    joy = bool(s) and s[0] in JOY
    # the history the sequence is in ends with the firing input itself
    if s and (joy == (trig in JOY)) and s[-1] == trig:
        s = s[:-1]
    S = [DIR.get(x, x) for x in s]
    T = DIR.get(trig, trig)
    exact = rom.held_exact(e["cond"])
    need = [b for b in MASK if exact & MASK[b] and b != T]
    allow = (e["m0"] | exact) & 0x00070070
    dheld = rom.held_dir(e["cond"])
    out = []
    if joy:
        hs = list(need)
        if "U" in S and "BL" not in hs:
            hs.append("BL")
        if hs:
            out.append("hold:" + "+".join(hs))
        body = S[:]
        if dheld:
            k = len(body) - 1 - body[::-1].index(dheld)
            body[k] = "hold:" + dheld
        out += body
        letgo = [b for b in hs if not allow & MASK[b] or b == T]
        if letgo:
            out.append("rel:" + "+".join(letgo))
        out.append(T)
        rest = [b for b in hs if b not in letgo] + ([dheld] if dheld else [])
        if rest:
            out.append("rel:" + "+".join(rest))
    else:
        body = S[:]
        for b in need:
            if body and body[-1] == b:
                body[-1] = "hold:" + b
            else:
                body.append("hold:" + b)
        out = body + [T]
        if need:
            out.append("rel:" + "+".join(need))
    if wait:
        k = out.index(T)
        out[k:k] = [f"w:{wait}"]
    return " ".join(fast + out)


def rom_moves(rom_bytes, family):
    """{(char, slot): program} of a program image: of the entries for a
    move, the one with the most frames to spare"""
    rom = Rom(rom_bytes)
    ents = rom.entries()
    hm = classify(rom, ents)
    best = {}
    for k, e in enumerate(ents):
        slot = hm.get(e["hnd"])
        if slot is None or e["char"] >= NCHAR[family] or rom.never(e["cond"]):
            continue
        if e["kind"] == "release" and EVENT[e["event"]] == "LK":
            continue
        key = (e["char"], slot)
        # the sequence for facing left must be the mirror of the one for
        # facing right (one of Stryker's Friendships has none)
        mirror = [{8: 9, 9: 8}.get(x, x) for x in e["seq"]]
        if mirror != list(e["seq_left"]):
            continue
        if period(e) is not None and (key not in best or slack(e) > slack(ents[best[key]])):
            best[key] = k
    out = {}
    for key, k in best.items():
        e = ents[k]
        same = [x for x in ents[:k] if (x["char"], x["kind"], x["event"]) == (e["char"], e["kind"], e["event"])]
        d = delay(e, same) if e["kind"] == "press" else 0
        if d and d > slack(e):
            raise NoMatch(f"{CHARS[e['char']]} {SLOTS[key[1]]}: an earlier move takes its tail")
        out[key] = program(rom, e, d)
    # an Animality needs a Mercy first (MK3 1.x's Cyrax has none)
    for c, slot in list(out):
        if slot == 3 and (c, MERCY) not in out:
            del out[(c, slot)]
    return out


# ----------------------------------------------------------------------------
# The core: programs, OSD page
# ----------------------------------------------------------------------------

# the OSD's character lists (alphabetical), as game numbers
OPT_ORDER = {
    "mk3": sorted(range(15), key=lambda c: CHARS[c]),
    "umk3": sorted(range(23), key=lambda c: CHARS[c]),
}
OPT_BITS = "O[72:68]"           # the character option
FIRST_R = 103                   # status bits of the slots (R[103]-R[109])
GROUP = "0789A"                 # menu mask bits: character / 5 (one-hot) ...
INDEX = "BCDEF"                 # ... and character % 5; set = hide
OLD_TABLE = "3"                 # set unless the MK3 1.x table (MK3 / UMK3 only)

# Where the winner must stand for each move (the distance between the
# fighters' X positions in pixels when it is picked), as tools/lua/
# finishing_moves.lua measured it in MAME 0.289 in steps of 10, a few edges
# in steps of 5 (30: as close as the fighters get, 310: as far): the OSD
# labels come from these. Slots as SLOTS; None: no such move.
WHERE = {
    1: {
        'Kano': ((120, 160), (30, 90), (30, 70), (30, 70), (30, 310), (30, 310)),
        'Sonya': ((30, 310), (200, 310), (30, 80), (30, 70), (30, 310), (30, 310)),
        'Jax': ((30, 70), (200, 310), (30, 70), (30, 90), (30, 310), (30, 310)),
        'Nightwolf': ((30, 70), (140, 190), (30, 70), (30, 80), (160, 310), (30, 310)),
        'Sub-Zero': ((110, 150), (30, 70), (30, 80), (30, 70), (30, 310), (30, 310)),
        'Stryker': ((280, 310), (30, 80), (30, 70), (80, 110), (30, 310), (30, 310)),
        'Sindel': ((30, 70), (80, 130), (30, 70), (30, 310), (30, 310), (30, 310)),
        'Sektor': ((90, 130), (200, 260), (30, 70), (30, 80), (190, 310), (30, 310)),
        'Cyrax': ((30, 70), (30, 310), (30, 70), (30, 70), (30, 310), (30, 310)),
        'Kung Lao': ((30, 310), (30, 100), (30, 80), (30, 70), (90, 310), (30, 310)),
        'Kabal': ((90, 210), (30, 60), (30, 60), (30, 90), (30, 310), (30, 310)),
        'Sheeva': ((30, 80), (30, 80), (30, 70), (30, 70), (30, 310), (30, 310)),
        'Shang Tsung': ((30, 80), (30, 70), (30, 70), (110, 150), (30, 310), (30, 310)),
        'Liu Kang': ((30, 310), (30, 310), (30, 70), (80, 130), (30, 310), (30, 310)),
        'Smoke': ((200, 310), (110, 150), (30, 80), None, (200, 310), (30, 310)),
        'Kitana': ((30, 90), (30, 70), (30, 70), (70, 100), (30, 310), (30, 310)),
        'Jade': ((30, 70), (30, 70), (30, 80), (30, 80), (30, 310), (30, 310)),
        'Mileena': ((230, 310), (30, 70), (30, 70), (30, 80), (30, 310), (30, 310)),
        'Scorpion': ((30, 70), (150, 210), (30, 70), (30, 70), (30, 110), (30, 310)),
        'Reptile': ((170, 220), (90, 110), (30, 70), (30, 70), (30, 115), (30, 310)),
        'Ermac': ((90, 180), (30, 70), (30, 70), None, None, None),
        'Classic Sub-Zero': ((30, 70), None, (30, 80), None, None, None),
        'Human Smoke': (None, (30, 70), (30, 70), None, None, (30, 310)),
    },
    2: {
        'Kano': ((120, 160), (30, 90), (30, 90), (30, 70), None, (30, 310)),
        'Sonya': ((30, 310), None, (30, 90), (30, 70), None, None),
        'Jax': ((30, 70), (200, 310), (30, 90), (30, 90), None, None),
        'Nightwolf': ((30, 90), (140, 190), (30, 100), (30, 70), None, None),
        'Sub-Zero': ((120, 160), (30, 70), (30, 90), (30, 70), None, None),
        'Stryker': ((280, 310), (30, 80), (30, 100), (80, 110), None, None),
        'Sindel': ((30, 70), (70, 130), (30, 90), (30, 310), None, None),
        'Sektor': ((70, 110), (200, 260), (30, 90), (30, 70), None, None),
        'Cyrax': ((30, 70), (30, 310), (30, 90), None, None, None),
        'Kung Lao': ((30, 310), (30, 150), (30, 90), (30, 70), None, None),
        'Kabal': ((100, 220), (30, 310), (30, 80), None, None, None),
        'Sheeva': ((30, 90), (30, 100), (30, 90), (30, 70), None, None),
        'Shang Tsung': ((30, 70), (30, 70), (30, 90), (110, 150), None, None),
        'Liu Kang': ((30, 310), (30, 310), (30, 90), (80, 130), None, None),
        'Smoke': (None, None, None, (180, 310), None, None),
    },
}
MERCY_WHERE = {1: (160, 300), 2: (120, 300)}


# the words for a distance (the OSD's labels; README "Finishing Moves")
CLOSE, SWEEP, OUTSIDE, HALF = 90, 130, 165, 260


def words(lo, hi):
    """lo is the first distance it worked at (the edge lies just below), hi
    the last (the edge lies just above)"""
    def cat(x, near):
        e = [CLOSE, SWEEP, OUTSIDE, HALF]
        return sum(1 for t in e if (x >= t if near else x > t))
    if hi >= 290:
        return ["Anywhere", "Not close", "Past sweep", "Half or full", "Full screen"][cat(lo, True)]
    a, b = cat(lo, True), cat(hi, False)
    if a == b:
        return ["Close", "Sweep", "Outside sweep", "Half screen", "Full screen"][a]
    return ["Close", "Sweep", "Outside", "Half", "Full"][a] + "-" + ["close", "sweep", "outside", "half", "full"][b]


def steps(prog):
    """a program as step words"""
    out = []
    for tok in prog.split():
        if tok.startswith("t:"):
            h, g = map(int, tok[2:].split("/"))
            out.append((OP_TIME << 13) | (h << 4) | g)
            continue
        if tok.startswith("w:"):
            n = int(tok[2:])
            if not 0 < n < 256:
                raise NoMatch(f"wait {n}")
            out.append((OP_WAIT << 13) | n)
            continue
        op = OP_TAP
        for pre, o in (("hold:", OP_HOLD), ("rel:", OP_REL)):
            if tok.startswith(pre):
                op, tok = o, tok[len(pre):]
        bits = 0
        for k in tok.split("+"):
            bits |= 1 << INPUT_BIT[k]
        out.append((op << 13) | bits)
    return out + [0]


def where(table, c, s):
    """(nearest, farthest) the winner stands for a move, or None"""
    if s == MERCY:
        return MERCY_WHERE[table]
    row = WHERE[table].get(CHARS[c])
    return row[s] if row else None


def distance(table, c, s):
    w = where(table, c, s)
    return words(*w) if w else "?"


def label(programs, table, c, s):
    name = SLOTS[s]
    if s in (0, 1) and sum(1 for k in (0, 1) if (c, k) in programs[table]) == 1:
        name = "Fatality"
    return f"{name}: {distance(table, c, s)}"


def vh(programs):
    """rtl/wunit_finish_moves.vh for {table: {(char, slot): program}}"""
    words = [0]
    start = {}
    seen = {}
    for t in sorted(programs):
        for key in sorted(programs[t]):
            p = programs[t][key]
            if p not in seen:
                seen[p] = len(words)
                words += steps(p)
            start[(t, key)] = seen[p]
    if len(words) > 2048:
        raise NoMatch(f"{len(words)} steps, the player has room for 2048")
    L = ["//============================================================================",
         "//  The finishing move programs of rtl/wunit_finish.sv",
         "//",
         "//  Written by tools/finishing_moves.py --write from the games' move tables",
         "//  (see there); do not edit. Table 1: UMK3, MK3 rev 2.0 / 2.1; table 2: MK3",
         "//  rev 1.0, p4.0. idx_a = {table 2, character, slot}.",
         "//",
         "//  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later",
         "//============================================================================",
         "",
         "// the OSD's character lists (alphabetical) to the game's numbers",
         "function automatic [4:0] opt_char(input u, input [4:0] o);",
         "\tcase ({u, o})"]
    for g, u in (("mk3", 0), ("umk3", 1)):
        for k, c in enumerate(OPT_ORDER[g]):
            L.append(f"\t\t6'h{u * 32 + k:02X}: opt_char = 5'd{c};{' ' * (3 - len(str(c)))}// {CHARS[c]}")
    L += ["\t\tdefault: opt_char = 5'd0;", "\tendcase", "endfunction", "",
          "always @(posedge clk) begin",
          "\tcase (idx_a)"]
    for (t, (c, s)), a in sorted(start.items(), key=lambda x: ((x[0][0] == 2) * 256 + x[0][1][0] * 8 + x[0][1][1])):
        idx = (t == 2) * 256 + c * 8 + s
        L.append(f"\t\t9'h{idx:03X}: idx_q <= 11'd{a};{' ' * (5 - len(str(a)))}// {CHARS[c]}, {SLOTS[s]}: {programs[t][(c, s)]}")
    L += ["\t\tdefault: idx_q <= 11'd0;", "\tendcase", "end", "", "always @(posedge clk) begin", "\tcase (pc)"]
    for i, w in enumerate(words):
        if w:
            L.append(f"\t\t11'd{i}:{' ' * (5 - len(str(i)))}step <= 16'h{w:04X};")
    L += ["\t\tdefault: step <= 16'h0000;", "\tendcase", "end", ""]
    return "\n".join(L)


def osd_lines(programs):
    """the OSD page's lines (CONF_STR strings)"""
    L = ['"H2P9,Finishing Moves;",', '"P9-;",',
         '"h6P9%s,Character,%s;",' % (OPT_BITS, ",".join(CHARS[c] for c in OPT_ORDER["mk3"])),
         '"H6P9%s,Character,%s;",' % (OPT_BITS, ",".join(CHARS[c] for c in OPT_ORDER["umk3"])),
         '"P9-;",']
    for c in range(len(CHARS)):
        pre = f"H{GROUP[c // 5]}H{INDEX[c % 5]}"
        for s in range(MERCY):
            a = (c, s) in programs[1] and label(programs, 1, c, s)
            b = (c, s) in programs[2] and label(programs, 2, c, s)
            if a and a == b:
                L.append(f'"{pre}P9R[{FIRST_R + s}],{a};",')
                continue
            if a:
                L.append(f'"{pre}{"h" + OLD_TABLE if c < 15 else ""}P9R[{FIRST_R + s}],{a};",')
            if b:
                L.append(f'"{pre}H{OLD_TABLE}P9R[{FIRST_R + s}],{b};",')
    L.append('"P9-;",')
    m1, m2 = distance(1, -1, MERCY), distance(2, -1, MERCY)
    if m1 == m2:
        L.append(f'"P9R[{FIRST_R + MERCY}],Mercy: {m1};",')
    else:
        L.append(f'"h{OLD_TABLE}P9R[{FIRST_R + MERCY}],Mercy: {m1};",')
        L.append(f'"H{OLD_TABLE}P9R[{FIRST_R + MERCY}],Mercy: {m2};",')
    return L


def core_programs():
    """{table: {(char, slot): program}} from rtl/wunit_finish_moves.vh"""
    out = {1: {}, 2: {}}
    for m in re.finditer(r"9'h([0-9A-F]{3}): idx_q <= 11'd\d+;\s*// ([^,]+), ([^:]+): (.*)", open(VH).read()):
        i = int(m.group(1), 16)
        out[2 if i & 0x100 else 1][((i >> 3) & 31, i & 7)] = m.group(4).strip()
    return out


def which(rom_bytes, family):
    """the core's table for a program image (0: none), and the differences
    to the closest one"""
    mine = rom_moves(rom_bytes, family)
    core = core_programs()
    best, diff = 0, None
    for t in (1, 2):
        ref = {k: v for k, v in core[t].items() if k[0] < NCHAR[family]}
        d = sorted(set(ref.items()) ^ set(mine.items()))
        if diff is None or len(d) < len(diff):
            best, diff = t, d
    return (best if not diff else 0), diff


def config(family, rom_bytes):
    """Config byte 14 for a set (mra_gen.py): the core's table for its
    finishing moves, 0 when the family has none or no table matches."""
    if family not in NCHAR:
        return 0
    try:
        t, diff = which(rom_bytes, family)
    except NoMatch as e:
        print(f"finishing_moves: {family}: {e}", file=sys.stderr)
        return 0
    if not t:
        print(f"finishing_moves: {family}: no table matches ({len(diff)} differences)", file=sys.stderr)
    return t


def check_core():
    """the OSD page in the top level against the programs and WHERE"""
    programs = core_programs()
    want = [re.sub(r'^"|",$', "", l) for l in osd_lines(programs)]
    top = open(TOP, encoding="utf-8").read()
    have = re.findall(r'"([^"]*P9[^"]*)"', top)
    err = []
    if have != want:
        for a, b in zip(have + [""] * len(want), want + [""] * len(have)):
            if a != b:
                err.append(f"OSD has {a!r}, expected {b!r}")
                break
        err.append(f"{len(have)} OSD lines, expected {len(want)}")
    return err


# ----------------------------------------------------------------------------
# MAME (tools/lua/finishing_moves.lua)
# ----------------------------------------------------------------------------

# the sets: family, state variable word, the core's table
SETS = {
    "umk3": ("umk3", 0x6096, 1), "umk3r11": ("umk3", 0x6096, 1), "umk3r10": ("umk3", 0x6096, 1),
    "mk3": ("mk3", 0x6096, 1), "mk3r20": ("mk3", 0x6096, 1), "mk3r10": ("mk3", 0x601E, 2), "mk3p40": ("mk3", 0x601E, 2),
}
DISTS = list(range(30, 320, 10))
MERCY_DISTS = list(range(100, 320, 20))



def rtl_frames(sim, family, kst, table, winner, c, slot):
    """what the core's player holds a frame, as sim/finish prints it"""
    import subprocess
    args = [sim, "-table", str(table), "-winner", str(winner), "-opt", str(OPT_ORDER[family].index(c)),
            "-char", str(c), "-slot", str(slot), "-kstate", f"{kst:x}"] + (["-umk3"] if family == "umk3" else []) + \
           (["-left"] if winner == 2 else [])
    lines = subprocess.run(args, capture_output=True, text=True, check=True).stdout.split("\n")
    if [l for l in lines if l.startswith("info")] != ["info 6"]:
        raise NoMatch(f"{CHARS[c]} {SLOTS[slot]}: the player says {lines[:3]}")
    return " ".join("r:%s.%s" % tuple(l.split()) for l in lines if len(l.split()) == 2 and not l.startswith("info"))


def mame(args):
    """--mame WTUNIT ROMDIR SET OUTDIR [--rtl SIM] [--winner 2] [--chars N,..]
    [--slots N,..] [--dists D,..|label]: every move of the set's characters
    in MAME"""
    import subprocess
    import tempfile
    wtunit, romdir, sset, outdir = args[:4]
    opt = dict(zip(args[4::2], args[5::2]))
    family, kst, table = SETS[sset]
    winner = int(opt.get("--winner", "1"))
    chars = [int(x) for x in opt["--chars"].split(",")] if "--chars" in opt else range(NCHAR[family])
    slots = [int(x) for x in opt["--slots"].split(",")] if "--slots" in opt else range(len(SLOTS))
    dists = [int(x) for x in opt["--dists"].split(",")] if opt.get("--dists", "label") != "label" else DISTS
    lua = os.path.join(REPO, "tools", "lua", "finishing_moves.lua")
    programs = core_programs()[table]
    for c in chars:
        d = os.path.join(outdir, f"{sset}_{c}")
        os.makedirs(d, exist_ok=True)
        lines = []
        for (cc, s), p in sorted(programs.items()):
            if cc != c or s not in slots:
                continue
            if "--rtl" in opt:
                p = rtl_frames(opt["--rtl"], family, kst, table, winner, c, s)
            kind = {3: "a", MERCY: "m"}.get(s, "f")
            # label: each end of the window (5 in: player 2 stands a pixel
            # off player 1) and the middle
            w = where(table, c, s)
            ds = sorted({w[0] + (5 if w[0] > 30 else 0), (w[0] + w[1]) // 2, w[1] - (5 if w[1] < 310 else 0)}) \
                if opt.get("--dists") == "label" else MERCY_DISTS if s == MERCY else dists
            lines.append(f"c{c}s{s} {kind} {','.join(map(str, ds))} {p}")
        open(os.path.join(d, "tests.txt"), "w").write("\n".join(lines) + "\n")
        with tempfile.TemporaryDirectory() as tmp:
            env = dict(os.environ, FM_TESTS=os.path.join(d, "tests.txt"), FM_OUT=d, FM_KSTATE=f"{kst:x}",
                       FM_UMK3="1" if family == "umk3" else "0", FM_P1=str(c if winner == 1 else 0),
                       FM_P2=str(c if winner == 2 else 0), FM_STAGE="a", FM_WINNER=str(winner),
                       FM_LEAD="0" if "--rtl" in opt else "10",
                       FM_MERCY=programs.get((c, MERCY), "hold:RN w:66 D D rel:RN"))
            subprocess.run([wtunit, sset, "-rompath", romdir, "-state_directory", tmp, "-nvram_directory", tmp,
                            "-cfg_directory", tmp, "-video", "none", "-sound", "none", "-nothrottle",
                            "-skip_gameinfo", "-autoboot_script", lua], env=env, capture_output=True)
        res = {}
        for line in open(os.path.join(d, "results.txt")):
            t = line.split()
            if len(t) == 4 and t[0].startswith("c"):
                slot = int(t[0].split("s")[1])
                ok = t[3] == ("revived" if slot == MERCY else f"type{EXPECT[slot]}")
                res.setdefault(slot, []).append((int(t[2]), ok))
            elif t and t[0] != "done":
                print(f"{CHARS[c]}: {line.strip()}")
        for slot, r in sorted(res.items()):
            good = [m for m, ok in r if ok]
            bad = [m for m, ok in r if not ok]
            print(f"{sset} {CHARS[c]:17s} {SLOTS[slot]:15s} {distance(table, c, slot):14s} "
                  + (f"{min(good)}-{max(good)}" if good else "NONE") + (f", not at {bad}" if bad else ""), flush=True)


EXPECT = {0: 1, 1: 1, 2: 2, 3: 3, 4: 4, 5: 5}


def main():
    a = sys.argv[1:]
    if a[:1] == ["--mame"] and len(a) >= 5:
        mame(a[1:])
        return
    if a[:1] == ["--write"] and len(a) == 3:
        programs = {1: rom_moves(open(a[1], "rb").read(), "umk3"), 2: rom_moves(open(a[2], "rb").read(), "mk3")}
        open(VH, "w").write(vh(programs))
        print("\n".join("\t" + l for l in osd_lines(programs)))
        return
    if a == ["--check"]:
        err = check_core()
        print("core: " + ("OK" if not err else "; ".join(err)))
        sys.exit(1 if err else 0)
    if a == ["--list"]:
        programs = core_programs()
        for t in (1, 2):
            print(f"table {t} ({TABLES[t]}):")
            for (c, s), p in sorted(programs[t].items()):
                print(f"  {CHARS[c]:17s} {SLOTS[s]:15s} {distance(t, c, s):14s} {p}")
        return
    if len(a) == 2 and a[1] in NCHAR:
        rom = open(a[0], "rb").read()
        for (c, s), p in sorted(rom_moves(rom, a[1]).items()):
            print(f"{CHARS[c]:17s} {SLOTS[s]:15s} {p}")
        t, diff = which(rom, a[1])
        print(f"core table: {t} ({TABLES.get(t, 'none')})" + ("" if t else f", {len(diff)} differences: {diff[:6]}"))
        sys.exit(0 if t else 1)
    print("usage: see the header of " + sys.argv[0], file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    main()
