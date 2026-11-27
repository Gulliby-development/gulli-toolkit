-- Equip new bags: a plain bag that comes into the bags goes into an empty bag slot at once (out
-- of a fight; Shift skips it). With no slot free, a bigger bag than the smallest worn one gets a
-- notice, and its button swaps them when the smaller bag is empty. Only a worn plain bag is ever
-- offered for a swap: a quiver, an ammo pouch or a soul bag gives what a plain bag cannot.

local _, ns = ...

local ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local ITEM_CONTAINER = 1
local frame, seen, offered

local function numSlots(bag) local C = C_Container or {}; return (C.GetContainerNumSlots or GetContainerNumSlots)(bag) or 0 end
local function itemID(bag, slot)
    local C = C_Container or {}
    if C.GetContainerItemID then return C.GetContainerItemID(bag, slot) end
    return GetContainerItemID and GetContainerItemID(bag, slot)
end
local function invSlot(bag)
    local C = C_Container or {}
    if C.ContainerIDToInventoryID then return C.ContainerIDToInventoryID(bag) end
    return ContainerIDToInventoryID and ContainerIDToInventoryID(bag)
end
local function pickup(bag, slot) local C = C_Container or {}; (C.PickupContainerItem or PickupContainerItem)(bag, slot) end

-- A plain bag (class Container, subclass Bag): never a quiver, a soul bag or a herb bag.
local function isPlainBag(id)
    if not id then return false end
    local classID, subclassID
    if C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, _, _, c, s = C_Item.GetItemInfoInstant(id)
        classID, subclassID = c, s
    end
    return classID == ITEM_CONTAINER and subclassID == 0
end

local slotsPattern
local function pattern()
    if slotsPattern then return slotsPattern end
    local f = type(CONTAINER_SLOTS) == "string" and CONTAINER_SLOTS or "%d Slot %s"
    f = f:gsub("([%(%)%.%+%-%*%?%[%]%^])", "%%%1")
    f = f:gsub("%%(%d?%$?)([ds])", function(_, t) return t == "d" and "(%d+)" or ".+" end)
    slotsPattern = "^" .. f .. "$"
    return slotsPattern
end

-- How many slots a bag item has, from its tooltip (nil while the client does not know).
function ns.BagItemSlots(id)
    local data = C_TooltipInfo and C_TooltipInfo.GetItemByID and C_TooltipInfo.GetItemByID(id)
    for _, line in ipairs(data and data.lines or {}) do
        local text = line.leftText
        if type(text) == "string" and not (issecretvalue and issecretvalue(text)) then
            local n = tonumber(text:match(pattern()))
            if n and n > 0 then return n end
        end
    end
    return nil
end

local function bagCount() return NUM_BAG_SLOTS or 4 end

-- The worn bag slots: { bag, inv, empty, slots, free } for bags 1 .. NUM_BAG_SLOTS (the reagent
-- bag slot takes only reagent bags).
function ns.WornBags()
    local out = {}
    for bag = 1, bagCount() do
        local inv = invSlot(bag)
        if inv then
            local worn = GetInventoryItemID and GetInventoryItemID("player", inv)
            local n, used = numSlots(bag), 0
            for s = 1, n do if itemID(bag, s) then used = used + 1 end end
            out[#out + 1] = { bag = bag, inv = inv, empty = worn == nil, id = worn, slots = n, free = used == 0 }
        end
    end
    return out
end

local function put(bag, slot, inv)
    pickup(bag, slot)
    if PutItemInBag then PutItemInBag(inv) elseif EquipCursorItem then EquipCursorItem(inv) end
    if ClearCursor and CursorHasItem and CursorHasItem() then ClearCursor() end
end

-- The plain bags that came into the bags since the last look: { bag, slot, id }.
local function arrivals()
    local now, out = {}, {}
    for bag = 0, bagCount() do
        for slot = 1, numSlots(bag) do
            local id = itemID(bag, slot)
            if isPlainBag(id) then
                local key = bag * 100 + slot
                now[key] = id
                if seen and seen[key] ~= id then out[#out + 1] = { bag = bag, slot = slot, id = id } end
            end
        end
    end
    seen = now
    return out
end

local function offerSwap(new, worn)
    local S = ns.Skin
    if not S or not S.Toast then return end
    offered = offered or {}
    if offered[new.id] then return end
    offered[new.id] = true
    local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(new.id)) or ""
    local buttons
    if worn.free then
        buttons = { { text = ns.L.TWP_BAGS_SWAP, primary = true, onClick = function()
            if InCombatLockdown and InCombatLockdown() then return end
            if itemID(new.bag, new.slot) == new.id then put(new.bag, new.slot, worn.inv) end
        end } }
    end
    S.Toast({ key = "autoBags", icon = ICON, title = ns.L.TW_AUTOBAGS,
              text = (worn.free and ns.L.TWP_BAGS_BIGGER or ns.L.TWP_BAGS_EMPTY):format(name, worn.slots),
              buttons = buttons, seconds = 20 })
end

-- Puts every new plain bag on: an empty slot first, else offers to swap the smallest worn bag.
function ns.EquipNewBags()
    -- In a fight nothing is looked at, so a bag that comes in then is still new afterwards.
    if InCombatLockdown and InCombatLockdown() then return 0 end
    local new = arrivals()
    if #new == 0 or ns.TweakSkip() then return 0 end
    local done = 0
    for _, e in ipairs(new) do
        local slot
        for _, w in ipairs(ns.WornBags()) do if w.empty then slot = w break end end
        if slot then
            put(e.bag, e.slot, slot.inv)
            done = done + 1
        else
            local size = ns.BagItemSlots(e.id)
            local small
            for _, w in ipairs(ns.WornBags()) do
                if isPlainBag(w.id) and (not small or w.slots < small.slots) then small = w end
            end
            if size and small and size > small.slots then offerSwap(e, small) end
        end
    end
    return done
end

local function onEvent() ns.EquipNewBags() end

ns.AutoBagsEvent = onEvent

ns.AddTweak({
    key = "autoBags", group = "loot", icon = ICON, shift = true,
    enable = function()
        frame = frame or CreateFrame("Frame")
        frame:SetScript("OnEvent", onEvent)
        frame:RegisterEvent("BAG_UPDATE_DELAYED")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        seen = nil
        arrivals()   -- what is in the bags now is not new
    end,
    disable = function()
        if frame then frame:UnregisterAllEvents() end
        seen, offered = nil, nil
    end,
})
