#!/bin/sh
# Copies the shared look (Gulli-Toolkit/Skin.lua) into every module folder.
# Run from the repository root after editing it; CI fails when a copy differs.
set -e
for d in Gulli-*/; do
  [ "$d" = "Gulli-Toolkit/" ] && continue
  cp Gulli-Toolkit/Skin.lua "$d/Skin.lua"
done
