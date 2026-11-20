"""Builds Gulli-WorthIt/Data.lua from the QuestieDB Forever data.

    python3 tools/worthit/build_data.py <questiedb-checkout>
    python3 tools/worthit/build_data.py <questiedb-checkout> --unlinked

A reward worth a quest is an item of one of KINDS (by item class and subclass) that a quest gives
(the item data's `questRewards`, plus the hand list EXTRA for what the data does not link). For
each such quest: its chain back to the first step, and for every step who gives it and where,
who takes it back, and where its work is (the zone with the most spawns of what it asks for).
Repeatable quests and the quests in EXCLUDE are left out.

`--unlinked` lists the Forever items of a kind that no quest, drop or vendor gives and that are
not in seen.txt: candidates for EXTRA once players find their quest.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "questcleaner"))
import questie  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "Gulli-WorthIt", "Data.lua")
SEEN = os.path.join(HERE, "seen.txt")

# questKeys, npcKeys, objectKeys, itemKeys of QuestieDB (src/meta/*Meta.lua).
Q_NAME, Q_STARTED_BY, Q_FINISHED_BY, Q_REQ_LEVEL, Q_LEVEL, Q_RACES, Q_CLASSES = 1, 2, 3, 4, 5, 6, 7
Q_OBJECTIVES, Q_PRE_GROUP, Q_PRE_SINGLE, Q_SPECIAL = 10, 12, 13, 24
REPEATABLE = 1
N_NAME, N_SPAWNS, N_ZONE, N_FACTION = 1, 7, 9, 13
O_NAME, O_SPAWNS, O_ZONE = 1, 4, 5
I_NAME, I_NPC_DROPS, I_OBJECT_DROPS, I_ITEM_DROPS, I_QUEST_REWARDS, I_CLASS, I_SUBCLASS, I_VENDORS = 1, 2, 3, 4, 6, 12, 13, 14
FOREVER_ITEMS = 200000

# The kinds of reward, in window order: key and the test on (item class, subclass). A new kind is
# a row here, a KIND_<KEY> text in every language and an icon in ns.KIND_ICON; the window needs
# no change.
KINDS = [
    ("bag", lambda c, s: c == 1 and (s or 0) == 0),
    ("ammo", lambda c, s: c == 11),
    ("soul", lambda c, s: c == 1 and s == 1),
    ("prof", lambda c, s: c == 1 and (s or 0) >= 2),
]

# Rewards the data does not link to their quest: (item id, quest id). Only with a source a
# player can check (the quest's page), named in a comment.
EXTRA = [
    (260307, 93269),  # Hyjal Postal Satchel: Top of the Post (wowhead.com/forever/quest=93269)
    (1652, 79192),    # Sturdy Lunchbox, the other choice of Stepping Stones (wowhead.com/forever/quest=79192)
]

# Quests that give such an item but are no one-time quest a levelling player can do.
EXCLUDE = {
    9223,  # Superior Armaments of Battle: a reputation hand-in like its repeatable twins
    7634,  # Ancient Sinew Wrapped Lamina: needs a Molten Core drop, and Forever has no Molten Core
}

KALIMDOR = [14, 15, 16, 17, 141, 148, 215, 331, 357, 361, 400, 405, 406, 440, 490, 493, 618, 1377,
            1637, 1638, 1657, 2548]
ALLIANCE, HORDE = 1 + 4 + 8 + 64, 2 + 16 + 32 + 128


def seq(t):
    return [t[k] for k in sorted(t)] if isinstance(t, dict) else []


def lua_str(s):
    return '"' + (s or "").replace("\\", "\\\\").replace('"', '\\"') + '"'


def num(v):
    return ("%.1f" % v).rstrip("0").rstrip(".") if v else "0"


def kind_of(item):
    for key, test in KINDS:
        if test(item.get(I_CLASS), item.get(I_SUBCLASS)):
            return key
    return None


def zones_of(rec, spawns_key, zone_key):
    z = set()
    if rec.get(zone_key):
        z.add(rec[zone_key])
    if isinstance(rec.get(spawns_key), dict):
        z.update(rec[spawns_key].keys())
    return z


def points(rec, spawns_key):
    """zone -> the spawn points on a map (map percent)."""
    out = {}
    for zone, pts in (rec.get(spawns_key) or {}).items() if isinstance(rec.get(spawns_key), dict) else []:
        for p in seq(pts):
            xy = seq(p)
            if len(xy) >= 2 and xy[0] >= 0 and xy[1] >= 0:
                out.setdefault(zone, []).append((xy[0], xy[1]))
            else:
                out.setdefault(zone, [])
    return out


def build(quests, npcs, objects, items):
    def place(rec, spawns_key, zone_key, name_key):
        zs = sorted(zones_of(rec, spawns_key, zone_key))
        zone = rec.get(zone_key) or (zs[0] if zs else 0)
        pts = points(rec, spawns_key).get(zone) or []
        x, y = pts[0] if pts else (0, 0)
        return rec.get(name_key) or "", zone, x, y

    def who(q, key):
        by = q.get(key) or {}
        for nid in seq(by.get(1) or {}):
            return place(npcs.get(nid) or {}, N_SPAWNS, N_ZONE, N_NAME)
        for oid in seq(by.get(2) or {}):
            return place(objects.get(oid) or {}, O_SPAWNS, O_ZONE, O_NAME)
        if key == Q_STARTED_BY:
            for iid in seq(by.get(3) or {}):
                return item_place(items.get(iid) or {})
        return "", 0, 0, 0

    def item_place(it):
        """An item that starts a quest is taken where it lies or drops: the object that holds it,
        else the mob that drops it and has the most spawns. Named "Item (Source)"."""
        name = it.get(I_NAME) or ""
        best = None
        for oid in seq(it.get(I_OBJECT_DROPS) or {}):
            got = place(objects.get(oid) or {}, O_SPAWNS, O_ZONE, O_NAME)
            if got[1] and (got[2] or got[3]):
                best = got
                break
        if not best:
            most = -1
            for nid in seq(it.get(I_NPC_DROPS) or {}):
                rec = npcs.get(nid) or {}
                got = place(rec, N_SPAWNS, N_ZONE, N_NAME)
                n = sum(len(v) for v in points(rec, N_SPAWNS).values())
                if got[1] and (got[2] or got[3]) and n > most:
                    best, most = got, n
        if not best:
            return name, 0, 0, 0
        label = name if best[0] in ("", name) else "%s (%s)" % (name, best[0])
        return label, best[1], best[2], best[3]

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

    def work(q):
        """Where the quest's work is: the zone with the most spawns of what it asks for, and
        the middle spawn there. 0, 0 for a zone without a map (a dungeon)."""
        by_zone = {}

        def add(rec, spawns_key):
            for zone, pts in points(rec, spawns_key).items():
                by_zone.setdefault(zone, []).extend(pts or [None])

        obj = q.get(Q_OBJECTIVES) or {}
        for row in seq(obj.get(1) or {}):
            add(npcs.get((seq(row) or [0])[0]) or {}, N_SPAWNS)
        for row in seq(obj.get(2) or {}):
            add(objects.get((seq(row) or [0])[0]) or {}, O_SPAWNS)
        for row in seq(obj.get(3) or {}):
            it = items.get((seq(row) or [0])[0]) or {}
            for nid in seq(it.get(I_NPC_DROPS) or {}):
                add(npcs.get(nid) or {}, N_SPAWNS)
            for oid in seq(it.get(I_OBJECT_DROPS) or {}):
                add(objects.get(oid) or {}, O_SPAWNS)
        if not by_zone:
            return 0, 0, 0
        zone = max(sorted(by_zone), key=lambda z: len(by_zone[z]))
        pts = sorted(p for p in by_zone[zone] if p)
        if not pts:
            return zone, 0, 0
        # the spawn nearest the middle of them all, so the pin is on a real spot
        mx = sum(p[0] for p in pts) / len(pts)
        my = sum(p[1] for p in pts) / len(pts)
        x, y = min(pts, key=lambda p: (p[0] - mx) ** 2 + (p[1] - my) ** 2)
        return zone, x, y

    def pres(qid):
        q = quests.get(qid) or {}
        return seq(q.get(Q_PRE_GROUP) or {}) + seq(q.get(Q_PRE_SINGLE) or {})[:1]

    def depth(qid, seen=()):
        if qid in seen or len(seen) > 30:
            return 0
        return max([1 + depth(p, seen + (qid,)) for p in pres(qid) if p in quests] or [0])

    def chain(qid):
        path, cur = [qid], qid
        while len(path) < 15:
            back = [p for p in pres(cur) if p in quests and p not in path]
            if not back:
                break
            cur = max(back, key=lambda p: (depth(p), -p))
            path.insert(0, cur)
        return path

    links = []
    for iid, it in items.items():
        k = kind_of(it)
        if k:
            for qid in seq(it.get(I_QUEST_REWARDS) or {}):
                links.append((iid, k, qid))
    for iid, qid in EXTRA:
        k = kind_of(items.get(iid) or {})
        if k and (iid, k, qid) not in links:
            links.append((iid, k, qid))

    def alternatives(qid):
        """The quests of an "any one of" earlier quest, each with the others that may stand for it."""
        q = quests.get(qid) or {}
        single = [p for p in seq(q.get(Q_PRE_SINGLE) or {}) if p in quests]
        return {p: [o for o in single if o != p] for p in single} if len(single) > 1 else {}

    rewards, used, chains, alt = [], set(), {}, {}
    for iid, k, qid in sorted(links, key=lambda r: ((quests.get(r[2]) or {}).get(Q_LEVEL) or 0, r[2], r[0])):
        q = quests.get(qid)
        if not q or qid in EXCLUDE or (q.get(Q_SPECIAL) or 0) % 2 == REPEATABLE:
            continue
        rewards.append((iid, k, qid))
        path = chain(qid)
        for step in path:
            for p, others in alternatives(step).items():
                alt.setdefault(p, [o for o in others])
                used.add(p)
        used.update(path)
        if len(path) > 1:
            chains[qid] = path

    rows = {}
    for qid in sorted(used):
        q = quests[qid]
        rows[qid] = (q.get(Q_NAME) or "", q.get(Q_LEVEL) or 0, q.get(Q_REQ_LEVEL) or 0, q.get(Q_RACES) or 0,
                     q.get(Q_CLASSES) or 0, faction(q)) + who(q, Q_STARTED_BY) + who(q, Q_FINISHED_BY) + work(q)
    return rewards, rows, chains, alt


def unlinked(items):
    seen = set()
    if os.path.exists(SEEN):
        for line in open(SEEN, encoding="utf-8"):
            line = line.split("#")[0].strip()
            if line:
                seen.add(int(line))
    out = []
    for iid, it in sorted(items.items()):
        if iid < FOREVER_ITEMS or iid in seen or not kind_of(it) or "(DNT)" in str(it.get(I_NAME) or ""):
            continue
        if any(seq(it.get(k) or {}) for k in (I_QUEST_REWARDS, I_NPC_DROPS, I_OBJECT_DROPS, I_ITEM_DROPS, I_VENDORS)):
            continue
        if any(iid == e[0] for e in EXTRA):
            continue
        out.append((iid, it.get(I_NAME) or "", kind_of(it)))
    return out


def write(rewards, rows, chains, names, alt=None):
    lines = [
        "-- Generated by tools/worthit/build_data.py from QuestieDB (Forever data). Do not edit.",
        "-- Quest data (c) the Questie team and contributors, GPLv3.",
        "local _, ns = ...",
        "local D = {}",
        "ns.Data = D",
        "",
        "-- The kinds of reward, in window order.",
        "D.kinds = {%s}" % ",".join(lua_str(k) for k, _ in KINDS),
        "",
        "-- Rewards: { item, kind, the quest that gives it }, lowest quest level first.",
        "D.rewards = {",
    ]
    for iid, k, qid in rewards:
        lines.append("{%d,%s,%d}, -- %s" % (iid, lua_str(k), qid, names.get(iid, "")))
    lines += ["}", "",
              "-- Quest -> { English name, level, required level, race mask, class mask, side (A, H or \"\"),",
              "--   giver, its area, x, y, who takes it back, area, x, y, the area of its work, x, y }.",
              "-- x, y are map percent; 0, 0 is a place with no map (a dungeon) or one the data lacks.",
              "D.quest = {"]
    for qid in sorted(rows):
        r = rows[qid]
        lines.append("[%d]={%s,%d,%d,%d,%d,%s,%s,%d,%s,%s,%s,%d,%s,%s,%d,%s,%s}," % (
            qid, lua_str(r[0]), r[1], r[2], r[3], r[4], lua_str(r[5]),
            lua_str(r[6]), r[7], num(r[8]), num(r[9]), lua_str(r[10]), r[11], num(r[12]), num(r[13]),
            r[14], num(r[15]), num(r[16])))
    lines += ["}", "", "-- Reward quest -> its chain, first step first (only chains of two steps or more).", "D.chain = {"]
    for qid in sorted(chains):
        lines.append("[%d]={%s}," % (qid, ",".join(str(x) for x in chains[qid])))
    lines += ["}", "", "-- Step -> the quests that may stand for it (an \"any one of\" earlier quest, one per side).",
              "D.alt = {"]
    for qid in sorted(alt or {}):
        lines.append("[%d]={%s}," % (qid, ",".join(str(x) for x in alt[qid])))
    lines += ["}", "", "-- Areas on Kalimdor; the others are in the Eastern Kingdoms.",
              "D.kalimdor = {%s}" % ",".join(str(a) for a in sorted(set(KALIMDOR))), ""]
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    quests, npcs, objects, items = questie.load_forever(sys.argv[1])
    if "--unlinked" in sys.argv:
        for iid, name, k in unlinked(items):
            print("%d # %s (%s)" % (iid, name, k))
        sys.exit(0)
    rewards, rows, chains, alt = build(quests, npcs, objects, items)
    write(rewards, rows, chains, {iid: it.get(I_NAME) or "" for iid, it in items.items()}, alt)
    print("%d rewards, %d quests, %d chains" % (len(rewards), len(rows), len(chains)))
