# Deadmines map v2 prompts

Generator: Codex CLI 0.167 (`codex exec --skip-git-repo-check --sandbox workspace-write -C . -i skeleton-deadmines-clean.png -i skeleton-deadmines.png -i real-deadmines-291.png -i real-deadmines-292.png -i deadmines-c.png -`) with its built-in image generation tool, on 2026-11-28. Two runs with the same prompt; each run is one attempt.

Inputs: `skeleton-deadmines-clean.png` and `skeleton-deadmines.png` (the layout from ForeverDungeonRoutes route data, MIT), `real-deadmines-291.png` and `real-deadmines-292.png` (the game's maps, for the look of rooms), `deadmines-c.png` (the style the owner picked).

## Instruction (start of each prompt)

> Use your image generation tool to create exactly one image, then copy the resulting PNG into the current directory as deadmines-v2-&lt;n&gt;.png. Do not create or modify any other file. Do not draw it with code; use the image generation tool. Make one attempt only.

## Prompt

Attached images, in order: 1) skeleton-deadmines-clean.png: the layout to follow exactly. 2) skeleton-deadmines.png: the same layout with labels, only to explain what each shape is. 3) real-deadmines-291.png and 4) real-deadmines-292.png: the game's real maps, only for the look of the rooms (ship, wooden walkways, cove). 5) deadmines-c.png: the style to copy.

Repaint the skeleton image as a finished dungeon map in the style of deadmines-c.png: dark background, stone walls with slight 3D depth, warm cave rooms, the square Mast Room workshop (boss 2), the round red-hot Goblin Foundry (boss 3), a dark sloping tunnel with clear downward steps from the foundry to the cove, the blue-water Ironclad Cove with the boss-4 platform at its top, narrow winding wooden walkways down along the left side of the ship, and the big ship with two decks. KEEP EVERY ROOM, CORRIDOR, TURN AND THE SHIP EXACTLY WHERE THE SKELETON HAS THEM (same pixel positions, same proportions); straight corridors stay short as in the skeleton. NO text, NO numbers, NO boss markers, NO route line, NO arrows, NO small props (crates, barrels, sails detail kept minimal). Clean and minimal, readable when shrunk to 500 px wide; slopes and stairs must be obvious. Landscape, 1536x1024.

## Check against the skeleton

- Both: every room, corridor, turn, the boss-4 platform and the ship are where the skeleton has them. No text, numbers, markers or route line.
- v2-1: stairs on both parts of the tunnel to the cove; more sail detail on the ship.
- v2-2: the dark tunnel with stairs reads as a slope down more clearly; plainer ship.
- Neither shows Cookie's place under the deck. It goes in as a marker later.
