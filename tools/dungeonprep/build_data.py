"""Builds Gulli-DungeonPrep/Data.lua from the QuestieDB Forever data.

    python3 tools/dungeonprep/build_data.py <questiedb-checkout>

For each dungeon: the quests that belong to it (the quest's zone is the dungeon, or a mob,
object or drop it asks for is there), with who can take them, their faction, and who starts
them and where. Repeatable quests and item exchanges at a machine (started and finished by
the same object, such as the Sparklematic 5200) give no experience and are left out.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "questcleaner"))
import luadata  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "Gulli-DungeonPrep", "Data.lua")

# questKeys, npcKeys, objectKeys, itemKeys of QuestieDB (src/meta/*Meta.lua).
Q_NAME, Q_STARTED_BY, Q_REQ_LEVEL, Q_LEVEL, Q_RACES, Q_CLASSES = 1, 2, 4, 5, 6, 7
Q_FINISHED_BY, Q_OBJECTIVES, Q_PRE_GROUP, Q_PRE_SINGLE, Q_ZONE, Q_EXCLUSIVE = 3, 10, 12, 13, 17, 16
Q_SPECIAL = 24
REPEATABLE = 1
N_NAME, N_SPAWNS, N_ZONE, N_FACTION = 1, 7, 9, 13
O_NAME, O_SPAWNS, O_ZONE = 1, 4, 5
I_NAME, I_NPC_DROPS, I_OBJECT_DROPS = 1, 2, 3

# key, area ids (the first names the dungeon), English name, level range.
DUNGEONS = [
    ("RFC", [2437], "Ragefire Chasm", 13, 18),
    ("WC", [718], "Wailing Caverns", 17, 24),
    ("DM", [1581], "The Deadmines", 17, 26),
    ("SFK", [209], "Shadowfang Keep", 22, 30),
    ("BFD", [719], "Blackfathom Deeps", 24, 32),
    ("STOCKS", [717], "The Stockade", 24, 32),
    ("GNOMER", [721, 133], "Gnomeregan", 29, 38),
    ("RFK", [491], "Razorfen Kraul", 30, 40),
    ("SM", [796], "Scarlet Monastery", 34, 45),
    ("RFD", [722], "Razorfen Downs", 37, 46),
    ("ULDA", [1337], "Uldaman", 41, 51),
    ("ZF", [1176], "Zul'Farrak", 44, 54),
    ("MARA", [2100], "Maraudon", 46, 55),
    ("ST", [1477, 1417], "Sunken Temple", 50, 56),
    ("BRD", [1584, 1585], "Blackrock Depths", 52, 60),
    ("BRS", [1583], "Blackrock Spire", 55, 60),
    ("DIREMAUL", [2557], "Dire Maul", 56, 60),
    ("SCHOLO", [2057], "Scholomance", 58, 60),
    ("STRAT", [2017], "Stratholme", 58, 60),
]


# Zones and dungeons on Kalimdor (area ids); every other zone is in the Eastern Kingdoms.
KALIMDOR = [14, 15, 16, 17, 141, 148, 215, 331, 357, 361, 400, 405, 406, 440, 490, 493, 618, 1377,
            1637, 1638, 1657, 2437, 718, 719, 491, 722, 1176, 2100, 2557]


def seq(t):
    return [t[k] for k in sorted(t)] if isinstance(t, dict) else []


def zones_of(rec, spawns_key, zone_key):
    z = set()
    if rec.get(zone_key):
        z.add(rec[zone_key])
    if isinstance(rec.get(spawns_key), dict):
        z.update(rec[spawns_key].keys())
    return z


def lua_str(s):
    return '"' + (s or "").replace("\\", "\\\\").replace('"', '\\"') + '"'


def num(v):
    return ("%.1f" % v).rstrip("0").rstrip(".") if v else "0"


def lua_list(values):
    return "{" + ",".join(str(v) for v in values) + "}"


def main(root):
    d = os.path.join(root, "data", "Forever")
    quests = luadata.load(os.path.join(d, "foreverQuestDB.lua"), "questData")
    npcs = luadata.load(os.path.join(d, "foreverNpcDB.lua"), "npcData")
    objects = luadata.load(os.path.join(d, "foreverObjectDB.lua"), "objectData")
    items = luadata.load(os.path.join(d, "foreverItemDB.lua"), "itemData")

    area_to_key = {}
    for key, areas, _, _, _ in DUNGEONS:
        for a in areas:
            area_to_key[a] = key

    # A mob or object belongs to a dungeon when every place it spawns is inside it.
    def inside(zones):
        keys = {area_to_key.get(z) for z in zones}
        if len(keys) == 1 and None not in keys:
            return keys.pop()

    def npc_key(nid):
        return inside(zones_of(npcs.get(nid) or {}, N_SPAWNS, N_ZONE))

    def obj_key(oid):
        return inside(zones_of(objects.get(oid) or {}, O_SPAWNS, O_ZONE))

    # An item belongs to a dungeon when most of what drops it is there.
    def item_key(iid):
        it = items.get(iid) or {}
        sources = [npc_key(n) for n in seq(it.get(I_NPC_DROPS) or {})]
        sources += [obj_key(o) for o in seq(it.get(I_OBJECT_DROPS) or {})]
        if not sources:
            return None
        best = max(set(sources), key=sources.count)
        if best and sources.count(best) * 3 >= len(sources) * 2:
            return best

    ranges = {k: (lo, hi) for k, _, _, lo, hi in DUNGEONS}
    by_dungeon = {k: [] for k, *_ in DUNGEONS}
    def exchange(q):
        sb, fb = q.get(Q_STARTED_BY) or {}, q.get(Q_FINISHED_BY) or {}
        objs = seq(sb.get(2) or {})
        return (not seq(sb.get(1) or {}) and not seq(sb.get(3) or {}) and objs
                and not seq(fb.get(1) or {}) and set(objs) == set(seq(fb.get(2) or {})))

    dropped = []
    for qid, q in quests.items():
        level = q.get(Q_LEVEL)
        if not level:
            continue
        if (q.get(Q_SPECIAL) or 0) & REPEATABLE or exchange(q):
            dropped.append(qid)
            continue
        keys = set()
        if q.get(Q_ZONE) in area_to_key:
            keys.add(area_to_key[q[Q_ZONE]])
        obj = q.get(Q_OBJECTIVES) or {}
        keys.update(npc_key(o.get(1)) for o in seq(obj.get(1) or {}))
        keys.update(obj_key(o.get(1)) for o in seq(obj.get(2) or {}))
        keys.update(item_key(o.get(1)) for o in seq(obj.get(3) or {}))
        keys.discard(None)
        for k in keys:
            lo, hi = ranges[k]
            # Cloth and leather turn-ins are level 60 everywhere; keep quests near the dungeon.
            if lo - 6 <= level <= hi + 4:
                by_dungeon[k].append(qid)

    # The first spawn in the zone, in map percent; 0, 0 when it is not on a map (inside).
    def spot(rec, spawns_key, zone):
        pts = seq((rec.get(spawns_key) or {}).get(zone) or {})
        if pts:
            xy = seq(pts[0])
            if len(xy) >= 2 and xy[0] >= 0 and xy[1] >= 0:
                return xy[0], xy[1]
        return 0, 0

    def starter(q):
        sb = q.get(Q_STARTED_BY) or {}
        for nid in seq(sb.get(1) or {}):
            n = npcs.get(nid) or {}
            zs = sorted(zones_of(n, N_SPAWNS, N_ZONE))
            zone = n.get(N_ZONE) or (zs[0] if zs else 0)
            return (n.get(N_NAME) or "", zone) + spot(n, N_SPAWNS, zone)
        for oid in seq(sb.get(2) or {}):
            o = objects.get(oid) or {}
            zs = sorted(zones_of(o, O_SPAWNS, O_ZONE))
            zone = o.get(O_ZONE) or (zs[0] if zs else 0)
            return (o.get(O_NAME) or "", zone) + spot(o, O_SPAWNS, zone)
        for iid in seq(sb.get(3) or {}):
            return (items.get(iid) or {}).get(I_NAME) or "", 0, 0, 0
        return "", 0, 0, 0

    # "A" or "H" when the quest is for one faction only: from its race mask, else from the
    # NPCs that give and take it (QuestieDB leaves the race mask 0 on many such quests).
    ALLIANCE, HORDE = 1 + 4 + 8 + 64, 2 + 16 + 32 + 128

    def faction(q):
        races = q.get(Q_RACES) or 0
        low = races % 2 ** 32
        if races:
            if low & ALLIANCE and not low & HORDE:
                return "A"
            if low & HORDE and not low & ALLIANCE:
                return "H"
            return ""
        for key in (Q_STARTED_BY, Q_FINISHED_BY):
            for nid in seq((q.get(key) or {}).get(1) or {}):
                f = (npcs.get(nid) or {}).get(N_FACTION)
                if f in ("A", "H"):
                    return f
        return ""

    lines = [
        "-- Generated by tools/dungeonprep/build_data.py from QuestieDB (Forever data). Do not edit.",
        "-- Quest data (c) the Questie team and contributors, GPLv3.",
        "local _, ns = ...",
        "local D = {}",
        "ns.Data = D",
        "-- { key, area ids, English name, min level, max level }",
        "D.dungeons = {",
    ]
    for key, areas, name, lo, hi in DUNGEONS:
        lines.append("{%s,%s,%s,%d,%d}," % (lua_str(key), lua_list(areas), lua_str(name), lo, hi))
    lines.append("}")
    lines.append("-- Dungeon -> quests.")
    lines.append("D.byDungeon = {")
    used = set()
    for key, *_ in DUNGEONS:
        ids = sorted(by_dungeon[key])
        used.update(ids)
        lines.append("%s=%s," % (key, lua_list(ids)))
    lines.append("}")
    lines.append("-- Quest -> { English name, level, required level, race mask, class mask,")
    lines.append("--   who starts it, the area id there, quests before it (all of them), quests before it (one of them),")
    lines.append("--   quests that close it, faction (A, H or \"\" for both), x, y on the zone map }.")
    lines.append("D.quest = {")
    for qid in sorted(used):
        q = quests[qid]
        who, area, x, y = starter(q)
        lines.append("[%d]={%s,%d,%d,%d,%d,%s,%d,%s,%s,%s,%s,%s,%s}," % (
            qid, lua_str(q.get(Q_NAME)), q.get(Q_LEVEL) or 0, q.get(Q_REQ_LEVEL) or 0, q.get(Q_RACES) or 0,
            q.get(Q_CLASSES) or 0, lua_str(who), area or 0, lua_list(seq(q.get(Q_PRE_GROUP) or {})),
            lua_list(seq(q.get(Q_PRE_SINGLE) or {})), lua_list(seq(q.get(Q_EXCLUSIVE) or {})),
            lua_str(faction(q)), num(x), num(y)))
    lines.append("}")
    lines.append("-- Area ids on Kalimdor; the rest are in the Eastern Kingdoms.")
    lines.append("D.kalimdor = %s" % lua_list(KALIMDOR))
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(", ".join("%s %d" % (k, len(by_dungeon[k])) for k, *_ in DUNGEONS))
    print("quests %d, %d bytes; left out %d repeatable or exchange quests" % (
        len(used), os.path.getsize(OUT), len(dropped)))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
