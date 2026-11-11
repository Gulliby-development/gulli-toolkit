-- Raid attunements: the quest chains each character must finish before a raid lets them in.
-- Each character saves its progress when it plays, so the window shows every character.

local ADDON, ns = ...
local L = ns.L

-- Steps: quest id, English quest name (the game's own name is used when it knows the quest),
-- who starts it (English name) and the area id of where (the game names it in your language).
-- anyOf: one of these quests is enough. Ids and names come from the QuestieDB Forever data.
local BRM, BRD, LBRS, SW, BURNING = 25, 1584, 1583, 1519, 46
ns.RAIDS = {
    { key = "MC", area = 2717, steps = {
        { 7848, "Attunement to the Core", "Lothos Riftwaker", BRM },
    } },
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
        { 6502, "Drakefire Amulet", "Haleh", 618 },
    } },
    { key = "ONY", area = 2159, faction = "Horde", item = 16309, steps = {
        { 4903, "Warlord's Command", "Warlord Goretooth", 3 },
        { 4941, "Eitrigg's Wisdom", "Warlord Goretooth", 3 },
        { 4974, "For The Horde!", "Thrall", 1637 },
        { 6566, "What the Wind Carries", "Thrall", 1637 },
        { 6567, "The Champion of the Horde", "Thrall", 1637 },
        { 6568, "The Testament of Rexxar", "Rexxar", 357 },
        { 6569, "Oculus Illusions", "Myranda the Hag", 28 },
        { 6570, "Emberstrife", "Myranda the Hag", 28 },
        { 6582, "The Test of Skulls, Scryer", "Emberstrife", 15 },
        { 6583, "The Test of Skulls, Somnus", "Emberstrife", 15 },
        { 6584, "The Test of Skulls, Chronalis", "Emberstrife", 15 },
        { 6585, "The Test of Skulls, Axtroz", "Emberstrife", 15 },
        { 6601, "Ascension...", "Emberstrife", 15 },
        { 6602, "Blood of the Black Dragon Champion", "Rexxar", 357 },
    } },
    { key = "BWL", area = 2677, steps = {
        { 7761, "Blackhand's Command", "Blackhand's Command", LBRS },
    } },
    { key = "NAXX", area = 3456, steps = {
        { 9121, "The Dread Citadel - Naxxramas", "Archmage Angela Dosantos", 139, anyOf = { 9121, 9122, 9123 } },
    } },
    { key = "UBRS", area = 1583, item = 12344, steps = {
        { 4742, "Seal of Ascension", "Vaelan", LBRS },
        { 4743, "Seal of Ascension", "Vaelan", LBRS },
    } },
}

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
    ns.db.chars[ns.CharKey()] = { name = UnitName("player"), class = class, level = UnitLevel("player"),
                                  faction = UnitFactionGroup("player"), done = done, active = active,
                                  items = items, t = time() }
    if ns.Refresh then ns.Refresh() end
end

-- Progress of one character on one raid: { raid, steps = { { step, state } }, done, total,
-- next (the first step not done), ready }. state: "done", "active" or "todo".
function ns.Progress(char, raid)
    local out = { raid = raid, steps = {}, done = 0, total = #raid.steps }
    for _, s in ipairs(raid.steps) do
        local state = "todo"
        for _, id in ipairs(s.anyOf or { s[1] }) do
            if char.done[id] then state = "done"; break end
            if char.active[id] then state = "active" end
        end
        out.steps[#out.steps + 1] = { step = s, state = state }
        if state == "done" then out.done = out.done + 1 elseif not out.next then out.next = s end
    end
    -- The amulet or the key in the bags means the chain is done even if the log says otherwise.
    out.ready = out.done == out.total or (raid.item ~= nil and char.items and char.items[raid.item] == true)
    return out
end

-- The raids that apply to a character (Onyxia has a chain per faction).
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

local pending = false
local function soonScan()
    if pending then return end
    pending = true
    C_Timer.After(2, function() pending = false; ns.Scan() end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliAttuneDB = GulliAttuneDB or {}
        ns.db = GulliAttuneDB
        ns.db.chars = ns.db.chars or {}
        for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "BAG_UPDATE_DELAYED",
                             "PLAYER_LEVEL_UP" }) do
            self:RegisterEvent(e)
        end
        return
    end
    soonScan()
end)

SLASH_GULLIATTUNE1 = "/gat"
SLASH_GULLIATTUNE2 = "/gulliattune"
SlashCmdList.GULLIATTUNE = function() ns.Toggle() end

function GulliAttune_Toggle() ns.Toggle() end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "Attune",
        icon = "Interface\\AddOns\\Gulli-Attune\\icon",
        slash = "/gat",
        open = function() ns.Toggle() end,
    })
end
