"""The QuestieDB Forever data with its Forever corrections, without running Lua.

    quests, npcs, objects, items = questie.load_forever(<questiedb-checkout>)

`data/Forever/*DB.lua` holds only the records QuestieDB took over from Classic. Everything
WoW Forever added (Riverglades, Zephras Isle, Krol'dok Stronghold, Manor Mistmantle, ...)
lives in its corrections, so a generator that reads only the data files never sees it.
This applies them in QuestieDB's static order (docs/forever-delta-base.md): raw base ->
generated delta-base -> generated traces -> authored Forever fixes. The Classic corrections
that come before the delta-base and the dynamic corrections are left out.

Each table is id -> {field index -> value}, the same shape as `luadata.load`.
"""
import os
import re

import luadata

TOKEN = re.compile(r"""
    \s+|--\[(?P<eq0>=*)\[.*?\](?P=eq0)\]|--[^\n]*
  | (?P<num>0x[0-9a-fA-F]+|\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)
  | (?P<str>"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|\[(?P<eq>=*)\[.*?\](?P=eq)\])
  | (?P<name>[A-Za-z_]\w*(?:[.:][A-Za-z_]\w*)*)
  | (?P<sym>\.\.|==|~=|<=|>=|[{}\[\]=,;()+\-*/#<>])
""", re.X | re.S)

# Fields whose value is a set of groups (giver kinds, objective kinds, zones): an _add or
# _remove works on the rows inside each group it names. Every other table field is one list.
GROUPED = {"startedBy", "finishedBy", "objectives", "spawns", "waypoints"}
# Objective group 4 (a reputation pair) is one value, not a list of rows.
ATOMIC_GROUPS = {("objectives", 4)}

PROVIDERS = [
    ("generated/foreverBase%s.lua", {"quest": "Quest", "npc": "Npc", "object": "Object", "item": "Item"}),
    ("traces/forever%s.lua", {"quest": "QuestTraces", "npc": "NpcTraces", "object": "ObjectTraces",
                              "item": "ItemTraces"}),
    ("traces/forever%s.lua", {"quest": "QuestRelationTraces"}),
    ("forever%s.lua", {"quest": "QuestFixes", "npc": "NPCFixes", "object": "ObjectFixes", "item": "ItemFixes"}),
]
FILES = {"quest": "Quest", "npc": "Npc", "object": "Object", "item": "Item"}


def _tokens(text, start):
    out = []
    for m in TOKEN.finditer(text, start):
        for k in ("num", "str", "name", "sym"):
            if m.group(k) is not None:
                out.append((k, m.group(k)))
                break
    return out


def _unquote(s):
    if s.startswith("["):
        return re.sub(r"^\[=*\[\n?|\]=*\]$", "", s)
    return luadata._unquote(s)


class _Parser:
    def __init__(self, toks, resolve):
        self.t, self.i, self.resolve = toks, 0, resolve

    def peek(self):
        return self.t[self.i][1] if self.i < len(self.t) else None

    def expr(self):
        v = self.prim()
        while self.peek() in ("+", "-", "*", ".."):
            op = self.t[self.i][1]
            self.i += 1
            w = self.prim()
            try:
                if op == "+":
                    v = v + w
                elif op == "-":
                    v = v - w
                elif op == "*":
                    v = v * w
                else:
                    v = str(v) + str(w)
            except TypeError:
                v = None
        return v

    def prim(self):
        kind, v = self.t[self.i]
        self.i += 1
        if kind == "sym" and v == "-":
            x = self.prim()
            return -x if isinstance(x, (int, float)) else None
        if kind == "sym" and v == "(":
            x = self.expr()
            self.i += 1  # )
            return x
        if kind == "num":
            if v.startswith("0x"):
                return int(v, 16)
            return float(v) if ("." in v or "e" in v.lower()) else int(v)
        if kind == "str":
            return _unquote(v)
        if kind == "name":
            if v == "nil":
                return None
            if v in ("true", "false"):
                return v == "true"
            if self.peek() == "(":  # a call such as l10n("text"): keep its first argument
                self.i += 1
                args = []
                while self.peek() != ")":
                    args.append(self.expr())
                    if self.peek() == ",":
                        self.i += 1
                self.i += 1
                return args[0] if args and isinstance(args[0], str) else None
            return self.resolve(v)
        if v == "{":
            t, n = {}, 0
            while self.peek() != "}":
                if self.peek() == "[":
                    self.i += 1
                    k = self.expr()
                    self.i += 2  # ] =
                    t[k] = self.expr()
                elif self.t[self.i][0] == "name" and self.t[self.i + 1][1] == "=":
                    k = self.t[self.i][1]
                    self.i += 2
                    t[k] = self.expr()
                else:
                    n += 1
                    x = self.expr()
                    if x is not None:
                        t[n] = x
                if self.peek() in (",", ";"):
                    self.i += 1
            self.i += 1
            return t
        raise ValueError("unexpected %r" % v)


def _read(root, rel):
    with open(os.path.join(root, rel), encoding="utf-8") as f:
        return f.read()


def _field_keys(root):
    keys = {}
    for kind, f in FILES.items():
        src = _read(root, "data/Forever/forever%sDB.lua" % f)
        m = re.search(r"QuestieDB\.%sKeys\s*=\s*\{(.*?)\n\}" % kind, src, re.S)
        keys[kind] = {k: int(v) for k, v in re.findall(r"\['(\w+)'\]\s*=\s*(\d+)", m.group(1))}
    return keys


