"""Reads the levelling quests of a dungeon from Guidelime_DungeonQuests (GPLv3,
https://github.com/JanRK/Guidelime_DungeonQuests): one Guidelime guide per dungeon (or wing)
that walks the quest chains a player takes for it while levelling, for each faction, and says
in its `-- Left out:` lines what it skips (class mounts, world PvP, set upgrades).

    quests(path) -> {quest id}
    tips(path) -> {quest id: {"t": text, "d": text, "h": text}}

A step's note (the text after `\\\\` on its line) is a tip for the stage of each quest the line
tags first: [QA] taking it (t), [QC] and [QS] its work (d), [QT] handing it in (h). Notes about the
guide's own sources (QuestieDB, Wowhead, "unverified", links) and the level a quest needs (the
page shows it) are left out; the first tip of a stage wins.

The quests are the [QA<id>], [QT<id>], [QC<id>] and [QS<id>] tags of the guide's steps; the
faction of each comes from QuestieDB, not from the guide. The file is read as text, never run.
"""
import re

QUEST = re.compile(r"\[Q[ATCS](\d+)")
TAG = re.compile(r"\[Q([ATCS])(\d+)")
STAGE = {"A": "t", "C": "d", "S": "d", "T": "h"}
TIP_MAX = 220
# A sentence about where the guide's facts come from, not about the quest.
META = re.compile(r"QuestieDB|Wowhead|Dungeon Journal|\bDJ\b|https?:|[Uu]nverified|[Nn]o source|\bguides?\b|\b\d{3,6}\b|"
                  r"[Ll]eft out|not part of|[Ff]ollow-up \d|^Needs level \d+\.?$|^Optional lead-in")


def quests(path):
    out = set()
    for line in open(path, encoding="utf-8"):
        if line.strip().startswith("--"):
            continue
        out.update(int(q) for q in QUEST.findall(line))
    return out


def clean(note):
    """A note as plain text: quest tags become their names, faction and map tags go."""
    note = re.sub(r"\[Q[ATCS]\d+\s*([^\]]*)\]", r"\1", note)
    note = re.sub(r"\[[A-Z]+[^\]]*\]", "", note)
    keep = []
    for sentence in re.split(r"(?<=[.!?])\s+", note.strip()):
        sentence = sentence.strip()
        if sentence and not META.search(sentence):
            keep.append(sentence)
    text = re.sub(r"\s+", " ", " ".join(keep)).strip(" ;,")
    if len(text) > TIP_MAX:
        text = text[:TIP_MAX].rsplit(" ", 1)[0].rstrip(",;:") + "..."
    return text


def tips(path):
    out = {}
    for line in open(path, encoding="utf-8"):
        if line.strip().startswith("--") or "\\\\" not in line:
            continue
        step, _, note = line.partition("\\\\")
        tags = TAG.findall(step)
        text = clean(note.replace("\\\\", " "))
        if not text or not tags:
            continue
        # The note is about the line's first step ("X takes [QT..] and gives [QA..]: turn in together").
        kind, qid = tags[0]
        out.setdefault(int(qid), {}).setdefault(STAGE[kind], text)
    return out


if __name__ == "__main__":
    import sys
    for qid in sorted(quests(sys.argv[1])):
        print(qid)
