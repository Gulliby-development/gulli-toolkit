<p align="center"><img src="icon.png" alt="Gulli-GroupBuffs" width="128"></p>

<h1 align="center">Gulli-GroupBuffs</h1>

<p align="center"><b>A small WoW Forever addon that buffs your group for you: one press, one missing buff. It keeps going in combat too.</b></p>

<p align="center">
  <a href="https://github.com/Gulliby-development/gulli-toolkit/releases"><img src="https://img.shields.io/github/v/release/Gulliby-development/gulli-toolkit?filter=GroupBuffs-*&label=download&color=d9a441&style=for-the-badge" alt="Download the latest release"></a>
  <img src="https://img.shields.io/badge/WoW-Forever-17302d?style=for-the-badge" alt="For WoW Forever">
  <img src="https://img.shields.io/badge/languages-8-17302d?style=for-the-badge" alt="8 languages">
</p>

<p align="center"><img src="preview.png" alt="The Quick Buff bar and the settings" width="860"></p>

<p align="center"><img src="settings.png" alt="The settings window" width="520"></p>

---

Before a pull, somebody always misses Fortitude or Intellect. Gulli-GroupBuffs looks at your group and puts the next missing buff on one button. Press it, or press your key, until everyone has your buffs.

## Features

- **One button, one key.** The big button shows the next buff and who gets it. Click it or press your Quick Buff key. You first, then the group.
- **See who is missing what.** Small buttons next to it show the buffs after that. Click one to cast that buff on that player.
- **In combat too.** The game does not let an addon change a button in combat. So when the fight starts, the addon gives the button the list of missing buffs. Each press in combat casts the next buff from that list and skips the dead. Buffs that landed in combat are greyed out on the bar.
- **Group spells when they pay off.** When three or more players in a party need the same buff, it casts Prayer of Fortitude, Arcane Brilliance or Gift of the Wild instead, if you have the reagent.
- **Buff again in time.** A buff with less than one minute left counts as missing. You choose: when it is gone, or 1, 3 or 5 minutes before.
- **Every class.**
  - Priest: Power Word: Fortitude, Divine Spirit, Shadow Protection (off by default), Inner Fire, and the racial Touch of Weakness (Undead) and Shadowguard (Troll), only on yourself.
  - Mage: Arcane Intellect, and your armor (the best one you know, or the one you pick).
  - Druid: Mark of the Wild, Thorns on you, on your tanks or on everyone, and Omen of Clarity.
  - Paladin: one blessing per class, one for tanks and one for healers, your aura, and Righteous Fury (off by default).
  - Shaman: your shield and a weapon imbue you choose.
  - Warrior: Battle Shout. Warlock: Demon Skin or Demon Armor. Hunter: the aspect you pick.
- **Pets too.** Hunter and warlock pets get Fortitude and Mark of the Wild, and the mana buffs when they have mana. Turn **Buff pets** off if you do not want that.
- **See it at a glance.** The big button shows how many buffs wait (**+3**). Its border is red when there is something to cast, yellow when the rest is out of range, green when everyone is done.
- **Icons only, if you like.** Switch off **Buff names on the bar** and the bar shows only the icons, without the spell name and the player.
- **Marks on your group frames.** A small icon on the game's party and raid frames shows who misses a buff, even when the bar is hidden.
- **Smart about people.** No Intellect or Spirit for warriors and rogues. Dead, offline and far away players are skipped; the bar says how many are out of range. When a cast fails on someone (out of sight, a stronger buff), that player is skipped for 20 seconds, so the button does not get stuck.
- **Mouseover and target first.** Point at a player, or target them, and the next press buffs them first.
- **Save mana.** Below the mana you choose, it only buffs you.
- **Raid groups.** In a raid, buff only the groups you are given (1–2, 3–4, 1–4, ...). You always buff yourself.
- **Different for solo, party and raid.** Turn on **By group size** to keep **Buff again when** and **Group spells** apart for each.
- **Your target too.** A friendly player you target is offered too, even outside your group. Set **Who it buffs** to **Your group** to skip them.
- **Your bar, your place.** A big buff icon with your key and how many casts are left, and a line with the buff and who gets it. The icon pulses red while someone misses a buff. Place it with `/gulli move` (or `/ggb lock`). Show it only when a buff is missing, always, or never (key only). Hide it in cities and inns, or show it only in dungeons and raids. On a ready check it shows up with a sound when someone misses a buff. `/ggb lock` locks it.
- **It tells you why.** When there is nothing to cast, the bar says why: no reagent, low mana, everyone out of range. `/ggb status` prints it in the chat.
- **Made for handhelds.** Big buttons, so it works with a mouse and with touch on WoW Forever for Android.
- **Your language.** English, German, Spanish, French, Polish, Portuguese, Russian and Chinese. Spell and class names come from your game.

