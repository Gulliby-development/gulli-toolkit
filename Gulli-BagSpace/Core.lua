-- Frees the number of bag slots the player asks for. The plan: merge partial stacks, then
-- sell or delete the cheapest junk (gray items, then white gear). Nothing goes before the
-- player sees the list and presses OK; at a vendor items are sold (and can be bought back).

local ADDON, ns = ...
local L = ns.L

local J = ns.J
local BATCH, STEP = J.BATCH, J.STEP
ns.DEFAULTS = { want = 5, warnAt = 2, unusable = true, counter = true, popup = true }
local AH_FACTOR = 2 -- an auction price this many times the vendor price keeps an item off the ticks

-- Game API wrappers.
local C = C_Container or {}
local function numSlots(bag) return (C.GetContainerNumSlots or GetContainerNumSlots)(bag) or 0 end
local function freeSlots(bag)
    local free, family = (C.GetContainerNumFreeSlots or GetContainerNumFreeSlots)(bag)
    return free or 0, family or 0
end
local slotInfo = J.SlotInfo
local function pickup(bag, slot) (C.PickupContainerItem or PickupContainerItem)(bag, slot) end
local function split(bag, slot, n) (C.SplitContainerItem or SplitContainerItem)(bag, slot, n) end
local useItem = J.UseItem
local function cursorItem()
    local kind, id = GetCursorInfo()
    return kind == "item" and id or nil
end
local protected = J.Protected
-- The auction price of one item from Auctionator, when it is loaded.
local function ahPrice(id)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.GetAuctionPriceByItemID) then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemID, "Gulli-BagSpace", id)
    return ok and price or nil
end
local function sortBags() local fn = C.SortBags or SortBags if fn then fn() return true end end

ns.TOOLS = J.TOOLS
ns.BAGS = J.BAGS

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

function ns.Items() return J.Scan(true) end

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

-- How sure we are an item is junk (the shared rules in Junk.lua): 1 gray or "always sell",
-- 2 white gear and bound gear the class cannot use, 3 other white items (offered unticked).
-- Items the player unticked before (`keep`) are not offered until /gbs reset.
function ns.Tier(it)
    if ns.db and ns.db.keep[it.id] then return nil end
    return J.Tier(it, { unusable = not ns.db or ns.db.unusable })
end

