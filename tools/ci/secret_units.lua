-- Flags a UnitName/UnitGUID/GetUnitName read of another unit with no secret check close by.
-- In combat or an instance the game may return a secret value, and using one as a table key,
-- in a comparison or in a string raises an error (AGENTS.md, Working conventions).
-- Run from the repository root: lua5.1 tools/ci/secret_units.lua Gulli-*/*.lua
local GUARDS = { "issecretvalue", "secret%(", "readable%(", "[Aa]sk%(", "pcall" }
local bad = 0
for _, path in ipairs(arg) do
    if not path:match("Skin%.lua$") then
        local lines = {}
        for l in io.lines(path) do lines[#lines + 1] = l end
        for i, l in ipairs(lines) do
            for fn, a in l:gmatch("(%f[%w_]%a*Unit%a*)%(([^)]*)%)") do
                local read = fn == "UnitName" or fn == "UnitGUID" or fn == "GetUnitName"
                if read and not a:match('^%s*"player"%s*$') and not l:match("%-%-.*" .. fn) then
                    local ok = false
                    for j = math.max(1, i - 1), math.min(#lines, i + 2) do
                        for _, g in ipairs(GUARDS) do
                            if lines[j]:match(g) then ok = true end
                        end
                    end
                    if not ok then
                        bad = bad + 1
                        print(("::error file=%s,line=%d::%s(%s) may return a secret value: check issecretvalue before using it."):format(path, i, fn, a))
                    end
                end
            end
        end
    end
end
os.exit(bad == 0 and 0 or 1)
