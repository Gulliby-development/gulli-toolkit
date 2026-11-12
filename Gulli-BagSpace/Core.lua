-- Frees the number of bag slots the player asks for. The plan: merge partial stacks, then
-- sell or delete the cheapest junk (gray items, then white gear). Nothing goes before the
-- player sees the list and presses OK; at a vendor items are sold (and can be bought back).

local ADDON, ns = ...
local L = ns.L

local ITEM_WEAPON, ITEM_ARMOR, ITEM_QUEST, ITEM_KEY = 2, 4, 12, 13
local HEARTHSTONE = 6948

-- Game API wrappers.
local C = C_Container or {}
local function numSlots(bag) return (C.GetContainerNumSlots or GetContainerNumSlots)(bag) or 0 end
local function freeSlots(bag)
    local free, family = (C.GetContainerNumFreeSlots or GetContainerNumFreeSlots)(bag)
    return free or 0, family or 0
end
local function slotInfo(bag, slot)
    if C.GetContainerItemInfo then
        local i = C.GetContainerItemInfo(bag, slot)
        if not i then return nil end
        return i.itemID, i.stackCount, i.isLocked, i.hyperlink, i.iconFileID, i.quality
    end
    local icon, count, locked, quality, _, _, link, _, _, id = GetContainerItemInfo(bag, slot)
    return id, count, locked, link, icon, quality
end
local function itemInfo(id)
    local name, link, quality, _, _, _, _, maxStack, _, icon, price, classID = ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(id)
    return name, quality, maxStack or 1, price or 0, classID, icon
end
local function pickup(bag, slot) (C.PickupContainerItem or PickupContainerItem)(bag, slot) end
local function split(bag, slot, n) (C.SplitContainerItem or SplitContainerItem)(bag, slot, n) end
local function useItem(bag, slot) (C.UseContainerItem or UseContainerItem)(bag, slot) end
local function cursorItem()
    local kind, id = GetCursorInfo()
    return kind == "item" and id or nil
end
local function protected(id)
    return id == HEARTHSTONE or (GulliToolkit and GulliToolkit.IsProtected and GulliToolkit.IsProtected(id)) or false
end

ns.BAGS = { 0, 1, 2, 3, 4 }

-- Free and total slots in normal bags (a herb or soul bag does not help other items).
function ns.Space()
    local free, total = 0, 0
    for _, bag in ipairs(ns.BAGS) do
        local f, family = freeSlots(bag)
        if family == 0 then
            free = free + f
            total = total + numSlots(bag)
        end
    end
    return free, total
end

function ns.Items()
    local out = {}
    for _, bag in ipairs(ns.BAGS) do
        local _, family = freeSlots(bag)
        if family == 0 then
            for slot = 1, numSlots(bag) do
                local id, count, locked, link, icon = slotInfo(bag, slot)
                if id then
                    local name, quality, maxStack, price, classID, icon2 = itemInfo(id)
                    out[#out + 1] = { bag = bag, slot = slot, id = id, count = count or 1, locked = locked,
                                      link = link, name = name or link or ("item:" .. id), quality = quality or 1,
                                      maxStack = maxStack, price = price, classID = classID, icon = icon or icon2 }
                end
            end
        end
    end
    return out
end

