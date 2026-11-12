#!/bin/sh
# Fetches the game icons the addons name (Interface\Icons\...) as PNG from the
# Gethe/wow-ui-textures mirror, and turns each addon's icon.tga into a PNG, into
# tools/preview/.cache so the previews show real icons. Needs curl and python3 with Pillow.
# Run from the repository root.
set -e
dir=tools/preview/.cache
mkdir -p "$dir/icons" "$dir/addons"
grep -ohE 'Interface\\\\+Icons\\\\+[A-Za-z0-9_]+' Gulli-*/*.lua tools/preview/scenes.lua |
  sed -E 's/.*\\//' | sort -u | while read -r n; do
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
