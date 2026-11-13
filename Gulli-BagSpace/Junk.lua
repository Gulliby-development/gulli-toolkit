-- Junk rules shared by Gulli Merchant and Gulli Bag Space: what counts as junk, the "always
-- sell" list, selling in steps of 12, and the marks in the bags (Alt+click, the tooltip line,
-- the coin on a junk slot). The original is Gulli-Merchant/Junk.lua; tools/junk/sync.sh copies
-- it into Gulli-BagSpace. Change only the original. Each addon keeps working alone: when both
-- are loaded, their "always sell" lists are kept the same and the bag marks are made once.

local _, ns = ...
local J = {}
ns.J = J

local ITEM_WEAPON, ITEM_ARMOR, ITEM_QUEST, ITEM_KEY = 2, 4, 12, 13
local FISHING_POLE = 20 -- weapon subclass
local HEARTHSTONE = 6948
J.BATCH, J.STEP = 12, 0.25 -- the vendor buys back the last 12; sell in steps of that size

-- Profession tools are plain white items, but losing one hurts: never offer them.
J.TOOLS = {
    [2901] = true,  -- Mining Pick
    [7005] = true,  -- Skinning Knife
    [5956] = true,  -- Blacksmith Hammer
    [6219] = true,  -- Arclight Spanner
    [10498] = true, -- Gyromatic Micro-Adjustor
    [9149] = true,  -- Philosopher's Stone
    [4471] = true,  -- Flint and Tinder
    [6218] = true,  -- Runed Copper Rod
    [6339] = true,  -- Runed Silver Rod
    [11130] = true, -- Runed Golden Rod
    [11145] = true, -- Runed Truesilver Rod
    [16207] = true, -- Runed Arcanite Rod
    [6256] = true,  -- Fishing Pole
    [6365] = true,  -- Strong Fishing Pole
    [6366] = true,  -- Darkwood Fishing Pole
    [6367] = true,  -- Big Iron Fishing Pole
    [12225] = true, -- Blump Family Fishing Pole
    [19022] = true, -- Nat Pagle's Extreme Angler FC-5000
    [19970] = true, -- Arcanite Fishing Pole
}

-- Armour (4) and weapon (2) subclasses each class can learn to use. Armour subclass 0
-- (rings, necks, trinkets) and cloth cloaks fit everyone.
local A = { CLOTH = 1, LEATHER = 2, MAIL = 3, PLATE = 4, SHIELD = 6 }
local function set(...) local t = {} for _, v in ipairs({ ... }) do t[v] = true end return t end
J.CAN_USE = {
    WARRIOR = { armor = set(0, 1, 2, 3, 4, 6), weapon = set(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18) },
    PALADIN = { armor = set(0, 1, 2, 3, 4, 6, 7), weapon = set(0, 1, 4, 5, 6, 7, 8) },
    HUNTER = { armor = set(0, 1, 2, 3), weapon = set(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18) },
    ROGUE = { armor = set(0, 1, 2), weapon = set(2, 3, 4, 7, 13, 15, 16, 18) },
    PRIEST = { armor = set(0, 1), weapon = set(4, 10, 15, 19) },
    SHAMAN = { armor = set(0, 1, 2, 3, 6, 9), weapon = set(0, 1, 4, 5, 10, 13, 15) },
    MAGE = { armor = set(0, 1), weapon = set(7, 10, 15, 19) },
    WARLOCK = { armor = set(0, 1), weapon = set(7, 10, 15, 19) },
    DRUID = { armor = set(0, 1, 2, 8), weapon = set(4, 5, 10, 13, 15) },
}
J.ARMOR = A

-- Game API wrappers.
local C = C_Container or {}
local function numSlots(bag) return (C.GetContainerNumSlots or GetContainerNumSlots)(bag) or 0 end
local function bagFamily(bag)
    local _, family = (C.GetContainerNumFreeSlots or GetContainerNumFreeSlots)(bag)
    return family or 0
