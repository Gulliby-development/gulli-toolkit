# Deadmines map prompts

Generator: Codex CLI 0.167 (`codex exec --skip-git-repo-check --sandbox workspace-write -C . -i dungeon.png -i minimap-deadmines.png -`) with its built-in image generation tool, on 2026-11-28. Each file is one generation attempt.

References (layout only), from github.com/Checkov23/ForeverDungeonRoutes, `docs/screenshots/`:

- `dungeon.png`: the game's parchment map of Deadmines floor 1, with a route.
- `minimap-deadmines.png`: the game's minimap pictures of floor 1, with the route.

The full text sent for each variant is in `prompts/full-<v>.txt`: the instruction, the common prompt, then the variant line.

## Instruction (start of every prompt)

> Use your image generation tool to create exactly one image, then copy the resulting PNG into the current directory as deadmines-&lt;v&gt;.png. Do not create or modify any other file. Do not draw it with code; use the image generation tool. Make one attempt only.

## Common prompt

The two attached images are layout references: they show the real floor plan of the dungeon with a route drawn on it. Copy the geometry of the floor plan (tunnels, rooms, turns), not their art style or the UI around them.

Top-down minimalist game map of the Deadmines dungeon (World of Warcraft Classic), tracing EXACTLY the corridor layout of the two attached reference images (same shapes, turns and rooms, north up): a winding mine tunnel enters at the top left, runs down past side caves to the first boss cave, then turns down to a big square foundry room at the bottom, then east and back north up a corridor to a round smelting room on the right, and from there continues on to the hidden sea cove with a pirate ship to the east. Dark warm background (#17110c), walkable floor as soft flat stone shapes with a thin lighter edge, no clutter, no text, no labels, no UI frame. Make vertical changes obvious: ramps and slopes drawn as stepped chevrons in the floor pointing downhill, a tunnel or cave passage drawn darker with a dashed outline, the drop down to the hidden Ironclad Cove harbour (the ship) shown as a clear stair or down-arrow symbol at the end. One continuous route line (cream #f4e6c4, with small arrows) from the entrance at the top to the ship, the already walked part dimmer. Numbered round boss markers in gold rings: 1 in the first boss cave, 2 in the big square foundry room, 3 in the round smelting room, 4 on the way to the cove, 5 at the gangplank of the ship, 6 on the ship deck. Small yellow '!' and blue diamond quest markers. Style: clean, flat, modern, like a metro/transit diagram crossed with a fantasy map, high contrast, readable at small size. Landscape 3:2, 1536x1024.

## deadmines-a.png

Style variant A: flat dark map with gold accents. Background #17110c, floor shapes in muted warm grey-brown stone, thin gold #d9a441 edges on rooms, gold boss rings, completely flat, no shading.

## deadmines-b.png

Style variant B: light parchment map with ink lines. Pale parchment background (instead of the dark one), floor shapes in a slightly darker parchment tone outlined with crisp dark brown ink lines, route line in deep red-brown ink instead of cream, boss rings in gold with dark ink numbers, hand-drawn cartography feel but still clean and flat.

## deadmines-c.png

Style variant C: dark background #17110c with slight isometric depth, so the three levels read as stacked layers: the upper mine tunnels as the top layer, the lower foundry and smelting rooms one layer down, and the sea cove with the ship lowest, each layer with a visible thin side wall or drop shadow so the height steps are obvious. Keep it clean, flat-shaded and readable.

## Notes

- The brief named the bosses (Rhahk'Zor, Sneed's Shredder, Gilnid, Mr. Smite, Captain Greenskin, Edwin VanCleef). The prompt gives only their numbers and rooms, because the map must have no text.
