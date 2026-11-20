"""The players' comments behind Worth It's "what to do" steps.

    python3 tools/worthit/comments.py                    what the steps lack (empty when all is well)
    python3 tools/worthit/comments.py --urls             the Wowhead pages to collect
    python3 tools/worthit/comments.py --merge <folder>   take a new collection, print the new comments
    python3 tools/worthit/comments.py --digest           every reward with its chain and top comments

Gulli-WorthIt/Tips.lua has two to four hand-written steps per reward quest, in every language.
They come from the quest texts and the comments on Wowhead's WoW Forever quest pages, kept in
tools/worthit/wowhead-comments.json:

    { "collected": "YYYY-MM-DD", "site": ..., "quests": { "<id>": { "name", "objective",
      "description", "comments": [ { "user", "rating", "date", "body" } ] } } }

Wowhead refuses servers, so the pages are read in a browser on a player's computer: for each
URL of --urls, the quest's name, objective and description and the `lv_comments0` list of the
page (the 12 best rated comments, bodies cut at 1500 characters), saved as <folder>/q<id>.json
in the shape of one "quests" entry. --merge writes the snapshot again and prints the comments
it did not have: read them, and correct the steps in Tips.lua (every language) where players
found a better way.

The report names: a reward quest without steps, a quest of a reward's chain the snapshot lacks,
and a snapshot older than COMMENT_DAYS (collect again). tools/health/forever_content.py adds it
to the forever-content issue.
"""
import datetime
import html
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
DATA = os.path.join(ROOT, "Gulli-WorthIt", "Data.lua")
TIPS = os.path.join(ROOT, "Gulli-WorthIt", "Tips.lua")
SNAPSHOT = os.path.join(HERE, "wowhead-comments.json")
SITE = "https://www.wowhead.com/forever"
COMMENT_DAYS = 14   # WoW Forever is new: players still find better ways every week
KEEP, BODY = 12, 1500


def rewards():
    """[(reward quest, its chain)] from Data.lua, in the data's order, each quest once."""
    text = open(DATA, encoding="utf-8").read()
    chains = {}
    block = text[text.index("D.chain"):]
    for m in re.finditer(r"^\[(\d+)\]=\{([\d,]+)\},", block[:block.index("\n}")], re.M):
        chains[int(m.group(1))] = [int(x) for x in m.group(2).split(",")]
    out, seen = [], set()
    block = text[text.index("D.rewards"):]
    for m in re.finditer(r'^\{\d+,"\w+",(\d+)\}', block[:block.index("\n}")], re.M):
        q = int(m.group(1))
        if q not in seen:
            seen.add(q)
            out.append((q, chains.get(q, [q])))
    return out


def tipped():
    """The quests the English table of Tips.lua has steps for."""
    text = open(TIPS, encoding="utf-8").read()
    en = text[text.index("T.en = {"):]
    return {int(m) for m in re.findall(r"^\[(\d+)\] = \{", en[:en.index("\n}\n")], re.M)}


def load():
    if not os.path.exists(SNAPSHOT):
        return {"collected": "", "site": SITE, "quests": {}}
    return json.load(open(SNAPSHOT, encoding="utf-8"))


def clean(body):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"\[/?[^\]]*\]", "", body or ""))).strip()


def report(today=None):
    """The lines for the health report: [] when the steps keep up."""
    snap, lines = load(), []
    have, quests = tipped(), snap.get("quests", {})
    for q, chain in rewards():
        name = (quests.get(str(q)) or {}).get("name", "")
        if q not in have:
            lines.append("- Quest %d %s has no steps in Gulli-WorthIt/Tips.lua: write two to four, in "
                         "every language." % (q, name))
        missing = [str(s) for s in chain if str(s) not in quests]
        if missing:
            lines.append("- The comments snapshot lacks quest %s (chain of %d %s)." % (", ".join(missing), q, name))
    today = today or datetime.date.today()
    try:
        age = (today - datetime.date.fromisoformat(snap.get("collected", "")[:10])).days
    except ValueError:
        age = None
    if age is None or age > COMMENT_DAYS:
        lines.append("- The Wowhead comments of Worth It's quests are %s old: collect them again on a computer "
                     "(`python3 tools/worthit/comments.py --urls`, then `--merge`; Wowhead refuses servers) "
                     "and read the new ones for better steps." % ("%d days" % age if age is not None else "of unknown age"))
    return lines


def merge(folder):
    snap = load()
    old = snap.get("quests", {})
    fresh, new = {}, []
    for q, chain in rewards():
        for step in chain:
            path = os.path.join(folder, "q%d.json" % step)
            if not os.path.exists(path):
                if str(step) in old:
                    fresh[str(step)] = old[str(step)]
                continue
            entry = json.load(open(path, encoding="utf-8"))
            entry = entry.get(str(step), entry)
            comments = sorted(entry.get("comments") or [], key=lambda c: -(c.get("rating") or 0))[:KEEP]
            comments = [{"user": c.get("user", ""), "rating": c.get("rating") or 0, "date": c.get("date", ""),
                         "body": (c.get("body") or "")[:BODY]} for c in comments]
            known = {(c.get("user"), c.get("date")) for c in (old.get(str(step)) or {}).get("comments", [])}
            for c in comments:
                if (c["user"], c["date"]) not in known:
                    new.append((q, step, entry.get("name", ""), c))
            fresh[str(step)] = {"name": entry.get("name", ""), "objective": entry.get("objective", ""),
                                "description": entry.get("description", ""), "comments": comments}
    snap = {"collected": datetime.date.today().isoformat(), "site": SITE, "quests": fresh}
    with open(SNAPSHOT, "w", encoding="utf-8") as f:
        json.dump(snap, f, ensure_ascii=False, indent=1, sort_keys=True)
        f.write("\n")
    for q, step, name, c in new:
        print("## reward %d, quest %d %s | %s, %s, rating %s\n%s\n" % (
            q, step, name, c["user"], c["date"][:10], c["rating"], clean(c["body"])))
    print("%d quests, %d new comments." % (len(fresh), len(new)))


def digest():
    quests = load().get("quests", {})
    for q, chain in rewards():
        print("\n### REWARD %d chain %s" % (q, chain))
        for step in chain:
            e = quests.get(str(step)) or {}
            print("## %d %s | %s" % (step, e.get("name", "?"), clean(e.get("objective", ""))))
            for c in sorted(e.get("comments") or [], key=lambda c: -(c.get("rating") or 0))[:3]:
                print("  - (%s) %s" % (c.get("date", "")[:10], clean(c.get("body"))[:600]))


def main(argv):
    if "--urls" in argv:
        for q, chain in rewards():
            for step in chain:
                print("%s/quest=%d" % (SITE, step))
    elif "--merge" in argv:
        merge(argv[argv.index("--merge") + 1])
    elif "--digest" in argv:
        digest()
    elif argv:
        print(__doc__)
        return 2
    else:
        print("\n".join(report()) or "Worth It's steps keep up with the comments.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
