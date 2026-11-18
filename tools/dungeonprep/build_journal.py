"""Builds Gulli-DungeonPrep/JournalData.lua from a Wowhead snapshot of the WoW Forever dungeons.

    python3 tools/dungeonprep/build_journal.py [tools/dungeonprep/wowhead-dungeons.json] [AllTheThings]

The snapshot is collected from Wowhead's WoW Forever pages on a player's computer (Wowhead
refuses scripted reads from servers) and kept next to this file, so the generator runs anywhere.
Its shape:

    {"dungeons": {"DM": {"bosses": [{"id", "name", "tag", "minLevel", "maxLevel", "displayId",
        "abilities": [[spell id, name]], "drops": [{"id", "quality", "class", "pct", "count",
        "outof"}]}], "rares": [...same...]}}}

Wowhead lists every elite with a blue zone drop as a boss, and every NPC's drops include the
world drops. So a boss is kept when Wowhead ranks it a boss (and it is not in NOT_BOSSES) or one
of its own drops comes at BOSS_PCT or more, and a drop is kept when it is in the dungeon's own
zone drops at MIN_PCT or more, from at least MIN_OUTOF kills, and is uncommon or better (a white
quest item says nothing about a boss).

Wowhead has no order of the bosses. AllTheThings (MIT) lists each instance's NPCs in the order a
group meets them, wing by wing (att.walk): with an AllTheThings checkout as the second argument
that order is read and kept in att-walk.json next to this file, which a run without it uses.
Bosses go in that order (a skull boss, level 9999, is written as level 0), then the rares in the
same order; where ATT knows the instance, an elite that is neither ranked a boss nor listed by ATT
is left out, and a ranked boss ATT does not list comes after the others, by level. D.walk names the dungeons whose bosses
all have a place in it. D.zone has what the ordinary mobs drop: Wowhead's zone drops that no boss
or rare has, and ATT's ZONE_DROPS (quality 0: the game says what they are).
The snapshot is untrusted text: it is only read as JSON, never run.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "wowhead-dungeons.json")
WALK = os.path.join(HERE, "att-walk.json")
OUT = os.path.join(HERE, "..", "..", "Gulli-DungeonPrep", "JournalData.lua")
sys.path.insert(0, HERE)
import att  # noqa: E402
from build_data import ATT_FILES, DUNGEONS  # noqa: E402

def as_int(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return 0


QUEST_CLASS = 12
MIN_QUALITY = 2       # uncommon
MIN_OUTOF = 10        # kills behind a chance
MIN_PCT = 1           # rarer drops are noise
BOSS_PCT = 5          # an elite with a drop this likely is a boss
SKULL = 9999          # Wowhead's level of a skull boss
BOSS_RANK = 3
COMMON_SPELLS = {1604, 5101, 13496, 15571}  # Dazed: every melee mob has it
COMMON_NAMES = {"dazed"}
# NPCs Wowhead ranks as bosses that are not fought there (story NPCs, items).
NOT_BOSSES = {
    242867,  # The Will of the Ashbringer
    15362,   # Malfurion Stormrage
    10162,   # Lord Victor Nefarius
    16387,   # Atiesh
}
MAX_DROPS = 30        # per boss, best first
MAX_SPELLS = 6


def lua_str(s):
    s = str(s or "")
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'


def pct_of(d):
    pct = d.get("pct")
    if pct is None and d.get("outof"):
        pct = 100.0 * (d.get("count") or 0) / d["outof"]
    return float(pct or 0)


def own_drop(d, own):
    """A drop that tells a boss from the mobs around it: its quest item or a zone drop."""
    if d.get("outof") is not None and d["outof"] < MIN_OUTOF:
        return False
    if pct_of(d) < MIN_PCT:
        return False
    if d.get("class") == QUEST_CLASS:
        return True
    return as_int(d.get("id")) in own and (d.get("quality") or 0) >= MIN_QUALITY


def keep_drop(d, own):
    """A drop the journal lists: no white quest items (every boss has the same ones)."""
    return own_drop(d, own) and (d.get("quality") or 0) >= MIN_QUALITY


def is_boss(b, own):
    if as_int(b.get("id")) in NOT_BOSSES:
        return False
    if b.get("classification") == BOSS_RANK:
        return True
    return any(own_drop(d, own) and pct_of(d) >= BOSS_PCT for d in b.get("drops") or [])


def spells_of(b):
    """The boss's abilities, one per name (Wowhead lists every rank), without the common ones."""
    out, names = [], set()
    for a in b.get("abilities") or []:
        sid = as_int(a[0] if isinstance(a, list) else a)
        name = str(a[1]).strip().lower() if isinstance(a, list) and len(a) > 1 else str(sid)
        if sid <= 0 or sid in COMMON_SPELLS or name in COMMON_NAMES or name in names:
            continue
        names.add(name)
        out.append(sid)
    return out[:MAX_SPELLS]


def read_walk(att_root):
    """Dungeon key -> att.walk of its AllTheThings file; saved to att-walk.json when read anew."""
    if att_root:
        folder = os.path.join(att_root, ".contrib", ".db", "forever", "dungeons & raids")
        walk = {}
        for key, name in sorted(ATT_FILES.items()):
            path = os.path.join(folder, name + ".lua")
            if os.path.exists(path):
                walk[key] = att.walk(path)
            else:
                print("no AllTheThings file for %s: %s" % (key, path))
        with open(WALK, "w", encoding="utf-8", newline="\n") as f:
            json.dump(walk, f, separators=(",", ":"), sort_keys=True)
            f.write("\n")
        return walk
    if os.path.exists(WALK):
        with open(WALK, encoding="utf-8") as f:
            return json.load(f)
    return {}


