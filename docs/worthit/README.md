<p align="center"><img src="icon.png" alt="" width="96"></p>

<h1 align="center">Gulli-WorthIt</h1>

<p align="center"><b>The quests whose reward is worth the walk: bags, quivers and pouches, and a guide that leads you to them.</b></p>

<p align="center">
  <a href="https://github.com/Gulliby-development/gulli-toolkit/releases"><img src="https://img.shields.io/github/v/release/Gulliby-development/gulli-toolkit?filter=WorthIt-*&label=download&color=d9a441&style=for-the-badge" alt="Download the latest release"></a>
  <img src="https://img.shields.io/badge/WoW-Forever-17302d?style=for-the-badge" alt="For WoW Forever">
  <img src="https://img.shields.io/badge/languages-8-17302d?style=for-the-badge" alt="8 languages">
</p>

<p align="center"><img src="window.png" alt="The window" width="640"></p>

---

Some quests give a bag. Most players find out too late, or never. Worth It lists these quests for your character, shows how many slots each one adds to the bags you wear, and leads you to them step by step.

## Features

- **Every reward that lasts.** Bags for everyone, quivers and ammo pouches for hunters, soul bags for warlocks, profession bags, and the Cozy Sleeping Bag: sleep in it for up to +3% XP. Also the ones WoW Forever added, such as the 18-slot Hyjal Postal Satchel. Only quests your faction, race and class can do; a chain that starts in another place for each faction shows your faction's start.
- **Compared with your bags.** The window shows the bags you wear and marks the smallest one. Each reward says what it adds: `+4 over your smallest bag`. The switch **Only better than mine** hides the rest.
- **Open now, later, got.** Rewards you can go for now come first. Then the ones that wait for a level. Then the ones you already have.
- **What to do, step by step.** Each reward has two to four short steps: where the quest items are, which way to go, what to watch out for. They come from the tips of players on Wowhead, in your game's language.
- **The whole chain.** When a bag is the end of a quest chain, you see every step and where you are in it.
- **Lead to the reward.** One button puts a pin on the map: first on who gives the quest, then on the place of its work, then on who takes it back. **Lead through all** does this for every open reward, the nearest first.
- **Class quests.** A tab of its own lists every class quest of your class that gives an item: the weapons, armour, totems and robes your trainers send you for. Each one shows what you get (or the items you choose from), the whole chain and where you are in it. **Lead to the reward** and **Lead through all** work here too. The row of class icons on top shows the class quests of any other class too, so you can plan an alt or help a friend: each starts at the level it asks for, with its rewards, its chain and where it begins. Your own class is chosen when the tab opens, and only your class can be led to. Only quests WoW Forever has: raids it has not opened yet stay out.
- **The library.** WoW Forever hides library books all over the world. The **Library** tab lists every one: the books in your bags, the ones to pick up and where they lie, and the ones you handed in. On top you see how many you handed in and the four library rewards, with the books each one still needs. **Lead through the books** makes every book a stop of the guide: the nearest books at your level first, books above your level later, then who takes them back, then the reward when it is ready.
- **A goal in the library.** Click a reward (for example **Books: 10**) to make it your goal. The guide then leads only to the books you still need for it: books in your bags count, so with 3 in the bags it leads to 7. Click the reward again to drop the goal.
- **A tracker on the screen.** While the guide leads, a small panel shows what to do now and where. Through the library it shows the ten nearest stops and counts the rest. Place it with the toolkit's **Unlock frames**.
- **A note when a reward opens.** When you reach the level of a reward quest, or finish the step before it, a notice says so, once.
- **In the toolkit.** The home page shows how many slots the open rewards would add.

<p align="center"><img src="guide.png" alt="The guide and its tracker" width="640"></p>

## Install

Download `Gulli-WorthIt-<version>-forever.zip` from the [releases](https://github.com/Gulliby-development/gulli-toolkit/releases) and unpack it into `Interface/AddOns`. Then type `/reload`.

Worth It works alone. With [Gulli Toolkit](../../README.md) installed, it also shows up in the toolkit's window.

## How to use it

1. Type `/gwi`.
2. Pick a reward on the left.
3. Press **Lead to the reward** and follow the pin on your map.

For the library books, open the **Library** tab, click the reward you want as your goal, and press **Lead through the books**.

Commands: `/gwi` opens the window, `/gwi lead` leads to every open reward, `/gwi stop` ends the guide, `/gwi reset` puts the settings back.

## FAQ

<details>
<summary><b>A reward shows no number of slots.</b></summary>

The game tells a bag's size a moment after it first hears of the item. Open the window again and the number is there.
</details>

<details>
<summary><b>Where does the list of class quests come from?</b></summary>

From Wowhead's WoW Forever quest list (every class quest that gives an item), joined with the quest data of QuestieDB for the chains and the places. Quests of raids WoW Forever has not opened yet (Zul'Gurub, Ahn'Qiraj, Molten Core, Blackwing Lair, Naxxramas) are left out until they open.
</details>

<details>
<summary><b>Where do the steps under "What to do" come from?</b></summary>

We write them by hand from the quest text and from the best comments of players on Wowhead's WoW Forever pages. We read the new comments again from time to time. Names of NPCs, quests and items stay in English.
</details>

<details>
<summary><b>Where does the list of library books come from?</b></summary>

From the WoW Forever quest data of QuestieDB: every quest that gives a book back to a librarian (Garion Wendell in Stormwind, Owen Thadd in Undercity) or, for the last books, to a mage trainer. A book counts as found while it is in your bags, and as done once its quest is handed in.
</details>

<details>
<summary><b>The map pin did not appear.</b></summary>

Some quests start from an item or inside a dungeon. These places are on no map, so there is no pin. The window still says who or what starts the quest.
</details>

<details>
<summary><b>I know a quest with a bag that is not in the list.</b></summary>

Tell us on GitHub. The list comes from the QuestieDB data, and new WoW Forever quests get there with a delay.
</details>

<details>
<summary><b>Does it take or hand in quests for me?</b></summary>

No. It only shows the way. You talk to the people yourself.
</details>

<details>
<summary><b>Is it tested in the game?</b></summary>

Not yet in WoW Forever itself. It is tested on a fake game client. If something does not work, tell us on GitHub.
</details>

<details>
<summary><b>Where does the data come from?</b></summary>

`Data.lua` is built by `tools/worthit/build_data.py` from the [QuestieDB](https://github.com/Questie/QuestieDB) data for WoW Forever (GPLv3). Bag sizes are read from the game.
</details>

<details>
<summary><b>A bag quest is missing.</b></summary>

Some quests give a bag, but the game data does not say so. We add those by hand, and every day we compare the list with the bag quests that other players found. Tell us in an issue if you know one we lack.
</details>
