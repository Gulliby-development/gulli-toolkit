"""Experience of the Dungeon Journal quests that QuestieDB has not measured (WoW Forever's own).

    python3 tools/dungeonprep/questxp.py                 the quests without experience (empty when all is well)
    python3 tools/dungeonprep/questxp.py --urls          their Wowhead pages
    python3 tools/dungeonprep/questxp.py --collect       read those pages (on a player's computer) into the snapshot

Wowhead refuses servers, so --collect runs on a player's computer: it reads each quest's page on
Wowhead's WoW Forever site, one every few seconds, and takes the experience of its "Gains" part.
The snapshot is tools/dungeonprep/wowhead-questxp.json:

    { "collected": "YYYY-MM-DD", "site": ..., "quests": { "<id>": <experience> } }

build_data.py takes it where QuestieDB's QuestXP tables have nothing; QuestieDB wins where it has
a number. A quest whose own page shows no experience is kept as 0, so it is not asked for again.
An empty, challenge or Human Verification page is never saved.
"""
import datetime
import json
import os
import re
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
DATA = os.path.join(ROOT, "Gulli-DungeonPrep", "Data.lua")
SNAPSHOT = os.path.join(HERE, "wowhead-questxp.json")
SITE = "https://www.wowhead.com/forever"
PAUSE = 3


def block(text, name):
    start = text.index("\n%s = {" % name)
    return text[start:text.index("\n}", start)]


def missing():
    """Quest ids of D.quest and D.pre that D.xp and the snapshot both lack."""
    text = open(DATA, encoding="utf-8").read()
    ids = set()
    for name in ("D.quest", "D.pre"):
        ids |= {int(m) for m in re.findall(r"^\[(\d+)\]=", block(text, name), re.M)}
    have = {int(m) for m in re.findall(r"^\[(\d+)\]=", block(text, "D.xp"), re.M)}
    have |= {int(k) for k in load()["quests"]}
    return sorted(ids - have)


def load():
    if os.path.exists(SNAPSHOT):
        with open(SNAPSHOT, encoding="utf-8") as fh:
            return json.load(fh)
    return {"collected": None, "site": SITE, "quests": {}}


def save(snap):
    snap["collected"] = datetime.date.today().isoformat()
    snap["quests"] = dict(sorted(snap["quests"].items(), key=lambda kv: int(kv[0])))
    with open(SNAPSHOT, "w", encoding="utf-8") as fh:
        json.dump(snap, fh, indent=1)
        fh.write("\n")


def experience(page, qid):
    """The experience a quest page names under "Gains" (div quest-reward-xp); 0 when the quest's own
    page shows none; None when the page is not that quest's page (empty, challenge, Human Verification)."""
    m = re.search(r'id="quest-reward-xp"[^>]*>(.*?)</div>', page, re.S)
    if m:
        n = re.search(r"(\d[\d,.\s]*)\s*experience", re.sub(r"<[^>]+>", " ", m.group(1)), re.I)
        if n:
            return int(re.sub(r"\D", "", n.group(1)))
    if re.search(r"Human Verification|challenge-platform|cf-chl-", page, re.I):
        return None
    own = re.search(r'rel="canonical"[^>]*/quest=%d' % qid, page) and re.search(r"<h1[^>]*>\s*[^<\s]", page)
    return 0 if own else None


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
                                               "Accept-Language": "en-US,en;q=0.9"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")


def collect():
    snap, todo = load(), missing()
    print("%d quests to read" % len(todo))
    for n, qid in enumerate(todo, 1):
        try:
            xp = experience(fetch("%s/quest=%d" % (SITE, qid)), qid)
        except Exception as e:
            print("quest %d: %s (try again later)" % (qid, e))
            continue
        if xp is None:
            print("quest %d: not the quest's page (verification or empty), try again later" % qid)
            time.sleep(PAUSE)
            continue
        snap["quests"][str(qid)] = xp
        print("%d/%d quest %d: %d" % (n, len(todo), qid, xp))
        save(snap)
        time.sleep(PAUSE)
    print("done: %s" % SNAPSHOT)


def main(argv):
    if "--collect" in argv:
        collect()
    elif "--urls" in argv:
        for qid in missing():
            print("%s/quest=%d" % (SITE, qid))
    else:
        for qid in missing():
            print("quest %d has no experience" % qid)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
