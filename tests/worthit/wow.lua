-- A fake WoW client for the Gulli-WorthIt tests: the shared basics plus the quest log, the bags,
-- bag tooltips, the map and its waypoint.
local W = {}

local function stub()
    return setmetatable({}, { __index = function(t, k)
        if k == "GetWidth" then return function() return 400 end end
        if k == "GetHeight" then return function() return 300 end end
        if k == "GetStringWidth" or k == "GetValue" then return function() return 0 end end
        if k == "IsShown" then return function() return rawget(t, "_shown") == true end end
        if k == "Show" then return function() rawset(t, "_shown", true) end end
        if k == "Hide" then return function() rawset(t, "_shown", false) end end
        if k == "SetShown" then return function(_, v) rawset(t, "_shown", v and true or false) end end
        if k == "IsEnabled" then return function() return rawget(t, "_enabled") ~= false end end
        if k == "SetEnabled" then return function(_, v) rawset(t, "_enabled", v and true or false) end end
        if k == "GetText" then return function() return rawget(t, "_text") end end
        if k == "SetText" then return function(_, v) rawset(t, "_text", v) end end
        if k == "GetNumber" then return function() return tonumber(rawget(t, "_text")) or 0 end end
        if k == "SetScript" then return function(_, n, f) rawset(t, "_" .. n, f) end end
        if k == "HookScript" then return function(_, n, f) rawset(t, "_" .. n, f) end end
        if k == "GetScript" then return function(_, n) return rawget(t, "_" .. n) end end
        if k == "SetAttribute" then return function(_, n, v) rawget(t, "_attr")[n] = v end end
        if k == "GetAttribute" then return function(_, n) return rawget(t, "_attr")[n] end end
        if k == "GetName" then return function() return rawget(t, "_name") end end
        if k == "RegisterEvent" then return function(_, e) rawget(t, "_events")[e] = true end end
        if k == "UnregisterEvent" then return function(_, e) rawget(t, "_events")[e] = nil end end
        return function() return stub() end
    end })
end
W.stub = stub

