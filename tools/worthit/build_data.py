"""Builds Gulli-WorthIt/Data.lua from the QuestieDB Forever data.

    python3 tools/worthit/build_data.py <questiedb-checkout>
    python3 tools/worthit/build_data.py <questiedb-checkout> --unlinked

A reward worth a quest is an item of one of KINDS (by item class and subclass) that a quest gives
(the item data's `questRewards`, plus the hand list EXTRA for what the data does not link). For
each such quest: its chain back to the first step, and for every step who gives it and where,
who takes it back, and where its work is (the zone with the most spawns of what it asks for).
Repeatable quests and the quests in EXCLUDE are left out.

Class quests come from the Wowhead snapshot CLASS_SNAPSHOT (WoW Forever's class-specific
quests that give an item, collected on a player's computer since Wowhead refuses servers): each
one QuestieDB knows gets the same chain and places, and goes into D.class with the items it
gives (CLASS_ITEM_CLASSES only) and its class mask. Raids Forever has not opened (CLOSED_RAIDS),
profession quests (a quest sort that is no class's, for more than one class) and quests above
level 60 are left out.

Library books come from the librarians (TAKERS): every quest for no one class they take back that asks for
one item is a book's hand-in, and that item lies on a world object whose spawns are its places
(BOOK_PLACES adds a place the data lacks). The milestone quests (TIERS, with the number of books
the game asks for, which no data holds) give their rewards from the item data's `questRewards`,
plus TIER_ITEMS where the data does not link them. D.books, D.librarian and D.tiers.

`--unlinked` lists the Forever items of a kind that no quest, drop or vendor gives and that are
not in seen.txt: candidates for EXTRA once players find their quest.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "questcleaner"))
import questie  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "Gulli-WorthIt", "Data.lua")
SEEN = os.path.join(HERE, "seen.txt")
CLASS_SNAPSHOT = os.path.join(HERE, "wowhead-classquests.json")

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
    ("rest", lambda c, s: False),
]

# Lasting rewards no item class marks (a misc item that is a tool for good): item id -> kind of
# KINDS. A kind used only here tests False above, so it keeps its place in the window order.
ITEM_KINDS = {
    211527: "rest",  # Cozy Sleeping Bag: sleeping in it gives up to +3% XP (This Must Be The Place)
}

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

# Class quests: the item classes worth listing (bags, weapons, armour, totems and other class
# reagents, quivers), Wowhead's quest sorts of the classes, and the raids Forever has not opened
# (Zul'Gurub, Ruins and Temple of Ahn'Qiraj, Molten Core, Blackwing Lair, Naxxramas). A raid
# that opens leaves CLOSED_RAIDS.
CLASS_ITEM_CLASSES = {1, 2, 4, 5, 11}
CLASS_SORTS = {-61, -81, -82, -141, -161, -162, -261, -262, -263}
CLOSED_RAIDS = {1977, 3429, 3428, 2717, 2677, 3456}
MAX_LEVEL = 60

# Class quests of WoW Forever that the Wowhead snapshot misses, with the reason; their items come
# from the item data's `questRewards`. Only a quest QuestieDB's Forever data has.
CLASS_EXTRA = {
    97257: "Call of Fire for the Forever Horde shamans of Olariaan Swiftburn: Fire Totem",
    1782: "Furen's Armor, the warriors' Fire Hardened Mail chain: Fire Hardened Hauberk",
}

# Library books. Who takes the books back, Alliance then Horde: the librarians (Garion Wendell in
# Stormwind, Owen Thadd in Undercity) and, for the level 60 books, the mage trainers beside them
# (Jennea Cannon, Oran Snakewrithe); the milestone quests with the books they ask for (from the players' guides:
# Warcraft Tavern, foreverchanges.pro); books that are not in WoW Forever; places the data lacks.
TAKERS = [(211033, 211022), (5497, 7825)]
TIERS = {78150: 10, 79536: 20, 82208: 25, 84394: 35}
TIER_ITEMS = {84394: [281637, 277202, 281636]}  # warcrafttavern.com/forever/guides/library-books
NOT_BOOKS = {81951}  # The Liminal and the Arcane: Season of Discovery only (foreverchanges.pro/library-books)
BOOK_PLACES = {79953: [(8, 61.2, 22.2)]}  # A Luddite's Guide: caged in Fallow Sanctuary (the guides above)

KALIMDOR = [14, 15, 16, 17, 141, 148, 215, 331, 357, 361, 400, 405, 406, 440, 490, 493, 618, 1377,
            1637, 1638, 1657, 2548]
ALLIANCE, HORDE = 1 + 4 + 8 + 64, 2 + 16 + 32 + 128


def seq(t):
    return [t[k] for k in sorted(t)] if isinstance(t, dict) else []


def lua_str(s):
    return '"' + (s or "").replace("\\", "\\\\").replace('"', '\\"') + '"'


def num(v):
    return ("%.1f" % v).rstrip("0").rstrip(".") if v else "0"


def kind_of(item, iid=None):
    if iid in ITEM_KINDS:
        return ITEM_KINDS[iid]
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


def class_links(quests, items, snapshot):
    """(quest, class mask, items) for every class quest of the snapshot worth listing."""
    out = []
    for row in snapshot:
        qid, mask = row["id"], row["classes"]
        if row["category"] in CLOSED_RAIDS or row["level"] > MAX_LEVEL:
            continue
        if row["category"] not in CLASS_SORTS and bin(mask).count("1") > 1:
            continue
        q = quests.get(qid)
        if not q or qid in EXCLUDE or (q.get(Q_SPECIAL) or 0) % 2 == REPEATABLE:
            continue
        got = []
        for iid in row["rewards"] + row["choices"]:
            it = items.get(iid)
            if iid not in got and (not it or it.get(I_CLASS) in CLASS_ITEM_CLASSES):
                got.append(iid)
        if got:
            out.append((qid, mask, got))
    listed = {qid for qid, _, _ in out}
    for qid in sorted(CLASS_EXTRA):
        q = quests.get(qid)
        if not q or qid in listed:
            continue
        got = sorted(iid for iid, it in items.items()
                     if qid in seq(it.get(I_QUEST_REWARDS) or {}) and it.get(I_CLASS) in CLASS_ITEM_CLASSES)
        if got:
            out.append((qid, q.get(Q_CLASSES) or 0, got))
    return out


def build(quests, npcs, objects, items, classq=()):
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
        # every NPC counts: a quest that the trainers of both sides give (Cenarion Aid, the
        # first step of the priests' Sunken Temple chain) is for both sides
        for key in (Q_STARTED_BY, Q_FINISHED_BY):
            sides = set()
            for nid in seq((q.get(key) or {}).get(1) or {}):
                f = (npcs.get(nid) or {}).get(N_FACTION)
                if f in ("A", "H"):
                    sides.add(f)
            if len(sides) == 1:
                return sides.pop()
            if sides:
                return ""
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
        k = kind_of(it, iid)
        if k:
            for qid in seq(it.get(I_QUEST_REWARDS) or {}):
                links.append((iid, k, qid))
    for iid, qid in EXTRA:
        k = kind_of(items.get(iid) or {}, iid)
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

    classes = []
    for qid, mask, got in sorted(classq, key=lambda r: ((quests.get(r[0]) or {}).get(Q_LEVEL) or 0, r[0])):
        classes.append((qid, mask, got))
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
    return rewards, rows, chains, alt, classes


def library(quests, npcs, objects, items):
    """(books, takers, tiers): books as (quest, item, level, places, name, taker index), the
    takers as a list of side -> (name, area, x, y), the tiers as (quest, books, required level, items, givers)
    where givers is side -> (name, area, x, y)."""
    def npc_place(nid):
        n = npcs.get(nid) or {}
        pts = points(n, N_SPAWNS)
        zone = n.get(N_ZONE) or (sorted(pts)[0] if pts else 0)
        x, y = (pts.get(zone) or [(0, 0)])[0]
        return n.get(N_NAME) or "", zone, x, y

    def givers(q):
        out = {}
        for nid in seq((q.get(Q_FINISHED_BY) or {}).get(1) or {}):
            side = (npcs.get(nid) or {}).get(N_FACTION)
            if side in ("A", "H") and side not in out:
                out[side] = npc_place(nid)
        return out

    books = []
    for qid, q in sorted(quests.items()):
        ends = set(seq((q.get(Q_FINISHED_BY) or {}).get(1) or {}))
        taker = next((i + 1 for i, ids in enumerate(TAKERS) if ends & set(ids)), None)
        if not taker or qid in TIERS or qid in NOT_BOOKS or q.get(Q_CLASSES):
            continue
        wanted = [seq(r)[0] for r in seq((q.get(Q_OBJECTIVES) or {}).get(3) or {}) if seq(r)]
        if len(wanted) != 1:
            continue
        iid = wanted[0]
        places = []
        for oid in seq((items.get(iid) or {}).get(I_OBJECT_DROPS) or {}):
            for zone, pts in sorted(points(objects.get(oid) or {}, O_SPAWNS).items()):
                for x, y in pts[:1]:
                    places.append((zone, x, y))
        places += [p for p in BOOK_PLACES.get(qid, []) if p not in places]
        books.append((qid, iid, q.get(Q_LEVEL) or 0, places, q.get(Q_NAME) or "", taker))
    books.sort(key=lambda b: (b[2], b[0]))

    takers = []
    for ids in TAKERS:
        by = {}
        for nid in ids:
            side = (npcs.get(nid) or {}).get(N_FACTION)
            if side in ("A", "H"):
                by[side] = npc_place(nid)
        takers.append(by)

    tiers = []
    for qid, need in sorted(TIERS.items(), key=lambda t: t[1]):
        q = quests.get(qid)
        if not q:
            continue
        got = sorted(iid for iid, it in items.items() if qid in seq(it.get(I_QUEST_REWARDS) or {}))
        got += [i for i in TIER_ITEMS.get(qid, []) if i not in got]
        tiers.append((qid, need, q.get(Q_REQ_LEVEL) or 1, got, givers(q)))
    return books, takers, tiers


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


def write(rewards, rows, chains, names, alt=None, classes=(), lib=None):
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
              "-- Class quests: { quest, class mask (1 warrior ... 1024 druid), items it gives }, lowest level first.",
              "D.class = {"]
    for qid, mask, got in classes:
        lines.append("{%d,%d,{%s}}, -- %s" % (qid, mask, ",".join(str(i) for i in got), rows[qid][0]))
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
    books, takers, tiers = lib or ([], [], [])

    def place(p):
        return "{%s,%d,%s,%s}" % (lua_str(p[0]), p[1], num(p[2]), num(p[3]))

    lines += ["}", "",
              "-- Library books: { hand-in quest, the book (item), the quest's level, { area, x, y, area, x, y ... }",
              "--   (where it lies; a book in two places has both), who takes it back (D.takers) }, lowest level first.",
              "D.books = {"]
    for qid, iid, level, places, name, taker in books:
        flat = ",".join("%d,%s,%s" % (z, num(x), num(y)) for z, x, y in places)
        lines.append("{%d,%d,%d,{%s},%d}, -- %s" % (qid, iid, level, flat, taker, name))
    lines += ["}", "", "-- Who takes the books back, by side: { name, area, x, y }; the librarians first.",
              "D.takers = {"]
    for by in takers:
        lines.append("{%s}," % ",".join("%s=%s" % (side, place(by[side])) for side in sorted(by)))
    lines += ["}",
              "", "-- The milestones: { quest, books it asks for, required level, { reward items },",
              "--   { A = who gives it, H = ... } }, fewest books first.",
              "D.tiers = {"]
    for qid, need, req, got, giv in tiers:
        lines.append("{%d,%d,%d,{%s},{%s}}," % (qid, need, req, ",".join(str(i) for i in got),
                                                ",".join("%s=%s" % (side, place(giv[side])) for side in sorted(giv))))
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
    with open(CLASS_SNAPSHOT, encoding="utf-8") as f:
        snapshot = json.load(f)["quests"]
    classq = class_links(quests, items, snapshot)
    rewards, rows, chains, alt, classes = build(quests, npcs, objects, items, classq)
    lib = library(quests, npcs, objects, items)
    write(rewards, rows, chains, {iid: it.get(I_NAME) or "" for iid, it in items.items()}, alt, classes, lib)
    print("%d rewards, %d class quests, %d quests, %d chains, %d books, %d tiers" % (
        len(rewards), len(classes), len(rows), len(chains), len(lib[0]), len(lib[2])))
