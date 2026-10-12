#!/usr/bin/env python3
# ============================================================================
#  movelist_logo.py - the game logos behind the Move List and Secret Codes
#  windows (MK3, UMK3, Open Ice, NBA Hangtime, NBA Maximum Hangtime)
#
#  rtl/wunit_movelist.sv draws a game's Move List or Secret Codes page over
#  its logo instead of the dimmed game. A logo is a picture of the game's title (any size;
#  its middle 4:3 is used, as the board's 400 x 254 picture is shown 4:3)
#  brought down to 200 x 127 (each dot drawn 2 x 2) and 16 colours, the
#  colours dimmed (DIM) so the text over it reads. This writes two ROM
#  images for $readmemh:
#
#    rtl/wunit_movelist_logo.hex  127000 x 4 bits: the colour of each dot,
#                                 25400 a logo in LOGOS order, row by row
#    rtl/wunit_movelist_pal.hex   80 x 24 bits: the colours (RGB), 16 a logo
#
#  The pictures are not in the repository (the logos are Midway's).
#
#  Usage:
#    movelist_logo.py --write MK3.png UMK3.png OPENICE.png NBAHANGT.png NBAMHT.png
#                                 write the two ROM images (one picture a
#                                 logo, in LOGOS order)
#    movelist_logo.py --check MK3.png UMK3.png OPENICE.png NBAHANGT.png NBAMHT.png
#                                 the ROM images against them
#    movelist_logo.py --show OUT.png
#                                 the logos as the window draws them (no text)
#
#  Needs Pillow.
#
#  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
# ============================================================================

import os
import sys

from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = {k: os.path.join(REPO, "rtl", f"wunit_movelist_{k}.hex") for k in ("logo", "pal")}

W, H = 200, 127                     # the logo's dots (2 x 2 picture dots each)
COLOURS = 16
LOGOS = ["mk3", "umk3", "openice", "nbahangt", "nbamht"]   # in ROM order (the window's logo 1-5)
# colour x a / b: the text reads over it (the busier or brighter the
# picture, the darker)
DIM = {"mk3": (3, 8), "umk3": (5, 16), "openice": (3, 16), "nbahangt": (1, 4), "nbamht": (1, 4)}


def convert(path, name):
    """(dots [W * H] colour numbers, palette [16] (r, g, b)) of a picture"""
    im = Image.open(path).convert("RGB")
    w, h = im.size
    cw = min(w, h * 4 // 3)
    ch = min(h, w * 3 // 4)
    x0, y0 = (w - cw) // 2, (h - ch) // 2
    im = im.crop((x0, y0, x0 + cw, y0 + ch)).resize((W, H), Image.LANCZOS)
    q = im.quantize(colors=COLOURS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    pal = q.getpalette()[:COLOURS * 3]
    pal += [0] * (COLOURS * 3 - len(pal))
    a, b = DIM[name]
    pal = [tuple(pal[3 * i + k] * a // b for k in range(3)) for i in range(COLOURS)]
    return list(q.tobytes()), pal


def images(paths):
    """the two ROM images' lines"""
    dots, pals = [], []
    for name, p in zip(LOGOS, paths):
        d, pal = convert(p, name)
        dots += d
        pals += pal
    return ["%X" % d for d in dots], ["%02X%02X%02X" % c for c in pals]


def read(name):
    return [l.strip() for l in open(OUT[name]) if l.strip()]


def show(out):
    dots = [int(x, 16) for x in read("logo")]
    pal = [tuple(int(x[i:i + 2], 16) for i in (0, 2, 4)) for x in read("pal")]
    im = Image.new("RGB", (400, 254 * len(LOGOS)))
    for k in range(len(LOGOS)):
        for y in range(254):
            for x in range(400):
                im.putpixel((x, 254 * k + y), pal[16 * k + dots[W * H * k + W * (y >> 1) + (x >> 1)]])
    im.save(out)


def main():
    a = sys.argv[1:]
    if a[:1] in (["--write"], ["--check"]) and len(a) == 1 + len(LOGOS):
        logo, pal = images(a[1:])
        if a[0] == "--write":
            open(OUT["logo"], "w").write("\n".join(logo) + "\n")
            open(OUT["pal"], "w").write("\n".join(pal) + "\n")
            print(f"written {OUT['logo']} ({len(logo)} dots), {OUT['pal']}")
            return
        ok = read("logo") == logo and read("pal") == pal
        print("logo ROM images: " + ("OK" if ok else "differ"))
        sys.exit(0 if ok else 1)
    if a[:1] == ["--show"] and len(a) == 2:
        show(a[1])
        return
    print("usage: see the header of " + sys.argv[0], file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    main()
