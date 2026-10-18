#!/usr/bin/env python3
# ============================================================================
#  move_list.py - the pages of the Move List window (MK3, UMK3) and the
#  Secret Codes window (NBA Hangtime, NBA Maximum Hangtime, 2 On 2 Open Ice
#  Challenge)
#
#  The OSD's "Move List" option (Off or a fighter) has rtl/wunit_movelist.sv
#  draw a window over the game's logo (tools/movelist_logo.py) with the
#  fighter's moves: the special moves (tools/move_list.txt, from MAME's
#  command.dat), Shang Tsung's morphs, and the finishing moves with their
#  names, inputs and where to stand (tools/finishing_moves.py: the programs
#  the core enters, in the same notation as the OSD lines, and the
#  distances it measured).
#
#  One page per fighter and game: UMK3 (pages 0-22), MK3 rev 2.x (23-37),
#  MK3 rev 1.x / p4.0 (38-52), each in the OSD's order (alphabetical,
#  finishing_moves.OPT_ORDER), so the option picks page first + n - 1. The
#  Hangtimes' Secret Codes window (tools/hangtime_secrets.py: the secret
#  players and match-up codes the program ROMs hold, with who each player
#  is) has two pages per variant from 53 on (variant v: 51 + 2v the secret
#  players and match-up codes, 52 + 2v the hidden NBA players) and page 61,
#  shown when the MRA names no variant; Open Ice's (tools/openice_secrets.py)
#  pages 62-64 the secret players with who they are, 65 the Tonight's Game
#  codes, 66 the face-off codes. Long full names that do not fit two to a
#  row lose their first name to an initial. A page
#  is 30 rows of 56 characters; a row is a list of segments, runs of text in
#  one colour (the blanks between them are not stored). This writes four
#  ROM images for $readmemh:
#
#    rtl/wunit_movelist_row.hex   4096 x 12 bits, address {page, row}: the
#                                 row's first segment (0: empty row)
#    rtl/wunit_movelist_seg.hex   4096 x 29 bits, a segment: [13:0] its
#                                 first character in the text ROM, [19:14]
#                                 its length, [25:20] its column, [27:26]
#                                 its colour (0 white, 1 yellow, 2 cyan,
#                                 3 gray), [28] the row's last segment
#    rtl/wunit_movelist_text.hex  16384 x 7 bits: the character codes - 32
#                                 (segments with the same text share it)
#    rtl/wunit_movelist_font.hex  96 x 8 rows of 8 bits (bit x: column x,
#                                 the left one bit 0), characters 32-127
#
#  The font is the MiSTer OSD's (Main_MiSTer charrom.cpp, GPL-3.0), so the
#  window reads like the OSD.
#
#  Usage:
#    move_list.py --write          write the four ROM images
#    move_list.py --check          the ROM images against the sources
#    move_list.py --show [PAGE|all]
#                                  print pages as text
#
#  Copyright (C) 2026 Gm0rk - GPL-3.0-or-later
# ============================================================================

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import finishing_moves as fm  # noqa: E402
import hangtime_secrets as hs  # noqa: E402
import openice_secrets as oi  # noqa: E402

REPO = fm.REPO
TXT = os.path.join(REPO, "tools", "move_list.txt")
OUT = {k: os.path.join(REPO, "rtl", f"wunit_movelist_{k}.hex") for k in ("row", "seg", "text", "font")}

COLS, ROWS = 56, 30
LEFT, RIGHT = 1, 54                 # the columns text uses
PAGES = 128                         # row ROM pages (67 used)
HANGTIME_PAGE = 53                  # the Secret Codes window's first page (Hangtimes)
OPENICE_PAGE = 62                   # Open Ice's first
SEG_SIZE = 4096                     # segment ROM entries
TEXT_SIZE = 16384                   # text ROM characters
WHITE, YELLOW, CYAN, GRAY = range(4)

# the games: (set in move_list.txt, the finishing moves table, family, logo, title)
GAMES = [
    ("umk3", 1, "umk3", 2, "Ultimate Mortal Kombat 3"),
    ("mk3", 1, "mk3", 1, "Mortal Kombat 3 rev 2"),
    ("mk3r10", 2, "mk3", 1, "Mortal Kombat 3 rev 1"),
]

FOOTER = [
    [("F", YELLOW), (" toward the opponent   ", GRAY), ("A+B", YELLOW), (" at once   ", GRAY),
     (",", YELLOW), (" let go, go on", GRAY)],
    [("(X)", YELLOW), (" hold X until the end   ", GRAY), ("(air)", YELLOW),
     (" also in the air", GRAY)],
]

