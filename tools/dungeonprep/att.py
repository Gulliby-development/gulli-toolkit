"""Reads the quests of a dungeon from AllTheThings' WoW Forever data (MIT licence,
https://github.com/ATTWoWAddon/AllTheThings, `.contrib/.db/forever/dungeons & raids/<name>.lua`).

ATT lists every quest of an instance under it, checked in the game, with the races that can
take it (`races = ALLIANCE_ONLY` on the quest or on a header above it). QuestieDB ties quests
to a dungeon only through their mobs, objects and drops, and its race masks are sometimes
wrong for WoW Forever's own quests, so the generator takes both.

    quests(path) -> {quest id: "A" | "H" | ""}

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


if __name__ == "__main__":
    import sys
    for qid, s in sorted(quests(sys.argv[1]).items()):
        print(qid, s)
