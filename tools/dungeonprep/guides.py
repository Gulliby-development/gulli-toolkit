"""Reads the levelling quests of a dungeon from Guidelime_DungeonQuests (GPLv3,
https://github.com/JanRK/Guidelime_DungeonQuests): one Guidelime guide per dungeon (or wing)
that walks the quest chains a player takes for it while levelling, for each faction, and says
in its `-- Left out:` lines what it skips (class mounts, world PvP, set upgrades).

    quests(path) -> {quest id}

The quests are the [QA<id>], [QT<id>], [QC<id>] and [QS<id>] tags of the guide's steps; the
faction of each comes from QuestieDB, not from the guide. The file is read as text, never run.
"""
import re

QUEST = re.compile(r"\[Q[ATCS](\d+)")


def quests(path):
    out = set()
    for line in open(path, encoding="utf-8"):
        if line.strip().startswith("--"):
            continue
        out.update(int(q) for q in QUEST.findall(line))
    return out


if __name__ == "__main__":
    import sys
    for qid in sorted(quests(sys.argv[1])):
        print(qid)
