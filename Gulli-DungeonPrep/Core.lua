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
                            level = q[2], minLevel = q[3], who = q[6], area = q[7],
                            x = q[12] or 0, y = q[13] or 0 }
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
function ns.Route(take, here)
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
    print("|cff9ad0ffGulli-DungeonPrep|r: " .. L.PIN_SET:format(stop.who))
    return true
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
        self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
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
        window = function() return ns.Window and ns.Window() end,
    })
end
