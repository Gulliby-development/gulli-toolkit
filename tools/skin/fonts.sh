#!/bin/sh
# Makes the text fonts of Gulli Hearth: Fira Sans Medium and Bold (SIL OFL 1.1, no Reserved
# Font Name, so a subset may keep the name) cut to Latin, Latin-1, Latin Extended-A (Polish),
# Cyrillic and common punctuation, into Gulli-Toolkit/Media/Fonts with the licence beside them.
# Needs fonttools (pip install fonttools). Run from the repository root, then tools/skin/sync.sh.
set -e
SRC=https://raw.githubusercontent.com/google/fonts/main/ofl/firasans
OUT=Gulli-Toolkit/Media/Fonts
TMP=$(mktemp -d)
mkdir -p "$OUT"
for f in FiraSans-Medium.ttf FiraSans-Bold.ttf OFL.txt; do curl -sSfL -o "$TMP/$f" "$SRC/$f"; done
RANGES="U+0020-007E,U+00A0-00FF,U+0100-017F,U+0400-045F,U+0490-0491,U+2010-2027,U+2030-203A,U+20AC,U+2116,U+2122"
for f in FiraSans-Medium FiraSans-Bold; do
  pyftsubset "$TMP/$f.ttf" --unicodes="$RANGES" --layout-features='kern,liga' --hinting \
    --desubroutinize --output-file="$OUT/$f.ttf"
done
cp "$TMP/OFL.txt" "$OUT/OFL.txt"
rm -rf "$TMP"
ls -l "$OUT"
