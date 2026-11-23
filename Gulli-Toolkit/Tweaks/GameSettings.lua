-- Hidden game settings: options the game has but does not show in its settings window. Each one
-- is its own switch; switched off, it goes back to what the player had (ns.TweakCVar).

local _, ns = ...
local L = ns.L

local KEY = "gameSettings"

-- key: the switch; cvar; value(get) the value we set; raise: only when the player's is lower.
ns.GAME_SETTINGS = {
    { key = "camera", cvar = "cameraDistanceMaxZoomFactor", value = function() return 2.6 end, raise = true },
    { key = "plates", cvar = "nameplateMaxDistance", value = function() return 60 end, raise = true },
    { key = "queue", cvar = "SpellQueueWindow", value = function(get) return get("queueMs") end },
    { key = "mapFade", cvar = "mapFade", value = function() return 0 end },
    { key = "noWatch", cvar = "autoQuestWatch", value = function() return 0 end },
    { key = "compare", cvar = "alwaysCompareItems", value = function() return 1 end },
}

local function apply(get)
    for _, s in ipairs(ns.GAME_SETTINGS) do
        if get(s.key) then
            local want = s.value(get)
            local cur = tonumber(ns.GetCVarValue(s.cvar) or "")
            local mine = GulliToolkitDB and GulliToolkitDB.tweakCVars and GulliToolkitDB.tweakCVars[s.cvar]
            if not (s.raise and not mine and cur and cur >= want) then ns.TweakCVar(KEY, s.cvar, want) end
        else
            local mine = GulliToolkitDB and GulliToolkitDB.tweakCVars and GulliToolkitDB.tweakCVars[s.cvar]
            if mine and mine.owner == KEY then ns.TweakCVarRestore(s.cvar) end
        end
    end
end
ns.ApplyGameSettings = apply

local function has(cvar) return function() return ns.HasCVar(cvar) end end
local function hasQueue(get) return get("queue") == true and ns.HasCVar("SpellQueueWindow") end

ns.AddTweak({
    key = KEY, group = "ui", icon = "Interface\\Icons\\INV_Gizmo_01", star = true,
    defaults = { camera = true, plates = true, queue = false, queueMs = 200, mapFade = true, noWatch = false, compare = true },
    panel = {
        { kind = "head", label = L.TWP_GS_HEAD },
        { kind = "switch", key = "camera", label = L.TWP_GS_CAMERA, when = has("cameraDistanceMaxZoomFactor") },
        { kind = "switch", key = "plates", label = L.TWP_GS_PLATES, when = has("nameplateMaxDistance") },
        { kind = "switch", key = "mapFade", label = L.TWP_GS_MAPFADE, when = has("mapFade") },
        { kind = "switch", key = "noWatch", label = L.TWP_GS_WATCH, when = has("autoQuestWatch") },
        { kind = "switch", key = "compare", label = L.TWP_GS_COMPARE, when = has("alwaysCompareItems") },
        { kind = "switch", key = "queue", label = L.TWP_GS_QUEUE, tip = L.TWP_GS_QUEUE_T, when = has("SpellQueueWindow") },
        { kind = "step", key = "queueMs", label = L.TWP_GS_QUEUE_MS, step = 25, min = 50, max = 400,
          fmt = function(v) return L.TWP_MS:format(v or 0) end, when = hasQueue },
    },
    enable = apply,
    disable = function() ns.TweakCVarsRestore(KEY) end,
    changed = function(_, _, get) apply(get) end,
})
