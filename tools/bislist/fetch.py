#!/usr/bin/env python3
"""Fetches the WoW Forever BiS lists of wowtbc.gg into tools/bislist/wowtbc.json.

Usage: python3 tools/bislist/fetch.py [out.json]

The site is a static Gatsby build: each spec's list is one page-data.json. The snapshot keeps
only what build_data.py reads. When any page fails, nothing is written and the exit code is 1,
so the weekly job keeps the last snapshot (forever_content.py reports it when it gets old; then
run this on a computer and commit the file). Standard library only.
"""
import datetime
import json
import os
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "tools", "bislist", "wowtbc.json")
BASE = "https://wowtbc.gg/page-data/warcraftforever/bis-list/%s/page-data.json"
SPECS = ["balance-druid", "feral-tank-druid", "feral-dps-druid", "restoration-druid", "beast-mastery-hunter",
         "marksmanship-hunter", "survival-hunter", "arcane-mage", "fire-mage", "frost-mage", "holy-paladin",
         "protection-paladin", "retribution-paladin", "discipline-priest", "holy-priest", "shadow-priest",
         "assassination-rogue", "combat-rogue", "subtlety-rogue", "elemental-shaman", "enhancement-shaman",
         "restoration-shaman", "affliction-warlock", "demonology-warlock", "destruction-warlock", "arms-warrior",
         "fury-warrior", "protection-warrior"]


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (bis-list data job)"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode("utf-8"))


def convert(pages):
    """pages: slug -> page-data.json. Returns the snapshot build_data.py reads."""
    out = {"fetched": datetime.date.today().isoformat(), "specs": {}, "items": {}, "sets": None}
    for slug in SPECS:
        ctx = pages[slug]["result"]["pageContext"]
        b = ctx["bisList"]
        sp = {"class": b.get("class"), "spec": b.get("spec"), "simmed": bool(b.get("simmed")), "lists": {}, "enchants": {}}
        for k in ("pre-raid", "pre-raid-realistic"):
            if not b.get(k):
                continue
            sp["lists"][k] = {sl: [e["id"] for e in l] for sl, l in b[k]["gear"].items()}
            sp["enchants"][k] = {sl: [v.get("id"), v.get("name")] for sl, v in (b[k].get("enchants") or {}).items()}
        for lv, m in (b.get("caps") or {}).items():
            sp["lists"][lv] = m
        out["specs"][slug] = sp
        for x in ctx.get("gearData") or []:
            key = str(x["id"])
            if key not in out["items"]:
                out["items"][key] = [x.get("name"), x.get("slot"), x.get("type"), x.get("rarity"), x.get("ilvl"),
                                     (x.get("other_stats") or {}).get("min_level") or 0, x.get("bind") or "",
                                     x.get("source") or "", x.get("source_type") or ""]
        if out["sets"] is None:
            out["sets"] = [[z["id"], z["name"], z["set"]["set_pieces"], [q["count"] for q in z["set"].get("set_bonus") or []]]
                           for z in ctx.get("setsData") or []]
    return out


def main(argv):
    out = argv[0] if argv else OUT
    pages = {}
    for slug in SPECS:
        try:
            pages[slug] = get(BASE % slug)
        except Exception as e:  # one failed page keeps the last snapshot
            print("wowtbc.gg: %s failed: %s" % (slug, e), file=sys.stderr)
            return 1
    snap = convert(pages)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(snap, f, ensure_ascii=False, separators=(",", ":"))
    print("%d specs, %d items" % (len(snap["specs"]), len(snap["items"])))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
