"""Builds Gulli-DungeonPrep/Data.lua from the QuestieDB Forever data.

    python3 tools/dungeonprep/build_data.py <questiedb-checkout>

For each dungeon: the quests that belong to it (the quest's zone is the dungeon, or a mob,
object or drop it asks for is there), with who can take them and who starts them.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "questcleaner"))
import luadata  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "Gulli-DungeonPrep", "Data.lua")

# questKeys, npcKeys, objectKeys, itemKeys of QuestieDB (src/meta/*Meta.lua).
Q_NAME, Q_STARTED_BY, Q_REQ_LEVEL, Q_LEVEL, Q_RACES, Q_CLASSES = 1, 2, 4, 5, 6, 7
Q_OBJECTIVES, Q_PRE_GROUP, Q_PRE_SINGLE, Q_ZONE, Q_EXCLUSIVE = 10, 12, 13, 17, 16
N_NAME, N_SPAWNS, N_ZONE = 1, 7, 9
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
    for qid, q in quests.items():
        level = q.get(Q_LEVEL)
        if not level:
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

    def starter(q):
        sb = q.get(Q_STARTED_BY) or {}
        for nid in seq(sb.get(1) or {}):
            n = npcs.get(nid) or {}
            zs = sorted(zones_of(n, N_SPAWNS, N_ZONE))
            return n.get(N_NAME) or "", (n.get(N_ZONE) or (zs[0] if zs else 0))
        for oid in seq(sb.get(2) or {}):
            o = objects.get(oid) or {}
            zs = sorted(zones_of(o, O_SPAWNS, O_ZONE))
            return o.get(O_NAME) or "", (o.get(O_ZONE) or (zs[0] if zs else 0))
        for iid in seq(sb.get(3) or {}):
            return (items.get(iid) or {}).get(I_NAME) or "", 0
        return "", 0

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
    lines.append("--   quests that close it }.")
    lines.append("D.quest = {")
    for qid in sorted(used):
        q = quests[qid]
        who, area = starter(q)
        lines.append("[%d]={%s,%d,%d,%d,%d,%s,%d,%s,%s,%s}," % (
            qid, lua_str(q.get(Q_NAME)), q.get(Q_LEVEL) or 0, q.get(Q_REQ_LEVEL) or 0, q.get(Q_RACES) or 0,
            q.get(Q_CLASSES) or 0, lua_str(who), area or 0, lua_list(seq(q.get(Q_PRE_GROUP) or {})),
            lua_list(seq(q.get(Q_PRE_SINGLE) or {})), lua_list(seq(q.get(Q_EXCLUSIVE) or {}))))
    lines.append("}")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(", ".join("%s %d" % (k, len(by_dungeon[k])) for k, *_ in DUNGEONS))
    print("quests %d, %d bytes" % (len(used), os.path.getsize(OUT)))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
