-- Frees the number of bag slots the player asks for. The plan: merge partial stacks, then
-- sell or delete the cheapest junk (gray items, then white gear). Nothing goes before the
-- player sees the list and presses OK; at a vendor items are sold (and can be bought back).

local ADDON, ns = ...
local L = ns.L

local J = ns.J
local BATCH, STEP = J.BATCH, J.STEP
ns.DEFAULTS = { want = 5, warnAt = 2, unusable = true, counter = true, popup = true, disenchant = true, bank = false }
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
-- The auction price of one item from any price addon (Auctionator, auxForever, Naowh Forever, ...).
local function ahPrice(id)
    return ns.Skin and ns.Skin.AuctionPrice and (ns.Skin.AuctionPrice(id)) or nil
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
-- stacks. DeleteCursorItem is allowed once per hardware event (a second call is blocked),
-- so one OK deletes one item; ns.Leftover offers the rest for the next OK.
-- Returns how many items it sells and deletes.
function ns.Run(plan)
    if InCombatLockdown() then return 0, 0 end
    ClearCursor()
    local sold, deleted = 0, 0
    local idle = #selling == 0
    local first, fresh
    for _, it in ipairs(plan.items) do
        if it.checked then
            local id, _, locked = slotInfo(it.bag, it.slot)
            if id == it.id and not locked then
                if ns.atMerchant and it.price > 0 then
                    selling[#selling + 1] = it
                    sold = sold + 1
                else
                    first = first or it
                    if not it.tried then fresh = fresh or it end
                end
            end
        end
    end
    -- An item the game refused once goes to the back, so it never holds up the rest.
    local it = fresh or first
    if it then
        it.tried = true
        pickup(it.bag, it.slot)
        if cursorItem() == it.id then
            DeleteCursorItem()
            deleted = 1
        end
        if GetCursorInfo() then ClearCursor() end
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

-- The items a "Bags are full" notice would sell or delete to free n slots: the cheapest ticked
-- candidates of a plan for n more slots (gray items first, else white gear).
function ns.FreeItems(n)
    n = math.max(1, n or 1)
    local plan, out = ns.Plan(ns.Space() + n), {}
    for _, it in ipairs(plan.items) do
        if #out >= n then break end
        if it.checked and not it.ah then out[#out + 1] = it end
    end
    return out
end

function ns.OneItem() return ns.FreeItems(1)[1] end

-- Does an item of this bag family (C_Item.GetItemFamily) go into a bag of that family?
local function fitsFamily(itemFamily, bagFamily)
    if not itemFamily or itemFamily == 0 or not bagFamily or bagFamily == 0 then return false end
    local bit = 1
    while bit <= bagFamily do
        if bagFamily % (bit * 2) >= bit and itemFamily % (bit * 2) >= bit then return true end
        bit = bit * 2
    end
    return false
end

local function maxStackOf(id)
    local n = C_Item and C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(id)
    if not n then n = select(8, ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(id)) end
    return math.max(1, tonumber(n) or 1)
end

-- How many more free slots the open loot window needs than the normal bags have. Each item first
-- fills the room left in its own stacks, then a free slot of a special bag that takes it (herbs,
-- ...), then whole normal slots. nil while no loot window is open.
function ns.LootShort()
    local n = GetNumLootItems and GetNumLootItems() or 0
    if n == 0 or not GetLootSlotLink then return nil end
    local room, special = {}, {}
    for _, bag in ipairs(ns.BAGS) do
        local f, family = freeSlots(bag)
        if family and family ~= 0 and f > 0 then special[#special + 1] = { family = family, free = f } end
    end
    local want = {}
    for i = 1, n do
        local link = GetLootSlotLink(i)
        local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
        if id then
            local count = GetLootSlotInfo and select(3, GetLootSlotInfo(i))
            want[#want + 1] = { id = id, count = math.max(1, tonumber(count) or 1) }
            room[id] = 0
        end
    end
    if #want == 0 then return 0 end
    for _, bag in ipairs(ns.BAGS) do
        for s = 1, numSlots(bag) do
            local id, count = slotInfo(bag, s)
            if id and room[id] then room[id] = room[id] + math.max(0, maxStackOf(id) - (count or 1)) end
        end
    end
    local slots = 0
    for _, w in ipairs(want) do
        local stack = maxStackOf(w.id)
        local fit = math.min(room[w.id], w.count)
        room[w.id] = room[w.id] - fit
        local left = w.count - fit
        while left > 0 do
            local family = C_Item and C_Item.GetItemFamily and C_Item.GetItemFamily(w.id)
            local bag
            for _, b in ipairs(special) do
                if b.free > 0 and fitsFamily(family, b.family) then bag = b; break end
            end
            if bag then bag.free = bag.free - 1 else slots = slots + 1 end
            local put = math.min(stack, left)
            room[w.id] = room[w.id] + stack - put
            left = left - put
        end
    end
    return math.max(0, slots - (ns.Space()))
end

-- Runs inside the click of the notice's button: sells all of them at a vendor, else deletes one
-- (the game allows one delete per click), so the notice stays for the next click.
function ns.FreeSome(items)
    local list = {}
    for _, it in ipairs(items) do
        list[#list + 1] = { bag = it.bag, slot = it.slot, id = it.id, price = it.price, checked = true }
    end
    if #list == 0 then return 0, 0 end
    return ns.Run({ items = list, merges = {} })
end

function ns.FreeOne()
    local it = ns.OneItem()
    if not it then return nil end
    ns.FreeSome({ it })
    return it
end

function ns.SortBags() return sortBags() end

-- Bag frames by name, for a bag addon whose item buttons do not say their bag.
local BAG_FRAMES = { "bag", "container", "inventory", "baganator", "bagnon", "adibags", "arkinv", "combuctor", "elvui" }
local function inBagFrame(f)
    for _ = 1, 10 do
        if not f then return false end
        local name = f.GetName and f:GetName()
        if type(name) == "string" then
            name = name:lower()
            for _, w in ipairs(BAG_FRAMES) do if name:find(w, 1, true) then return true end end
        end
        f = f.GetParent and f:GetParent()
    end
    return false
end

-- The bag slot of the item a tooltip shows: the owner's own bag and slot when it says them, else,
-- for a button in a bag frame, the first slot that holds this item and may be disenchanted.
function ns.BagPlace(owner, id)
    if not owner or not id then return nil end
    local ok, bag = pcall(function() return owner.GetBagID and owner:GetBagID() end)
    local slot = owner.GetID and owner:GetID()
    if ok and type(bag) == "number" and type(slot) == "number" and slotInfo(bag, slot) == id then
        return bag, slot
    end
    if not inBagFrame(owner) then return nil end
    for _, b in ipairs(ns.BAGS) do
        for s = 1, numSlots(b) do
            if slotInfo(b, s) == id and ns.DisenchantTarget(b, s) then return b, s end
        end
    end
    return nil
end

-- Disenchant with a key: which bag item the key would disenchant. The key presses a secure button
-- (UI.lua), since only a hardware event may cast.
ns.DISENCHANT = 13262
function ns.KnowsDisenchant()
    local id = ns.DISENCHANT
    if C_SpellBook and C_SpellBook.IsSpellKnown then return C_SpellBook.IsSpellKnown(id) and true or false end
    if IsPlayerSpell then return IsPlayerSpell(id) and true or false end
    return false
end

-- Green, blue and purple weapons and armour, never a shirt or tabard, and never what the junk
-- rules keep (protected items, equipment sets, tools, quest items).
function ns.CanDisenchant(it)
    if not it or J.Never(it) then return false end
    if it.classID ~= 2 and it.classID ~= 4 then return false end
    local q = it.quality or 1
    if q < 2 or q > 4 then return false end
    if it.equipLoc == "INVTYPE_BODY" or it.equipLoc == "INVTYPE_TABARD" then return false end
    return true
end

-- The item at a bag slot when the key would disenchant it now, else nil.
function ns.DisenchantTarget(bag, slot)
    if not (ns.db and ns.db.disenchant) or InCombatLockdown() then return nil end
    if type(bag) ~= "number" or type(slot) ~= "number" or bag < 0 or bag > 4 then return nil end
    if not ns.KnowsDisenchant() then return nil end
    local it = J.Item(bag, slot)
    if it and not it.locked and ns.CanDisenchant(it) then return it end
    return nil
end
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
        ns.db.bankNever = ns.db.bankNever or {}
        J.Attach(ns.db.junk)
        J.OnChange(function() if ns.Refresh then ns.Refresh(true) end end)
        J.InstallMarks({ JUNK_TIP = L.JUNK_TIP, ALWAYS_TIP = L.ALWAYS_TIP, MARKED = L.MARKED, UNMARKED = L.UNMARKED })
        self:RegisterEvent("UI_ERROR_MESSAGE")
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:RegisterEvent("MERCHANT_SHOW")
        self:RegisterEvent("MERCHANT_CLOSED")
        self:RegisterEvent("BAG_UPDATE_DELAYED")
        self:RegisterEvent("LOOT_CLOSED")
        self:RegisterEvent("PLAYER_LOGIN")
        self:RegisterEvent("BANKFRAME_OPENED")
        return
    end
    if event == "PLAYER_LOGIN" then
        if ns.UpdateCounter then ns.UpdateCounter() end
        if ns.InstallDisenchant then ns.InstallDisenchant() end
        return
    end
    if event == "BAG_UPDATE_DELAYED" then
        checkFull()
        if ns.UpdateCounter then ns.UpdateCounter() end
        if ns.CheckArmed then ns.CheckArmed() end
        if ns.UpdatePopup then ns.UpdatePopup() end
        if ns.Refresh then ns.Refresh(true) end
        if ns.RefreshBank then ns.RefreshBank() end
        return
    end
    if event == "BANKFRAME_OPENED" then
        if ns.BankOpened then ns.BankOpened() end
        return
    end
    if event == "LOOT_CLOSED" then
        if ns.LootClosed then ns.LootClosed() end
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
        -- Still out of lockdown here: the disenchant key lets go before the fight.
        if ns.HideDisenchant then ns.HideDisenchant() end
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
        wipe(ns.db.bankNever)
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
    disenchant = "Interface\\Icons\\INV_Enchant_Disenchant",
    bank = "Interface\\Minimap\\Tracking\\Banker",
}

local function option(key, label)
    return { label = label, icon = ns.OPT_ICON[key], tip = ns.L["TIP_" .. key], get = function() return ns.db ~= nil and ns.db[key] == true end,
             set = function(on)
                 if not ns.db then return end
                 ns.db[key] = on and true or false
                 if key == "counter" and ns.UpdateCounter then ns.UpdateCounter() end
                 if key == "disenchant" and not on and ns.HideDisenchant then ns.HideDisenchant() end
                 if key == "bank" and ns.RefreshBank then ns.RefreshBank(on) end
             end }
end

-- With the hub: its row and button there; alone: its own minimap button (Skin.lua).
do
    local register = GulliToolkit and GulliToolkit.Register or function(info) ns.alone = info end
    register({
        options = { option("unusable", ns.L.OPT_UNUSABLE), option("counter", ns.L.OPT_COUNTER),
                    option("popup", ns.L.OPT_POPUP), option("disenchant", ns.L.OPT_DISENCHANT),
                    option("bank", ns.L.OPT_BANK) },
        -- the hub's Tweaks page: the same saved key as the window
        tweaks = { (function()
            local o = option("bank", ns.L.OPT_BANK)
            o.key, o.group, o.desc, o.tip = "bank", "loot", ns.L.TIP_bank, nil
            return o
        end)() },
        key = "BagSpace",
        icon = "Interface\\AddOns\\Gulli-BagSpace\\icon",
        slash = "/gbs",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        summary = function()
            if not ns.db then return nil end
            local free = ns.Space()
            -- the hub's Ready card shows the free slots too: the tile gives way to it
            return ns.L.HUB_SUMMARY:format(free), "Interface\\Icons\\INV_Misc_Bag_10", { ready = "BAGS" }
        end,
        reset = function()
            if not ns.db then return end
            for k, v in pairs(ns.DEFAULTS) do ns.db[k] = v end
            if ns.UpdateCounter then ns.UpdateCounter() end
            if ns.HideDisenchant then ns.HideDisenchant() end
            if ns.RefreshBank then ns.RefreshBank() end
            if ns.Refresh then ns.Refresh(true) end
        end,
    })
end