## Install

**With [Runeloader](https://github.com/Gulliby-development/runeloader)** (Android): open **Browse**, search for **Gulli Toolkit** and tap **Install**. You get every Gulli module; remove the ones you do not want in **Library**.

**By hand:**

1. **Download** `Gulli-GroupBuffs-<version>-forever.zip` from the newest `GroupBuffs-v…` [release](https://github.com/Gulliby-development/gulli-toolkit/releases).
2. **Unpack** it into the game's `Interface/AddOns` folder. You get the folder `Interface/AddOns/Gulli-GroupBuffs`.
3. **Restart** the game, or type `/reload`.

## How to use it

1. Type `/ggb`, or open it from the [Gulli Toolkit](../../README.md) window (`/gulli`).
2. Press the **Quick Buff key** button, then the key you want.
3. Turn on the buffs you want to watch.
4. Press your key (or the big button) until the bar says **Everyone has your buffs**.

On a gamepad or a phone you can also put `/click GulliGroupBuffsButton` in a macro and place it on your action bar.

## FAQ

**I have Camp Benefits. Why does it not ask for Fortitude?**
The camp gives stats such as Stamina. When the camp gives as much as your buff or more, the game does not let you cast the weaker buff, so it is not shown. When the game refuses a buff as weaker for any other reason, it is not asked for again while that effect lasts (ten minutes at most).

<details>
<summary><b>Why does it skip a buff in combat?</b></summary>

In combat the game does not tell the button who still needs a buff. The button walks through the list made when the fight started. If a press does not cast (the spell is on cooldown, or you are moving), the button still moves on. After the last one it starts the list again, so just keep pressing. Out of combat it always aims at the right player.
</details>

<details>
<summary><b>The bar is empty, but someone has no buff</b></summary>

Type `/ggb status`. It tells you the reason: the spell is not learned, a reagent is missing, your mana is low, they are out of range, or a cast on them failed a moment ago.
</details>

<details>
<summary><b>Can it share raid buff jobs with other players?</b></summary>

Not yet. Set **Raid groups** to the groups the raid leader gives you. Sharing jobs with other players (and with PallyPower) may come later.
</details>

<details>
<summary><b>The key does nothing</b></summary>

A key set in combat works after the fight. If another addon uses the same key, pick another one. Right-click the key button to clear it.
</details>

<details>
<summary><b>It does not see buffs in a battleground</b></summary>

The game hides some buffs from addons there. Then the addon leaves that player alone instead of asking you again and again.
</details>

<details>
<summary><b>Is it the same as HealKit?</b></summary>

The idea is the same as HealKit's Quick Buff, but it is a small addon of its own, written from scratch, with no healing frames. It also keeps working in combat.
</details>

<details>
<summary><b>For developers</b></summary>

- `Buffs.lua`: the buffs per class by spell id (`B.CLASS`), and the pick-one lists (`B.CHOICES`, "auto" takes the best known). Names come from the game, so they are always in your language.
- `Core.lua`: the plan (`ns.Plan`): units you first (pets after their owner), what each one misses, group spells, mana, mouseover and target first, range. `ns.Status` gives why nothing is cast. It never casts.
- `UI.lua`: the secure buttons. Out of combat every change sets their `spell` and `unit`. On `PLAYER_REGEN_DISABLED` the list goes into attributes of the big button, and a restricted snippet (`ns.COMBAT_SNIPPET`) picks the next living unit on each press in combat.
- Tests: `lua5.1 tests/groupbuffs/test.lua`. They run the combat snippet with only the calls the restricted environment has.
</details>

---

<p align="center">
  <sub>Gulli-GroupBuffs is a fan project. It is not affiliated with Blizzard Entertainment or with HealKit.<br>
  It is free software under the <a href="../../LICENSE">GPLv3</a>.</sub>
</p>
