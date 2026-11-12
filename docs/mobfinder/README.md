<p align="center"><img src="icon.png" width="96" alt=""></p>

# Gulli-MobFinder

Type the mobs you look for. When one of them shows its nameplate, you hear a sound.

<p align="center"><img src="window.png" alt="The window" width="560"></p>

## Features

- **A list of mobs.** One name per line. A part of the name is enough, and the case does not matter (also in Russian).
- **Add target.** Target a mob and press the button to put its name on the list.
- **Check every N seconds.** From 0.5 to 60 seconds. A new nameplate also counts at once, between two checks.
- **Pick a sound.** Raid warning, ready check, alarm clock and more. The arrows play each sound, so you hear it before you pick it. The sound plays even when game effects are muted.
- **One alert per mob.** A mob alerts when it comes into sight. It alerts again only after it was out of sight, or on every check if you turn on **Repeat while it is in sight**.
- **A warning on the screen** and a line in the chat with the name.
- Works alone, or as a module of **Gulli Toolkit**.
- Speaks English, Deutsch, Español, Français, Polski, Português, Русский and 中文 (it follows the game language).

## Install

Install it in [Runeloader](https://github.com/Gulliby-development/runeloader): search for **Gulli-MobFinder** and press **Install**. Or download the zip from the releases and unpack it into `Interface/AddOns`.

Open the window with `/gmf` or from the addon menu at the minimap.

## FAQ

**Why does it not find a mob I can see?**
The game makes a nameplate only for a mob that is close enough and only when nameplates are on. The addon turns on enemy nameplates for you. A friendly NPC needs friendly nameplates (Options, Interface, Nameplates).

**Does it work in dungeons?**
No. In dungeons and raids the game hides mob names from addons, so the addon cannot read them there.

**Can it target the mob for me?**
No. The game allows targeting only from a key press or a click, not from an addon timer.

<details>
<summary>Slash commands</summary>

- `/gmf` opens the window.
- `/gmf on`, `/gmf off` switch the search.
- `/gmf add <name>` adds a name, `/gmf target` adds your target.
- `/gmf list` shows the list, `/gmf clear` empties it.

</details>

<details>
<summary>How it works</summary>

A timer (`C_Timer.NewTicker`) runs every N seconds and reads `C_NamePlate.GetNamePlates()`. For each plate it reads `UnitName` of the plate's unit and compares it with the list. `NAME_PLATE_UNIT_ADDED` runs the same check at once. Dead mobs do not count. On WoW 12 a creature's name can be a secret value (in instances): the addon checks `issecretvalue` first and skips such a plate instead of raising an error. The sound plays with `PlaySound(id, "Master")`.

</details>
