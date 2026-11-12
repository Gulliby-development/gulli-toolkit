-- Attunements and dungeon keys: the quest chains each character must finish before a raid or
-- a dungeon door lets them in.
-- Each character saves its progress when it plays, so the window shows every character.

local ADDON, ns = ...
local L = ns.L

-- Steps: quest id, English quest name (the game's own name is used when it knows the quest),
-- who starts it (English name) and the area id of where (the game names it in your language).
-- anyOf: one of these quests is enough. after: the steps that must be done first (by quest
-- id); without it a step follows the one above it, so steps with the same `after` run side by
-- side. tag: "elite", "dungeon" or "raid" (a step whose area is a dungeon is "dungeon" anyway).
-- Ids and names come from the QuestieDB Forever data.
-- Only what WoW Forever has: a raid or dungeon that is not in Forever does not belong here.
-- Order is the order in the window: raids first, then the dungeon keys.
local BRD, LBRS, SW, BURNING = 1584, 1583, 1519, 46
local WPL, TIRISFAL, TANARIS, DESOLACE, MARAUDON = 28, 85, 440, 405, 2100
ns.RAIDS = {
    { key = "ONY", area = 2159, faction = "Alliance", item = 16309, steps = {
        { 4182, "Dragonkin Menace", "Helendis Riverhorn", BURNING },
        { 4183, "The True Masters", "Helendis Riverhorn", BURNING },
        { 4184, "The True Masters", "Magistrate Solomon", 44 },
        { 4185, "The True Masters", "Highlord Bolvar Fordragon", SW },
        { 4186, "The True Masters", "Highlord Bolvar Fordragon", SW },
        { 4223, "The True Masters", "Magistrate Solomon", 44 },
        { 4224, "The True Masters", "Marshal Maxwell", BURNING },
        { 4241, "Marshal Windsor", "Marshal Maxwell", BURNING },
        { 4242, "Abandoned Hope", "Marshal Windsor", BRD },
        { 4264, "A Crumpled Up Note", "A Crumpled Up Note", BRD },
        { 4282, "A Shred of Hope", "Marshal Windsor", BRD },
        { 4322, "Jail Break!", "Marshal Windsor", BRD },
        { 6402, "Stormwind Rendezvous", "Marshal Maxwell", BURNING },
        { 6403, "The Great Masquerade", "Reginald Windsor", SW },
        { 6501, "The Dragon's Eye", "Highlord Bolvar Fordragon", SW },
        { 6502, "Drakefire Amulet", "Haleh", 618, tag = "raid" },
    } },
    { key = "ONY", area = 2159, faction = "Horde", item = 16309, steps = {
        { 4903, "Warlord's Command", "Warlord Goretooth", 3 },
        { 4941, "Eitrigg's Wisdom", "Warlord Goretooth", 3 },
        { 4974, "For The Horde!", "Thrall", 1637 },
        { 6566, "What the Wind Carries", "Thrall", 1637 },
        { 6567, "The Champion of the Horde", "Thrall", 1637 },
        { 6568, "The Testament of Rexxar", "Rexxar", 357 },
        { 6569, "Oculus Illusions", "Myranda the Hag", 28 },
        { 6570, "Emberstrife", "Myranda the Hag", 28, tag = "elite" },
        { 6582, "The Test of Skulls, Scryer", "Emberstrife", 15, after = { 6570 }, tag = "elite" },
        { 6583, "The Test of Skulls, Somnus", "Emberstrife", 15, after = { 6570 }, tag = "elite" },
        { 6584, "The Test of Skulls, Chronalis", "Emberstrife", 15, after = { 6570 }, tag = "elite" },
        { 6585, "The Test of Skulls, Axtroz", "Emberstrife", 15, after = { 6570 }, tag = "elite" },
        { 6601, "Ascension...", "Emberstrife", 15, after = { 6582, 6583, 6584, 6585 }, tag = "elite" },
        { 6602, "Blood of the Black Dragon Champion", "Rexxar", 357, tag = "raid" },
    } },
    { key = "UBRS", area = 1583, item = 12344, steps = {
        { 4742, "Seal of Ascension", "Vaelan", LBRS },
        { 4743, "Seal of Ascension", "Vaelan", LBRS, tag = "raid" },
    } },
    -- Dungeon keys from quest chains. Keys that only drop (Key to the City, Crescent Key) need no tracking.
    { key = "BRD", area = BRD, item = 11000, steps = {
        { 3801, "Dark Iron Legacy", "Franclorn Forgewright", BRD },
        { 3802, "Dark Iron Legacy", "Franclorn Forgewright", BRD },
    } },
    { key = "SCHOLO", area = 2057, faction = "Alliance", item = 13704, steps = {
        { 5092, "Clear the Way", "Commander Ashlam Valorfist", WPL },
        { 5097, "All Along the Watchtowers", "Commander Ashlam Valorfist", WPL },
        { 5533, "Scholomance", "Commander Ashlam Valorfist", WPL },
        { 5537, "Skeletal Fragments", "Alchemist Arbington", WPL },
        { 5538, "Mold Rhymes With...", "Alchemist Arbington", WPL },
        { 5801, "Fire Plume Forged", "Krinkle Goodsteel", TANARIS },
        { 5803, "Araj's Scarab", "Alchemist Arbington", WPL },
        { 5505, "The Key to Scholomance", "Alchemist Arbington", WPL },
    } },
    { key = "SCHOLO", area = 2057, faction = "Horde", item = 13704, steps = {
        { 5096, "Scarlet Diversions", "High Executor Derrington", TIRISFAL },
        { 5098, "All Along the Watchtowers", "High Executor Derrington", TIRISFAL },
        { 838, "Scholomance", "High Executor Derrington", TIRISFAL },
        { 964, "Skeletal Fragments", "Apothecary Dithers", TIRISFAL },
        { 5514, "Mold Rhymes With...", "Apothecary Dithers", TIRISFAL },
        { 5802, "Fire Plume Forged", "Krinkle Goodsteel", TANARIS },
        { 5804, "Araj's Scarab", "Apothecary Dithers", TIRISFAL },
        { 5511, "The Key to Scholomance", "High Executor Derrington", TIRISFAL },
    } },
    { key = "MARA", area = MARAUDON, item = 17191, steps = {
        { 7044, "Legends of Maraudon", "Cavindra", DESOLACE },
        { 7046, "The Scepter of Celebras", "Celebras the Redeemed", MARAUDON },
    } },
}

-- Generated by tools/attune/check_data.py --info: quest -> { level, x, y, items asked for (id, count) }.
ns.INFO = {
    [838] = { 55, 83.1, 68.9, {  } },
    [964] = { 55, 83.3, 69.2, { 14619, 1 } },
    [3801] = { 48, 0, 0, {  } },
    [3802] = { 48, 0, 0, { 10999, 1 } },
    [4182] = { 48, 85.8, 69, {  } },
    [4183] = { 48, 85.8, 69, {  } },
    [4184] = { 48, 24.9, 44.5, {  } },
    [4185] = { 48, 80.2, 38.4, {  } },
    [4186] = { 48, 80.2, 38.4, {  } },
    [4223] = { 48, 24.9, 44.5, {  } },
    [4224] = { 48, 84.7, 69, {  } },
    [4241] = { 48, 84.7, 69, {  } },
    [4242] = { 48, 0, 0, {  } },
    [4264] = { 50, 0, 0, {  } },
    [4282] = { 50, 0, 0, { 11464, 1, 11465, 1 } },
    [4322] = { 50, 0, 0, {  } },
    [4742] = { 57, 0, 0, { 12336, 1, 12335, 1, 12337, 1, 12219, 1 } },
    [4743] = { 57, 0, 0, { 12324, 1 } },
    [4903] = { 55, 5.8, 47.5, { 12562, 1 } },
    [4941] = { 55, 5.8, 47.5, {  } },
    [4974] = { 55, 31.7, 37.8, { 12630, 1 } },
    [5092] = { 50, 42.7, 84, {  } },
    [5096] = { 50, 83.1, 68.9, {  } },
    [5097] = { 50, 42.7, 84, {  } },
    [5098] = { 50, 83.1, 68.9, {  } },
    [5505] = { 55, 42.7, 83.8, {  } },
    [5511] = { 55, 83.1, 68.9, {  } },
    [5514] = { 55, 83.3, 69.2, {  } },
    [5533] = { 55, 42.7, 84, {  } },
    [5537] = { 55, 42.7, 83.8, { 14619, 1 } },
    [5538] = { 55, 42.7, 83.8, {  } },
    [5801] = { 55, 51.5, 28.8, { 14645, 1 } },
    [5802] = { 55, 51.5, 28.8, { 14645, 1 } },
    [5803] = { 55, 42.7, 83.8, { 14610, 1 } },
    [5804] = { 55, 83.3, 69.2, { 14610, 1 } },
    [6402] = { 50, 84.7, 69, {  } },
    [6403] = { 50, 0, 0, {  } },
    [6501] = { 50, 80.2, 38.4, {  } },
    [6502] = { 50, 54.5, 51.2, { 16663, 1 } },
    [6566] = { 55, 31.7, 37.8, {  } },
    [6567] = { 55, 31.7, 37.8, {  } },
    [6568] = { 55, 46.4, 18.2, {  } },
    [6569] = { 55, 50.8, 77.8, { 16786, 1 } },
    [6570] = { 55, 50.8, 77.8, {  } },
    [6582] = { 55, 56.7, 87.7, { 16869, 1 } },
    [6583] = { 55, 56.7, 87.7, { 16870, 1 } },
    [6584] = { 55, 56.7, 87.7, { 16871, 1 } },
    [6585] = { 55, 56.7, 87.7, { 16872, 1 } },
    [6601] = { 55, 56.7, 87.7, {  } },
    [6602] = { 55, 46.4, 18.2, { 16663, 1 } },
    [7044] = { 41, 32.1, 64, { 17703, 1, 17702, 1 } },
    [7046] = { 41, 0, 0, {  } },
}

-- Areas that are dungeons: a step there is a dungeon step.
local INSTANCE = { [BRD] = true, [LBRS] = true, [MARAUDON] = true, [2057] = true, [2017] = true }

-- Settings; each change through ns.Set.
ns.DEFAULTS = { groupMsg = true, tooltip = true, announce = false, onlyAvail = false, hideEmpty = false }

function ns.Get(key)
    local v = ns.db and ns.db.settings and ns.db.settings[key]
    if v == nil then return ns.DEFAULTS[key] end
    return v
end

function ns.Set(key, value)
    if not ns.db then return end
    ns.db.settings = ns.db.settings or {}
    ns.db.settings[key] = value
    if ns.Refresh then ns.Refresh() end
end

function ns.Reset()
    if not ns.db then return end
    ns.db.settings = {}
    if ns.Refresh then ns.Refresh() end
end

-- What a step needs: { level, tag, items = { { id, count } }, x, y }.
function ns.Needs(step)
    local i = ns.INFO[step[1]] or { 0, 0, 0, {} }
    local items = {}
    for k = 1, #(i[4] or {}), 2 do items[#items + 1] = { id = i[4][k], count = i[4][k + 1] or 1 } end
    return { level = i[1] or 0, tag = step.tag or (INSTANCE[step[4]] and "dungeon") or nil, items = items,
             x = i[2] or 0, y = i[3] or 0 }
end

-- Every quest id the module checks.
local function allIds()
    local ids = {}
    for _, r in ipairs(ns.RAIDS) do
        for _, s in ipairs(r.steps) do
            for _, id in ipairs(s.anyOf or { s[1] }) do ids[#ids + 1] = id end
        end
    end
    return ids
end

-- Game API wrappers.
local Q = C_QuestLog or {}
local function questDone(id)
    if Q.IsQuestFlaggedCompleted then return Q.IsQuestFlaggedCompleted(id) end
    return IsQuestFlaggedCompleted and IsQuestFlaggedCompleted(id) or false
end
local function onQuest(id)
    if Q.IsOnQuest then return Q.IsOnQuest(id) end
    return Q.GetLogIndexForQuestID and Q.GetLogIndexForQuestID(id) ~= nil or false
end
local function itemCount(id)
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    return count and count(id, true) or 0
end
local function areaName(id)
    local name = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(id)
    return (type(name) == "string" and name ~= "") and name or nil
end
function ns.QuestName(step)
    local t = Q.GetTitleForQuestID and Q.GetTitleForQuestID(step[1])
    return (t and t ~= "") and t or step[2]
end
function ns.RaidName(raid)
    return areaName(raid.area) or L["RAID_" .. raid.key]
end
function ns.Where(step)
    local zone = areaName(step[4])
    return zone and L.WHERE:format(step[3], zone) or step[3]
end

function ns.CharKey()
    return UnitName("player") .. "-" .. (GetRealmName() or "")
end

-- Saves this character's progress.
function ns.Scan()
    local done, active = {}, {}
    for _, id in ipairs(allIds()) do
        if questDone(id) then done[id] = true elseif onQuest(id) then active[id] = true end
    end
    local items = {}
    for _, r in ipairs(ns.RAIDS) do
        if r.item and itemCount(r.item) > 0 then items[r.item] = true end
    end
    local _, class = UnitClass("player")
    local old = ns.db.chars[ns.CharKey()]
    ns.db.chars[ns.CharKey()] = { name = UnitName("player"), class = class, level = UnitLevel("player"),
                                  faction = UnitFactionGroup("player"), done = done, active = active,
                                  items = items, t = time() }
    if old then ns.Announce(old, ns.db.chars[ns.CharKey()]) end
    if ns.Refresh then ns.Refresh() end
end

-- Progress of one character on one raid: { raid, steps = { { step, state, open } }, done,
-- total, pct, next (the first open step), nexts (every open step), ready }. state: "done",
-- "active" or "todo"; open: not done and every step before it is.
function ns.Progress(char, raid)
    local out = { raid = raid, steps = {}, done = 0, total = #raid.steps, nexts = {} }
    local doneById, prev = {}, nil
    for _, s in ipairs(raid.steps) do
        local state = "todo"
        for _, id in ipairs(s.anyOf or { s[1] }) do
            if char.done[id] then state = "done"; break end
            if char.active[id] then state = "active" end
        end
        local open = state ~= "done"
        for _, id in ipairs(s.after or (prev and { prev[1] }) or {}) do
            if not doneById[id] then open = false end
        end
        doneById[s[1]] = state == "done"
        out.steps[#out.steps + 1] = { step = s, state = state, open = open }
        if state == "done" then out.done = out.done + 1 end
        if open then
            out.nexts[#out.nexts + 1] = s
            out.next = out.next or s
        end
        prev = s
    end
    -- A step done out of order (an old save) still leaves a next step.
    if not out.next then
        for _, x in ipairs(out.steps) do
            if x.state ~= "done" then out.next = x.step; out.nexts[1] = x.step; break end
        end
    end
    out.pct = out.total > 0 and math.floor(out.done * 100 / out.total) or 0
    -- The amulet or the key in the bags means the chain is done even if the log says otherwise.
    out.ready = out.done == out.total or (raid.item ~= nil and char.items and char.items[raid.item] == true)
    if out.ready then out.pct, out.next, out.nexts = 100, nil, {} end
    return out
end

-- Whether a chain is worth showing to this character: started, or its first step is at most
-- five levels away.
function ns.Available(char, raid)
    local p = ns.Progress(char, raid)
    if p.done > 0 or p.ready then return true end
    return (char.level or 0) + 5 >= ns.Needs(raid.steps[1]).level
end

-- Where a step starts, as a map pin (and a TomTom arrow when it is installed).
local MAP = C_Map or {}
local KALIMDOR, EASTERN = 1414, 1415
local mapOfZone
function ns.SetPin(step)
    local n = ns.Needs(step)
    local zone = areaName(step[4])
    if n.x == 0 or not zone or not (MAP.SetUserWaypoint and UiMapPoint and MAP.GetMapChildrenInfo) then return false end
    if not mapOfZone then
        mapOfZone = {}
        for _, c in ipairs({ KALIMDOR, EASTERN }) do
            for _, m in ipairs(MAP.GetMapChildrenInfo(c, nil, true) or {}) do
                if m.name and not mapOfZone[m.name] then mapOfZone[m.name] = m.mapID end
            end
        end
    end
    local id = mapOfZone[zone]
    if not id then return false end
    MAP.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(id, n.x / 100, n.y / 100))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    if TomTom and TomTom.AddWaypoint then TomTom:AddWaypoint(id, n.x / 100, n.y / 100, { title = step[3] }) end
    print("|cff9ad0ffGulli Attune|r: " .. L.PIN_SET:format(ns.Where(step)))
    return true
end

-- Bags of this character: how many of an item.
function ns.Have(id) return itemCount(id) end

-- One line per raid of a character, short: "ONY=9/16,UBRS=R". The group message and the export use it.
function ns.Short(char)
    local parts = {}
    for _, r in ipairs(ns.RaidsFor(char)) do
        local p = ns.Progress(char, r)
        parts[#parts + 1] = r.key .. "=" .. (p.ready and "R" or (p.done .. "/" .. p.total))
    end
    return table.concat(parts, ",")
end

-- Reads ns.Short back: key -> { done, total, ready }.
function ns.ParseShort(text)
    local out = {}
    for key, v in (text or ""):gmatch("([%u]+)=([%dR/]+)") do
        if v == "R" then
            out[key] = { ready = true }
        else
            local d, t = v:match("^(%d+)/(%d+)$")
            if d then out[key] = { done = tonumber(d), total = tonumber(t), ready = false } end
        end
    end
    return out
end

-- Group and guild: addon messages on the prefix GulliAT. "S\t<short>" is a state, "H" asks
-- for one. The format is a contract between versions: add a new type, never change one.
ns.PREFIX = "GulliAT"
ns.others = {}
local function send(msg, channel, target)
    if not ns.Get("groupMsg") then return false end
    local C = C_ChatInfo or {}
    local fn = C.SendAddonMessage or SendAddonMessage
    if not fn then return false end
    fn(ns.PREFIX, msg:sub(1, 240), channel, target)
    return true
end

local function myChar() return ns.db and ns.db.chars[ns.CharKey()] end

function ns.SendState(channel, target)
    local c = myChar()
    if not c then return false end
    return send("S\t" .. ns.Short(c), channel, target)
end

local function groupChannel()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
end

-- Asks the guild (or the group) for their attunements.
function ns.AskGuild()
    if not (IsInGuild and IsInGuild()) then return false end
    return send("H", "GUILD")
end

function ns.Receive(prefix, msg, channel, sender)
    if prefix ~= ns.PREFIX or not ns.Get("groupMsg") then return end
    local name = (sender or ""):match("^[^-]+") or sender
    if name == UnitName("player") then return end
    if msg == "H" then
        ns.SendState(channel == "WHISPER" and "WHISPER" or channel, channel == "WHISPER" and sender or nil)
        return
    end
    local short = msg:match("^S\t(.*)$")
    if short then
        ns.others[name] = { raids = ns.ParseShort(short), t = time(), channel = channel }
        if ns.Refresh then ns.Refresh() end
    end
end

-- Group members with what they told (or nil when they have no module): { name, raids }.
function ns.Group()
    local out = {}
    local n = (IsInRaid and IsInRaid()) and 40 or 4
    local prefix = (IsInRaid and IsInRaid()) and "raid" or "party"
    for i = 1, n do
        local unit = prefix .. i
        if UnitExists and UnitExists(unit) then
            local name = UnitName(unit)
            if name and name ~= UnitName("player") then
                out[#out + 1] = { name = name, raids = ns.others[name] and ns.others[name].raids }
            end
        end
    end
    return out
end

-- Everyone heard from (group and guild), by name.
function ns.Heard()
    local out = {}
    for name, o in pairs(ns.others) do out[#out + 1] = { name = name, raids = o.raids, channel = o.channel } end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- The members of the group without a raid's attunement (unknown counts as without).
function ns.Missing(key)
    local out = {}
    for _, m in ipairs(ns.Group()) do
        local r = m.raids and m.raids[key]
        if not (r and r.ready) then out[#out + 1] = m.name end
    end
    local c = myChar()
    if c then
        for _, r in ipairs(ns.RaidsFor(c)) do
            if r.key == key and not ns.Progress(c, r).ready then table.insert(out, 1, UnitName("player")) end
        end
    end
    return out
end

-- Tells the group who has no access to a raid; runs from a click.
function ns.TellGroup(key)
    local channel = groupChannel()
    if not channel or not SendChatMessage then return false end
    local who = ns.Missing(key)
    local name = L["RAID_" .. key]
    SendChatMessage(#who == 0 and L.ALL_READY:format(name) or L.WITHOUT:format(name, table.concat(who, ", ")), channel)
    return true
end

-- Lines for a player's tooltip: one per raid they started or finished.
function ns.TooltipLines(name)
    local o = name and ns.others[name]
    if not (o and ns.Get("tooltip")) then return {} end
    local out, seen = {}, {}
    for _, r in ipairs(ns.RAIDS) do
        local x = o.raids[r.key]
        if x and not seen[r.key] and (x.ready or (x.done or 0) > 0) then
            seen[r.key] = true
            out[#out + 1] = L.TT_LINE:format(L["RAID_" .. r.key],
                x.ready and L.READY or L.STEPS:format(x.done, x.total))
        end
    end
    return out
end

-- Every character as one text: "GAT1;Name-Realm:CLASS:60:ONY=9/16,UBRS=R;...".
function ns.Export()
    local parts = { "GAT1" }
    for _, e in ipairs(ns.Chars()) do
        parts[#parts + 1] = e.key .. ":" .. (e.char.class or "") .. ":" .. (e.char.level or 0) .. ":" .. ns.Short(e.char)
    end
    return table.concat(parts, ";")
end

-- One line for the hub's home page: the chain of this character closest to done.
function ns.Summary()
    local c = myChar()
    if not c then return nil end
    local best
    for _, r in ipairs(ns.RaidsFor(c)) do
        local p = ns.Progress(c, r)
        if not p.ready and p.done > 0 and (not best or p.pct > best.pct) then best = p end
    end
    if not best then return nil end
    return L.SUMMARY:format(ns.RaidName(best.raid), best.done, best.total), "Interface\\Icons\\INV_Misc_Key_14"
end

-- The raids and keys that apply to a character (Onyxia and Scholomance have a chain per faction).
function ns.RaidsFor(char)
    local out = {}
    for _, r in ipairs(ns.RAIDS) do
        if not r.faction or r.faction == char.faction then out[#out + 1] = r end
    end
    return out
end

-- Characters, this one first, then by level.
function ns.Chars()
    local me = ns.CharKey()
    local list = {}
    for key, c in pairs(ns.db.chars) do list[#list + 1] = { key = key, char = c, me = key == me } end
    table.sort(list, function(a, b)
        if a.me ~= b.me then return a.me end
        if (a.char.level or 0) ~= (b.char.level or 0) then return (a.char.level or 0) > (b.char.level or 0) end
        return a.key < b.key
    end)
    return list
end

function ns.Forget(key)
    ns.db.chars[key] = nil
    if ns.Refresh then ns.Refresh() end
end

-- News between two scans: a chain ready (hub feed, and the guild when `announce` is on) or a
-- step done (hub feed).
function ns.Announce(old, new)
    for _, r in ipairs(ns.RaidsFor(new)) do
        local a, b = ns.Progress(old, r), ns.Progress(new, r)
        local name = ns.RaidName(r)
        if b.ready and not a.ready then
            local text = L.N_READY:format(name)
            print("|cff9ad0ffGulli Attune|r: " .. text)
            if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("Attune", text) end
            if ns.Get("announce") and IsInGuild and IsInGuild() and SendChatMessage then
                SendChatMessage(L.GUILD_READY:format(name), "GUILD")
            end
        elseif b.done > a.done and not b.ready then
            local text = L.N_STEP:format(name, b.done, b.total)
            if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("Attune", text) end
        end
    end
end

-- A step just taken: "Step 5 of 16: Onyxia's Lair" in chat.
function ns.OnAccepted(questID)
    local c = myChar()
    if not (c and questID) then return end
    for _, r in ipairs(ns.RaidsFor(c)) do
        for i, s in ipairs(r.steps) do
            for _, id in ipairs(s.anyOf or { s[1] }) do
                if id == questID then
                    print("|cff9ad0ffGulli Attune|r: " .. L.STEP_OF:format(i, #r.steps, ns.RaidName(r)))
                    return
                end
            end
        end
    end
end

local pending = false
local function soonScan()
    if pending then return end
    pending = true
    C_Timer.After(2, function() pending = false; ns.Scan() end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
local sentTo = {}
f:SetScript("OnEvent", function(self, event, a1, ...)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliAttuneDB = GulliAttuneDB or {}
        ns.db = GulliAttuneDB
        ns.db.chars = ns.db.chars or {}
        ns.db.settings = ns.db.settings or {}
        for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "BAG_UPDATE_DELAYED",
                             "PLAYER_LEVEL_UP", "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "PLAYER_LOGIN" }) do
            self:RegisterEvent(e)
        end
        local C = C_ChatInfo or {}
        local reg = C.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
        if reg then reg(ns.PREFIX) end
        return
    end
    if event == "CHAT_MSG_ADDON" then return ns.Receive(a1, ...) end
    if event == "PLAYER_LOGIN" then return ns.HookTooltip() end
    if event == "GROUP_ROSTER_UPDATE" then
        local channel = groupChannel()
        if channel and not sentTo[channel] then
            sentTo[channel] = true
            C_Timer.After(3, function() sentTo[channel] = nil; ns.SendState(channel) end)
        end
        return
    end
    if event == "QUEST_ACCEPTED" then ns.OnAccepted(select(2, ...) or a1) end
    soonScan()
end)

-- The tooltip of a player: their attunements, when they told them.
-- The world cursor tooltip can carry secret unit tokens and names (WoW 12): never pass one on.
local function secret(v) return issecretvalue and issecretvalue(v) end
local function safe(fn, ...)
    if not fn then return nil end
    local ok, v = pcall(fn, ...)
    if ok and not secret(v) then return v end
end
function ns.UnitTooltip(tip)
    if not (tip and tip.GetUnit) then return end
    local ok, _, unit = pcall(tip.GetUnit, tip)
    if not ok or not unit or secret(unit) or not safe(UnitIsPlayer, unit) then return end
    local name = safe(UnitName, unit)
    if not name then return end
    for _, line in ipairs(ns.TooltipLines(name)) do tip:AddLine(line, 0.6, 0.8, 1) end
end
local hooked = false
function ns.HookTooltip()
    if hooked then return end
    hooked = true
    local add = ns.UnitTooltip
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, add)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetUnit", add)
    end
end

SLASH_GULLIATTUNE1 = "/gat"
SLASH_GULLIATTUNE2 = "/gulliattune"
SlashCmdList.GULLIATTUNE = function() ns.Toggle() end

function GulliAttune_Toggle() ns.Toggle() end

-- The game icon of each switch, in the window and in the hub.
ns.OPT_ICON = {
    groupMsg = "Interface\\Icons\\Spell_Holy_PrayerOfHealing", tooltip = "Interface\\Icons\\INV_Misc_Note_01",
    announce = "Interface\\Icons\\Ability_Warrior_BattleShout", onlyAvail = "Interface\\Icons\\INV_Misc_Book_09",
    hideEmpty = "Interface\\Icons\\INV_Box_01",
}

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "Attune",
        icon = "Interface\\AddOns\\Gulli-Attune\\icon",
        slash = "/gat",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        summary = function() return ns.Summary() end,
        reset = function() ns.Reset() end,
        options = {
            { label = L.OPT_GROUP, tip = L.OPT_GROUP_D, icon = ns.OPT_ICON.groupMsg,
              get = function() return ns.Get("groupMsg") end, set = function(v) ns.Set("groupMsg", v) end },
            { label = L.OPT_TOOLTIP, tip = L.OPT_TOOLTIP_D, icon = ns.OPT_ICON.tooltip,
              get = function() return ns.Get("tooltip") end, set = function(v) ns.Set("tooltip", v) end },
            { label = L.OPT_ANNOUNCE, tip = L.OPT_ANNOUNCE_D, icon = ns.OPT_ICON.announce,
              get = function() return ns.Get("announce") end, set = function(v) ns.Set("announce", v) end },
            { label = L.OPT_AVAIL, tip = L.OPT_AVAIL_D, icon = ns.OPT_ICON.onlyAvail,
              get = function() return ns.Get("onlyAvail") end, set = function(v) ns.Set("onlyAvail", v) end },
        },
    })
end
