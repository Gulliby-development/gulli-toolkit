<p align="center"><img src="icon.png" alt="" width="96"></p>

<h1 align="center">Gulli-Reminders</h1>

<p align="center"><b>Shows icons for what is missing before a fight: your class buffs, what your class puts on its weapons, ammo and soul shards.</b></p>

<p align="center">
  <a href="https://github.com/Gulliby-development/gulli-toolkit/releases"><img src="https://img.shields.io/github/v/release/Gulliby-development/gulli-toolkit?filter=Reminders-*&label=download&color=d9a441&style=for-the-badge" alt="Download the latest release"></a>
  <img src="https://img.shields.io/badge/WoW-Forever-17302d?style=for-the-badge" alt="For WoW Forever">
  <img src="https://img.shields.io/badge/languages-8-17302d?style=for-the-badge" alt="8 languages">
</p>

<p align="center"><img src="window.jpg" alt="The window" width="560"></p>

---

Pulled without Inner Fire again? Gulli Reminders puts an icon on screen while something is missing.

## Features

- **Your class buffs, one switch each.** Fortitude, Inner Fire, Arcane Intellect, armor spells, Mark of the Wild, Demon Armor, blessings, auras, aspects, Trueshot Aura, Lightning Shield, a warrior's stance (after a resurrection you have none) and more. Priest racials count too: Touch of Weakness, Shadowguard and Fear Ward (for your race), and Shadowform. The window lists only your class, with the game's own icons. A buff you have not learned yet waits until you learn it.
- **Before it runs out.** A buff with less than 3 minutes left already shows, with the time on the icon. You choose the minutes, or turn it off.
- **Your class's own supplies.** Each class sees only its own card, **Class supplies**:
  - Rogue: poisons on each hand (from level 20; a sharpening stone before that).
  - Warrior: sharpening stones for a blade, weightstones for a mace or a staff, on each hand.
  - Shaman: the weapon imbue you pick: Rockbiter, Flametongue, Frostbrand or Windfury.
  - Paladin and hunter: stones, else mana or wizard oil. Hunters check the off hand too.
  - Mage, warlock, priest and druid: wizard and mana oils.
  - Mage: a mana gem in your bags. Warlock: a healthstone. A click conjures the best one you know.
  - Hunter and warlock: your pet. Hunter: ammo. Warlock: soul shards below the number you set.
- **See what a click uses.** Next to **Main hand**, **Off hand** and **Your food** you see the icon and name of the item a click puts on: the best one in your bags, or the one you dropped there. Right-click goes back to the best one. Stones and oils cost money, so they start off; poisons and imbues start on.
- **Click to fix it.** Click an icon and it casts the buff on you, puts poison or an oil on your weapon, summons or revives your pet, or eats your food. Right-click opens the settings.
- **Food, elixirs and flasks.** Well Fed shows when it is gone or ends soon; a click eats the best buff food in your bags, or the food you dropped on **Your food**.
- **Your own reminders.** Drop any item on the window: an elixir or a flask reminds you of its buff, other items (water, bandages, potions, reagents) of how many you want to keep. Or type `/grm item <link>` or `/grm spell <id>`. At an open vendor, a click on a count icon buys what is missing.
- **Repairs and bag space.** An icon when an item is below the durability you set, or your bags have too few free slots.
- **Buffs from your group.** Turn it on, and when you lack Fortitude, Mark of the Wild, Intellect or a blessing, it shows who in your group can give it.
- **Where it counts.** Class checks and consumables each have their own place: everywhere, only in a group, or only in dungeons and raids. Consumables start with dungeons and raids.
- **A sound and a line on screen** when a new reminder shows up: always, only in dungeons and raids (the default), or never.
- **Tanks.** Righteous Fury is on for a paladin who has the tank role, unless you turn it off.
- **Easy to read.** A missing buff pulses red; one that runs out soon has a yellow ring and the time on it.
- **A panel you place.** It starts hidden. Turn it on and place it in **Unlock frames** in `/gulli` (`/grm unlock`), with the other Gulli frames: there it shows every icon it can show. In the window, set the icon size, the opacity, a row or a column, and names with the icons. In a row each icon gets a short name under it, such as "MH: poison" (main hand) or "OH: stone" (off hand), so the icons never move.
- **Also in a fight.** If you put a buff, a form, a stance or an oil on in combat, its icon goes away at once. A form, a stance or a paladin aura that drops in a fight shows beside the panel; the game lets an addon cast only after the fight, so use your own key for it. Other buffs (Well Fed, your class buffs) are checked in a fight too, except while the game hides them (a boss fight): then they only go away, and are checked again right after the fight. Nothing shows while you are dead or on a flight. In cities and inns too, unless you turn that off.

<p align="center"><img src="panel.png" alt="The panel on screen" width="460"></p>

## Install

**With [Runeloader](https://github.com/Gulliby-development/runeloader)** (Android): install **Gulli Toolkit**. Reminders comes with it.

**By hand:** download `Gulli-Reminders-<version>-forever.zip` from the [releases](https://github.com/Gulliby-development/gulli-toolkit/releases) and unpack it into `Interface/AddOns`. Then type `/reload`.

## How to use it

1. Type `/grm`, or open **Reminders** in `/gulli`.
2. Switch on the buffs you want to watch.
3. Open **Unlock frames** in `/gulli` (or type `/grm unlock`), turn on **Reminders**, drag the icons where you want them, and press **Save and lock**.
4. Hover over an icon to see what is missing. A click fixes it, a right-click opens the settings.

`/grm reset` puts the panel back at the top of the screen.

## FAQ

**I have Camp Benefits. Why does it not ask for Fortitude?**
The camp gives stats such as Stamina. When the camp gives as much as your buff or more, the game does not let you cast the weaker buff, so it is not shown. When the game refuses a buff as weaker for any other reason, it is not asked for again while that effect lasts (ten minutes at most).

<details>
<summary><b>I see no icons. Why?</b></summary>

Nothing is missing, or the panel waits: while you are dead, on a flight, in a city when you turned **Also in cities and inns** off, or outside a group or a dungeon when **Where to check** says so. The line at the bottom of the window says which. Open **Unlock frames** in `/gulli` to see where the icons appear, and check that **Reminders** is on there.
</details>

<details>
<summary><b>A click on the food icon does nothing</b></summary>

You have none of the buff foods it knows in your bags (**Your food** says "None in your bags"). Drop the food you use on **Your food** in the window, and it eats that one first. The same works for poisons, stones and oils on **Main hand** and **Off hand**.
</details>

<details>
<summary><b>A group buff from another player counts?</b></summary>

Yes. Any buff with the same name counts, from you or from another player.
</details>

<details>
<summary><b>Is it tested in the game?</b></summary>

Not yet in WoW Forever itself. It is tested on a fake game client. If something does not work, tell us on GitHub.
</details>

---

<p align="center"><sub>Part of <a href="../../README.md">Gulli Toolkit</a>. A fan project, not affiliated with Blizzard Entertainment. Free software under the <a href="../../LICENSE">GPLv3</a>.</sub></p>
