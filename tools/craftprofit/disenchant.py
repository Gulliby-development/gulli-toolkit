"""What disenchanting the crafted gear gives in WoW Forever, from Wowhead's "Disenchanting" tabs.

    python3 tools/craftprofit/disenchant.py              the items not read yet (empty when all is well)
    python3 tools/craftprofit/disenchant.py --urls       their Wowhead pages
    python3 tools/craftprofit/disenchant.py --collect    read those pages (on a player's computer) into the snapshot
    python3 tools/craftprofit/disenchant.py --again N    with --collect: also read again what is older than N days

Wowhead refuses servers, so --collect runs on a player's computer: it reads the page of each item
a profession of tools/craftprofit/wowhead-professions.json makes (Blacksmithing, Leatherworking,
Tailoring, Engineering; no reagent), one every few seconds, and keeps what its Disenchanting tab
counted. It reads only the items it has not read yet, so a weekly run takes the new items alone.
The snapshot is tools/craftprofit/wowhead-disenchant.json:

    { "collected": "YYYY-MM-DD", "site": ...,
      "items": { "<id>": { "at": "YYYY-MM-DD", "total": <disenchants counted>,
                           "mats": [ [ material id, share 0..1, mean count ], ... ] } } }

An item whose page has no Disenchanting tab is kept with "total": 0, so it is not asked for again.
A challenge or Human Verification page is never saved. build_data.py turns the snapshot into
Data.de (item -> the mean count of each material per disenchant); CraftProfit uses it where enough
disenchants were counted (`ns.DE_MIN` in Core.lua), else the Vanilla tables by item level.
"""
import datetime
import json
import os
import re
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
PROFS = os.path.join(HERE, "wowhead-professions.json")
SNAPSHOT = os.path.join(HERE, "wowhead-disenchant.json")
SITE = "https://www.wowhead.com/forever"
PAUSE = 3
GEAR_SKILLS = ("164", "165", "197", "202")


def items():
    """The items the gear professions make, without their reagents (bolts, bars, leather)."""
    with open(PROFS, encoding="utf-8") as fh:
        skills = json.load(fh)["skills"]
    made, reagents = set(), set()
    for k in GEAR_SKILLS:
        for r in (skills.get(k) or {}).get("recipes") or []:
            if r.get("item") and not r.get("unavailable"):
                made.add(int(r["item"]))
    for p in skills.values():
        for r in p.get("recipes") or []:
            for x in r.get("reagents") or {}:
                reagents.add(int(x))
    return sorted(made - reagents)


def load():
    try:
        with open(SNAPSHOT, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {"collected": None, "site": SITE, "items": {}}


def save(snap):
    snap["collected"] = datetime.date.today().isoformat()
    with open(SNAPSHOT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(snap, fh, indent=1, sort_keys=True)
        fh.write("\n")


def missing(snap=None, again=None):
    snap = snap or load()
    have = snap.get("items") or {}
    out = []
    today = datetime.date.today()
    for i in items():
        e = have.get(str(i))
        if e is None:
            out.append(i)
        elif again is not None and e.get("at"):
            try:
                if (today - datetime.date.fromisoformat(e["at"])).days > again:
                    out.append(i)
            except ValueError:
                out.append(i)
    return out


def _block(page, start):
    """The text of a bracketed block that opens at `start` ([ or {), strings respected."""
    open_c = page[start]
    close_c = "]" if open_c == "[" else "}"
    depth, i, quote = 0, start, None
    while i < len(page):
        c = page[i]
        if quote:
            if c == "\\":
                i += 1
            elif c == quote:
                quote = None
        elif c in "\"'":
            quote = c
        elif c == open_c:
            depth += 1
        elif c == close_c:
            depth -= 1
            if depth == 0:
                return page[start:i + 1]
        i += 1
    return None


def _stack(row):
    """The mean count of one drop: from `pctstack` ({count: percent}), else the middle of `stack`."""
    ps = row.get("pctstack")
    if isinstance(ps, str):
        pairs = re.findall(r"[\"']?(\d+)[\"']?\s*:\s*([\d.]+)", ps)
        ps = {k: float(v) for k, v in pairs}
    if isinstance(ps, dict) and ps:
        tot = sum(float(v) for v in ps.values())
        if tot > 0:
            return sum(int(k) * float(v) for k, v in ps.items()) / tot
    st = row.get("stack")
    if isinstance(st, list) and st:
        return (float(st[0]) + float(st[-1])) / 2
    return 1.0


def parse(page, item):
    """{ total, mats } of an item page; total 0 when it has no Disenchanting tab; None when the page
    is not that item's page (challenge, Human Verification, empty)."""
    if re.search(r"Human Verification|challenge-platform|cf-chl-", page, re.I):
        return None
    m = re.search(r"""["']?id["']?\s*:\s*["']disenchanting["']""", page)
    if not m:
        own = re.search(r"/item=%d(?!\d)" % item, page) and re.search(r"<h1[^>]*>\s*[^<\s]", page)
        return {"total": 0, "mats": []} if own else None
    # the Listview call around the tab's id
    begin = page.rfind("new Listview(", 0, m.start())
    if begin < 0:
        return None
    lv = _block(page, page.index("{", begin))
    if not lv:
        return None
    tm = re.search(r"""["']?_totalCount["']?\s*:\s*(\d+)""", lv)
    dm = re.search(r"""["']?data["']?\s*:\s*\[""", lv)
    if not dm:
        return None
    data = json.loads(_block(lv, dm.end() - 1))
    counts = [(int(r["id"]), int(r.get("count") or 0), _stack(r)) for r in data if r.get("id")]
    total = int(tm.group(1)) if tm else 0
    if total <= 0:
        total = sum(c for _, c, _ in counts)
    if total <= 0:
        return {"total": 0, "mats": []}
    mats = [[mid, round(c / total, 4), round(s, 3)] for mid, c, s in counts if c > 0]
    mats.sort(key=lambda x: -x[1])
    return {"total": total, "mats": mats}


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
                                               "Accept-Language": "en-US,en;q=0.9"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")


def collect(again=None):
    snap = load()
    snap.setdefault("items", {})
    snap["site"] = SITE
    todo = missing(snap, again)
    print("%d items to read" % len(todo))
    for n, item in enumerate(todo, 1):
        try:
            page = fetch("%s/item=%d" % (SITE, item))
            got = parse(page, item)
        except Exception as e:  # one bad page never stops the run
            print("item %d: %s (try again later)" % (item, e))
            time.sleep(PAUSE)
            continue
        if got is None:
            print("item %d: not the item's page (verification or empty), try again later" % item)
            time.sleep(PAUSE)
            continue
        got["at"] = datetime.date.today().isoformat()
        snap["items"][str(item)] = got
        print("%d/%d item %d: %d disenchants, %s" % (n, len(todo), item, got["total"], got["mats"]))
        if n % 20 == 0:
            save(snap)
        time.sleep(PAUSE)
    save(snap)
    print("done: %s" % SNAPSHOT)


def main(argv):
    again = None
    if "--again" in argv:
        again = int(argv[argv.index("--again") + 1])
    if "--collect" in argv:
        collect(again)
    elif "--urls" in argv:
        for i in missing(None, again):
            print("%s/item=%d" % (SITE, i))
    else:
        for i in missing(None, again):
            print("item %d has no disenchanting data" % i)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
