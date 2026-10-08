#!/usr/bin/env python3
# ============================================================================
#  mra_gen.py - MRA files for the Midway Wolf Unit core, from MAME source
#
#  Reads MAME 0.289's williams/midwunit.cpp (ROM definitions, GAME() lines
#  and input ports) and writes one MRA per ROM set:
#    mra/<Game> (<revision>).mra                  parent sets
#    mra/_alternatives/_<Game>/<...>.mra           clones
#  NBA Maximum Hangtime is a clone of NBA Hangtime in MAME but a game of its
#  own, so its parent set (nbamht) gets a top-level MRA too.
#
#  ROM image the core receives (MRA rom index 0, byte addresses):
#    0x000000  program ROM, 1 MB (MAME "maincpu", 16-bit little endian)
#    0x100000  DCS sound ROMs, 4 x 1 MB: the byte of chip n (u2..u5) at
#              n * 0x100000. MAME loads them as the low bytes of a 16-bit
#              region; only those bytes carry data. Missing chips are 0xFF.
#    0x500000  security PIC program, 0x2000 bytes as MAME loads it (sets
#              with a dumped PIC; zeros otherwise)
#    0x502000  graphics: the 4 MB slots of MAME's 32 MB "video" region that
#              hold data, packed in slot order. A slot not filled to 4 MB is
#              padded with zeros.
#    (end)     sets with cut-content patches (tools/cut_content.py, UMK3):
#              the program ROM again, right after the graphics, with the
#              patches applied by MRA <patch> elements; the OSD option runs
#              it instead of the first copy
#  ROM index 1 carries the core's game configuration: the game id, then for
#  each of the 8 graphics slots its packed index (FF: empty), FF, then where
#  the patched program copy starts (8 KB units, 2 bytes little endian; 0:
#  none), then the main RAM word of the game's state variable for the
#  Kombat Kode and finishing move players (MK3, UMK3: tools/kombat_kodes.py;
#  2 bytes little endian; 0: none), then (MK3, UMK3) the core's finishing
#  move table for the set (tools/finishing_moves.py: 0 none, 1 UMK3 / MK3
#  2.x, 2 MK3 1.x) and a 0.
#
#  md5: the value Main_MiSTer computes while assembling the ROM - every part
#  in MRA order (each repeat counted), before interleaving. A wrong md5 makes
#  Main_MiSTer drop the whole ROM ("md5 mismatch for rom 0"), so it is worked
#  out here by the same rules as support/arcade/mra_loader.cpp.
#
#  Checking (--check ROMDIR): every MRA is assembled from the zips exactly as
#  Main_MiSTer would (interleave maps, repeats, CRC lookup in merged sets),
#  its md5 recomputed, and the image compared byte for byte with MAME's
#  regions built from the same source. --regions DIR compares with region
#  dumps taken from MAME itself (tools/lua/dump_regions.lua), which does not
#  depend on this script's own parser.
#
#  Usage:
#    mra_gen.py --mame MAME_SRC [--out mra] [--check ROMDIR] [--regions DIR]
#
#  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
# ============================================================================

import argparse
import hashlib
import os
import re
import sys
import zipfile
import zlib
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cut_content  # noqa: E402
import finishing_moves  # noqa: E402
import kombat_kodes  # noqa: E402

# ----------------------------------------------------------------------------
# Core configuration
# ----------------------------------------------------------------------------

RBF = "Arcade-Midway-Wolf-Unit"
MAME_VERSION = "0289"
DRIVER = "src/mame/williams/midwunit.cpp"

PROG_BASE = 0x000000
DCS_BASE = 0x100000
PIC_BASE = 0x500000
GFX_BASE = 0x502000
PROG_SIZE = 0x100000
DCS_CHIP = 0x100000          # one DCS ROM chip in the image
DCS_CHIPS = 4
PIC_SIZE = 0x2000
GFX_SLOT = 0x400000          # one graphics slot (4 chips of up to 1 MB)
GFX_SLOTS = 8
NVRAM_SIZE = 0xC000          # 48 KB CMOS

# game ids (Arcade-Midway-Wolf-Unit.sv, "Game configuration")
GAME_IDS = {
    "mk3":      0,
    "umk3":     1,
    "wwfmania": 2,
    "openice":  3,
    "nbahangt": 4,
    "rmpgwt":   5,
}

