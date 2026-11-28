# Deadmines map v3 prompts (parchment style B, traced from the game maps)

Generator: Codex CLI 0.167 (`codex exec --skip-git-repo-check --sandbox workspace-write -C . -i <inputs> -`) with its built-in image generation tool, on 2026-11-28. Each file is one attempt.

Instruction at the start of every prompt:

> Use your image generation tool to create exactly one image, then copy the resulting PNG into the current directory as <file>. Do not create or modify any other file. Do not draw it with code; use the image generation tool. Make one attempt only.

## Per floor: deadmines-v3-f1-1/2.png, deadmines-v3-f2-1/2.png

Inputs: `game-floor1-deadmines.png` or `game-floor2-ironclad.png` (the game's map, 1503x1002), and `deadmines-b.png` (style).

Redraw this exact dungeon map in the style of deadmines-b.png: warm parchment, ink outlines, hand-drawn WoW cartography with depth (soft inner shadows along the walls, darker cave floors, lighter raised platforms, wooden planks drawn as planks, water with gentle hatching, the ship drawn top-down with decks). Trace EVERY wall, bend, alcove, room and corridor of the input exactly in place: same pixel positions, nothing simplified, straightened or moved. Mark slopes with small ink chevrons pointing downhill and stairs as drawn steps. Keep the title banner area empty or remove it. NO text, NO numbers, NO route line, NO markers. Output size 1503x1002, the same framing as the input map, so it overlays it 1:1.

## Earlier tries: deadmines-v3-a.png (both floors in one image), -b.png (floor 1), -c.png (floor 2)

Inputs: `real-deadmines-291.png`, `real-deadmines-292.png`, `deadmines-b.png`, 1536x1024.

a:

Attached: real-deadmines-291.png (floor 1, the mines) and real-deadmines-292.png (floor 2, Ironclad Cove), and deadmines-b.png for the style.
Draw ONE combined map, landscape 1536x1024: floor 1 on the left half exactly as in real-deadmines-291.png (entrance at the top, side caves, Rhahk'Zor's cave, the branch to Miner Johnson, the Mast Room at the bottom, the round Goblin Foundry). From the Goblin Foundry, continue with the long tunnel of floor 2 that rises to the right with wooden stairs and walkways (as in real-deadmines-292.png), into Ironclad Cove on the right half: the platform at the top, the wooden walkways that wind down along the left side of the ship, and the oval ship with its two decks. Show the cove water in a faint blue-green wash as in the real map.

b:

Attached: real-deadmines-291.png (floor 1, the mines) and deadmines-b.png for the style.
Draw floor 1 only, landscape 1536x1024, with the same framing and layout as real-deadmines-291.png: entrance at the top left, the side caves, Rhahk'Zor's cave, the short branch to Miner Johnson, the Mast Room at the bottom, the round Goblin Foundry with its ring walkway, and the corridor that loops from the Mast Room up to the Foundry.

c:

Attached: real-deadmines-292.png (floor 2, Ironclad Cove) and deadmines-b.png for the style.
Draw floor 2 only, landscape 1536x1024, with the same framing and layout as real-deadmines-292.png: the round Goblin Foundry at the bottom left, the long rising tunnel with wooden stairs and walkways to the platform at the top of the cove, the walkways that wind down along the left side of the ship, and the oval ship with its decks and the raised stern cabin. Show the cove water in a faint blue-green wash as in the real map.

Common part:

Style: the light parchment style of deadmines-b.png (pale parchment background, floor in a slightly darker parchment tone, crisp dark-brown ink outlines), but with more depth, like the default World of Warcraft dungeon maps (the real maps attached): soft inner shadows along every wall, darker ink hatching where walls rise, slight bevel on ledges, wooden planks drawn on walkways and bridges, ramps and slopes drawn with fine hatching or steps so it is obvious where the path goes down. Clean, no clutter.
Geometry: trace the floor outlines of the attached real game maps EXACTLY: every bend, side cave, niche, room shape and corridor width, same proportions. Do not simplify, straighten or invent shapes.
Leave out: all text, the DEADMINES title banner, the torn frame, the faint pencil sketches of the ship and lamp in the corners, numbers, boss markers, the white route line and any arrows. Only the map itself on clean parchment.

## Check against the game maps (50% overlay at 1503x1002)

- f1-1, f1-2, f2-1, f2-2: walls, side caves, the Mast Room, the Foundry ring, the tunnel, the walkways and the ship match the game map almost 1:1. All four kept the torn frame, an empty title banner and the corner sketches of the game map.
- Best floor 1: f1-1 (stronger wall shadows, Mast Room with water texture). f1-2 is the same shape, softer.
- Best floor 2: f2-1 (chevrons on the tunnel and walkways point the way down to the cove). In f2-2 one chevron at the Foundry exit points up.
- a, b, c: clean parchment without frame. Shapes are close but not 1:1 (b and c are scaled and shifted; a joins both floors and loses the Foundry ring).
