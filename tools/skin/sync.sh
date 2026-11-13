#!/bin/sh
# Copies the shared look (Gulli-Toolkit/Skin.lua and its round shapes in Gulli-Toolkit/Media)
# into every module folder. Run from the repository root after editing them; CI fails when a
# copy differs.
set -e
for d in Gulli-*/; do
  [ "$d" = "Gulli-Toolkit/" ] && continue
  cp Gulli-Toolkit/Skin.lua "$d/Skin.lua"
  rm -rf "$d/Media"
  cp -r Gulli-Toolkit/Media "$d/Media"
done