# per input-port layout: MRA button names (MiSTer B1..B6 in that order) and
# the default pad mapping; players from MAME's ports
LAYOUTS = {
    "mk3":      (["High Punch", "Block", "High Kick", "Low Punch", "Low Kick", "Run"],
                 "Y,R,X,B,A,L", 2),
    "wwfmania": (["Punch", "Defense", "Power Punch", "Kick", "Power Kick"],
                 "Y,R,X,B,A", 2),
    "openice":  (["Turbo", "Shoot / Block", "Pass / Steal"], "R,B,A", 4),
    "nbahangt": (["Turbo", "Shoot / Block", "Pass / Steal"], "R,B,A", 4),
    "rmpgwt":   (["Jump", "Punch", "Kick"], "B,Y,X", 3),
}

CATEGORIES = {
    "mk3": "Fighter / Versus",
    "umk3": "Fighter / Versus",
    "wwfmania": "Fighter / Versus",
    "openice": "Sports / Hockey",
    "nbahangt": "Sports / Basketball",
    "rmpgwt": "Action / Destruction",
}

# Sets that get their own top-level MRA although MAME lists them as clones
OWN_GAME = {"nbamht"}

# MAME's DEF_STR names
DEF_STR = {
    "Off": "Off", "On": "On", "Yes": "Yes", "No": "No", "Normal": "Normal",
    "Cabinet": "Cabinet", "Coinage": "Coinage", "USA": "USA", "French": "French",
    "German": "German", "Free_Play": "Free Play", "Unused": "Unused",
    "Unknown": "Unknown", "Difficulty": "Difficulty", "Demo_Sounds": "Demo Sounds",
}


# ----------------------------------------------------------------------------
# Source parsing
# ----------------------------------------------------------------------------

