#!/bin/sh
# Fetches the game icons the addons name (Interface\Icons\...) as PNG from the
# Gethe/wow-ui-textures mirror, and turns each addon's icon.tga into a PNG, into
# tools/preview/.cache so the previews show real icons. Needs curl and python3 with Pillow.
# Run from the repository root.
set -e
dir=tools/preview/.cache
mkdir -p "$dir/icons" "$dir/addons" "$dir/tracking"
# the minimap tracking pictures (auctioneer, banker, ...) the addons use as icons
grep -ohE 'Interface\\\\+Minimap\\\\+Tracking\\\\+[A-Za-z0-9_]+' Gulli-*/*.lua | sed -E 's/.*\\//' | sort -u | while read -r n; do
  low=$(echo "$n" | tr 'A-Z' 'a-z')
  [ -s "$dir/tracking/$low.png" ] && continue
  curl -fsS -o "$dir/tracking/$low.png" "https://raw.githubusercontent.com/Gethe/wow-ui-textures/classic/MINIMAP/TRACKING/$n.PNG" ||
    { rm -f "$dir/tracking/$low.png"; echo "no tracking icon: $n" >&2; }
done
# the quest marks of the gossip window (the "?" and "!" of a quest)
mkdir -p "$dir/gossip"
grep -ohE 'Interface\\\\+GossipFrame\\\\+[A-Za-z0-9_]+' Gulli-*/*.lua | sed -E 's/.*\\//' | sort -u | while read -r n; do
  low=$(echo "$n" | tr 'A-Z' 'a-z')
  [ -s "$dir/gossip/$low.png" ] && continue
  curl -fsS -o "$dir/gossip/$low.png" "https://raw.githubusercontent.com/Gethe/wow-ui-textures/classic/GossipFrame/$n.PNG" ||
    { rm -f "$dir/gossip/$low.png"; echo "no quest mark: $n" >&2; }
done
# the game's button pictures (the loot roll dice, coin and pass, the refresh arrows)
mkdir -p "$dir/buttons"
grep -ohE 'Interface\\\\+Buttons\\\\+UI-(GroupLoot-[A-Za-z-]+|RefreshButton)' Gulli-*/*.lua | sed -E 's/.*\\//' | sort -u | while read -r n; do
  low=$(echo "$n" | tr 'A-Z' 'a-z')
  [ -s "$dir/buttons/$low.png" ] && continue
  curl -fsS -o "$dir/buttons/$low.png" "https://raw.githubusercontent.com/Gethe/wow-ui-textures/classic/Buttons/$n.PNG" ||
    { rm -f "$dir/buttons/$low.png"; echo "no button: $n" >&2; }
done
{ grep -ohE 'Interface\\\\+Icons\\\\+[A-Za-z0-9_]+' Gulli-*/*.lua tools/preview/scenes.lua | sed -E 's/.*\\//'
  grep -ohE '"(INV|Spell|Ability|Trade|Racial)_[A-Za-z0-9_]+"' Gulli-*/*.lua | tr -d '"'; } | sort -u | while read -r n; do
  low=$(echo "$n" | tr 'A-Z' 'a-z')
  [ -s "$dir/icons/$low.png" ] && continue
  curl -fsS -o "$dir/icons/$low.png" "https://raw.githubusercontent.com/Gethe/wow-ui-textures/classic/ICONS/$n.PNG" ||
    { rm -f "$dir/icons/$low.png"; echo "no icon: $n" >&2; }
done
python3 - "$dir/addons" <<'P'
import sys, glob, os
from PIL import Image
for t in glob.glob("Gulli-*/icon.tga"):
    name = t.split("/")[0].lower()
    Image.open(t).save(os.path.join(sys.argv[1], name + ".png"))
P
# A stand-in for the game's Friz Quadrata in the title texts (it may not be embedded).
mkdir -p "$dir/fonts"
[ -s "$dir/fonts/Philosopher-Bold.ttf" ] || curl -fsS -o "$dir/fonts/Philosopher-Bold.ttf" \
  "https://raw.githubusercontent.com/google/fonts/main/ofl/philosopher/Philosopher-Bold.ttf" || echo "no title font" >&2
