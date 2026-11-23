#!/usr/bin/env python3
"""Builds Gulli-MyBisList/Data.lua from the wowtbc.gg snapshot (tools/bislist/wowtbc.json).

The snapshot is the WoW Forever BiS lists of wowtbc.gg: for each of the 28 specs the lists by
level (20, 30, 40, 50) and the pre-raid ones (best and realistic), with the items they name.
fetch.py collects it again; this script only reads it.

    python3 tools/bislist/build_data.py [snapshot] [out] [questiedb]

With a QuestieDB checkout as the third argument, the ids of the set pieces the snapshot does not
name (the site lists a set's pieces by name, and knows only the items of its lists) are looked up
in the Forever item data and kept in tools/bislist/set-items.json for a run without it.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SNAP = os.path.join(ROOT, "tools", "bislist", "wowtbc.json")
OUT = os.path.join(ROOT, "Gulli-MyBisList", "Data.lua")
SET_ITEMS = os.path.join(ROOT, "tools", "bislist", "set-items.json")

CLASS_ORDER = ["WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"]
TANKS = {"feral tank", "protection"}
HEALERS = {"restoration", "holy", "discipline"}
# Our stage keys and the site's list names.
STAGES = [("L20", "20"), ("L30", "30"), ("L40", "40"), ("L50", "50"), ("PRE", "pre-raid"),
          ("REAL", "pre-raid-realistic")]
SLOTS = ["head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet",
         "finger1", "finger2", "trinket1", "trinket2", "main", "off", "ranged"]
# The site's slot names of the pre-raid lists.
PRE_SLOT = {"finger 1": "finger1", "finger 2": "finger2", "trinket 1": "trinket1", "trinket 2": "trinket2",
            "weapon": "main", "off hand": "off"}
KEEP = 5  # items per slot (owner's decision of 2026-11-21)
# Item slot codes in the data (the game's equip location, short).
ITEM_SLOT = {"head": "head", "neck": "neck", "shoulder": "shoulder", "back": "back", "chest": "chest",
             "wrist": "wrist", "hands": "hands", "waist": "waist", "legs": "legs", "feet": "feet",
             "finger": "finger", "trinket": "trinket", "two-hand": "2h", "main hand": "mh", "one-hand": "1h",
             "off hand": "oh", "held in off-hand": "held", "ranged": "ranged", "relic": "relic", "thrown": "ranged"}
QUALITY = {"uncommon": 2, "rare": 3, "epic": 4}

# The dungeons of Dungeon Journal, by the site's name.
DUNGEON = {
    "Ragefire Chasm": "RFC", "Wailing Caverns": "WC", "The Deadmines": "DM", "Shadowfang Keep": "SFK",
    "Ruins of Lordaeron / Shadowfang Keep": "SFK", "Blackfathom Deeps": "BFD", "The Stockade": "STOCKS",
    "Gnomeregan": "GNOMER", "Razorfen Kraul": "RFK", "Razorfen Downs": "RFD", "Uldaman": "ULDA",
    "Zul'Farrak": "ZF", "Maraudon": "MARA", "The Temple of Atal'Hakkar": "ST", "Blackrock Depths": "BRD",
    "Blackrock Spire": "BRS", "Blackrock Spire: Upper": "BRS", "Blackrock Spire: Lower": "BRS",
    "Dire Maul": "DIREMAUL", "Dire Maul: West": "DIREMAUL", "Dire Maul: East": "DIREMAUL",
    "Dire Maul: North": "DIREMAUL", "Scholomance": "SCHOLO", "Stratholme": "STRAT",
    "Scarlet Monastery": "SM", "Scarlet Monastery: Cathedral": "SM", "Scarlet Monastery: Graveyard": "SM",
    "Scarlet Monastery: Library": "SM", "Scarlet Monastery: Armory": "SM", "Hall of Thanes": "THANES",
    "Ruins of Lordaeron": "LORDAERON", "Excavation Site: Wetlands": "EXCAVATION", "City of Dalaran": "DALARAN",
    "The Drowned City": "DROWNED", "Krol'dok Stronghold": "KROLDOK", "Alcaz Prison": "ALCAZ",
    "Blackmaw Hold": "BLACKMAW", "Shaper's Terrace": "SHAPERS",
}
ALLIANCE_REP = {"The League of Arathor", "Stormpike Guard", "Silverwing Sentinels", "Theramore Expeditionary Force"}
HORDE_REP = {"Warsong Outriders", "Frostwolf Clan", "The Defilers", "Darkspear Raiders"}
# PvP ranks in item names.
ALLIANCE_PVP = ("Knight-", "Marshal", "Lieutenant Commander", "Commander's", "Sergeant Major")
HORDE_PVP = ("Warlord", "Legionnaire", "General's", "Champion's", "Centurion", "Blood Guard", "Stone Guard")


# Item sets. The site names each set's pieces and the piece counts of its bonuses; the class, the
# tier and the pairs come from here, the bonus texts and the names from the game.
T0 = {"Battlegear of Valor": "WARRIOR", "Lightforge Armor": "PALADIN", "Beaststalker Armor": "HUNTER",
      "Shadowcraft Armor": "ROGUE", "Vestments of the Devout": "PRIEST", "The Elements": "SHAMAN",
      "Magister's Regalia": "MAGE", "Dreadmist Raiment": "WARLOCK", "Wildheart Raiment": "DRUID"}
# Tier 0.5 -> the tier 0 set it is made from.
T05 = {"Battlegear of Heroism": "Battlegear of Valor", "Soulforge Armor": "Lightforge Armor",
       "Beastmaster Armor": "Beaststalker Armor", "Darkmantle Armor": "Shadowcraft Armor",
       "Vestments of the Virtuous": "Vestments of the Devout", "The Five Thunders": "The Elements",
       "Sorcerer's Regalia": "Magister's Regalia", "Deathmist Raiment": "Dreadmist Raiment",
       "Feralheart Raiment": "Wildheart Raiment"}
# The quests of the tier 0.5 chain that give the pieces, in the chain's order.
SET_STEPS = ["An Earnest Proposition", "Just Compensation", "Anthion's Parting Words", "Saving the Best for Last"]
# PvP sets: the rank in front, then the word that names the class.
PVP_RANKS = {"Champion's": "H", "Warlord's": "H", "Lieutenant Commander's": "A", "Field Marshal's": "A"}
PVP_CLASS = {"Battlegear": "WARRIOR", "Threads": "WARLOCK", "Pursuit": "HUNTER", "Sanctuary": "DRUID",
             "Earthshaker": "SHAMAN", "Regalia": "MAGE", "Raiment": "PRIEST", "Vestments": "ROGUE",
             "Aegis": "PALADIN", "Investiture": "PRIEST", "Wildhide": "DRUID", "Vindication": "PALADIN",
             "Wartide": "SHAMAN", "Thunderfist": "SHAMAN"}
# Other sets of one class (Zul'Gurub, Ahn'Qiraj).
CLASS_SETS = {"Predator's Armor": "HUNTER", "Demoniac's Threads": "WARLOCK", "Illusionist's Attire": "MAGE",
              "Doomcaller's Malevolence": "WARLOCK"}
SET_KINDS = ["t0", "t05", "pvp", "class", "any"]
ARMOR_SUB = {1: "cloth", 2: "leather", 3: "mail", 4: "plate"}
ARMOR_RANK = {"": 0, "cloth": 1, "leather": 2, "mail": 3, "plate": 4}


def set_kind(name):
    """The kind of a set, its class and its faction: ("pvp", "MAGE", "H")."""
    if name in T0:
        return "t0", T0[name], None
    if name in T05:
        return "t05", T0[T05[name]], None
    for rank, side in PVP_RANKS.items():
        if name.startswith(rank + " "):
            cls = PVP_CLASS.get(name[len(rank) + 1:])
            if cls:
                return "pvp", cls, side
    if name in CLASS_SETS:
        return "class", CLASS_SETS[name], None
    return "any", None, None


def lookup_set_items(snap, root):
    """The ids of the set pieces the snapshot does not name, from the QuestieDB Forever items:
    name -> [id, armour type]. Of several items with one name, the one with the highest level."""
    sys.path.insert(0, os.path.join(ROOT, "tools", "questcleaner"))
    import questie
    items = questie.load_forever(root)[3]
    by_name = {}
    for iid, it in items.items():
        if it.get(1):
            by_name.setdefault(it[1], []).append(iid)
    known = {v[0] for v in snap["items"].values()}
    out = {}
    for s in snap.get("sets") or []:
        for piece in s[2]:
            ids = by_name.get(piece)
            if piece in known or not ids:
                continue
            best = max(ids, key=lambda i: (items[i].get(10) or 0, i))
            it = items[best]
            out[piece] = [best, ARMOR_SUB.get(it.get(13), "") if it.get(12) == 4 else ""]
    return out


def build_sets(snap, extra):
    """The sets for the window: one per name (the site keeps the Classic set beside the one WoW
    Forever changed; the newer id is Forever's), pieces as item ids. Returns the rows, the snapshot
    items among the pieces, the names of the other pieces and each tier 0.5 piece's chain step."""
    by_name = {}
    for iid, v in snap["items"].items():
        by_name.setdefault(v[0], []).append(int(iid))
    newest = {}
    for s in snap.get("sets") or []:
        if s[1] not in newest or s[0] > newest[s[1]][0]:
            newest[s[1]] = s
    ids_of = {}
    rows, listed, names, steps = [], set(), {}, {}
    for name, s in newest.items():
        kind, cls, side = set_kind(name)
        pieces, armor, sides = [], "", set()
        for piece in s[2]:
            found = sorted(by_name.get(piece) or [])
            if found:
                for iid in found[-1:]:
                    v = snap["items"][str(iid)]
                    pieces.append(iid)
                    listed.add(iid)
                    if ARMOR_RANK.get(v[2] or "", 0) > ARMOR_RANK[armor]:
                        armor = v[2]
                    sides.add(faction(v[0], v[7] or "", v[8] or ""))
                    if kind == "t05" and v[7] in SET_STEPS:
                        steps[iid] = SET_STEPS.index(v[7]) + 1
            elif piece in extra:
                iid, sub = extra[piece]
                pieces.append(iid)
                names[iid] = piece
                if ARMOR_RANK.get(sub, 0) > ARMOR_RANK[armor]:
                    armor = sub
        if len(pieces) < 2:
            continue  # a set whose pieces nobody knows
        if side is None and len(sides) == 1:
            side = sides.pop()
        ids_of[name] = s[0]
        rows.append([s[0], name, kind, cls or False, armor, side or False, T05.get(name) or False, pieces, s[3]])
    for r in rows:
        r[6] = ids_of.get(r[6]) or False
    rows.sort(key=lambda r: (SET_KINDS.index(r[2]), CLASS_ORDER.index(r[3]) if r[3] else 99, r[0]))
    return rows, listed, names, steps


def enchant_kind(name):
    """Who makes an enchant, from its English name: ench (an enchanter), kit (a leatherworker's
    armor kit), scope (an engineer), arcanum (a libram quest), else other."""
    if name.startswith("Enchant "):
        return "ench"
    if name.endswith("Armor Kit"):
        return "kit"
    if "Scope" in name:
        return "scope"
    if "Arcanum" in name:
        return "arcanum"
    return "other"


def spec_key(info):
    return info["class"].upper() + "_" + info["spec"].replace(" ", "").upper()


def role(spec):
    if spec in TANKS:
        return "tank"
    if spec in HEALERS:
        return "heal"
    return "dps"


def faction(name, source, kind):
    """A for Alliance, H for Horde, None for both."""
    if "Alliance" in kind:
        return "A"
    if "Horde" in kind:
        return "H"
    if kind == "Reputation":
        f = source.split(" - ")[0]
        if f in ALLIANCE_REP:
            return "A"
        if f in HORDE_REP:
            return "H"
    if kind == "Honor Vendor":
        if any(w in name for w in ALLIANCE_PVP):
            return "A"
        if any(w in name for w in HORDE_PVP):
            return "H"
    return None


def source(name, src, kind):
    """The kind of source and its two texts: ("boss", boss, dungeon key) and the like."""
    if kind == "Crafted":
        return ("craft", src, "")
    if kind == "Reputation":
        f, _, st = src.partition(" - ")
        return ("rep", f, st)
    if kind == "Honor Vendor":
        return ("pvp", "", "")
    if kind.startswith("Quest"):
        return ("quest", src, "")
    if kind == "Vendor":
        return ("vendor", "" if src.startswith("Multiple") else src, "")
    if "Undermine Real" in kind:
        return ("vendor", src, kind)
    if kind == "Fishing":
        return ("fish", "", "")
    if kind in DUNGEON:
        return ("boss", "" if src.startswith("Multiple") or src == "Trash drop" else src, DUNGEON[kind])
    if kind == "Dungeons":
        return ("boss", "", "")
    if "Rare Spawn" in kind:
        return ("rare", src, kind.split(" (")[0] if not kind.startswith("Rare Spawn") else "")
    if kind.startswith("World Boss"):
        return ("rare", src, "")
    if src == "World drop":
        return ("world", "", "")
    if kind == "":
        return ("unknown", "", "")
    if kind == "Comprehend Scroll":
        return ("other", src, "")
    # a zone's ordinary mobs ("Trash drop", Azshara) or a named mob there
    return ("zone", "" if src == "Trash drop" else src, kind)


def lua(v):
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, (list, tuple)):
        return "{" + ",".join(lua(x) for x in v) + "}"
    raise TypeError(v)


