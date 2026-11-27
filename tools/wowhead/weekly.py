"""The weekly read of what only Wowhead has: comments, quest experience, boss models and drop chances.

    python3 tools/wowhead/weekly.py todo [tasks.json]     the pages to read now (default tools/wowhead/todo.json)
    python3 tools/wowhead/weekly.py tasks                 those tasks as [url, kind, id], for gulliWH()
    python3 tools/wowhead/weekly.py js <run.js>           collector.js with those tasks, to paste into the tab
    python3 tools/wowhead/weekly.py merge <pages.json>    take the pages read into the snapshots

Wowhead refuses servers, so the pages are read in a browser on the owner's computer: the weekly
scheduled run pastes collector.js into a tab on www.wowhead.com with the tasks of `todo`, and
reads its results back as one JSON object, page URL -> the small parts merge needs (for a quest
page its name, objective, description, experience and best comments; for an NPC page its name,
model, abilities and drops). Only what is missing is read, so a week costs a few minutes:

- Dungeon Journal: comments of quests tools/dungeonprep/wowhead-comments.json lacks, the experience
  of quests neither QuestieDB nor tools/dungeonprep/wowhead-questxp.json has, and the NPC page of
  each boss or rare of build_journal.LEVELS whose model or drops the snapshot lacks.
- Worth It: every quest of its reward chains (tools/worthit/wowhead-comments.json), since its
  steps follow what players find (COMMENT_DAYS there).

merge writes the snapshots through the scripts that own them (comments.py, questxp.py,
merge_npcs.py, worthit/comments.py) and prints the new Worth It comments. The daily game data
run then rebuilds the Data.lua files and writes tips from the new comments. Pages are untrusted
text: they are only parsed, never run.
"""
import datetime
import importlib.util
import json
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
TODO = os.path.join(HERE, "todo.json")
DJ = os.path.join(ROOT, "tools", "dungeonprep")


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.path.insert(0, os.path.dirname(path))
    spec.loader.exec_module(mod)
    return mod


def mods():
    return {
        "djc": module(os.path.join(DJ, "comments.py"), "dj_comments"),
        "xp": module(os.path.join(DJ, "questxp.py"), "dj_questxp"),
        "bj": module(os.path.join(DJ, "build_journal.py"), "build_journal"),
        "mn": module(os.path.join(DJ, "merge_npcs.py"), "merge_npcs"),
        "wi": module(os.path.join(ROOT, "tools", "worthit", "comments.py"), "wi_comments"),
    }


def journal_npcs():
    """npc id -> dungeon key, from the boss lists of JournalData.lua."""
    text = open(os.path.join(ROOT, "Gulli-DungeonPrep", "JournalData.lua"), encoding="utf-8").read()
    start = text.index("D.boss = {")
    body = text[start:text.index("\nD.", start + 1)]
    out, key = {}, None
    for line in body.splitlines()[1:]:
        m = re.match(r"^([A-Z_]+) = \{", line)
        if m:
            key = m.group(1)
            continue
        m = re.match(r"^\{(\d+),", line)
        if m and key:
            out[int(m.group(1))] = key
    return out


def npcs_to_read(m):
    snap = json.load(open(m["mn"].SNAPSHOT, encoding="utf-8")).get("dungeons", {})
    have = {}
    for key, d in snap.items():
        for b in (d.get("bosses") or []) + (d.get("rares") or []):
            have[m["bj"].as_int(b.get("id"))] = b
    where = journal_npcs()
    out = []
    for npc in sorted(m["bj"].LEVELS):
        npc = m["mn"].PARTS.get(npc, npc)
        b = have.get(npc)
        if b and b.get("displayId"):
            continue
        key = where.get(npc)
        if key:
            out.append((key, npc))
    return out


# What is read first when a week has more pages than MAX_PAGES: the rest waits for the next week.
ORDER = ["npc", "xp", "forever", "wi", "main", "classic"]
MAX_PAGES = 120   # Wowhead asks for a Human Verification after a few hundred pages
WI_DAYS = 13      # Worth It's quests are read again every second week (its COMMENT_DAYS is 14)


