-- Before a dungeon: its quests (in the log, can take now and where, not yet), their rewards
-- and chains, the way there with the entrance, and a short checklist of what runs out
-- inside: repairs, bag space, food and drink, the hearthstone, keys and class supplies.

local ADDON, ns = ...
local L = ns.L

local HEARTHSTONE = 6948
local CONSUMABLE, FOOD_DRINK = 0, 5

local function data()
    return ns.Data or { dungeons = {}, byDungeon = {}, quest = {} }
end

-- Settings: the checklist thresholds and the switches. Each change goes through ns.Set.
ns.DEFAULTS = {
    durMin = 50, bagsMin = 6, foodMin = 10, ammoMin = 400, shardsMin = 5, reagentMin = 5,
    keys = true, classCheck = true, remind = true, tomtom = true, hideLater = false,
}

function ns.Get(key)
    local v = ns.db and ns.db[key]
    if v == nil then return ns.DEFAULTS[key] end
    return v
end

function ns.Set(key, value)
    if ns.db then ns.db[key] = value end
    if ns.Refresh then ns.Refresh() end
end

-- Puts every setting back to its default and shows hidden quests again.
function ns.Reset()
    if not ns.db then return end
    for k in pairs(ns.DEFAULTS) do ns.db[k] = nil end
    ns.db.hidden = {}
    if ns.Refresh then ns.Refresh() end
end

function ns.Hidden(id) return ns.db and ns.db.hidden and ns.db.hidden[id] == true end

function ns.SetHidden(id, on)
    if not ns.db then return end
    ns.db.hidden = ns.db.hidden or {}
    ns.db.hidden[id] = on and true or nil
    if ns.Refresh then ns.Refresh() end
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
local function itemCount(id)
    return ((C_Item and C_Item.GetItemCount) or GetItemCount or function() return 0 end)(id) or 0
end
local function itemInfo(id)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not get then return nil end
    local name, link, quality, ilvl, _, _, _, _, equipLoc, icon, _, classID, subclassID = get(id)
    if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    return name, link, quality, ilvl, equipLoc, icon, classID, subclassID
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

local FACTION = { Alliance = "A", Horde = "H" }

local function forMe(q)
    local side = q[11] or ""
    if side ~= "" and FACTION[UnitFactionGroup("player") or ""] and side ~= FACTION[UnitFactionGroup("player")] then
        return false
    end
    return hasBit(q[4], select(3, UnitRace("player"))) and hasBit(q[5], select(3, UnitClass("player")))
end

-- The highest quest level that is gray for this player level.
function ns.GrayLevel(level)
    if level == UnitLevel("player") then
        local range = (UnitQuestTrivialLevelRange and UnitQuestTrivialLevelRange("player"))
            or (GetQuestGreenRange and GetQuestGreenRange())
        if range then return math.max(0, level - range - 1) end
    end
    if level <= 5 then return 0 end
    if level <= 39 then return level - 5 - math.floor(level / 10) end
    if level <= 59 then return level - 1 - math.floor(level / 5) end
    return level - 9
end

-- The game's quest colours: red, orange, yellow, green, gray.
ns.DIFF_COLOR = {
    IMPOSSIBLE = { 1.00, 0.10, 0.10, 1 }, VERYDIFFICULT = { 1.00, 0.50, 0.25, 1 },
    DIFFICULT = { 1.00, 0.82, 0.00, 1 }, STANDARD = { 0.25, 0.75, 0.25, 1 }, TRIVIAL = { 0.50, 0.50, 0.50, 1 },
}

-- How hard a quest of this level is for the player, as the game colours it.
function ns.Difficulty(questLevel, level)
    local diff = questLevel - level
    if diff >= 5 then return "IMPOSSIBLE" end
    if diff >= 3 then return "VERYDIFFICULT" end
    if diff >= -2 then return "DIFFICULT" end
    if questLevel > ns.GrayLevel(level) then return "STANDARD" end
    return "TRIVIAL"
end

-- The same colours for a dungeon: red below its range, orange just below, yellow in its
-- lower half, green in the upper half, gray above it.
function ns.DungeonDifficulty(d, level)
    if level < d.min - 2 then return "IMPOSSIBLE" end
    if level < d.min then return "VERYDIFFICULT" end
    if level <= (d.min + d.max) / 2 then return "DIFFICULT" end
    if level <= d.max then return "STANDARD" end
    return "TRIVIAL"
end

