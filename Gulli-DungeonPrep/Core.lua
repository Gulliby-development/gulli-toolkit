-- Before a dungeon: its quests (in the log, can take now and where, not yet), and a short
-- checklist of what runs out inside: repairs, bag space, food and drink, the hearthstone.

local ADDON, ns = ...
local L = ns.L

local HEARTHSTONE = 6948
local CONSUMABLE, FOOD_DRINK = 0, 5

local function data()
    return ns.Data or { dungeons = {}, byDungeon = {}, quest = {} }
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
local function areaName(id)
    local name = id and id > 0 and C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(id)
    return (type(name) == "string" and name ~= "") and name or nil
end
local C = C_Container or {}
local function numSlots(bag) return (C.GetContainerNumSlots or GetContainerNumSlots)(bag) or 0 end
local function freeSlots(bag)
    local free, family = (C.GetContainerNumFreeSlots or GetContainerNumFreeSlots)(bag)
    return free or 0, family or 0
end
local function slotItem(bag, slot)
    if C.GetContainerItemInfo then
        local i = C.GetContainerItemInfo(bag, slot)
        return i and i.itemID, i and i.stackCount
    end
    local _, count, _, _, _, _, _, _, _, id = GetContainerItemInfo(bag, slot)
    return id, count
end
local function itemClass(id)
    local _, _, _, _, _, classID, subclassID = ((C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant)(id)
    return classID, subclassID
end
local function itemCooldown(id)
    local start, duration = ((C_Container and C_Container.GetItemCooldown) or GetItemCooldown)(id)
    return start or 0, duration or 0
end

-- Whether bit `id` (1-based) is set in a race or class mask; 0 means everyone. Masks pass
-- 2^32 on Forever, past what bit.band takes, so this uses plain arithmetic.
local function hasBit(mask, id)
    if not mask or mask == 0 or not id then return true end
    return math.floor(mask / 2 ^ (id - 1)) % 2 == 1
end

local function forMe(q)
    return hasBit(q[4], select(3, UnitRace("player"))) and hasBit(q[5], select(3, UnitClass("player")))
end

-- Dungeons in level order: { key, areas, name, min, max, fits }.
function ns.Dungeons(level)
    local out = {}
    for _, d in ipairs(data().dungeons) do
        out[#out + 1] = { key = d[1], areas = d[2], en = d[3], min = d[4], max = d[5],
                          fits = level >= d[4] - 2 and level <= d[5] }
    end
    return out
end

function ns.DungeonName(d)
    return areaName(d.areas[1]) or d.en
end

-- The dungeon for this level: of those whose range holds it, the one that starts highest.
function ns.Suggest(level)
    local best
    for _, d in ipairs(ns.Dungeons(level)) do
        if level >= d.min and level <= d.max and (not best or d.min >= best.min) then best = d end
    end
    return best or ns.Dungeons(level)[1]
end

-- The quests of a dungeon for this character, split in three lists and a done count:
-- log (in the quest log), take (can take now), later (level too low or an earlier quest missing).
function ns.Quests(key, level)
    local D = data()
    local out = { log = {}, take = {}, later = {}, done = 0 }
    for _, id in ipairs(D.byDungeon[key] or {}) do
        local q = D.quest[id]
        if q and forMe(q) then
            local closed = false
            for _, other in ipairs(q[10] or {}) do if questDone(other) then closed = true end end
            local entry = { id = id, name = (Q.GetTitleForQuestID and Q.GetTitleForQuestID(id)) or q[1],
                            level = q[2], minLevel = q[3], who = q[6], area = q[7] }
            if questDone(id) then
                out.done = out.done + 1
            elseif onQuest(id) then
                out.log[#out.log + 1] = entry
            elseif not closed then
                local pre = true
                for _, p in ipairs(q[8] or {}) do if not questDone(p) then pre = false end end
                if #(q[9] or {}) > 0 then
                    local one = false
                    for _, p in ipairs(q[9]) do if questDone(p) or onQuest(p) then one = true end end
                    pre = pre and one
                end
                if not pre then
                    entry.why = "WHY_EARLIER"
                    out.later[#out.later + 1] = entry
                elseif level < entry.minLevel then
                    entry.why = "WHY_LEVEL"
                    out.later[#out.later + 1] = entry
                else
                    out.take[#out.take + 1] = entry
                end
            end
        end
    end
    local byLevel = function(a, b) if a.level ~= b.level then return a.level < b.level end return a.name < b.name end
    table.sort(out.log, byLevel); table.sort(out.take, byLevel); table.sort(out.later, byLevel)
    return out
end

function ns.Where(q)
    local zone = areaName(q.area)
    if q.who == "" then return zone or "" end
    return zone and L.WHERE:format(q.who, zone) or q.who
end

-- The checklist: { key, ok, text } for repairs, bag space, food and drink, hearthstone.
function ns.Checklist()
    local out = {}
    local lowest = 100
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then lowest = math.min(lowest, math.floor(cur * 100 / max)) end
    end
    out[#out + 1] = { key = "REPAIR", ok = lowest >= 50, text = L.CHECK_REPAIR:format(lowest) }

    local free, food = 0, 0
    for bag = 0, 4 do
        local f, family = freeSlots(bag)
        if family == 0 then free = free + f end
        for slot = 1, numSlots(bag) do
            local id, count = slotItem(bag, slot)
            if id then
                local class, sub = itemClass(id)
                if class == CONSUMABLE and sub == FOOD_DRINK then food = food + (count or 1) end
            end
        end
    end
    out[#out + 1] = { key = "BAGS", ok = free >= 6, text = L.CHECK_BAGS:format(free) }
    out[#out + 1] = { key = "FOOD", ok = food >= 10, text = L.CHECK_FOOD:format(food) }

    local start, duration = itemCooldown(HEARTHSTONE)
    local left = (start > 0 and duration > 0) and math.ceil(start + duration - GetTime()) or 0
    out[#out + 1] = { key = "HEARTH", ok = left <= 0,
                      text = left > 0 and L.CHECK_HEARTH_CD:format(math.ceil(left / 60)) or L.CHECK_HEARTH }
    return out
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliDungeonPrepDB = GulliDungeonPrepDB or {}
        ns.db = GulliDungeonPrepDB
        self:RegisterEvent("QUEST_LOG_UPDATE")
        self:RegisterEvent("BAG_UPDATE_DELAYED")
        self:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
        return
    end
    if ns.Refresh then ns.Refresh() end
end)

SLASH_GULLIDUNGEONPREP1 = "/gdp"
SLASH_GULLIDUNGEONPREP2 = "/gullidungeonprep"
SlashCmdList.GULLIDUNGEONPREP = function(msg)
    msg = strtrim(msg or ""):upper()
    for _, d in ipairs(ns.Dungeons(UnitLevel("player") or 1)) do
        if d.key == msg then ns.selected = d.key end
    end
    ns.Toggle()
end

function GulliDungeonPrep_Toggle() ns.Toggle() end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "DungeonPrep",
        icon = "Interface\\AddOns\\Gulli-DungeonPrep\\icon",
        slash = "/gdp",
        open = function() ns.Toggle() end,
    })
end
