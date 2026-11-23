"""The players' comments on the Dungeon Journal quests, to check where each part of a quest happens.

    python3 tools/dungeonprep/comments.py --collect     read the Wowhead pages (on a player's computer)
    python3 tools/dungeonprep/comments.py --check       compare them with D.inside, print the mismatches

Wowhead refuses servers, so --collect runs on a player's computer. For each quest of D.quest it reads
the quest's page on Wowhead's WoW Forever site, its Classic site and its main site (the oldest
comments, from 2006 on, live there), one page every few seconds, and keeps the comments of each:
tools/dungeonprep/wowhead-comments.json

    { "collected": "YYYY-MM-DD", "quests": { "<id>": { "<site>": [ { "user", "date", "rating", "body" } ] } } }

A page that is a challenge or Human Verification is not saved and is read again on the next run;
a quest already read on a site is skipped, so the run can stop and go on.
"""
import datetime
import html
import json
import os
import re
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
DATA = os.path.join(ROOT, "Gulli-DungeonPrep", "Data.lua")
SNAPSHOT = os.path.join(HERE, "wowhead-comments.json")
SITES = {"forever": "https://www.wowhead.com/forever", "classic": "https://www.wowhead.com/classic",
         "main": "https://www.wowhead.com"}
PAUSE, KEEP, BODY = 2.5, 15, 1500


def block(text, name):
    start = text.index("\n%s = {" % name)
    return text[start:text.index("\n}", start)]


def quests():
    text = open(DATA, encoding="utf-8").read()
    return sorted({int(m) for m in re.findall(r"^\[(\d+)\]=", block(text, "D.quest"), re.M)})


def load():
    if os.path.exists(SNAPSHOT):
        with open(SNAPSHOT, encoding="utf-8") as fh:
            return json.load(fh)
    return {"collected": None, "quests": {}}


def save(snap):
    snap["collected"] = datetime.date.today().isoformat()
    snap["quests"] = dict(sorted(snap["quests"].items(), key=lambda kv: int(kv[0])))
    with open(SNAPSHOT, "w", encoding="utf-8") as fh:
        json.dump(snap, fh, ensure_ascii=False, indent=0, sort_keys=True)
        fh.write("\n")


def array_after(page, name):
    """The text of the JS array assigned to name, brackets matched outside strings."""
    m = re.search(r"\b%s\s*=\s*\[" % name, page)
    if not m:
        return None
    i, depth, quote = m.end() - 1, 0, None
    while i < len(page):
        c = page[i]
        if quote:
            if c == "\\":
                i += 1
            elif c == quote:
                quote = None
        elif c in "\"'":
            quote = c
        elif c == "[":
            depth += 1
        elif c == "]":
            depth -= 1
            if depth == 0:
                return page[m.end() - 1:i + 1]
        i += 1
    return None


def comments(page, qid):
    """The comments of a quest page, best rated first; None when it is not the quest's page."""
    raw = array_after(page, "lv_comments0")
    if raw is None:
        if re.search(r"Human Verification|challenge-platform|cf-chl-", page, re.I):
            return None
        own = re.search(r"quest=%d(?!\d)" % qid, page) and re.search(r"<h1[^>]*>\s*[^<\s]", page)
        return [] if own else None
    try:
        items = json.loads(raw)
    except ValueError:
        items = [{"body": json.loads('"%s"' % b) if b else ""}
                 for b in re.findall(r'"body"\s*:\s*"((?:[^"\\]|\\.)*)"', raw)]
    out = []
    for c in items:
        if not isinstance(c, dict):
            continue
        out.append({"user": c.get("user", ""), "date": str(c.get("date", ""))[:10],
                    "rating": c.get("rating", 0), "body": (c.get("body") or "")[:BODY]})
    out.sort(key=lambda c: -(c["rating"] or 0) if isinstance(c["rating"], (int, float)) else 0)
    return out[:KEEP]


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
                                               "Accept-Language": "en-US,en;q=0.9"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")


