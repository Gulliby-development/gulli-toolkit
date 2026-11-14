<p align="center"><img src="icon.png" alt="" width="96"></p>

<h1 align="center">Gulli-Crates</h1>

<p align="center"><b>Fills your Waylaid Crates the cheapest way: from your bags, your bank and the auction house.</b></p>

<p align="center">
  <a href="https://github.com/Gulliby-development/gulli-toolkit/releases"><img src="https://img.shields.io/github/v/release/Gulliby-development/gulli-toolkit?filter=Crates-*&label=download&color=d9a441&style=for-the-badge" alt="Download the latest release"></a>
  <img src="https://img.shields.io/badge/WoW-Forever-17302d?style=for-the-badge" alt="For WoW Forever">
  <img src="https://img.shields.io/badge/languages-8-17302d?style=for-the-badge" alt="8 languages">
</p>

<p align="center"><img src="window.jpg" alt="The window" width="560"></p>

---

A Waylaid Crate takes any one bundle from its list: 10 Wintersbite, 10 Firebloom, 20 Purple Lotus or 10 Arthas' Tears. Which one is cheapest for you? Gulli Crates works it out and buys the rest.

## Features

- **Opens at the auction house.** Carry a crate and open the auction house: the window opens beside it. A switch turns this off.
- **Pick the crates.** Every crate in your bags is listed. Untick the ones you want to keep for later.
- **The cheapest bundle.** **Calculate** prices every bundle of every crate. What you already have costs nothing; the rest is priced from Auctionator's database.
- **Your bank counts.** Items in your bank are used too, and the list says so in orange: take them out before you fill the crate. A switch turns this off.
- **Several crates at once.** Your stock is shared fairly: a stack that fills one crate is not split over two.
- **Buy what is missing.** Press **Buy** to go through the list. The first press asks the auction house for the real price and shows it on the button. The next press buys. After that, each line is one press.
- **No surprises.** If the real price is much higher than Auctionator's, the line turns orange. Press **Skip** to leave a line out.
- **All 30 crates.** Apprentice, Journeyman, Expert and Artisan: herbs, ore, textiles, curiosities, fabrics, ingots and parts.

## Install

**With [Runeloader](https://github.com/Gulliby-development/runeloader)** (Android): install **Gulli Toolkit**. Crates comes with it.

**By hand:** download `Gulli-Crates-<version>-forever.zip` from the [releases](https://github.com/Gulliby-development/gulli-toolkit/releases) and unpack it into `Interface/AddOns`. Then type `/reload`.

You also need [Auctionator](https://www.curseforge.com/wow/addons/auctionator) for the prices. Scan the auction house with it now and then.

## How to use it

1. Put the crates in your bags and go to the auction house.
2. Untick the crates you do not want, press **Calculate**.
3. Press **Buy** until the list is done.
4. Use each crate: it takes the bundle from your bags. Then hand the sealed crate in at your trade hub.

Type `/gcr` to open the window anywhere.

## FAQ

<details>
<summary><b>Why one press per purchase?</b></summary>

The game lets an addon buy at the auction house only when you press a button yourself. So the button does one purchase each time. It never buys without your press.
</details>

<details>
<summary><b>Why does the real price differ from the plan?</b></summary>

Auctionator remembers the lowest price of one item. Buying 20 may take some dearer ones too. The button always shows the real price before you buy.
</details>

<details>
<summary><b>Where does the list of bundles come from?</b></summary>

From the crate's own tooltip in the game. If the game cannot give it, from a table in the addon, made from the WoW Forever guides on wowforever.ninja and urgametips.com.
</details>

<details>
<summary><b>Is it tested in the game?</b></summary>

Not yet in WoW Forever itself. It is tested on a fake game client. If something does not work, tell us on GitHub.
</details>

---

<p align="center"><sub>Part of <a href="../../README.md">Gulli Toolkit</a>. A fan project, not affiliated with Blizzard Entertainment. Free software under the <a href="../../LICENSE">GPLv3</a>.</sub></p>
