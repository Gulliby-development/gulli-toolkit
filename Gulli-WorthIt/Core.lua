-- Worth It: the quests whose reward is worth the walk (a bag, a quiver, an ammo pouch, a soul
-- bag, a profession bag, the Cozy Sleeping Bag), against the bags the character wears, and a guide that leads to them.
-- It only reads the game and sets map pins; it never takes, hands in or equips anything.

local ADDON, ns = ...
local L = ns.L

ns.DEFAULTS = { better = true, notify = true, showDone = true }
ns.TRACK_MAX = 6        -- rows of the tracker
ns.ICON = "Interface\\AddOns\\Gulli-WorthIt\\icon"
ns.KIND_ICON = {
    bag = "Interface\\Icons\\INV_Misc_Bag_08", ammo = "Interface\\Icons\\INV_Misc_Quiver_03",
    soul = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02", prof = "Interface\\Icons\\Trade_Herbalism",
    rest = "Interface\\Icons\\Spell_Nature_Sleep",
}
-- Kinds that are no bag: they have no slots and are worth it until the quest is done.
ns.PERKS = { rest = true }
ns.OPT_ICON = {
    better = "Interface\\Icons\\INV_Misc_Bag_10", notify = "Interface\\Icons\\INV_Misc_Bell_01",
    showDone = "Interface\\Icons\\INV_Misc_Ribbon_01",
}
-- Who a kind of reward is for; a kind without an entry is for every class.
ns.KIND_CLASS = { ammo = "HUNTER", soul = "WARLOCK" }

-- Game API wrappers -----------------------------------------------------------------------------

local Q = C_QuestLog or {}
local MAP = C_Map or {}
local CC = C_Container or {}
local CI = C_Item or {}
local turned = {}       -- handed in this session: the game flags a quest a moment later

local function questDone(id)
    if turned[id] then return true end
    if Q.IsQuestFlaggedCompleted then return Q.IsQuestFlaggedCompleted(id) and true or false end
    return false
end
local function onQuest(id)
    if Q.IsOnQuest then return Q.IsOnQuest(id) and true or false end
    return Q.GetLogIndexForQuestID and Q.GetLogIndexForQuestID(id) ~= nil or false
end
local function questReady(id)
    if Q.ReadyForTurnIn then return Q.ReadyForTurnIn(id) and true or false end
    return Q.IsComplete and Q.IsComplete(id) and true or false
end
local function questTitle(id)
    local t = Q.GetTitleForQuestID and Q.GetTitleForQuestID(id)
    if type(t) == "string" and t ~= "" then return t end
    local q = ns.Data.quest[id]
    return q and q[1] or ("#" .. id)
end
local function areaName(id)
    local name = id and id > 0 and MAP.GetAreaInfo and MAP.GetAreaInfo(id)
    return (type(name) == "string" and name ~= "") and name or nil
end
local function numSlots(bag)
    return CC.GetContainerNumSlots and CC.GetContainerNumSlots(bag) or 0
end
local function bagFamily(bag)
    if not CC.GetContainerNumFreeSlots then return 0 end
    local _, family = CC.GetContainerNumFreeSlots(bag)
    return family or 0
end
local function bagItem(bag)
    local slot = CC.ContainerIDToInventoryID and CC.ContainerIDToInventoryID(bag)
    return slot and GetInventoryItemID and GetInventoryItemID("player", slot) or nil
end
local function playerLevel() return UnitLevel("player") or 1 end

function ns.ItemName(id)
    local name = CI.GetItemNameByID and CI.GetItemNameByID(id)
    if name then return name end
    if CI.RequestLoadItemDataByID then CI.RequestLoadItemDataByID(id) end
    return "..."
end
function ns.ItemIcon(id)
    return (CI.GetItemIconByID and CI.GetItemIconByID(id)) or "Interface\\Icons\\INV_Misc_Bag_08"
end
function ns.ItemQuality(id)
    return (CI.GetItemQualityByID and CI.GetItemQualityByID(id)) or 1
end
ns.QuestTitle = questTitle
ns.AreaName = areaName

-- Whether bit `id` (1-based) is set in a race or class mask; 0 means everyone. Masks pass
-- 2^32 on Forever, past what bit.band takes, so this uses plain arithmetic.
local function hasBit(mask, id)
    if not mask or mask == 0 or not id then return true end
    return math.floor(mask / 2 ^ (id - 1)) % 2 == 1
end

local FACTION = { Alliance = "A", Horde = "H" }
-- While another class's quests are looked at: { class (id), side ("A", "H" or nil for both) };
-- any race of that class counts then.
local viewing
local function forMe(q)
    local side = q[6] or ""
    if viewing then
        if side ~= "" and viewing.side and side ~= viewing.side then return false end
        return hasBit(q[5], viewing.class)
    end
    local mine = FACTION[UnitFactionGroup("player") or ""]
    if side ~= "" and mine and side ~= mine then return false end
    return hasBit(q[4], select(3, UnitRace("player"))) and hasBit(q[5], select(3, UnitClass("player")))
end

-- Bags ------------------------------------------------------------------------------------------

-- The pattern of a bag's "16 Slot Bag" tooltip line, from the client's own text.
local slotsPattern
local function pattern()
    if slotsPattern then return slotsPattern end
    local f = type(CONTAINER_SLOTS) == "string" and CONTAINER_SLOTS or "%d Slot %s"
    f = f:gsub("([%(%)%.%+%-%*%?%[%]%^])", "%%%1")
    f = f:gsub("%%(%d?%$?)([ds])", function(_, t) return t == "d" and "(%d+)" or ".+" end)
    slotsPattern = "^" .. f .. "$"
    return slotsPattern
end

-- How many slots a bag item has: read once from its tooltip and kept (the data has no counts).
function ns.Slots(item)
    local known = ns.db and ns.db.slots
    if known and known[item] then return known[item] end
    local data = C_TooltipInfo and C_TooltipInfo.GetItemByID and C_TooltipInfo.GetItemByID(item)
    for _, line in ipairs(data and data.lines or {}) do
        local text = line.leftText
        if type(text) == "string" and not (issecretvalue and issecretvalue(text)) then
            local n = tonumber(text:match(pattern()))
            if n and n > 0 then
                if known then known[item] = n end
                return n
            end
        end
    end
    return nil