def split_pair(ids):
    """A level list names rings and trinkets once: ranks 1, 3, 5... for the first, 2, 4, 6... for the second."""
    return ids[0::2][:KEEP], ids[1::2][:KEEP]


def stage_lists(info, items):
    lists = {}
    pre = info["lists"].get("pre-raid", {})
    pre_main = pre.get("weapon", [None])[0]
    two_hand = pre_main is not None and items.get(str(pre_main), [None, None])[1] == "two-hand"
    for key, site in STAGES:
        src = info["lists"].get(site)
        if not src:
            continue
        out = {}
        if site.startswith("pre-raid"):
            for slot, ids in src.items():
                out[PRE_SLOT.get(slot, slot)] = ids[:KEEP]
        else:
            for slot, ids in src.items():
                if slot in ("finger", "trinket"):
                    out[slot + "1"], out[slot + "2"] = split_pair(ids)
                elif slot in ("neck", "head", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs",
                              "feet", "ranged"):
                    out[slot] = ids[:KEEP]
            # a spec that fights with a two-hander takes the two-hand list as its weapon
            if two_hand and src.get("two-hand"):
                out["main"] = src["two-hand"][:KEEP]
            else:
                if src.get("main-hand"):
                    out["main"] = src["main-hand"][:KEEP]
                if src.get("off-hand"):
                    out["off"] = src["off-hand"][:KEEP]
        lists[key] = {s: [i for i in out[s] if str(i) in items] for s in SLOTS if out.get(s)}
    return lists


