<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/toolkit/wordmark-dark.png">
    <img src="docs/toolkit/wordmark-light.png" alt="Gulli Toolkit" width="560">
  </picture>
</p>

<p align="center"><b>Small, handy addons for WoW Forever in one set. Install the toolkit and get them all, or take only the ones you like.</b></p>

<p align="center">
  <a href="../../releases"><img src="https://img.shields.io/github/v/release/Gulliby-development/gulli-toolkit?label=download&color=d9a441&style=for-the-badge" alt="Download"></a>
  <img src="https://img.shields.io/badge/WoW-Forever-17302d?style=for-the-badge" alt="For WoW Forever">
  <img src="https://img.shields.io/badge/languages-8-17302d?style=for-the-badge" alt="8 languages">
</p>

---

<p align="center"><img src="docs/toolkit/preview.png" alt="Gulli Toolkit" width="860"></p>

## The modules

| Module | What it does | Open it |
|---|---|---|
| [Quest Cleaner](docs/questcleaner/README.md) | Abandons low-level quests and deletes leftover quest items from your bags. You see a list before anything goes. | `/gqc` |
| [Mob Finder](docs/mobfinder/README.md) | Plays a sound when a mob you look for shows its nameplate. | `/gmf` |
| [Group Buffs](docs/groupbuffs/README.md) | Casts the buffs your group is missing, one press at a time, also in combat. | `/ggb` |
| [Bulletin Board](docs/bulletin/README.md) | Sorts trade and group chat into a board: groups by dungeon, selling, buying, crafting, guilds. | `/gbul` |
| [Party Quests](docs/partyquests/README.md) | Shows which quests your group shares and who still needs one. Share in one tap. | `/gpq` |
| [Instance Limit](docs/instancelimit/README.md) | Counts your dungeon entries this hour and today, and shows when the next one is free. | `/gil` |
| [Attunements](docs/attune/README.md) | Raid attunements and dungeon keys for all your characters, with the next step and where it starts. | `/gat` |
| [Bag Space](docs/bagspace/README.md) | Frees the bag slots you ask for: merges stacks, sells or deletes the cheapest junk. | `/gbs` |
| [Dungeon Prep](docs/dungeonprep/README.md) | A dungeon's quests you have and can still take, plus a checklist before you go. | `/gdp` |
| [Quick Chat](docs/quickchat/README.md) | Phrases on big buttons, a group message from a quest, whispers you missed. | `/gqk` |
| [Chores](docs/chores/README.md) | A to-do list for each character: cooldowns, mail, trainer, rested XP, repairs. | `/gch` |
| [Restock](docs/restock/README.md) | Keeps reagents, ammo, food and water at your amount and buys them at a vendor. | `/grs` |
| [Merchant](docs/merchant/README.md) | Sells gray items and repairs at a vendor, with guild money when allowed. | `/gmc` |
| [Mail](docs/mail/README.md) | Take all from the mailbox, and your characters and recent recipients as names to tap. | `/gml` |
| [Auto Quest](docs/autoquest/README.md) | Takes and hands in quests. Rewards with a choice stay your pick. | `/gaq` |
| [Tooltip](docs/tooltip/README.md) | Full stack price, the quests that need an item, item and NPC ids. | `/gtt` |
| [XP](docs/xp/README.md) | XP per hour, time and kills to the next level. | `/gxp` |
| [Loot](docs/loot/README.md) | Rolls Need, Greed or Pass by your rules for each quality and item. | `/glt` |
| [Social](docs/social/README.md) | Invite on a whispered word, accept friends, turn away strangers, duels and guild invites. | `/gso` |
| [Reminders](docs/reminders/README.md) | Icons for missing class buffs, poisons, ammo and soul shards. | `/grm` |
| [Craft Profit](docs/craftprofit/README.md) | Profitable crafts and the cheapest way to level a profession, drawn as a route: where to buy, what to craft, where to sell. | `/gcp` |

## Features

