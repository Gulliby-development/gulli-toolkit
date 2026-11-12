"""Checks Gulli-Attune's chains against the QuestieDB Forever data.

    python3 tools/attune/check_data.py <questiedb-checkout>

1. Every step in ns.RAIDS (Gulli-Attune/Core.lua) must exist in the data under the same English name.
2. Lists quests that look like an attunement or that reward a key, that Core.lua does not track
   and that seen.txt does not list yet. A human (or the daily check) decides whether one becomes
   a new chain; --update-seen then adds the rest to seen.txt, so only new quests show up next time.
Exits 1 when a step is missing or renamed.
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "questcleaner"))
import luadata  # noqa: E402

CORE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Gulli-Attune", "Core.lua")
Q_NAME = 1
I_NAME, I_REWARD_OF = 1, 6
LOOKS_LIKE = re.compile(r"attune|\bkey\b|seal of|amulet|brooch|sewer|scepter|the dread citadel", re.I)
SEEN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "seen.txt")


def read_seen():
    if not os.path.exists(SEEN):
        return set()
    return {int(line.split()[0]) for line in open(SEEN, encoding="utf-8") if line.strip() and line[0].isdigit()}


def tracked_steps(path):
    text = open(path, encoding="utf-8").read()
    steps = [(int(i), name) for i, name in re.findall(r'\{ (\d+), "((?:[^"\\]|\\.)*)"', text)]
    any_of = {int(i) for group in re.findall(r"anyOf = \{([^}]*)\}", text) for i in re.findall(r"\d+", group)}
    return steps, any_of


def main(root, update_seen=False):
    quests = luadata.load(os.path.join(root, "data/Forever/foreverQuestDB.lua"), "questData")
    items = luadata.load(os.path.join(root, "data/Forever/foreverItemDB.lua"), "itemData")
    steps, any_of = tracked_steps(CORE)
    known = {i for i, _ in steps} | any_of
    seen = read_seen()
    new = []
    bad = 0
    for qid, name in steps:
        got = quests.get(qid, {}).get(Q_NAME)
        if got != name.replace("\\'", "'"):
            print(f"STEP {qid} {name!r}: data has {got!r}")
            bad += 1
    key_quests = set()
    for item in items.values():
        if re.search(r"\bkey\b|seal|amulet|brooch|scepter", item.get(I_NAME) or "", re.I):
            key_quests.update((item.get(I_REWARD_OF) or {}).values())
    for qid in sorted(quests):
        name = quests[qid].get(Q_NAME) or ""
        if qid in known or qid in seen:
            continue
        if qid in key_quests or LOOKS_LIKE.search(name):
            print(f"CANDIDATE {qid} {name}")
            new.append(f"{qid} {name}")
    if update_seen and new:
        with open(SEEN, "a", encoding="utf-8") as f:
            f.write("\n".join(new) + "\n")
    print(f"{len(steps)} steps checked, {bad} wrong")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], "--update-seen" in sys.argv[2:]))
