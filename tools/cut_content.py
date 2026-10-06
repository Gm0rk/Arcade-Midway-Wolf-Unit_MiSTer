#!/usr/bin/env python3
# ============================================================================
#  cut_content.py - program ROM patches for content a game left unreachable
#
#  The MRA of a set with patches loads a second copy of the program ROM after
#  the graphics, with these patches applied to it (MRA <patch> elements); the
#  OSD option runs that copy instead of the original (see "Hidden menus and
#  cut content" in Arcade-Midway-Wolf-Unit.sv). The patches are found in the
#  ROM itself by pattern, so every revision gets the same result, and each
#  search must match exactly once or the set gets no patches.
#
#  Ultimate Mortal Kombat 3 (1.0, 1.1, 1.2): CHARACTER ENDINGS in the EJB menu
#
#    MK3's EJB menu (the developers' test menu, opened by a Block button
#    code in attract mode) has a CHARACTER ENDINGS item. UMK3's menu does
#    not, but the item's string, its handler and the whole submenu (Kano to
#    Smoke) are still in the ROM, unreferenced. The submenu's common routine
#    also lost the call that shows the ending's story: it clears the screen
#    twice in a row and goes straight to the cast roll. The patches:
#      1. a copy of the EJB menu table in free ROM space with CHARACTER
#         ENDINGS inserted after ENTER INITIALS, as in MK3, and lines 11
#         pixels apart instead of 12 so the 13 items fit on the screen
#      2. the MOVI that loads the menu table pointed at the copy
#      3. in the submenu's routine, the first of the two clears replaced by
#         a call of the game's own ending-story process (the one attract
#         mode uses, character in A0), the clear kept after it:
#           GETPC A7 / ADDI 60h,A7 / MOVE A7,-*A12,1 / JA story
#           CALLA clear / NOP
#         (11 words, the size of what they replace)
#
#  Usage (check a program image, 1 MB, 16-bit little endian):
#    cut_content.py umk3 PROGRAM.BIN
#
#  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
# ============================================================================

import struct
import sys

ROM_BIT = 0xFF800000            # 34010 bit address of the program ROM's byte 0


def _bit(o):
    return ROM_BIT + o * 8


class NoMatch(Exception):
    pass


def _find_all(rom, pat):
    out = []
    i = rom.find(pat)
    while i >= 0:
        out.append(i)
        i = rom.find(pat, i + 1)
    return out


def _one(lst, what):
    if len(lst) != 1:
        raise NoMatch(f"{what}: {len(lst)} matches")
    return lst[0]


