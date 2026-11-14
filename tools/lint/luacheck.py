"""Run luacheck on the addons and keep only the warnings that point at real bugs.

Usage: python3 tools/lint/luacheck.py

Kept: a global set or changed that is not ours (a leak, or a typo of a local), a local that is
read but never set (such as `local a, b = f and f()`, which keeps one value), unreachable code,
and a loop that runs at most once. Game globals are not known to luacheck, so reading a global
(W113) is not checked. Ours are `Gulli*`, `SLASH_GULLI*` and `BINDING_*`, and the game tables in
GAME_TABLES that addons may write to.
"""
import re
import subprocess
import sys
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CODES = ("W111", "W112", "W121", "W122", "W221", "W511", "W571")
OURS = re.compile(r"^(Gulli\w*|SLASH_GULLI\w*|BINDING_\w+)$")
GAME_TABLES = {"SlashCmdList", "StaticPopupDialogs", "ChatFrame_DisplayTimePlayed"}


def main():
    files = sorted(
        os.path.join(d, f)
        for d in os.listdir(ROOT) if d.startswith("Gulli-") and os.path.isdir(os.path.join(ROOT, d))
        for f in os.listdir(os.path.join(ROOT, d)) if f.endswith(".lua") and f != "Data.lua"
    )
    out = subprocess.run(["luacheck", "--std", "lua51", "--codes", "--no-color", "--formatter", "plain", "-q"] + files,
                         cwd=ROOT, capture_output=True, text=True).stdout
    bad = []
    for line in out.splitlines():
        m = re.search(r"\((W\d+)\)", line)
        if not m or m.group(1) not in CODES:
            continue
        g = re.search(r"global variable '([^']+)'", line)
        if g and (OURS.match(g.group(1)) or g.group(1) in GAME_TABLES):
            continue
        bad.append(line)
    for line in bad:
        print("::error::" + line if os.environ.get("GITHUB_ACTIONS") else line)
    print("luacheck: %d files, %d problems." % (len(files), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
