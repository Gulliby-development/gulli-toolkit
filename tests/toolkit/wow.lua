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
        if k == "GetText" then return function() return rawget(t, "_text") end end
        if k == "SetText" then return function(_, v) rawset(t, "_text", v) end end
        if k == "SetEnabled" then return function(_, v) rawset(t, "_enabled", v) end end
        if k == "SetScript" then return function(_, n, f) rawset(t, "_" .. n, f) end end
        if k == "GetScript" then return function(_, n) return rawget(t, "_" .. n) end end
        return function() return stub() end
    end })
end

function Fake(spec)
    W.addons = spec.addons or {}
    W.frames, W.printed, W.reloaded = {}, {}, false
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
        GetAddOnEnableState = function(name) local a = find(name); return (a and a.enabled) and 2 or 0 end,
        EnableAddOn = function(name) find(name).enabled = true end,
        DisableAddOn = function(name) find(name).enabled = false end,
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
