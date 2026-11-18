<p align="center"><img src="icon.png" alt="" width="96"></p>

<h1 align="center">Gulli-Tooltip</h1>

<p align="center"><b>Adds the quests that need an item, how many you hold, prices, where it drops, and ids to tooltips.</b></p>

<p align="center">
  <a href="https://github.com/Gulliby-development/gulli-toolkit/releases"><img src="https://img.shields.io/github/v/release/Gulliby-development/gulli-toolkit?filter=Tooltip-*&label=download&color=d9a441&style=for-the-badge" alt="Download the latest release"></a>
  <img src="https://img.shields.io/badge/WoW-Forever-17302d?style=for-the-badge" alt="For WoW Forever">
  <img src="https://img.shields.io/badge/languages-8-17302d?style=for-the-badge" alt="8 languages">
</p>

<p align="center"><img src="window.png" alt="The window" width="560"></p>

---

Is this worth keeping? Which quest wanted it? Gulli Tooltip puts the answer in the tooltip.

## Features

- **One tidy block.** A gold line sets the Gulli lines apart from the game's and other addons' lines. Inside, thin lines split the groups, and each group starts with a small game icon. The lines of the other Gulli modules (junk, Quest Cleaner, Party Quests, Craft Profit, Attune) stand in the same block.
- **Colours with one meaning.** Gold is a quest or a boss, green is good news, orange is an item that will go, money shows in gold, silver and copper colours, your characters in their class colours.
- **Protected** on items you protected in the Gulli Toolkit.
- **Quests that need it.** "Wolves 3/10" on a Wolf Pelt, from the quests in your log. The count turns green with a check mark when your bags hold enough. Only the whole name counts: a Large Wolf Pelt is not a Wolf Pelt.
- **You have:** how many you hold in all, then you and each other character with bags and bank. The other characters come from Gulli Chores.
- **Stack price.** What a full stack sells for at a vendor.
- **Auction price of a full stack** from Auctionator, when you have it. It also says when a vendor pays more than the auction house after its cut. Off by default, because Auctionator already shows the price of one.
- **Professions** that use the item, from Gulli Craft Profit. Off by default, because the game already says "Crafting Reagent".
- **Where it drops:** the boss, the dungeon and the chance, from the Dungeon Journal. It also says when the item is on your wish list.
- **Ids** of items, NPCs and spells, for guides and bug reports. Off by default.
- **Look:** prices and ids only while you hold **Shift**, the border in the item's quality colour, the tooltip at the cursor.
- The window shows an **example tooltip** with only the lines you switched on.

## Install

**With [Runeloader](https://github.com/Gulliby-development/runeloader)** (Android): install **Gulli Toolkit**. Tooltip comes with it.

**By hand:** download `Gulli-Tooltip-<version>-forever.zip` from the [releases](https://github.com/Gulliby-development/gulli-toolkit/releases) and unpack it into `Interface/AddOns`. Then type `/reload`.

## How to use it

1. Hover over an item or an NPC, or tap it on a touch screen.
2. Type `/gtt` (or open it from `/gulli`) to choose the lines. The example on the right shows the result.

## FAQ

<details>
<summary><b>The quest line is missing</b></summary>

It reads the objectives in your quest log. A quest that does not name the item in its objectives is not shown.
</details>

<details>
<summary><b>My other characters are missing</b></summary>

Your own bags and bank come from the game. The other characters come from what Gulli Chores saved. Log in once on each character with Chores on, and open the bank there.
</details>

<details>
<summary><b>Where is the quest line on monsters?</b></summary>

The game itself shows the kill objectives on a monster, so Gulli Tooltip no longer repeats them.
</details>

<details>
<summary><b>Is it tested in the game?</b></summary>

Not yet in WoW Forever itself. It is tested on a fake game client. If something does not work, tell us on GitHub.
</details>

---

<p align="center"><sub>Part of <a href="../../README.md">Gulli Toolkit</a>. A fan project, not affiliated with Blizzard Entertainment. Free software under the <a href="../../LICENSE">GPLv3</a>.</sub></p>
