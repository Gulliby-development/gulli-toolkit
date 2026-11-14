"""Does every module keep up with the WoW Forever data in QuestieDB?

    python3 tools/health/forever_content.py <questiedb> [--out report.md] [--update-seen]

1. Dungeons: the dungeons of DungeonPrep's generator (`DUNGEONS` in
   tools/dungeonprep/build_data.py) are the list. Bulletin and QuickChat (`ns.DUNGEONS`)
   must name each one (by area id or by name), and DungeonPrep needs its icon (`ns.ICONS`)
   and entrance (`ENTRANCES`).
2. New Forever areas: every area in a "Forever:" section of QuestieDB's zones.lua that is not
   in tools/health/forever_seen.txt is news, with how many Forever quests and NPCs it has.
   An instance area stays a finding until DungeonPrep lists it (or the dungeon it is a part
   of); `--update-seen` marks only the other areas, so add a non-dungeon instance area to
   forever_seen.txt by hand.

Prints the report (empty when all is well) and writes it to --out.
"""
import ast
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
SEEN = os.path.join(HERE, "forever_seen.txt")
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
    for module in ("Bulletin", "QuickChat"):
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


def read_seen():
    seen = set()
    if os.path.exists(SEEN):
        for line in open(SEEN, encoding="utf-8"):
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


def main(argv):
    if not argv or argv[0].startswith("-"):
        print(__doc__)
        return 2
    qdb, out = argv[0], None
    if "--out" in argv:
        out = argv[argv.index("--out") + 1]
    dungeon_lines, prep_areas = check_dungeons()
    area_lines, areas = check_areas(qdb, prep_areas)
    if "--update-seen" in argv:
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
                   "Add what a module needs (a dungeon to DungeonPrep, Bulletin and QuickChat; rares to "
                   "MobFinder; an attunement to Attune), then run "
                   "`python3 tools/health/forever_content.py <questiedb> --update-seen`.", ""] + area_lines + [""]
    text = "\n".join(report)
    print(text or "Every module keeps up with the Forever data.")
    if out:
        open(out, "w", encoding="utf-8").write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
