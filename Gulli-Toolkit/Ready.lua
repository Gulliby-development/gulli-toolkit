-- Readiness on the hub's home page: what runs out on a long trip or in a dungeon (repairs, bag
-- space, food, drink, the hearthstone, ammo and class reagents, and Gulli Restock's list when it
-- runs). The thresholds live in GulliToolkitDB.ready; the Ready card and its page only show this.

local _, ns = ...
local L = ns.L

ns.READY_DEFAULTS = {
    show = true, classCheck = true,
    durMin = 50, bagsMin = 6, foodMin = 10, drinkMin = 10, ammoMin = 400, shardsMin = 5, reagentMin = 5,
}

function ns.ReadyGet(key)
    local db = GulliToolkitDB and GulliToolkitDB.ready
    local v = db and db[key]
    if v == nil then return ns.READY_DEFAULTS[key] end
    return v
end

function ns.ReadySet(key, value)
    GulliToolkitDB = GulliToolkitDB or {}
    GulliToolkitDB.ready = GulliToolkitDB.ready or {}
    GulliToolkitDB.ready[key] = value
    if ns.Refresh then ns.Refresh() end
end

function ns.ReadyReset()
    if GulliToolkitDB then GulliToolkitDB.ready = nil end
    if ns.Refresh then ns.Refresh() end
end

-- Game API wrappers (the C_ call first, the old global as fallback).
local HEARTHSTONE = 6948
local CONSUMABLE, FOOD_DRINK = 0, 5
local C = C_Container or {}
local function numSlots(bag)
    local f = C.GetContainerNumSlots or GetContainerNumSlots
    return f and f(bag) or 0
end
local function freeSlots(bag)
    local f = C.GetContainerNumFreeSlots or GetContainerNumFreeSlots
    if not f then return 0, 0 end
    local free, family = f(bag)
    return free or 0, family or 0
end
local function slotItem(bag, slot)
    if C.GetContainerItemInfo then
        local i = C.GetContainerItemInfo(bag, slot)
        return i and i.itemID, i and i.stackCount
    elseif GetContainerItemInfo then
        local _, count, _, _, _, _, _, _, _, id = GetContainerItemInfo(bag, slot)
        return id, count
    end
end
local function itemClass(id)
    local get = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not get then return nil end
    local _, _, _, _, _, classID, subclassID = get(id)
    return classID, subclassID
end
local function itemSpell(id)
    local get = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not get then return nil end
    return (get(id))
end
local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and (GetSpellInfo(id)) or nil
end
local function itemCount(id)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    return f and f(id) or 0
end
-- "..." until the client has the name; the hub redraws when it comes (ns.OnItemInfo).
local function itemName(id)
    return ns.ItemName(id) or "..."
end
local function itemIcon(id)
    local get = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    return get and get(id) or nil
end
local function itemCooldown(id)
    local f = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not f then return 0, 0 end
    local start, duration = f(id)
    return start or 0, duration or 0
end

-- Classes that drink: everyone with mana.
local NO_MANA = { WARRIOR = true, ROGUE = true, DEATHKNIGHT = true }

-- What each class brings along: a reagent from the level its spell comes, or shards.
ns.READY_CLASS_ITEMS = {
    PRIEST = { id = 17028, level = 48 },  -- Holy Candle
    MAGE = { id = 17020, level = 56 },    -- Arcane Powder
    SHAMAN = { id = 17030, level = 30 },  -- Ankh
    DRUID = { id = 17034, level = 20 },   -- Maple Seed
    ROGUE = { id = 5140, level = 22 },    -- Flash Powder
    PALADIN = { id = 21177, level = 52 }, -- Symbol of Kings
    WARLOCK = { id = 6265, level = 1, key = "SHARDS" }, -- Soul Shard
}

ns.READY_ICON = {
    REPAIR = "Interface\\Icons\\Trade_BlackSmithing", BAGS = "Interface\\Icons\\INV_Misc_Bag_10",
    FOOD = "Interface\\Icons\\INV_Misc_Food_14", DRINK = "Interface\\Icons\\INV_Drink_07",
    HEARTH = "Interface\\Icons\\INV_Misc_Rune_01", AMMO = "Interface\\Icons\\INV_Ammo_Arrow_02",
    SHARDS = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02", REAGENT = "Interface\\Icons\\INV_Misc_Dust_02",
    RESTOCK = "Interface\\Icons\\INV_Misc_Bag_08",
}

-- Food and drink in the bags. A drink is an item whose use spell is the game's Drink; anything
-- else of the food and drink class counts as food.
function ns.FoodAndDrink()
    local drinkName = spellName(430)
    local food, drink = 0, 0
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        for slot = 1, numSlots(bag) do
            local id, count = slotItem(bag, slot)
            if id then
                local class, sub = itemClass(id)
                if class == CONSUMABLE and sub == FOOD_DRINK then
                    local s = itemSpell(id)
                    if drinkName and s == drinkName then drink = drink + (count or 1) else food = food + (count or 1) end
                end
            end
        end
    end
    return food, drink
end

