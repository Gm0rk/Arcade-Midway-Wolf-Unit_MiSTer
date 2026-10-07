#!/usr/bin/env python3
# ============================================================================
#  dcs_trace.py - MAME's DCS trace against the simulator's (sim/dcs)
#
#  tools/lua/dcs_trace.lua makes MAME trace the sound DSP, each line the
#  registers before the instruction (AX0 AX1 AY0 AY1 AR AF MX0 MX1 MY0 MY1
#  MR0 MR1 MR2 MF SI SE SB SR0 SR1 I0-I7 CNTR ASTAT MSTAT IMASK PX IRQ2
#  LATCH) and "PC: disassembly"; sim/dcs/tb_dcs.cpp writes the same with
#  the opcode in place of the disassembly.
#
#    dcs_trace.py events TRACE STREAM EVENTS [-raw]
#        TRACE "-": standard input, up to a line "END" (sim/dcs/run_ref.sh
#        reads MAME's trace through a pipe, it is too big to keep).
#        Writes MAME's trace into STREAM without the main loop's waits for
#        the DAC buffer (PC 0137-0139 and 013D-013F: most of any trace; the
#        simulator leaves them out the same way) unless -raw, and the host's
#        actions for the simulator into EVENTS:
#          n W xx   a write to the input latch before instruction n (IRQ2
#                   comes on, or the latch changes while it is on)
#          n R      a host reset before instruction n (the DSP restarts at
#                   0000 without having written its system control register)
#        MAME's trace starts at the DSP's second instruction (the breakpoint
#        on the first one starts it), so STREAM gets a line for 0000 first.
#
#    dcs_trace.py compare STREAM SIM [-max N] [-ctx K]
#        the first instructions where the PC or a register differs, with K
#        lines of both traces before each
#
#    dcs_trace.py dac MAME_DAC SIM [-skip N]
#        MAME's DAC words (tools/lua/dcs_trace.lua DCS_DAC: the half buffers
#        its DCS moves out of DSP memory) against the simulator's (tb_dcs
#        -samples, or a WAV from tb_board -wav), from the first non-zero
#        word of each: how far they agree word for word, then the non-zero
#        words alone (a silence can differ in length where the DSP was
#        reset: the simulator plays out its FIFO, MAME's log only has what
#        it moved). -skip N leaves out N MAME words.
#
#  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
# ============================================================================

import sys

NAMES = ("AX0 AX1 AY0 AY1 AR AF MX0 MX1 MY0 MY1 MR0 MR1 MR2 MF SI SE SB SR0 SR1 "
         "I0 I1 I2 I3 I4 I5 I6 I7 CNTR ASTAT MSTAT IMASK PX IRQ2 LATCH").split()
NF = len(NAMES)
POLL = {
    "0137: AR = I7", "0138: AF = AR - AY0", "0139: IF GE JUMP $0137",
    "013D: AR = I7", "013E: AF = AR - AY0", "013F: IF LT JUMP $013D",
}


def split(line):
    """(fields, PC, rest) of a trace line"""
    t = line.split(None, NF)
    if len(t) <= NF:
        return None
    pc, _, rest = t[NF].partition(":")
    return t[:NF], int(pc, 16), rest.strip()


def events(trace, stream, evf, raw=False):
    out = open(stream, "w")
    ev = open(evf, "w")
    out.write(" ".join(["*"] * NF) + " 0000: JUMP\n")
    n = 1
    prev_irq, prev_latch, prev_text = 0, None, ""
    src = sys.stdin if trace == "-" else open(trace)
    for line in src:
        if line.startswith("END"):
            break
        p = split(line)
        if p is None:
            continue
        f, pc, rest = p
        text = f"{pc:04X}: {rest}"
        if not raw and text in POLL:
            continue
        if pc == 0 and "DM($3FFF)" not in prev_text:
            ev.write(f"{n} R\n")
            prev_irq, prev_latch = 0, None
        irq, latch = int(f[NAMES.index("IRQ2")], 16), f[NAMES.index("LATCH")]
        if irq and (not prev_irq or latch != prev_latch):
            ev.write(f"{n} W {latch}\n")
        prev_irq, prev_latch, prev_text = irq, latch, text
        out.write(f"{' '.join(f)} {text}\n")
        n += 1
    print(f"{n} instructions")


