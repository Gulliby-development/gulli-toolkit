#!/bin/sh
# Builds every scene of tools/preview/scenes.lua and fails on room a window wastes at its
# bottom (R.Empty in frames.lua): a footer shown with nothing in it, or a list that has more
# rows than it shows while nothing is under it. Run from the repository root.
set -e
list=$(lua5.1 -e 'for m, t in pairs(dofile("tools/preview/scenes.lua")) do if type(t) == "table" then for s in pairs(t) do print(m .. " " .. s) end end end' | sort)
out=$(mktemp)
fail=0
echo "$list" | while read -r m s; do
    [ -d "tests/$m" ] || continue
    lua5.1 tools/preview/shoot.lua "$m" "$out" "$s" 2>&1 | grep " empty: " | sed "s|^|$s: |" || true
done > "$out.log"
rm -f "$out"
if [ -s "$out.log" ]; then
    cat "$out.log"
    echo "A page wastes room at the bottom: hide an empty footer, let a list reach the bottom (AGENTS.md, window sizes)."
    fail=1
fi
rm -f "$out.log"
exit $fail
