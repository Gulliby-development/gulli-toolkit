-- Builds one addon window on the fake frames and writes it as HTML.
-- Run from the repository root: lua5.1 tools/preview/shoot.lua <test folder> <out.html> [scene]
-- The scene (tools/preview/scenes.lua) fills the fake client with sample data and opens the window.
local name, out, scene = arg[1], arg[2], arg[3] or "default"
local R = dofile("tools/preview/frames.lua")
local scenes = dofile("tools/preview/scenes.lua")
local W = dofile("tests/" .. name .. "/wow.lua")

local s = scenes[name] and scenes[name][scene]
local spec = s and s.spec or {}
spec.class = spec.class or "MAGE"
spec.locale = os.getenv("LOCALE") or spec.locale
if Fake then Fake(spec) end
R.Install(W)
if s and s.before then s.before(W, R) end
local ns = Load()
if s and s.open then s.open(ns, W, R) else ns.Toggle() end
if W.RunTimers then pcall(W.RunTimers) end

-- The window to frame: the given one, else the biggest shown frame on UIParent.
local crop = s and s.crop and _G[s.crop]
if not crop then
    local best, area = nil, 0
    for _, f in ipairs(R.UIParent.__children) do
        if f.__shown and f ~= GameTooltip then
            local c = R.Rect(f)
            local a = (c.r - c.l) * (c.t - c.b)
            if a > area then best, area = f, a end
        end
    end
    crop = best
end
local fh = assert(io.open(out, "w"))
fh:write(R.Html(crop, 24))
fh:close()
for _, o in ipairs(R.Overlaps(crop or R.UIParent)) do
    io.stderr:write(name .. ": overlap: " .. o[1]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. " / " ..
        o[2]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "\n")
end