def level(v):
    v = as_int(v)
    return 0 if v >= SKULL else v




def boss_row(b, rare, own, wing=""):
    drops = sorted((d for d in b.get("drops") or [] if as_int(d.get("id")) > 0 and keep_drop(d, own)),
                   key=lambda d: (-(d.get("quality") or 0), -pct_of(d), as_int(d["id"])))[:MAX_DROPS]
    loot = ",".join("{%d,%d,%s}" % (as_int(d["id"]), as_int(d.get("quality")),
                                    ("%.1f" % pct_of(d)).rstrip("0").rstrip("."))
                    for d in drops)
    spells = ",".join(str(s) for s in spells_of(b))
    return "{%d,%s,%s,%d,%d,%d,%d,{%s},{%s},%s}" % (
        as_int(b["id"]), lua_str(b.get("name")), lua_str(b.get("tag")), level(b.get("minLevel")),
        level(b.get("maxLevel")), as_int(b.get("displayId")), 1 if rare else 0, spells, loot, lua_str(wing))


def build(snapshot, walk=None):
    walk = walk or {}
    known = [d[0] for d in DUNGEONS]
    data = snapshot.get("dungeons") or {}
    lines = [
        "-- Generated by tools/dungeonprep/build_journal.py from a Wowhead snapshot. Do not edit.",
        "local _, ns = ...",
        "local D = ns.Data",
        "-- D.boss[dungeon] = { { npc, name, tag, min level, max level, display id, rare (1),",
        "--   { ability spell ids }, { { item, quality, drop chance in percent } }, wing } }: the bosses",
        "--   in the order a group meets them, then the rares.",
        "D.boss = {",
    ]
    missing, walked, zones = [], [], []
    for key in known:
        d = data.get(key)
        if not d:
            missing.append(key)
            continue
        own = {as_int(z.get("id")) for z in d.get("zoneDrops") or []}
        w = walk.get(key) or {}
        place = {npc: (n, wing) for n, (npc, wing) in enumerate(w.get("order") or [])}
        bosses = [b for b in d.get("bosses") or [] if as_int(b.get("id")) > 0 and is_boss(b, own)]
        # Where ATT knows the instance, an elite it does not list is an ordinary mob with a good
        # drop, not a boss: its drops go to the zone's.
        if place:
            bosses = [b for b in bosses if b.get("classification") == BOSS_RANK or as_int(b.get("id")) in place]
        # One boss can come twice under two ids (an old and a Forever copy): keep the one with loot.
        by_name = {}
        for b in bosses:
            name = b.get("name")
            if name not in by_name or len(b.get("drops") or []) > len(by_name[name].get("drops") or []):
                by_name[name] = b
        bosses = [b for b in bosses if by_name[b.get("name")] is b]
        def by_walk(b):
            n = place.get(as_int(b.get("id")), (len(place), ""))[0]
            return (n, as_int(b.get("minLevel")), as_int(b.get("maxLevel")))

        def wing_of(b):
            return place.get(as_int(b.get("id")), (0, ""))[1]

        bosses.sort(key=by_walk)
        rares = sorted((b for b in d.get("rares") or []
                        if as_int(b.get("id")) > 0 and as_int(b.get("id")) not in NOT_BOSSES), key=by_walk)
        rows = [boss_row(b, False, own, wing_of(b)) for b in bosses]
        rows += [boss_row(b, True, own, wing_of(b)) for b in rares]
        if not rows:
            missing.append(key)
            continue
        if bosses and all(as_int(b.get("id")) in place for b in bosses):
            walked.append(key)
        elif place:
            print("%s: not in the AllTheThings order: %s" % (key, ", ".join(
                str(b.get("name")) for b in bosses if as_int(b.get("id")) not in place)))
        # What the ordinary mobs drop: zone drops no boss or rare has.
        listed = set()
        for b in bosses + rares:
            listed.update(as_int(x.get("id")) for x in b.get("drops") or [] if keep_drop(x, own))
        named = {as_int(b.get("id")) for b in bosses + rares}
        zone, got = [], set()
        for z in d.get("zoneDrops") or []:
            zid = as_int(z.get("id"))
            if (zid > 0 and zid not in listed and zid not in got and as_int(z.get("npcId")) not in named
                    and (z.get("quality") or 0) >= MIN_QUALITY and z.get("class") != QUEST_CLASS):
                got.add(zid)
                zone.append((zid, as_int(z.get("quality"))))
        for zid in w.get("zone") or []:
            if zid not in listed and zid not in got:
                got.add(zid)
                zone.append((zid, 0))
        if zone:
            zones.append("%s = {%s}," % (key, ",".join("{%d,%d}" % z for z in zone)))
        lines.append("%s = {" % key)
        lines.extend(r + "," for r in rows)
        lines.append("},")
    lines.append("}")
    lines.append("-- The dungeons whose bosses are all in the order a group meets them.")
    lines.append("D.walk = {%s}" % ",".join("%s=true" % k for k in walked))
    lines.append("-- D.zone[dungeon] = { { item, quality } }: what the ordinary mobs drop; quality 0 = ask the game.")
    lines.append("D.zone = {")
    lines.extend(zones)
    lines.append("}")
    unknown = sorted(set(data) - set(known))
    return "\n".join(lines) + "\n", missing, unknown


def main(src, att_root=None):
    with open(src, encoding="utf-8") as f:
        snapshot = json.load(f)
    text, missing, unknown = build(snapshot, read_walk(att_root))
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    if missing:
        print("no bosses for: " + ", ".join(missing))
    if unknown:
        print("not a DungeonPrep dungeon, skipped: " + ", ".join(unknown))
    print("wrote " + os.path.relpath(OUT))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else SRC, sys.argv[2] if len(sys.argv) > 2 else None)
