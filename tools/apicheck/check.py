"""Check the addons against the game client's own API documentation.

Usage: python3 tools/apicheck/check.py <Blizzard_APIDocumentationGenerated folder>

It fails when
- an event is registered with a plain RegisterEvent (or compared as `event == "X"`)
  and the client does not have it; a classic-only event must go through a safe
  register (a `Listen`-style helper with C_EventUtils.IsEventValid and pcall),
- a `C_Namespace.Function` the client documentation lacks is called without a check
  (the documentation misses a few real functions, so a checked call passes),
- a classic-only global (CLASSIC_ONLY) is called in a file that never checks it
  (`if X then`, `X and X(`, `elseif X then`).

Exceptions that were looked at go into tools/apicheck/allow.txt.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

# Old global functions the retail client dropped or may drop; each use needs a check.
CLASSIC_ONLY = [
    "GetMerchantItemInfo", "GetItemInfo", "GetItemInfoInstant", "GetItemIcon", "GetItemCount",
    "GetItemQualityColor", "GetContainerNumSlots", "GetContainerItemInfo", "GetContainerItemLink",
    "GetContainerItemID", "PickupContainerItem", "UseContainerItem", "UnitBuff", "UnitDebuff",
    "UnitAura", "GetSpellInfo", "GetSpellTexture", "GetSpellCooldown", "IsSpellKnown",
    "GetGuildRosterInfo", "GetNumQuestLogEntries", "GetQuestLogTitle", "SelectQuestLogEntry",
    "AbandonQuest", "SetAbandonQuest", "GetQuestLogLeaderBoard", "GetAddOnInfo", "IsAddOnLoaded",
    "EnableAddOn", "DisableAddOn", "GetAddOnMetadata", "GetNumAddOns", "GetTradeSkillInfo",
    "GetNumTradeSkills", "GetTradeSkillLine", "GetCraftInfo", "QueryAuctionItems",
    "GetAuctionItemInfo", "GetNumAuctionItems", "GetQuestLogIndexByID", "IsQuestComplete",
]

EVENT_RE = r'[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+'


def load_docs(folder):
    functions, events = set(), set()
    for name in os.listdir(folder):
        if not name.endswith(".lua"):
            continue
        text = open(os.path.join(folder, name), encoding="utf-8", errors="replace").read()
        m = re.search(r'^\tNamespace = "([^"]+)"', text, re.M)
        ns = m.group(1) if m else None
        section = None
        for line in text.splitlines():
            s = re.match(r'^\t(\w+) =\s*$', line)
            if s:
                section = s.group(1)
                continue
            if section == "Functions":
                f = re.match(r'^\t\t\tName = "(\w+)"', line)
                if f:
                    functions.add(ns + "." + f.group(1) if ns else f.group(1))
            elif section == "Events":
                e = re.match(r'^\t\t\tLiteralName = "(\w+)"', line)
                if e:
                    events.add(e.group(1))
    return functions, events


def load_allow():
    allow = set()
    path = os.path.join(HERE, "allow.txt")
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            line = line.split("#", 1)[0].strip()
            if line:
                allow.add(line)
    return allow


def strip_comments(text):
    text = re.sub(r'--\[(=*)\[.*?\]\1\]', lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    return re.sub(r'--[^\n]*', "", text)


def addon_files():
    for d in sorted(os.listdir(ROOT)):
        if d.startswith("Gulli-") and os.path.isdir(os.path.join(ROOT, d)):
            for f in sorted(os.listdir(os.path.join(ROOT, d))):
                if f.endswith(".lua") and f not in ("Locales.lua", "Data.lua"):
                    yield os.path.join(d, f)


def events_in(text):
    """(event, line, safe) for every event the file registers or compares."""
    out = []
    lines = text.splitlines()
    for i, line in enumerate(lines, 1):
        for m in re.finditer(r'Register(?:Unit)?Event\(\s*"(' + EVENT_RE + ')"', line):
            out.append((m.group(1), i, False))
        for m in re.finditer(r'\b(?:event|ev|e|evt)\s*[~=]=\s*"(' + EVENT_RE + ')"', line):
            out.append((m.group(1), i, None))
    # literal lists: `for _, e in ipairs({ ... }) do x:RegisterEvent(e)` and `Listen(f, { ... })`
    for m in re.finditer(r'(ipairs|Listen\s*\(\s*[\w.]+\s*,)\s*\(?\s*\{([^{}]*)\}', text):
        after = text[m.end():m.end() + 160].split(" end", 1)[0]
        safe = m.group(1).startswith("Listen")
        if not safe and "RegisterEvent" not in after and "RegisterUnitEvent" not in after:
            continue
        line = text.count("\n", 0, m.start()) + 1
        for e in re.findall(r'"(' + EVENT_RE + ')"', m.group(2)):
            out.append((e, line, safe))
    # named lists: `local events = { ... }` later passed to RegisterEvent or Listen
    for m in re.finditer(r'local\s+(\w+)\s*=\s*\{([^{}]*)\}', text):
        name = m.group(1)
        if not re.search(r'ipairs\(\s*' + name + r'\s*\)\s*do[^\n]*Register(?:Unit)?Event', text) and \
           not re.search(r'Listen\(\s*[\w.]+\s*,\s*' + name + r'\s*\)', text):
            continue
        safe = bool(re.search(r'Listen\(\s*[\w.]+\s*,\s*' + name + r'\s*\)', text))
        line = text.count("\n", 0, m.start()) + 1
        for e in re.findall(r'"(' + EVENT_RE + ')"', m.group(2)):
            out.append((e, line, safe))
    return out


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    functions, events = load_docs(sys.argv[1])
    if len(functions) < 1000 or len(events) < 500:
        print("The API documentation looks incomplete: %d functions, %d events." % (len(functions), len(events)))
        return 2
    allow = load_allow()
    problems = []
    for path in addon_files():
        text = strip_comments(open(os.path.join(ROOT, path), encoding="utf-8").read())
        found = events_in(text)
        listened = set(e for e, _, safe in found if safe)
        for e, line, safe in found:
            if safe is None:
                # a comparison is fine for an event the file registers safely; else it is a typo
                safe = e in listened
            if e not in events and not safe and e not in allow:
                problems.append("%s:%d: event %s is not in the client; register it through a safe Listen" % (path, line, e))
        for m in re.finditer(r'\b(C_\w+)\.(\w+)', text):
            name = m.group(1) + "." + m.group(2)
            if name in functions or name in allow:
                continue
            # the documentation misses a few real functions; a checked call is fine
            q = re.escape(name)
            if re.search(r'(?:and|if|elseif|not)\s+' + q + r'\b|\b' + q + r'\s+(?:and|then|or)\b', text):
                continue
            if True:
                line = text.count("\n", 0, m.start()) + 1
                problems.append("%s:%d: %s is not in the client" % (path, line, name))
        for g in CLASSIC_ONLY:
            if g in functions:
                continue
            calls = [m for m in re.finditer(r'(?<![\w.:])' + g + r'\s*\(', text)]
            if not calls:
                continue
            guarded = re.search(r'(?:if|elseif|and|or|not)\s+' + g + r'\b', text) or \
                      re.search(r'\b' + g + r'\s+(?:and|then)\b', text)
            if not guarded and g not in allow:
                line = text.count("\n", 0, calls[0].start()) + 1
                problems.append("%s:%d: %s is not in the retail client; call it only after a check (elseif %s then)" % (path, line, g, g))
    seen = set()
    for p in problems:
        if p not in seen:
            seen.add(p)
            print("::error::" + p if os.environ.get("GITHUB_ACTIONS") else p)
    print("Checked against %d functions and %d events: %d problems." % (len(functions), len(events), len(seen)))
    return 1 if seen else 0


if __name__ == "__main__":
    sys.exit(main())
