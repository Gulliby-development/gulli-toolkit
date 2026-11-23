-- Hide quest tracker: the game's quest tracker goes away always, or only in the places the
-- player picked (dungeons and raids, battlegrounds, a fight, while a Gulli guide leads). The
-- tracker holds secure item buttons, so in a fight it only fades; it hides after the fight.

local _, ns = ...

local frame, ticker, get, hooked
local hidden = false

local function tracker()
    return rawget(_G, "ObjectiveTrackerFrame") or rawget(_G, "QuestWatchFrame") or rawget(_G, "WatchFrame")
end

local function combat() return InCombatLockdown and InCombatLockdown() end

-- Whether the tracker goes away now, from the settings and what the game says.
function ns.TrackerHidden(g, state)
    if g("where") == "always" then return true end
    if state.instance == "party" or state.instance == "raid" then
        if g("dungeon") then return true end
    end
    if (state.instance == "pvp" or state.instance == "arena") and g("pvp") then return true end
    if state.combat and g("combat") then return true end
    if state.guide and g("guide") then return true end
    return false
end

local function state()
    local kind
    if IsInInstance then kind = select(2, IsInInstance()) end
    local guide = GulliHUD and rawget(GulliHUD, "guide")
    return {
        instance = kind,
        combat = (UnitAffectingCombat and UnitAffectingCombat("player")) or combat(),
        guide = guide ~= nil,
    }
end

local function apply()
    local f = tracker()
    if not f then return end
    local want = get ~= nil and ns.TrackerHidden(get, state())
    if want then
        f:SetAlpha(0)
        if not combat() and f:IsShown() then f:Hide() end
    elseif hidden then
        -- Only what we hid comes back; the game may hide its tracker for its own reasons.
        f:SetAlpha(1)
        if combat() then return end   -- shown again after the fight
        if not f:IsShown() then f:Show() end
    end
    hidden = want
end
ns.ApplyTracker = apply

local function hook()
    local f = tracker()
    if hooked or not f then return end
    hooked = true
    -- The game shows the tracker again on its own updates.
    f:HookScript("OnShow", function(self)
        if get and ns.TrackerHidden(get, state()) then
            self:SetAlpha(0)
            if not combat() then self:Hide() end
        end
    end)
end

ns.AddTweak({
    key = "hideTracker", group = "quests", icon = "Interface\\Icons\\Ability_Vanish",
    defaults = { where = "places", dungeon = true, pvp = true, combat = false, guide = true },
    panel = {
        { kind = "choice", key = "where", label = ns.L.TWP_TRACK_WHEN,
          values = { { "places", ns.L.TWP_TRACK_PLACES }, { "always", ns.L.TWP_TRACK_ALWAYS } } },
        { kind = "switch", key = "dungeon", label = ns.L.TWP_TRACK_DUNGEON, when = function(g) return g("where") ~= "always" end },
        { kind = "switch", key = "pvp", label = ns.L.TWP_TRACK_PVP, when = function(g) return g("where") ~= "always" end },
        { kind = "switch", key = "combat", label = ns.L.TWP_TRACK_COMBAT, when = function(g) return g("where") ~= "always" end },
        { kind = "switch", key = "guide", label = ns.L.TWP_TRACK_GUIDE, when = function(g) return g("where") ~= "always" end },
    },
    enable = function(g)
        get = g
        hook()
        frame = frame or CreateFrame("Frame")
        frame:SetScript("OnEvent", apply)
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        frame:RegisterEvent("PLAYER_REGEN_DISABLED")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        -- A guide starts and stops without an event.
        if C_Timer and C_Timer.NewTicker and not ticker then ticker = C_Timer.NewTicker(1, apply) end
        apply()
    end,
    disable = function()
        if frame then frame:UnregisterAllEvents() end
        if ticker then ticker:Cancel(); ticker = nil end
        get = nil
        apply()
    end,
    changed = function(_, _, g) get = g; apply() end,
})