def collect():
    snap = load()
    todo = [(qid, site) for qid in quests() for site in SITES
            if not (site != "forever" and qid >= 90000)
            and site not in snap["quests"].get(str(qid), {})]
    print("%d pages to read" % len(todo))
    for n, (qid, site) in enumerate(todo, 1):
        try:
            got = comments(fetch("%s/quest=%d" % (SITES[site], qid)), qid)
        except Exception as e:
            print("quest %d %s: %s (try again later)" % (qid, site, e))
            time.sleep(PAUSE)
            continue
        if got is None:
            print("quest %d %s: not the quest's page, try again later" % (qid, site))
        else:
            snap["quests"].setdefault(str(qid), {})[site] = got
            print("%d/%d quest %d %s: %d comments" % (n, len(todo), qid, site, len(got)))
            if n % 20 == 0:
                save(snap)
        time.sleep(PAUSE)
    save(snap)
    print("done: %s" % SNAPSHOT)


def clean(body):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"\[/?[^\]]*\]", "", body or ""))).strip()


def main(argv):
    if "--collect" in argv:
        collect()
    elif "--check" in argv:
        check()
    else:
        print(__doc__)
    return 0



# Words that say where a part of a quest happens. --check prints each sentence with one of them
# beside the quest's inside marks, for a person to judge (a comment is a hint, never a rule).
WHERE = re.compile(r"\b(outside|inside|instance|entrance|portal|zone[ds]? in|zone-in|in front of|"
                   r"before (?:you )?(?:enter|go in|zone)|don'?t (?:need|have) to (?:go|enter)|"
                   r"no need to (?:go|enter)|not in the (?:dungeon|instance)|in the (?:dungeon|instance)|"
                   r"mountain|summon|spawns?|respawn|escort|cave|courtyard|upstairs|downstairs|"
                   r"in town|in the city|the (?:inn|bar|tavern))\b", re.I)


def data():
    text = open(DATA, encoding="utf-8").read()
    names, givers = {}, {}
    for m in re.finditer(r'^\[(\d+)\]=\{"((?:[^"\\]|\\.)*)",.*?,"((?:[^"\\]|\\.)*)",(\d+),.*?,"([AH]?)",[^,]*,[^,]*,"((?:[^"\\]|\\.)*)",(\d+)',
                         block(text, "D.quest"), re.M):
        names[int(m.group(1))] = m.group(2)
        givers[int(m.group(1))] = (m.group(3), m.group(6))
    inside = {}
    for line in block(text, "D.inside").splitlines():
        m = re.match(r"(\w+)=\{(.*)\},?$", line)
        if m:
            for q, f in re.findall(r'\[(\d+)\]="(\w+)"', m.group(2)):
                inside.setdefault(int(q), {})[m.group(1)] = f
    dungeon = {}
    for line in block(text, "D.byDungeon").splitlines():
        m = re.match(r"(\w+)=\{(.*)\},?$", line)
        if m:
            for q in re.findall(r"\d+", m.group(2)):
                dungeon.setdefault(int(q), []).append(m.group(1))
    return names, givers, inside, dungeon


def check():
    snap = load()
    names, givers, inside, dungeon = data()
    for qid in quests():
        lines = []
        for site, items in sorted(snap["quests"].get(str(qid), {}).items()):
            for c in items:
                for s in re.split(r"(?<=[.!?])\s+", clean(c["body"])):
                    if WHERE.search(s):
                        lines.append("    [%s %s %s] %s" % (site, c.get("date", ""), c.get("rating", ""), s[:300]))
        if lines:
            print("%d %s | %s | marks %s | from %s, to %s" % (
                qid, names.get(qid, "?"), ",".join(dungeon.get(qid, [])), inside.get(qid, {}) or "-",
                *givers.get(qid, ("?", "?"))))
            print("\n".join(lines))


if __name__ == "__main__":
    sys.exit(main(sys.argv))
