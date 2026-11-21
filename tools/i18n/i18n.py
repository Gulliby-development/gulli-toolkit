"""Translations of the English texts that come from game data (guides, QuestieDB) rather than
from a module's Locales.lua: every text a player reads is in all eight languages.

Each domain (such as `dungeonprep-tips`) has its cache `tools/i18n/<domain>.json`:
{ "<English text>": { "de": "...", "es": "...", ... } }. A generator calls `sync(domain, texts)`,
which adds the new English texts (without translations), drops the ones no longer used and
returns the cache (a text the game has in some languages lists the others as `_need`); it writes what it has, and a text with no translation yet shows in English.

    python3 tools/i18n/i18n.py pending            # untranslated texts per domain and language
    python3 tools/i18n/i18n.py export <domain> <lang> <out.json>   # the texts to translate
    python3 tools/i18n/i18n.py merge <domain> <lang> <in.json>     # { English: translation }

Names (NPCs, quests, items, places) stay in English inside a translation, as the game data
names them; numbers, levels and coordinates stay as they are.
"""
import json
import os
import sys

LANGS = ["de", "es", "fr", "pl", "pt", "ru", "zh"]
DIR = os.path.dirname(os.path.abspath(__file__))


def path(domain):
    return os.path.join(DIR, domain + ".json")


def load(domain):
    try:
        with open(path(domain), encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def save(domain, data):
    with open(path(domain), "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=1, sort_keys=True)
        f.write("\n")


def sync(domain, texts):
    """Keeps the cache to `texts` (English) and returns it. `texts` is a list (every language
    needs it) or {text: [languages that need it]}, for a text the game already has in the
    others; those are kept as `_need`."""
    old = load(domain)
    if not isinstance(texts, dict):
        texts = {t: LANGS for t in texts}
    data = {}
    for t, need in texts.items():
        if not t or not need:
            continue
        entry = {l: v for l, v in (old.get(t) or {}).items() if l in LANGS and v}
        if sorted(need) != sorted(LANGS):
            entry["_need"] = sorted(need)
        data[t] = entry
    save(domain, data)
    return data


def needs(entry, lang):
    return lang in entry.get("_need", LANGS)


def pending(domain):
    """{lang: [English texts without a translation]}."""
    data = load(domain)
    return {l: sorted(t for t, tr in data.items() if needs(tr, l) and not tr.get(l)) for l in LANGS}


def domains():
    return sorted(n[:-5] for n in os.listdir(DIR) if n.endswith(".json"))


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "pending"
    if cmd == "pending":
        total = 0
        for d in domains():
            for l, texts in pending(d).items():
                if texts:
                    total += len(texts)
                    print("%s %s: %d untranslated" % (d, l, len(texts)))
        print("%d untranslated" % total)
        return 1 if total and "--strict" in argv else 0
    if cmd == "export":
        d, l, out = argv[2], argv[3], argv[4]
        with open(out, "w", encoding="utf-8") as f:
            json.dump({t: "" for t in pending(d)[l]}, f, ensure_ascii=False, indent=1)
        return 0
    if cmd == "merge":
        d, l, src = argv[2], argv[3], argv[4]
        data = load(d)
        with open(src, encoding="utf-8") as f:
            got = json.load(f)
        n = 0
        for t, v in got.items():
            if t in data and v:
                data[t][l] = v
                n += 1
        save(d, data)
        print("%s %s: %d merged" % (d, l, n))
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
