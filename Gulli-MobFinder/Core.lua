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
                   again = false, banner = true,
                   cooldown = 60,      -- seconds before the same mob alerts again
                   card = true,        -- the card with the model and the Target button
                   cardSeconds = 30,   -- the card closes itself after this (0: stays)
                   mark = false,       -- a skull on the found mob
                   flash = true,       -- the screen edges flash
                   repeatSound = false, -- the sound repeats until the card is closed
                   quietRest = false, quietCombat = false,
                   skipTapped = true,  -- not a mob another player already tagged
                   sources = true,     -- also mouseover, target and the group's targets
                   vignettes = true,   -- also the map's rare markers
                   share = false,      -- tell other Gulli users in the group
                   mobs = {},          -- lower-case name -> { off, exact, count, zone, at }
                   ids = {},           -- npc id -> English name (rares from the zone preset)
                   history = {} }
ns.HISTORY_MAX = 50
ns.COOLDOWNS = { 0, 30, 60, 120, 300 }
ns.CARD_SECONDS = { 10, 30, 60, 0 }
ns.PREFIX = "GulliMF"

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

-- The saved switches of one list entry: off, exact, count, zone, at.
function ns.Info(entry)
    local mobs = ns.db and ns.db.mobs
    if not mobs then return {} end
    local key = ns.Lower(entry)
    mobs[key] = mobs[key] or {}
    return mobs[key]
end

-- The list entry a nameplate name matches: the whole name or a part of it (or the whole
-- name only, for an entry set to exact), any case. Entries switched off do not match.
function ns.Match(name, list)
    local low = ns.Lower(name)
    for _, entry in ipairs(list) do
        local info = ns.db and ns.db.mobs and ns.db.mobs[ns.Lower(entry)] or {}
        if not info.off then
            local e = ns.Lower(entry)
            if (info.exact and low == e) or (not info.exact and low:find(e, 1, true)) then return entry end
        end
    end
end

-- The npc id in a creature GUID ("Creature-0-1-2-3-<id>-..."), or nil.
function ns.NpcID(guid)
    if type(guid) ~= "string" then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
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

