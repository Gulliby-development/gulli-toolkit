-- Error message filter: hides the red messages the player picks (not enough rage, not ready yet,
-- out of range, no target, facing the wrong way), always or only in combat. It asks the game's
-- own error frame to leave those message types out (UIErrorsFrame:SetMessageTypeEnabled), so a
-- hidden message is silent too, and gives every type back as it was when switched off.

local _, ns = ...
local L = ns.L

local KEY = "errorFilter"

-- The kinds of the panel, each a list of the game's message type names (LE_GAME_ERR_<name>); a
-- name this client lacks is skipped.
ns.ERROR_KINDS = {
    { key = "power", names = { "OUT_OF_RAGE", "OUT_OF_ENERGY", "OUT_OF_MANA", "OUT_OF_FOCUS",
        "OUT_OF_POWER_DISPLAY", "OUT_OF_COMBO_POINTS", "OUT_OF_HEALTH" } },
    { key = "cooldown", names = { "ABILITY_COOLDOWN", "SPELL_COOLDOWN", "ITEM_COOLDOWN",
        "SPELL_FAILED_ANOTHER_IN_PROGRESS" } },
    { key = "range", names = { "OUT_OF_RANGE", "SPELL_OUT_OF_RANGE", "BADATTACKPOS" } },
    { key = "target", names = { "GENERIC_NO_TARGET", "NO_ATTACK_TARGET", "INVALID_ATTACK_TARGET",
        "GENERIC_NO_VALID_TARGETS" } },
    { key = "facing", names = { "BADATTACKFACING", "SPELL_FAILED_UNIT_NOT_INFRONT" } },
}

local hidden = {} -- message type -> what the game's list said before (true, false or nil)
local frame, get

local function list() return _G.BLACK_LISTED_MESSAGE_TYPES end

local function setType(t, show)
    local f = _G.UIErrorsFrame
    if f and f.SetMessageTypeEnabled then
        pcall(f.SetMessageTypeEnabled, f, t, show)
    elseif list() then
        list()[t] = not show or nil
    end
end

local function restore()
    local bl = list()
    for t, was in pairs(hidden) do
        if bl then
            if was == "none" then bl[t] = nil else bl[t] = was end
        else
            setType(t, true)
        end
    end
    hidden = {}
end

-- The message types the panel's ticks hide.
function ns.ErrorTypes(g)
    local out = {}
    for _, kind in ipairs(ns.ERROR_KINDS) do
        if g(kind.key) then
            for _, name in ipairs(kind.names) do
                local t = _G["LE_GAME_ERR_" .. name]
                if t ~= nil then out[#out + 1] = t end
            end
        end
    end
    return out
end

local function hide()
    restore()
    local bl = list()
    for _, t in ipairs(ns.ErrorTypes(get)) do
        if hidden[t] == nil then
            local was = bl and bl[t]
            if was == nil then was = "none" end
            hidden[t] = was
            setType(t, false)
        end
    end
end

local function update()
    if not get then return end
    local fight = InCombatLockdown and InCombatLockdown() or false
    if get("combat") and not fight then restore() else hide() end
    if get("voice") then ns.TweakCVar(KEY, "Sound_EnableErrorSpeech", 0)
    else ns.TweakCVarsRestore(KEY) end
end
ns.ErrorFilterUpdate = update

local function onEvent(_, event)
    if not get then return end
    if event == "PLAYER_REGEN_DISABLED" then
        if get("combat") then hide() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if get("combat") then restore() end
    end
end
ns.ErrorFilterEvent = onEvent

ns.AddTweak({
    key = KEY, group = "combat", icon = "Interface\\Icons\\Ability_Spy", star = true,
    defaults = { power = true, cooldown = true, range = true, target = true, facing = false, combat = false, voice = true },
    panel = {
        { kind = "head", label = L.TWP_ERR_HEAD },
        { kind = "check", key = "power", label = L.TWP_ERR_POWER },
        { kind = "check", key = "cooldown", label = L.TWP_ERR_COOLDOWN },
        { kind = "check", key = "range", label = L.TWP_ERR_RANGE },
        { kind = "check", key = "target", label = L.TWP_ERR_TARGET },
        { kind = "check", key = "facing", label = L.TWP_ERR_FACING },
        { kind = "switch", key = "combat", label = L.TWP_ERR_COMBAT },
        { kind = "switch", key = "voice", label = L.TWP_ERR_VOICE, when = function() return ns.HasCVar("Sound_EnableErrorSpeech") end },
    },
    enable = function(g)
        get = g
        frame = frame or CreateFrame("Frame")
        frame:SetScript("OnEvent", onEvent)
        frame:RegisterEvent("PLAYER_REGEN_DISABLED")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        update()
    end,
    disable = function()
        if frame then frame:UnregisterAllEvents() end
        restore()
        ns.TweakCVarsRestore(KEY)
        get = nil
    end,
    changed = function(_, _, g) get = g; update() end,
})
