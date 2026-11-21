"""Does every module keep up with the WoW Forever data in QuestieDB?

    python3 tools/health/forever_content.py <questiedb> [--out report.md] [--update-seen]

1. Dungeons: the dungeons of DungeonPrep's generator (`DUNGEONS` in
   tools/dungeonprep/build_data.py) are the list. Bulletin (`ns.DUNGEONS`)
   must name each one (by area id or by name), and DungeonPrep needs its icon (`ns.ICONS`)
   and entrance (`ENTRANCES`).
2. New Forever areas: every area in a "Forever:" section of QuestieDB's zones.lua that is not
   in tools/health/forever_seen.txt is news, with how many Forever quests and NPCs it has.
   An instance area stays a finding until DungeonPrep lists it (or the dungeon it is a part
   of); `--update-seen` marks only the other areas, so add a non-dungeon instance area to
   forever_seen.txt by hand.

3. Forever recipes: every pattern of WoW Forever's own (an item id above the Season of Discovery
   items, with a vendor, quest or drop in the data) must teach a recipe that CraftProfit's
   Data.lua knows, so the planner has its skill levels and source. A pattern it lacks that is not
   in tools/health/recipes_seen.txt is news; `--update-seen` marks them all as looked at.
   The same for a Forever pattern the Wowhead snapshot (tools/craftprofit/wowhead-professions.json)
   lacks: Wowhead's profession pages changed since they were collected. Wowhead refuses servers,
   so the snapshot is collected on a player's computer; one older than WOWHEAD_DAYS is news too.

4. Forever bags: a bag, quiver or pouch of WoW Forever's own that no quest, drop or vendor of the
   data gives and that is not in tools/worthit/seen.txt is news for Worth It: when players find
   its quest, it goes into EXTRA in tools/worthit/build_data.py. `--update-seen` marks them.

5. Worth It's steps: every reward quest has its "what to do" steps in Gulli-WorthIt/Tips.lua, the
   comments snapshot (tools/worthit/wowhead-comments.json) has every quest of its chain and is no
   older than COMMENT_DAYS of tools/worthit/comments.py, whose report this is.

6. BagQuests: every quest bag the BagQuests addon (pmgower/bagquests-forever) offers is in
   Worth It, or in tools/worthit/bagquests_seen.txt (tools/worthit/bagquests.py).

7. Dungeon Journal: every dungeon has its bosses in Gulli-DungeonPrep/JournalData.lua, and every
   boss of WoW Forever's own (npc id from FOREVER_NPCS) has a level: Wowhead and QuestieDB give
   none, so it goes into LEVELS in tools/dungeonprep/build_journal.py as the game shows it.

8. My BiS List: the wowtbc.gg snapshot (tools/bislist/wowtbc.json) is no older than BIS_DAYS; the
   weekly job fetches it, and when the site refuses the server it is collected on a computer.

Prints the report (empty when all is well) and writes it to --out.
"""
import ast
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
SEEN = os.path.join(HERE, "forever_seen.txt")
RECIPES_SEEN = os.path.join(HERE, "recipes_seen.txt")
CRAFT_DATA = os.path.join(ROOT, "Gulli-CraftProfit", "Data.lua")
WOWHEAD = os.path.join(ROOT, "tools", "craftprofit", "wowhead-professions.json")
WOWHEAD_DAYS = 60
BIS = os.path.join(ROOT, "tools", "bislist", "wowtbc.json")
BIS_DAYS = 21
PATTERN = re.compile(r"^(Pattern|Plans|Recipe|Formula|Schematic|Manual): ")
FOREVER_ITEMS = 245000  # SOD_ITEMS in tools/craftprofit/build_data.py ends here
JOURNAL = os.path.join(ROOT, "Gulli-DungeonPrep", "JournalData.lua")
FOREVER_NPCS = 240000   # WoW Forever's own NPCs start about here
I_NAME, I_SOURCES = 1, (2, 3, 4, 6, 14)
sys.path.insert(0, os.path.join(ROOT, "tools", "questcleaner"))

Q_ZONE = 17
N_SPAWNS, N_ZONE = 7, 9
SKIP_SECTIONS = ("prototypes", "battleground")


def load_forever(qdb):
    """Quests and NPCs of Forever, with the patch files when the shared loader is there."""
    try:
        import questie  # tools/questcleaner/questie.py
        quests, npcs, _, _ = questie.load_forever(qdb)
        return quests, npcs
    except ImportError:
        import luadata
        d = os.path.join(qdb, "data", "Forever")
        return (luadata.load(os.path.join(d, "foreverQuestDB.lua"), "questData"),
                luadata.load(os.path.join(d, "foreverNpcDB.lua"), "npcData"))


