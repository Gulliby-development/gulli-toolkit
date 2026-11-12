<p align="center"><img src="icon.png" alt="" width="96"></p>

<h1 align="center">Gulli-AutoQuest</h1>

<p align="center"><b>Takes and hands in quests for you. You still pick the reward when there is a choice.</b></p>

<p align="center">
  <a href="https://github.com/Gulliby-development/gulli-toolkit/releases"><img src="https://img.shields.io/github/v/release/Gulliby-development/gulli-toolkit?filter=AutoQuest-*&label=download&color=d9a441&style=for-the-badge" alt="Download the latest release"></a>
  <img src="https://img.shields.io/badge/WoW-Forever-17302d?style=for-the-badge" alt="For WoW Forever">
  <img src="https://img.shields.io/badge/languages-8-17302d?style=for-the-badge" alt="8 languages">
</p>

<p align="center"><img src="window.png" alt="The window" width="560"></p>

---

Talking to a quest giver takes four or five taps. On a phone that adds up. Gulli Auto Quest does them for you.

## Features

- **Takes quests** when you talk to a quest giver.
- **Hands in finished quests,** before it takes new ones.
- **Skips gray quests** that give you almost no experience. You can turn that off.
- **Your rewards stay your choice.** When a quest has more than one reward, it waits for you and marks the one that sells for the most. A switch lets it take that one for you.
- **No surprise costs.** A quest that asks for gold is never handed in on its own, and a quest that takes cloth, ore or other non-quest items waits for you (a switch changes that).
- **Pause without a keyboard.** A **Pause** switch (also in `/gulli`), a **5 min** button, and a pause key you choose: Shift, Ctrl, Alt or none.
- **Ignore list.** Ignore an NPC or a quest with one tap in the **Ignored** tab, or `/gaq ignore` at an NPC. Remove them from the list there too.
- **Quests from your group** are accepted only when you turn that on (escorts can start without warning).
- **Rules.** Skip elite, dungeon and raid, or group quests; keep some quest log places free; pick the only dialogue line of an NPC.
- **See what it did.** Taken, handed in and clicks saved for this session (a `/reload` keeps them), a line in the Gulli Toolkit feed, and a chat line if you want.
- **Undo.** **Abandon last** drops the last quest it took for you.

## Install

**With [Runeloader](https://github.com/Gulliby-development/runeloader)** (Android): install **Gulli Toolkit**. Auto Quest comes with it.

**By hand:** download `Gulli-AutoQuest-<version>-forever.zip` from the [releases](https://github.com/Gulliby-development/gulli-toolkit/releases) and unpack it into `Interface/AddOns`. Then type `/reload`.

## How to use it

1. It works on its own.
2. Type `/gaq` to change what it does. `/gaq pause` turns the pause on or off.

## FAQ

<details>
<summary><b>It took a quest I did not want</b></summary>

Press **Abandon last** in `/gaq`. To stop it at that NPC for good, open the **Ignored** tab and press **Ignore** with the NPC's name.
</details>

<details>
<summary><b>Is it tested in the game?</b></summary>

Not yet in WoW Forever itself. It is tested on a fake game client. If something does not work, tell us on GitHub.
</details>

---

<p align="center"><sub>Part of <a href="../../README.md">Gulli Toolkit</a>. A fan project, not affiliated with Blizzard Entertainment. Free software under the <a href="../../LICENSE">GPLv3</a>.</sub></p>
