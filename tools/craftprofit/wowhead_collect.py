"""Convert saved Wowhead WoW Forever profession pages into one JSON file.

Reads tools/craftprofit/.wowhead-cache/skill-<id>.json: one file per
profession page on https://www.wowhead.com/forever/skill=<id>, saved from
a browser. Each file holds the page's "recipes" listview as `r` rows
[spell, name, creates, reagents, colors, learnedat, trainingcost, source,
skill] and its "recipe-items" listview as `it` rows [item, name, skill,
source, sourcemore].

Run:  python tools/craftprofit/wowhead_collect.py

Writes tools/craftprofit/wowhead-professions.json.
"""

import datetime
import glob
import json
import os
import re
import sys

SITE = "https://www.wowhead.com/forever"
HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, ".wowhead-cache")
OUT = os.path.join(HERE, "wowhead-professions.json")

# Wowhead source codes (listview "source" field).
SOURCE_NAMES = {
    1: "crafted", 2: "drop", 3: "pvp", 4: "quest", 5: "vendor",
    6: "trainer", 7: "discovery", 8: "redemption", 9: "talent",
    10: "starter", 11: "event", 12: "achievement", 15: "disenchanted",
    16: "fished", 17: "gathered", 19: "mined", 21: "pickpocketed",
    23: "skinned",
}

# Wowhead "sourcemore" types: what the `ti` id points at.
MORE_KIND = {1: "npc", 2: "object", 3: "item", 5: "quest", 6: "spell", 7: "zone"}

PREFIX = re.compile(r"^(Pattern|Plans|Recipe|Formula|Schematic|Manual|Blueprint|Design|Technique)\s*:\s*",
                    re.I)


def key(name):
    """Name key that matches a recipe item to the spell it teaches."""
    name = PREFIX.sub("", name or "").lower()
    name = name.replace("transmute ", "transmute: ")
    return re.sub(r"[^a-z0-9:]+", " ", name).strip()


def pattern_source(item):
    _, name, skill, source, more = item
    src = {"item": item[0], "name": name, "skill": skill, "source": source}
    rows = []
    for t, ti, n, z in more:
        row = {"kind": MORE_KIND.get(t, t) if t is not None else "zone"}
        if ti is not None:
            row["id"] = ti
        if n:
            row["name"] = n
        if z is not None:
            row["zone"] = z
        rows.append(row)
    # The skill page names at most a few places; vendor prices are only on item pages.
    if rows:
        src["from"] = rows
    return src


def convert(page):
    sid = int(re.search(r"skill=(\d+)", page["url"]).group(1))
    name = page["title"].split(" - ")[0]
    by_key = {}
    for it in page["it"]:
        by_key.setdefault(key(it[1]), it)
    recipes = []
    for spell, sname, creates, reagents, colors, learnedat, cost, source, _ in page["r"]:
        r = {"spell": spell, "name": sname}
        if creates:
            r["item"] = creates[0]
            lo, hi = (list(creates) + [1, 1])[1:3]
            r["count"] = lo if lo == hi else [lo, hi]
        else:
            r["item"], r["count"] = None, 0
        r["reagents"] = {str(i): c for i, c in reagents}
        r["colors"] = colors
        r["learnedat"] = learnedat
        r["trainingcost"] = cost
        r["source"] = source
        item = by_key.get(key(sname))
        r["pattern"] = item[0] if item else None
        r["patternSource"] = pattern_source(item) if item else None
        # Wowhead gives no skill-up colours for recipes players cannot learn.
        r["unavailable"] = not colors or bool(item and item[1] == "UNUSED")
        recipes.append(r)
    return sid, {"name": name, "recipes": recipes,
                 "unmatchedPatterns": sorted(i[0] for i in page["it"]
                                             if key(i[1]) not in {key(x[1]) for x in page["r"]})}


def main():
    files = sorted(glob.glob(os.path.join(CACHE, "skill-*.json")))
    if not files:
        sys.exit("no saved pages in %s" % CACHE)
    out = {"generated": datetime.date.today().isoformat(), "site": SITE,
           "sourceNames": {str(k): v for k, v in SOURCE_NAMES.items()}, "skills": {}}
    for f in files:
        with open(f, encoding="utf-8") as fh:
            page = json.load(fh)
        if not page.get("r"):
            continue
        sid, skill = convert(page)
        out["skills"][str(sid)] = skill
        rs = skill["recipes"]
        print("%-15s %4d recipes, %4d colours, %3d training cost, %3d patterns, %3d unavailable"
              % (skill["name"], len(rs), sum(1 for r in rs if r["colors"]),
                 sum(1 for r in rs if r["trainingcost"]), sum(1 for r in rs if r["pattern"]),
                 sum(1 for r in rs if r["unavailable"])), file=sys.stderr)
    out["skills"] = dict(sorted(out["skills"].items(), key=lambda kv: int(kv[0])))
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=1, ensure_ascii=False)
        fh.write("\n")
    print("wrote %s" % OUT, file=sys.stderr)


if __name__ == "__main__":
    main()
