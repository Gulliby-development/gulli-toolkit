-- Game settings (CVars) that tweaks change: each change keeps the player's own value in
-- GulliToolkitDB.tweakCVars, so switching the tweak off, or a later login after a crash, puts it
-- back. A setting the client lacks is never touched.

local _, ns = ...

local function api()
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    return get, set
end

local function store()
    GulliToolkitDB = GulliToolkitDB or {}
    GulliToolkitDB.tweakCVars = GulliToolkitDB.tweakCVars or {}
    return GulliToolkitDB.tweakCVars
end

-- Whether the client has this setting.
function ns.HasCVar(name)
    if C_CVar and C_CVar.GetCVarInfo then
        local ok, value = pcall(C_CVar.GetCVarInfo, name)
        return ok and value ~= nil
    end
    local get = api()
    if not get then return false end
    local ok, value = pcall(get, name)
    return ok and value ~= nil
end

function ns.GetCVarValue(name)
    local get = api()
    if not get or not ns.HasCVar(name) then return nil end
    local ok, value = pcall(get, name)
    if ok then return value end
end

-- Sets a CVar for a tweak (owner: its key), keeping the player's value the first time.
function ns.TweakCVar(owner, name, value)
    local _, set = api()
    if not set or not ns.HasCVar(name) then return false end
    value = tostring(value)
    local cur = ns.GetCVarValue(name)
    local all = store()
    if not all[name] then all[name] = { owner = owner, was = cur } end
    all[name].owner, all[name].set = owner, value
    if cur ~= value then pcall(set, name, value) end
    return true
end

-- Gives the player's value back, unless the player changed the setting since.
function ns.TweakCVarRestore(name)
    local all = store()
    local s = all[name]
    if not s then return end
    all[name] = nil
    local _, set = api()
    if not set or s.was == nil or not ns.HasCVar(name) then return end
    if s.set == nil or ns.GetCVarValue(name) == s.set then pcall(set, name, s.was) end
end

-- Every setting a tweak (owner) changed goes back.
function ns.TweakCVarsRestore(owner)
    for name, s in pairs(store()) do
        if s.owner == owner then ns.TweakCVarRestore(name) end
    end
end

-- After the tweaks started: a setting whose tweak no longer runs (switched off before a crash)
-- goes back.
function ns.TweakCVarsCleanup()
    for name, s in pairs(store()) do
        local t = ns.Tweak and ns.Tweak(s.owner)
        if not (t and t.running) then ns.TweakCVarRestore(name) end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event)
    if event ~= "PLAYER_ENTERING_WORLD" then return end
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    ns.TweakCVarsCleanup()
end)
