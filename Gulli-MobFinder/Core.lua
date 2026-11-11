local addonName, ns = ...
local L = ns.L

-- The rules and the game calls: which nameplates match the list, when to alert, the
-- poll timer, the saved settings and the slash commands. UI.lua only shows them.

ns.MIN_INTERVAL, ns.MAX_INTERVAL = 0.5, 60

-- Sounds to pick from: a SOUNDKIT name with its id, for a client that lacks the name.
ns.SOUNDS = {
    { key = "RAID_WARNING", kit = "RAID_WARNING", id = 8959 },
    { key = "READY_CHECK", kit = "READY_CHECK", id = 8960 },
    { key = "ALARM", kit = "ALARM_CLOCK_WARNING_3", id = 12889 },
    { key = "PVP_QUEUE", kit = "PVP_THROUGH_QUEUE", id = 8459 },
    { key = "LEVEL_UP", kit = "LEVELUP", id = 888 },
    { key = "MAP_PING", kit = "MAP_PING", id = 3175 },
}

local DEFAULTS = { enabled = false, names = {}, interval = 2, sound = "RAID_WARNING",
                   again = false, banner = true }

---- Text ----------------------------------------------------------------------

-- Lower case that also covers Cyrillic, which string.lower leaves alone.
function ns.Lower(s)
    s = s:lower()
    s = s:gsub("\208([\144-\159])", function(c) return "\208" .. string.char(c:byte() + 32) end)
    s = s:gsub("\208([\160-\175])", function(c) return "\209" .. string.char(c:byte() - 32) end)
    s = s:gsub("\208\129", "\209\145") -- Ё
    return s
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- One name per line; blank lines and repeats are dropped.
function ns.ParseNames(text)
    local list, seen = {}, {}
    for line in ((text or "") .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        local name = trim(line)
        local key = ns.Lower(name)
        if name ~= "" and not seen[key] then
            seen[key] = true
            list[#list + 1] = name
        end
    end
    return list
end

function ns.Interval(value)
    local n = tonumber((tostring(value or ""):gsub(",", ".")))
    if not n then return nil end
    return math.min(ns.MAX_INTERVAL, math.max(ns.MIN_INTERVAL, n))
end

-- The list entry a nameplate name matches: the whole name or a part of it, any case.
function ns.Match(name, list)
    local low = ns.Lower(name)
    for _, entry in ipairs(list) do
        if low:find(ns.Lower(entry), 1, true) then return entry end
    end
end

---- Nameplates ----------------------------------------------------------------

-- In an instance (and in combat on some builds) creature names are secret values: an
-- addon may not compare them. Such a plate is skipped, never an error.
local function readable(v)
    if issecretvalue and issecretvalue(v) then return false end
    return v ~= nil
end

local function plateUnits()
    local units = {}
    local plates = C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates()
    if plates then
        for _, p in ipairs(plates) do
            local unit = p.namePlateUnitToken or (p.UnitFrame and p.UnitFrame.unit)
            if unit then units[#units + 1] = unit end
        end
    else
        for i = 1, 40 do
            if UnitExists("nameplate" .. i) then units[#units + 1] = "nameplate" .. i end
        end
    end
    return units
end

-- Visible nameplates whose name is on the list: { unit, name, entry, key }.
-- Dead mobs do not count: a corpse is not what the player looks for.
function ns.Scan(list)
    local found = {}
    if #list == 0 then return found end
    for _, unit in ipairs(plateUnits()) do
        local ok, name = pcall(UnitName, unit)
        if ok and readable(name) and not (UnitIsDead and UnitIsDead(unit)) then
            local entry = ns.Match(name, list)
            if entry then
                local guid = UnitGUID and UnitGUID(unit)
                local key = readable(guid) and guid or (name .. "@" .. unit)
                found[#found + 1] = { unit = unit, name = name, entry = entry, key = key }
            end
        end
    end
    return found
end

---- Alerts --------------------------------------------------------------------

local seen = {}
ns.lastFound = nil

function ns.SoundOf(key)
    for _, s in ipairs(ns.SOUNDS) do
        if s.key == key then return (SOUNDKIT and SOUNDKIT[s.kit]) or s.id end
    end
    return ns.SOUNDS[1].id
end

function ns.PlayAlert(key)
    PlaySound(ns.SoundOf(key or ns.db.sound), "Master")
end

local function alert(hits)
    local names = {}
    for _, h in ipairs(hits) do names[#names + 1] = h.name end
    local text = L.FOUND:format(table.concat(names, ", "))
    ns.PlayAlert()
    print("|cff9ad0ffGulli-MobFinder|r: " .. text)
    if ns.db.banner and RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.3, b = 0.1 })
    end
    ns.lastFound = { names = names, at = GetTime and GetTime() or 0 }
    if ns.OnFound then ns.OnFound() end
end

-- One scan. A mob alerts when its plate appears; it alerts again only after its plate
-- was gone for a scan, or on every scan with "again" on. Returns the plates found.
function ns.Tick()
    local found = ns.Scan(ns.db.names)
    local fresh, now = {}, {}
    for _, h in ipairs(found) do
        now[h.key] = true
        if ns.db.again or not seen[h.key] then fresh[#fresh + 1] = h end
    end
    seen = now
    if #fresh > 0 then alert(fresh) end
    return found
end

---- Timer ---------------------------------------------------------------------

local ticker

function ns.Stop()
    if ticker then ticker:Cancel() end
    ticker = nil
end

-- Nameplates exist only while the game shows them, so the enemy plates are turned on
-- (outside combat, where the game allows it).
local function showEnemyPlates()
    if GetCVar and SetCVar and GetCVar("nameplateShowEnemies") ~= "1"
       and not (InCombatLockdown and InCombatLockdown()) then
        SetCVar("nameplateShowEnemies", "1")
        print("|cff9ad0ffGulli-MobFinder|r: " .. L.PLATES_ON)
    end
end

function ns.Start()
    ns.Stop()
    if not ns.db.enabled then return end
    showEnemyPlates()
    seen = {}
    ticker = C_Timer.NewTicker(ns.db.interval, ns.Tick)
    ns.Tick()
end

function ns.Running() return ticker ~= nil end

function ns.SetEnabled(on)
    ns.db.enabled = on and true or false
    if ns.db.enabled then ns.Start() else ns.Stop() end
    if ns.OnState then ns.OnState() end
end

function ns.SetInterval(value)
    local n = ns.Interval(value)
    if not n then return false end
    ns.db.interval = n
    if ticker then ns.Start() end
    return true
end

function ns.SetNames(list)
    ns.db.names = list
end

-- The current target's name, for the "Add target" button.
function ns.AddTarget()
    if not UnitExists("target") or UnitIsPlayer("target") then return nil end
    local name = UnitName("target")
    if not readable(name) then return nil end
    for _, n in ipairs(ns.db.names) do
        if ns.Lower(n) == ns.Lower(name) then return name end
    end
    table.insert(ns.db.names, name)
    return name
end

---- Saved settings and events -------------------------------------------------

local function loadDB()
    GulliMobFinderDB = GulliMobFinderDB or {}
    local d = GulliMobFinderDB
    for k, v in pairs(DEFAULTS) do
        if d[k] == nil then d[k] = type(v) == "table" and {} or v end
    end
    d.interval = ns.Interval(d.interval) or DEFAULTS.interval
    ns.db = d
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:SetScript("OnEvent", function(self, event, arg)
    if event == "ADDON_LOADED" and arg == addonName then
        loadDB()
    elseif event == "PLAYER_LOGIN" then
        if ns.db then ns.Start() end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        -- A plate that appears between two polls alerts at once.
        if ticker then ns.Tick() end
    end
end)

---- Slash commands ------------------------------------------------------------

local function say(text) print("|cff9ad0ffGulli-MobFinder|r: " .. text) end

function ns.Slash(msg)
    msg = trim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = ns.Lower(cmd or "")
    if cmd == "" then
        if ns.Toggle then ns.Toggle() end
    elseif cmd == "on" or cmd == "off" then
        ns.SetEnabled(cmd == "on")
        say(ns.db.enabled and L.ON or L.OFF)
    elseif cmd == "add" and rest ~= "" then
        local list = ns.db.names
        for _, n in ipairs(ns.ParseNames(rest)) do list[#list + 1] = n end
        ns.SetNames(ns.ParseNames(table.concat(list, "\n")))
        say(L.LIST:format(table.concat(ns.db.names, ", ")))
    elseif cmd == "target" then
        local name = ns.AddTarget()
        say(name and L.ADDED:format(name) or L.NO_TARGET)
    elseif cmd == "list" then
        say(#ns.db.names > 0 and L.LIST:format(table.concat(ns.db.names, ", ")) or L.LIST_EMPTY)
    elseif cmd == "clear" then
        ns.SetNames({})
        say(L.LIST_EMPTY)
    else
        say(L.HELP)
    end
    if ns.Refresh then ns.Refresh() end
end

SLASH_GULLIMOBFINDER1 = "/gmf"
SLASH_GULLIMOBFINDER2 = "/mobfinder"
SlashCmdList.GULLIMOBFINDER = ns.Slash
