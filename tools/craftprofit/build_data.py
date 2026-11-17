"""Builds Gulli-CraftProfit/Data.lua: the skill levels at which each recipe turns yellow, green
and grey, so the planner knows the chance of a skill point instead of guessing it.

    python3 tools/craftprofit/build_data.py <SkillLevelData1.lua> <questiedb-checkout> [wowhead.json]

The input is SkillLevelData1.lua of Skillet-Classic (GPLv3,
https://github.com/b-morgan/Skillet-Classic), the Classic Era tables made from the game's
SkillLineAbility data. Two tables come out:

- ns.Data.spell[recipe spell id] = { yellow, green, grey } (the modern API keys recipes by spell);
- ns.Data.item[made item id] = { orange, yellow, green, grey } (the classic API keys them by the
  item made; orange is the skill the recipe is learned at).

The QuestieDB Forever data (GPLv3, https://github.com/Questie/QuestieDB) adds where a pattern comes
from: ns.Data.src[recipe spell id] = { kind, pattern item id, "Vendor|AH", ... } with kind "v"
(sold by the vendors named, with the factions they serve), "q" (a quest reward) or "d" (a drop).
A pattern is matched to its recipe by name ("Pattern: Green Silk Pack" -> "Green Silk Pack").
A recipe without a pattern comes from the trainer.

Not every recipe the client lists can be learned in WoW Forever. ns.Data.gone[recipe spell id] = true
marks the ones the app must leave out when the character does not know them:

- every Season of Discovery recipe (spell id from SOD_SPELL up: Invoker's Cord, the Gnomeregan and
  Scarlet Enclave sets, ...): the Forever client still has them, but no trainer or pattern gives them.
  The QuestieDB Forever data still names the Season of Discovery patterns (item ids in SOD_ITEMS)
  with their old vendors and drops, so those patterns are not a source. A Season of Discovery recipe
  stays only when a Forever pattern (an item id above SOD_ITEMS) teaches it, such as
  "Formula: Enchant Gloves - Holy Power";
- a recipe whose pattern is in the Forever data with no vendor, quest or drop (Molten Core and
  Naxxramas patterns, while Forever has not opened those raids).

Such a recipe gets no thresholds and no source, so nothing treats it as a trainer recipe.

WoW Forever moved many skill levels (Bolt of Mageweave is grey at 150, not 185) and has recipes
of its own (spell ids from FOREVER_SPELL up). Its profession pages on Wowhead, collected into
wowhead-professions.json on a player's computer (Wowhead refuses servers), win over Skillet:

- their colours replace the Skillet levels, and Forever's own recipes are added;
- ns.Data.train[recipe spell id] = the trainer's price in copper, for a recipe a trainer teaches
  (such a recipe gets no pattern source, even when a vendor sells its pattern too);
- a pattern the Questie data does not tie to the recipe gets its source from Wowhead
  (vendors without a faction, "Name|AH");
- a recipe Wowhead marks unavailable is gone (unless a Forever pattern teaches it), and so is a
  Classic recipe that a Forever recipe of the same name replaced (Greater Healing Potion).

The Season of Discovery rules above stay: Wowhead lists those recipes too.

The file is parsed as text, never run.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "questcleaner"))
import questie  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "Gulli-CraftProfit", "Data.lua")

# Vanilla items have ids below this; the item table also lists later expansions.
MAX_ITEM = 25000
ENTRY = re.compile(r"^\[(-?\d+)\]\s*=\s*['\"](\d+)/(\d+)/(\d+)/(\d+)['\"]")


def section(text, name):
    start = text.index("Skillet.db.global.%s = {" % name)
    end = text.index("\n}", start)
    return text[start:end].splitlines()[1:]


def parse(text):
    spell, item = {}, {}
    for line in section(text, "SkillLineAbility"):
        m = ENTRY.match(line.strip())
        if m:
            sid, _, y, gr, g = (int(x) for x in m.groups())
            if 0 < y <= gr <= g:
                spell[sid] = (y, gr, g)
    for line in section(text, "SkillLevels"):
        m = ENTRY.match(line.strip())
        if m:
            iid, o, y, gr, g = (int(x) for x in m.groups())
            if 0 < iid < MAX_ITEM and o <= y <= gr <= g and y > 0:
                item[iid] = (o, y, gr, g)
    return spell, item


NAME = re.compile(r"""^\[(["'])(.+)\1\]\s*=\s*(\d+)""")
PREFIX = re.compile(r"^(Pattern|Plans|Recipe|Formula|Schematic|Manual): (.+)$")
# QuestieDB itemKeys and npcKeys (data/Forever/*.lua).
I_NAME, I_NPC_DROPS, I_OBJECT_DROPS, I_ITEM_DROPS, I_REWARD_OF, I_VENDORS = 1, 2, 3, 4, 6, 14
N_NAME, N_FRIENDLY = 1, 13
MAX_VENDORS = 3
# Skillet lists the Season of Discovery recipes after the Classic ones; their spell ids start here.
SOD_SPELL = 400000
# Recipes with a pattern item that a trainer teaches anyway (the Gnomish and Goblin engineering
# trainers): never "gone" for lack of a pattern source.
TRAINER_TOO = {11454, 11456}  # Inlaid Mithril Cylinder, Goblin Rocket Fuel
# Season of Discovery items; WoW Forever's own items come after them.
SOD_ITEMS = range(200000, 245000)


def names(text):
    """enUS recipe name -> spell id; the lowest id when two spells share a name (the Vanilla one)."""
    out = {}
    for line in section(text, "NameToSpellID"):
        m = NAME.match(line.strip())
        if m:
            name, sid = m.group(2).replace("\\'", "'"), int(m.group(3))
            out[name] = min(sid, out.get(name, sid))
    return out


def sources(root, by_name, spell):
    # With the Forever corrections (vendors and drops Forever added).
    _, npcs, _, items = questie.load_forever(root)

    def field(row, k):
        return row.get(k) if isinstance(row, dict) else (row[k - 1] if len(row) >= k else None)

    out, unsourced, by_item = {}, set(), {}
    for iid in sorted(items):
        row = items[iid]
        if iid in SOD_ITEMS:
            continue
        m = PREFIX.match(field(row, I_NAME) or "")
        if not m:
            continue
        sid = by_name.get(m.group(2))
        sid = sid if sid in spell else None
        vendors = []
        for nid in sorted(luadata_seq(field(row, I_VENDORS))):
            npc = npcs.get(nid)
            if npc and field(npc, N_NAME):
                # a vendor with no faction (Timbermaw, Forever quartermasters) sells to both
                vendors.append("%s|%s" % (field(npc, N_NAME), field(npc, N_FRIENDLY) or "AH"))
        if vendors:
            entry = ["v", iid] + vendors[:MAX_VENDORS]
        elif luadata_seq(field(row, I_REWARD_OF)):
            entry = ["q", iid]
        elif any(luadata_seq(field(row, k)) for k in (I_NPC_DROPS, I_OBJECT_DROPS, I_ITEM_DROPS)):
            entry = ["d", iid]
        else:
            by_item[iid] = None
            if sid:
                unsourced.add(sid)
            continue
        by_item[iid] = entry
        # a pattern sold by a vendor wins over one that only drops
        if sid and (sid not in out or (entry[0] == "v" and out[sid][0] != "v")):
            out[sid] = entry
    return out, unsourced - set(out), by_item


def gone(spell, src, unsourced):
    """Recipes no one can learn in WoW Forever (see the module docstring)."""
    return {sid for sid in spell if sid >= SOD_SPELL and sid not in src} | (set(unsourced) - TRAINER_TOO)


# Wowhead's source codes (wowhead-professions.json "sourceNames").
WH_DROP, WH_QUEST, WH_VENDOR, WH_TRAINER = 2, 4, 5, 6
# WoW Forever's own recipe spells start here (Skillet does not know them).
FOREVER_SPELL = 1000000


def wowhead(path, spell, item, src, out_gone, by_item, by_name):
    """Merges the WoW Forever profession pages of Wowhead (see the module docstring); returns the
    trainer prices. Changes spell, item, src and out_gone in place."""
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    recipes = [r for s in data["skills"].values() for r in s["recipes"]]
    forever_names = {r["name"] for r in recipes if r["spell"] >= FOREVER_SPELL and not r["unavailable"]}
    made = {}
    for r in recipes:
        if r.get("item"):
            made[r["item"]] = made.get(r["item"], 0) + 1
    known = {r["spell"] for r in recipes}
    train = {}
    for r in recipes:
        sid = r["spell"]
        # Wowhead lists Season of Discovery recipes too: their availability stays the Questie rule
        if sid in out_gone or (SOD_SPELL <= sid < FOREVER_SPELL):
            continue
        if sid < SOD_SPELL and sid not in spell:
            continue
        p = r.get("pattern")
        # Wowhead's "unavailable" loses to a pattern the Forever data sells or drops (Stormcloth)
        if r["unavailable"] and not (sid in src or by_item.get(p)):
            out_gone.add(sid)
            continue
        c = r.get("colors") or []
        if len(c) == 4 and 0 < c[1] <= c[2] <= c[3]:
            spell[sid] = (c[1], c[2], c[3])
            if r.get("item") and made[r["item"]] == 1:
                o = c[0] or r.get("learnedat") or c[1]
                item[r["item"]] = (min(o, c[1]), c[1], c[2], c[3])
        elif sid >= FOREVER_SPELL:
            continue
        if p and sid not in src:
            entry = (by_item.get(p) or from_pattern(r.get("patternSource") or {}, p)
                     or from_pattern({"source": r.get("source")}, p))
            if entry:
                src[sid] = entry
            elif p in by_item and sid not in TRAINER_TOO and WH_TRAINER not in (r.get("source") or []):
                # the Forever data has the pattern, and no one sells or drops it
                out_gone.add(sid)
                continue
        if r.get("trainingcost") and WH_TRAINER in (r.get("source") or []):
            # the trainer teaches it: learning there wins over buying its pattern
            train[sid] = r["trainingcost"]
            src.pop(sid, None)
    # a Classic recipe that WoW Forever replaced with its own spell (Greater Healing Potion)
    for name, sid in sorted(by_name.items()):
        if sid < SOD_SPELL and sid in spell and sid not in known and name in forever_names:
            out_gone.add(sid)
    return train


def from_pattern(ps, p):
    kinds = ps.get("source") or []
    if WH_VENDOR in kinds:
        who = [f["name"] for f in ps.get("from") or [] if f.get("kind") == "npc" and f.get("name")]
        return ["v", p] + ["%s|AH" % n for n in who[:MAX_VENDORS]]
    if WH_QUEST in kinds:
        return ["q", p]
    if WH_DROP in kinds:
        return ["d", p]
    return None


def luadata_seq(t):
    if isinstance(t, dict):
        return [t[k] for k in sorted(t)]
    return list(t or [])


def quote(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua(spell, item, src, out_gone=(), train=None):
    out = [
        "-- Generated by tools/craftprofit/build_data.py from Skillet-Classic's SkillLevelData1.lua",
        "-- (GPLv3, https://github.com/b-morgan/Skillet-Classic) and the QuestieDB Forever data",
        "-- (GPLv3, https://github.com/Questie/QuestieDB), with the WoW Forever profession pages of",
        "-- Wowhead (tools/craftprofit/wowhead-professions.json). Do not edit by hand.",
        "local _, ns = ...",
        "ns.Data = { spell = {",
    ]
    for k in sorted(spell):
        out.append("[%d]={%d,%d,%d}," % ((k,) + spell[k]))
    out.append("}, item = {")
    for k in sorted(item):
        out.append("[%d]={%d,%d,%d,%d}," % ((k,) + item[k]))
    out.append("}, src = {")
    for k in sorted(src):
        e = src[k]
        out.append("[%d]={%s}," % (k, ",".join([quote(e[0]), str(e[1])] + [quote(v) for v in e[2:]])))
    out.append("}, train = {")
    for k in sorted(train or {}):
        out.append("[%d]=%d," % (k, train[k]))
    out.append("}, gone = {")
    for k in sorted(out_gone):
        out.append("[%d]=true," % k)
    out.append("} }")
    return "\n".join(out) + "\n"


WOWHEAD = os.path.join(HERE, "wowhead-professions.json")


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    with open(sys.argv[1], encoding="utf-8") as f:
        text = f.read()
    spell, item = parse(text)
    by_name = names(text)
    src, unsourced, by_item = sources(sys.argv[2], by_name, spell)
    if len(spell) < 500 or len(item) < 500:
        sys.exit("too few recipes (%d spells, %d items): is it the right file?" % (len(spell), len(item)))
    out_gone = gone(spell, src, unsourced)
    train = wowhead(sys.argv[3] if len(sys.argv) == 4 else WOWHEAD, spell, item, src, out_gone, by_item, by_name)
    spell = {k: v for k, v in spell.items() if k not in out_gone}
    src = {k: v for k, v in src.items() if k not in out_gone}
    train = {k: v for k, v in train.items() if k not in out_gone}
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(lua(spell, item, src, out_gone, train))
    print("%d spells, %d items, %d pattern sources, %d trainer prices, %d not in Forever -> %s"
          % (len(spell), len(item), len(src), len(train), len(out_gone), OUT))


if __name__ == "__main__":
    main()
