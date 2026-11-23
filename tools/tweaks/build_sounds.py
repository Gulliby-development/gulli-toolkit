#!/usr/bin/env python3
"""Writes the sound lists of the Quieter game tweak (Gulli-Toolkit/Tweaks/MuteSounds.lua).

The game names its sound files by number (FileDataID). The numbers come from the game's own
file list as the community keeps it (wowdev/wow-listfile, community-listfile.csv: "id;path"),
picked by path, so no other addon's mute list is copied.

    curl -sSL https://github.com/wowdev/wow-listfile/releases/latest/download/community-listfile.csv -o listfile.csv
    python3 tools/tweaks/build_sounds.py listfile.csv

A new kind of sound is a row in KINDS, a TWP_MUTE_<KEY> text in every language and a case in the
toolkit test.
"""
import re
import sys

TARGET = "Gulli-Toolkit/Tweaks/MuteSounds.lua"

# key -> path patterns (lower case). Footsteps of hooved players (bipedal) stay.
KINDS = [
    ("hooves", [r"^sound/creature/horse/mfootsteps", r"^sound/character/footsteps/horse_footstep",
                r"^sound/character/footsteps/hooved[a-z]*/mon_footstep_quadraped_hooved"]),
    ("mechano", [r"^sound/creature/mechastrider/"]),
    ("airships", [r"^sound/doodad/(doodadcompression/)?zeppelin", r"^sound/doodad/go_fx_zeppelin",
                  r"^sound/creature/hordezeppelin/", r"^sound/creature/allianceairship/"]),
    ("weather", [r"^sound/ambience/weather/"]),
    ("fizzle", [r"^sound/spells/fizzle/"]),
]


def main(path):
    found = {k: [] for k, _ in KINDS}
    rules = [(k, [re.compile(p) for p in pats]) for k, pats in KINDS]
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if ";" not in line:
                continue
            num, name = line.split(";", 1)
            name = name.lower()
            if not num.isdigit() or not name.endswith(".ogg"):
                continue
            for key, pats in rules:
                if any(p.search(name) for p in pats):
                    found[key].append(int(num))
                    break
    out = ["-- BEGIN SOUNDS (tools/tweaks/build_sounds.py writes this part)", "ns.MUTE_SOUNDS = {"]
    for key, _ in KINDS:
        ids = sorted(set(found[key]))
        if not ids:
            sys.exit("no sound found for " + key)
        out.append("    %s = {" % key)
        for i in range(0, len(ids), 12):
            out.append("        " + ", ".join(str(x) for x in ids[i:i + 12]) + ",")
        out.append("    },")
    out += ["}", "-- END SOUNDS"]
    text = open(TARGET, encoding="utf-8").read()
    new = re.sub(r"-- BEGIN SOUNDS.*?-- END SOUNDS", lambda _: "\n".join(out), text, flags=re.S)
    open(TARGET, "w", encoding="utf-8", newline="\n").write(new)
    print({k: len(v) for k, v in found.items()})


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