def umk3_endings(rom):
    """Word patches {offset: value} restoring CHARACTER ENDINGS in UMK3's
    EJB menu. Raises NoMatch when the ROM does not look as expected."""
    W = lambda o: struct.unpack_from("<H", rom, o)[0]
    D = lambda o: struct.unpack_from("<I", rom, o)[0]
    ptr_refs = lambda o: _find_all(rom, struct.pack("<I", _bit(o)))

    # the EJB menu table: 3 pointers (title at +8), 10 layout words, then
    # entries of {string, handler, preview} ending with a 0 string
    title = _one(_find_all(rom, b"ULTIMATE EJB MENU\0"), "menu title")
    ini = _one(_find_all(rom, b"ENTER INITIALS\0"), "ENTER INITIALS")
    tabs = []
    for r in ptr_refs(title):
        t = r - 8
        if any(D(t + 0x20 + 12 * i) == _bit(ini) for i in range(16)):
            tabs.append(t)
    tab = _one(tabs, "EJB menu table")
    e = tab + 0x20
    entries = []
    while D(e) != 0:
        entries.append(e)
        e += 12
    end = e + 4
    ini_e = _one([x for x in entries if D(x) == _bit(ini)], "ENTER INITIALS entry")
    movi = _one([r for r in ptr_refs(tab) if W(r - 2) == 0x09E8], "MOVI table,A8")

    # the cut item: its string, and its handler right after it (MOVI submenu,A8)
    s = _one(_find_all(rom, b"CHARACTER ENDINGS\0"), "CHARACTER ENDINGS")
    h = (s + 18 + 1) & ~1
    if W(h) != 0x09E8:
        raise NoMatch("CHARACTER ENDINGS handler")

    # the submenu's common routine: MMFM SP,A0 ; CALLA clear ; CALLA x ;
    # MOVI 8h,A0 ; CALLA sleep
    pats = [m for m in _find_all(rom, struct.pack("<HH", 0x09AF, 0x0001))
            if h < m < h + 0x800 and W(m + 4) == 0x0D5F and W(m + 10) == 0x0D5F
            and W(m + 16) == 0x09C0 and W(m + 18) == 8 and W(m + 20) == 0x0D5F]
    pat = _one(pats, "endings routine")
    clear = D(pat + 6)

    # the ending story process: MOVI text_table,A1 ; MOVE A1,*A13(250h),1
    story = _bit(_one([m - 6 for m in _find_all(rom, struct.pack("<HH", 0xB22D, 0x0250))
                       if W(m - 6) == 0x09E1], "ending story"))

    # free space for the table copy: the longest run of FF
    best, i = (0, 0), 0
    while i < len(rom):
        if rom[i] == 0xFF:
            j = i
            while j < len(rom) and rom[j] == 0xFF:
                j += 1
            if j - i > best[1]:
                best = (i, j - i)
            i = j
        else:
            i += 1
    new = (best[0] + 0x10) & ~0xF
    hdr = bytearray(rom[tab:tab + 0x20])
    if struct.unpack_from("<H", hdr, 0x12)[0] != 0x000C:
        raise NoMatch("menu line spacing")
    struct.pack_into("<H", hdr, 0x12, 0x000B)
    table = (bytes(hdr) + rom[tab + 0x20:ini_e + 12]
             + struct.pack("<III", _bit(s), _bit(h), 0) + rom[ini_e + 12:end])
    if new + len(table) > best[0] + best[1]:
        raise NoMatch("free space")

    p = {}
    for k in range(0, len(table), 2):
        p[new + k] = struct.unpack_from("<H", table, k)[0]
    for k, w in enumerate(struct.unpack("<HH", struct.pack("<I", _bit(new)))):
        p[movi + 2 * k] = w
    code = [0x0147, 0x0B07, 0x0060, 0xA2EC,
            0xC080, story & 0xFFFF, story >> 16,
            0x0D5F, clear & 0xFFFF, clear >> 16, 0x0300]
    for k, w in enumerate(code):
        p[pat + 4 + 2 * k] = w
    return {o: w for o, w in p.items() if W(o) != w}


def runs(words):
    """{offset: word} as a list of (offset, bytes), contiguous words merged."""
    out = []
    for o in sorted(words):
        b = struct.pack("<H", words[o])
        if out and out[-1][0] + len(out[-1][1]) == o:
            out[-1] = (out[-1][0], out[-1][1] + b)
        else:
            out.append((o, b))
    return out


# game family -> patch builder
BUILDERS = {"umk3": umk3_endings}


def patches(family, prog):
    """(offset, bytes) runs for this program image, [] when the family has
    none or the ROM does not match."""
    b = BUILDERS.get(family)
    if b is None:
        return []
    try:
        return runs(b(bytes(prog)))
    except NoMatch as e:
        print(f"cut_content: {family}: {e}, no patches", file=sys.stderr)
        return []


if __name__ == "__main__":
    fam, path = sys.argv[1], sys.argv[2]
    rs = patches(fam, open(path, "rb").read())
    for o, b in rs:
        print(f"{o:06x} {b.hex(' ')}")
    print(f"{sum(len(b) for _, b in rs) // 2} words in {len(rs)} runs")