-- Stack merges: for each item with more stacks than it needs, the moves that fill the
-- fullest stacks from the emptiest. Returns moves and the slots they free.
function ns.Merges(items)
    local groups, order = {}, {}
    for _, it in ipairs(items) do
        if it.maxStack > 1 and it.count < it.maxStack and not protected(it.id) then
            if not groups[it.id] then groups[it.id] = {}; order[#order + 1] = it.id end
            table.insert(groups[it.id], { bag = it.bag, slot = it.slot, count = it.count, item = it })
        end
    end
    local moves, freed = {}, 0
    for _, id in ipairs(order) do
        local g = groups[id]
        if #g > 1 then
            table.sort(g, function(a, b) return a.count > b.count end)
            local max = g[1].item.maxStack
            local i, j = 1, #g
            while i < j do
                local room = max - g[i].count
                if room <= 0 then
                    i = i + 1
                else
                    local n = math.min(room, g[j].count)
                    moves[#moves + 1] = { from = g[j], to = g[i], n = n, id = id }
                    g[i].count = g[i].count + n
                    g[j].count = g[j].count - n
                    if g[j].count == 0 then j = j - 1; freed = freed + 1 end
                end
            end
        end
    end
    return moves, freed
end

-- How sure we are an item is junk: 1 gray, 2 white gear, 3 other white items (offered
-- unticked). Quest items, keys, better items and protected items are never offered.
function ns.Tier(it)
    if protected(it.id) or it.classID == ITEM_QUEST or it.classID == ITEM_KEY then return nil end
    if it.quality == 0 then return 1 end
    if it.quality ~= 1 or it.price <= 0 then return nil end
    if it.classID == ITEM_WEAPON or it.classID == ITEM_ARMOR then return 2 end
    return 3
end

-- The plan for `want` free slots: { merges, freedByMerges, items (ticked or not), free, total }.
function ns.Plan(want)
    local items = ns.Items()
    local free, total = ns.Space()
    local merges, merged = ns.Merges(items)
    local need = math.max(0, want - free - merged)
    local cands = {}
    for _, it in ipairs(items) do
        local tier = ns.Tier(it)
        if tier then
            it.tier = tier
            it.value = it.price * it.count
            cands[#cands + 1] = it
        end
    end
    table.sort(cands, function(a, b)
        if a.tier ~= b.tier then return a.tier < b.tier end
        if a.value ~= b.value then return a.value < b.value end
        return a.name < b.name
    end)
    -- Gray items always; white gear while slots are still missing; other white items
    -- (cloth, food, ...) only as a suggestion, unticked.
    local picked, extra = {}, 0
    for _, it in ipairs(cands) do
        if it.tier == 1 or (it.tier == 2 and need > 0) then
            it.checked = true
            need = need - 1
            picked[#picked + 1] = it
        elseif it.tier == 3 and need > 0 and extra < need + 3 then
            it.checked = false
            extra = extra + 1
            picked[#picked + 1] = it
        end
    end
    return { merges = merges, merged = merged, items = picked, free = free, total = total, want = want }
end

function ns.Summary(plan)
    local slots, value = plan.merged, 0
    for _, it in ipairs(plan.items) do
        if it.checked then slots = slots + 1; value = value + it.value end
    end
    return slots, value
end

-- Runs inside the OK click: sells at a vendor, deletes elsewhere, then merges stacks.
function ns.Run(plan)
    if InCombatLockdown() then return 0, 0 end
    ClearCursor()
    local sold, deleted = 0, 0
    for _, it in ipairs(plan.items) do
        if it.checked then
            local id, _, locked = slotInfo(it.bag, it.slot)
            if id == it.id and not locked then
                if ns.atMerchant and it.price > 0 then
                    useItem(it.bag, it.slot)
                    sold = sold + 1
                else
                    pickup(it.bag, it.slot)
                    if cursorItem() == it.id then
                        DeleteCursorItem()
                        deleted = deleted + 1
                    end
                    if GetCursorInfo() then ClearCursor() end
                end
            end
        end
    end
    ns.StartMerges(plan.merges)
    return sold, deleted
end

-- Moving items is not instant, so merges run one at a time on a short timer.
local queue = {}
local function step()
    local m = table.remove(queue, 1)
    if not m then
        if ns.Refresh then ns.Refresh(true) end
        return
    end
    local id, count, locked = slotInfo(m.from.bag, m.from.slot)
    local toID, _, toLocked = slotInfo(m.to.bag, m.to.slot)
    if id == m.id and toID == m.id and not locked and not toLocked and not InCombatLockdown() then
        ClearCursor()
        split(m.from.bag, m.from.slot, math.min(m.n, count or m.n))
        pickup(m.to.bag, m.to.slot)
        if GetCursorInfo() then ClearCursor() end
    end
    C_Timer.After(0.3, step)
end

function ns.StartMerges(moves)
    local idle = #queue == 0
    for _, m in ipairs(moves) do queue[#queue + 1] = m end
    if idle and #queue > 0 then step() end
end

function ns.Money(copper)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    if g > 0 then return string.format("%dg %ds %dc", g, s, c) end
    if s > 0 then return string.format("%ds %dc", s, c) end
    return string.format("%dc", c)
end

-- A hint in the chat when the bags are nearly full; it never removes anything.
local hinted = false
local function checkFull()
    local free = ns.Space()
    if free > ns.db.warnAt then hinted = false; return end
    if hinted then return end
    hinted = true
    local msg = L.ALMOST_FULL:format(free)
    print("|cff9ad0ffGulli Bag Space|r: " .. msg)
    if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("BagSpace", msg) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliBagSpaceDB = GulliBagSpaceDB or {}
        ns.db = GulliBagSpaceDB
        ns.db.want = ns.db.want or 5
        ns.db.warnAt = ns.db.warnAt or 2
        self:RegisterEvent("MERCHANT_SHOW")
        self:RegisterEvent("MERCHANT_CLOSED")
        self:RegisterEvent("BAG_UPDATE_DELAYED")
        return
    end
    if event == "BAG_UPDATE_DELAYED" then
        checkFull()
        if ns.Refresh then ns.Refresh(true) end
        return
    end
    ns.atMerchant = event == "MERCHANT_SHOW"
    if ns.Refresh then ns.Refresh(false) end
end)

SLASH_GULLIBAGSPACE1 = "/gbs"
SLASH_GULLIBAGSPACE2 = "/gullibagspace"
SlashCmdList.GULLIBAGSPACE = function(msg)
    local n = tonumber(strtrim(msg or ""))
    if n and n > 0 then ns.db.want = math.floor(n) end
    ns.Toggle()
end

function GulliBagSpace_Toggle() ns.Toggle() end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "BagSpace",
        icon = "Interface\\AddOns\\Gulli-BagSpace\\icon",
        slash = "/gbs",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
    })
end
