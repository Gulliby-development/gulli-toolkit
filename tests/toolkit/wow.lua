-- A fake WoW client for the Gulli Toolkit tests: the addon list and what the hub calls.
-- Fake{ addons = { { name, meta = {...}, enabled, loaded } }, locale = "enUS" } sets the globals,
-- Load() runs the toolkit files and returns its addon table.

local W = {}

local function stub()
    return setmetatable({}, { __index = function(t, k)
        if k == "IsShown" then return function() return rawget(t, "_shown") == true end end
        if k == "Show" then return function() rawset(t, "_shown", true) end end
        if k == "Hide" then return function() rawset(t, "_shown", false) end end
        if k == "SetShown" then return function(_, v) rawset(t, "_shown", v and true or false) end end
        if k == "GetHeight" then return function() return rawget(t, "_height") or 768 end end
        if k == "SetHeight" then return function(_, v) rawset(t, "_height", v) end end
        if k == "GetWidth" then return function() return 500 end end
        if k == "GetValue" then return function() return 0 end end
        if k == "GetText" then return function() return rawget(t, "_text") end end
        if k == "SetText" then return function(_, v) rawset(t, "_text", v) end end
        if k == "SetEnabled" then return function(_, v) rawset(t, "_enabled", v) end end
        if k == "SetScript" then return function(_, n, f) rawset(t, "_" .. n, f) end end
        if k == "GetScript" then return function(_, n) return rawget(t, "_" .. n) end end
        return function() return stub() end
    end })
end

function Fake(spec)
    -- A copy, so a test that switches an addon does not change it for the next test.
    W.addons = {}
    for i, a in ipairs(spec.addons or {}) do
        local c = {}
        for k, v in pairs(a) do c[k] = v end
        W.addons[i] = c
    end
    W.frames, W.printed, W.reloaded, W.unsaved = {}, {}, false, false
    local function find(name)
        for i, a in ipairs(W.addons) do
            if a.name == name or i == name then return a end
        end
    end
    C_AddOns = {
        GetNumAddOns = function() return #W.addons end,
        GetAddOnInfo = function(i) local a = find(i); return a and a.name end,
        GetAddOnMetadata = function(name, field) local a = find(name); return a and a.meta and a.meta[field] end,
        IsAddOnLoaded = function(name) local a = find(name); return a and a.loaded or false end,
        -- a.state forces what the game answers, as a client that reads another character would.
        GetAddOnEnableState = function(name) local a = find(name); return a and (a.state or (a.enabled and 2 or 0)) or 0 end,
        IsAddOnLoadable = function(name)
            local a = find(name)
            if not a then return false, "MISSING" end
            if not a.enabled then return false, "DISABLED" end
            if a.blocked then return false, a.blocked end
            return true
        end,
        -- a.stuck: the game ignores the switch.
        EnableAddOn = function(name) local a = find(name); if not a.stuck then a.enabled = true end; W.unsaved = true end,
        DisableAddOn = function(name) local a = find(name); if not a.stuck then a.enabled = false end; W.unsaved = true end,
        SaveAddOns = function() W.unsaved = false end,
    }
    UnitName = function() return "Tester" end
    UnitClass = function() return "Priest", "PRIEST" end
    GetLocale = function() return spec.locale or "enUS" end
    SlashCmdList = {}
    CreateFrame = function() local f = stub(); W.frames[#W.frames + 1] = f; return f end
    UIParent, GameTooltip, UISpecialFrames = stub(), stub(), {}
    tinsert = table.insert
    time = function() return 1000 end
    GetCursorInfo = function() end
    Minimap = setmetatable({ GetWidth = function() return 140 end, GetCenter = function() return 100, 100 end,
        GetEffectiveScale = function() return 1 end, GetFrameLevel = function() return 2 end }, { __index = stub() })
    W.cursor = { 100, 100 }
    GetCursorPosition = function() return W.cursor[1], W.cursor[2] end
    GetMinimapShape = nil
    ClearCursor = function() end
    C_Item = { GetItemInfo = function() end }
    ReloadUI = function() W.reloaded = true end
    Settings = nil
    print = function(...) W.printed[#W.printed + 1] = table.concat({ ... }, " ") end
    GulliToolkit = nil
    GulliToolkitDB = nil
    return W
end

function Load(dir)
    dir = dir or "Gulli-Toolkit/"
    local ns = {}
    for _, f in ipairs({ "Locales.lua", "Core.lua", "Skin.lua", "UI.lua" }) do
        assert(loadfile(dir .. f))("Gulli-Toolkit", ns)
    end
    for _, f in ipairs(W.frames) do
        local onEvent = rawget(f, "_OnEvent")
        if onEvent then onEvent(f, "ADDON_LOADED", "Gulli-Toolkit") end
    end
    return ns
end

return W
