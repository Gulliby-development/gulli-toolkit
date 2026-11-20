"""Does Worth It list every quest bag that BagQuests (pmgower/bagquests-forever) offers?

    python3 tools/worthit/bagquests.py

BagQuests is a WoW Forever addon that guides players to bag quests, kept up by hand from players'
finds. Each file of its BagQuests/Data folder names the items a route gives (`rewardItems`,
`bonusItems`). An item there that Worth It's Data.lua does not list and that is not in
bagquests_seen.txt is news: add its quest to EXTRA in tools/worthit/build_data.py (with the
quest's Wowhead page as the source), or note why not in bagquests_seen.txt. The daily Forever
watch runs it through tools/health/forever_content.py. Only the item ids are read; nothing of
that addon is copied.
"""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
DATA = os.path.join(ROOT, "Gulli-WorthIt", "Data.lua")
SEEN = os.path.join(HERE, "bagquests_seen.txt")
REPO = "pmgower/bagquests-forever"
URL = "https://github.com/%s" % REPO
ITEMS = re.compile(r"\b(rewardItems|bonusItems)\s*=\s*\{([^}]*)\}")
TITLE = re.compile(r'^\s*title\s*=\s*"([^"]+)"', re.M)


def fetch():
    """{file name: text} of BagQuests/Data in a fresh shallow clone (git works where the API is refused)."""
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["git", "clone", "-q", "--depth", "1", URL, tmp], check=True, timeout=120,
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        folder = os.path.join(tmp, "BagQuests", "Data")
        return {n: open(os.path.join(folder, n), encoding="utf-8", errors="replace").read()
                for n in os.listdir(folder) if n.endswith(".lua")}


def their_items(files=None):
    """{item id: (file, route title)} from BagQuests' data files ({name: text} or fetched)."""
    if files is None:
        files = fetch()
    out = {}
    for name, text in sorted(files.items()):
        text = re.sub(r"--[^\n]*", "", text)
        m = TITLE.search(text)
        title = m.group(1) if m else name
        for _, ids in ITEMS.findall(text):
            for iid in re.findall(r"\d+", ids):
                out.setdefault(int(iid), (name, title))
    return out


def ours():
    text = open(DATA, encoding="utf-8").read()
    block = text[text.index("D.rewards = {"):text.index("}\n", text.index("D.rewards = {"))]
    return {int(i) for i in re.findall(r"^\{(\d+),", block, re.M)}


def seen():
    out = set()
    if os.path.exists(SEEN):
        for line in open(SEEN, encoding="utf-8"):
            line = line.split("#")[0].strip()
            if line:
                out.add(int(line))
    return out


def report(files=None):
    """Lines for the Forever watch: the items BagQuests gives that Worth It lacks."""
    try:
        theirs = their_items(files)
    except Exception as e:  # a network hiccup is no finding; the next run reads it again
        print("BagQuests could not be read: %s" % e, file=sys.stderr)
        return []
    have, skip = ours(), seen()
    return ["- %d (%s, %s)" % (iid, title, name) for iid, (name, title) in sorted(theirs.items())
            if iid not in have and iid not in skip]


if __name__ == "__main__":
    lines = report()
    print("\n".join(lines) or "Worth It lists every bag BagQuests offers.")