def build(snap, extra=None):
    items = snap["items"]
    set_rows, set_listed, set_names, set_steps = build_sets(snap, extra or {})
    specs = []
    for slug, info in snap["specs"].items():
        specs.append((CLASS_ORDER.index(info["class"].upper()), slug, info))
    specs.sort(key=lambda x: (x[0], x[1]))

    used = set()
    srcs, src_index = [], {}
    out = ["-- Generated by tools/bislist/build_data.py from the wowtbc.gg snapshot "
           "(tools/bislist/wowtbc.json). Do not edit.",
           "-- The lists are the work of wowtbc.gg (https://wowtbc.gg/warcraftforever/).",
           "local _, ns = ...", "local D = {}", "ns.Data = D", "",
           "D.ver = " + lua(snap.get("fetched", "")),
           "D.stages = " + lua([k for k, _ in STAGES]),
           "D.slots = " + lua(SLOTS), "",
           "-- Specs: { key, class, role, site page, simulated }.",
           "D.specs = {"]
    for _, slug, info in specs:
        out.append("  " + lua([spec_key(info), info["class"].upper(), role(info["spec"]), slug,
                               bool(info.get("simmed"))]) + ",")
    out += ["}", "", "-- Lists: spec -> stage -> slot -> item ids, best first.", "D.lists = {"]
    for _, slug, info in specs:
        lists = stage_lists(info, items)
        out.append("  " + spec_key(info) + " = {")
        for key, _ in STAGES:
            if key not in lists:
                continue
            parts = []
            for s in SLOTS:
                if s in lists[key]:
                    used.update(lists[key][s])
                    parts.append(s + "=" + lua(lists[key][s]))
            out.append("    " + key + " = {" + ",".join(parts) + "},")
        out.append("  },")
    out += ["}", "", "-- Enchants of the pre-raid lists: spec -> stage -> slot -> { spell id, English name, kind }.",
            "D.ench = {"]
    for _, slug, info in specs:
        parts = []
        for key, site in (("PRE", "pre-raid"), ("REAL", "pre-raid-realistic")):
            e = info.get("enchants", {}).get(site) or {}
            if e:
                parts.append(key + "={" + ",".join(
                    PRE_SLOT.get(s, s) + "=" + lua([v[0], v[1], enchant_kind(v[1])]) for s, v in sorted(e.items())) + "}")
        if parts:
            out.append("  " + spec_key(info) + " = {" + ",".join(parts) + "},")
    out += ["}", ""]

    used.update(set_listed)
    out += ["-- Item sets: { id, English name, kind, class, armour, faction (A/H), the set it is made from,",
            "-- piece ids, the piece counts of its bonuses }. Kinds: " + ", ".join(SET_KINDS) + ".",
            "D.sets = {"]
    out += ["  " + lua(r) + "," for r in set_rows]
    out += ["}", "", "-- The quests of the tier 0.5 chain that give pieces, and each piece's quest.",
            "D.setSteps = " + lua(SET_STEPS),
            "D.setStep = {" + ",".join("[%d]=%d" % kv for kv in sorted(set_steps.items())) + "}", "",
            "-- English names of the set pieces that are on no list.",
            "D.names = {" + ",".join("[%d]=%s" % (k, lua(v)) for k, v in sorted(set_names.items())) + "}", ""]

    rows = []
    for iid in sorted(used):
        v = items[str(iid)]
        name, slot, _type, rarity, ilvl, minlvl, _bind, src, kind = v
        s = source(name, src or "", kind or "")
        if s not in src_index:
            src_index[s] = len(srcs) + 1
            srcs.append(s)
        rows.append("[" + str(iid) + "]=" + lua([ITEM_SLOT.get(slot, slot), QUALITY.get(rarity, 2), ilvl or 0,
                                                minlvl or 0, src_index[s], faction(name, src or "", kind or ""),
                                                name, _type or ""]))
    out += ["-- Sources: { kind, what, where } (boss + dungeon key, quest, rep + standing, craft + profession...).",
            "D.src = {"]
    out += ["  " + lua(list(s)) + "," for s in srcs]
    names = {}
    for name, key in DUNGEON.items():
        if " / " not in name and ":" not in name and key not in names:
            names[key] = name
    names["SM"], names["BRS"], names["DIREMAUL"] = "Scarlet Monastery", "Blackrock Spire", "Dire Maul"
    out += ["}", "", "-- Dungeon Journal keys -> English name, for a client without Dungeon Journal.",
            "D.dungeons = {" + ",".join(k + "=" + lua(v) for k, v in sorted(names.items())) + "}"]
    out += ["", "-- Items: id -> { slot, quality, item level, required level, source, faction (A/H), English name, type }.",
            "D.item = {"]
    out += rows
    out[-len(rows):] = [r + "," for r in out[-len(rows):]]
    out += ["}", ""]
    return "\n".join(out)


def main():
    snap = sys.argv[1] if len(sys.argv) > 1 else SNAP
    dest = sys.argv[2] if len(sys.argv) > 2 else OUT
    with open(snap, encoding="utf-8") as f:
        data = json.load(f)
    if len(sys.argv) > 3:
        with open(SET_ITEMS, "w", encoding="utf-8") as f:
            json.dump(lookup_set_items(data, sys.argv[3]), f, ensure_ascii=False, indent=0, sort_keys=True)
            f.write("\n")
    extra = {}
    if os.path.exists(SET_ITEMS):
        with open(SET_ITEMS, encoding="utf-8") as f:
            extra = json.load(f)
    text = build(data, extra)
    with open(dest, "w", encoding="utf-8") as f:
        f.write(text)
    print("wrote", dest, len(text) // 1024, "KB")


if __name__ == "__main__":
    main()
