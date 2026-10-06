#!/usr/bin/env python3
# ============================================================================
#  wunit_roms.py - ROM image and configuration of one set, for simulation
#
#  Builds exactly what Main_MiSTer would send the core for a set's MRA (rom
#  index 0, assembled by the same code mra_gen.py uses) and writes:
#    <out>/<set>.rom   the ROM image (SDRAM from address 0)
#    <out>/<set>.cfg   one "key value" per line: game id, the 8 graphics slot
#                      bytes, the DIP switch default, the year, I/O remap, and
#                      where the patched program copy starts (alt, 0: none)
#
#  Usage: wunit_roms.py --mame MAME_SRC --roms ROMDIR --out DIR set [set...]
#
#  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
# ============================================================================

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mra_gen  # noqa: E402

YEARS = {"mk3": 1994, "umk3": 1994, "wwfmania": 1995, "openice": 1995, "nbahangt": 1996, "rmpgwt": 1997}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mame", required=True)
    ap.add_argument("--roms", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("sets", nargs="+")
    args = ap.parse_args()

    src = mra_gen.strip_comments(open(os.path.join(args.mame, mra_gen.DRIVER), encoding="utf-8").read())
    romsets = mra_gen.parse_roms(src)
    games = {g.name: g for g in mra_gen.parse_games(src)}
    files = mra_gen.RomFiles(args.roms)
    os.makedirs(args.out, exist_ok=True)

    for name in args.sets:
        g = games[name]
        family = g.name if g.parent == "0" else g.parent
        entries, slotmap = mra_gen.rom_layout(romsets[name])
        alt = mra_gen.add_cut_content(entries, slotmap, family, files)
        img, md5 = mra_gen.assemble(entries, files)
        if img is None:
            raise SystemExit(f"{name}: ROM files missing")
        _, dsw, _ = mra_gen.parse_dsw(src, g.input)
        with open(os.path.join(args.out, name + ".rom"), "wb") as f:
            f.write(img)
        with open(os.path.join(args.out, name + ".cfg"), "w") as f:
            f.write(f"game {mra_gen.GAME_IDS[family]}\n")
            f.write("slots " + " ".join(f"{s:02x}" for s in slotmap) + "\n")
            f.write(f"dsw {dsw:04x}\n")
            f.write(f"year {YEARS[family]}\n")
            f.write(f"io_remap {1 if family == 'wwfmania' else 0}\n")
            f.write(f"alt {alt:x}\n")
            f.write(f"md5 {md5}\n")
        print(f"{name}: {len(img):#x} bytes, md5 {md5}")


if __name__ == "__main__":
    main()