- **One window for all.** Type `/gulli`, or click the toolkit in the addon button on the minimap. Modules are sorted into groups (Quests, Group & Dungeons, Bags & Vendors, Chat & Social, Info & Alerts), each with how many are on. Pick a module to see what it does, its command and its main switches, and press **Open**.
- **Search.** Type in the search box to find a module by name, what it does or its command. **All**, **On** and **Off** show only the modules you want.
- **Switch off what you do not need.** Flip a module's switch in `/gulli` and press **Reload**: the game does not load it at all. Modules that act on their own (Merchant, Auto Quest, Loot, Social) also have a switch for each thing they do.
- **Each module works alone.** You do not need the toolkit to use a module. With the toolkit, they come together in one place.
- **Install once.** In Runeloader, install **Gulli Toolkit** and every module comes with it. Remove the ones you do not want; the rest keeps working.
- **Protected items.** In `/gulli`, press **Protected items** and drop an item there (or type `/gulli protect` and shift-click it). No module ever sells, deletes or moves it.
- **Recent news.** The toolkit window shows the last messages from the modules, such as how many dungeon entries are left or what waits on your other characters.
- **One look.** Every module has the same flat dark window in your class colour, in the style of ElvUI: settings in cards, the main button at the bottom right, and an icon from the game next to each setting, timer and spell, so you find things at a glance.
- **Made for handhelds.** Big buttons and switches, so it works with a mouse and with touch on WoW Forever for Android. The window shrinks to fit a small screen, and **-** and **+** make it smaller or bigger.
- **Your language.** English, German, Spanish, French, Polish, Portuguese, Russian and Chinese. It follows the language of your game.

## Install

**With [Runeloader](https://github.com/Gulliby-development/runeloader)** (Android): open **Browse**, search for **Gulli Toolkit** and tap **Install**. You get the toolkit and every module. In **Library**, open the toolkit to see its modules and remove the ones you do not want.

**Everything in one zip:** download [`Gulli-Toolkit-All.zip`](../../releases/download/bundle/Gulli-Toolkit-All.zip) and unpack it into the game's `Interface/AddOns` folder. It holds the newest version of the toolkit and of every module, and it is rebuilt after each release.

**By hand, one by one:**

1. **Download** the zips you want from the [releases](../../releases): `Gulli-Toolkit-<version>-forever.zip` for the toolkit, `Gulli-<Module>-<version>-forever.zip` for each module.
2. **Unpack** each one into the game's `Interface/AddOns` folder. You get folders like `Interface/AddOns/Gulli-Toolkit` and `Interface/AddOns/Gulli-QuestCleaner`.
3. **Restart** the game, or type `/reload`.

## How to use it

1. Type `/gulli`.
2. Pick a group on the left, or type in **Search modules**.
3. Click a module to see it on the right, and press **Open** (or **>** in its row). Or use the module's own command, such as `/gqc`.
4. To switch a module off, flip its switch and press **Reload**.

`/gulli questcleaner` opens a module directly.

## FAQ

<details>
<summary><b>Do I need the toolkit?</b></summary>

No. Each module is a normal addon and works alone. The toolkit only puts them in one window.
</details>

<details>
<summary><b>A module says "Not installed"</b></summary>

The toolkit knows about it, but it is not in your AddOns folder. Install it with Runeloader or from the releases.
</details>

<details>
<summary><b>I switched a module off, but it is still there</b></summary>

The game turns addons on and off only when the interface loads. Press **Reload** in the toolkit window, or type `/reload`.
</details>

## For developers

<details>
<summary><b>How the repository is built</b></summary>

Each top-level `Gulli-<Name>` folder is one addon: `Gulli-Toolkit` is the core, the others are modules. Each folder is released on its own tag: the core on `Core-v<version>`, a module on `<Name>-v<version>`. The [Runeloader index](https://github.com/Gulliby-development/runeloader-index) reads them every night and lists the repository as one package: the core plus one entry per module.

A module registers with the toolkit when it is loaded:

```lua
if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({ key = "QuestCleaner", open = function() ns.Toggle() end,
                            icon = "Interface\\AddOns\\Gulli-QuestCleaner\\icon", slash = "/gqc",
                            -- optional: a hub group and switches the hub shows beside the module
                            category = "Quests",
                            options = { { label = "...", get = function() ... end, set = function(on) ... end } } })
end
```

Its TOC has `## OptionalDeps: Gulli-Toolkit` and `## X-Gulli-Module: <Name>`. [AGENTS.md](AGENTS.md) has the full contract.
</details>

<details>
<summary><b>Releases</b></summary>

Bump `## Version` in the folder's TOC and run the **Release** workflow from the Actions tab with `module` set to `Core` or the module name.
</details>

<details>
<summary><b>Tests</b></summary>

Each addon has its tests on a small fake WoW client:

```sh
for t in tests/*/test.lua; do lua5.1 "$t"; done
```
</details>

---

<p align="center">
  <sub>Gulli Toolkit is a fan project. It is not affiliated with Blizzard Entertainment.<br>
  It is free software under the <a href="LICENSE">GPLv3</a>.</sub>
</p>
