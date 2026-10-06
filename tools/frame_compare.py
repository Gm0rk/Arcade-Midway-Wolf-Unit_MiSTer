#!/usr/bin/env python3
# ============================================================================
#  frame_compare.py - compare simulator frames with MAME's
#
#  Both sides write a frame as 32-bit little-endian xRGB, one pixel after the
#  other over the visible picture (MAME screen:pixels(), tb_board.cpp).
#
#    frame_compare.py A.rgb B.rgb [--png out.png] [--width 400]
#      number of differing pixels; with --png, A | B | difference side by side
#    frame_compare.py --scan SIMDIR REFDIR [--offset K]
#      for every frame_NNNNN.rgb in SIMDIR, compare with REFDIR's frame
#      NNNNN + K and list the result
#    frame_compare.py --png out.png A.rgb
#      just the picture
#
#  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
# ============================================================================

import argparse
import os
import re
import struct
import sys
import zlib


def load(p):
    d = open(p, "rb").read()
    return list(struct.unpack("<%dI" % (len(d) // 4), d))


def png(path, rows):
    """Write rows (lists of 0xRRGGBB) as an RGB PNG."""
    h, w = len(rows), len(rows[0])
    raw = bytearray()
    for r in rows:
        raw.append(0)
        for p in r:
            raw += bytes(((p >> 16) & 255, (p >> 8) & 255, p & 255))

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 6)))
        f.write(chunk(b"IEND", b""))


def diff(a, b):
    return sum(1 for x, y in zip(a, b) if (x ^ y) & 0xFFFFFF) + abs(len(a) - len(b))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*")
    ap.add_argument("--png")
    ap.add_argument("--width", type=int, default=400)
    ap.add_argument("--scan", nargs=2)
    ap.add_argument("--offset", type=int, default=0)
    args = ap.parse_args()
    w = args.width

    if args.scan:
        sim, ref = args.scan
        for f in sorted(os.listdir(sim)):
            m = re.match(r"frame_(\d+)\.rgb$", f)
            if not m:
                continue
            n = int(m.group(1))
            rf = os.path.join(ref, "frame_%05d.rgb" % (n + args.offset))
            if not os.path.exists(rf):
                continue
            print("frame %5d vs MAME %5d: %6d pixels differ" % (n, n + args.offset, diff(load(os.path.join(sim, f)), load(rf))))
        return

    a = load(args.files[0])
    if len(args.files) == 1:
        png(args.png, [[p & 0xFFFFFF for p in a[i:i + w]] for i in range(0, len(a), w)])
        return
    b = load(args.files[1])
    print(diff(a, b), "pixels differ")
    if args.png:
        rows = []
        for i in range(0, min(len(a), len(b)), w):
            ra, rb = a[i:i + w], b[i:i + w]
            rd = [0xFF0000 if (x ^ y) & 0xFFFFFF else 0x202020 for x, y in zip(ra, rb)]
            rows.append([p & 0xFFFFFF for p in ra] + [0xFFFFFF] + [p & 0xFFFFFF for p in rb] + [0xFFFFFF] + rd)
        png(args.png, rows)


if __name__ == "__main__":
    main()