end

local function familyKind(family)
    if family == 0 then return "bag" end
    if family == 1 or family == 2 then return "ammo" end
    if family == 4 then return "soul" end
    return "prof"
end

-- The bags worn: { list = { { bag, slots, kind, item } } (the backpack first), total (slots),
-- open (bag slots with nothing in them), smallest = kind -> the smallest worn bag of it }.
function ns.Bags()
    local out = { list = {}, total = 0, open = 0, smallest = {} }
    local pack = numSlots(0)
    out.list[1] = { bag = 0, slots = pack, kind = "bag", pack = true }
    out.total = pack
    for bag = 1, 4 do
        local n = numSlots(bag)
        if n > 0 then
            local e = { bag = bag, slots = n, kind = familyKind(bagFamily(bag)), item = bagItem(bag) }
            out.list[#out.list + 1] = e
            out.total = out.total + n
            local s = out.smallest[e.kind]
            if not s or n < s.slots then out.smallest[e.kind] = e end
        else
            out.open = out.open + 1
        end
    end
    return out
end

-- What a reward bag adds to the bags worn: its slots into an empty bag slot, else over the
-- smallest bag of its kind (a quiver without one worn takes the place of a plain bag). nil
-- when the slots are not known yet; a profession bag with none worn counts as no gain.
function ns.Gain(kind, slots, bags)
    if not slots then return nil end
    local same = bags.smallest[kind]
    if same then
        if bags.open > 0 and kind == "bag" then return slots end
        return slots - same.slots
    end
    if kind == "prof" then return 0 end
    if bags.open > 0 then return slots end
    local plain = bags.smallest.bag
    return plain and (slots - plain.slots) or slots
end

-- Rewards ---------------------------------------------------------------------------------------

local STATE_ORDER = { ready = 1, log = 2, take = 3, later = 4, done = 5 }

local function usable(kind)
    local class = ns.KIND_CLASS[kind]
    return not class or class == select(2, UnitClass("player"))
end

-- A reward's chain for this character: a step of the other side gives way to the quest that
-- stands for it on this side (`D.alt`, the choices of an "any one of" earlier quest).
function ns.ChainOf(quest)
    local D = ns.Data
    local base = D.chain[quest] or { quest }
    local out = {}
    for i, id in ipairs(base) do
        local q = D.quest[id]
        if q and not forMe(q) and D.alt and D.alt[id] then
            for _, other in ipairs(D.alt[id]) do
                local o = D.quest[other]
                if o and forMe(o) then id = other break end
            end
        end
        out[i] = id
    end
    return out
end

-- Whether every step of a reward's chain is for this character (a chain of the other side
-- can end in a quest both sides may hand in).
local function wholeChain(quest)
    local D = ns.Data
    for _, id in ipairs(ns.ChainOf(quest)) do
        local q = D.quest[id]
        if q and not forMe(q) then return false end
    end
    return true
end

-- Where an entry stands for this character: state (ready, log, take, later, done), group (now,
-- later, done), chain (quest ids), cur (the step to do now), step, steps, level, req (the level
-- the step asks for), hidden and progress (how far on, for picking between branches).
local function settle(e, level)
    local D = ns.Data
    local chain = ns.ChainOf(e.quest)
    e.chain, e.steps = chain, #chain
    local progress = 0
    if questDone(e.quest) then
        e.state, e.step, e.cur, progress = "done", #chain, e.quest, 1000
    else
        for i, id in ipairs(chain) do
            if questDone(id) then progress = i elseif not e.cur then e.cur, e.step = id, i end
        end
        e.cur, e.step = e.cur or e.quest, e.step or #chain
        local q = D.quest[e.cur] or D.quest[e.quest]
        e.req = q[3] or 1
        if onQuest(e.cur) then
            e.state = questReady(e.cur) and "ready" or "log"
            progress = progress + 0.5
        else
            e.state = level >= e.req and "take" or "later"
        end
    end
    e.level = D.quest[e.quest][2]
    e.group = (e.state == "done" and "done") or (e.state == "later" and "later") or "now"
    e.hidden = ns.db ~= nil and ns.db.hidden ~= nil and ns.db.hidden[e.quest] == true
    e.progress = progress
end

