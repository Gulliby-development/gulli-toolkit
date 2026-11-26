-- Level-up screenshot: a screenshot once the "Level N" banner shows, and on an achievement too
-- when the player wants it.

local _, ns = ...

local DELAY = 1.2
local frame

-- The game's Screenshot may be no plain Lua function (C_Timer.After refused it), so the timer
-- gets one of ours that looks the global up when it runs.
local function take()
    if Screenshot then Screenshot() end
end

local function shoot()
    if not Screenshot then return end
    if C_Timer and C_Timer.After then C_Timer.After(DELAY, take) else take() end
end

local get
local function onEvent(_, event)
    if event == "PLAYER_LEVEL_UP" or (event == "ACHIEVEMENT_EARNED" and get and get("achievement")) then
        shoot()
    end
end

ns.AddTweak({
    key = "levelShot", group = "level", icon = "Interface\\Icons\\INV_Misc_Spyglass_03", star = true,
    defaults = { achievement = false },
    panel = {
        { kind = "head", label = ns.L.TWP_SHOT_ALSO },
        { kind = "switch", key = "achievement", label = ns.L.TWP_SHOT_ACH },
    },
    enable = function(g)
        get = g
        frame = frame or CreateFrame("Frame")
        frame:SetScript("OnEvent", onEvent)
        frame:RegisterEvent("PLAYER_LEVEL_UP")
        frame:RegisterEvent("ACHIEVEMENT_EARNED")
    end,
    disable = function()
        if frame then frame:UnregisterAllEvents() end
    end,
    changed = function(_, _, g) get = g end,
})

-- For the tests: what an event does.
ns.LevelShotEvent = onEvent