-- The globals every Gulli module uses. spec: locale, level, class, now, combat.
function W.Base(spec)
    W.frames, W.printed, W.timers, W.sent = {}, {}, {}, {}
    W.now = spec.now or 100000
    W.combat = spec.combat or false
    W.level = spec.level or 60
    GetLocale = function() return spec.locale or "enUS" end
    UnitName = function(u) if u == "player" then return spec.name or "Tester" end end
    UnitClass = function() return "Priest", spec.class or "PRIEST" end
    UnitLevel = function(u) if u == "player" then return W.level end return 60 end
    UnitRace = function() return "Human", spec.race or "Human" end
    UnitFactionGroup = function() return spec.faction or "Alliance" end
    GetRealmName = function() return "Realm" end
    InCombatLockdown = function() return W.combat end
    time = function() return W.now end
    GetTime = function() return W.now end
    SlashCmdList = {}
    CreateFrame = function(_, name)
        local f = stub()
        rawset(f, "_events", {})
        rawset(f, "_attr", {})
        rawset(f, "_name", name)
        W.frames[#W.frames + 1] = f
        return f
    end
    UIParent, GameTooltip, UISpecialFrames = stub(), stub(), {}
    tinsert, tremove, wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end
    strtrim = function(s) return (s or ""):match("^%s*(.-)%s*$") end
    C_Timer = { After = function(d, fn) W.timers[#W.timers + 1] = { at = W.now + (d or 0), fn = fn } end,
                NewTicker = function(_, fn) return stub() end }
    hooksecurefunc = function() end
    PlaySound = function() end
    SOUNDKIT = {}
    RAID_CLASS_COLORS = nil
    issecretvalue = nil
    ChatFrame_OpenChat = function() end
    print = function(...) W.printed[#W.printed + 1] = table.concat({ ... }, " ") end
    GulliToolkit = nil
end

-- Runs the addon files in TOC order with one shared addon table, then ADDON_LOADED.
function W.Load(addon, files)
    local ns = {}
    for _, f in ipairs(files) do
        assert(loadfile(addon .. "/" .. f))(addon, ns)
    end
    W.Fire("ADDON_LOADED", addon)
    return ns
end

-- Sends an event to every frame that registered it (ADDON_LOADED always).
function W.Fire(event, ...)
    for _, f in ipairs(W.frames) do
        local on = rawget(f, "_OnEvent")
        if on and (event == "ADDON_LOADED" or rawget(f, "_events")[event]) then on(f, event, ...) end
    end
end

-- Runs the timers that are due by now.
function W.RunTimers()
    local t = W.timers
    W.timers = {}
    for _, x in ipairs(t) do
        if x.at <= W.now then x.fn() else W.timers[#W.timers + 1] = x end
    end
end

-- Every language has every English key, with the same placeholders, and no extra key.
function W.CheckLocales(ns)
    for _, tag in ipairs(ns.TAGS) do
        local t = ns.T[tag]
        assert(t, "no table for " .. tag)
        for key, text in pairs(ns.T.en) do
            assert(t[key], tag .. " misses " .. key)
            for _, p in ipairs({ "%%d", "%%s" }) do
                local _, a = text:gsub(p, "")
                local _, b = t[key]:gsub(p, "")
                assert(a == b, tag .. "." .. key .. " placeholders differ")
            end
        end
        for key in pairs(t) do assert(ns.T.en[key], tag .. " has an extra key " .. key) end
    end
end

-- A tiny test runner: W.test(name, fn), W.eq(a, b, what), W.finish().
local failed, count = 0, 0
function W.test(name, fn)
    count = count + 1
    local ok, err = pcall(fn)
    if ok then io.write("ok   ", name, "\n")
    else failed = failed + 1; io.write("FAIL ", name, "\n     ", tostring(err), "\n") end
end
function W.eq(a, b, what)
    if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
function W.finish()
    io.write(string.format("%d/%d passed\n", count - failed, count))
    os.exit(failed == 0 and 0 or 1)
end

-- spec: done, log, ready (quest id sets), bags (bag 1-4 -> slots), family (bag -> family),
-- slots (item id -> slots, 10 for the rest), raceId, classId, zone (area id the player is in),
-- kalimdor, x, y, items (item id -> count in the bags), toys and pets (item id -> true: known), db, cdb.
local CLASS_ID = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }
function Fake(spec)
    spec = spec or {}
    W.Base(spec)
    W.done, W.log, W.ready = spec.done or {}, spec.log or {}, spec.ready or {}
    W.bags, W.family, W.slots = spec.bags or { 6, 6, 8, 8 }, spec.family or {}, spec.slots or {}
    W.zone, W.kalimdor, W.x, W.y = spec.zone, spec.kalimdor, spec.x, spec.y
    W.items = spec.items or {}
    W.bank = spec.bank or {}
    W.toys, W.pets = spec.toys or {}, spec.pets or {}
    PlayerHasToy = function(id) return W.toys[id] == true end
    -- a pet item's species is 100000 + its id; GetNumCollectedInfo counts the pets known of it
    C_PetJournal = {
        GetPetInfoByItemID = function(id) return "Pet", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 100000 + id end,
        GetNumCollectedInfo = function(species) return W.pets[species - 100000] and 1 or 0, 3 end,
    }
    W.pins, W.cleared, W.toasts, W.notes, W.maps = {}, 0, {}, {}, {}
    UnitRace = function() return "Race", "Race", spec.raceId or 1 end
    UnitClass = function() return "Class", spec.class or "PRIEST", CLASS_ID[spec.class or "PRIEST"] end
    LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue",
        PRIEST = "Priest", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
    CONTAINER_SLOTS = spec.slotText or "%d Slot %s"
    C_QuestLog = {
        IsQuestFlaggedCompleted = function(id) return W.done[id] == true end,
        IsOnQuest = function(id) return W.log[id] == true end,
        ReadyForTurnIn = function(id) return W.ready[id] == true end,
        GetTitleForQuestID = function() return nil end,
    }
    C_Container = {
        GetContainerNumSlots = function(bag) if bag == 0 then return 16 end return W.bags[bag] or 0 end,
        GetContainerNumFreeSlots = function(bag) return 0, W.family[bag] or 0 end,
        ContainerIDToInventoryID = function(bag) return 30 + bag end,
    }
    GetInventoryItemID = function(_, slot) return 5000 + slot end
    C_Item = {
        GetItemNameByID = function(id) return "Item" .. id end,
        GetItemIconByID = function(id) return "icon" .. id end,
        GetItemQualityByID = function() return 1 end,
        RequestLoadItemDataByID = function() end,
        GetItemCount = function(id, bank) return (W.items[id] or 0) + (bank and W.bank and W.bank[id] or 0) end,
    }
    C_TooltipInfo = { GetItemByID = function(id)
        local n = W.slots[id]
        if n == false then return { lines = { { leftText = "Item" .. id } } } end
        return { lines = { { leftText = "Item" .. id }, { leftText = CONTAINER_SLOTS:gsub("%%%d?%$?d", tostring(n or 10)):gsub("%%%d?%$?s", "Bag") } } }
    end }
    local function zoneMap() return W.zone and (10000 + W.zone) end
    C_Map = {
        GetAreaInfo = function(id) return "Area" .. id end,
        GetBestMapForUnit = function() return zoneMap() end,
        GetMapInfo = function(id)
            if id == 1414 or id == 1415 then return { mapType = 2, name = "Continent", parentMapID = 0 } end
            return { mapType = 3, name = "Area" .. (id - 10000), parentMapID = W.kalimdor and 1414 or 1415 }
        end,
        GetPlayerMapPosition = function()
            if not W.x then return nil end
            return { GetXY = function() return W.x / 100, W.y / 100 end }
        end,
        GetMapChildrenInfo = function(c)
            local out = {}
            if c == 1415 then
                for _, a in ipairs({ 1, 10, 12, 38, 40, 85 }) do out[#out + 1] = { name = "Area" .. a, mapID = 10000 + a } end
            else
                for _, a in ipairs({ 17, 141, 148, 215, 406 }) do out[#out + 1] = { name = "Area" .. a, mapID = 10000 + a } end
            end
            return out
        end,
        SetUserWaypoint = function(p) W.pins[#W.pins + 1] = p end,
        ClearUserWaypoint = function() W.cleared = W.cleared + 1 end,
        OpenWorldMap = function(id) W.maps[#W.maps + 1] = id end,
    }
    UiMapPoint = { CreateFromCoordinates = function(id, x, y) return { map = id, x = x, y = y } end }
    C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
    -- the addon's own call taints the map's pins (SetPassThroughButtons is blocked)
    OpenWorldMap = function(id) W.tainted = id end
    WorldMapFrame = nil
    TomTom = nil
    GulliHUD = nil
    GulliWorthItDB = spec.db
    GulliWorthItCharDB = spec.cdb
    if spec.hub then
        GulliToolkit = { Register = function(t) W.registered = t end,
                         Notify = function(key, text) W.notes[#W.notes + 1] = { key, text } end }
    end
    return W
end

-- The last pin as { area, x, y } (map percent).
function W.Pin()
    local p = W.pins[#W.pins]
    return p and { p.map - 10000, math.floor(p.x * 1000 + 0.5) / 10, math.floor(p.y * 1000 + 0.5) / 10 }
end

function Load()
    local ns = W.Load("Gulli-WorthIt", { "Locales.lua", "Tips.lua", "Data.lua", "Core.lua", "Skin.lua", "UI.lua" })
    ns.Skin.Toast = function(o) W.toasts[#W.toasts + 1] = o end
    return ns
end

return W
