#!/usr/bin/env python3
"""Fails on a sign in an addon's Lua or TOC text that the game's fonts may draw as an empty box.

The game's own fonts (Friz Quadrata Cyrillic on a Russian client, the font the Gulli look falls
back to when Fira Sans cannot load) lack signs such as the middle dot, so a line like
"wowtbc.gg · 2026-11-21" shows "wowtbc.gg [] 2026-11-21". Use S.DOT (a dot texture) between parts
of a line in code, ", " or " - " in a translated text, "x" for a count and "..." for more.
Comments are not checked. In Chinese text a dot between two characters (a name) and an ellipsis
next to Chinese text are fine: the Chinese fonts have them.
Usage: python3 tools/ci/glyphs.py [files...] (default: every Gulli-*/**/*.lua and Gulli-*/*.toc)
"""
import glob
import re
import sys

BANNED = "·•×…→←↑↓⇒⇐↔≈≤≥■□▪▫►▶◀◆◇●○✓✔✗✘★☆♦♥"
HAN = re.compile(r"[一-鿿]")
CJK = re.compile(r"[　-〿一-鿿＀-￯]")


def code_part(line):
    """The line without its comment (a -- outside a string)."""
    quote = None
    i = 0
    while i < len(line):
        c = line[i]
        if quote:
            if c == "\\":
                i += 1
            elif c == quote:
                quote = None
        elif c in "\"'":
            quote = c
        elif line.startswith("--", i):
            return line[:i]
        i += 1
    return line


def allowed(text, i):
    c = text[i]
    before = text[i - 1] if i > 0 else ""
    after = text[i + 1] if i + 1 < len(text) else ""
    if c == "·":
        return bool(HAN.match(before) and HAN.match(after))
    if c == "…":
        return bool(CJK.match(before) or CJK.match(after) or before == "…" or after == "…")
    return False


def main(files):
    bad = 0
    for path in files:
        toc = path.endswith(".toc")
        with open(path, encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                text = line if toc else code_part(line)
                if toc and text.lstrip().startswith("#") and not text.lstrip().startswith("##"):
                    continue
                for i, c in enumerate(text):
                    if c in BANNED and not allowed(text, i):
                        print(f"{path}:{n}: {c!r} (U+{ord(c):04X}) may show as an empty box in the game's fonts")
                        bad += 1
    if bad:
        print(f"{bad} sign(s) the game's fonts may lack: use S.DOT, ', ', ' - ', 'x' or '...' instead")
    return 1 if bad else 0


if __name__ == "__main__":
    args = sys.argv[1:] or sorted(glob.glob("Gulli-*/**/*.lua", recursive=True) + glob.glob("Gulli-*/*.toc"))
    sys.exit(main(args))
