#!/usr/bin/env python3
# ============================================================================
#  extra_content.py - keeps each game page's "Extra content" section in step
#  with docs/Extra-Content.md
#
#  docs/Extra-Content.md lists everything the core adds, core-wide and game by
#  game. Each game page in docs/ opens with the same overview for its game
#  (that game's section of Extra-Content.md, without the link back to the
#  page itself), between two comment lines this tool owns. Edit the section
#  in Extra-Content.md, then run:
#
#    python3 tools/extra_content.py --write   copy the sections into the pages
#                                             (adds the section, and its line
#                                             in the page's Contents, to a page
#                                             that has none yet)
#    python3 tools/extra_content.py --check   fail when a page differs from
#                                             Extra-Content.md, a game has no
#                                             section, the README does not link
#                                             the page, or an OSD item the
#                                             page names is not in the core's
#                                             CONF_STR
#
#  Counts and lists in the sections (Kombat Kodes, fighters, secret players,
#  codes) are written by hand; when a feature is added or removed, update
#  Extra-Content.md, run --write, and update the other places that name it
#  (README, the game page's own sections, Testing.md, CHANGELOG.md).
# ============================================================================
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, "docs")
MASTER = os.path.join(DOCS, "Extra-Content.md")
SV = os.path.join(ROOT, "Arcade-Midway-Wolf-Unit.sv")
README = os.path.join(ROOT, "README.md")

# section of Extra-Content.md -> the game's page
PAGES = {
    "Mortal Kombat 3": "Mortal-Kombat-3.md",
    "Ultimate Mortal Kombat 3": "Ultimate-Mortal-Kombat-3.md",
    "WWF WrestleMania": "WWF-WrestleMania.md",
    "2 On 2 Open Ice Challenge": "2-On-2-Open-Ice-Challenge.md",
    "NBA Hangtime and NBA Maximum Hangtime": "NBA-Hangtime.md",
    "Rampage World Tour": "Rampage-World-Tour.md",
}

BEGIN = "<!-- extra-content: this section is copied from Extra-Content.md by tools/extra_content.py -->"
END = "<!-- /extra-content -->"
CONTENTS_LINE = "- [Extra content](#extra-content)"
FOOT = ("The core-wide extras every game gets, and the other games' extras:\n"
        "[Extra content](Extra-Content.md).")

# OSD items the pages name; each must be in the core's CONF_STR
OSD_NAMES = [
    "Open EJB Menu (Attract Mode)", "Hidden Alternate Test Menu",
    "Scorpion - Smoke Voice Fix", "Secret Midway Menu", "Secret Codes",
    "Move List", "Finishing Moves", "Kombat Kodes", "Ultimate Kombat Kodes",
    "Video Timing", "CRT Adjust", "CRT V-Size", "DIP Switches", "Service Mode",
    "Pause when OSD is Open", "Reset and close OSD", "Service Credit", "Tilt",
]


def sections(text):
    """heading -> body of every '## ' section"""
    out = {}
    parts = re.split(r"^## (.+)$", text, flags=re.M)
    for i in range(1, len(parts), 2):
        out[parts[i].strip()] = parts[i + 1].strip("\n")
    return out


def game_block(body):
    body = re.sub(r"\s*\[Details\]\([^)]*\)\.?", "", body).strip("\n")
    return "## Extra content\n\n" + body + "\n\n" + FOOT + "\n"


def apply(text, block):
    """the page with its Extra content section made to match block"""
    region = BEGIN + "\n\n" + block + "\n" + END
    if BEGIN in text:
        a = text.index(BEGIN)
        b = text.index(END, a) + len(END)
        text = text[:a] + region + text[b:]
    else:
        at = text.index("\n## OSD")
        text = text[:at + 1] + region + "\n\n" + text[at + 1:]
    if "## Contents" in text and "(#extra-content)" not in text:
        text = text.replace("## Contents\n\n", "## Contents\n\n" + CONTENTS_LINE + "\n", 1)
    return text


def conf_str():
    s = open(SV).read()
    body = re.search(r"localparam\s+CONF_STR\s*=\s*\{(.*?)\};", s, re.S).group(1)
    body = re.sub(r"//[^\n]*", "", body)
    return "".join(re.findall(r'"((?:[^"\\]|\\.)*)"', body)).replace('\\"', '"')


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "--check"
    if mode not in ("--check", "--write"):
        sys.exit("usage: extra_content.py --check | --write")
    master = open(MASTER).read()
    secs = sections(master)
    bad = []
    for sec, page in PAGES.items():
        if sec not in secs:
            bad.append(f"{MASTER}: no section '{sec}'")
            continue
        path = os.path.join(DOCS, page)
        old = open(path).read()
        new = apply(old, game_block(secs[sec]))
        if new != old:
            if mode == "--write":
                open(path, "w").write(new)
                print(f"{page}: Extra content written")
            else:
                bad.append(f"{page}: Extra content differs from Extra-Content.md")
        elif mode == "--write":
            print(f"{page}: already in step")
    if mode == "--check":
        if "docs/Extra-Content.md" not in open(README).read():
            bad.append("README.md does not link docs/Extra-Content.md")
        cs = conf_str()
        for name in OSD_NAMES:
            if name in master and name not in cs:
                bad.append(f"Extra-Content.md names the OSD item '{name}', which is not in CONF_STR")
        for name in OSD_NAMES:
            if name not in cs:
                bad.append(f"OSD_NAMES lists '{name}', which is not in CONF_STR")
        if bad:
            print("\n".join(bad))
            sys.exit(1)
        print(f"extra content: {len(PAGES)} game pages match Extra-Content.md, {len(OSD_NAMES)} OSD items found")


if __name__ == "__main__":
    main()
