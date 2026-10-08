#!/usr/bin/env python3
# ============================================================================
#  kombat_kodes.py - Kombat Kodes in the MK3 / UMK3 program ROMs
#
#  The core's Kombat Kode player (rtl/wunit_kodes.sv) needs one value from
#  each set: the main RAM word of the game's state variable, which it
#  watches for the VS screen (state 9) and the Ultimate Kombat Kode screen
#  (13h). mra_gen.py writes it to the MRA's config bytes 12-13. It is found
#  by the game's own state setter, which leaves attract mode (1) alone:
#      MOVE @state,A1,0 ; CMPI 1h,A1 ; JREQ +n ; MOVE A0,@state,0
#  (exactly one match in every revision: 0x1060960, MK3 1.0 and p4.0
#  0x10601E0).
#
#  The kodes themselves are fixed in the core. This script checks them:
#    - the OSD pages (Arcade-Midway-Wolf-Unit.sv: "Kombat Kodes" links to
#      five category pages P4-P8; status bits 18-67 in order) and the
#      player's table (rtl/wunit_kodes.sv) list the same digits in the same
#      order, and the UMK3-only lines (H6) are the ones MK3 lacks
#    - every VS screen kode the core offers for the game is in the game's
#      kode table, found by its lookup loop:
#          MOVI table,A0 ; MOVE *A0+,A1,1 ; JREQ ; CMP A1,A5
#      (six BCD digits a long; MK3 pairs each with a handler, UMK3 indexes
#      a jump table by position). The game takes the first match: MK3
#      lists 688422 twice, so its FAST UPPERCUT RECOVERY entry is never
#      reached (UMK3 moved it to 788322)
#    - UMK3: the three Ultimate Kombat Kodes. Their tables are hidden: the
#      game over code pushes a key, then adds it to each table's address
#          MOVI key,A0 ; MOVE A0,-*A12,1 ; MOVI 13h,A0 (the screen's state)
#          ... MOVI x,A7 ; ADD A0,A7 ; CALLR compare
#      and the compare takes word i of a table as digit + i
#
#  Usage:
#    kombat_kodes.py PROGRAM.BIN mk3|umk3   the image's kodes, state variable
#                                           and the check against the core
#    kombat_kodes.py --core                 the OSD page against the table
#
#  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
# ============================================================================

import os
import re
import struct
import sys

ROM_BIT = 0xFF800000            # 34010 bit address of the program ROM's byte 0
RAM_BIT = 0x01000000            # and of main RAM
RAM_WORDS = 0x40000             # 512 KB
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOP = os.path.join(REPO, "Arcade-Midway-Wolf-Unit.sv")
PLAYER = os.path.join(REPO, "rtl", "wunit_kodes.sv")
FIRST_BIT = 18                  # status bit of the first kode


class NoMatch(Exception):
    pass


