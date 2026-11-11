# Gulli Toolkit logo prompts

Generator: Codex CLI 0.167.0-alpha.3.2 (`codex exec --sandbox workspace-write`) with its built-in image generation tool, on 2026-11-12.
Each file came from one generation attempt. Codex got this instruction, with the image prompt below after it:

> Use your image generation tool to create exactly one image, then copy the resulting PNG into the current directory as FILE. Do not create or modify any other file. Do not draw it with code; use the image generation tool. Make one attempt only.

When a reference image was attached (`-i`), this sentence was added:

> The attached image is a style reference from the same addon family: match its flat vector style, palette, outline weight and seal ring, but draw the new subject described below.

The files are the originals: 1254x1254 squares and 1774x887 wide images.

## Toolkit (this folder)

### icon.png (reference: `../gulli-questcleaner/icon.png`)

Square app icon, flat minimal vector style, for Gulli Toolkit, a set of small World of Warcraft helper addons. Deep teal background #17302d with a soft radial vignette. Centered: an original emblem of an open adventurer's leather tool satchel in warm brown with a gold #d9a441 buckle, with a few small tools rising out of it in cream #f3ead6 with dark teal outlines: a rolled parchment scroll, a small gold cog wheel, a tiny key and a quill, plus three small gold sparkles above. A faint thin circular seal ring in lighter teal #2a7f73 around it. Flat colors, crisp dark outlines, generous padding, readable at 48px. No text, no letters, no numbers, no game logos.

### wordmark-dark.png (reference: `icon.png`)

Horizontal logo, wide 2:1 aspect, on a solid deep teal #17302d background. On the left, the icon mark from the attached image: a brown leather tool satchel with a gold buckle, a cream scroll, a gold cog, a gold key and a cream quill rising from it, three gold sparkles, inside a faint thin lighter teal seal ring, flat vector. To its right, the wordmark text exactly 'Gulli Toolkit' in a clean modern geometric sans-serif; the word 'Gulli' in light sky blue #9ad0ff, the word 'Toolkit' in cream #f3ead6. Spelled exactly, well kerned, flat vector, crisp, plenty of margin, no other text.

### wordmark-light.png (reference: `icon.png`)

Horizontal logo, wide 2:1 aspect, on a solid cream #f3ead6 background. On the left, a rounded-square deep teal #17302d tile containing the mark from the attached image: a brown leather tool satchel with a gold #d9a441 buckle, a cream scroll, a gold cog, a gold key and a cream quill rising from it, three gold sparkles. To its right, the wordmark text exactly 'Gulli Toolkit' in a clean modern geometric sans-serif; 'Gulli' in steel blue #3a78a8, 'Toolkit' in deep teal #17302d. Spelled exactly, well kerned, flat vector, crisp, plenty of margin, no other text.

### preview.png (reference: `icon.png`)

Wide 2:1 promotional preview banner, flat minimal vector style, for Gulli Toolkit, a set of small World of Warcraft helper addons. Deep teal background #17302d with a soft radial vignette and a few tiny gold sparkles. On the left third: the satchel emblem from the attached image (brown leather satchel with gold buckle, cream scroll, gold cog, gold key, cream quill) inside its faint lighter teal seal ring. On the right: the title text exactly 'Gulli Toolkit' in a clean geometric sans-serif, 'Gulli' in sky blue #9ad0ff and 'Toolkit' in cream #f3ead6, and below it a neat row of six small round teal badges with cream and gold line icons: a quest scroll, a coin pouch, a letter envelope, a shield with a plus, a magnifying glass, an experience star. Flat colors, crisp dark outlines, balanced margins, no other text, no game logos.

## Modules (`../gulli-<module>/`)