-- The plan for `want` free slots: { merges, freedByMerges, items (ticked or not), free, total }.
function ns.Plan(want)
    local items = ns.Items()
    local free, total = ns.Space()
    local merges, merged = ns.Merges(items)
    local need = math.max(0, want - free - merged)
    local cands = {}
    for _, it in ipairs(items) do
        local tier, why = ns.Tier(it)
        if tier then
            it.tier, it.why = tier, why
            it.value = it.price * it.count
            -- Worth more at the auction house: offered, but never ticked.
            if tier > 1 then
                local ah = ahPrice(it.id)
                if ah and ah > math.max(it.price * AH_FACTOR, it.price + 100) then it.ah = ah * it.count end
            end
            it.boe = it.bound == false and (it.classID == 2 or it.classID == 4)
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
        if it.ah and (it.tier == 2 or (it.tier == 3 and need > 0 and extra < need + 3)) then
            it.checked = false
            if it.tier == 3 then extra = extra + 1 end
            picked[#picked + 1] = it
        elseif it.tier == 1 or (it.tier == 2 and need > 0) then
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

-- Sells in steps of 12, so the vendor keeps up; stops when the vendor closes.
local selling = {}
local function sellStep()
    for _ = 1, BATCH do
        local it = table.remove(selling, 1)
        if not it then return end
        if not ns.atMerchant then wipe(selling); return end
        local id, _, locked = slotInfo(it.bag, it.slot)
        if id == it.id and not locked then useItem(it.bag, it.slot) end
    end
    if #selling > 0 then C_Timer.After(STEP, sellStep) end
end

-- Runs inside the OK click: sells at a vendor (in steps), deletes elsewhere, then merges
-- stacks. Returns how many items it sells and deletes.
function ns.Run(plan)
    if InCombatLockdown() then return 0, 0 end
    ClearCursor()
    local sold, deleted = 0, 0
    local idle = #selling == 0
    for _, it in ipairs(plan.items) do
        if it.checked then
            local id, _, locked = slotInfo(it.bag, it.slot)
            if id == it.id and not locked then
                if ns.atMerchant and it.price > 0 then
                    selling[#selling + 1] = it
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
    if idle and #selling > 0 then sellStep() end
    ns.StartMerges(plan.merges)
    return sold, deleted
end

-- What the game did not take: ticked items still in their slots a moment after OK (a
-- delete the game refused). The window offers them again, ticked, for one more OK.
function ns.Leftover(plan)
    local out = {}
    for _, it in ipairs(plan.items) do
        if it.checked and slotInfo(it.bag, it.slot) == it.id then out[#out + 1] = it end
    end
    return out
end

-- How many ticked items a sale would sell: past 12, the first ones cannot be bought back.
function ns.ToSell(plan)
    local n = 0
    if not ns.atMerchant then return 0 end
    for _, it in ipairs(plan.items) do if it.checked and it.price > 0 then n = n + 1 end end
    return n
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

-- Unticking an item in the plan keeps it out of later plans, until /gbs reset; ticking it
-- again takes it back.
function ns.SetKept(it, kept)
    ns.db.keep[it.id] = kept and true or nil
end

function ns.KeptCount()
    local n = 0
    for _ in pairs(ns.db.keep) do n = n + 1 end
    return n
end

-- The one item "Free 1 slot" would sell or delete: the cheapest ticked candidate of a plan
-- for one more slot (a gray item first, else white gear).
function ns.OneItem()
    local plan = ns.Plan(ns.Space() + 1)
    for _, it in ipairs(plan.items) do
        if it.checked and not it.ah then return it end
    end
end

-- Runs inside the click of the Free 1 slot button.
function ns.FreeOne()
    local it = ns.OneItem()
    if not it then return nil end
    ns.Run({ items = { { bag = it.bag, slot = it.slot, id = it.id, price = it.price, checked = true } }, merges = {} })
    return it
end

function ns.SortBags() return sortBags() end
function ns.CanSort() return (C.SortBags or SortBags) ~= nil end

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
f:SetScript("OnEvent", function(self, event, a1, ...)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliBagSpaceDB = GulliBagSpaceDB or {}
        ns.db = GulliBagSpaceDB
        for k, v in pairs(ns.DEFAULTS) do if ns.db[k] == nil then ns.db[k] = v end end
        ns.db.keep = ns.db.keep or {}
        ns.db.junk = ns.db.junk or {}
        J.Attach(ns.db.junk)
        J.OnChange(function() if ns.Refresh then ns.Refresh(true) end end)
        J.InstallMarks({ JUNK_TIP = L.JUNK_TIP, ALWAYS_TIP = L.ALWAYS_TIP, MARKED = L.MARKED, UNMARKED = L.UNMARKED })
        self:RegisterEvent("UI_ERROR_MESSAGE")
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:RegisterEvent("MERCHANT_SHOW")
        self:RegisterEvent("MERCHANT_CLOSED")
        self:RegisterEvent("BAG_UPDATE_DELAYED")
        self:RegisterEvent("PLAYER_LOGIN")
        return
    end
    if event == "PLAYER_LOGIN" then
        if ns.UpdateCounter then ns.UpdateCounter() end
        return
    end
    if event == "BAG_UPDATE_DELAYED" then
        checkFull()
        if ns.UpdateCounter then ns.UpdateCounter() end
        if ns.Refresh then ns.Refresh(true) end
        return
    end
    if event == "UI_ERROR_MESSAGE" then
        -- Retail sends (type, message), older clients only the message.
        local msg = (...) or a1
        if ns.db.popup and (msg == ERR_INV_FULL or msg == ERR_BAG_FULL) and not InCombatLockdown()
            and ns.ShowPopup then
            ns.ShowPopup()
        end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        if ns.HidePopup then ns.HidePopup() end
        return
    end
    ns.atMerchant = event == "MERCHANT_SHOW"
    if not ns.atMerchant then wipe(selling) end
    if ns.Refresh then ns.Refresh(false) end
end)

SLASH_GULLIBAGSPACE1 = "/gbs"
SLASH_GULLIBAGSPACE2 = "/gullibagspace"
SlashCmdList.GULLIBAGSPACE = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "reset" then
        wipe(ns.db.keep)
        print("|cff9ad0ffGulli Bag Space|r: " .. L.RESET_DONE)
        if ns.Refresh then ns.Refresh(true) end
        return
    end
    if msg == "sort" then ns.SortBags() return end
    local n = tonumber(msg)
    if n and n > 0 then ns.db.want = math.floor(n) end
    ns.Toggle()
end

function GulliBagSpace_Toggle() ns.Toggle() end

-- The game icon of each switch, in the window and in the hub.
ns.OPT_ICON = {
    unusable = "Interface\\Icons\\INV_Gauntlets_04",
    counter = "Interface\\Icons\\INV_Misc_Bag_08",
    popup = "Interface\\Icons\\INV_Misc_Bag_10",
}

local function option(key, label)
    return { label = label, icon = ns.OPT_ICON[key], tip = ns.L["TIP_" .. key], get = function() return ns.db ~= nil and ns.db[key] == true end,
             set = function(on)
                 if not ns.db then return end
                 ns.db[key] = on and true or false
                 if key == "counter" and ns.UpdateCounter then ns.UpdateCounter() end
             end }
end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        options = { option("unusable", ns.L.OPT_UNUSABLE), option("counter", ns.L.OPT_COUNTER),
                    option("popup", ns.L.OPT_POPUP) },
        key = "BagSpace",
        icon = "Interface\\AddOns\\Gulli-BagSpace\\icon",
        slash = "/gbs",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        summary = function()
            if not ns.db then return nil end
            local free = ns.Space()
            return ns.L.HUB_SUMMARY:format(free), "Interface\\Icons\\INV_Misc_Bag_10"
        end,
        reset = function()
            if not ns.db then return end
            for k, v in pairs(ns.DEFAULTS) do ns.db[k] = v end
            if ns.UpdateCounter then ns.UpdateCounter() end
            if ns.Refresh then ns.Refresh(true) end
        end,
    })
end