def todo(path, limit=MAX_PAGES):
    m = mods()
    tasks = {}

    def add(url, kind, qid, dungeon=None):
        t = tasks.setdefault(url, {"key": url, "url": url, "id": qid, "kinds": []})
        t["kinds"].append(kind)
        t["kind"] = "npc" if kind == "npc" else "quest"
        if dungeon:
            t["dungeon"] = dungeon

    snap = m["djc"].load()
    for qid in m["djc"].quests():
        for site, base in m["djc"].SITES.items():
            if site != "forever" and qid >= 90000:
                continue
            if site not in snap["quests"].get(str(qid), {}):
                add("%s/quest=%d" % (base, qid), "djc:" + site, qid)
    for qid in m["xp"].missing():
        add("%s/quest=%d" % (m["xp"].SITE, qid), "xp", qid)
    wi = m["wi"].load()
    try:
        age = (datetime.date.today() - datetime.date.fromisoformat(wi.get("collected", "")[:10])).days
    except ValueError:
        age = None
    for _q, chain in m["wi"].rewards():
        for step in chain:
            if age is None or age >= WI_DAYS or str(step) not in wi.get("quests", {}):
                add("%s/quest=%d" % (m["wi"].SITE, step), "wi", step)
    for key, npc in npcs_to_read(m):
        add("https://www.wowhead.com/forever/npc=%d" % npc, "npc", npc, key)
    out = sorted(tasks.values(), key=lambda t: (min(ORDER.index(k.split(":")[-1] if k.startswith("djc:") else k)
                                                      for k in t["kinds"]), t["url"]))[:limit]
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=0)
        f.write("\n")
    kinds = {}
    for t in out:
        for k in t["kinds"]:
            kinds[k.split(":")[0]] = kinds.get(k.split(":")[0], 0) + 1
    print("%d of %d pages to read (%s) -> %s" % (len(out), len(tasks), ", ".join("%s %d" % kv for kv in sorted(kinds.items())), path))


def merge(path):
    m = mods()
    pages = json.load(open(path, encoding="utf-8"))
    tasks = {t["key"]: t for t in json.load(open(TODO, encoding="utf-8"))} if os.path.exists(TODO) else {}
    djc, xp = m["djc"].load(), m["xp"].load()
    npcs, wi_dir = {}, tempfile.mkdtemp(prefix="wi-")
    counts = {"djc": 0, "xp": 0, "wi": 0, "npc": 0, "skipped": 0}
    for url, page in pages.items():
        task = tasks.get(url)
        if task is None or page is None:
            counts["skipped"] += 1
            continue
        qid = task["id"]
        for kind in task["kinds"]:
            if kind == "npc":
                if isinstance(page, dict):
                    entry = dict(page, id=qid)
                    npcs.setdefault(task["dungeon"], []).append(entry)
                    counts["npc"] += 1
            elif not isinstance(page, dict):
                continue
            elif kind.startswith("djc:"):
                # A quest another site does not have sends its quest list: noted as no comments.
                got = page.get("comments") if page.get("own") else []
                if got is not None:
                    djc["quests"].setdefault(str(qid), {})[kind[4:]] = got
                    counts["djc"] += 1
            elif kind == "xp":
                if page.get("own") and page.get("xp") is not None:
                    xp["quests"][str(qid)] = int(page["xp"])
                    counts["xp"] += 1
            elif kind == "wi":
                if not page.get("own") or page.get("comments") is None:
                    continue
                with open(os.path.join(wi_dir, "q%d.json" % qid), "w", encoding="utf-8") as f:
                    json.dump({k: page.get(k) for k in ("name", "objective", "description", "comments")},
                              f, ensure_ascii=False)
                counts["wi"] += 1
    if counts["djc"]:
        m["djc"].save(djc)
    if counts["xp"]:
        m["xp"].save(xp)
    if npcs:
        snap = json.load(open(m["mn"].SNAPSHOT, encoding="utf-8"))
        for line in m["mn"].merge(snap, npcs, m["bj"].read_walk(None)):
            print("added " + line)
        with open(m["mn"].SNAPSHOT, "w", encoding="utf-8", newline="\n") as f:
            json.dump(snap, f, ensure_ascii=False, separators=(",", ":"))
    if counts["wi"]:
        m["wi"].merge(wi_dir)
    print("merged: %s" % ", ".join("%s %d" % kv for kv in counts.items()))


def compact():
    """The tasks of todo.json as [url, kind, id], for gulliWH()."""
    return [[t["url"], t["kind"], t["id"]] for t in json.load(open(TODO, encoding="utf-8"))]


def script(out):
    """collector.js and the call that starts it on the tasks of todo.json, to paste into the tab."""
    tasks = [{"key": t["key"], "url": t["url"], "kind": t["kind"], "id": t["id"]}
             for t in json.load(open(TODO, encoding="utf-8"))]
    js = open(os.path.join(HERE, "collector.js"), encoding="utf-8").read()
    with open(out, "w", encoding="utf-8") as f:
        f.write(js + "\ngulliWHClear();\ngulliWH(%s);\n\"started %d pages\";\n" % (json.dumps(tasks), len(tasks)))
    print("%d pages -> %s" % (len(tasks), out))


def main(argv):
    if argv[:1] == ["todo"]:
        todo(argv[1] if len(argv) > 1 else TODO)
    elif argv[:1] == ["tasks"]:
        print(json.dumps(compact(), separators=(",", ":")))
    elif argv[:1] == ["js"] and len(argv) > 1:
        script(argv[1])
    elif argv[:1] == ["merge"] and len(argv) > 1:
        merge(argv[1])
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