end
local function slotInfo(bag, slot)
    if C.GetContainerItemInfo then
        local i = C.GetContainerItemInfo(bag, slot)
        if not i then return nil end
        return i.itemID, i.stackCount, i.isLocked, i.hyperlink, i.iconFileID, i.quality, i.hasNoValue
    end
    local icon, count, locked, quality, _, _, link, _, noValue, id = GetContainerItemInfo(bag, slot)
    return id, count, locked, link, icon, quality, noValue
end
J.SlotInfo = slotInfo
local function itemInfo(id)
    local name, _, quality, _, _, _, _, maxStack, equipLoc, icon, price, classID, subclassID =
        ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(id)
    return name, quality, maxStack or 1, price or 0, classID, icon, subclassID, equipLoc
end
local function inSet(bag, slot)
    local fn = C.GetContainerItemEquipmentSetInfo or GetContainerItemEquipmentSetInfo
    return fn and fn(bag, slot) and true or false
end
-- true, false, or nil when the game cannot tell.
local function isBound(bag, slot)
    if C_Item and C_Item.IsBound and ItemLocation and ItemLocation.CreateFromBagAndSlot then
        local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
        return C_Item.IsBound(loc) and true or false
    end
    return nil
end
local function useItem(bag, slot) (C.UseContainerItem or UseContainerItem)(bag, slot) end
J.UseItem = useItem

function J.Protected(id)
    return id == HEARTHSTONE or (GulliToolkit and GulliToolkit.IsProtected and GulliToolkit.IsProtected(id)) or false
end

-- The items in the bags: { bag, slot, id, count, locked, link, name, quality, maxStack, price,
-- classID, subclassID, equipLoc, icon, inSet, bound, value }. normalOnly leaves out herb,
-- soul and other special bags.
J.BAGS = { 0, 1, 2, 3, 4 }
-- One bag slot as a Scan record, or nil when it is empty.
function J.Item(bag, slot)
    local id, count, locked, link, icon, slotQuality, noValue = slotInfo(bag, slot)
    if not id then return nil end
    local name, quality, maxStack, price, classID, icon2, subclassID, equipLoc = itemInfo(id)
    quality = slotQuality or quality
    if noValue then price = 0 end
    count = count or 1
    return { bag = bag, slot = slot, id = id, count = count, locked = locked, link = link,
             name = name or link or ("item:" .. id), quality = quality or 1,
             maxStack = maxStack, price = price, classID = classID, subclassID = subclassID,
             equipLoc = equipLoc, icon = icon or icon2, inSet = inSet(bag, slot),
             bound = isBound(bag, slot), value = price * count }
end

