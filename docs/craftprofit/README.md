<p align="center"><img src="icon.png" alt="" width="96"></p>

<h1 align="center">Gulli-CraftProfit</h1>

<p align="center"><b>Profitable crafts and the cheapest way to level a profession, from your bags, your bank and Auctionator prices.</b></p>

<p align="center">
  <a href="https://github.com/Gulliby-development/gulli-toolkit/releases"><img src="https://img.shields.io/github/v/release/Gulliby-development/gulli-toolkit?filter=CraftProfit-*&label=download&color=d9a441&style=for-the-badge" alt="Download the latest release"></a>
  <img src="https://img.shields.io/badge/WoW-Forever-17302d?style=for-the-badge" alt="For WoW Forever">
  <img src="https://img.shields.io/badge/languages-8-17302d?style=for-the-badge" alt="8 languages">
</p>

<p align="center"><img src="window.png" alt="The window" width="560"></p>

---

Want to level Tailoring without losing your gold? Gulli CraftProfit looks at what you have, what things cost at the auction and at vendors, and draws a route: take this from the bank, buy that at the auction, craft these, learn this at the trainer, sell the rest.

## Features

- **A route, not a table.** Each stop shows where to go, with the real game icons of what you buy, craft or sell there. Tap a stop to see the list.
- **You choose what matters.** Money, balance or speed. Use your bags and bank or not, buy at the auction or only at vendors, buy patterns, go to the trainer, sell at the auction or to a vendor. The route changes at once, and the changed stops light up.
- **Honest money.** The auction cut (5%, or 15% at a neutral auction), the deposit you lose when an item does not sell, and how many of one item the market will take. Your own cloth counts at what you could sell it for.
- **Crafts now.** Your recipes sorted by profit per craft, and how many you can make from what you have.
- **My items.** For each material in your bags and bank: sell at the auction, sell to a vendor, or craft it.
- **Recipes.** Patterns you can buy or learn, and the craft that pays them back.

## Install

**With [Runeloader](https://github.com/Gulliby-development/runeloader)** (Android): install **Gulli Toolkit**. CraftProfit comes with it.

**By hand:** download `Gulli-CraftProfit-<version>-forever.zip` from the [releases](https://github.com/Gulliby-development/gulli-toolkit/releases) and unpack it into `Interface/AddOns`. Then type `/reload`.

For auction prices, also install **Auctionator** and scan the auction once.

## How to use it

1. Open your profession window once. CraftProfit reads your recipes.
2. Open the bank once if you want it to count what is there.
3. Type `/gcp`. Pick what matters on the right and follow the route.

## FAQ

<details>
<summary><b>Do I need Auctionator?</b></summary>

No, but without it only vendor prices count, and the route never buys or sells at the auction.
</details>

<details>
<summary><b>Why are the numbers marked as estimates?</b></summary>

The game shows only the colour a recipe has at your skill now (orange, yellow, green, grey). CraftProfit remembers the colours it sees and guesses when a recipe turns grey, on the careful side. The more you level, the better the guess.
</details>

<details>
<summary><b>Does it buy or craft for me?</b></summary>

No. It only shows the route. You buy, craft and sell yourself.
</details>

<details>
<summary><b>Is it tested in the game?</b></summary>

Not yet in WoW Forever itself. It is tested on a fake game client. Type `/gcp probe` with a profession window open and send us what it prints. If something does not work, tell us on GitHub.
</details>

---

<p align="center"><sub>Part of <a href="../../README.md">Gulli Toolkit</a>. A fan project, not affiliated with Blizzard Entertainment. Free software under the <a href="../../LICENSE">GPLv3</a>.</sub></p>