-- The units to look at: the nameplates, and with "sources" on the mouseover, the target and
-- what the group targets.
local function units()
    local list = plateUnits()
    if ns.db and ns.db.sources then
        list[#list + 1] = "target"
        list[#list + 1] = "mouseover"
        for i = 1, 4 do list[#list + 1] = "party" .. i .. "target" end
    end
    return list
end

-- A unit that is not worth an alert: a player, a player's pet, a mob another player tagged.
local function skip(unit)
    if UnitIsPlayer and UnitIsPlayer(unit) then return true end
    if UnitPlayerControlled and UnitPlayerControlled(unit) then return true end
    if ns.db and ns.db.skipTapped and UnitIsTapDenied and UnitIsTapDenied(unit) then return true end
    return false
end

-- Visible mobs whose name is on the list, or whose npc id is in the rare list:
-- { unit, name, entry, key }. Dead mobs do not count: a corpse is not what the player looks for.
function ns.Scan(list)
    local found, seenKey = {}, {}
    local ids = ns.db and ns.db.ids or {}
    if #list == 0 and next(ids) == nil then return found end
    for _, unit in ipairs(units()) do
        local ok, name = pcall(UnitName, unit)
        if ok and readable(name) and UnitExists(unit) and not (UnitIsDead and UnitIsDead(unit)) and not skip(unit) then
            local guid = UnitGUID and UnitGUID(unit)
            local entry = ns.Match(name, list)
            local npc = readable(guid) and ns.NpcID(guid)
            if not entry and npc and ids[npc] then entry = ids[npc] end
            local key = readable(guid) and guid or (name .. "@" .. unit)
            if entry and not seenKey[key] then
                seenKey[key] = true
                found[#found + 1] = { unit = unit, name = name, entry = entry, key = key }
            end
        end
    end
    -- The map's markers for rares (vignettes), where the client has them.
    if ns.db and ns.db.vignettes and C_VignetteInfo and C_VignetteInfo.GetVignettes then
        local ok, vs = pcall(C_VignetteInfo.GetVignettes)
        for _, v in ipairs(ok and vs or {}) do
            local okInfo, info = pcall(C_VignetteInfo.GetVignetteInfo, v)
            local name = okInfo and info and info.name
            if readable(name) and type(name) == "string" then
                local entry = ns.Match(name, list)
                local npc = info.objectGUID and readable(info.objectGUID) and ns.NpcID(info.objectGUID)
                if not entry and npc and ids[npc] then entry = ids[npc] end
                local key = (readable(info.objectGUID) and info.objectGUID) or ("v:" .. name)
                if entry and not seenKey[key] then
                    seenKey[key] = true
                    found[#found + 1] = { name = name, entry = entry, key = key, vignette = true }
                end
            end
        end
    end
    return found
end

---- Alerts --------------------------------------------------------------------

local seen, alerted = {}, {}
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

local function now() return GetTime and GetTime() or 0 end

-- Quiet: no sound while resting or in combat, when the player asked so.
function ns.Quiet()
    if ns.db.quietRest and IsResting and IsResting() then return true end
    if ns.db.quietCombat and InCombatLockdown and InCombatLockdown() then return true end
    return false
end

-- Where the player stands: map id, x and y (0-1), and the zone name.
function ns.Here()
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local x, y
    if map and C_Map.GetPlayerMapPosition then
        local pos = C_Map.GetPlayerMapPosition(map, "player")
        if pos then x, y = pos:GetXY() end
    end
    local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
    return map, x, y, zone
end

-- Adds a find to the history (newest first, at most HISTORY_MAX); who is set for a find
-- another player shared.
function ns.Remember(name, map, x, y, zone, who)
    table.insert(ns.db.history, 1, { name = name, map = map, x = x, y = y, zone = zone,
        t = time and time() or 0, who = who })
    for i = #ns.db.history, ns.HISTORY_MAX + 1, -1 do ns.db.history[i] = nil end
end

local function alert(hits)
    local names = {}
    for _, h in ipairs(hits) do names[#names + 1] = h.name end
    local text = L.FOUND:format(table.concat(names, ", "))
    if not ns.Quiet() then ns.PlayAlert() end
    print("|cff9ad0ffGulli-MobFinder|r: " .. text)
    if ns.db.banner and RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.3, b = 0.1 })
    end
    local map, x, y, zone = ns.Here()
    for _, h in ipairs(hits) do
        local info = ns.Info(h.entry)
        info.count = (info.count or 0) + 1
        info.zone, info.at = zone, time and time() or 0
        ns.Remember(h.name, map, x, y, zone)
        if ns.db.mark and h.unit and SetRaidTarget and GetRaidTargetIndex and not GetRaidTargetIndex(h.unit) then
            SetRaidTarget(h.unit, 8)
        end
        if ns.db.share then ns.Share(h.name, map, x, y) end
    end
    if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("MobFinder", text) end
    ns.lastFound = { names = names, at = now(), hit = hits[1] }
    if ns.OnFound then ns.OnFound(hits) end
end

-- One scan. A mob alerts when it comes into sight; it alerts again only after it was gone
-- for a scan and its cooldown passed, or on every scan with "again" on. Returns the mobs found.
function ns.Tick()
    local found = ns.Scan(ns.db.names)
    local fresh, inSight = {}, {}
    local t = now()
    for _, h in ipairs(found) do
        inSight[h.key] = true
        local cooled = not alerted[h.key] or t - alerted[h.key] >= (ns.db.cooldown or 0)
        if ns.db.again or (not seen[h.key] and cooled) then
            fresh[#fresh + 1] = h
            alerted[h.key] = t
        end
    end
    seen = inSight
    if #fresh > 0 then alert(fresh) end
    return found
end

---- Acting on a find ------------------------------------------------------------

-- The macro the Target button runs: /targetexact with the name the game showed.
function ns.TargetMacro(name)
    return "/targetexact " .. name
end

-- Puts a map pin on a history entry (or a find) and tracks it.
function ns.Pin(e)
    if not (e and e.map and e.x and C_Map and C_Map.SetUserWaypoint and UiMapPoint) then return false end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(e.map, e.x, e.y))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    return true
end

-- One line for the group chat: the name, where, and the coordinates. Sent from a click only.
function ns.TellText(name)
    local _, x, y, zone = ns.Here()
    if x and y then return L.TELL:format(name, zone, math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10) end
    return L.TELL_NOPOS:format(name, zone)
end

function ns.TellGroup(name)
    local channel = (IsInRaid and IsInRaid()) and "RAID" or ((IsInGroup and IsInGroup()) and "PARTY") or nil
    if not channel then return false end
    SendChatMessage(ns.TellText(name), channel)
    return true
end

-- Other Gulli users in the group hear about a find: "F1<tab>name<tab>map<tab>x<tab>y".
-- The format is a contract between versions: add a new type, never change this one.
function ns.Share(name, map, x, y)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    local channel = (IsInRaid and IsInRaid()) and "RAID" or ((IsInGroup and IsInGroup()) and "PARTY") or nil
    if not channel then return end
    local msg = table.concat({ "F1", name, tostring(map or ""), x and ("%.4f"):format(x) or "", y and ("%.4f"):format(y) or "" }, "\t")
    C_ChatInfo.SendAddonMessage(ns.PREFIX, msg:sub(1, 250), channel)
end

function ns.Receive(prefix, msg, sender)
    if prefix ~= ns.PREFIX or type(msg) ~= "string" then return nil end
    local me = UnitName and UnitName("player")
    local who = sender and sender:match("^[^%-]+") or sender
    if who == me then return nil end
    local kind, name, map, x, y = msg:match("^(%w+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
    if kind ~= "F1" or not name or name == "" then return nil end
    map, x, y = tonumber(map), tonumber(x), tonumber(y)
    local zone = map and C_Map and C_Map.GetMapInfo and (C_Map.GetMapInfo(map) or {}).name or ""
    ns.Remember(name, map, x, y, zone, who)
    local text = L.SHARED:format(who or "?", name)
    print("|cff9ad0ffGulli-MobFinder|r: " .. text)
    if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("MobFinder", text) end
    if ns.Refresh then ns.Refresh() end
    return name
end

---- The rare preset ---------------------------------------------------------------

-- The rares of the zone the player is in, from Data.lua: { { id, name, min, max, elite } }.
-- The zone is found by its name: the client gives area names in its own language.
function ns.ZoneRares(zone)
    zone = zone or select(4, ns.Here())
    local out = {}
    if not ns.RARES or not zone or zone == "" then return out end
    for area, list in pairs(ns.RARES) do
        local info = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(area)
        if info == zone then
            for _, r in ipairs(list) do out[#out + 1] = r end
        end
    end
    table.sort(out, function(a, b) return a[3] < b[3] end)
    return out
end

-- Adds the zone's rares to the watched ids; returns how many were new.
function ns.AddZoneRares(zone)
    local n = 0
    for _, r in ipairs(ns.ZoneRares(zone)) do
        if not ns.db.ids[r[1]] then
            ns.db.ids[r[1]] = r[2]
            n = n + 1
        end
    end
    return n
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
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "NAME_PLATE_UNIT_ADDED", "UPDATE_MOUSEOVER_UNIT",
                     "PLAYER_TARGET_CHANGED", "VIGNETTE_MINIMAP_UPDATED", "CHAT_MSG_ADDON" }) do
    f:RegisterEvent(e)
end
f:SetScript("OnEvent", function(self, event, a1, ...)
    if event == "ADDON_LOADED" and a1 == addonName then
        loadDB()
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX) end
    elseif event == "ADDON_LOADED" then
        return
    elseif event == "PLAYER_LOGIN" then
        if ns.db then ns.Start() end
    elseif event == "CHAT_MSG_ADDON" then
        local msg, _, sender = ...
        ns.Receive(a1, msg, sender)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        -- A plate that appears between two polls alerts at once.
        if ticker then ns.Tick() end
    elseif ticker and ns.db.sources then
        ns.Tick()
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
        for k in pairs(ns.db.ids) do ns.db.ids[k] = nil end
        say(L.LIST_EMPTY)
    elseif cmd == "rares" then
        say(L.RARES_ADDED:format(ns.AddZoneRares()))
    else
        say(L.HELP)
    end
    if ns.Refresh then ns.Refresh() end
end

SLASH_GULLIMOBFINDER1 = "/gmf"
SLASH_GULLIMOBFINDER2 = "/mobfinder"
SlashCmdList.GULLIMOBFINDER = ns.Slash