def forever_areas(qdb):
    """(symbol, area id, section) of the Forever sections of zones.lua."""
    path = os.path.join(qdb, "src", "corrections", "enum", "zones.lua")
    out, section = [], None
    for line in open(path, encoding="utf-8"):
        s = line.strip()
        m = re.match(r"--\s*Forever:\s*(.+)", s)
        if m:
            section = m.group(1).strip().rstrip(".")
            continue
        if s.startswith("--") and section and not s.startswith("-- Forever"):
            # a comment inside a section continues it; a blank line does too
            continue
        m = re.match(r"([A-Z0-9_]+)\s*=\s*(\d+)\s*,", s)
        if m and section:
            out.append((m.group(1), int(m.group(2)), section))
        elif s.startswith("}"):
            section = None
    return out


def prep_dungeons():
    src = open(os.path.join(ROOT, "tools", "dungeonprep", "build_data.py"), encoding="utf-8").read()
    tree = ast.parse(src)
    found = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            name = node.targets[0].id
            if name in ("DUNGEONS", "ENTRANCES"):
                found[name] = ast.literal_eval(node.value)
    return found["DUNGEONS"], found.get("ENTRANCES", {})


def lua_dungeons(path):
    """(area id or None, name) of every row of a module's ns.DUNGEONS."""
    text = open(path, encoding="utf-8").read()
    start = text.find("ns.DUNGEONS = {")
    if start < 0:
        return []
    body = text[start:text.find("\n}", start)]
    return [(None if a == "nil" else int(a), n)
            for a, n in re.findall(r'\{\s*"[A-Z0-9_]+"\s*,\s*(\d+|nil)\s*,\s*"([^"]*)"', body)]


def lua_keys(path, table):
    text = open(path, encoding="utf-8").read()
    start = text.find(table + " = {")
    if start < 0:
        return set()
    body = text[start:text.find("\n}", start)]
    return set(re.findall(r"\b([A-Z][A-Z0-9_]*)\s*=", body))


def norm(name):
    n = name.lower().replace("'", "").replace("’", "")
    n = re.sub(r"^(the|lower|upper)\s+", "", n)
    return re.sub(r"[^a-z0-9]+", " ", n).strip()


def check_dungeons():
    dungeons, entrances = prep_dungeons()
    lines = []
    for module in ("Bulletin",):
        rows = lua_dungeons(os.path.join(ROOT, "Gulli-" + module, "Core.lua"))
        areas = {a for a, _ in rows if a}
        names = {norm(n) for _, n in rows}
        for key, ids, name, _, _ in dungeons:
            if areas.isdisjoint(ids) and not any(norm(name) in n or n in norm(name) for n in names):
                lines.append("- %s does not list **%s** (DungeonPrep `%s`)." % (module, name, key))
    icons = lua_keys(os.path.join(ROOT, "Gulli-DungeonPrep", "Core.lua"), "ns.ICONS")
    for key, _, name, _, _ in dungeons:
        if key not in icons:
            lines.append("- DungeonPrep has no icon for **%s** (`ns.ICONS.%s`)." % (name, key))
        if key not in entrances:
            lines.append("- DungeonPrep has no entrance for **%s** (`ENTRANCES`)." % name)
    return lines, {a for _, ids, _, _, _ in dungeons for a in ids}


def read_seen(path=SEEN):
    seen = set()
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            m = re.match(r"\s*(\d+)", line)
            if m:
                seen.add(int(m.group(1)))
    return seen


def check_areas(qdb, prep_areas):
    areas = [a for a in forever_areas(qdb) if not a[2].lower().startswith(SKIP_SECTIONS)]
    seen = read_seen()
    quests, npcs = load_forever(qdb)
    q_count, n_count = {}, {}
    for q in quests.values():
        z = q.get(Q_ZONE)
        if isinstance(z, int):
            q_count[z] = q_count.get(z, 0) + 1
    for n in npcs.values():
        zs = set(n[N_SPAWNS].keys()) if isinstance(n.get(N_SPAWNS), dict) else set()
        if isinstance(n.get(N_ZONE), int):
            zs.add(n[N_ZONE])
        for z in zs:
            n_count[z] = n_count.get(z, 0) + 1
    # A subarea (CITY_OF_DALARAN_FEL_GROVE) is covered when its dungeon (CITY_OF_DALARAN) is.
    listed = [sym for sym, aid, _ in areas if aid in prep_areas]

    def covered(sym, aid):
        return aid in prep_areas or any(sym.startswith(l + "_") for l in listed)

    lines = []
    for sym, aid, section in areas:
        instance = section.lower().startswith("instance")
        if instance and not covered(sym, aid) and aid not in seen:
            lines.append("- Instance area **%s** (%d) is not in DungeonPrep: %d quests, %d NPCs."
                         % (sym, aid, q_count.get(aid, 0), n_count.get(aid, 0)))
        elif aid not in seen and not instance:
            lines.append("- New Forever area **%s** (%d, %s): %d quests, %d NPCs."
                         % (sym, aid, section, q_count.get(aid, 0), n_count.get(aid, 0)))
    return lines, areas


