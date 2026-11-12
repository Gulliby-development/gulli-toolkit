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

- **A route, not a table.** Each stop shows where to go, with the real game icons of what you buy, craft or sell there. A craft stop names the recipe, the skill it covers and how many crafts it takes. Tap a stop to see the list.
- **The real skill-up chances.** CraftProfit knows when each Classic recipe turns yellow, green and grey, so it knows how often a craft raises your skill. When the game shows another colour, it trusts the game.
- **One run at a time.** The route is your next run: one kind of craft, with only the shopping it needs. Craft it, and the route plans the next run from your new skill and the new prices. Below the route you still see how far the whole way is.
- **The whole way, run by run.** Small tabs over the route show every run up to your target skill: 150-155, 155-185 and so on, each with the gold it gains or loses. Tap one to see that run. A red tab with a question mark is a stretch where no recipe you know raises the skill; learn a new one, and the route goes on.
- **The route fits on the screen.** You always see two rows of stops. When there are more, **All stops** opens the rest.
- **Routes side by side.** Up to four ways to level, from the cheapest to the fastest, and two ways to just make money: from what you already have, or also buying reagents and patterns when the craft still pays. A money run is one recipe, crafted while it still pays and the market still takes it. It does not raise your skill, and it buys at most a few stacks of one reagent at the auction (**Auction buy, at most**), because only a few sell at the cheapest price. Each tab shows the gold, so you can compare them.
- **How much you may lose.** Set **Ready to lose**, and CraftProfit picks the fastest way to level that stays within it. Ways that cost more are marked.
- **Not levelling?** Switch off **Level the profession**, and you only see the crafts that make money. When your skill is at the top, the money routes open by themselves.
- **You choose the rest.** Use your bags and bank or not, buy at the auction or only at vendors, buy patterns, go to the trainer, sell at the auction or to a vendor. The route changes at once, and the changed stops light up.
- **Honest money.** Over the route: what you buy, what your own materials are worth, what the sales bring and the result, red when you lose gold. The auction cut (5%, or 15% at a neutral auction), the deposit you lose when an item does not sell, and how many of one item the market will take. Your own cloth counts at what you could sell it for.
- **Straight to Auctionator.** At the auction stop, **To Auctionator** puts everything the run buys there into an Auctionator shopping list, with the amounts.
- **Real lot prices.** At the auction house, **Update prices** reads the lots of what the run buys. Buying 60 cloth then costs what the cheapest 60 really cost, not 60 times the first lot.
- **Craft from the route.** At a craft stop, **Make 142** crafts the run in the open profession window, and **Recipe** shows it there. Tap the recipe row to show it too.
- **Mail and your other characters.** Items waiting in your mailbox count as yours. Switch on **Other characters**, and items your alts carry count too (read from Gulli Chores); the route says who sends them.
- **You gather it?** Right-click a reagent in the stop list, or type `/gcp gather <item link>`, and the route stops buying it. A **Gather** stop shows how much to collect.
- **Run log.** Press **Start the run**, craft, then **Finish the run**: you see the gold the plan promised and what you really made or spent.
- **In the item tooltip:** how many of it the chosen run needs.
- **Crafts now.** Your recipes in their game colour, sorted by profit per craft, and how many you can make from what you have. Tap a column head to sort by it; point at a row to see its reagents.
- **My items.** For each material in your bags and bank: sell at the auction, sell to a vendor, or craft it.
- **Recipes.** Patterns you can buy or learn: from the trainer, a vendor (with the vendor's name), a quest, a drop or the auction, with the price, the profit per craft and after how many crafts the profit has paid for the pattern. The best profit first.

## Install

**With [Runeloader](https://github.com/Gulliby-development/runeloader)** (Android): install **Gulli Toolkit**. CraftProfit comes with it.

**By hand:** download `Gulli-CraftProfit-<version>-forever.zip` from the [releases](https://github.com/Gulliby-development/gulli-toolkit/releases) and unpack it into `Interface/AddOns`. Then type `/reload`.

For auction prices, also install **Auctionator** and scan the auction once.

## How to use it

1. Open your profession window once. CraftProfit reads your recipes.
2. Open the bank once if you want it to count what is there.
3. Type `/gcp`. Pick a route at the top, set the switches on the right and follow the stops.

## FAQ

<details>
<summary><b>Do I need Auctionator?</b></summary>

No, but without it only vendor prices count, and the route never buys or sells at the auction.
</details>

<details>
<summary><b>How does it know how many crafts a skill point takes?</b></summary>

An orange recipe always gives a point. A yellow or green one gives it less often, the closer it is to grey. CraftProfit knows the levels of every Classic recipe, so it knows the chance. Only a recipe it does not know (marked as an estimate) is guessed from the colours the game showed.
</details>

<details>
<summary><b>Why does the route lose gold when Crafts now shows a profit?</b></summary>

Crafts now counts one craft sold at the auction. A run makes many of one item, and the auction only buys so many at that price (**At most of one item**, 20 at first); the rest go to a vendor for less. Each item goes where it brings more: to a vendor only when the vendor pays more than the auction after its cut and the deposit you lose on what does not sell. Raise or lower that setting to match your auction. One step past the top of it is **no limit**: then every unit goes to the auction. **Auction buy, at most** ends in **no limit** the same way.
</details>

<details>
<summary><b>Why does the whole way take hundreds of crafts?</b></summary>

Green and yellow recipes do not raise your skill every time, so one skill point can take more than one craft. The number under the route is for the whole way to your target. You do not need to plan it: follow one run, and the next one is planned for you.
</details>

<details>
<summary><b>Where do the recipe levels come from?</b></summary>

The skill levels come from the Classic recipe tables of the [Skillet-Classic](https://github.com/b-morgan/Skillet-Classic) addon (GPLv3), made from the game's own data. Where a pattern comes from (vendor, quest, drop) comes from the WoW Forever data of [QuestieDB](https://github.com/Questie/QuestieDB) (GPLv3). A vendor's price is four times what a vendor pays for the pattern until you see the vendor; a trainer's price shows after one visit. `tools/craftprofit/build_data.py` turns both into `Data.lua`.
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
