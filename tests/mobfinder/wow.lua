-- A fake WoW client for the Gulli-MobFinder tests: just the API the addon calls.
-- Fake{ plates = { { name = "Bob", guid = "G1", dead = false, secret = false }, ... } }
-- sets the globals; Load() runs the addon files on it and returns the addon table.

local W = {}

local function stub()
    return setmetatable({}, { __index = function(t, k)
        if k == "GetWidth" or k == "GetHeight" or k == "GetStringWidth" or k == "GetVerticalScroll" then
            return function() return 0 end
        end
        if k == "IsShown" or k == "HasFocus" then return function() return false end end
        if k == "GetChecked" then return function() return rawget(t, "_checked") end end
        if k == "SetChecked" then return function(_, v) rawset(t, "_checked", v) end end
        if k == "GetText" then return function() return rawget(t, "_text") end end
        if k == "SetText" then return function(_, v) rawset(t, "_text", v) end end
        if k == "SetScript" then return function(_, n, f) rawset(t, "_" .. n, f) end end
        return function() return stub() end
    end })
end

-- A secret value: a table the fake issecretvalue knows.
local SECRET = {}

function Fake(spec)
    spec = spec or {}
    W.plates = spec.plates or {}
    W.frames, W.printed, W.sounds, W.banners, W.cvars = {}, {}, {}, {}, { nameplateShowEnemies = spec.enemies or "0" }
    W.tickers = {}
    W.target = spec.target

    local function plate(unit)
        local i = tonumber(unit:match("^nameplate(%d+)$") or "")
        return i and W.plates[i]
    end
    C_NamePlate = {
        GetNamePlates = function()
            local list = {}
            for i in ipairs(W.plates) do list[#list + 1] = { namePlateUnitToken = "nameplate" .. i } end
            return list
        end,
    }
    issecretvalue = function(v) return type(v) == "table" and v.secret == SECRET end
    UnitName = function(unit)
        if unit == "target" then return W.target and W.target.name end
        local p = plate(unit)
        if not p then return nil end
        if p.secret then return { secret = SECRET } end
        return p.name
    end
    UnitGUID = function(unit) local p = plate(unit); return p and (p.guid or p.name) end
    UnitIsDead = function(unit) local p = plate(unit); return p and p.dead or false end
    UnitExists = function(unit)
        if unit == "target" then return W.target ~= nil end
        return plate(unit) ~= nil
    end
    UnitIsPlayer = function(unit) return unit == "target" and W.target and W.target.player or false end
    PlaySound = function(id, channel) W.sounds[#W.sounds + 1] = { id = id, channel = channel } end
    SOUNDKIT = { RAID_WARNING = 8959, READY_CHECK = 8960 }
    RaidWarningFrame = stub()
    RaidNotice_AddMessage = function(_, text) W.banners[#W.banners + 1] = text end
    ChatTypeInfo = { RAID_WARNING = { r = 1, g = 0.3, b = 0.1 } }
    GetCVar = function(k) return W.cvars[k] end
    SetCVar = function(k, v) W.cvars[k] = v end
    InCombatLockdown = function() return false end
    GetTime = function() return 100 end
    C_Timer = {
        NewTicker = function(seconds, fn)
            local t = { seconds = seconds, fn = fn }
            t.Cancel = function(self) self.cancelled = true end
            W.tickers[#W.tickers + 1] = t
            return t
        end,
    }
    GetLocale = function() return spec.locale or "enUS" end
    SlashCmdList = {}
    CreateFrame = function() local f = stub(); W.frames[#W.frames + 1] = f; return f end
    UIParent, UISpecialFrames = stub(), {}
    tinsert = table.insert
    UnitClass = function() return "Mage", "MAGE", 8 end
    RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
    STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    print = function(...) W.printed[#W.printed + 1] = table.concat({ ... }, " ") end
    GulliMobFinderDB = spec.db
    GulliToolkit = spec.toolkit
    return W
end

-- The ticker that is running now, if any.
function W.Ticker()
    local t = W.tickers[#W.tickers]
    if t and not t.cancelled then return t end
end

function Load()
    local dir = "Gulli-MobFinder/"
    local ns = {}
    for line in io.lines(dir .. "Gulli-MobFinder.toc") do
        line = line:gsub("\r", "")
        if line:match("%.lua$") then assert(loadfile(dir .. line))("Gulli-MobFinder", ns) end
    end
    Fire("ADDON_LOADED", "Gulli-MobFinder")
    return ns
end

-- Sends a game event to every frame that listens.
function Fire(event, ...)
    for _, f in ipairs(W.frames) do
        local onEvent = rawget(f, "_OnEvent")
        if onEvent then onEvent(f, event, ...) end
    end
end

return W
