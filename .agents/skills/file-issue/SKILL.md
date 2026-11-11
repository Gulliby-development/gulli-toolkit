---
name: file-issue
description: Use every time you open or update a GitHub issue for a Gulli Toolkit bug (the core or any module). Finds the root cause, sweeps the code for every other place with the same or a neighbouring defect, and files issues that cover all of them.
---

# File an issue with a sibling sweep

A fix that changes only the place where a bug showed up often leaves copies of the bug behind: the same check in another rule, another view or the old API fallback. This skill makes the issue name every affected place before anyone starts the fix.

Run it before you create or extend any Bug issue. Keep the sweep small: about 15 minutes or 20 tool calls. It is research, not a fix.

## 1. Name the root cause

Read the code at the point of failure until you can say in one sentence which rule or computation is wrong. Name the rule, not only the symptom. For example, "an item counts as needed only when its name is in the objectives, not in the quest description", not "the addon deleted my letter".

## 2. Sweep for every occurrence

Search current `main` for each kind of sibling below. Search for the function, the constant, the text key and the field names involved.

- **Copies of the rule.** Other places that decide the same thing their own way instead of through `PlanQuests`, `PlanItems` or `ItemGoes`.
- **Kinds of quest items.** Quest-class items, items the game marks as quest items, items that start a quest, a quest's usable item, items in `PERMANENT` and items in `keep`.
- **Quest log entries.** Headers, hidden quests, quests without a level, collapsed headers, quests abandoned during the run.
- **Bags.** The backpack, the other bags and the reagent bag (`NUM_TOTAL_EQUIPPED_BAG_SLOTS`), locked slots, stacks.
- **API paths.** The `C_` function and the old global fallback in each wrapper of `Core.lua`.
- **The run.** The first OK, a refused delete, the second OK after `Leftover`, combat.
- **Views and input.** The setup view, the preview, the language menu; mouse, touch and a small screen.
- **Languages.** Every table in `Locales.lua`, texts saved by key, the TOC notes.
- **Edge cases of earlier fixes.** Check `git log -S<symbol>` and recent `bugfix/` merges on the same code for an empty list, a first-match-wins lookup or a name that is part of another name.

Sort each place you check into one of three groups:

- **same defect:** it goes into this issue's scope;
- **related but different:** it gets its own issue, linked from this one;
- **checked, not affected:** list it with the reason.

## 3. Check for duplicates

Search open issues and issues closed in the last two weeks by function, file and text. If a closed fix did not hold, link it and say which place it missed.

## 4. Write the issue

Follow the rules in `AGENTS.md`: the issue type, the labels and the `Priority: P0|P1|P2` first line. The body has these sections:

- **Problem:** the root cause in one or two sentences, with the evidence (steps, the Lua error, a screenshot, the quest and the item).
- **Where:** every affected `file:line` on current `main`, with the sibling places.
- **Scenario:** the quest log, the bags and the clicks that lead to the wrong behaviour.
- **Sweep:** what you searched, the same-defect places, the linked related issues, and the places checked and not affected.
- **Suggested fix:** prefer one shared rule that all places use over a separate patch at each place.
- **Tests:** a case in `tests/<name>/test.lua` that fails without the fix, or the steps in the game for a window bug.
- **Maintainability:** when the fix adds a shared rule or a table that later code must use or extend, name the rule for `AGENTS.md`. Otherwise write `None`.

## 5. When you fix an issue filed this way

Fix every place listed under **Where**. If the issue names a rule under **Maintainability**, add it to `AGENTS.md` in the same pull request. Before you open the pull request, run the sweep searches again on the branch. Fix a new place in the same pull request, or open its own issue and link it.

Report it in a `## Sweep` section of the pull request description:

- each place from **Where**, fixed;
- each new place the second sweep found: fixed here, or the new issue's number;
- the places you checked that are not affected, with the reason.
