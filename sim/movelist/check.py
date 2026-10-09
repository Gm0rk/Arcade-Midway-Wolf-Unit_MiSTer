#!/usr/bin/env python3
# ============================================================================
#  check.py - the Move List window's frames against tools/move_list.py
#
#  Runs obj_dir/Vwunit_movelist for each page (and once with the window
#  off) and compares every dot of the picture with the page drawn here from
#  tools/move_list.py's pages and font: the test picture dimmed to a quarter,
#  the characters in their colours on the 7 x 8 grid at dot 4, line 7.
#
#  Usage: check.py [PAGE ...]      (default: every page)
#
#  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
# ============================================================================

import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools"))
import move_list as ml  # noqa: E402

W, H, X0, Y0, CW, CH = 400, 254, 4, 7, 7, 8
INK = {0: (0xFF, 0xFF, 0xFF), 1: (0xFF, 0xE0, 0x40), 2: (0x60, 0xE0, 0xFF), 3: (0xA0, 0xA0, 0xA0)}
SIM = os.path.join(HERE, "obj_dir", "Vwunit_movelist")


def expected(rows, font):
    img = bytearray()
    for y in range(H):
        for x in range(W):
            img += bytes([(x & 0xFF) >> 2, (y & 0xFF) >> 2, 0x80 >> 2])
    for r, row in enumerate(rows):
        if not row:
            continue
        col = row[0]
        for t, colour in row[1]:
            for ch in t:
                glyph = font[ord(ch) - 32]
                for ly in range(CH):
                    for px in range(CW):
                        if glyph[ly] >> px & 1:
                            i = ((Y0 + r * CH + ly) * W + X0 + col * CW + px) * 3
                            img[i:i + 3] = bytes(INK[colour])
                col += 1
    return bytes(img)


def frame(page, off=False):
    with tempfile.NamedTemporaryFile(suffix=".ppm") as f:
        r = subprocess.run([SIM, str(page), f.name] + (["-off"] if off else []), capture_output=True, text=True)
        data = open(f.name, "rb").read()
    return r, data[data.index(b"255\n") + 4:]


def main():
    pages = ml.pages()
    font = ml.font_rows()
    which = [int(a) for a in sys.argv[1:]] or range(len(pages))
    bad = 0
    r, _ = frame(0, off=True)
    print(r.stdout.strip())
    bad += r.returncode != 0
    for k in which:
        label, rows = pages[k]
        _, got = frame(k)
        want = expected(rows, font)
        diff = sum(1 for i in range(0, len(want), 3) if got[i:i + 3] != want[i:i + 3])
        print(f"page {k:2d} {label:24s} {'OK' if not diff else f'{diff} dots differ'}")
        bad += diff != 0
    print("all OK" if not bad else f"{bad} failed")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