-- Keeps one entry per set of items: the same reward behind two quests (a branch of a chain, a
-- copy for each race) is listed once, by the branch the character is further on.
local function once(entries)
    local out, byKey = {}, {}
    for _, e in ipairs(entries) do
        local ids = {}
        for _, o in ipairs(e.options) do ids[#ids + 1] = o.item end
        table.sort(ids)
        local key = table.concat(ids, ",")
        local at = byKey[key]
        if not at then
            out[#out + 1] = e
            byKey[key] = #out
        elseif e.progress > out[at].progress then
            out[at] = e
        end
    end
    return out
end

-- Every reward this character can get, one entry per quest: { quest, item, kind, slots, gain,
-- options (every item the quest offers the character, the best first) } and what settle adds.
function ns.Rewards()
    local D, bags, level = ns.Data, ns.Bags(), playerLevel()
    local byQuest, order = {}, {}
    for _, r in ipairs(D.rewards) do
        local item, kind, quest = r[1], r[2], r[3]
        local q = D.quest[quest]
        if q and usable(kind) and wholeChain(quest) then
            local e = byQuest[quest]
            if not e then
                e = { quest = quest, options = {} }
                byQuest[quest] = e
                order[#order + 1] = e
            end
            local slots = not ns.PERKS[kind] and ns.Slots(item) or nil
            e.options[#e.options + 1] = { item = item, kind = kind, slots = slots, gain = slots and ns.Gain(kind, slots, bags) }
        end
    end
    for _, e in ipairs(order) do
        table.sort(e.options, function(a, b)
            local ga, gb = a.gain or -1000, b.gain or -1000
            if ga ~= gb then return ga > gb end
            return a.item < b.item
        end)
        local best = e.options[1]
        e.item, e.kind, e.slots, e.gain = best.item, best.kind, best.slots, best.gain
        settle(e, level)
    end
    return once(order), bags
end

-- The class ids of the game, in its order (the class picker of the window), and their tokens.
ns.CLASSES = { 1, 2, 3, 4, 5, 7, 8, 9, 11 }
ns.CLASS_TOKEN = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", nil, "SHAMAN", "MAGE", "WARLOCK",
                   nil, "DRUID" }

-- A class's name in the client's language: the game's class info, else its list of names.
function ns.ClassName(id)
    local info = C_CreatureInfo and C_CreatureInfo.GetClassInfo and C_CreatureInfo.GetClassInfo(id)
    if info and type(info.className) == "string" and info.className ~= "" then return info.className end
    local token = ns.CLASS_TOKEN[id]
    local names = LOCALIZED_CLASS_NAMES_MALE
    return (token and names and names[token]) or token or ""
end

-- Another class's entry: nothing of this character's log counts, so it is only where the
-- chain starts and the level it asks for (state `other`, group `all`).
local function settleOther(e)
    local D = ns.Data
    local chain = ns.ChainOf(e.quest)
    e.chain, e.steps, e.cur, e.step = chain, #chain, chain[1], 1
    local first = D.quest[chain[1]] or D.quest[e.quest]
    e.req = first[3] or 1
    e.level = D.quest[e.quest][2]
    e.state, e.group, e.hidden, e.progress, e.other = "other", "all", false, 0, true
end

local function classList(classId, other, level)
    local D = ns.Data
    local order = {}
    for _, r in ipairs(D.class or {}) do
        local quest, mask, items = r[1], r[2], r[3]
        if D.quest[quest] and hasBit(mask, classId) and wholeChain(quest) then
            local e = { quest = quest, class = true, classId = classId, options = {} }
            for _, item in ipairs(items) do e.options[#e.options + 1] = { item = item } end
            e.item = items[1]
            if other then settleOther(e) else settle(e, level) end
            order[#order + 1] = e
        end
    end
    return once(order)
end

-- The class quests that give an item: { quest, class = true, classId, item (the first the quest
-- gives), options (every item, in the quest's order) } and what settle adds. For this
-- character's class (classId nil or its own) with its progress; for another class every quest
-- that class has on this character's side, or on both sides when it has none on this one
-- (a class of the other faction), each as state `other`.
function ns.ClassQuests(classId)
    local own = select(3, UnitClass("player"))
    if not classId or classId == own then return classList(own, false, playerLevel()) end
    local list
    viewing = { class = classId, side = FACTION[UnitFactionGroup("player") or ""] }
    local ok, err = pcall(function()
        list = classList(classId, true)
        if #list == 0 and viewing.side then
            viewing.side = nil
            list = classList(classId, true)
        end
    end)
    viewing = nil
    if not ok then error(err, 0) end
    table.sort(list, function(a, b)
        if a.req ~= b.req then return a.req < b.req end
        return a.quest < b.quest
    end)
    return list
end

-- The entry of a quest, a bag reward or a class quest.
function ns.Entry(quest)
    for _, e in ipairs((ns.Rewards())) do if e.quest == quest then return e end end
    for _, e in ipairs(ns.ClassQuests()) do if e.quest == quest then return e end end
end

-- Whether the reward is better than what is worn (unknown slots and a perk count as better).
function ns.IsBetter(e) return ns.PERKS[e.kind] or e.gain == nil or e.gain > 0 end

-- The kinds that have a reward for this character, in the data's order.
function ns.Kinds()
    local has, out = {}, {}
    for _, e in ipairs((ns.Rewards())) do has[e.kind] = true end
    for _, k in ipairs(ns.Data.kinds) do if has[k] then out[#out + 1] = k end end
    return out
end

-- The window's list: a { head = group, count } row before each group's entries. kind filters
-- (nil is all). Hidden rewards are left out, the ones that are no better with `better` on,
-- the done ones with `showDone` off. Also returns the number of entries.
function ns.List(kind, classId)
    local class = kind == "class"
    local rewards = class and ns.ClassQuests(classId) or ns.Rewards()
    local groups = { now = {}, later = {}, done = {}, all = {} }
    for _, e in ipairs(rewards) do
        local keep = not e.hidden and (class or not kind or e.kind == kind)
        if keep and e.state == "done" then keep = ns.db.showDone
        elseif keep and ns.db.better and not class then keep = ns.IsBetter(e) end
        if keep then local g = groups[e.group]; g[#g + 1] = e end
    end
    table.sort(groups.now, function(a, b)
        if STATE_ORDER[a.state] ~= STATE_ORDER[b.state] then return STATE_ORDER[a.state] < STATE_ORDER[b.state] end
        local ga, gb = a.gain or 0, b.gain or 0
        if ga ~= gb then return ga > gb end
        if a.level ~= b.level then return a.level < b.level end
        return a.quest < b.quest
    end)
    table.sort(groups.later, function(a, b)
        if a.req ~= b.req then return a.req < b.req end
        return a.quest < b.quest
    end)
    local out, n = {}, 0
    for _, g in ipairs({ "now", "later", "done", "all" }) do
        if #groups[g] > 0 then
            out[#out + 1] = { head = g, count = #groups[g] }
            for _, e in ipairs(groups[g]) do out[#out + 1] = e; n = n + 1 end
        end
    end
    return out, n
end

-- The rewards the guide would lead to: open now, not hidden, better than what is worn. With
-- `class`, the class quests open now that are not hidden.
function ns.Targets(class)
    local out = {}
    for _, e in ipairs(class and ns.ClassQuests() or (ns.Rewards())) do
        if e.group == "now" and not e.hidden and (class or ns.IsBetter(e)) then out[#out + 1] = e end
    end
    return out
end

-- What the open rewards would add together: each takes the place of the smallest bag of its
-- kind, the biggest reward first. Returns the slots gained and how many rewards give them.
function ns.Potential()
    local targets, bags = ns.Targets(), ns.Bags()
    local sizes = {}
    for _, b in ipairs(bags.list) do
        if not b.pack then
            sizes[b.kind] = sizes[b.kind] or {}
            table.insert(sizes[b.kind], b.slots)
        end
    end
    sizes.bag = sizes.bag or {}
    for _ = 1, bags.open do table.insert(sizes.bag, 0) end
    table.sort(targets, function(a, b) return (a.slots or 0) > (b.slots or 0) end)
    local gain, count = 0, 0
    for _, e in ipairs(targets) do
        local pool = sizes[e.kind] or (e.kind ~= "prof" and sizes.bag)
        if e.slots and pool and #pool > 0 then
            table.sort(pool)
            if e.slots > pool[1] then
                gain, count = gain + e.slots - pool[1], count + 1
                pool[1] = e.slots
            end
        end
    end
    return gain, count
end

-- The steps of a reward's chain for the window: { id, name, level, done, now }.
function ns.Steps(e)
    local out = {}
    for i, id in ipairs(e.chain) do
        local q = ns.Data.quest[id]
        out[i] = { id = id, n = i, name = questTitle(id), level = q and q[2] or e.level,
                   done = not e.other and (e.state == "done" or questDone(id)),
                   now = not e.other and e.state ~= "done" and id == e.cur }
    end
    return out
end

-- What to do for a reward, step by step (Tips.lua): the client's language, else English.
function ns.Tips(quest)
    local all = ns.TIPS or {}
    local t = all[ns.lang]
    return (t and t[quest]) or (all.en and all.en[quest]) or nil
end

-- The entry's page under its lines: a class quest's rewards, "What to do" with its steps, then
-- the chain with its quests. { head = text }, { item = id }, { tip = text, n = i } or a step of
-- ns.Steps.
function ns.DetailRows(e, chainHead, tipsHead, rewardHead)
    local out = {}
    if e.class then
        out[#out + 1] = { head = rewardHead or (#e.options > 1 and ns.L.CQ_CHOOSE_HEAD or ns.L.CQ_REWARD_HEAD) }
        for _, o in ipairs(e.options) do out[#out + 1] = { item = o.item } end
    end
    local tips = ns.Tips(e.quest)
    if tips and #tips > 0 then
        out[#out + 1] = { head = tipsHead or ns.L.TIPS }
        for i, text in ipairs(tips) do out[#out + 1] = { tip = text, n = i } end
    end
    out[#out + 1] = { head = chainHead or ns.L.CHAIN }
    for _, st in ipairs(ns.Steps(e)) do out[#out + 1] = st end
    return out
end

-- Where a reward sends the character now: { kind (take, work, turnin), who, area, zone, x, y,
-- quest, reward, pin (the place is on a map) }. A quest in the log without a known work spot
-- points to who takes it back (`at`).
function ns.Stop(e)
    if e.state == "done" then return nil end
    local q = ns.Data.quest[e.cur]
    if not q then return nil end
    local kind, who, area, x, y, at = "take", q[7], q[8], q[9], q[10], nil
    if e.state == "ready" then
        kind, who, area, x, y = "turnin", q[11], q[12], q[13], q[14]
    elseif e.state == "log" then
        if (q[16] or 0) > 0 or (q[17] or 0) > 0 then
            kind, who, area, x, y = "work", questTitle(e.cur), q[15], q[16], q[17]
        else
            kind, who, area, x, y, at = "work", q[11], q[12], q[13], q[14], true
        end
    end
    area, x, y = area or 0, x or 0, y or 0
    return { kind = kind, who = who or "", area = area, zone = areaName(area), x = x, y = y, at = at,
             quest = e.cur, reward = e.quest, pin = area > 0 and (x > 0 or y > 0) }
end

-- "Take: Poor Old Blanchy" and "Verna Furlbrow, Westfall" for a stop.
function ns.StopText(stop)
    if stop.book then return ns.BookStopText(stop) end
    local what = L["DO_" .. stop.kind:upper()]:format(questTitle(stop.quest))
    local where = (stop.kind == "work" and not stop.at) and (stop.zone or "") or
        (stop.zone and L.WHERE:format(stop.who, stop.zone) or stop.who)
    return what, where
end

-- Map pins --------------------------------------------------------------------------------------

local CONTINENT, ZONE, KALIMDOR, EASTERN, COSMIC = 2, 3, 1414, 1415, 946

-- Where the player is: { zone (the zone map's name), x, y (map percent), kalimdor }.
function ns.Here()
    local here = {}
    local id = MAP.GetBestMapForUnit and MAP.GetBestMapForUnit("player")
    local zoneMap
    while id do
        local info = MAP.GetMapInfo and MAP.GetMapInfo(id)
        if not info then break end
        if info.mapType == ZONE and not zoneMap then zoneMap, here.zone = id, info.name end
        if info.mapType == CONTINENT or id == KALIMDOR or id == EASTERN then
            here.kalimdor = id == KALIMDOR
            break
        end
        id = info.parentMapID ~= 0 and info.parentMapID or nil
    end
    local pos = zoneMap and MAP.GetPlayerMapPosition and MAP.GetPlayerMapPosition(zoneMap, "player")
    if pos then
        local x, y = pos:GetXY()
        if x and x > 0 then here.x, here.y = x * 100, y * 100 end
    end
    return here
end

local function onKalimdor(area)
    for _, a in ipairs(ns.Data.kalimdor or {}) do if a == area then return true end end
    return false
end

-- Opens the world map on a map id, out of combat only. C_Map.OpenWorldMap lets the game open it
-- from its own event, so the map's pins are made in secure code: an addon's call of
-- OpenWorldMap or SetMapID taints them and the game blocks SetPassThroughButtons.
function ns.OpenMap(id)
    if not id or (InCombatLockdown and InCombatLockdown()) then return false end
    if C_Map and C_Map.OpenWorldMap then
        C_Map.OpenWorldMap(id)
    elseif OpenWorldMap then
        OpenWorldMap(id)
    elseif WorldMapFrame and WorldMapFrame.SetMapID and ShowUIPanel then
        ShowUIPanel(WorldMapFrame)
        WorldMapFrame:SetMapID(id)
    else
        return false
    end
    if ns.BehindMap then ns.BehindMap() end
    return true
end

-- A map pin on a stop, through the world map's own waypoint (and TomTom's arrow when it is
-- loaded). Returns true when it is set. With `open`, the world map opens on it too.
local mapOfZone
function ns.SetPin(stop, open)
    if not (stop and stop.pin and stop.zone and MAP.SetUserWaypoint and UiMapPoint and MAP.GetMapChildrenInfo) then
        return false
    end
    if not mapOfZone then
        mapOfZone = {}
        -- the two continents first, then every other map (the zones WoW Forever added)
        for _, c in ipairs({ KALIMDOR, EASTERN, COSMIC }) do
            for _, m in ipairs(MAP.GetMapChildrenInfo(c, nil, true) or {}) do
                if m.name and not mapOfZone[m.name] then mapOfZone[m.name] = m.mapID end
            end
        end
    end
    local id = mapOfZone[stop.zone]
    if not id then return false end
    MAP.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(id, stop.x / 100, stop.y / 100))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    if TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(id, stop.x / 100, stop.y / 100, { title = stop.who, from = "Gulli-WorthIt" })
    end
    ns.pinned = true
    if open then ns.OpenMap(id) end
    return true
end

function ns.WowheadURL(kind, id)
    return "https://www.wowhead.com/forever/" .. kind .. "=" .. id
end

-- The guide ---------------------------------------------------------------------------------------

-- One guide leads at a time, whatever module it is of: GulliHUD.guide = { owner, stop }.
local function claim()
    GulliHUD = GulliHUD or {}
    local g = GulliHUD.guide
    if g and g.owner ~= "WorthIt" and g.stop then pcall(g.stop) end
    GulliHUD.guide = { owner = "WorthIt", stop = function() ns.StopGuide() end }
end

function ns.Guiding() return ns.cdb ~= nil and ns.cdb.guide ~= nil end

-- Whether the guide leads to this reward.
function ns.Leads(quest)
    local g = ns.cdb and ns.cdb.guide
    if not g then return false end
    for _, id in ipairs(g.targets) do if id == quest then return true end end
    return false
end

-- Starts leading: to the rewards of these quests, or to every open one (of the class quests
-- with `class`). Returns false when there is nowhere to lead.
function ns.StartGuide(quests, class)
    if ns.paused or not ns.cdb then return false end
    if not quests then
        quests = {}
        for _, e in ipairs(ns.Targets(class)) do quests[#quests + 1] = e.quest end
    end
    if #quests == 0 then return false end
    claim()
    ns.cdb.guide = { targets = quests }
    return ns.StepGuide()
end

function ns.StopGuide()
    if ns.cdb then ns.cdb.guide = nil end
    if GulliHUD and GulliHUD.guide and GulliHUD.guide.owner == "WorthIt" then GulliHUD.guide = nil end
    if ns.pinned and MAP.ClearUserWaypoint then MAP.ClearUserWaypoint() end
    ns.pinned = nil
    ns.stop = nil
    if ns.RefreshTracker then ns.RefreshTracker() end
    if ns.Refresh then ns.Refresh() end
end

local function dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

-- The guide's rows, the stop to go to first: { entry, stop, tier } for every reward it leads
-- to that is not got yet. Stops in the player's zone come first, the nearest first, then the
-- same continent, the other one, and last the ones no map shows (a quest started by an item)
-- and the rewards that wait for a level.
function ns.GuideRows()
    local g = ns.cdb and ns.cdb.guide
    if not g then return {} end
    local here, rows = ns.Here(), nil
    if g.library then
        rows = ns.LibraryRows(here)
    else
        local byQuest = {}
        rows = {}
        for _, e in ipairs(ns.ClassQuests()) do byQuest[e.quest] = e end
        for _, e in ipairs((ns.Rewards())) do byQuest[e.quest] = e end
        for i, id in ipairs(g.targets) do
            local e = byQuest[id]
            if e and e.state ~= "done" then
                rows[#rows + 1] = { entry = e, stop = ns.Stop(e), order = i, later = e.state == "later" }
            end
        end
    end
    for _, row in ipairs(rows) do ns.RankRow(row, here) end
    table.sort(rows, ns.RowBefore)
    return rows
end

-- A row's place: `tier` 0 the player's zone (with `dist`), 1 the same continent, 2 the other
-- one, 5 no map, 6 waits for a level; `band` puts a book above the player's level (`high`)
-- after every book at or below it, and the books that wait last.
function ns.RankRow(row, here)
    local stop = row.stop
    row.tier, row.dist = 5, nil
    row.band = row.later and 2 or (row.high and 1 or 0)
    if row.later then row.tier = 6
    elseif stop and stop.pin then
        local k = onKalimdor(stop.area)
        row.tier = (here.zone ~= nil and stop.zone == here.zone) and 0
            or ((here.kalimdor == nil or k == here.kalimdor) and 1 or 2)
        if row.tier == 0 and here.x then row.dist = dist(here.x, here.y, stop.x, stop.y) end
    end
end

function ns.RowBefore(a, b)
    if (a.band or 0) ~= (b.band or 0) then return (a.band or 0) < (b.band or 0) end
    -- above the player's level the lowest book comes first, wherever it lies
    if (a.band or 0) > 0 and (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
    if a.tier ~= b.tier then return a.tier < b.tier end
    if (a.dist or 0) ~= (b.dist or 0) then return (a.dist or 0) < (b.dist or 0) end
    return a.order < b.order
end

-- Pins the stop to go to now, when it changed. With every reward got, the guide is done.
function ns.StepGuide()
    if not ns.Guiding() then return false end
    local rows = ns.GuideRows()
    if #rows == 0 then
        ns.StopGuide()
        return false
    end
    -- The stop the guide leads to stays while it is still among the nearest group, so walking
    -- nearer to another one never moves the pin back and forth.
    local pick = rows[1]
    for _, row in ipairs(rows) do
        if row.tier ~= pick.tier or row.band ~= pick.band then break end
        local st = row.stop
        if st and (st.kind .. "@" .. st.quest) == ns.cdb.guide.last then pick = row break end
    end
    local stop = pick.stop
    local key = stop and (stop.kind .. "@" .. stop.quest) or ""
    if key ~= ns.cdb.guide.last then
        ns.cdb.guide.last = key
        if stop and stop.pin and pick.tier < 5 then ns.SetPin(stop) end
    end
    ns.stop = stop
    if ns.RefreshTracker then ns.RefreshTracker() end
    if ns.Refresh then ns.Refresh() end
    return true
end

-- The tracker's rows: { quest, item, name, state, what, where, pin (its stop) }, at most
-- ns.TRACK_MAX (ns.TRACK_BOOKS through the library, `book` rows of two lines). Also returns how
-- many rows did not fit.
function ns.TrackerItems()
    local out = {}
    local rows = ns.GuideRows()
    local library = ns.LeadsLibrary()
    local cap = library and ns.TRACK_BOOKS or ns.TRACK_MAX
    for i, row in ipairs(rows) do
        if i > cap then break end
        local e, stop = row.entry, row.stop
        local it = { quest = e.quest, item = e.item, state = e.state, first = i == 1 }
        if library then
            it.book = true
            if e.tier then it.item, it.state = e.items[1], "ready" end
            if stop and stop.kind == "pick" then
                it.name = ns.ItemName(e.item)
                it.where = row.later and ((stop.zone or "") .. ((ns.Skin and ns.Skin.DOT) or " - ") .. L.FROM_LEVEL:format(e.level - ns.BOOK_EARLY))
                    or (stop.zone or "")
                it.state = row.later and "later" or "take"
            elseif stop then
                it.name, it.where = ns.StopText(stop)
                it.state = "ready"
            end
            if stop and stop.pin then it.pin = stop end
        else
            it.name = ns.ItemName(e.item)
            if e.state == "later" then
                it.what = L.FROM_LEVEL:format(e.req)
            elseif stop then
                it.what, it.where = ns.StopText(stop)
                if stop.pin then it.pin = stop end
            end
        end
        out[#out + 1] = it
    end
    return out, math.max(0, #rows - cap)
end

-- Notices -----------------------------------------------------------------------------------------

local function toast(o)
    local S = ns.Skin
    if S and S.Toast then S.Toast(o) else print(L.TITLE .. ": " .. o.text) end
end

-- The library ---------------------------------------------------------------------------------
-- WoW Forever's library books: each lies somewhere in the world and goes back to a librarian
-- (the last ones to a mage trainer) through a quest of its own; every so many books handed in
-- open a reward quest (D.tiers). Each book is a stop of the library guide.

ns.TRACK_BOOKS = 10     -- rows of the tracker while it leads through the books
ns.BOOK_EARLY = 10      -- a book waits ("later") while the character is this far below its level
ns.BOOK_ICON = "Interface\\Icons\\INV_Misc_Book_09"
ns.CAGE_KEY_BOOK = 79953 -- the book behind a cage: the Rusted Cage Key opens it

local function itemCount(id)
    if CI.GetItemCount then return CI.GetItemCount(id) or 0 end
    if GetItemCount then return GetItemCount(id) or 0 end
    return 0
end

-- Who takes a book back, or gives a reward, for this character's side: { who, area, x, y }.
local function sideOf(t)
    local mine = FACTION[UnitFactionGroup("player") or ""] or "A"
    return t[mine] or t.A
end
function ns.Taker(i) return sideOf(ns.Data.takers[i]) end

-- Every book: { book = true, quest, item, level, places = { { area, x, y } }, taker (index),
-- state (done, bag: in the bags, take, later), group (bags, now, later, done) }, in the data's
-- order (lowest level first).
function ns.Books()
    local level, out = playerLevel(), {}
    for _, b in ipairs(ns.Data.books or {}) do
        local e = { book = true, quest = b[1], item = b[2], level = b[3], taker = b[5], places = {} }
        local p = b[4]
        for i = 1, #p, 3 do e.places[#e.places + 1] = { area = p[i], x = p[i + 1], y = p[i + 2] } end
        if questDone(e.quest) then e.state = "done"
        elseif itemCount(e.item) > 0 then e.state = "bag"
        elseif level < e.level - ns.BOOK_EARLY then e.state = "later"
        else e.state = "take" end
        e.group = (e.state == "bag" and "bags") or (e.state == "take" and "now") or e.state
        out[#out + 1] = e
    end
    return out
end

-- The library for this character: { books, handed (books handed in), bags (in the bags),
-- total, tiers = { { quest, need, req, items, giver, state, left } } }. A reward is done,
-- ready (enough books and the level), log (taken), wait (books missing: `left`) or later
-- (the level missing).
function ns.Library()
    local books = ns.Books()
    local handed, bags = 0, 0
    for _, e in ipairs(books) do
        if e.state == "done" then handed = handed + 1 elseif e.state == "bag" then bags = bags + 1 end
    end
    local level, tiers = playerLevel(), {}
    for _, t in ipairs(ns.Data.tiers or {}) do
        local r = { tier = true, quest = t[1], need = t[2], req = t[3], items = t[4], giver = sideOf(t[5]) }
        if questDone(r.quest) then r.state = "done"
        elseif onQuest(r.quest) then r.state = "log"
        elseif handed < r.need then r.state, r.left = "wait", r.need - handed
        elseif level < r.req then r.state = "later"
        else r.state = "ready" end
        tiers[#tiers + 1] = r
    end
    return { books = books, handed = handed, bags = bags, total = #books, tiers = tiers }
end

-- The window's book list: a { head = group, count } row before each group (in the bags, to
-- pick up, later, done). Also returns the number of books shown.
function ns.BookList()
    local groups = { bags = {}, now = {}, later = {}, done = {} }
    for _, e in ipairs(ns.Books()) do
        if e.state ~= "done" or ns.db.showDone then local g = groups[e.group]; g[#g + 1] = e end
    end
    local out, n = {}, 0
    for _, g in ipairs({ "bags", "now", "later", "done" }) do
        if #groups[g] > 0 then
            out[#out + 1] = { head = g, count = #groups[g] }
            for _, e in ipairs(groups[g]) do out[#out + 1] = e; n = n + 1 end
        end
    end
    return out, n
end

function ns.Book(quest)
    for _, e in ipairs(ns.Books()) do if e.quest == quest then return e end end
end

-- The place to pick a book up: the one in the player's zone, else on the same continent, else
-- the first.
function ns.BookPlace(e, here)
    here = here or ns.Here()
    local best, rank
    for _, p in ipairs(e.places) do
        local zone = areaName(p.area)
        local r = (here.zone ~= nil and zone == here.zone) and 0
            or ((here.kalimdor == nil or onKalimdor(p.area) == here.kalimdor) and 1 or 2)
        if not rank or r < rank then best, rank = p, r end
    end
    return best
end

local function placeStop(kind, at, quest, extra)
    local area, x, y = at[2] or at.area or 0, at[3] or at.x or 0, at[4] or at.y or 0
    local s = { kind = kind, who = at[1] or "", area = area, zone = areaName(area), x = x, y = y, quest = quest,
                book = true, pin = area > 0 and (x > 0 or y > 0) }
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
end

-- Where a book or a library reward sends the character: pick (the book where it lies),
-- handin (the books in the bags, to who takes them back) or claim (a reward that is ready).
function ns.BookStop(e, here)
    if e.tier then
        if e.state ~= "ready" and e.state ~= "log" then return nil end
        return placeStop("claim", e.giver, e.quest, { need = e.need })
    end
    if e.state == "done" then return nil end
    if e.state == "bag" then return placeStop("handin", ns.Taker(e.taker), e.quest, { item = e.item, count = 1 }) end
    local p = ns.BookPlace(e, here)
    if not p then return nil end
    return placeStop("pick", { "", p.area, p.x, p.y }, e.quest, { item = e.item })
end

-- "Pick up: Goaz Scrolls" and "Westfall" for a stop of the library guide.
function ns.BookStopText(stop)
    if stop.kind == "pick" then return L.DO_PICK:format(ns.ItemName(stop.item)), stop.zone or "" end
    local what = stop.kind == "claim" and L.DO_CLAIM:format(stop.need) or L.DO_HANDIN:format(stop.count or 1)
    return what, stop.zone and L.WHERE:format(stop.who, stop.zone) or stop.who
end

-- Starts leading through the books. Returns false when there is nothing to do.
function ns.StartLibrary()
    if ns.paused or not ns.cdb then return false end
    if #ns.LibraryRows(ns.Here()) == 0 then return false end
    claim()
    ns.cdb.guide = { library = true, targets = {} }
    return ns.StepGuide()
end

function ns.LeadsLibrary() return ns.cdb ~= nil and ns.cdb.guide ~= nil and ns.cdb.guide.library == true end

-- The library guide's rows, the same shape as ns.GuideRows: one row for the books in the bags
-- of each who takes them back, one per reward ready to take, one per book to pick up (with a
-- goal, only as many as it still needs). The books at or below the player's level come before
-- the ones above it, and the books that wait for a level last.
local function libraryRows(here)
    local lib, rows, picks, level = ns.Library(), {}, {}, playerLevel()
    local hand = {}
    for i, e in ipairs(lib.books) do
        if e.state == "bag" then
            local h = hand[e.taker]
            if h then
                h.stop.count = h.stop.count + 1
            else
                h = { entry = e, stop = ns.BookStop(e, here), order = i }
                hand[e.taker] = h
                rows[#rows + 1] = h
            end
        elseif e.state == "take" or e.state == "later" then
            picks[#picks + 1] = { entry = e, stop = ns.BookStop(e, here), order = 100 + i, level = e.level,
                                  later = e.state == "later", high = e.level > level }
        end
    end
    for i, t in ipairs(lib.tiers) do
        if t.state == "ready" or t.state == "log" then
            rows[#rows + 1] = { entry = t, stop = ns.BookStop(t, here), order = 50 + i }
        end
    end
    -- With a goal only the books it still needs, the first in the guide's order.
    local goal = ns.LibGoal(lib)
    if goal then
        for _, row in ipairs(picks) do ns.RankRow(row, here) end
        table.sort(picks, ns.RowBefore)
        for i = goal.left + 1, #picks do picks[i] = nil end
    end
    for _, row in ipairs(picks) do rows[#rows + 1] = row end
    return rows
end
ns.LibraryRows = libraryRows

-- The library goal of this character: { tier, need, left (books still to find: the goal less
-- the books handed in and in the bags) } or nil. `lib` is ns.Library() when the caller has it.
function ns.LibGoal(lib)
    local q = ns.cdb and ns.cdb.libGoal
    if not q then return nil end
    lib = lib or ns.Library()
    for _, t in ipairs(lib.tiers) do
        if t.quest == q then
            return { tier = t, quest = q, need = t.need, left = math.max(0, t.need - lib.handed - lib.bags) }
        end
    end
end

-- Makes a library reward the goal; the same one again takes the goal away. A guide through the
-- books follows it at once.
function ns.SetLibGoal(quest)
    if not ns.cdb then return end
    if ns.cdb.libGoal == quest then quest = nil end
    ns.cdb.libGoal = quest
    if ns.LeadsLibrary() then ns.StepGuide() end
    if ns.Refresh then ns.Refresh() end
    return quest
end

-- Tells once about a book that came into the bags and a reward that opened. The first look on
-- a character only notes what is there.
function ns.CheckBooks()
    if not ns.cdb or ns.paused then return 0 end
    local first = ns.cdb.bookTold == nil
    ns.cdb.bookTold = ns.cdb.bookTold or {}
    local told, news = ns.cdb.bookTold, {}
    local lib = ns.Library()
    for _, e in ipairs(lib.books) do
        local key = "b" .. e.quest
        if e.state == "bag" and not told[key] then
            told[key] = true
            local who = ns.Taker(e.taker)
            news[#news + 1] = { icon = ns.ItemIcon(e.item), quest = e.quest,
                                text = L.LIB_FOUND:format(ns.ItemName(e.item), who[1]) }
        end
    end
    for _, t in ipairs(lib.tiers) do
        local key = "t" .. t.quest
        if t.state == "ready" and not told[key] then
            told[key] = true
            news[#news + 1] = { icon = ns.ItemIcon(t.items[1]), quest = t.quest,
                                text = L.LIB_REWARD:format(t.need, t.giver[1]) }
        end
    end
    if first then return 0 end
    for _, n in ipairs(news) do
        if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("WorthIt", n.text) end
        if ns.db.notify then
            toast({ key = "book" .. n.quest, icon = n.icon, title = L.TAB_LIBRARY, text = n.text, seconds = 10,
                    buttons = { { text = L.OPEN, onClick = function() ns.ShowBook(n.quest) end } } })
        end
    end
    return #news
end


-- A reward quest was handed in: one notice, and the guide goes on to the next reward.
function ns.OnTurnedIn(id)
    local entry = ns.Entry(id)
    turned[id] = true
    if entry and not ns.paused then
        local text = L.GOT:format(ns.ItemName(entry.item))
        toast({ key = "got", icon = ns.ItemIcon(entry.item), title = L.TITLE, text = text, kind = "good", seconds = 8 })
        if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("WorthIt", text) end
    end
    ns.StepGuide()
    if ns.Refresh then ns.Refresh() end
end

-- Tells once about each reward that opened (a level reached, an earlier step done). The first
-- time on a character only notes what is open, so a new install tells nothing.
function ns.CheckNew()
    if not ns.cdb or ns.paused then return 0 end
    local first = ns.cdb.told == nil
    ns.cdb.told = ns.cdb.told or {}
    local fresh = {}
    for _, e in ipairs(ns.Targets()) do
        if e.state == "take" and not ns.cdb.told[e.quest] then
            ns.cdb.told[e.quest] = true
            fresh[#fresh + 1] = e
        end
    end
    if first or #fresh == 0 then return 0 end
    local e = fresh[1]
    local text = #fresh == 1 and L.NEW_ONE:format(ns.ItemName(e.item)) or L.NEW_MANY:format(#fresh)
    if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("WorthIt", text) end
    if ns.db.notify then
        toast({ key = "new", icon = ns.ItemIcon(e.item), title = L.TITLE, text = text, seconds = 10,
                buttons = { { text = L.OPEN, onClick = function() ns.Show(e.quest) end } } })
    end
    return #fresh
end

-- The hub's home line: "+8 slots · rewards: 3", with the number for its tile.
function ns.Summary()
    if not ns.db or ns.paused then return nil end
    local gain, count = ns.Potential()
    if count == 0 then return nil end
    return L.SUM:format(gain, count), ns.ICON, { value = "+" .. gain, label = L.SUM_LABEL:format(count) }
end

-- Settings ----------------------------------------------------------------------------------------

function ns.SetPref(key, value)
    if not ns.db then return end
    ns.db[key] = value
    if ns.Refresh then ns.Refresh() end
end

function ns.SetHidden(quest, on)
    if not ns.db then return end
    ns.db.hidden[quest] = on and true or nil
    if on and ns.Leads(quest) then
        local left = {}
        for _, id in ipairs(ns.cdb.guide.targets) do if id ~= quest then left[#left + 1] = id end end
        ns.cdb.guide.targets = left
        ns.StepGuide()
    end
    if ns.Refresh then ns.Refresh() end
end

function ns.Reset()
    for k, v in pairs(ns.DEFAULTS) do ns.db[k] = v end
    ns.db.hidden = {}
    ns.db.trackerPoint = nil
    if ns.PlaceTracker then ns.PlaceTracker() end
    if ns.Refresh then ns.Refresh() end
end

-- The hub's switch: a paused module leads nowhere and tells nothing.
function ns.Pause(on)
    ns.paused = on and true or false
    if on and ns.Guiding() then ns.StopGuide() end
    if ns.RefreshTracker then ns.RefreshTracker() end
    if ns.Refresh then ns.Refresh() end
end

-- Slash command -------------------------------------------------------------------------------------

function ns.Slash(msg)
    local cmd = strtrim(msg or ""):lower()
    if cmd == "lead" then
        if not ns.StartGuide() then print(L.TITLE .. ": " .. L.NOTHING) end
    elseif cmd == "stop" then
        ns.StopGuide()
    elseif cmd == "reset" then
        ns.Reset()
        print(L.TITLE .. ": " .. L.RESET_DONE)
    elseif cmd == "help" then
        print(L.TITLE .. ": " .. L.HELP)
    else
        ns.Toggle()
    end
end

-- Events ----------------------------------------------------------------------------------------------

-- Quest log, bag and item news come in bursts: one refresh a moment later.
local function later()
    if ns.pending then return end
    ns.pending = true
    C_Timer.After(0.5, function()
        ns.pending = nil
        if ns.paused then return end
        if ns.Guiding() then ns.StepGuide() elseif ns.Refresh then ns.Refresh() end
        ns.CheckNew()
        ns.CheckBooks()
    end)
end
ns.Later = later

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliWorthItDB = GulliWorthItDB or {}
        GulliWorthItCharDB = GulliWorthItCharDB or {}
        ns.db, ns.cdb = GulliWorthItDB, GulliWorthItCharDB
        for k, v in pairs(ns.DEFAULTS) do
            if ns.db[k] == nil then ns.db[k] = v end
        end
        ns.db.hidden = ns.db.hidden or {}
        ns.db.slots = ns.db.slots or {}
        for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE",
                             "PLAYER_LEVEL_UP", "BAG_UPDATE_DELAYED", "ZONE_CHANGED_NEW_AREA",
                             "GET_ITEM_INFO_RECEIVED" }) do
            self:RegisterEvent(e)
        end
        return
    end
    if ns.paused then return end
    if event == "PLAYER_ENTERING_WORLD" then
        -- a guide kept over a reload leads on
        if ns.Guiding() then claim() end
        later()
    elseif event == "QUEST_TURNED_IN" then
        ns.OnTurnedIn(a1)
    else
        later()
    end
end)

SLASH_GULLIWORTHIT1 = "/gwi"
SLASH_GULLIWORTHIT2 = "/worthit"
SlashCmdList.GULLIWORTHIT = function(msg) ns.Slash(msg) end

function GulliWorthIt_Toggle() ns.Toggle() end

-- With the hub: its row and button there; alone: its own minimap button (Skin.lua).
do
    local register = GulliToolkit and GulliToolkit.Register or function(info) ns.alone = info end
    local function opt(key)
        local up = key:upper()
        return { label = L["OPT_" .. up], tip = L["OPT_" .. up .. "_TIP"], icon = ns.OPT_ICON[key],
                 get = function() return ns.db ~= nil and ns.db[key] == true end,
                 set = function(v) ns.SetPref(key, v) end }
    end
    register({
        key = "WorthIt",
        icon = ns.ICON,
        slash = "/gwi",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        summary = function() return ns.Summary() end,
        pause = function(on) ns.Pause(on) end,
        reset = function() ns.Reset() end,
        move = function(on) if ns.MoveTracker then ns.MoveTracker(on) end end,
        frames = { { key = "tracker", icon = "Interface\\Icons\\INV_Misc_Map_02",
                     frame = function() return ns.TrackerFrame and ns.TrackerFrame() end } },
        options = { opt("better"), opt("notify"), opt("showDone") },
    })
end