function J.Scan(normalOnly)
    local out = {}
    for _, bag in ipairs(J.BAGS) do
        if not normalOnly or bagFamily(bag) == 0 then
            for slot = 1, numSlots(bag) do
                local it = J.Item(bag, slot)
                if it then out[#out + 1] = it end
            end
        end
    end
    return out
end

-- The "always sell" list (item id -> true). Each addon keeps its own copy in its saved
-- variables; while both are loaded a mark goes into both.
local shared = GulliJunkShared or { lists = {} }
GulliJunkShared = shared
function J.Attach(list) shared.lists[#shared.lists + 1] = list end
function J.IsAlways(id)
    for _, l in ipairs(shared.lists) do if l[id] then return true end end
    return false
end
function J.SetAlways(id, on)
    for _, l in ipairs(shared.lists) do l[id] = on and true or nil end
    for _, fn in ipairs(shared.changed or {}) do fn() end
end
function J.AlwaysIDs()
    local seen, out = {}, {}
    for _, l in ipairs(shared.lists) do
        for id in pairs(l) do if not seen[id] then seen[id] = true; out[#out + 1] = id end end
    end
    table.sort(out)
    return out
end
-- fn() runs when the list or the bags' junk changes, so a window can refresh.
function J.OnChange(fn)
    shared.changed = shared.changed or {}
    shared.changed[#shared.changed + 1] = fn
end

-- Gear this character can never use: armour or a weapon type outside its class. Only bound
-- items count, since an unbound one can still go to the auction house or another character.
function J.Unusable(it)
    if it.bound ~= true then return false end
    local _, class = UnitClass("player")
    local can = J.CAN_USE[class or ""]
    if not can then return false end
    if it.classID == ITEM_ARMOR then
        if it.equipLoc == "INVTYPE_CLOAK" then return false end
        return it.subclassID ~= nil and not can.armor[it.subclassID]
    end
    if it.classID == ITEM_WEAPON then
        return it.subclassID ~= nil and it.subclassID ~= FISHING_POLE and not can.weapon[it.subclassID]
    end
    return false
end

-- Never junk: quest items, keys, profession tools and fishing poles, items of an equipment
-- set, the hearthstone and items protected in the toolkit.
function J.Never(it)
    return J.Protected(it.id) or it.classID == ITEM_QUEST or it.classID == ITEM_KEY or J.TOOLS[it.id] or it.inSet
        or (it.classID == ITEM_WEAPON and it.subclassID == FISHING_POLE) or false
end

-- How sure we are an item is junk, and why: 1 for gray items and the "always sell" list,
-- 2 for white weapons and armour and (opts.unusable) bound gear the class cannot use,
-- 3 for other white items. nil means never offer it.
function J.Tier(it, opts)
    if J.Never(it) then return nil end
    if J.IsAlways(it.id) then return 1, "always" end
    if it.quality == 0 then return 1, "gray" end
    if opts and opts.unusable and (it.quality or 1) <= 2 and it.price > 0 and J.Unusable(it) then
        return 2, "unusable"
    end
    if it.quality ~= 1 or it.price <= 0 then return nil end
    if it.classID == ITEM_WEAPON or it.classID == ITEM_ARMOR then return 2, "gear" end
    return 3, "white"
end

-- At a vendor? Both addons read this one flag.
local ev = CreateFrame("Frame")
ev:RegisterEvent("MERCHANT_SHOW")
ev:RegisterEvent("MERCHANT_CLOSED")
ev:SetScript("OnEvent", function(_, event) J.atVendor = event == "MERCHANT_SHOW" end)

-- Sells the items in steps of 12 so the vendor keeps up; an item sells only if its slot still
-- holds it. Stops when the vendor closes. done(sold, value) runs at the end.
J.selling = false
function J.Sell(items, done)
    local i, sold, value = 1, 0, 0
    J.selling = true
    local function step()
        if not J.atVendor then J.selling = false; if done then done(sold, value, true) end return end
        for _ = 1, J.BATCH do
            local it = items[i]
            if not it then
                J.selling = false
                if done then done(sold, value) end
                return
            end
            local id, _, locked = slotInfo(it.bag, it.slot)
            if id == it.id and not locked then
                useItem(it.bag, it.slot)
                sold, value = sold + 1, value + (it.value or 0)
            end
            i = i + 1
        end
        C_Timer.After(J.STEP, step)
    end
    step()
end

-- Bag marks -----------------------------------------------------------------------------------
-- Made once even when both addons are loaded. texts: { JUNK_TIP, ALWAYS_TIP, MARKED, UNMARKED }
-- from the first addon that loads.

local function junkFor(id, bag, slot)
    if not id then return nil end
    local it
    -- Only this slot: a whole bag scan per button froze the game ("script ran too long").
    if bag and slot then
        it = J.Item(bag, slot)
        if it and it.id ~= id then it = nil end
    end
    if not it then
        local name, quality, _, price, classID, _, subclassID = itemInfo(id)
        if not name then return nil end
        it = { id = id, quality = quality or 1, price = price, classID = classID, subclassID = subclassID }
    end
    local tier, why = J.Tier(it)
    if tier == 1 and (it.price or 0) > 0 then return why end
end
J.JunkFor = junkFor

local function buttonPlace(b)
    if not b then return end
    local bag = b.GetBagID and b:GetBagID() or (b.GetParent and b:GetParent() and b:GetParent():GetID())
    local slot = b.GetID and b:GetID()
    return bag, slot
end

-- Each item button of the open bags.
local function eachButton(fn)
    local frames = {}
    if ContainerFrameCombinedBags then frames[#frames + 1] = ContainerFrameCombinedBags end
    for i = 1, 13 do
        local f = _G["ContainerFrame" .. i]
        if f then frames[#frames + 1] = f end
    end
    for _, f in ipairs(frames) do
        if f.IsShown and f:IsShown() then
            if f.EnumerateValidItems then
                for _, b in f:EnumerateValidItems() do fn(b) end
            else
                local name = f.GetName and f:GetName()
                for j = 1, 36 do
                    local b = name and _G[name .. "Item" .. j]
                    if b then fn(b) end
                end
            end
        end
    end
end

-- Bag events and frame updates come in bursts: the coins are redrawn once, on the next frame.
function J.QueueCoins()
    if shared.coinsQueued then return end
    shared.coinsQueued = true
    C_Timer.After(0, function() shared.coinsQueued = false; J.UpdateCoins() end)
end

function J.UpdateCoins()
    if not shared.coins then return end
    eachButton(function(b)
        local bag, slot = buttonPlace(b)
        local id = bag and slot and slotInfo(bag, slot)
        local show = id and junkFor(id, bag, slot) ~= nil
        if show and not b.gulliCoin then
            b.gulliCoin = b:CreateTexture(nil, "OVERLAY")
            b.gulliCoin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
            b.gulliCoin:SetSize(13, 13)
            b.gulliCoin:SetPoint("TOPLEFT", 2, -2)
        end
        if b.gulliCoin then b.gulliCoin:SetShown(show and true or false) end
    end)
end

function J.InstallMarks(texts)
    if shared.marks then return end
    shared.marks = texts
    shared.coins = true
    -- The tooltip line.
    local function addLine(tip, id, bag, slot)
        local why = junkFor(id, bag, slot)
        if not why then return end
        local t = shared.marks
        tip:AddLine("|cff9ad0ffGulli|r " .. (why == "always" and t.ALWAYS_TIP or t.JUNK_TIP), 0.8, 0.8, 0.8)
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
            if tip ~= GameTooltip or not data then return end
            addLine(tip, data.id)
        end)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", function(tip)
            local _, link = tip:GetItem()
            local id = link and tonumber(link:match("item:(%d+)"))
            if id then addLine(tip, id) end
        end)
    end
    -- Alt+click on a bag item marks or unmarks it as "always sell".
    local function onClick(b, button)
        if button ~= "LeftButton" or not (IsAltKeyDown and IsAltKeyDown()) then return end
        local bag, slot = buttonPlace(b)
        local id = bag and slot and slotInfo(bag, slot)
        if not id then return end
        if J.Protected(id) then return end
        local on = not J.IsAlways(id)
        J.SetAlways(id, on)
        local name = itemInfo(id) or ("item:" .. id)
        print("|cff9ad0ffGulli|r: " .. (on and shared.marks.MARKED or shared.marks.UNMARKED):format(name))
        J.UpdateCoins()
    end
    if ContainerFrameItemButtonMixin and ContainerFrameItemButtonMixin.OnModifiedClick then
        hooksecurefunc(ContainerFrameItemButtonMixin, "OnModifiedClick", onClick)
    elseif ContainerFrameItemButton_OnModifiedClick then
        hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", onClick)
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:SetScript("OnEvent", function() J.QueueCoins() end)
    if ContainerFrame_Update then hooksecurefunc("ContainerFrame_Update", function() J.QueueCoins() end) end
    J.OnChange(J.QueueCoins)
end
