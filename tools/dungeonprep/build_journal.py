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

WoW Forever's own dungeons came after Wowhead's zone pages were read: where the snapshot has no
boss of a dungeon, its bosses come from ATT alone (its order, the names in its comments, the
items listed under each boss as loot with no chance, quality 0: the game says what they are).
Wowhead gives no level for WoW Forever's own NPCs and neither does QuestieDB, so LEVELS holds the
levels read in the game (a level the snapshot has wins), RARES marks the rares ATT lists among
the bosses, NAMES renames an encounter the game shows under another name, SKIP drops an NPC that
is part of another one's encounter, and EXTRA adds a boss or rare neither source lists.
merge_npcs.py adds the NPC pages of bosses Wowhead files under another zone (read one by one)
to the snapshot, with their models and drop chances.
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
# Levels of WoW Forever's own bosses, read in the game (another journal addon's boss list,
# screenshots of the owner, 2026-11-20). A new dungeon's bosses get theirs here.
LEVELS = {
    # The Hall of Thanes
    261306: 16, 261316: 16, 261311: 16, 261319: 16,
    # Ruins of Lordaeron
    250660: 17, 250483: 17, 256035: 19, 250631: 18, 256097: 19, 250657: 20, 255699: 19,
    # Excavation Site: Wetlands
    260322: 28, 260325: 29, 260326: 31,
    # City of Dalaran
    247126: 29, 245999: 30, 246003: 32, 246017: 31, 246008: 31, 246016: 30, 246020: 33,
    247032: 32, 246931: 30,
    # The Drowned City (told by the owner)
    258905: 37, 258924: 38, 260042: 38, 260202: 39, 263886: 38, 273738: 38, 264177: 38,
    264172: 38, 260468: 38, 260243: 40, 260274: 40,
    # Krol'dok Stronghold
    258966: 42, 258972: 43, 259281: 43, 258964: 44, 264773: 42, 262716: 41, 258968: 45,
    # Alcaz Prison
    255391: 50, 256236: 51, 255997: 50, 257016: 52, 255702: 53,
    # Blackmaw Hold
    247206: 57, 247198: 58, 269104: 55, 269111: 55, 250034: 55, 247195: 58, 247209: 59,
    247207: 59, 247231: 59, 247234: 60,
    # The Shaper's Terrace
    253201: 61, 261813: 61, 261812: 61, 262127: 61, 261974: 61, 262081: 62, 262297: 62,
    272561: 62, 253214: 61, 261809: 62,
}
RARES = {247032, 262716, 269111}       # Lyn the Ignored, Kroog, Gortek the Apprentice
NAMES = {253214: "Izha'Rel and Tor'Rel"}  # ATT: Ravasaur Hunters
SKIP = {262688}                         # the second Ravasaur Hunter of that encounter
# Bosses and rares the game shows that neither Wowhead's zone page nor ATT lists:
# dungeon -> [(npc, name, rare)], placed after the others.
EXTRA = {
    "KROLDOK": [(262716, "Kroog", True)],
    "BLACKMAW": [(269111, "Gortek the Apprentice", True)],
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


def level(v, npc=0):
    v = as_int(v)
    if v <= 0:
        return LEVELS.get(as_int(npc), 0)
    return 0 if v >= SKULL else v




def att_boss(npc, name, loot, rare):
    """A boss known only from ATT: its loot without a chance (quality 0: the game says)."""
    return {"id": npc, "name": NAMES.get(npc, name), "classification": BOSS_RANK, "rare": rare,
            "att": [{"id": i, "quality": 0, "pct": 0} for i in loot]}


def boss_row(b, rare, own, wing=""):
    if "att" in b:
        drops = b["att"][:MAX_DROPS]
    else:
        drops = sorted((d for d in b.get("drops") or [] if as_int(d.get("id")) > 0 and keep_drop(d, own)),
                       key=lambda d: (-(d.get("quality") or 0), -pct_of(d), as_int(d["id"])))[:MAX_DROPS]
    loot = ",".join("{%d,%d,%s}" % (as_int(d["id"]), as_int(d.get("quality")),
                                    ("%.1f" % pct_of(d)).rstrip("0").rstrip("."))
                    for d in drops)
    spells = ",".join(str(s) for s in spells_of(b))
    return "{%d,%s,%s,%d,%d,%d,%d,{%s},{%s},%s}" % (
        as_int(b["id"]), lua_str(NAMES.get(as_int(b["id"]), b.get("name"))), lua_str(b.get("tag")),
        level(b.get("minLevel"), b["id"]), level(b.get("maxLevel"), b["id"]), as_int(b.get("displayId")), 1 if rare else 0, spells, loot, lua_str(wing))


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
        d = data.get(key) or {}
        own = {as_int(z.get("id")) for z in d.get("zoneDrops") or []}
        w = walk.get(key) or {}
        place = {npc: (n, wing) for n, (npc, wing) in enumerate(w.get("order") or [])}
        bosses = [b for b in d.get("bosses") or [] if as_int(b.get("id")) > 0 and is_boss(b, own)
                  and as_int(b.get("id")) not in SKIP]
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
        # The bosses of the ATT order the snapshot lacks (all of them for a dungeon Wowhead's
        # zone page had no NPC of); elsewhere only those the game showed with a level, so
        # trash in the order stays out.
        alone = not (bosses or rares)
        have = {as_int(b.get("id")) for b in bosses + rares}
        seen_names = {NAMES.get(as_int(b.get("id")), b.get("name")) for b in bosses + rares}
        names, att_loot = w.get("names") or {}, w.get("loot") or {}
        for npc, _ in w.get("order") or []:
            if npc in have or npc in SKIP or npc in NOT_BOSSES:
                continue
            if alone or npc in LEVELS:
                b = att_boss(npc, names.get(str(npc)) or str(npc), att_loot.get(str(npc)) or [], npc in RARES)
                if b["name"] in seen_names:
                    continue
                seen_names.add(b["name"])
                (rares if npc in RARES else bosses).append(b)
                have.add(npc)
        for npc, name, rare in EXTRA.get(key) or []:
            if npc not in have:
                (rares if rare else bosses).append(att_boss(npc, name, [], rare))
        bosses.sort(key=by_walk)
        rares.sort(key=by_walk)
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
