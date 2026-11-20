"""Merges NPC pages read one by one on Wowhead into the snapshot wowhead-dungeons.json.

    python3 tools/dungeonprep/merge_npcs.py <npcs.json>

Wowhead files WoW Forever's own bosses under a continent or a neighbour zone, not under the
dungeon, so its zone pages miss them. Their NPC pages are read on a player's computer instead,
as {"DUNGEON": [{"id", "name", "classification", "displayId", "abilities", "drops"}]} (an entry
with "notFetched" is skipped). Only NPCs of build_journal.LEVELS are taken, those the game shows
as bosses. A boss the snapshot has gets the newer model, abilities and drops. A new one is added
(to the rares when in RARES), and its own drops join the dungeon's zone drops so build_journal
keeps them: the items AllTheThings lists in the dungeon, or uncommon or better at BOSS_PCT or more
(a world drop never comes that often). PARTS gives an encounter the model and drops of the NPC
that carries them. The input is untrusted text: it is only read as JSON, never run.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_journal as bj  # noqa: E402

SNAPSHOT = os.path.join(HERE, "wowhead-dungeons.json")
# Encounter npc -> the npc whose page has its model and loot (Izha'Rel and Tor'Rel: Tor'Rel).
PARTS = {253214: 261811}
KEEP = ("name", "tag", "classification", "displayId", "abilities", "drops")


def merge(snapshot, pages, walk):
    data = snapshot.setdefault("dungeons", {})
    added = []
    for key, npcs in pages.items():
        by_id = {bj.as_int(n.get("id")): n for n in npcs if not n.get("notFetched")}
        d = data.setdefault(key, {})
        have = {bj.as_int(b.get("id")): b for b in (d.get("bosses") or []) + (d.get("rares") or [])}
        att_loot = {i for items in ((walk.get(key) or {}).get("loot") or {}).values() for i in items}
        zone = d.setdefault("zoneDrops", [])
        zone_ids = {bj.as_int(z.get("id")) for z in zone}
        for npc in bj.LEVELS:
            page = by_id.get(npc)
            part = by_id.get(PARTS.get(npc))
            if page is None:
                continue
            entry = {k: page.get(k) for k in KEEP}
            entry["id"] = npc
            if part is not None:
                entry["displayId"] = part.get("displayId") or entry["displayId"]
                entry["drops"] = part.get("drops") or []
            if npc in have:
                have[npc].update({k: v for k, v in entry.items() if v and k != "name"})
                continue
            entry["minLevel"] = entry["maxLevel"] = None
            d.setdefault("rares" if npc in bj.RARES else "bosses", []).append(entry)
            added.append("%s %s" % (key, entry["name"]))
            for drop in entry["drops"] or []:
                did = bj.as_int(drop.get("id"))
                ownish = did in att_loot or ((drop.get("quality") or 0) >= bj.MIN_QUALITY
                                             and bj.pct_of(drop) >= bj.BOSS_PCT)
                if ownish and did not in zone_ids:
                    zone_ids.add(did)
                    zone.append({"id": did, "name": drop.get("name"), "quality": drop.get("quality"),
                                 "class": drop.get("class"), "npcId": npc})
    return added


def main(src):
    with open(SNAPSHOT, encoding="utf-8") as f:
        snapshot = json.load(f)
    with open(src, encoding="utf-8") as f:
        pages = json.load(f)
    walk = bj.read_walk(None)
    for line in merge(snapshot, pages, walk):
        print("added " + line)
    with open(SNAPSHOT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(snapshot, f, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main(sys.argv[1])