def strip_comments(src):
    """Remove // and /* */ comments, leaving string literals alone."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '"':
            j = i + 1
            while j < n and src[j] != '"':
                j += 2 if src[j] == '\\' else 1
            out.append(src[i:j + 1])
            i = j + 1
        elif src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def split_args(s):
    """Split a macro argument list on top-level commas (strings and nested
    parentheses respected)."""
    args, depth, cur, i = [], 0, [], 0
    while i < len(s):
        c = s[i]
        if c == '"':
            j = i + 1
            while j < len(s) and s[j] != '"':
                j += 2 if s[j] == '\\' else 1
            cur.append(s[i:j + 1])
            i = j + 1
            continue
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
        if c == ',' and depth == 0:
            args.append("".join(cur).strip())
            cur = []
        else:
            cur.append(c)
        i += 1
    if cur or args:
        args.append("".join(cur).strip())
    return args


# A macro name followed by its parenthesised arguments. MAME source sometimes
# has a space before the bracket ("ROM_RELOAD (" - the case that once left
# two Y Unit games silent), so whitespace is allowed there.
MACRO_RE = re.compile(r"\b([A-Z][A-Z0-9_]*)\s*\(")


def macros(src):
    """Yield (name, [args]) for every macro call in src, in order."""
    pos = 0
    while True:
        m = MACRO_RE.search(src, pos)
        if not m:
            return
        start = m.end()
        depth, i = 1, start
        while i < len(src) and depth:
            if src[i] == '"':
                j = i + 1
                while j < len(src) and src[j] != '"':
                    j += 2 if src[j] == '\\' else 1
                i = j + 1
                continue
            if src[i] == '(':
                depth += 1
            elif src[i] == ')':
                depth -= 1
            i += 1
        yield m.group(1), split_args(src[start:i - 1])
        pos = i


def num(s):
    """MAME numeric literal (with optional U suffix)."""
    return int(s.strip().rstrip("uU"), 0)


def unquote(s):
    s = s.strip()
    if s.startswith('"') and s.endswith('"'):
        return s[1:-1]
    m = re.match(r"DEF_STR\s*\(\s*(\w+)\s*\)", s)
    if m:
        return DEF_STR.get(m.group(1), m.group(1).replace("_", " "))
    return s


class RomLoad:
    """One file load into a region (MAME ROM_LOAD family)."""
    def __init__(self, name, offset, length, crc, skip, group=1):
        self.name, self.offset, self.length, self.crc = name, offset, length, crc
        self.skip, self.group = skip, group      # bytes skipped after each group
        self.reloads = []                        # (offset, length) of ROM_RELOAD
        self.continues = []                      # (offset, length) of ROM_CONTINUE


class Region:
    def __init__(self, tag, size, fill):
        self.tag, self.size, self.fill = tag, size, fill
        self.loads = []
        self.fills = []                          # (offset, length, value)


class RomSet:
    def __init__(self, name):
        self.name = name
        self.regions = {}
        self.order = []


def parse_roms(src):
    """All ROM_START blocks of the driver: {set name: RomSet}."""
    sets = {}
    for m in re.finditer(r"ROM_START\s*\(\s*(\w+)\s*\)(.*?)ROM_END", src, re.S):
        rs = RomSet(m.group(1))
        region = None
        last = None
        for name, a in macros(m.group(2)):
            if name in ("ROM_REGION", "ROM_REGION16_LE", "ROM_REGION16_BE",
                        "ROM_REGION32_LE", "ROM_REGION32_BE"):
                size = num(a[0])
                tag = unquote(a[1])
                flags = a[2] if len(a) > 2 else "0"
                fill = 0xFF if "ERASEFF" in flags else 0x00
                region = Region(tag, size, fill)
                rs.regions[tag] = region
                rs.order.append(tag)
            elif name in ("ROM_LOAD", "ROM_LOAD16_BYTE", "ROM_LOAD32_BYTE",
                          "ROM_LOAD16_WORD", "ROM_LOAD64_BYTE"):
                crc = re.search(r"CRC\s*\(\s*([0-9a-fA-F]+)\s*\)", a[3])
                skip = {"ROM_LOAD": 0, "ROM_LOAD16_WORD": 0, "ROM_LOAD16_BYTE": 1,
                        "ROM_LOAD32_BYTE": 3, "ROM_LOAD64_BYTE": 7}[name]
                group = 2 if name == "ROM_LOAD16_WORD" else 1
                if name == "ROM_LOAD16_WORD":
                    skip = 0
                last = RomLoad(unquote(a[0]), num(a[1]), num(a[2]),
                               crc.group(1).lower() if crc else None, skip, group)
                region.loads.append(last)
            elif name == "ROM_RELOAD":
                last.reloads.append((num(a[0]), num(a[1])))
            elif name == "ROM_CONTINUE":
                last.continues.append((num(a[0]), num(a[1])))
            elif name == "ROM_FILL":
                region.fills.append((num(a[0]), num(a[1]), num(a[2])))
            elif name in ("CRC", "SHA1", "NO_DUMP", "BAD_DUMP", "ROM_START", "ROM_END"):
                pass
            elif name in ("ROMX_LOAD", "ROM_COPY"):
                raise SystemExit(f"{rs.name}: {name} not handled by this generator")
        sets[rs.name] = rs
    return sets


class Game:
    def __init__(self, year, name, parent, machine, inp, init, company, title):
        self.year, self.name, self.parent = year, name, parent
        self.machine, self.input, self.init = machine, inp, init
        self.company, self.title = company, title


def parse_games(src):
    games = []
    for name, a in macros(src):
        if name == "GAME" and len(a) >= 10:
            games.append(Game(a[0], a[1], a[2], a[3], a[4], a[6], unquote(a[8]), unquote(a[9])))
    return games


class Dip:
    def __init__(self, mask, default, name):
        self.mask, self.default, self.name = mask, default, name
        self.settings = []


def parse_dsw(src, ports_name):
    """The DSW port of an INPUT_PORTS block: (dips, default word)."""
    m = re.search(r"INPUT_PORTS_START\s*\(\s*%s\s*\)(.*?)INPUT_PORTS_END" % ports_name, src, re.S)
    if not m:
        raise SystemExit(f"input ports {ports_name} not found")
    port = None
    dips, default, used = [], 0, 0
    for name, a in macros(m.group(1)):
        if name == "PORT_START":
            port = unquote(a[0])
            continue
        if port != "DSW":
            continue
        if name == "PORT_DIPNAME":
            d = Dip(num(a[0]), num(a[1]), unquote(a[2]))
            dips.append(d)
            default |= d.default & d.mask
            used |= d.mask
        elif name == "PORT_DIPSETTING":
            dips[-1].settings.append((num(a[0]), unquote(a[1])))
        elif name == "PORT_BIT":
            mask = num(a[0])
            if a[1].strip() == "IP_ACTIVE_LOW":
                default |= mask
            used |= mask
    return dips, default, used


# ----------------------------------------------------------------------------
# MAME region images (as romload.cpp would build them)
# ----------------------------------------------------------------------------

class RomFiles:
    """ROM files by CRC from a folder of (merged) zips."""
    def __init__(self, romdir):
        self.by_crc = {}
        for f in sorted(os.listdir(romdir)):
            if not f.lower().endswith(".zip"):
                continue
            with zipfile.ZipFile(os.path.join(romdir, f)) as z:
                for info in z.infolist():
                    if info.is_dir():
                        continue
                    self.by_crc.setdefault("%08x" % info.CRC, (os.path.join(romdir, f), info.filename))
        self.cache = {}

    def get(self, crc):
        if crc not in self.cache:
            if crc not in self.by_crc:
                return None
            zpath, member = self.by_crc[crc]
            with zipfile.ZipFile(zpath) as z:
                data = z.read(member)
            if "%08x" % (zlib.crc32(data) & 0xFFFFFFFF) != crc:
                raise SystemExit(f"CRC mismatch reading {member} from {zpath}")
            self.cache[crc] = data
        return self.cache[crc]


def build_regions(rs, files):
    """{tag: bytearray} for a ROM set, or None if a file is missing."""
    out = {}
    for tag in rs.order:
        r = rs.regions[tag]
        img = bytearray([r.fill]) * r.size
        for off, length, value in r.fills:
            img[off:off + length] = bytes([value]) * length
        for ld in r.loads:
            data = files.get(ld.crc)
            if data is None:
                return None
            pos = 0
            for off, length in [(ld.offset, ld.length)] + ld.continues:
                place(img, off, data[pos:pos + length], ld.group, ld.skip)
                pos += length
            for off, length in ld.reloads:
                place(img, off, data[:length], ld.group, ld.skip)
        out[tag] = img
    return out


def place(img, off, data, group, skip):
    """Store data at off in groups of `group` bytes, `skip` bytes apart."""
    step = group + skip
    for k in range(group):
        img[off + k:off + k + (len(data) // group) * step:step] = data[k::group]


# ----------------------------------------------------------------------------
# MRA ROM description
#
# The ROM is a list of entries, each either
#   ("file", name, crc, map)          a whole file (map: interleave lane map)
#   ("fill", value, count)            <part repeat=count>value</part>
#   ("interleave", width, [files])    files inside <interleave output=width>
#   ("patch", offset, bytes)          <patch offset=..>: bytes written over the
#                                     image (Main_MiSTer applies them after
#                                     the data and leaves them out of the md5)
# ----------------------------------------------------------------------------

def lane_map(lane, width):
    """Main_MiSTer map string for one byte lane ("0001" = lane 0 of 4)."""
    return "".join("1" if (width - 1 - i) == lane else "0" for i in range(width))


def rom_layout(rs, regions_known=True):
    """Entries describing the core's ROM image for one set, plus the graphics
    slot map. Raises if the set does not fit the layout."""
    entries = []
    regs = rs.regions

    # ---- program ROM: 16-bit little endian, LOAD16_BYTE pairs ----
    prog = regs["maincpu"]
    if prog.size != PROG_SIZE:
        raise SystemExit(f"{rs.name}: program region size {prog.size:#x}")
    lo = [l for l in prog.loads if l.skip == 1 and l.offset % 2 == 0]
    hi = [l for l in prog.loads if l.skip == 1 and l.offset % 2 == 1]
    if len(lo) != 1 or len(hi) != 1 or lo[0].length * 2 != PROG_SIZE:
        raise SystemExit(f"{rs.name}: unexpected program ROM layout")
    entries.append(("comment", "program ROM"))
    entries.append(("interleave", 16, [(lo[0], 0), (hi[0], 1)]))

    # ---- DCS sound ROMs: chip n at region offset n * 0x200000 ----
    dcs = regs["dcs"]
    entries.append(("comment", "DCS sound ROMs"))
    for n in range(DCS_CHIPS):
        chips = [l for l in dcs.loads if l.offset == n * 2 * DCS_CHIP]
        if chips:
            ld = chips[0]
            if ld.skip != 1 or ld.length > DCS_CHIP or ld.reloads or ld.continues:
                raise SystemExit(f"{rs.name}: unexpected DCS chip {ld.name}")
            entries.append(("file", ld, None))
            if ld.length < DCS_CHIP:
                entries.append(("fill", 0xFF, DCS_CHIP - ld.length))
        else:
            entries.append(("fill", 0xFF, DCS_CHIP))
    others = [l for l in dcs.loads if l.offset % (2 * DCS_CHIP) != 0]
    if others:
        raise SystemExit(f"{rs.name}: DCS ROM at an unexpected offset")

    # ---- security PIC ----
    entries.append(("comment", "security PIC"))
    pic = regs.get("serial_security:pic")
    if pic:
        ld = pic.loads[0]
        if ld.length > PIC_SIZE or ld.skip:
            raise SystemExit(f"{rs.name}: unexpected PIC ROM")
        entries.append(("file", ld, None))
        if ld.length < PIC_SIZE:
            entries.append(("fill", 0x00, PIC_SIZE - ld.length))
    else:
        entries.append(("fill", 0x00, PIC_SIZE))

    # ---- graphics: packed 4 MB slots of LOAD32_BYTE quads ----
    gfx = regs["video"]
    if gfx.size != GFX_SLOT * GFX_SLOTS:
        raise SystemExit(f"{rs.name}: video region size {gfx.size:#x}")
    slotmap = [0xFF] * GFX_SLOTS
    used = 0
    entries.append(("comment", "graphics"))
    for s in range(GFX_SLOTS):
        base = s * GFX_SLOT
        loads = sorted([l for l in gfx.loads if base <= l.offset < base + GFX_SLOT],
                       key=lambda l: l.offset)
        if not loads:
            continue
        slotmap[s] = used
        used += 1
        pos = 0                                  # bytes of this slot emitted
        i = 0
        while i < len(loads):
            quad = loads[i:i + 4]
            q0 = quad[0].offset - base
            ok = (len(quad) == 4 and q0 % 4 == 0 and
                  all(l.skip == 3 and l.offset - base == q0 + k and
                      l.length == quad[0].length and not l.reloads and not l.continues
                      for k, l in enumerate(quad)))
            if not ok:
                raise SystemExit(f"{rs.name}: graphics slot {s} is not LOAD32_BYTE quads")
            if q0 > pos:
                entries.append(("fill", 0x00, q0 - pos))
            entries.append(("interleave", 32, [(l, k) for k, l in enumerate(quad)]))
            pos = q0 + 4 * quad[0].length
            i += 4
        if pos < GFX_SLOT:
            entries.append(("fill", 0x00, GFX_SLOT - pos))
    return entries, slotmap


def add_cut_content(entries, slotmap, family, files):
    """Append the patched program copy for a set with cut-content patches.
    Returns the copy's image offset (0: the set has none). Needs the ROM
    files: the patches are found in the program itself."""
    img, _ = assemble(entries, files)
    if img is None:
        return 0
    runs = cut_content.patches(family, img[PROG_BASE:PROG_BASE + PROG_SIZE])
    if not runs:
        return 0
    base = GFX_BASE + sum(1 for x in slotmap if x != 0xFF) * GFX_SLOT
    assert base % 0x2000 == 0 and len(img) == base
    prog = [e for e in entries if e[0] == "interleave" and e[1] == 16][0]
    entries.append(("comment", "program ROM again, patched below: the OSD's cut-content option"))
    entries.append(prog)
    for off, data in runs:
        entries.append(("patch", base + off, data))
    return base


def kode_state(entries, family, files):
    """Config bytes 12-13: the state variable the Kombat Kode player
    watches (0: the set has no kodes). Needs the ROM files."""
    img, _ = assemble(entries, files)
    if img is None:
        return 0
    return kombat_kodes.config(family, bytes(img[PROG_BASE:PROG_BASE + PROG_SIZE]))


def finish_table(entries, family, files):
    """Config byte 14: the core's finishing move table for the set (0:
    none). Needs the ROM files."""
    img, _ = assemble(entries, files)
    if img is None:
        return 0
    return finishing_moves.config(family, bytes(img[PROG_BASE:PROG_BASE + PROG_SIZE]))


def assemble(entries, files):
    """The ROM image and md5 exactly as Main_MiSTer builds them (or None, md5
    of what could be read, when a file is missing)."""
    md5 = hashlib.md5()
    img = bytearray()
    for e in entries:
        if e[0] == "comment":
            continue
        if e[0] == "fill":
            chunk = bytes([e[1]]) * e[2]
            md5.update(chunk)
            img += chunk
        elif e[0] == "file":
            data = files.get(e[1].crc) if files else None
            if data is None:
                return None, None
            md5.update(data)
            img += data
        elif e[0] == "patch":
            img[e[1]:e[1] + len(e[2])] = e[2]
        elif e[0] == "interleave":
            width = e[1] // 8
            parts = []
            for ld, lane in e[2]:
                data = files.get(ld.crc) if files else None
                if data is None:
                    return None, None
                md5.update(data)                 # read order = MRA order
                parts.append((data, lane))
            n = len(parts[0][0])
            block = bytearray(n * width)
            for data, lane in parts:
                block[lane::width] = data
            img += block
    return img, md5.hexdigest()


# ----------------------------------------------------------------------------
# Checks against MAME's regions
# ----------------------------------------------------------------------------

def check_image(name, img, slotmap, regions, alt=0, entries=()):
    """Compare the core's view of the image with MAME's regions. Returns a
    list of error strings (empty when everything matches). With a patched
    program copy at `alt`, the copy must be the program with exactly the
    patches written over it."""
    err = []

    prog = regions["maincpu"]
    if img[PROG_BASE:PROG_BASE + PROG_SIZE] != prog:
        err.append("program ROM differs")

    dcs = regions["dcs"]
    for n in range(DCS_CHIPS):
        want = bytes(dcs[n * 2 * DCS_CHIP:(n + 1) * 2 * DCS_CHIP:2])
        got = bytes(img[DCS_BASE + n * DCS_CHIP:DCS_BASE + (n + 1) * DCS_CHIP])
        if got != want:
            err.append(f"DCS chip {n} differs")
        # the high bytes MAME leaves are the region fill (0xFF)
        if set(dcs[n * 2 * DCS_CHIP + 1:(n + 1) * 2 * DCS_CHIP:2]) - {0xFF}:
            err.append(f"DCS chip {n}: high bytes are not 0xFF")

    pic = regions.get("serial_security:pic")
    if pic is not None:
        if img[PIC_BASE:PIC_BASE + len(pic)] != pic:
            err.append("PIC differs")

    gfx = regions["video"]
    for s in range(GFX_SLOTS):
        want = gfx[s * GFX_SLOT:(s + 1) * GFX_SLOT]
        if slotmap[s] == 0xFF:
            if any(want):
                err.append(f"graphics slot {s} has data but is not mapped")
        else:
            a = GFX_BASE + slotmap[s] * GFX_SLOT
            if img[a:a + GFX_SLOT] != want:
                err.append(f"graphics slot {s} differs")
    end = GFX_BASE + sum(1 for x in slotmap if x != 0xFF) * GFX_SLOT
    if alt:
        if alt != end:
            err.append(f"patched program at {alt:#x}, expected {end:#x}")
        want = bytearray(prog)
        for e in entries:
            if e[0] == "patch":
                want[e[1] - alt:e[1] - alt + len(e[2])] = e[2]
        if img[alt:alt + PROG_SIZE] != want:
            err.append("patched program copy differs")
        end = alt + PROG_SIZE
    if len(img) != end:
        err.append(f"image length {len(img):#x}, expected {end:#x}")
    return err


def load_region_dumps(rdir, setname):
    """Region dumps written by tools/lua/dump_regions.lua: <set>/<tag>.bin
    (':' in tags becomes '_')."""
    d = os.path.join(rdir, setname)
    if not os.path.isdir(d):
        return None
    out = {}
    for f in os.listdir(d):
        if f.endswith(".bin"):
            tag = f[:-4].replace("serial_security_pic", "serial_security:pic")
            with open(os.path.join(d, f), "rb") as fh:
                out[tag] = bytearray(fh.read())
    return out


# ----------------------------------------------------------------------------
# MRA writer
# ----------------------------------------------------------------------------

def xml_escape(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")


def file_name(title):
    """MRA file name for a MAME title (no characters Windows refuses)."""
    s = title.replace(": ", " - ").replace(":", "-").replace("/", "-")
    s = re.sub(r'[<>"\\|?*]', "", s)
    return s.strip()


def folder_name(title):
    """_alternatives folder: the title without its revision, no trailing dot."""
    base = re.sub(r"\s*\(.*\)\s*$", "", title)
    base = file_name(base)
    return "_" + base.replace(".", "_") if base.endswith(".") else "_" + base


def dip_xml(dips, used):
    lines = []
    for d in dips:
        bits = [b for b in range(16) if d.mask >> b & 1]
        lo, hi = bits[0], bits[-1]
        if bits != list(range(lo, hi + 1)):
            raise SystemExit(f"DIP {d.name}: mask {d.mask:#x} is not contiguous")
        names = [s[1] for s in d.settings]
        vals = [s[0] >> lo for s in d.settings]
        b = f"{lo}" if lo == hi else f"{lo},{hi}"
        attr = f'bits="{b}" name="{xml_escape(d.name)}" ids="{xml_escape(",".join(names))}"'
        if vals != list(range(len(vals))):
            attr += f' values="{",".join(str(v) for v in vals)}"'
        lines.append(f"\t\t<dip {attr}/>")
    return lines


def entry_xml(e):
    if e[0] == "comment":
        return [f"\t\t<!-- {e[1]} -->"]
    if e[0] == "fill":
        return [f'\t\t<part repeat="{e[2]:#X}">{e[1]:02X}</part>'.replace("0X", "0x")]
    if e[0] == "file":
        ld = e[1]
        return [f'\t\t<part crc="{ld.crc}" name="{xml_escape(ld.name)}"/>']
    if e[0] == "patch":
        return [f'\t\t<patch offset="0x{e[1]:07X}">' + " ".join(f"{b:02X}" for b in e[2]) + "</patch>"]
    if e[0] == "interleave":
        width = e[1] // 8
        out = [f'\t\t<interleave output="{e[1]}">']
        for ld, lane in e[2]:
            out.append(f'\t\t\t<part crc="{ld.crc}" name="{xml_escape(ld.name)}" map="{lane_map(lane, width)}"/>')
        out.append("\t\t</interleave>")
        return out
    raise ValueError(e)


def write_mra(path, game, family, zips, entries, slotmap, md5, dips, dsw_default, used, alt=0, kst=0, fin=0):
    names, pad, players = LAYOUTS[family if family != "umk3" else "mk3"]
    lines = ["<misterromdescription>"]
    lines.append(f"\t<name>{xml_escape(game.title)}</name>")
    lines.append(f"\t<mratimestamp>{date.today():%Y%m%d}</mratimestamp>")
    lines.append(f"\t<mameversion>{MAME_VERSION}</mameversion>")
    lines.append(f"\t<setname>{game.name}</setname>")
    lines.append(f"\t<year>{game.year}</year>")
    lines.append(f"\t<manufacturer>{xml_escape(game.company)}</manufacturer>")
    lines.append(f"\t<category>{CATEGORIES[family]}</category>")
    lines.append(f"\t<rbf>{RBF}</rbf>")
    lines.append(f"\t<remark>{players} players</remark>")
    lines.append(f'\t<switches default="{dsw_default & 0xFF:02X},{dsw_default >> 8:02X}">')
    lines += dip_xml(dips, used)
    lines.append("\t</switches>")
    bnames = names + ["Start", "Coin", "Test", "Pause"]
    bdef = pad.split(",") + ["Start", "Select", "-", "-"]
    lines.append(f'\t<buttons names="{",".join(bnames)}" default="{",".join(bdef)}"/>')
    nslots = sum(1 for x in slotmap if x != 0xFF)
    lines.append("\t<romstruct>")
    lines.append(f"0x{PROG_BASE:06X} program ROM (1 MB, 16-bit little endian)")
    lines.append(f"0x{DCS_BASE:06X} DCS sound ROMs (4 x 1 MB, MAME region bytes 0, 2, 4, ...)")
    lines.append(f"0x{PIC_BASE:06X} security PIC (8 KB)")
    lines.append(f"0x{GFX_BASE:06X} graphics ({nslots} x 4 MB slots of MAME's video region: "
                 + " ".join("--" if x == 0xFF else f"{i}" for i, x in enumerate(slotmap)) + ")")
    if alt:
        lines.append(f"0x{alt:07X} program ROM again with the cut-content patches (OSD)")
    lines.append("\t</romstruct>")
    cfg = [GAME_IDS[family]] + slotmap + [0xFF, (alt >> 13) & 0xFF, alt >> 21, kst & 0xFF, kst >> 8]
    if family in finishing_moves.NCHAR:
        cfg += [fin, 0]
    lines.append('\t<rom index="1">')
    lines.append("\t\t<part>" + " ".join(f"{b:02X}" for b in cfg) + "</part>")
    lines.append("\t</rom>")
    ztype = ' type="merged"' if "|" in zips else ""
    lines.append(f'\t<rom index="0" zip="{zips}" md5="{md5}"{ztype}>')
    for e in entries:
        lines += entry_xml(e)
    lines.append("\t</rom>")
    lines.append(f'\t<nvram index="2" size="{NVRAM_SIZE}"/>')
    lines.append("</misterromdescription>")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="\r\n") as f:
        f.write("\n".join(lines) + "\n")


def md5_of(entries, files):
    _, md5 = assemble(entries, files)
    return md5


# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

def family_of(game, games_by_name):
    """The game family (core game id) of a set: its MAME parent's name."""
    root = game.name if game.parent == "0" else game.parent
    return root


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--mame", required=True, help="MAME source tree (0.289)")
    ap.add_argument("--out", default="mra", help="MRA output folder")
    ap.add_argument("--check", metavar="ROMDIR", help="assemble every MRA from these zips and check it")
    ap.add_argument("--regions", metavar="DIR", help="MAME region dumps to compare with")
    ap.add_argument("--md5-from", metavar="ROMDIR",
                    help="zips to compute md5 from (default: --check folder)")
    args = ap.parse_args()

    src = strip_comments(open(os.path.join(args.mame, DRIVER), encoding="utf-8").read())
    romsets = parse_roms(src)
    games = parse_games(src)
    by_name = {g.name: g for g in games}

    files = RomFiles(args.check) if args.check else None
    md5files = RomFiles(args.md5_from) if args.md5_from else files
    if md5files is None:
        raise SystemExit("an md5 needs the ROM files: give --check or --md5-from")

    failures = 0
    for g in games:
        family = family_of(g, by_name)
        if family not in GAME_IDS:
            raise SystemExit(f"{g.name}: family {family} has no game id")
        rs = romsets[g.name]
        entries, slotmap = rom_layout(rs)
        alt = add_cut_content(entries, slotmap, family, md5files)
        kst = kode_state(entries, family, md5files)
        fin = finish_table(entries, family, md5files)
        md5 = md5_of(entries, md5files)
        if md5 is None:
            print(f"{g.name}: ROM files missing, skipped")
            failures += 1
            continue
        dips, dsw_default, used = parse_dsw(src, g.input)
        zips = f"{g.name}.zip" if g.parent == "0" else f"{g.name}.zip|{g.parent}.zip"

        # where the MRA goes: parents (and OWN_GAME sets) at the top, the
        # rest under the folder of their game
        if g.parent == "0" or g.name in OWN_GAME:
            path = os.path.join(args.out, file_name(g.title) + ".mra")
        else:
            head = by_name[g.parent]
            if g.title.startswith("NBA Maximum Hangtime"):
                head = by_name["nbamht"]
            path = os.path.join(args.out, "_alternatives", folder_name(head.title),
                                file_name(g.title) + ".mra")
        write_mra(path, g, family, zips, entries, slotmap, md5, dips, dsw_default, used, alt, kst, fin)

        status = "written"
        if files:
            img, md5chk = assemble(entries, files)
            regions = build_regions(rs, files)
            errs = check_image(g.name, img, slotmap, regions, alt, entries)
            if md5chk != md5:
                errs.append("md5 differs")
            if args.regions:
                dumps = load_region_dumps(args.regions, g.name)
                if dumps is None:
                    errs.append("no MAME region dump")
                else:
                    for tag, want in dumps.items():
                        if tag in regions and regions[tag] != want:
                            errs.append(f"parser region {tag} differs from MAME's dump")
                    errs += ["MAME dump: " + e for e in check_image(g.name, img, slotmap, dumps, alt, entries)]
            status = "OK" if not errs else "FAIL: " + "; ".join(errs)
            failures += bool(errs)
        print(f"{g.name:12s} {GAME_IDS[family]} slots "
              + "".join("-" if x == 0xFF else str(x) for x in slotmap)
              + (f" cut {alt:#x}" if alt else "")
              + (f" kodes {kst:#x}" if kst else "")
              + (f" finish {fin}" if fin else "")
              + f" {md5} {status}  {os.path.relpath(path, args.out)}")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