-- The bar of a count against its limit: the limit sits in the middle (mark), twice the limit
-- fills the bar. No limit: a full bar without a mark.
local function against(n, min)
    if not min or min <= 0 then return 1, nil end
    return math.max(0, math.min(1, n / (2 * min))), 0.5
end
ns.ReadyBar = against

-- The checks: { key, ok, value (short), label (what it is, short), text (the whole line), icon,
-- frac (0-1, how full its bar is), mark (0-1, where the limit sits on the bar, or nil) }.
function ns.Readiness()
    local out = {}
    local function add(key, ok, value, text, icon, frac, mark, label)
        out[#out + 1] = { key = key, ok = ok, value = value, text = text, icon = icon or ns.READY_ICON[key],
                          frac = frac or (ok and 1 or 0), mark = mark, label = label or L["RD_L_" .. key] or text }
    end
    local lowest = 100
    if GetInventoryItemDurability then
        for slot = 1, 18 do
            local cur, max = GetInventoryItemDurability(slot)
            if cur and max and max > 0 then lowest = math.min(lowest, math.floor(cur * 100 / max)) end
        end
    end
    add("REPAIR", lowest >= ns.ReadyGet("durMin"), lowest .. "%", L.RD_REPAIR:format(lowest), nil,
        lowest / 100, ns.ReadyGet("durMin") / 100)

    local free = 0
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        local f, family = freeSlots(bag)
        if family == 0 then free = free + f end
    end
    add("BAGS", free >= ns.ReadyGet("bagsMin"), tostring(free), L.RD_BAGS:format(free), nil,
        against(free, ns.ReadyGet("bagsMin")))

    local food, drink = ns.FoodAndDrink()
    add("FOOD", food >= ns.ReadyGet("foodMin"), tostring(food), L.RD_FOOD:format(food), nil,
        against(food, ns.ReadyGet("foodMin")))
    local _, class = UnitClass("player")
    if not NO_MANA[class or ""] then
        add("DRINK", drink >= ns.ReadyGet("drinkMin"), tostring(drink), L.RD_DRINK:format(drink), nil,
            against(drink, ns.ReadyGet("drinkMin")))
    end

    local start, duration = itemCooldown(HEARTHSTONE)
    local left = (start > 0 and duration > 0 and GetTime) and math.ceil(start + duration - GetTime()) or 0
    if left > 0 then
        local min = math.ceil(left / 60)
        -- the bar fills as the cooldown runs out
        add("HEARTH", false, L.RD_MIN:format(min), L.RD_HEARTH_CD:format(min), nil,
            math.max(0, math.min(1, 1 - left / duration)))
    else
        add("HEARTH", true, L.RD_OK, L.RD_HEARTH)
    end

    if ns.ReadyGet("classCheck") then
        local level = UnitLevel and UnitLevel("player") or 1
        if class == "HUNTER" then
            local ammo = GetInventoryItemCount and GetInventoryItemCount("player", 0) or 0
            add("AMMO", ammo >= ns.ReadyGet("ammoMin"), tostring(ammo), L.RD_AMMO:format(ammo), nil,
                against(ammo, ns.ReadyGet("ammoMin")))
        end
        local c = ns.READY_CLASS_ITEMS[class or ""]
        if c and level >= c.level then
            local n = itemCount(c.id)
            local min = ns.ReadyGet(c.key == "SHARDS" and "shardsMin" or "reagentMin")
            local frac, mark = against(n, min)
            add(c.key or "REAGENT", n >= min, tostring(n), L.RD_ITEM:format(n, itemName(c.id)), itemIcon(c.id),
                frac, mark, itemName(c.id))
        end
    end

    -- Gulli Restock, when it runs: what its keep list misses.
    if GulliRestock and GulliRestock.Missing then
        local miss = GulliRestock.Missing() or {}
        local names = {}
        local have, want = 0, 0
        for i, m in ipairs(miss) do
            if i <= 2 then names[#names + 1] = m.name .. " " .. m.have .. "/" .. m.want end
            have, want = have + (tonumber(m.have) or 0), want + (tonumber(m.want) or 0)
        end
        if #miss > 2 then names[#names + 1] = "..." end
        add("RESTOCK", #miss == 0, #miss == 0 and L.RD_OK or tostring(#miss),
            #miss == 0 and L.RD_RESTOCK_OK or L.RD_RESTOCK:format(table.concat(names, ", ")), nil,
            #miss == 0 and 1 or (want > 0 and math.min(1, have / want) or 0), nil,
            -- one thing missing: its name and count say more than "Restock 1"
            #miss == 1 and miss[1].name or nil)
        if #miss == 1 then out[#out].value = miss[1].have .. "/" .. miss[1].want end
    end
    return out
end

-- How many checks pass, and how many there are.
function ns.ReadyCount(list)
    local ok = 0
    for _, c in ipairs(list) do if c.ok then ok = ok + 1 end end
    return ok, #list
end

-- The bags and gear change often; the hub redraws only while it is open.
local f = CreateFrame("Frame")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
f:SetScript("OnEvent", function()
    if ns.Refresh then ns.Refresh() end
end)