def _words(rom):
    return struct.unpack("<%dH" % (len(rom) // 2), rom[:len(rom) // 2 * 2])


def _off(bit):
    return (bit - ROM_BIT) // 8


def state_var(rom):
    """Main RAM word (0-0x3FFFF) of the game's state variable."""
    w = _words(rom)
    hits = set()
    for i in range(len(w) - 8):
        if (w[i] == 0x05A1 and w[i + 3] == 0x0B41 and w[i + 4] == 0xFFFE and (w[i + 5] >> 8) == 0xCA
                and w[i + 6] == 0x0580 and w[i + 7] == w[i + 1] and w[i + 8] == w[i + 2]):
            hits.add(w[i + 1] | (w[i + 2] << 16))
    if len(hits) != 1:
        raise NoMatch(f"state setter: {len(hits)} matches")
    bit = hits.pop()
    word = (bit - RAM_BIT) >> 4
    if bit & 15 or not 0 < word < 0x10000:
        raise NoMatch(f"state variable at {bit:#x}, not a main RAM word the config can give")
    return word


def vs_kodes(rom):
    """The VS screen kode table, in order, as 6-digit strings."""
    w = _words(rom)
    tabs = []
    for i in range(len(w) - 8):
        if w[i] == 0x09E0 and w[i + 3] == 0x9601 and (w[i + 4] >> 8) == 0xCA and w[i + 5] == 0x4825:
            tab = _off(w[i + 1] | (w[i + 2] << 16))
            # MK3 steps over the handler: ADDI 20h,A0 after the compare
            pair = (0x0B00, 0x0020) in ((w[i + 6], w[i + 7]), (w[i + 7], w[i + 8]))
            tabs.append((tab, 8 if pair else 4))
    if len(tabs) != 1:
        raise NoMatch(f"kode lookup: {len(tabs)} matches")
    o, stride = tabs[0]
    out = []
    while struct.unpack_from("<I", rom, o)[0] != 0:
        out.append("%06x" % struct.unpack_from("<I", rom, o)[0])
        o += stride
    return out


def ukk_kodes(rom):
    """The Ultimate Kombat Kodes (UMK3), as 10-digit strings."""
    w = _words(rom)
    out = []
    for i in range(len(w) - 6):
        if w[i] == 0x09E0 and w[i + 3] == 0xA20C and w[i + 4] == 0x09C0 and w[i + 5] == 0x0013:
            key = w[i + 1] | (w[i + 2] << 16)
            for j in range(i, min(i + 0x800, len(w) - 4)):
                if w[j] == 0x09E7 and w[j + 3] == 0x4007 and w[j + 4] == 0x0D3F:
                    o = _off(((w[j + 1] | (w[j + 2] << 16)) + key) & 0xFFFFFFFF)
                    t = struct.unpack_from("<10H", rom, o)
                    d = [(t[k] - k) & 0xFFFF for k in range(10)]
                    if any(x > 9 for x in d):
                        raise NoMatch("Ultimate Kombat Kode table")
                    out.append("".join(map(str, d)))
    return out


def core_kodes():
    """The core's kodes: [(index, umk3 only, label, digits)] from the OSD
    page, checked against the player's table."""
    top = open(TOP, encoding="utf-8").read()
    osd = []
    for m in re.finditer(r'"(H6)?P[4-8]R\[(\d+)\],([^;]*?) (\d{3}-\d{3}|\d{5}-\d{5});"', top):
        osd.append((int(m.group(2)) - FIRST_BIT, bool(m.group(1)), m.group(3), m.group(4).replace("-", "")))
    table = {}
    for m in re.finditer(r"6'd(\d+):\s+kode = (vs|ukk)\((?:24|40)'h([0-9_]+)\)", open(PLAYER, encoding="utf-8").read()):
        table[int(m.group(1))] = m.group(3).replace("_", "")
    err = []
    if [k[0] for k in osd] != list(range(len(osd))):
        err.append("OSD kode lines are not on consecutive status bits from %d" % FIRST_BIT)
    for idx, _, label, digits in osd:
        if table.get(idx) != digits:
            err.append(f"{label}: OSD {digits}, player table {table.get(idx)}")
    if len(table) != len(osd):
        err.append(f"player table has {len(table)} kodes, the OSD {len(osd)}")
    if err:
        raise NoMatch("; ".join(err))
    return osd


def check(family, rom):
    """Problems with the core's kodes on this program image ([] when none)."""
    err = []
    try:
        kodes = core_kodes()
    except NoMatch as e:
        return [str(e)]
    try:
        table = vs_kodes(rom)
    except NoMatch as e:
        return [str(e)]
    ukk = []
    if family == "umk3":
        try:
            ukk = ukk_kodes(rom)
        except NoMatch as e:
            err.append(str(e))
    for _, umk3_only, label, digits in kodes:
        if umk3_only and family != "umk3":
            if digits in table:
                err.append(f"{label}: in the {family} table but hidden for it")
            continue
        if len(digits) == 6 and digits not in table:
            err.append(f"{label}: not in the kode table")
        if len(digits) == 10 and digits not in ukk:
            err.append(f"{label}: not an Ultimate Kombat Kode")
    return err


def config(family, rom):
    """Config bytes 12-13 for a set: the state variable's main RAM word, or
    0 when the family has no kodes or the ROM does not match."""
    if family not in ("mk3", "umk3"):
        return 0
    try:
        word = state_var(rom)
    except NoMatch as e:
        print(f"kombat_kodes: {family}: {e}, no kodes", file=sys.stderr)
        return 0
    for e in check(family, rom):
        print(f"kombat_kodes: {family}: {e}", file=sys.stderr)
    return word


def main():
    if sys.argv[1:] == ["--core"]:
        for idx, umk3_only, label, digits in core_kodes():
            print(f"{FIRST_BIT + idx:3d} {'UMK3' if umk3_only else '    '} {digits:10s} {label}")
        return
    path, family = sys.argv[1], sys.argv[2]
    rom = open(path, "rb").read()
    print(f"state variable: main RAM word {state_var(rom):#x} "
          f"(bit address {RAM_BIT + (state_var(rom) << 4):#x})")
    table = vs_kodes(rom)
    print(f"{len(table)} VS screen kodes: " + " ".join(table))
    if family == "umk3":
        print("Ultimate Kombat Kodes: " + " ".join(ukk_kodes(rom)))
    err = check(family, rom)
    print("core kodes: " + ("OK" if not err else "; ".join(err)))
    sys.exit(1 if err else 0)


if __name__ == "__main__":
    main()