# Main_MiSTer charrom.cpp, characters 32-127: 8 bytes each, byte i column i,
# bit b row b (the top row bit 0)
FONT = [
    "0000000000000000 00006F6F00000000 0503000005030000 147F7F147F140000",  #  !"#
    "48DC745C76240000 4C2A166854320000 20744A5E34605000 0000050300000000",  # $%&'
    "00001C3E63410000 41633E1C00000000 082A1C1C2A080000 08083E3E08080000",  # ()*+
    "0000A06000000000 0808080808080000 0000606000000000 6030180C06030000",  # ,-./
    "3E7F415D7F3E0000 00017F7F00000000 717949494F460000 414949497F360000",  # 0123
    "1C1E137F7F100000 4F4F494979310000 3E7F494979310000 0101797D07030000",  # 4567
    "367F49497F360000 464F49497F3E0000 00006C6C00000000 0000AC6C00000000",  # 89:;
    "081C366341000000 0014141414000000 004163361C080000 060751590F060000",  # <=>?
    "3E7F415D5F4E0000 7E7F09097F7E0000 7F7F49497F360000 3E7F414141410000",  # @ABC
    "7F7F41417F3E0000 3E7F494941410000 7E7F090901010000 3E7F41497B7B0000",  # DEFG
    "7F7F08087F7F0000 00007F7F00000000 606040407F3F0000 7F7F081C77630000",  # HIJK
    "3F7F404040400000 7F7F060C067F7F00 7F7F0C187F7F0000 7E7F41417F3F0000",  # LMNO
    "7F7F09090F060000 7E7F41F1FF3F0000 7F7F09097F760000 464F494979310000",  # PQRS
    "01017F7F01010000 3F7F40407F7F0000 1F3F60603F1F0000 7F7F3018307F7F00",  # TUVW
    "63771C1C77630000 070F78780F070000 6171594D47430000 00007F7F41410000",  # XYZ[
    "03060C1830600000 41417F7F00000000 080C0603060C0800 8080808080808000",  # \]^_
    "0000030500000000 387C44447C7C0000 3F7F44447C380000 387C444444440000",  # `abc
    "387C44447F3F0000 387C54545C580000 00087E7F09010000 98BCA4A4FC780000",  # defg
    "7F7F04047C780000 00007D7D00000000 8080FD7D00000000 7F7F10107C6C0000",  # hijk
    "00007F7F40000000 7C7C0C180C7C7800 7C7C04047C780000 387C44447C380000",  # lmno
    "F8FC44447C380000 387C4444FCF80000 7C7C080404040000 485C545474240000",  # pqrs
    "00043F7F44400000 3C7C40407C7C0000 1C3C60603C1C0000 3C7C6030607C3C00",  # tuvw
    "6C6C10106C6C0000 9CBCA0A0FC7C0000 646454544C4C0000 08083E7741410000",  # xyz{
    "0000777700000000 4141773E08080000 1008081810100800 7F7F7F7F7F7F7F00",  # |}~.
]


def font_rows():
    """96 x 8 row bytes (bit x: column x)"""
    cols = [bytes.fromhex(w) for line in FONT for w in line.split()]
    assert len(cols) == 96, len(cols)
    return [[sum(((c[x] >> y) & 1) << x for x in range(8)) for y in range(8)] for c in cols]


# ----------------------------------------------------------------------------
# the moves
# ----------------------------------------------------------------------------

