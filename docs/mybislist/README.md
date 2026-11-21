<p align="center"><img src="icon.png" alt="" width="96"></p>

<h1 align="center">Gulli-MyBisList</h1>

<p align="center"><b>The best gear for your class, spec and level, slot by slot, against what you wear.</b></p>

<p align="center">
  <a href="https://github.com/Gulliby-development/gulli-toolkit/releases"><img src="https://img.shields.io/github/v/release/Gulliby-development/gulli-toolkit?filter=MyBisList-*&label=download&color=d9a441&style=for-the-badge" alt="Download the latest release"></a>
  <img src="https://img.shields.io/badge/WoW-Forever-17302d?style=for-the-badge" alt="For WoW Forever">
  <img src="https://img.shields.io/badge/languages-8-17302d?style=for-the-badge" alt="8 languages">
</p>

<p align="center"><img src="window.jpg" alt="The window" width="640"></p>

---

Which helmet should you hunt for at level 40? My BiS List shows the best items for every slot of your character, from level 20 up to the raids, and what you already have of them.

## Features

- **Every class and spec.** 28 specs, tanks, healers and damage, with lists for levels 20, 30, 40 and 50 and before the raids. Your spec and level are picked for you; the button at the top left shows the list of any other spec.
- **Five items for each slot.** The best first. Items of the other faction leave the list.
- **Against what you wear.** Each slot shows the best item of the list with a dot: green when you wear it, yellow when it is in your bags or bank, red when you do not have it yet. Open a slot to see its five items, and what you wear under a line when it is not one of them. A bar shows how many best items you wear.
- **Where to get it.** Each item says where it comes from: a boss and its dungeon, a quest, a reputation, a craft or a world drop.
- **Realistic before the raids.** The switch **Realistic** shows the list without the hardest items to get.
- **My target.** The target button on an item makes it the first of its slot. On a site list, the first click makes your own copy of it, and that copy becomes your main list. What you wear can be your target too.
- **Your own lists.** **Copy to mine** makes a copy of any list that you can change: make an item your target, remove items, and add others with a search over the items your class can use (the ones of your spec first). Type an item id or Shift-click an item into the search to add any item at all. Rename it in the box at the top. When the site later changes the first item of a slot, a line over the list says which slots. Your lists are for every character of your account.
- **Favourite lists.** The star keeps a list at the top of the picker, for an alt or a second spec.
- **Your main list.** **Track this list** chooses the list the tooltips and notices follow. Until you choose, it is the list of your spec and level.
- **In the tooltip.** An item on your main list shows its place in its slot, and the place of what you wear there.
- **A sound when it drops.** When an item of your main list that beats what you wear is in the loot window (also master loot) or in a need or greed roll, you hear a sound and get a notice. A switch in the settings turns it off.
- **A note for a better item.** When an item near the top of your list comes into your bags, a notice says so, once.
- **In the toolkit.** The home page shows how many best items you wear.

## Install

Download `Gulli-MyBisList-<version>-forever.zip` from the [releases](https://github.com/Gulliby-development/gulli-toolkit/releases) and unpack it into `Interface/AddOns`. Then type `/reload`.

My BiS List works alone. With [Gulli Toolkit](../../README.md) installed, it also shows up in the toolkit's window.

## How to use it

1. Type `/gbis`.
2. Click a slot to see its five best items.
3. Shift-click an item to put its link in the chat.
4. Press the target button on an item to make it your first choice for that slot.
5. To change a list, press **Copy to mine**, then **Add item**, the target button or the cross on a row.

Commands: `/gbis` opens the window, `/gbis reset` puts the settings back.

## FAQ

<details>
<summary><b>Where do the lists come from?</b></summary>

From the WoW Forever BiS lists of [wowtbc.gg](https://wowtbc.gg/warcraftforever/). They are the work of its authors; the addon only shows them in the game. We read them again every week, and the date of the lists is at the bottom of the window. Lists marked "simulated" come from a simulator; the healer lists are picked by hand.
</details>

<details>
<summary><b>My spec is wrong.</b></summary>

The addon reads your spec from your talents. Pick the right one with the button at the top left; it stays for this character.
</details>

<details>
<summary><b>Why does the off hand say "Two-hander in use"?</b></summary>

The best weapon of this list is a two-handed one, so the off hand does not count.
</details>