-- A game icon for each dungeon, by key.
ns.ICONS = {
    RFC = "Spell_Fire_Fire", WC = "Spell_Nature_Sleep", DM = "INV_Pick_02", SFK = "Ability_Hunter_Pet_Wolf",
    BFD = "Spell_Frost_SummonWaterElemental", STOCKS = "INV_BannerPVP_02", GNOMER = "INV_Gizmo_02",
    RFK = "Ability_Hunter_Pet_Boar", SM = "Spell_Holy_HolyBolt", RFD = "Spell_Shadow_AnimateDead",
    ULDA = "INV_Misc_StoneTablet_05", ZF = "INV_Misc_Head_Troll_01", MARA = "Spell_Nature_ResistNature",
    ST = "INV_Misc_Head_Dragon_Green", BRD = "Spell_Fire_Volcano", BRS = "INV_Misc_Head_Dragon_Black",
    DIREMAUL = "INV_Crown_01", SCHOLO = "INV_Misc_Bone_HumanSkull_01", STRAT = "Spell_Shadow_RaiseDead",
}

function ns.Icon(key)
    return "Interface\\Icons\\" .. (ns.ICONS[key] or "INV_Misc_QuestionMark")
end

-- Dungeons in level order: { key, areas, name, min, max, fits }.
function ns.Dungeons(level)
    local out = {}
    for _, d in ipairs(data().dungeons) do
        out[#out + 1] = { key = d[1], areas = d[2], en = d[3], min = d[4], max = d[5],
                          fits = level >= d[4] - 2 and level <= d[5],
                          entrance = d[6] and { area = d[6], x = d[7] or 0, y = d[8] or 0 } }
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