def forever_patterns(qdb):
    """(item id, name) of every Forever pattern that the data says someone can get."""
    import questie
    _, _, _, items = questie.load_forever(qdb)
    out = []
    for iid in sorted(items):
        row = items[iid]
        name = row.get(I_NAME) or ""
        if iid >= FOREVER_ITEMS and PATTERN.match(name) and any(row.get(k) for k in I_SOURCES):
            out.append((iid, name))
    return out


def wowhead_patterns(path=WOWHEAD):
    """The pattern items of the Wowhead snapshot and the day it was collected."""
    import json
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    out = set()
    for skill in data["skills"].values():
        out |= {r["pattern"] for r in skill["recipes"] if r.get("pattern")}
        out |= {u["item"] if isinstance(u, dict) else u for u in skill.get("unmatchedPatterns") or []}
    return out, data.get("generated", "")


def check_recipes(qdb, today=None):
    import datetime
    text = open(CRAFT_DATA, encoding="utf-8").read()
    known = {int(m) for m in re.findall(r'^\[\d+\]=\{"[vqd]",(\d+)', text, re.M)}
    wh, generated = wowhead_patterns()
    seen = read_seen(RECIPES_SEEN)
    patterns = forever_patterns(qdb)
    missing = [(iid, name) for iid, name in patterns if iid not in known or iid not in wh]
    lines = ["- **%s** (item %d)%s" % (name, iid, "" if iid in wh else ": not in the Wowhead snapshot")
             for iid, name in missing if iid not in seen]
    today = today or datetime.date.today()
    try:
        age = (today - datetime.date.fromisoformat(generated[:10])).days
    except ValueError:
        age = None
    if age is None or age > WOWHEAD_DAYS:
        lines.append("- The Wowhead profession snapshot is %s old: collect it again on a computer "
                     "(Wowhead refuses servers)." % ("%d days" % age if age is not None else "of unknown age"))
    return lines, missing


def check_bislist(today=None, path=BIS):
    """My BiS List's wowtbc.gg snapshot: the weekly job fetches it; when the site refused it for
    three weeks, it is collected on a computer (python3 tools/bislist/fetch.py)."""
    import datetime
    try:
        fetched = json.load(open(path, encoding="utf-8")).get("fetched", "")
        age = ((today or datetime.date.today()) - datetime.date.fromisoformat(fetched[:10])).days
    except (OSError, ValueError):
        age = None
    if age is not None and age <= BIS_DAYS:
        return []
    return ["- My BiS List's wowtbc.gg snapshot is %s old: run `python3 tools/bislist/fetch.py` and "
            "`python3 tools/bislist/build_data.py` on a computer and commit both files."
            % ("%d days" % age if age is not None else "of unknown age")]


def check_rewards(qdb):
    """Forever bags without a source that Worth It has not looked at: (lines, [(id, name, kind)])."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("worthit_data", os.path.join(ROOT, "tools", "worthit", "build_data.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    found = mod.unlinked(mod.questie.load_forever(qdb)[3])
    return ["- %d %s (%s)" % f for f in found], found


def check_tips():
    """What Worth It's "what to do" steps lack (tools/worthit/comments.py)."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("worthit_comments", os.path.join(ROOT, "tools", "worthit", "comments.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.report()