Each module folder gets `icon.png` (reference: `../gulli-questcleaner/icon.png`) and `preview.png` (reference: that module's `icon.png`). `<Name>`, `<what it does>` and `<emblem>` come from the table.

### icon.png

Square app icon, flat minimal vector style, for Gulli-`<Name>`, a World of Warcraft addon that `<what it does>`. Deep teal background #17302d with a soft radial vignette. Centered: an original emblem of `<emblem>`. Cream #f3ead6 shapes with dark teal outlines, gold #d9a441 accents, warm brown leather details where natural. A faint thin circular seal ring in lighter teal #2a7f73 around it. Flat colors, crisp edges, generous padding, readable at 48px. No text, no letters, no numbers, no exclamation marks, no question marks, no game logos.

### preview.png

Wide 2:1 preview banner, flat minimal vector style, for Gulli-`<Name>`, a World of Warcraft addon that `<what it does>`. Part of the Gulli Toolkit family. Deep teal background #17302d with a soft radial vignette and a few tiny gold sparkles. On the left third: the emblem from the attached icon (`<emblem>`) inside its faint lighter teal seal ring. On the right: the title text exactly 'Gulli-`<Name>`' in a clean modern geometric sans-serif, 'Gulli' in light sky blue #9ad0ff and the hyphen and '`<Name>`' in cream #f3ead6. Below the title, a small flat mockup of a game window panel in a slightly lighter teal with a thin gold border, showing the idea of the addon with simple shapes: rows, bars, check marks and tiny icons, with no readable words. Spelled exactly, crisp dark outlines, balanced margins, no other text, no game logos.

| Name | What it does | Emblem |
| --- | --- | --- |
| Attune | tracks raid attunements for all characters | a gold key in front of a small stone raid gateway with a cream ribbon of three check marks |
| AutoQuest | takes and hands in quests automatically | a cream parchment scroll with two curved gold arrows circling it, one coming in and one going out |
| BagSpace | frees bag slots by merging stacks and selling junk | a brown leather bag in front of a small grid of four cream inventory slots, two of them empty and glowing gold |
| Bulletin | sorts trade and group chat into topics | a small wooden notice board with four cream notes of different shapes pinned by gold pins |
| Chores | keeps a daily to-do list for each character | a cream clipboard checklist with gold check marks and a small gold hourglass beside it |
| DungeonPrep | prepares a dungeon run: its quests and a checklist | a stone dungeon archway with a cream scroll and a small brown backpack in front of it |
| InstanceLimit | counts dungeon entries per hour | a gold hourglass in front of a stone dungeon archway, with five small cream tally marks below |
| Loot | rolls Need, Greed or Pass by rules | a small open brown treasure chest with gold coins and two cream dice showing dots |
| Mail | takes all mail and fills recipient names | a cream envelope with a gold wax seal and a small brown mail sack |
| Merchant | sells gray items and repairs gear at a vendor | a gold balance scale with a small pile of coins on one side and a small brown hammer on the other |
| PartyQuests | compares quests across the party and shares them | three small cream scrolls fanned out and linked by thin gold lines |
| QuickChat | chats without a keyboard using ready phrases | two cream speech bubbles with gold dots inside and a small round gamepad button |
| Reminders | reminds about missing buffs, poisons, ammo and shards | a gold bell with a small cream potion vial and a single arrow beside it |
| Restock | keeps reagents, ammo, food and water stocked | a brown quiver of arrows, a cream bread loaf and a water flask, circled by a gold refill arrow |
| Social | handles group and guild invites | two cream head-and-shoulder figure silhouettes side by side under a small gold banner ribbon |
| Tooltip | adds stack price and quest use to item tooltips | a cream rectangular tooltip panel with a gold coin and a small magnifying glass over its corner |
| XP | shows XP per hour and time to the next level | a gold star above a cream progress bar that is two thirds filled with gold |
| GroupBuffs | shows which party members miss which buffs | five small round cream portrait frames in an arc with small glowing gold buff auras (a sun, a shield, a leaf) above them |
| MobFinder | finds named mobs nearby by their nameplates | a gold crosshair compass ring over a cream wolf head silhouette, with a small magnifying glass |
| QuestCleaner | abandons low quests and deletes leftover quest items | a cream quest scroll with check boxes and a brown pouch under a gold sweeping arc of sparkles (icon already in `../gulli-questcleaner/`) |

The copies in this repository are resized: `docs/<module>/icon.png` to 256x256, `Gulli-<Module>/icon.tga` to 64x64, the toolkit wordmarks and preview to 1120x560. The originals are in the project files under `branding/`.