-- The first earlier quest still missing: { id, name, who, area }, from the dungeon quests or D.pre.
local function missing(q)
    local D = data()
    local ids = {}
    for _, p in ipairs(q[8] or {}) do if not questDone(p) then ids[#ids + 1] = p end end
    if #(q[9] or {}) > 0 then
        local one = false
        for _, p in ipairs(q[9]) do if questDone(p) or onQuest(p) then one = true end end
        if not one then ids[#ids + 1] = q[9][1] end
    end
    for _, p in ipairs(ids) do
        local d = D.quest[p]
        if d then return { id = p, name = d[1], who = d[6], area = d[7] } end
        d = D.pre and D.pre[p]
        if d then return { id = p, name = d[1], who = d[3], area = d[4] } end
    end
    if ids[1] then return { id = ids[1] } end
end

local function matches(entry, text)
    if not text or text == "" then return true end
    text = text:lower()
    local function has(s) return s and s ~= "" and s:lower():find(text, 1, true) ~= nil end
    if has(entry.name) or has(entry.who) or has(entry.turnin and entry.turnin.who) then return true end
    for _, t in ipairs(entry.targets or {}) do if has(t) then return true end end
    return false
end

-- The quests of a dungeon for this character, split in three lists and a done count:
-- log (in the quest log), take (can take now), later (level too low or an earlier quest missing).
-- Quests the player hid go to `hidden` instead; `filter` is a text to find in the name, the
-- quest givers or the mobs.
function ns.Quests(key, level, filter)
    local D = data()
    local out = { log = {}, take = {}, later = {}, hidden = {}, done = 0 }
    for _, id in ipairs(D.byDungeon[key] or {}) do
        local q = D.quest[id]
        if q and forMe(q) then
            local closed = false
            for _, other in ipairs(q[10] or {}) do if questDone(other) then closed = true end end
            local entry = { id = id, name = (Q.GetTitleForQuestID and Q.GetTitleForQuestID(id)) or q[1],
                            level = q[2], minLevel = q[3], who = q[6], area = q[7],
                            x = q[12] or 0, y = q[13] or 0, step = q[18] or 0, steps = q[19] or 0,
                            reward = D.reward and D.reward[id], targets = D.target and D.target[id] }
            if q[14] and q[14] ~= "" then
                entry.turnin = { who = q[14], area = q[15] or 0, zone = areaName(q[15]), x = q[16] or 0, y = q[17] or 0 }
            end
            if questDone(id) then
                out.done = out.done + 1
            elseif not matches(entry, filter) then
                -- left out by the search
            elseif ns.Hidden(id) then
                out.hidden[#out.hidden + 1] = entry
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
                    entry.need = missing(q)
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
    table.sort(out.hidden, byLevel)
    return out
end

-- Where an earlier quest starts, as one line ("Name (who, zone)"), or just its name.
function ns.NeedText(need)
    if not need then return L.WHY_EARLIER end
    if not need.name then return L.WHY_EARLIER end
    local where = ns.Where({ who = need.who or "", area = need.area or 0 })
    return where ~= "" and L.NEEDS_AT:format(need.name, where) or L.NEEDS:format(need.name)
end

-- Armour each class wears best (plate and mail from level 40) and the weapon subclasses it
-- can learn. Item class 4 is armour, 2 weapons; armour subclass 0 is rings, necks, trinkets.
local ARMOR, WEAPON = 4, 2
local BEST_ARMOR = {
    WARRIOR = { 3, 4 }, PALADIN = { 3, 4 }, HUNTER = { 2, 3 }, SHAMAN = { 2, 3 }, ROGUE = { 2, 2 },
    DRUID = { 2, 2 }, PRIEST = { 1, 1 }, MAGE = { 1, 1 }, WARLOCK = { 1, 1 },
}
local SHIELD = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local WEAPONS = {
    WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }, PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
    HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }, ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
    PRIEST = { 4, 10, 15, 19 }, SHAMAN = { 0, 1, 4, 5, 10, 13, 15 }, MAGE = { 7, 10, 15, 19 },
    WARLOCK = { 7, 10, 15, 19 }, DRUID = { 4, 5, 10, 13, 15 },
}

-- Whether an item is meant for this class: its best armour, any cloak or jewellery, a
-- shield it can carry, or a weapon it can learn. Anything else (a potion, a bag) fits too.
function ns.Fits(classID, subclassID, equipLoc, class, level)
    if classID == ARMOR then
        if subclassID == 0 or equipLoc == "INVTYPE_CLOAK" then return true end
        if subclassID == 6 then return SHIELD[class] == true end
        local best = BEST_ARMOR[class]
        if not best then return true end
        return subclassID == best[(level or 1) >= 40 and 2 or 1]
    elseif classID == WEAPON then
        for _, s in ipairs(WEAPONS[class] or {}) do if s == subclassID then return true end end
        return WEAPONS[class] == nil
    end
    return true
end

-- The gear slots an equip location fills, to compare with what is worn.
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_SHIELD = { 17 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
}

-- The lowest item level worn in the slots, 0 for an empty one.
local function wornLevel(slots)
    local low
    for _, slot in ipairs(slots) do
        local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
        local ilvl = 0
        if link then ilvl = select(4, itemInfo(link)) or 0 end
        low = low and math.min(low, ilvl) or ilvl
    end
    return low or 0
end

-- A quest's reward items: { id, name, link, icon, quality, fits, better }. `better` is an item
-- for this class with a higher item level than what is worn there. Names come once the game
-- has the item; until then only the id.
function ns.Rewards(entry)
    local out = {}
    local _, class = UnitClass("player")
    local level = UnitLevel("player") or 1
    for _, id in ipairs(entry.reward or {}) do
        local name, link, quality, ilvl, equipLoc, icon, classID, subclassID = itemInfo(id)
        local r = { id = id, name = name, link = link, icon = icon, quality = quality }
        if name then
            r.fits = ns.Fits(classID, subclassID, equipLoc, class, level)
            local slots = SLOTS[equipLoc or ""]
            r.better = r.fits and slots ~= nil and (ilvl or 0) > wornLevel(slots)
        end
        out[#out + 1] = r
    end
    return out
end

-- Experience and money of a quest in the log, when the game tells them.
function ns.LogReward(id)
    local xp = GetQuestLogRewardXP and GetQuestLogRewardXP(id)
    local money = GetQuestLogRewardMoney and GetQuestLogRewardMoney(id)
    return type(xp) == "number" and xp or 0, type(money) == "number" and money or 0
end

-- Group members (names) who have this quest too.
function ns.GroupOn(id)
    local out = {}
    if not (Q.IsUnitOnQuest and IsInGroup and IsInGroup()) then return out end
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists and UnitExists(unit) and Q.IsUnitOnQuest(unit, id) then
            local name = UnitName(unit)
            if not (issecretvalue and issecretvalue(name)) then out[#out + 1] = name end
        end
    end
    return out
end

-- Shares a quest of the log with the group. Returns true when it was offered.
function ns.Share(id)
    if not (IsInGroup and IsInGroup() and QuestLogPushQuest) then return false end
    if Q.SetSelectedQuest then
        Q.SetSelectedQuest(id)
    elseif SelectQuestLogEntry and Q.GetLogIndexForQuestID then
        SelectQuestLogEntry(Q.GetLogIndexForQuestID(id))
    end
    QuestLogPushQuest()
    print("|cff9ad0ffGulli-DungeonPrep|r: " .. L.SHARED)
    return true
end

function ns.Where(q)
    local zone = areaName(q.area)
    if q.who == "" then return zone or "" end
    return zone and L.WHERE:format(q.who, zone) or q.who
end

-- Where the player is: { zone (the zone map's name), x, y (map percent), kalimdor }, from
-- the world map; fields are nil where the game does not tell (inside an instance).
local MAP = C_Map or {}
local CONTINENT, ZONE, KALIMDOR, EASTERN = 2, 3, 1414, 1415
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
    for _, a in ipairs(data().kalimdor or {}) do if a == area then return true end end
    return false
end

local function dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

-- The quests to take as stops on one way to the dungeon: { who, area, zone, x, y, quests,
-- here, inside }. Stops in the player's zone come first, nearest first from where the
-- player stands; then other zones on the same continent, then the other continent, each
-- zone with the most quests first. Quests started by an item or inside the dungeon go last.
function ns.Route(take, here, dungeon)
    here = here or {}
    local stops, byKey, inside = {}, {}, nil
    for _, q in ipairs(take) do
        if q.area == 0 or (q.x == 0 and q.y == 0) then
            inside = inside or { inside = true, quests = {} }
            inside.quests[#inside.quests + 1] = q
        else
            local key = q.who .. "@" .. q.area
            local s = byKey[key]
            if not s then
                s = { who = q.who, area = q.area, zone = areaName(q.area), x = q.x, y = q.y, quests = {},
                      kalimdor = onKalimdor(q.area) }
                s.here = here.zone ~= nil and s.zone == here.zone
                byKey[key] = s
                stops[#stops + 1] = s
            end
            s.quests[#s.quests + 1] = q
        end
    end
    local zones, byArea = {}, {}
    for _, s in ipairs(stops) do
        local z = byArea[s.area]
        if not z then
            z = { stops = {}, count = 0, here = s.here, area = s.area,
                  tier = s.here and 0 or ((here.kalimdor == nil or s.kalimdor == here.kalimdor) and 1 or 2) }
            byArea[s.area] = z
            zones[#zones + 1] = z
        end
        z.stops[#z.stops + 1] = s
        z.count = z.count + #s.quests
    end
    table.sort(zones, function(a, b)
        if a.tier ~= b.tier then return a.tier < b.tier end
        if a.count ~= b.count then return a.count > b.count end
        return a.area < b.area
    end)
    local out = {}
    for _, z in ipairs(zones) do
        local left = z.stops
        table.sort(left, function(a, b)
            if #a.quests ~= #b.quests then return #a.quests > #b.quests end
            return a.who < b.who
        end)
        local px, py
        if z.here and here.x then px, py = here.x, here.y end
        while #left > 0 do
            local best = 1
            if px then
                for i = 2, #left do
                    if dist(px, py, left[i].x, left[i].y) < dist(px, py, left[best].x, left[best].y) then best = i end
                end
            end
            local s = table.remove(left, best)
            out[#out + 1] = s
            px, py = s.x, s.y
        end
    end
    local e = dungeon and dungeon.entrance
    if e and e.area > 0 then
        out[#out + 1] = { entrance = true, who = ns.DungeonName(dungeon), area = e.area, zone = areaName(e.area),
                          x = e.x, y = e.y, quests = {} }
    end
    if inside then out[#out + 1] = inside end
    return out
end

-- A map pin on a stop, through the world map's own waypoint. Returns true when it is set.
local mapOfZone
function ns.SetPin(stop)
    if not (stop.zone and MAP.SetUserWaypoint and UiMapPoint and MAP.GetMapChildrenInfo) then return false end
    if not mapOfZone then
        mapOfZone = {}
        for _, c in ipairs({ KALIMDOR, EASTERN }) do
            for _, m in ipairs(MAP.GetMapChildrenInfo(c, nil, true) or {}) do
                if m.name and not mapOfZone[m.name] then mapOfZone[m.name] = m.mapID end
            end
        end
    end
    local id = mapOfZone[stop.zone]
    if not id then return false end
    MAP.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(id, stop.x / 100, stop.y / 100))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    -- TomTom's arrow too, when it is installed (never needed).
    if ns.Get("tomtom") and TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(id, stop.x / 100, stop.y / 100, { title = stop.who, from = "Gulli-DungeonPrep" })
    end
    print("|cff9ad0ffGulli-DungeonPrep|r: " .. L.PIN_SET:format(stop.who))
    return true
end

-- Keys and items that open a dungeon or a part of it.
ns.KEYS = {
    SM = { 7146 },       -- The Scarlet Key
    GNOMER = { 6893 },   -- Workshop Key
    ZF = { 9240 },       -- Mallet of Zul'Farrak
    BRD = { 11000 },     -- Shadowforge Key
    BRS = { 12344 },     -- Seal of Ascension
    DIREMAUL = { 18249 }, -- Crescent Key
    SCHOLO = { 13704 },  -- Skeleton Key
    STRAT = { 12382 },   -- Key to the City
}

-- What each class brings along: a reagent from the level its spell comes, or ammo and shards.
ns.CLASS_ITEMS = {
    PRIEST = { id = 17028, level = 48 },  -- Holy Candle
    MAGE = { id = 17020, level = 56 },    -- Arcane Powder
    SHAMAN = { id = 17030, level = 30 },  -- Ankh
    DRUID = { id = 17034, level = 20 },   -- Maple Seed
    ROGUE = { id = 5140, level = 22 },    -- Flash Powder
    PALADIN = { id = 21177, level = 52 }, -- Symbol of Kings
    WARLOCK = { id = 6265, level = 1, key = "SHARDS" }, -- Soul Shard
}

local function nameOf(id)
    return itemInfo(id) or ("item:" .. id)
end

-- The checklist: { key, ok, text } for repairs, bag space, food and drink, hearthstone, then
-- the keys of the dungeon (`dungeonKey`) and what the class brings along.
function ns.Checklist(dungeonKey)
    local out = {}
    local lowest = 100
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then lowest = math.min(lowest, math.floor(cur * 100 / max)) end
    end
    out[#out + 1] = { key = "REPAIR", ok = lowest >= ns.Get("durMin"), text = L.CHECK_REPAIR:format(lowest) }

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
    out[#out + 1] = { key = "BAGS", ok = free >= ns.Get("bagsMin"), text = L.CHECK_BAGS:format(free) }
    out[#out + 1] = { key = "FOOD", ok = food >= ns.Get("foodMin"), text = L.CHECK_FOOD:format(food) }

    local start, duration = itemCooldown(HEARTHSTONE)
    local left = (start > 0 and duration > 0) and math.ceil(start + duration - GetTime()) or 0
    out[#out + 1] = { key = "HEARTH", ok = left <= 0,
                      text = left > 0 and L.CHECK_HEARTH_CD:format(math.ceil(left / 60)) or L.CHECK_HEARTH }

    -- Gulli Restock, when it runs: what its keep list misses.
    if GulliRestock and GulliRestock.Missing then
        local miss = GulliRestock.Missing() or {}
        local names = {}
        for i, m in ipairs(miss) do
            if i <= 2 then names[#names + 1] = m.name .. " " .. m.have .. "/" .. m.want end
        end
        if #miss > 2 then names[#names + 1] = "..." end
        out[#out + 1] = { key = "RESTOCK", ok = #miss == 0,
                          text = #miss == 0 and L.CHECK_RESTOCK_OK or L.CHECK_RESTOCK:format(table.concat(names, ", ")) }
    end

    if ns.Get("keys") and dungeonKey then
        for _, id in ipairs(ns.KEYS[dungeonKey] or {}) do
            local have = itemCount(id) > 0
            out[#out + 1] = { key = "KEY", item = id, ok = have,
                              text = (have and L.CHECK_KEY or L.CHECK_NO_KEY):format(nameOf(id)) }
        end
    end
    if ns.Get("classCheck") then
        local _, class = UnitClass("player")
        local level = UnitLevel("player") or 1
        if class == "HUNTER" then
            local ammo = GetInventoryItemCount and GetInventoryItemCount("player", 0) or 0
            out[#out + 1] = { key = "AMMO", ok = ammo >= ns.Get("ammoMin"), text = L.CHECK_AMMO:format(ammo) }
        end
        local c = ns.CLASS_ITEMS[class]
        if c and level >= c.level then
            local n = itemCount(c.id)
            local min = ns.Get(c.key == "SHARDS" and "shardsMin" or "reagentMin")
            out[#out + 1] = { key = c.key or "REAGENT", item = c.id, ok = n >= min,
                              text = L.CHECK_ITEM:format(n, nameOf(c.id)) }
        end
    end
    return out
end

-- Finished dungeon quests in the log: { entry with turnin }, for the reminder after a run.
function ns.HandIns()
    local D = data()
    local out, seen = {}, {}
    for _, ids in pairs(D.byDungeon) do
        for _, id in ipairs(ids) do
            local q = D.quest[id]
            if q and not seen[id] and onQuest(id) and Q.IsComplete and Q.IsComplete(id) then
                seen[id] = true
                out[#out + 1] = { id = id, name = (Q.GetTitleForQuestID and Q.GetTitleForQuestID(id)) or q[1],
                                  turnin = { who = q[14] or "", area = q[15] or 0, zone = areaName(q[15]),
                                             x = q[16] or 0, y = q[17] or 0 } }
            end
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

-- Leaving a dungeon: one line per finished quest with where to hand it in, a pin on the first.
function ns.Remind()
    if not ns.Get("remind") then return end
    local list = ns.HandIns()
    if #list == 0 then return end
    for _, q in ipairs(list) do
        local where = q.turnin.who ~= "" and ns.Where({ who = q.turnin.who, area = q.turnin.area }) or ""
        print("|cff9ad0ffGulli-DungeonPrep|r: " .. L.HAND_IN:format(q.name, where))
    end
    if GulliToolkit and GulliToolkit.Notify then
        GulliToolkit.Notify("DungeonPrep", L.HAND_IN_N:format(#list))
    end
    local first = list[1].turnin
    if first.who ~= "" and first.x > 0 then ns.SetPin(first) end
end

local wasInside = false
local function checkLeave()
    local inside, kind = false, nil
    if IsInInstance then inside, kind = IsInInstance() end
    inside = inside and (kind == "party" or kind == "raid")
    if wasInside and not inside then ns.Remind() end
    wasInside = inside and true or false
end
ns.CheckLeave = checkLeave

-- One line for the hub's home page: the dungeon for this level and its quests.
function ns.Summary()
    local level = UnitLevel("player") or 1
    local d = ns.Suggest(level)
    if not d then return nil end
    local q = ns.Quests(d.key, level)
    if #q.log + #q.take == 0 then return nil end
    return L.SUMMARY:format(ns.DungeonName(d), #q.log, #q.take), ns.Icon(d.key)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliDungeonPrepDB = GulliDungeonPrepDB or {}
        ns.db = GulliDungeonPrepDB
        ns.db.hidden = ns.db.hidden or {}
        self:RegisterEvent("QUEST_LOG_UPDATE")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        self:RegisterEvent("BAG_UPDATE_DELAYED")
        self:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
        self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        return
    end
    if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then checkLeave() end
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

-- The game icon of each switch, in the window and in the hub.
ns.OPT_ICON = {
    remind = "Interface\\Icons\\INV_Letter_15", keys = "Interface\\Icons\\INV_Misc_Key_04",
    classCheck = "Interface\\Icons\\INV_Misc_Bag_10", tomtom = "Interface\\Icons\\INV_Misc_Map_01",
    hideLater = "Interface\\Icons\\INV_Misc_PocketWatch_01",
}

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "DungeonPrep",
        icon = "Interface\\AddOns\\Gulli-DungeonPrep\\icon",
        slash = "/gdp",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        summary = function() return ns.Summary() end,
        reset = function() ns.Reset() end,
        options = {
            { label = L.OPT_REMIND, tip = L.OPT_REMIND_D, icon = ns.OPT_ICON.remind,
              get = function() return ns.Get("remind") end, set = function(v) ns.Set("remind", v) end },
            { label = L.OPT_KEYS, tip = L.OPT_KEYS_D, icon = ns.OPT_ICON.keys,
              get = function() return ns.Get("keys") end, set = function(v) ns.Set("keys", v) end },
            { label = L.OPT_CLASS, tip = L.OPT_CLASS_D, icon = ns.OPT_ICON.classCheck,
              get = function() return ns.Get("classCheck") end, set = function(v) ns.Set("classCheck", v) end },
            { label = L.OPT_TOMTOM, tip = L.OPT_TOMTOM_D, icon = ns.OPT_ICON.tomtom,
              get = function() return ns.Get("tomtom") end, set = function(v) ns.Set("tomtom", v) end },
        },
    })
end
