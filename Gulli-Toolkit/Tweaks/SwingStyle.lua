-- Swing timer style: WoW Forever has its own swing bars (Blizzard_SwingTimer: main hand, off
-- hand, ranged; placed in Edit Mode). This tweak only restyles them: a flat bar in the class
-- colour or bronze, and red while the target is out of reach. It never moves, shows or hides the
-- game's frames, so their layout and secure parts stay the game's.

local _, ns = ...
local L = ns.L

local KEY = "swingStyle"
local FRAMES = { "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" }
local FLAT = "Interface\\Buttons\\WHITE8X8"
local BRONZE = { 0.643, 0.514, 0.310 }
local RED = { 0.85, 0.25, 0.2 }

local get, running, frame
local hooked = setmetatable({}, { __mode = "k" })

function ns.SwingColor(g, classFile, outOfRange)
    if outOfRange and g("range") then return RED end
    if g("color") == "class" then
        local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if c then return { c.r, c.g, c.b } end
    end
    return BRONZE
end

local function bar(f) return f and f.StatusBar end

local function paint(f)
    if not running or not get then return end
    local sb = bar(f)
    if not sb then return end
    local _, classFile = UnitClass("player")
    local c = ns.SwingColor(get, classFile, f.isOutOfRange == true)
    pcall(sb.SetStatusBarTexture, sb, FLAT)
    pcall(sb.SetStatusBarColor, sb, c[1], c[2], c[3], 1)
    if f.Background and f.Background.SetVertexColor then f.Background:SetVertexColor(0.35, 0.28, 0.2) end
end

local function unpaint(f)
    local sb = bar(f)
    if not sb then return end
    if f.barTexture then pcall(sb.SetStatusBarTexture, sb, f.barTexture) end
    pcall(sb.SetStatusBarColor, sb, 1, 1, 1, 1)
    if f.Background and f.Background.SetVertexColor then f.Background:SetVertexColor(1, 1, 1) end
end

local function each(fn)
    for _, name in ipairs(FRAMES) do
        local f = _G[name]
        if f then fn(f) end
    end
end

-- A hook cannot be taken away: it does nothing while the tweak is off.
local function hook(f)
    if hooked[f] or not hooksecurefunc then return end
    hooked[f] = true
    for _, m in ipairs({ "ResetSwingTimer", "ApplyRangePresentation", "InitializeBarPresentation" }) do
        if type(f[m]) == "function" then hooksecurefunc(f, m, function(self) paint(self) end) end
    end
end

local function apply()
    if get and get("show") then ns.TweakCVar(KEY, "showSwingTimer", 1) else ns.TweakCVarsRestore(KEY) end
    each(function(f) hook(f); paint(f) end)
end
ns.SwingApply = apply

ns.AddTweak({
    key = KEY, group = "combat", icon = "Interface\\Icons\\Ability_MeleeDamage",
    defaults = { color = "class", range = true, show = true },
    panel = {
        { kind = "choice", key = "color", label = L.TWP_SW_COLOR,
          values = { { "class", L.TWP_SW_CLASS }, { "bronze", L.TWP_SW_BRONZE } } },
        { kind = "switch", key = "show", label = L.TWP_SW_SHOW, when = function() return ns.HasCVar("showSwingTimer") end },
        { kind = "switch", key = "range", label = L.TWP_SW_RANGE },
    },
    enable = function(g)
        get, running = g, true
        frame = frame or CreateFrame("Frame")
        frame:SetScript("OnEvent", function(_, event, name)
            if event == "ADDON_LOADED" and name == "Blizzard_SwingTimer" then apply() end
        end)
        frame:RegisterEvent("ADDON_LOADED")
        apply()
    end,
    disable = function()
        running = false
        if frame then frame:UnregisterAllEvents() end
        each(unpaint)
        ns.TweakCVarsRestore(KEY)
    end,
    changed = function(_, _, g) get = g; apply() end,
})