def specials():
    """{(set, character): [(name, input, morph)]} from move_list.txt"""
    out, cur = {}, None
    for line in open(TXT, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line.strip() or line.startswith("#"):
            continue
        if line.startswith("["):
            g, c = line[1:-1].split(" ", 1)
            cur = out.setdefault((g, c), [])
            continue
        morph = line.startswith("- ")
        if morph:
            line = line[2:]
        name, inp = line.split("  ", 1)
        cur.append((name.strip(), inp.strip(), morph))
    return out


def finishing(programs, table, c):
    """[(name, input, stand)] in slot order, the Mercy last"""
    out = []
    for s in range(fm.MERCY):
        if (c, s) in programs[table]:
            name = fm.move_name(programs, table, c, s)
            if s == 2:
                name = "Stage Fatality"
            if s == 3 and fm.CHARS[c] in fm.ANIMALS:
                name = "Animality: " + fm.ANIMALS[fm.CHARS[c]]
            out.append((name, fm.notation(programs[table][(c, s)]), fm.distance(table, c, s)))
    # the Mercy, where the fighter has one (MK3 1.x's Cyrax has none)
    if (c, fm.MERCY) in programs[table]:
        m = programs[table][(c, fm.MERCY)]
        out.append(("Mercy", fm.notation(m), fm.distance(table, c, fm.MERCY)))
    return out


# ----------------------------------------------------------------------------
# the pages: a row is (column, [(text, colour)]) or None
# ----------------------------------------------------------------------------

def row(*segs, col=LEFT):
    return (col, [s for s in segs if s[0]])


def width(r):
    return sum(len(t) for t, _ in r[1]) if r else 0


def pad(segs, n):
    """segments padded with spaces to n characters"""
    w = sum(len(t) for t, _ in segs)
    return segs + [(" " * (n - w), WHITE)] if n > w else segs


def morph_rows(morphs):
    """Shang Tsung's morphs, two columns; the long ones a row each"""
    LW, RW = 27, RIGHT - 28            # left: columns 1-27, right: 29-54
    short = [m for m in morphs if len(m[0]) + 1 + len(m[1]) <= RW]
    long_ = [m for m in morphs if m not in short]
    half = (len(short) + 1) // 2
    left, right = short[:half], short[half:]
    nl = max(len(n) for n, _, _ in left)
    nr = max(len(n) for n, _, _ in right) if right else 0
    if any(nl + 1 + len(i) > LW for _, i, _ in left):
        nl = 0
    if any(nr + 1 + len(i) > RW for _, i, _ in right):
        nr = 0
    out = []
    for k in range(half):
        n, i, _ = left[k]
        segs = pad([(n, WHITE), (" " * max(1, nl - len(n) + 1), WHITE), (i, YELLOW)], 28)
        if k < len(right):
            n2, i2, _ = right[k]
            segs += [(n2, WHITE), (" " * max(1, nr - len(n2) + 1), WHITE), (i2, YELLOW)]
        out.append(row(*segs))
    for n, i, _ in long_:
        out.append(row((n, WHITE), (" ", WHITE), (i, YELLOW)))
    return out


def page(game, table, c, programs, sp):
    name = fm.CHARS[c]
    title = GAMES[[g[0] for g in GAMES].index(game)][4]
    moves = sp[(game, name)]
    fin = finishing(programs, table, c)
    body = [row((name.upper(), CYAN), (" " * (RIGHT - LEFT + 1 - len(name) - len(title)), WHITE), (title, GRAY)),
            None,
            row(("SPECIAL MOVES", CYAN))]
    nw = max(len(n) for n, _, m in moves if not m) + 2
    nw = max(nw, 26)
    for n, i, m in moves:
        if not m:
            body.append(row((n.ljust(nw), WHITE), (i, YELLOW)))
    morphs = [m for m in moves if m[2]]
    if morphs:
        body.append(row(("MORPHS", CYAN)))
        body += morph_rows(morphs)
    body.append(None)
    fw = max(len(n) for n, _, _ in fin) + 2
    iw = max(len(i) for _, i, _ in fin) + 2
    sw = max(len(s) for _, _, s in fin)
    if nw + iw + sw <= RIGHT - LEFT + 1:
        fw = max(fw, nw)               # the inputs under the special moves'
    if fw + iw + sw > RIGHT - LEFT + 1:
        raise SystemExit(f"{game} {name}: the finishing moves need {fw + iw + sw} columns")
    head = "DISTANCE"
    body.append(row(("FINISHING MOVES", CYAN), (" " * (fw + iw - 15), WHITE), (head, CYAN)))
    for n, i, s in fin:
        body.append(row((n, WHITE), (" " * (fw - len(n)), WHITE), (i, YELLOW), (" " * (iw - len(i)), WHITE),
                        (s, GRAY)))
    foot = [row(*f) for f in FOOTER]
    rows = body + [None] * (ROWS - len(body) - len(foot)) + foot
    if len(rows) > ROWS:
        # no room for the blank lines: drop them, then the footer's second line
        body = [r for r in body if r is not None]
        rows = body + [None] * (ROWS - len(body) - len(foot)) + foot
        if len(rows) > ROWS:
            rows = body + [None] * (ROWS - len(body) - 1) + foot[:1]
    if len(rows) > ROWS:
        raise SystemExit(f"{game} {name}: {len(rows)} rows")
    for r in rows:
        if r and r[0] + width(r) - 1 > RIGHT:
            raise SystemExit(f"{game} {name}: too wide: {''.join(t for t, _ in r[1])!r}")
    return rows


def fit(rows, label):
    """the page's rows, checked"""
    if len(rows) > ROWS:
        raise SystemExit(f"{label}: {len(rows)} rows")
    for r in rows:
        if r and r[0] + width(r) - 1 > RIGHT:
            raise SystemExit(f"{label}: too wide: {''.join(t for t, _ in r[1])!r}")
    return rows + [None] * (ROWS - len(rows))


def columns(items, ncol, nrows):
    """items laid out down ncol columns: [[item or None] * ncol] * nrows"""
    return [[items[c * nrows + r] if c * nrows + r < len(items) else None for c in range(ncol)]
            for r in range(nrows)]


def title_row(left, right):
    return row((left, CYAN), (" " * (RIGHT - LEFT + 1 - len(left) - len(right)), WHITE), (right, GRAY))


def shorten(name):
    """a full name with its first name cut to an initial"""
    first, _, rest = name.partition(" ")
    return f"{first[0]}. {rest}" if rest and len(first) > 2 else name


def two_columns(cells, label):
    """cells (code segments of one width, full name) down two columns: the
    rows. The names are gray; a name too long for the page loses its first
    name to an initial"""
    cells = [(segs, name) for segs, name in cells]
    nrows = -(-len(cells) // 2)
    w0 = sum(len(t) for t, _ in cells[0][0])
    avail = RIGHT - LEFT + 1
    while True:
        lw = max(w0 + len(n) for _, n in cells[:nrows])
        rw = max(w0 + len(n) for _, n in cells[nrows:]) if len(cells) > nrows else 0
        if lw + 2 + rw <= avail:
            gap = 2
            break
        if lw + 1 + rw <= avail:
            gap = 1
            break
        # shorten the longest name of the wider column
        side = range(nrows) if lw >= rw else range(nrows, len(cells))
        k = max(side, key=lambda k: len(cells[k][1]))
        short = shorten(cells[k][1])
        if short == cells[k][1]:
            raise SystemExit(f"{label}: {cells[k][1]!r} does not fit")
        cells[k] = (cells[k][0], short)
    out = []
    for r in range(nrows):
        segs, name = cells[r]
        line = segs + [(name, GRAY)]
        if r + nrows < len(cells):
            segs2, name2 = cells[r + nrows]
            line = pad(line, lw + gap) + segs2 + [(name2, GRAY)]
        out.append(row(*line))
    return out


def head_row(left, right, hint=None):
    """a page's first row: the list's name (cyan), a hint (gray), the game (gray, right)"""
    segs = [(left, CYAN)] + ([("  " + hint, GRAY)] if hint else [])
    w = sum(len(t) for t, _ in segs)
    return row(*segs, (" " * (RIGHT - LEFT + 1 - w - len(right)), WHITE), (right, GRAY))


def hangtime_pages(v, players, codes):
    """the two pages of a variant: the secret players (name, PIN, who) and
    the match-up codes; the hidden NBA players (name, who)"""
    game, rev, _ = hs.VARIANTS[v]
    nba = [n for n, _ in players].index("PIPPEN")
    staff = sorted(players[:nba])
    stars = sorted(n for n, _ in players[nba:])
    shown = lambda n: n.replace(" ", "_")
    title = game if v == 1 else f"{game.replace('NBA ', '')} {rev}"

    p1 = [head_row("SECRET PLAYERS", title, "_ is SPC")]
    p1 += two_columns([([(shown(n).ljust(7), WHITE), (shown(pin) + " ", YELLOW)], hs.full_name(n))
                       for n, pin in staff], f"{title} 1")
    p1 += [None, head_row("MATCH-UP CODES", "", "Turbo, Shoot, Pass: the digits")]
    for cells in columns(codes, 2, -(-len(codes) // 2)):
        segs = []
        for k, cell in enumerate(cells):
            if cell:
                segs += [(" " * (27 * k - sum(len(t) for t, _ in segs)), WHITE),
                         (cell[0] + " ", YELLOW), (cell[1], WHITE)]
        p1.append(row(*segs))

    p2 = [head_row("HIDDEN NBA PLAYERS", title)]
    p2 += two_columns([([(shown(n).ljust(7), WHITE)], hs.full_name(n)) for n in stars], f"{title} 2")
    foot = [row(("Enter Name", YELLOW), (": the name (", GRAY), ("END", YELLOW), (" if shorter), ", GRAY),
                ("PIN 0000", YELLOW))]
    p2 = p2 + [None] * (ROWS - len(p2) - len(foot)) + foot
    return fit(p1, f"{title} 1"), fit(p2, f"{title} 2")


def hangtime_missing():
    """the page shown when the MRA names no variant"""
    return fit([title_row("SECRET CODES", "NBA Hangtime"), None,
                row(("This list needs the MRA files of this release of", WHITE)),
                row(("the core: they tell it which version of the game", WHITE)),
                row(("this is.", WHITE))], "Hangtime: no variant")


OI_PLAYER_PAGES = 3
OI_FOOT_PLAYERS = [
    [("Enter initials for record keeping?", YELLOW), (" YES, then the", GRAY)],
    [("initials (", GRAY), ("_", YELLOW), (" is ", GRAY), ("SP", YELLOW), ("), the birth month and the day.", GRAY)],
]
OI_FOOT_CODES = [
    [("A+B", YELLOW), (" at once   ", GRAY), ("(X)", YELLOW), (" hold X through the moves after it", GRAY)],
    [("Each step within a quarter second   ", GRAY), ("L R", YELLOW), (": as on screen", GRAY)],
]
OI_WHERE = {
    "game": ("ON THE TONIGHT'S GAME SCREEN",
             [[("Head codes: your own player, or your team's goalie.", GRAY)]]),
    "faceoff": ("BEFORE THE FIRST FACE-OFF",
                [[("After Tonight's Game, before the help windows show.", GRAY)],
                 [("Speed Up to Fast Turbo Recovery: your player, one", GRAY)],
                 [("of them at a time. Tournament Mode, Unlimited", GRAY)],
                 [("Turbo: humans on both teams. Turbo Checks Off is in", GRAY)],
                 [("the program but in no published list.", GRAY)]]),
}


def openice_pages():
    """Open Ice's Secret Codes pages: the secret players (initials, birthday,
    who; three pages), the codes (Tonight's Game, before the first
    face-off)"""
    players, codes = oi.load()
    players = sorted(players)
    head = title_row("2 ON 2 OPEN ICE CHALLENGE", "")
    out = []
    per = -(-len(players) // OI_PLAYER_PAGES)
    for k in range(OI_PLAYER_PAGES):
        part = players[k * per:(k + 1) * per]
        span = f"{part[0][0].replace(' ', '_')} - {part[-1][0].replace(' ', '_')}"
        rows = [head_row("SECRET PLAYERS", "2 On 2 Open Ice Challenge", span)]
        rows += two_columns([([(i.replace(" ", "_") + " ", WHITE), (f"{m} {d}".ljust(7), YELLOW)],
                              oi.full_name(i, m, d)) for i, m, d in part], f"Open Ice players {k + 1}")
        foot = [row(*f) for f in OI_FOOT_PLAYERS]
        rows = rows + [None] * (ROWS - len(rows) - len(foot)) + foot
        out.append((f"openice players {k + 1}", fit(rows, f"Open Ice players {k + 1}")))
    for where in ("game", "faceoff"):
        title, notes = OI_WHERE[where]
        mine = [(n, s) for w, n, s in codes if w == where]
        nw = max(len(n) for n, _ in mine) + 2
        rows = [head, None, row((title, CYAN))]
        for n, s in mine:
            # the inputs, wrapped at the right edge under their column
            words, line, first = s.split(), "", True
            for w in words + [None]:
                if w is not None and len(line) + len(w) + (1 if line else 0) <= RIGHT - LEFT + 1 - nw:
                    line += (" " if line else "") + w
                    continue
                rows.append(row((n.ljust(nw) if first else " " * nw, WHITE), (line, YELLOW)))
                first, line = False, w or ""
        rows.append(None)
        rows += [row(*f) for f in notes]
        foot = [row(*f) for f in OI_FOOT_CODES]
        rows = rows + [None] * (ROWS - len(rows) - len(foot)) + foot
        out.append((f"openice codes {where}", fit(rows, f"Open Ice codes {where}")))
    return out


def page_logo(k):
    """what page k is drawn over: 0 the dimmed game, else the logo
    (movelist_logo.py: 1 MK3, 2 UMK3, 3 Open Ice, 4 NBA Hangtime, 5 NBA
    Maximum Hangtime)"""
    first = 0
    for _, _, family, logo, _ in GAMES:
        n = len(fm.OPT_ORDER[family])
        if k < first + n:
            return logo
        first += n
    if HANGTIME_PAGE <= k < HANGTIME_PAGE + 2 * len(hs.VARIANTS):
        return 4 if k < HANGTIME_PAGE + 2 else 5
    if OPENICE_PAGE <= k < OPENICE_PAGE + OI_PLAYER_PAGES + 2:
        return 3
    return 0


def pages():
    """[(label, rows)] in page order"""
    programs = fm.core_programs()
    sp = specials()
    out = []
    for game, table, family, _, _ in GAMES:
        for c in fm.OPT_ORDER[family]:
            out.append((f"{game} {fm.CHARS[c]}", page(game, table, c, programs, sp)))
    if len(out) != HANGTIME_PAGE:
        raise SystemExit(f"{len(out)} Move List pages, the Secret Codes window starts at {HANGTIME_PAGE}")
    var, codes = hs.load()
    for v in sorted(var):
        p1, p2 = hangtime_pages(v, var[v], codes)
        out += [(f"hangtime {v} players", p1), (f"hangtime {v} nba", p2)]
    out.append(("hangtime none", hangtime_missing()))
    if len(out) != OPENICE_PAGE:
        raise SystemExit(f"Open Ice's pages start at {len(out)}, not {OPENICE_PAGE}")
    out += openice_pages()
    return out


# ----------------------------------------------------------------------------
# the ROM images
# ----------------------------------------------------------------------------

def segments(r):
    """a row's runs of text: [(column, text, colour)]"""
    out, k = [], r[0]
    for t, colour in r[1]:
        lead = len(t) - len(t.lstrip(" "))
        if t.strip():
            out.append((k + lead, t.strip(), colour))
        k += len(t)
    return out


def images():
    text, seg, rows, lists = "", [0], [], {}
    for _, page_rows in pages():
        for r in page_rows + [None] * (32 - ROWS):
            sg = tuple(segments(r)) if r else ()
            if not sg:
                rows.append(0)
                continue
            if sg not in lists:
                lists[sg] = len(seg)
                for n, (col, t, colour) in enumerate(sg):
                    at = text.find(t)
                    if at < 0:
                        at = len(text)
                        text += t
                    seg.append(at | (len(t) << 14) | (col << 20) | (colour << 26) | ((n == len(sg) - 1) << 28))
            rows.append(lists[sg])
    rows += [0] * (PAGES * 32 - len(rows))
    if len(seg) > SEG_SIZE or len(text) > TEXT_SIZE:
        raise SystemExit(f"{len(seg)} segments (room for {SEG_SIZE}), {len(text)} characters (room for {TEXT_SIZE})")
    used = (len(seg) - 1, len(text))
    seg += [0] * (SEG_SIZE - len(seg))
    codes = [ord(ch) - 32 for ch in text] + [0] * (TEXT_SIZE - len(text))
    font = [b for ch in font_rows() for b in ch]
    return {"row": [f"{w:03X}" for w in rows],
            "seg": [f"{w:08X}" for w in seg],
            "text": [f"{w:02X}" for w in codes],
            "font": [f"{w:02X}" for w in font], "used": used}


def show(rows):
    print("+" + "-" * COLS + "+")
    for r in rows:
        line = [" "] * COLS
        if r:
            k = r[0]
            for t, _ in r[1]:
                for ch in t:
                    line[k] = ch
                    k += 1
        print("|" + "".join(line) + "|")
    print("+" + "-" * COLS + "+")


def main():
    a = sys.argv[1:]
    if a == ["--write"] or a == ["--check"]:
        img = images()
        used = img.pop("used")
        bad = []
        for k, lines in img.items():
            body = "\n".join(lines) + "\n"
            if a == ["--write"]:
                open(OUT[k], "w").write(body)
            elif not os.path.exists(OUT[k]) or open(OUT[k]).read() != body:
                bad.append(os.path.relpath(OUT[k], REPO))
        print(f"{used[0]} of {SEG_SIZE - 1} segments, {used[1]} of {TEXT_SIZE} characters")
        if a == ["--check"]:
            print("ROM images: " + ("OK" if not bad else "differ: " + ", ".join(bad)))
            sys.exit(1 if bad else 0)
        return
    if a[:1] == ["--show"]:
        ps = pages()
        which = a[1] if len(a) > 1 else "0"
        for k, (label, rows) in enumerate(ps):
            if which == "all" or which == str(k) or which.lower() in label.lower():
                print(f"page {k}: {label}")
                show(rows)
        return
    print("usage: see the header of " + sys.argv[0], file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    main()