def check_bagquests():
    """Quest bags BagQuests offers that Worth It lacks (tools/worthit/bagquests.py)."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("worthit_bagquests", os.path.join(ROOT, "tools", "worthit", "bagquests.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.report()


def check_journal(path=JOURNAL):
    """Dungeons with no boss in the journal, and Forever bosses without a level."""
    dungeons, _ = prep_dungeons()
    text = open(path, encoding="utf-8").read()
    start = text.find("D.boss = {")
    body = text[start:text.find("\n}\n", start)] if start >= 0 else ""
    # A skull boss has level 0 on purpose (Wowhead's level 9999).
    snap = json.load(open(os.path.join(ROOT, "tools", "dungeonprep", "wowhead-dungeons.json"), encoding="utf-8"))
    skull = {str(b.get("id")) for d in (snap.get("dungeons") or {}).values()
             for b in (d.get("bosses") or []) + (d.get("rares") or []) if (b.get("minLevel") or 0) >= 9999}
    lines = []
    for key, _, name, _, _ in dungeons:
        m = re.search(r"\n%s = \{\n(.*?)\n\}," % key, body, re.S)
        rows = re.findall(r'^\{(\d+),"((?:[^"\\]|\\.)*)",[^,]*,(\d+),', m.group(1), re.M) if m else []
        if not rows:
            lines.append("- No bosses for **%s** (`%s`)." % (name, key))
            continue
        nolevel = [n for npc, n, lvl in rows if int(npc) >= FOREVER_NPCS and int(lvl) == 0
                   and npc not in skull]
        if nolevel:
            lines.append("- %s: no level for %s." % (name, ", ".join(n.replace("\\\"", "\"") for n in nolevel)))
    return lines


def main(argv):
    if not argv or argv[0].startswith("-"):
        print(__doc__)
        return 2
    qdb, out = argv[0], None
    if "--out" in argv:
        out = argv[argv.index("--out") + 1]
    dungeon_lines, prep_areas = check_dungeons()
    area_lines, areas = check_areas(qdb, prep_areas)
    recipe_lines, recipes = check_recipes(qdb)
    reward_lines, bags = check_rewards(qdb)
    tip_lines = check_tips()
    bagquest_lines = check_bagquests()
    journal_lines = check_journal()
    bis_lines = check_bislist()
    if "--update-seen" in argv:
        with open(os.path.join(ROOT, "tools", "worthit", "seen.txt"), "a", encoding="utf-8") as f:
            for iid, name, kind in bags:
                f.write("%d # %s (%s)\n" % (iid, name, kind))
        reward_lines = []
        seen = read_seen(RECIPES_SEEN)
        with open(RECIPES_SEEN, "a", encoding="utf-8") as f:
            for iid, name in recipes:
                if iid not in seen:
                    f.write("%d %s\n" % (iid, name))
        recipe_lines = []
        seen = read_seen()
        with open(SEEN, "a", encoding="utf-8") as f:
            for sym, aid, section in areas:
                if aid not in seen and not section.lower().startswith("instance"):
                    f.write("%d %s (%s)\n" % (aid, sym, section))
        area_lines = []
    report = []
    if dungeon_lines:
        report += ["### Dungeons a module lacks", ""] + dungeon_lines + [""]
    if area_lines:
        report += ["### Forever areas to look at", "",
                   "Add what a module needs (a dungeon to DungeonPrep and Bulletin; rares to "
                   "MobFinder; an attunement to Attune), then run "
                   "`python3 tools/health/forever_content.py <questiedb> --update-seen`.", ""] + area_lines + [""]
    if recipe_lines:
        report += ["### Forever recipes CraftProfit does not know", "",
                   "A new or changed Forever profession recipe. Give CraftProfit its skill levels and "
                   "source (tools/craftprofit/build_data.py), or note why not, then run "
                   "`python3 tools/health/forever_content.py <questiedb> --update-seen`.", ""] + recipe_lines + [""]
    if reward_lines:
        report += ["### Forever bags Worth It does not list", "",
                   "A bag, quiver or pouch with no quest, drop or vendor in the data. If a quest gives it, "
                   "add it to EXTRA in tools/worthit/build_data.py; else run "
                   "`python3 tools/health/forever_content.py <questiedb> --update-seen`.", ""] + reward_lines + [""]
    if bagquest_lines:
        report += ["### Quest bags BagQuests offers that Worth It lacks", "",
                   "Add the quest to EXTRA in tools/worthit/build_data.py (its Wowhead page as the source) "
                   "and its steps to Gulli-WorthIt/Tips.lua, or note why not in "
                   "tools/worthit/bagquests_seen.txt.", ""] + bagquest_lines + [""]
    if journal_lines:
        report += ["### Dungeon Journal bosses", "",
                   "Wowhead and QuestieDB have no level for WoW Forever's own bosses: put the level the "
                   "game shows into LEVELS (a boss neither source lists into EXTRA) in "
                   "tools/dungeonprep/build_journal.py and run it.", ""] + journal_lines + [""]
    if tip_lines:
        report += ["### Worth It: what to do", ""] + tip_lines + [""]
    if bis_lines:
        report += ["### My BiS List", ""] + bis_lines + [""]
    text = "\n".join(report)
    print(text or "Every module keeps up with the Forever data.")
    if out:
        open(out, "w", encoding="utf-8").write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
