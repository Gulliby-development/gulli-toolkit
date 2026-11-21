"""Reads the quests of a dungeon from AllTheThings' WoW Forever data (MIT licence,
https://github.com/ATTWoWAddon/AllTheThings, `.contrib/.db/forever/dungeons & raids/<name>.lua`).

ATT lists every quest of an instance under it, checked in the game, with the races that can
take it (`races = ALLIANCE_ONLY` on the quest or on a header above it). QuestieDB ties quests
to a dungeon only through their mobs, objects and drops, and its race masks are sometimes
wrong for WoW Forever's own quests, so the generator takes both.

    quests(path) -> {quest id: "A" | "H" | ""}

ATT also lists an instance's NPCs in the order a group meets them, under a header for each wing,
and the drops of its ordinary mobs under ZONE_DROPS: the journal takes the order from there.

    walk(path) -> {"order": [[npc id, wing key or ""]], "zone": [item id],
                   "names": {npc id: name}, "loot": {npc id: [item id]}}

ATT also says what comes before a quest (`sourceQuest`, `sourceQuests`), which quests stand
for each other (`altQuests`: one of them, such as a faction's copy) and the level it opens at:

    links(path) -> {quest id: {"pre": [quest id], "alt": [quest id], "lvl": level or 0}}

`names` comes from the comment after each NPC id, `loot` from the items listed under each boss
(an encounter's creatureID, or an n(<npc id>) of its own): the journal falls back to them where
the Wowhead snapshot has no NPC of the instance.

The file is Lua, read as text: never run.
"""
import re

ALLIANCE = {"HUMAN", "DWARF", "NIGHTELF", "GNOME", "DRAENEI", "WORGEN"}
HORDE = {"ORC", "UNDEAD", "SCOURGE", "TAUREN", "TROLL", "BLOODELF", "GOBLIN"}

TOKEN = re.compile(r'--\[(=*)\[.*?\]\1\]|--[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|'
                   r'\[(=*)\[.*?\]\2\]|[A-Za-z_][A-Za-z_0-9.]*|\d+|[(){}=,]', re.S)


def side(value):
    """"A", "H" or "" for a races value: a constant or a list of race constants."""
    names = set(re.findall(r"[A-Z_]+", value))
    if any(n.startswith("ALLIANCE") for n in names) or (names and names <= ALLIANCE):
        return "A"
    if any(n.startswith("HORDE") for n in names) or (names and names <= HORDE):
        return "H"
    return ""


def quests(path):
    text = open(path, encoding="utf-8").read()
    toks = [m.group(0) for m in TOKEN.finditer(text) if not m.group(0).startswith("--")]
    # A frame per open bracket: its parent, the races set directly in it, the quest it opens.
    frames = [{"parent": None, "races": None, "quest": None}]
    stack = [0]
    found = []
    i = 0
    while i < len(toks):
        t = toks[i]
        if t in "({":
            quest = None
            if t == "(" and i > 0 and toks[i - 1] == "q" and i + 1 < len(toks) and toks[i + 1].isdigit():
                quest = int(toks[i + 1])
            frames.append({"parent": stack[-1], "races": None, "quest": quest})
            # allianceQuestData = q(...), hordeQuestData = q(...): one faction's copy.
            if quest and i >= 3 and toks[i - 2] == "=":
                if toks[i - 3] == "allianceQuestData":
                    frames[-1]["races"] = "ALLIANCE_ONLY"
                elif toks[i - 3] == "hordeQuestData":
                    frames[-1]["races"] = "HORDE_ONLY"
            stack.append(len(frames) - 1)
            if quest:
                found.append(len(frames) - 1)
        elif t in ")}":
            if len(stack) > 1:
                stack.pop()
        elif t == "races" and i + 1 < len(toks) and toks[i + 1] == "=":
            value, j = [], i + 2
            if j < len(toks) and toks[j] == "{":
                depth = 0
                while j < len(toks):
                    value.append(toks[j])
                    depth += {"{": 1, "}": -1}.get(toks[j], 0)
                    j += 1
                    if depth == 0:
                        break
            elif j < len(toks):
                value.append(toks[j])
                j += 1
            frames[stack[-1]]["races"] = " ".join(value)
            i = j
            continue
        i += 1
    out = {}
    for f in found:
        qid = frames[f]["quest"]
        # The quest's own options table is the first frame opened inside its q( ... ).
        own = next((k for k in range(f + 1, len(frames)) if frames[k]["parent"] == f), None)
        races = frames[own]["races"] if own is not None else None
        if races is None:
            races = frames[f]["races"]
        p = frames[f]["parent"]
        while races is None and p is not None:
            races = frames[p]["races"]
            p = frames[p]["parent"]
        out.setdefault(qid, side(races or ""))
    return out


def links(path):
    text = open(path, encoding="utf-8").read()
    toks = [m.group(0) for m in TOKEN.finditer(text) if not m.group(0).startswith("--")]
    out = {}
    # A frame per open bracket; a quest's options table is the "{" right after q(<id>,.
    stack = []
    i = 0
    while i < len(toks):
        t = toks[i]
        if t in "({":
            quest = None
            if (t == "{" and i >= 4 and toks[i - 1] == "," and toks[i - 2].isdigit()
                    and toks[i - 3] == "(" and toks[i - 4] == "q"):
                quest = int(toks[i - 2])
                out.setdefault(quest, {"pre": [], "alt": [], "lvl": 0})
            stack.append(quest)
        elif t in ")}":
            if stack:
                stack.pop()
        elif (t in ("sourceQuest", "sourceQuests", "altQuests", "lvl") and stack and stack[-1]
              and i + 1 < len(toks) and toks[i + 1] == "="):
            ids, j = [], i + 2
            if j < len(toks) and toks[j] == "{":
                j += 1
                while j < len(toks) and toks[j] != "}":
                    if toks[j].isdigit():
                        ids.append(int(toks[j]))
                    j += 1
                j += 1
            elif j < len(toks) and toks[j].isdigit():
                ids.append(int(toks[j]))
                j += 1
            entry = out[stack[-1]]
            if t == "lvl":
                entry["lvl"] = ids[0] if ids else 0
            else:
                entry["alt" if t == "altQuests" else "pre"] += ids
            i = j
            continue
        i += 1
    return out


