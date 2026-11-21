"""Builds Gulli-DungeonPrep/Data.lua from the QuestieDB Forever data.

    python3 tools/dungeonprep/build_data.py <questiedb-checkout> [<allthethings-checkout> [<guidelime-dungeonquests-checkout>]]

With an AllTheThings checkout (MIT, its `.contrib/.db/forever` folder is enough), every quest
ATT lists under a dungeon belongs to it too, and ATT's faction wins over QuestieDB's race mask
for WoW Forever's own quests (see att.py).

With a Guidelime_DungeonQuests checkout (GPLv3), the quests of each dungeon's levelling guide
belong to it too, also the chain steps outside it, and `D.main` names them: the chains a player
takes for the dungeon while levelling, not every quest that touches it (see guides.py).

For each dungeon: the quests that belong to it (the quest's zone is the dungeon, or a mob,
object or drop it asks for is there), with who can take them, their faction, and who starts
them and where, who takes it back, its reward items, the dungeon mobs it needs (lowest level
first, a rough boss order), and its place in a chain. Repeatable quests and item exchanges at a machine (started and finished by
the same object, such as the Sparklematic 5200) give no experience and are left out.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "questcleaner"))
import questie  # noqa: E402
import luadata  # noqa: E402
sys.path.insert(0, HERE)
import att  # noqa: E402
import guides  # noqa: E402
sys.path.insert(0, os.path.join(HERE, "..", "i18n"))
import i18n  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "Gulli-DungeonPrep", "Data.lua")

# questKeys, npcKeys, objectKeys, itemKeys of QuestieDB (src/meta/*Meta.lua).
Q_NAME, Q_STARTED_BY, Q_REQ_LEVEL, Q_LEVEL, Q_RACES, Q_CLASSES = 1, 2, 4, 5, 6, 7
Q_FINISHED_BY, Q_OBJECTIVES, Q_PRE_GROUP, Q_PRE_SINGLE, Q_ZONE, Q_EXCLUSIVE = 3, 10, 12, 13, 17, 16
Q_SPECIAL, Q_TEXT = 24, 8
REPEATABLE = 1
N_NAME, N_MAX_LEVEL, N_SPAWNS, N_ZONE, N_FACTION = 1, 5, 7, 9, 13
O_NAME, O_SPAWNS, O_ZONE = 1, 4, 5
I_NAME, I_NPC_DROPS, I_OBJECT_DROPS, I_START_QUEST, I_QUEST_REWARDS = 1, 2, 3, 5, 6
Q_SOURCE_ITEM = 11

# key, area ids (the first names the dungeon; none for a Forever area the client data does not
# name), English name, level range.
DUNGEONS = [
    ("RFC", [2437], "Ragefire Chasm", 13, 18),
    ("WC", [718], "Wailing Caverns", 17, 24),
    ("DM", [1581], "The Deadmines", 17, 26),
    ("SFK", [209], "Shadowfang Keep", 22, 30),
    ("BFD", [719], "Blackfathom Deeps", 24, 32),
    ("STOCKS", [717], "The Stockade", 24, 32),
    ("GNOMER", [721, 133], "Gnomeregan", 29, 38),
    ("RFK", [491, 1717], "Razorfen Kraul", 30, 40),
    ("SM", [796], "Scarlet Monastery", 34, 45),
    ("RFD", [722], "Razorfen Downs", 37, 46),
    ("ULDA", [1337, 1517], "Uldaman", 41, 51),
    ("ZF", [1176], "Zul'Farrak", 44, 54),
    ("MARA", [2100], "Maraudon", 46, 55),
    ("ST", [1477, 1417], "Sunken Temple", 50, 56),
    ("BRD", [1584, 1585, 17803], "Blackrock Depths", 52, 60),
    ("BRS", [1583, 17804], "Blackrock Spire", 55, 60),
    ("DIREMAUL", [2557], "Dire Maul", 56, 60),
    ("SCHOLO", [2057], "Scholomance", 58, 60),
    ("STRAT", [2017], "Stratholme", 58, 60),
    # WoW Forever's own dungeons (levels from Blizzard's list of September 15, 2026).
    ("THANES", [16919], "The Hall of Thanes", 13, 18),
    ("LORDAERON", [16611, 16612, 16614, 16615, 16617], "Ruins of Lordaeron", 15, 20),
    ("EXCAVATION", [16732, 16877, 16878, 16879, 16880], "Excavation Site: Wetlands", 24, 29),
    ("DALARAN", [16544, 16558, 16559, 16562], "City of Dalaran", 28, 33),
    ("DROWNED", [], "The Drowned City", 35, 40),
    ("KROLDOK", [17780], "Krol'dok Stronghold", 40, 45),
    ("ALCAZ", [], "Alcaz Prison", 48, 53),
    ("BLACKMAW", [], "Blackmaw Hold", 55, 60),
    ("SHAPERS", [16985], "Shaper's Terrace", 58, 60),
]

# The Forever dungeons' mobs have no spawns in the data, so they are named here: the bosses
# and the mobs whose drops quests ask for, by npc id. A Forever quest (id 90000 and up) that
# names the dungeon in its objective (WORDS) belongs to it too.
NPCS = {
    "THANES": [261306, 261311, 261319],
    "LORDAERON": [250483, 250631, 255699, 256035, 256097, 250657],
    "EXCAVATION": [260322, 260325, 260326],
    "DALARAN": [245999, 246003, 246008, 246017, 247032, 247126, 246931, 246020],
    "DROWNED": [258905, 270882, 258924, 270883, 260042, 270884, 260213, 268478, 263886, 270887, 273738,
                260243, 260274, 267852, 269466, 270886],
    "KROLDOK": [258966, 258972, 258964, 258968, 259256, 268423],
    "ALCAZ": [255391, 255997, 257016, 256236, 255702, 255707, 264770],
    "BLACKMAW": [247195, 247206, 247209, 247198, 247234, 247207, 247231],
    "SHAPERS": [253201, 261812, 261813, 262127, 261974, 261993, 262297, 262081, 272561, 261809],
}
# Givers the data does not name, by npc id: Mason Connery, chained at the end of Alcaz Prison,
# gives The Man in the Iron Chains (ATT and the players' reports; not offered once The
# Questioner is dead). An npc here that stands in the dungeon belongs in NPCS too.
STARTERS = {96335: 264770}
# Who takes a quest back where the data names nobody, by npc id: Mason Connery again.
FINISHERS = {96335: 264770}
# Quests the data cannot tie to their dungeon (their item has no drop data).
QUESTS = {"BLACKMAW": [92065]}
WORDS = {
    "THANES": ["Hall of Thanes"], "LORDAERON": ["Ruins of Lordaeron"], "EXCAVATION": ["Excavation Site"],
    "DALARAN": ["City of Dalaran"], "DROWNED": ["Drowned City"], "KROLDOK": ["Krol'dok Stronghold"],
    "ALCAZ": ["Alcaz Prison"], "BLACKMAW": ["Blackmaw Hold"], "SHAPERS": ["Shaper's Terrace"],
}

# Each dungeon's file in AllTheThings' `.contrib/.db/forever/dungeons & raids/`.
ATT_FILES = {
    "RFC": "ragefire chasm", "WC": "wailing caverns", "DM": "the deadmines", "SFK": "shadowfang keep",
    "BFD": "blackfathom deeps", "STOCKS": "the stockade", "GNOMER": "gnomeregan", "RFK": "razorfen kraul",
    "SM": "scarlet monastery", "RFD": "razorfen downs", "ULDA": "uldaman", "ZF": "zul'farrak",
    "MARA": "maraudon", "ST": "the temple of atal'hakkar", "BRD": "blackrock depths",
    "BRS": "blackrock spire", "DIREMAUL": "dire maul", "SCHOLO": "scholomance", "STRAT": "stratholme",
    "THANES": "hall of thanes", "LORDAERON": "ruins of lordaeron", "EXCAVATION": "excavation site - wetlands",
    "DALARAN": "city of dalaran", "DROWNED": "the drowned city", "KROLDOK": "krol'dok stronghold",
    "ALCAZ": "alcaz prison", "BLACKMAW": "blackmaw hold", "SHAPERS": "the shaper's terrace",
}
FOREVER_QUESTS = 90000
# Quests the levelling guides leave out on purpose that still count as a chain for the dungeon
# (owner's decision, each one by name): they join D.main.
MAIN_EXTRA = {
    "MARA": [93404],  # Rot and Regret, the Maraudon step of the Shen'dralas chain
    "RFD": [93604],  # Agamaggan's Blood, the end of that chain
    "EXCAVATION": [95737],  # Seeking Caitlin
    "KROLDOK": [94969],  # Krol'dok No More!
    "BLACKMAW": [92065, 99187],  # Blackmaw Reclamation, The Reliquary of Tyr
    "DALARAN": [92459, 97287],  # Friend of the Kirin Tor, Shrewd Negotiations
}

# Quests whose work the game moved out of the dungeon: the data still ties it there, so the
# "inside" mark of that part is dropped by hand (the quest stays in the dungeon's list).
OUTSIDE_WORK = {
    93604: "d",  # Agamaggan's Blood: the elite area outside Razorfen Downs too (hotfix of 2026-11-17)
}

# Each dungeon's levelling guides in Guidelime_DungeonQuests (the part of the file name after
# the levels): the quest chains a player takes for it while levelling, for each faction.
GDQ_FILES = {
    "THANES": ["The_Hall_of_Thanes"], "RFC": ["Ragefire_Chasm"], "LORDAERON": ["Ruins_of_Lordaeron"],
    "DM": ["Deadmines"], "WC": ["Wailing_Caverns"], "SFK": ["Shadowfang_Keep"],
    "EXCAVATION": ["Excavation_Site_Wetlands"], "BFD": ["Blackfathom_Deeps"], "STOCKS": ["The_Stockade"],
    "DALARAN": ["City_of_Dalaran"], "RFK": ["Razorfen_Kraul"], "GNOMER": ["Gnomeregan"],
    "SM": ["Scarlet_Monastery_Armory", "Scarlet_Monastery_Cathedral", "Scarlet_Monastery_Graveyard",
           "Scarlet_Monastery_Library"],
    "DROWNED": ["The_Drowned_City"], "RFD": ["Razorfen_Downs"], "KROLDOK": ["Krol_dok_Stronghold"],
    "ULDA": ["Uldaman"], "ZF": ["Zul_Farrak"], "ALCAZ": ["Alcaz_Prison"], "MARA": ["Maraudon"],
    "ST": ["The_Temple_of_Atal_Hakkar"], "BRD": ["Blackrock_Depths"], "BLACKMAW": ["Blackmaw_Hold"],
    "DIREMAUL": ["Dire_Maul_East", "Dire_Maul_North", "Dire_Maul_West"],
    "BRS": ["Lower_Blackrock_Spire", "Upper_Blackrock_Spire"], "SCHOLO": ["Scholomance"],
    "SHAPERS": ["The_Shapers_Terrace"], "STRAT": ["Stratholme_Living", "Stratholme_Undead"],
}

# The way in of each dungeon: the zone's area id and the spot on its map in percent. Read
# off the game's maps by hand (QuestieDB has no entrances); check one in the game when moved.
ENTRANCES = {
    "RFC": (1637, 52.0, 49.6), "WC": (17, 46.0, 36.4), "DM": (40, 42.5, 71.7), "SFK": (130, 44.8, 67.8),
    "BFD": (331, 14.2, 13.9), "STOCKS": (1519, 40.5, 55.9), "GNOMER": (1, 24.3, 39.8), "RFK": (17, 42.3, 89.9),
    "SM": (85, 82.9, 33.2), "RFD": (17, 49.0, 93.9), "ULDA": (3, 44.0, 12.3), "ZF": (440, 38.7, 20.0),
    "MARA": (405, 29.1, 62.5), "ST": (8, 69.9, 53.5), "BRD": (46, 29.4, 37.6), "BRS": (46, 29.4, 37.6),
    "DIREMAUL": (357, 59.0, 44.9), "SCHOLO": (28, 69.4, 73.2), "STRAT": (139, 27.4, 11.6),
    # Forever: Krol'dok from the Riverglades guide run; the rest stand at the NPC next to the way
    # in (QuestieDB has no entrances and no site gives numbers yet), so check them in the game.
    "THANES": (1537, 33.2, 48.0), "LORDAERON": (85, 61.9, 66.0), "EXCAVATION": (11, 38.8, 52.4),
    "DALARAN": (36, 14.3, 59.6), "DROWNED": (33, 25.5, 25.0), "KROLDOK": (16591, 44.4, 26.5),
    "ALCAZ": (15, 70.3, 18.9), "BLACKMAW": (16, 42.4, 20.9), "SHAPERS": (490, 34.9, 22.1),
}


# Zones and dungeons on Kalimdor (area ids); every other zone is in the Eastern Kingdoms.
KALIMDOR = [14, 15, 16, 17, 141, 148, 215, 331, 357, 361, 400, 405, 406, 440, 490, 493, 618, 1377,
            1637, 1638, 1657, 2437, 718, 719, 491, 722, 1176, 2100, 2557, 16985]


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


def load_xp(root):
    """Quest -> (quest level, experience at that level), from QuestieDB's Forever QuestXP tables
    (the classic table, then what players' traces measured in WoW Forever). Read as text."""
    out = {}
    d = os.path.join(root, "support", "Forever", "QuestXP")
    for name in ("xpDB-classic.lua", "xpDB-traces.lua"):
        path = os.path.join(d, name)
        if not os.path.exists(path):
            continue
        with open(path, encoding="utf-8") as fh:
            for m in re.finditer(r"^\s*(?:QuestXP\.db)?\[(\d+)\]\s*=\s*\{\s*(\d+)\s*,\s*(\d+)\s*\}", fh.read(), re.M):
                out[int(m.group(1))] = (int(m.group(2)), int(m.group(3)))
    return out


def load_att(root):
    """Dungeon key -> {quest id: "A" | "H" | ""} from an AllTheThings checkout, and
    {quest id: {"pre", "alt", "lvl"}} of every quest there; both empty without one."""
    if not root:
        return {}, {}
    base = os.path.join(root, ".contrib", ".db", "forever")
    folder = os.path.join(base, "dungeons & raids")
    out, links = {}, {}
    for key, name in ATT_FILES.items():
        path = os.path.join(folder, name + ".lua")
        if os.path.exists(path):
            out[key] = att.quests(path)
        else:
            print("no AllTheThings file for %s: %s" % (key, path))
    # A chain may start in a zone file (The Missing Kor'kron in Orgrimmar's).
    for d, _, files in sorted(os.walk(base)):
        for f in sorted(files):
            if f.endswith(".lua"):
                for qid, link in att.links(os.path.join(d, f)).items():
                    have = links.setdefault(qid, {"pre": [], "alt": [], "lvl": 0})
                    have["pre"] += [p for p in link["pre"] if p not in have["pre"]]
                    have["alt"] += [a for a in link["alt"] if a not in have["alt"]]
                    have["lvl"] = have["lvl"] or link["lvl"]
    return out, links


def add_att_links(quests, links):
    """Fills in what QuestieDB lacks for WoW Forever's own quests from ATT: the quests before
    one (State Secrets needs the Document Box of More Valuable Than Gold), the copies that close
    it and the level it opens at. QuestieDB's own values always stay."""
    for qid, link in links.items():
        q = quests.get(qid)
        if q is None or qid < FOREVER_QUESTS:
            continue
        pre = [p for p in link["pre"] if p in quests]
        if pre and not seq(q.get(Q_PRE_SINGLE) or {}) and not seq(q.get(Q_PRE_GROUP) or {}):
            q[Q_PRE_GROUP if len(pre) > 1 else Q_PRE_SINGLE] = {i + 1: p for i, p in enumerate(pre)}
        alt = [a for a in link["alt"] if a in quests]
        if alt and not seq(q.get(Q_EXCLUSIVE) or {}):
            q[Q_EXCLUSIVE] = {i + 1: a for i, a in enumerate(alt)}
        if link["lvl"] and not q.get(Q_REQ_LEVEL):
            q[Q_REQ_LEVEL] = link["lvl"]


def add_starters(quests):
    """Hand-set givers and takers the data lacks (STARTERS, FINISHERS)."""
    for field, table in ((Q_STARTED_BY, STARTERS), (Q_FINISHED_BY, FINISHERS)):
        for qid, nid in table.items():
            q = quests.get(qid)
            if q is not None and not seq((q.get(field) or {}).get(1) or {}):
                q.setdefault(field, {})[1] = {1: nid}


def load_guides(root, tips=None):
    """Dungeon key -> set of quest ids from a Guidelime_DungeonQuests checkout, or {}. `tips`
    gets each quest's tips by stage (guides.tips), the first guide's first."""
    if not root:
        return {}
    names = os.listdir(root)
    out = {}
    for key, files in GDQ_FILES.items():
        for f in files:
            found = [n for n in names if re.match(r"^\d+(-\d+)?_" + re.escape(f) + r"\.lua$", n)]
            if len(found) != 1:
                print("no Guidelime_DungeonQuests guide for %s: %s" % (key, f))
                continue
            path = os.path.join(root, found[0])
            out.setdefault(key, set()).update(guides.quests(path))
            if tips is not None:
                for qid, by in guides.tips(path).items():
                    for stage, text in by.items():
                        tips.setdefault(qid, {}).setdefault(stage, text)
    return out


# Our language -> the game client's locale of QuestieDB's translations (Polish has no client).
GAME_LOCALES = {"de": "deDE", "es": "esES", "fr": "frFR", "pt": "ptBR", "ru": "ruRU", "zh": "zhCN"}


def game_objectives(root):
    """{lang: {quest: objective}}: the game's own text of each quest in that language, from
    QuestieDB's l10n lookups (the Forever ones, else the Classic ones)."""
    out = {}
    for lang, loc in GAME_LOCALES.items():
        for flavor in ("Forever", "Classic"):
            path = os.path.join(root, "l10n", flavor, "lookupQuests", loc + ".lua")
            if os.path.exists(path):
                break
        else:
            continue
        src = open(path, encoding="utf-8").read()
        m = re.search(r"loadstring\(\[(=*)\[\s*return\s*(.*?)\]\1\]", src, re.S)
        if not m:
            continue
        got = {}
        for qid, row in luadata.parse(m.group(2)).items():
            lines = row.get(2) if isinstance(row, dict) else None
            if isinstance(lines, dict):
                text = " ".join(v for _, v in sorted(lines.items()) if isinstance(v, str) and v.strip())
                if text:
                    got[qid] = text
        out[lang] = got
    return out


def write_translations(texts, tips, game=None):
    """Data_<lang>.lua: the objectives and the guide tips in each language. An objective is the
    game's own text where QuestieDB has it (`game`), else ours from tools/i18n. A file keeps only
    what is translated; the rest shows in English. Each file returns at once on a client of
    another language, so only one language stays in memory."""
    game = game or {}
    need = {}
    for qid, t in texts.items():
        if t:
            for lang in i18n.LANGS:
                if qid not in game.get(lang, {}):
                    need.setdefault(t, set()).add(lang)
    tr_text = i18n.sync("dungeonprep-objectives", {t: sorted(ls) for t, ls in need.items()})
    tr_tips = i18n.sync("dungeonprep-tips", [t for by in tips.values() for t in by.values()])
    for lang in i18n.LANGS:
        lines = [
            "-- Generated by tools/dungeonprep/build_data.py from tools/i18n. Do not edit.",
            "local _, ns = ...",
            "if ns.lang ~= %s then return end" % lua_str(lang),
            "local D = ns.Data",
            "D.L = { text = {}, tips = {} }",
            "local text, tips = D.L.text, D.L.tips",
        ]
        for qid in sorted(texts):
            v = game.get(lang, {}).get(qid) or (tr_text.get(texts[qid]) or {}).get(lang)
            if v and texts[qid]:
                lines.append("text[%d]=%s" % (qid, lua_str(v)))
        for qid in sorted(tips):
            parts = []
            for k in "tdh":
                v = (tr_tips.get(tips[qid].get(k)) or {}).get(lang)
                if v:
                    parts.append("%s=%s" % (k, lua_str(v)))
            if parts:
                lines.append("tips[%d]={%s}" % (qid, ",".join(parts)))
        out = os.path.join(os.path.dirname(OUT), "Data_%s.lua" % lang)
        with open(out, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(lines) + "\n")


def main(root, att_root=None, gdq_root=None):
    # The data files and the Forever corrections, where everything Forever added lives.
    quests, npcs, objects, items = questie.load_forever(root)
    quest_xp = load_xp(root)
    att_quests, att_links = load_att(att_root)
    add_att_links(quests, att_links)
    add_starters(quests)
    guide_tips = {}
    guide_quests = load_guides(gdq_root, guide_tips)
    att_side = {}
    for listed in att_quests.values():
        att_side.update(listed)

    area_to_key = {}
    for key, areas, _, _, _ in DUNGEONS:
        for a in areas:
            area_to_key[a] = key

    # A mob or object belongs to a dungeon when every place it spawns is inside it.
    def inside(zones):
        keys = {area_to_key.get(z) for z in zones}
        if len(keys) == 1 and None not in keys:
            return keys.pop()

    named = {n: k for k, ids in NPCS.items() for n in ids}

    def npc_key(nid):
        if nid in named:
            return named[nid]
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

    # The items that start a quest: its startedBy items, the items whose startQuest names it,
    # and its sourceItemId when no NPC or object gives it. An item without drops takes the drops
    # of the item of the same name that has them: the Forever data often lists the drop only
    # on one faction's copy (Krol'dok Moulding: Tunk drops 267138, the Horde quest names 267137).
    starts_of = {}
    for iid, it in items.items():
        if it.get(I_START_QUEST):
            starts_of.setdefault(it[I_START_QUEST], set()).add(iid)
    twins = {}
    for iid, it in items.items():
        if it.get(I_NAME) and (seq(it.get(I_NPC_DROPS) or {}) or seq(it.get(I_OBJECT_DROPS) or {})):
            twins.setdefault(it[I_NAME], []).append(iid)

    def start_items(qid, q):
        sb = q.get(Q_STARTED_BY) or {}
        ids = set(seq(sb.get(3) or {})) | starts_of.get(qid, set())
        if q.get(Q_SOURCE_ITEM) and not seq(sb.get(1) or {}) and not seq(sb.get(2) or {}):
            ids.add(q[Q_SOURCE_ITEM])
        out = set()
        for i in ids:
            it = items.get(i) or {}
            if seq(it.get(I_NPC_DROPS) or {}) or seq(it.get(I_OBJECT_DROPS) or {}):
                out.add(i)
            else:
                out.update(twins.get(it.get(I_NAME), [i]))
        return sorted(out)

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
        # Started by an item that drops there (Krol'dok Moulding from Tunk).
        keys.update(item_key(i) for i in start_items(qid, q))
        text = " ".join(t for t in seq(q.get(Q_TEXT) or {}) if isinstance(t, str))
        for k, words in WORDS.items():
            if qid >= 90000 and any(w in text for w in words):
                keys.add(k)
        for k, ids in QUESTS.items():
            if qid in ids:
                keys.add(k)
        keys.discard(None)
        for k in keys:
            lo, hi = ranges[k]
            # Cloth and leather turn-ins are level 60 everywhere; keep quests near the dungeon.
            if lo - 6 <= level <= hi + 4:
                by_dungeon[k].append(qid)
        # ATT lists the quest under the dungeon (checked in the game): it belongs there too.
        for k, listed in att_quests.items():
            if qid in listed and qid not in by_dungeon[k]:
                by_dungeon[k].append(qid)
        # A step of a levelling chain for the dungeon, also the ones outside it (the key quests).
        for k, listed in guide_quests.items():
            if qid in listed and qid not in by_dungeon[k]:
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
        for iid in seq(sb.get(3) or {}) or ([q[Q_SOURCE_ITEM]] if q.get(Q_SOURCE_ITEM) else []):
            return item_place(items.get(iid) or {})
        return "", 0, 0, 0

    def item_place(it):
        """An item that starts a quest is taken where it lies or drops: the object that holds it,
        else the mob that drops it and has the most spawns. Named "Item (Source)"."""
        name = it.get(I_NAME) or ""
        best, most = None, -1
        for key, recs, spawns, zkey, nkey in ((I_OBJECT_DROPS, objects, O_SPAWNS, O_ZONE, O_NAME),
                                              (I_NPC_DROPS, npcs, N_SPAWNS, N_ZONE, N_NAME)):
            for rid in seq(it.get(key) or {}):
                rec = recs.get(rid) or {}
                zs = sorted(zones_of(rec, spawns, zkey))
                zone = rec.get(zkey) or (zs[0] if zs else 0)
                x, y = spot(rec, spawns, zone)
                pts = rec.get(spawns) if isinstance(rec.get(spawns), dict) else {}
                n = sum(len(seq(v)) for v in pts.values())
                if zone and (x or y) and n > most:
                    best, most = (rec.get(nkey) or "", zone, x, y), n
            if best:
                break
        if not best:
            return name, 0, 0, 0
        return (name if best[0] in ("", name) else "%s (%s)" % (name, best[0]),) + best[1:]

    # "A" or "H" when the quest is for one faction only: from its race mask, else from the
    # NPCs that give and take it (QuestieDB leaves the race mask 0 on many such quests).
    ALLIANCE, HORDE = 1 + 4 + 8 + 64, 2 + 16 + 32 + 128

    def att_says(qid):
        """ATT's faction for a Forever quest, or None: QuestieDB's race masks are sometimes
        wrong there (Important Heirlooms is for both factions, QuestieDB says Alliance)."""
        if qid >= FOREVER_QUESTS and qid in att_side:
            return att_side[qid]

    def faction(q, qid=None):
        if qid is not None and att_says(qid) is not None:
            return att_says(qid)
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

    def finisher(q):
        fb = q.get(Q_FINISHED_BY) or {}
        for nid in seq(fb.get(1) or {}):
            n = npcs.get(nid) or {}
            zs = sorted(zones_of(n, N_SPAWNS, N_ZONE))
            zone = n.get(N_ZONE) or (zs[0] if zs else 0)
            return (n.get(N_NAME) or "", zone) + spot(n, N_SPAWNS, zone)
        for oid in seq(fb.get(2) or {}):
            o = objects.get(oid) or {}
            zs = sorted(zones_of(o, O_SPAWNS, O_ZONE))
            zone = o.get(O_ZONE) or (zs[0] if zs else 0)
            return (o.get(O_NAME) or "", zone) + spot(o, O_SPAWNS, zone)
        return "", 0, 0, 0

    rewards = {}
    for iid, it in items.items():
        for qid in seq(it.get(I_QUEST_REWARDS) or {}):
            rewards.setdefault(qid, []).append(iid)

    # The dungeon mobs a quest needs: kill targets and what drops its items, inside the dungeon.
    def targets(q, key):
        found = {}
        obj = q.get(Q_OBJECTIVES) or {}
        for o in seq(obj.get(1) or {}):
            if npc_key(o.get(1)) == key:
                found[o.get(1)] = True
        for o in seq(obj.get(3) or {}):
            it = items.get(o.get(1)) or {}
            drops = [n for n in seq(it.get(I_NPC_DROPS) or {}) if npc_key(n) == key]
            if 0 < len(drops) <= 2:
                for n in drops:
                    found[n] = True
        out = [(npcs.get(n) or {}) for n in found]
        out = [n for n in out if n.get(N_NAME)]
        out.sort(key=lambda n: (n.get(N_MAX_LEVEL) or 0, n.get(N_NAME)))
        return [n[N_NAME] for n in out][:4]

    # Where a dungeon quest happens: "t" when it is taken inside the dungeon, "d" when its
    # work is done there, "h" when it is handed in there. Taken or handed in inside: the NPC or
    # object stands in the dungeon (or, in the classic data, nowhere on a map: it shows up
    # during the run, as Celebras the Redeemed does), or the starting item drops there. Done
    # inside: a mob, object or item of its objectives is the dungeon's, or its objective names
    # the dungeon. When the data cannot tell, there is no flag: the mark is only ever a hint.
    names = {k: [n[4:] if n.startswith("The ") else n] + WORDS.get(k, []) for k, _, n, _, _ in DUNGEONS}
    areas_of = {k: a for k, a, _, _, _ in DUNGEONS}

    def stands_in(side, key, qid):
        for nid in seq(side.get(1) or {}):
            n = npcs.get(nid) or {}
            if npc_key(nid) == key:
                return True
            if qid < FOREVER_QUESTS and not zones_of(n, N_SPAWNS, N_ZONE) and not n.get(N_ZONE):
                return True
            return False
        for oid in seq(side.get(2) or {}):
            o = objects.get(oid) or {}
            if obj_key(oid) == key:
                return True
            return qid < FOREVER_QUESTS and not zones_of(o, O_SPAWNS, O_ZONE) and not o.get(O_ZONE)
        return False

    def inside_flags(qid, key):
        q = quests[qid]
        sb = q.get(Q_STARTED_BY) or {}
        flags = ""
        if stands_in(sb, key, qid) or (not seq(sb.get(1) or {}) and not seq(sb.get(2) or {})
                                       and any(item_key(i) == key for i in start_items(qid, q))):
            flags += "t"
        obj = q.get(Q_OBJECTIVES) or {}
        work = (any(npc_key(o.get(1)) == key for o in seq(obj.get(1) or {}))
                or any(obj_key(o.get(1)) == key for o in seq(obj.get(2) or {}))
                or any(item_key(o.get(1)) == key for o in seq(obj.get(3) or {})))
        text = objective(q)
        handed = stands_in(q.get(Q_FINISHED_BY) or {}, key, qid)
        # Without such an objective: a talk that starts and ends inside, or an escort from inside.
        if not work and flags:
            work = (handed and q.get(Q_ZONE) in areas_of[key]) or text.startswith("Escort ")
        if work or any(w in text for w in names[key]):
            flags += "d"
        if handed:
            flags += "h"
        return "".join(f for f in flags if f not in OUTSIDE_WORK.get(qid, ""))

    def pres(qid):
        q = quests.get(qid) or {}
        return seq(q.get(Q_PRE_GROUP) or {}) + seq(q.get(Q_PRE_SINGLE) or {})[:1]

    # The place of a quest in its chain: steps before it (the longest way back) and after it.
    after = {}
    for qid, q in quests.items():
        for p in pres(qid):
            after.setdefault(p, []).append(qid)

    def depth(qid, seen=()):
        if qid in seen or len(seen) > 30:
            return 0
        return max([1 + depth(p, seen + (qid,)) for p in pres(qid) if p in quests] or [0])

    def rest(qid, seen=()):
        if qid in seen or len(seen) > 30:
            return 0
        return max([1 + rest(n, seen + (qid,)) for n in after.get(qid, []) if n in quests] or [0])

    # The whole chain a quest is in, first step first: back along the longest way, then on
    # along the longest way of quests for the same faction.
    def chain(qid):
        side = faction(quests[qid], qid)
        path, cur = [qid], qid
        while len(path) < 15:
            back = [p for p in pres(cur) if p in quests and p not in path]
            if not back:
                break
            cur = max(back, key=lambda p: (depth(p), -p))
            path.insert(0, cur)
        cur = qid
        while len(path) < 15:
            nxt = [n for n in after.get(cur, []) if n not in path and faction(quests[n], n) in ("", side)]
            if not nxt:
                break
            cur = max(nxt, key=lambda n: (rest(n), -n))
            path.append(cur)
        return path if len(path) > 1 else []

    def objective(q):
        texts = [t for t in seq(q.get(Q_TEXT) or {}) if isinstance(t, str) and t.strip()]
        text = " ".join(texts).replace("\n", " ").strip()
        return text[:300]

    lines = [
        "-- Generated by tools/dungeonprep/build_data.py from QuestieDB (Forever data). Do not edit.",
        "-- Quest data (c) the Questie team and contributors, GPLv3.",
        "-- Dungeon quest lists checked against AllTheThings (MIT); levelling chains from",
        "-- Guidelime_DungeonQuests (https://github.com/JanRK/Guidelime_DungeonQuests, GPLv3).",
        "local _, ns = ...",
        "local D = {}",
        "ns.Data = D",
        "-- { key, area ids, English name, min level, max level }",
        "D.dungeons = {",
    ]
    for key, areas, name, lo, hi in sorted(DUNGEONS, key=lambda d: (d[3], d[4])):
        ea, ex, ey = ENTRANCES[key]
        lines.append("{%s,%s,%s,%d,%d,%d,%s,%s}," % (lua_str(key), lua_list(areas), lua_str(name), lo, hi,
                                                     ea, num(ex), num(ey)))
    lines.append("}")
    lines.append("-- (the last three: the entrance's area id and its spot on that zone's map)")
    lines.append("-- Dungeon -> quests.")
    lines.append("D.byDungeon = {")
    used = set()
    for key, *_ in DUNGEONS:
        ids = sorted(by_dungeon[key])
        used.update(ids)
        lines.append("%s=%s," % (key, lua_list(ids)))
    lines.append("}")
    lines.append("-- Dungeon -> the quests of its levelling chains (from Guidelime_DungeonQuests, GPLv3).")
    lines.append("D.main = {")
    for key, *_ in DUNGEONS:
        ids = sorted(q for q in by_dungeon[key]
                     if q in guide_quests.get(key, ()) or q in MAIN_EXTRA.get(key, ()))
        if ids:
            lines.append("%s=%s," % (key, lua_list(ids)))
    lines.append("}")
    lines.append("-- Quest -> { English name, level, required level, race mask, class mask,")
    lines.append("--   who starts it, the area id there, quests before it (all of them), quests before it (one of them),")
    lines.append("--   quests that close it, faction (A, H or \"\" for both), x, y on the zone map,")
    lines.append("--   who takes it back, the area id there, x, y, chain step, chain length }.")
    lines.append("D.quest = {")
    key_of = {}
    for key, *_ in DUNGEONS:
        for qid in by_dungeon[key]:
            key_of.setdefault(qid, key)
    for qid in sorted(used):
        q = quests[qid]
        who, area, x, y = starter(q)
        fwho, farea, fx, fy = finisher(q)
        before, later = depth(qid), rest(qid)
        lines.append("[%d]={%s,%d,%d,%d,%d,%s,%d,%s,%s,%s,%s,%s,%s,%s,%d,%s,%s,%d,%d}," % (
            qid, lua_str(q.get(Q_NAME)), q.get(Q_LEVEL) or 0, q.get(Q_REQ_LEVEL) or 0,
            0 if att_says(qid) == "" else q.get(Q_RACES) or 0,
            q.get(Q_CLASSES) or 0, lua_str(who), area or 0, lua_list(seq(q.get(Q_PRE_GROUP) or {})),
            lua_list(seq(q.get(Q_PRE_SINGLE) or {})), lua_list(seq(q.get(Q_EXCLUSIVE) or {})),
            lua_str(faction(q, qid)), num(x), num(y), lua_str(fwho), farea or 0, num(fx), num(fy),
            before + 1 if before + later else 0, before + later + 1 if before + later else 0))
    lines.append("}")
    # Quests before the dungeon quests that are not dungeon quests themselves, for their names.
    chains = {qid: chain(qid) for qid in used}
    others = set()
    for qid in used:
        for p in pres(qid) + chains[qid]:
            if p not in used and p in quests:
                others.add(p)
    lines.append("-- Other quests of a chain: quest -> { English name, level, who starts it, the area id there, x, y }.")
    lines.append("D.pre = {")
    for qid in sorted(others):
        q = quests[qid]
        who, area, x, y = starter(q)
        lines.append("[%d]={%s,%d,%s,%d,%s,%s}," % (qid, lua_str(q.get(Q_NAME)), q.get(Q_LEVEL) or 0, lua_str(who),
                                                    area or 0, num(x), num(y)))
    lines.append("}")
    lines.append("-- Quest -> its whole chain, first step first (dungeon quests and D.pre quests).")
    lines.append("D.chain = {")
    for qid in sorted(used):
        if chains[qid]:
            lines.append("[%d]=%s," % (qid, lua_list(chains[qid])))
    lines.append("}")
    lines.append("-- Quest -> its objective in English (the game's own text replaces it while it is in the log).")
    lines.append("D.text = {")
    for qid in sorted(used):
        t = objective(quests[qid])
        if t:
            lines.append("[%d]=%s," % (qid, lua_str(t)))
    lines.append("}")
    lines.append("-- Quest -> the items it rewards (both the ones it gives and the ones to choose from).")
    lines.append("D.reward = {")
    for qid in sorted(used):
        if rewards.get(qid):
            lines.append("[%d]=%s," % (qid, lua_list(sorted(rewards[qid]))))
    lines.append("}")
    lines.append("-- Quest -> the experience it gives at its own level (less for a character far above it).")
    lines.append("D.xp = {")
    for qid in sorted(used):
        if qid in quest_xp and quest_xp[qid][1] > 0:
            lines.append("[%d]=%d," % (qid, quest_xp[qid][1]))
    lines.append("}")
    lines.append("-- Dungeon -> quest -> what of it happens inside the dungeon: t taken, d done, h handed in.")
    lines.append("D.inside = {")
    for key, *_ in DUNGEONS:
        parts = ["[%d]=%s" % (qid, lua_str(f)) for qid in sorted(by_dungeon[key])
                 for f in [inside_flags(qid, key)] if f]
        if parts:
            lines.append("%s={%s}," % (key, ",".join(parts)))
    lines.append("}")
    lines.append("-- Quest -> the dungeon mobs it needs, lowest level first (a rough boss order).")
    lines.append("D.target = {")
    for qid in sorted(used):
        t = targets(quests[qid], key_of[qid])
        if t:
            lines.append("[%d]={%s}," % (qid, ",".join(lua_str(n) for n in t)))
    lines.append("}")
    lines.append("-- Quest -> its quest items: { item id, English name }, for the objective rows before")
    lines.append("--   the quest is in the log (the game gives the counts then).")
    lines.append("D.goal = {")
    for qid in sorted(used):
        obj = quests[qid].get(Q_OBJECTIVES) or {}
        goal = [(o.get(1), (items.get(o.get(1)) or {}).get(I_NAME)) for o in seq(obj.get(3) or {})]
        goal = [(i, n) for i, n in goal if i and n][:4]
        if goal:
            lines.append("[%d]={%s}," % (qid, ",".join("{%d,%s}" % (i, lua_str(n)) for i, n in goal)))
    lines.append("}")
    lines.append("-- Quest -> tips from its Guidelime_DungeonQuests guide (GPLv3), in English:")
    lines.append("--   t taking it, d its work, h handing it in.")
    lines.append("D.tips = {")
    for qid in sorted(used):
        by = guide_tips.get(qid)
        if by:
            lines.append("[%d]={%s}," % (qid, ",".join("%s=%s" % (k, lua_str(by[k])) for k in "tdh" if k in by)))
    lines.append("}")
    lines.append("-- Area ids on Kalimdor; the rest are in the Eastern Kingdoms.")
    lines.append("D.kalimdor = %s" % lua_list(KALIMDOR))
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    write_translations({qid: objective(quests[qid]) for qid in used},
                       {qid: guide_tips[qid] for qid in used if qid in guide_tips}, game_objectives(root))
    print(", ".join("%s %d" % (k, len(by_dungeon[k])) for k, *_ in DUNGEONS))
    print("quests %d, %d bytes; left out %d repeatable or exchange quests" % (
        len(used), os.path.getsize(OUT), len(dropped)))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".", sys.argv[2] if len(sys.argv) > 2 else None,
         sys.argv[3] if len(sys.argv) > 3 else None)