def compare(stream, sim, maxn=10, ctx=5):
    ref = open(stream)
    tst = open(sim)
    hist = []
    bad = 0
    i = 0
    for a, b in zip(ref, tst):
        pa, pb = split(a), split(b)
        diffs = []
        if pa[1] != pb[1]:
            diffs.append(f"PC {pa[1]:04X}/{pb[1]:04X}")
        for k in range(NF):
            if pa[0][k] == "*":
                continue
            if int(pa[0][k], 16) != int(pb[0][k], 16):
                diffs.append(f"{NAMES[k]} {pa[0][k]}/{pb[0][k]}")
        hist.append((a.rstrip(), b.rstrip()))
        if len(hist) > ctx + 1:
            hist.pop(0)
        if diffs:
            print(f"--- instruction {i}: " + ", ".join(diffs))
            for x, y in hist:
                print("  M " + x)
                print("  S " + y)
            bad += 1
            if bad >= maxn:
                break
            hist = []
        i += 1
    print(f"{i} instructions compared, {bad} differences shown")
    return bad


def mame_dac(path):
    """MAME's DAC stream: the words of its half-buffer moves (runs of more
    than 16 reads with one time stamp; the DSP's own reads are single)"""
    out, run, t0 = [], [], None
    for line in open(path):
        t = line.split()
        if len(t) < 3:
            continue
        if t[0] != t0:
            if len(run) > 16:
                out += run
            run, t0 = [], t[0]
        run.append(int(t[2], 16))
    if len(run) > 16:
        out += run
    return out


def sim_dac(path):
    if path.endswith(".wav"):
        import struct
        d = open(path, "rb").read()
        return list(struct.unpack("<%dH" % ((len(d) - 44) // 2), d[44:44 + (len(d) - 44) // 2 * 2]))
    return [int(line.split()[1], 16) for line in open(path) if len(line.split()) >= 2]


def dac(mpath, spath, skip=0):
    m, s = mame_dac(mpath)[skip:], sim_dac(spath)
    mi = next((i for i, v in enumerate(m) if v), None)
    si = next((i for i, v in enumerate(s) if v), None)
    print(f"MAME {len(m)} words, first sound at {mi}; simulator {len(s)} words, first sound at {si}")
    if mi is None or si is None:
        return 1
    m, s = m[mi:], s[si:]
    n = min(len(m), len(s))
    same = next((i for i in range(n) if m[i] != s[i]), n)
    print(f"word for word: the first {same} of {n} agree")
    mz, sz = [v for v in m if v], [v for v in s if v]
    n = min(len(mz), len(sz))
    bad = [i for i in range(n) if mz[i] != sz[i]]
    print(f"non-zero words: {n} compared, {len(bad)} differ")
    for i in bad[:10]:
        print(f"  non-zero word {i}: MAME {mz[i]:04x}, simulator {sz[i]:04x}")
    return 1 if bad else 0


def main():
    a = sys.argv[1:]
    if a and a[0] == "events" and len(a) in (4, 5):
        events(a[1], a[2], a[3], "-raw" in a)
    elif a and a[0] == "dac" and len(a) >= 3:
        skip = int(a[a.index("-skip") + 1]) if "-skip" in a else 0
        sys.exit(dac(a[1], a[2], skip))
    elif a and a[0] == "compare" and len(a) >= 3:
        maxn = int(a[a.index("-max") + 1]) if "-max" in a else 10
        ctx = int(a[a.index("-ctx") + 1]) if "-ctx" in a else 5
        sys.exit(1 if compare(a[1], a[2], maxn, ctx) else 0)
    else:
        print("usage: see the header of " + sys.argv[0], file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