# ATT's headers for the wings of an instance -> our wing key (a WING_<KEY> text in the addon).
WINGS = {
    "SCARLET_MONASTERY_GRAVEYARD_HEADER": "GRAVEYARD", "SCARLET_MONASTERY_LIBRARY_HEADER": "LIBRARY",
    "SCARLET_MONASTERY_ARMORY_HEADER": "ARMORY", "SCARLET_MONASTERY_CATHEDRAL_HEADER": "CATHEDRAL",
    "LOWER_BLACKROCK_SPIRE": "LOWER", "UPPER_BLACKROCK_SPIRE": "UPPER",
    "WARPWOOD_QUARTER": "EAST", "CAPITAL_GARDENS": "WEST", "GORDOK_COMMONS": "NORTH",
    "MAIN_GATE": "MAIN", "SERVICE_ENTRANCE": "SERVICE",
}
# Sections whose NPCs are not met on the way (quest givers, vendors, ...).
ASIDE = {"QUESTS", "VENDORS", "FACTIONS", "ACHIEVEMENTS", "REWARDS", "PROFESSIONS", "TREASURES",
         "SPECIAL", "ZONE_DROPS", "COMMON_BOSS_DROPS"}


def walk(path):
    text = open(path, encoding="utf-8").read()
    toks = [m.group(0) for m in TOKEN.finditer(text) if not m.group(0).startswith("--")]
    # A frame per open bracket: what opened it (a call's name and first arguments, or "{").
    stack = [{"fn": "", "args": []}]
    order, zone, seen = [], [], set()
    loot = {}

    def wing():
        for f in reversed(stack):
            for a in f["args"]:
                if a in WINGS:
                    return WINGS[a]
        return ""

    def aside():
        return any(f["fn"] == "n" and f["args"] and f["args"][0] in ASIDE for f in stack)

    def add(npc):
        if npc not in seen:
            seen.add(npc)
            order.append([npc, wing()])

    i = 0
    while i < len(toks):
        t = toks[i]
        if t == "(":
            fn = toks[i - 1] if i > 0 and re.match(r"[A-Za-z_]", toks[i - 1]) else ""
            args, j = [], i + 1
            while j < len(toks) and toks[j] not in "({)}" and len(args) < 4:
                if toks[j] != ",":
                    args.append(toks[j])
                j += 1
            stack.append({"fn": fn, "args": args})
            first = args[0] if args else ""
            if fn == "n" and first.isdigit() and not aside():
                add(int(first))
                stack[-1]["owner"] = int(first)
            elif fn == "i" and first.isdigit() and not aside():
                owner = next((f["owner"] for f in reversed(stack[:-1]) if "owner" in f), None)
                if owner and int(first) not in loot.setdefault(owner, []):
                    loot[owner].append(int(first))
            elif fn == "i" and first.isdigit():
                # A drop of the ordinary mobs: straight under ZONE_DROPS, not inside an NPC there.
                calls = [f for f in stack[:-1] if f["fn"] in ("n", "e", "i")]
                if calls and calls[-1]["fn"] == "n" and calls[-1]["args"][:1] == ["ZONE_DROPS"]:
                    if int(first) not in zone:
                        zone.append(int(first))
        elif t == "{":
            stack.append({"fn": "{", "args": []})
        elif t in ")}":
            if len(stack) > 1:
                stack.pop()
        elif t in ("creatureID", "crs") and i + 1 < len(toks) and toks[i + 1] == "=":
            # The creatures of an encounter: keys of the table that e( ... ) opens.
            if len(stack) >= 2 and stack[-1]["fn"] == "{" and stack[-2]["fn"] == "e" and not aside():
                j = i + 2
                if toks[j] == "{":
                    j += 1
                    while j < len(toks) and toks[j] != "}":
                        if toks[j].isdigit():
                            add(int(toks[j]))
                            stack[-2].setdefault("owner", int(toks[j]))
                        j += 1
                elif toks[j].isdigit():
                    add(int(toks[j]))
                    stack[-2].setdefault("owner", int(toks[j]))
        i += 1
    wanted = {npc for npc, _ in order}
    names = {}
    for line in text.splitlines():
        m = re.match(r"\s*(?:creatureID\s*=\s*|n\(\s*)?(\d+)[\s,{(]*--\s*(.+?)\s*$", line)
        if m and int(m.group(1)) in wanted and int(m.group(1)) not in names:
            names[int(m.group(1))] = re.sub(r"\s*<.*$", "", m.group(2))
    return {"order": order, "zone": zone, "names": {str(k): v for k, v in sorted(names.items())},
            "loot": {str(k): v for k, v in sorted(loot.items()) if k in wanted}}


if __name__ == "__main__":
    import sys
    for qid, s in sorted(quests(sys.argv[1]).items()):
        print(qid, s)