def _enums(root):
    """zoneIDs, raceIDs (Forever), classIDs and sortKeys by name."""
    zones = {k: int(v) for k, v in re.findall(r"^\s*(\w+)\s*=\s*(-?\d+)", _read(root, "src/corrections/enum/zones.lua"), re.M)}
    exp = _read(root, "src/corrections/enum/expansions.lua")
    mask = {int(k): int(v) for k, v in re.findall(r"\[(\d+)\]\s*=\s*(\d+),\s*--", exp)}
    alliance = mask[1] + mask[3] + mask[4] + mask[7]
    horde = mask[2] + mask[5] + mask[6] + mask[8]
    races = {"NONE": 0}
    block = exp[exp.index("Forever = {"):]
    block = block[block.index("raceKeys"):]
    block = block[:block.index("}")]
    for name, body in re.findall(r"(\w+)\s*=\s*([^,\n]+),", block):
        total = 0
        for part in body.split("+"):
            part = part.strip()
            m = re.match(r"raceMaskById\[(\d+)\]", part)
            if m:
                total += mask[int(m.group(1))]
            elif part == "classicAlliance":
                total += alliance
            elif part == "classicHorde":
                total += horde
            elif part.isdigit():
                total += int(part)
        races[name] = total
    classic = exp[exp.index("Classic = {"):]
    classic = classic[classic.index("classKeys"):]
    classic = classic[:classic.index("}")]
    classes = {k: int(v) for k, v in re.findall(r"(\w+)\s*=\s*(\d+)", classic)}
    q = _read(root, "src/corrections/enum/quests.lua")
    sort_block = q[q.index("constants.sortKeys"):]
    sort_block = sort_block[:sort_block.index("\n}")]
    sorts = {k: int(v) for k, v in re.findall(r"(\w+)\s*=\s*(-?\d+)", sort_block)}
    return {"zoneIDs": zones, "raceIDs": races, "classIDs": classes, "sortKeys": sorts}


def _seq(t):
    return [t[k] for k in sorted(t)] if isinstance(t, dict) else []


def _append(cur, values):
    """Append the values not already there, after the surviving ones (a 1..n dict)."""
    items = [v for v in _seq(cur)]
    for v in _seq(values):
        if v not in items:
            items.append(v)
    return {i + 1: v for i, v in enumerate(items)}


def _remove(cur, values):
    gone = _seq(values)
    items = [v for v in _seq(cur) if v not in gone]
    return {i + 1: v for i, v in enumerate(items)}


def _apply(table, fixes, names):
    for rid, fix in fixes.items():
        if not isinstance(fix, dict):
            continue
        rec = table.setdefault(rid, {})
        ops = []
        for k, v in fix.items():
            if isinstance(k, str) and (k.endswith("_add") or k.endswith("_remove")):
                ops.append((k, v))
            elif isinstance(k, int):
                rec[k] = v
        # Removals before additions, as QuestieDB orders them.
        ops.sort(key=lambda kv: 0 if kv[0].endswith("_remove") else 1)
        for k, v in ops:
            field, _, op = k.rpartition("_")
            idx = names.get(field)
            if idx is None or not isinstance(v, dict):
                continue
            fn = _append if op == "add" else _remove
            if field in GROUPED:
                cur = rec.get(idx) if isinstance(rec.get(idx), dict) else {}
                for g, rows in v.items():
                    if (field, g) in ATOMIC_GROUPS:
                        if op == "add":
                            cur[g] = rows
                        elif cur.get(g) == rows:
                            del cur[g]
                    else:
                        cur[g] = fn(cur.get(g) if isinstance(cur.get(g), dict) else {}, rows)
                rec[idx] = cur
            else:
                rec[idx] = fn(rec.get(idx) if isinstance(rec.get(idx), dict) else {}, v)


def _provider(root, rel, kind, keys, enums):
    src = _read(root, rel)
    m = re.search(r"function \w+:Load\(\)", src)
    start = src.index("return {", m.end()) + len("return ")
    names = keys[kind]

    def resolve(name):
        head, _, tail = name.rpartition(".")
        if head.endswith("Keys") and head[:-4] in keys:
            k = keys[head[:-4]]
            if tail in k:
                return k[tail]
            return tail  # an operation alias such as startedBy_add
        if head in enums:
            return enums[head].get(tail)
        return None

    toks = _tokens(src, start)
    fixes = _Parser(toks, resolve).expr()
    return fixes, names


def load_forever(root):
    d = os.path.join(root, "data", "Forever")
    tables = {
        "quest": luadata.load(os.path.join(d, "foreverQuestDB.lua"), "questData"),
        "npc": luadata.load(os.path.join(d, "foreverNpcDB.lua"), "npcData"),
        "object": luadata.load(os.path.join(d, "foreverObjectDB.lua"), "objectData"),
        "item": luadata.load(os.path.join(d, "foreverItemDB.lua"), "itemData"),
    }
    keys = _field_keys(root)
    enums = _enums(root)
    base = os.path.join("src", "corrections", "Forever")
    for pattern, files in PROVIDERS:
        for kind in ("quest", "npc", "object", "item"):
            if kind not in files:
                continue
            rel = os.path.join(base, pattern % files[kind])
            if not os.path.exists(os.path.join(root, rel)):
                continue
            fixes, names = _provider(root, rel, kind, keys, enums)
            _apply(tables[kind], fixes, names)
    return tables["quest"], tables["npc"], tables["object"], tables["item"]
