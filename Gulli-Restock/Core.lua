-- Keeps reagents, ammo, food and water at the amount the player sets for each character.
-- At a vendor it shows what it would buy and what it costs; only OK buys. At the bank it takes
-- what is missing out of the bank and (a switch) puts the surplus in. Lists come in sets
-- (levelling, raid, ...), and an entry can be "the best water for my level" instead of one item.

local ADDON, ns = ...
local L = ns.L

-- Class reagents: item, amount to keep, level the spell that needs it comes at.
-- A later entry with the same group replaces an earlier one once the level is reached.
ns.PRESETS = {
    MAGE = { { 17031, 10, 20 }, { 17032, 10, 40 }, { 17020, 20, 56 } },
    PRIEST = { { 17028, 20, 48, "candle" }, { 17029, 20, 56, "candle" } },
    PALADIN = { { 17033, 5, 30 }, { 21177, 40, 52 } },
    DRUID = { { 17034, 5, 20, "seed" }, { 17035, 5, 30, "seed" }, { 17036, 5, 40, "seed" },
              { 17037, 5, 50, "seed" }, { 17038, 5, 60, "seed" },
              { 17021, 20, 50, "gift" }, { 17026, 20, 60, "gift" } },
    SHAMAN = { { 17030, 5, 30 } },
    WARLOCK = { { 5565, 5, 50 }, { 16583, 2, 60 } },
    ROGUE = { { 5140, 10, 22 } },
}

-- "Best for my level" entries: vendor items by the level they need. The entry counts every
-- item of its kind in the bags (old water still counts), and buys the best one the open
-- vendor sells for the character's level. Keys in a list are "best:<kind>".
ns.BEST = {
    water = { { 159, 1 }, { 1179, 5 }, { 1205, 15 }, { 1708, 25 }, { 1645, 35 }, { 8766, 45 } },
    food = { { 4540, 1 }, { 4541, 5 }, { 4542, 15 }, { 4544, 25 }, { 4601, 35 }, { 8950, 45 },     -- bread
             { 117, 1 }, { 2287, 5 }, { 3770, 15 }, { 3771, 25 }, { 4599, 35 }, { 8952, 45 },      -- meat
             { 2070, 1 }, { 414, 5 }, { 422, 15 }, { 1707, 25 }, { 3927, 35 }, { 8932, 45 },       -- cheese
             { 4536, 1 }, { 4537, 5 }, { 4538, 15 }, { 4539, 25 }, { 4602, 35 }, { 8953, 45 },     -- fruit
             { 787, 1 }, { 4592, 5 }, { 4593, 15 }, { 4594, 25 }, { 8957, 45 },                    -- fish
             { 4604, 1 }, { 4605, 5 }, { 4606, 15 }, { 4607, 25 }, { 4608, 35 }, { 8948, 45 } },   -- fungus
    arrow = { { 2512, 1 }, { 2515, 10 }, { 3030, 25 }, { 11285, 40 } },
    bullet = { { 2516, 1 }, { 2519, 10 }, { 3033, 25 }, { 11284, 40 } },
}
ns.BEST_ORDER = { "water", "food", "arrow", "bullet" }

local LOW_SHARE = 0.25 -- warn when an item drops to a quarter of what is kept
local EARLY_HOURS = 2  -- with the forecast on, warn when the stock lasts less than this
local USE_WINDOW = 5 * 3600 -- the forecast looks at the last five hours of play
local CONSUMABLE, REAGENT, PROJECTILE, MISC = 0, 5, 6, 15

-- Game API wrappers.
local C = C_Container or {}
local function count(id, bank) return ((C_Item and C_Item.GetItemCount) or GetItemCount)(id, bank) or 0 end
local function itemInfo(id)
    local name, _, _, _, minLevel, _, _, stack, _, _, _, classID, subclassID =
        ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(id)
    return name, minLevel or 0, stack or 1, classID, subclassID
end
function ns.ItemName(id)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not name and GetItemInfo then name = GetItemInfo(id) end
    return name or ("#" .. id)
end
function ns.ItemIcon(id)
    return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id))
        or "Interface\\Icons\\INV_Misc_QuestionMark"
end
local function merchantCount() return GetMerchantNumItems and GetMerchantNumItems() or 0 end
local function merchantItem(i)
    local id = GetMerchantItemID and GetMerchantItemID(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local t = C_MerchantFrame.GetItemInfo(i)
        if not t then return nil end
        return id, t.price or 0, t.stackCount or 1, t.numAvailable or -1, t.hasExtendedCost
    end
    local _, _, price, stack, available, _, _, extended = GetMerchantItemInfo(i)
    return id, price or 0, stack or 1, available or -1, extended
end
local function maxStack(i) return GetMerchantItemMaxStack and GetMerchantItemMaxStack(i) or 20 end
local function money() return GetMoney and GetMoney() or 0 end
local function numSlots(bag) return (C.GetContainerNumSlots or GetContainerNumSlots)(bag) or 0 end
local function freeSlots(bag)
    local free, family = (C.GetContainerNumFreeSlots or GetContainerNumFreeSlots)(bag)
    return free or 0, family or 0
end
local function slotInfo(bag, slot)
    if C.GetContainerItemInfo then
        local i = C.GetContainerItemInfo(bag, slot)
        if not i then return nil end
        return i.itemID, i.stackCount or 1, i.isLocked
    end
    local _, n, locked, _, _, _, _, _, _, id = GetContainerItemInfo(bag, slot)
    return id, n or 1, locked
end
local function useItem(bag, slot) (C.UseContainerItem or UseContainerItem)(bag, slot) end
local function split(bag, slot, n) (C.SplitContainerItem or SplitContainerItem)(bag, slot, n) end
local function pickup(bag, slot) (C.PickupContainerItem or PickupContainerItem)(bag, slot) end
local function say(msg) print("|cff9ad0ffGulli Restock|r: " .. msg) end
local function notify(msg) if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("Restock", msg) end end

ns.BAGS = { 0, 1, 2, 3, 4 }
-- The bank: its own slots (-1) and the bank bags, which sit after the bags the player wears.
function ns.BankBags()
    local out = { BANK_CONTAINER or -1 }
    local first = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) + 1
    for b = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do out[#out + 1] = b end
    return out
end

-- Entries ------------------------------------------------------------------------------------

local function isBest(key) return type(key) == "string" and key:match("^best:(%a+)$") end

-- How many the bags hold of an entry: one item, or every item of a "best" kind.
function ns.Have(key, bank)
    local kind = isBest(key)
    if not kind then return count(key, bank) end
    local n = 0
    for _, e in ipairs(ns.BEST[kind] or {}) do n = n + count(e[1], bank) end
    return n
end

-- The item a "best" kind buys for this character, from `offer` (id -> true) when given.
function ns.BestItem(kind, offer)
    local level = UnitLevel("player") or 1
    local best
    for _, e in ipairs(ns.BEST[kind] or {}) do
        if e[2] <= level and (not offer or offer[e[1]]) and (not best or e[2] > best[2]) then best = e end
    end
    return best and best[1]
end

function ns.EntryName(key)
    local kind = isBest(key)
    if kind then return L["BEST_" .. kind:upper()] end
    return ns.ItemName(key)
end

function ns.EntryIcon(key)
    local kind = isBest(key)
    if kind then return ns.ItemIcon(ns.BestItem(kind) or ns.BEST[kind][1][1]) end
    return ns.ItemIcon(key)
end

-- The size of one step of the amount: the item's stack, 20 for food, water and ammo.
function ns.StepOf(key)
    if isBest(key) then return 20 end
    local _, _, stack = itemInfo(key)
    return math.max(1, math.min(stack or 1, 20))
end

-- The keep list of this character: { { id, want, have, bank, best } } by name.
function ns.List()
    local out = {}
    for id, want in pairs(ns.char.list) do
        local have = ns.Have(id)
        out[#out + 1] = { id = id, want = want, have = have, bank = ns.Have(id, true) - have, best = isBest(id) and true or false,
                          hours = ns.Lasts(id) }
    end
    table.sort(out, function(a, b) return ns.EntryName(a.id) < ns.EntryName(b.id) end)
    return out
end

function ns.Set(id, want)
    if not isBest(id) then id = tonumber(id) end
    if not id then return end
    want = math.floor(tonumber(want) or 0)
    ns.char.list[id] = want > 0 and want or nil
    ns.char.warned[id] = nil
    if ns.Refresh then ns.Refresh() end
end

-- Adds an item from a link, an id or a kind word (water, food, arrow, bullet).
function ns.AddFromText(text, amount)
    text = strtrim(text or "")
    local id = tonumber(text) or tonumber(text:match("item:(%d+)"))
    local key = id
    if not id then
        local word = text:lower()
        for _, kind in ipairs(ns.BEST_ORDER) do if word == kind then key = "best:" .. kind end end
    end
    if not key then return nil end
    ns.Set(key, amount or ns.char.list[key] or (isBest(key) and 20 or ns.StepOf(key)))
    return key
end

-- Adds the reagents of the player's class for its level. Returns how many were added.
function ns.AddPreset()
    local _, class = UnitClass("player")
    local level = UnitLevel("player")
    local best = {}
    local added = 0
    for _, p in ipairs(ns.PRESETS[class] or {}) do
        if level >= p[3] then
            if p[4] then best[p[4]] = p else
                if not ns.char.list[p[1]] then ns.char.list[p[1]] = p[2]; added = added + 1 end
            end
        end
    end
    for _, p in pairs(best) do
        if not ns.char.list[p[1]] then ns.char.list[p[1]] = p[2]; added = added + 1 end
    end
    if ns.Refresh then ns.Refresh() end
    return added
end

-- Sets ---------------------------------------------------------------------------------------

function ns.SetNames()
    local out = {}
    for name in pairs(ns.char.sets) do out[#out + 1] = name end
    table.sort(out)
    return out
end

function ns.UseSet(name)
    if not ns.char.sets[name] then return end
    ns.char.set = name
    ns.char.list = ns.char.sets[name]
    if ns.Refresh then ns.Refresh() end
end

-- A new set, a copy of the current one, named "<Set> 2", "<Set> 3", ...
function ns.NewSet()
    local n = 2
    while ns.char.sets[L.SET_NAME:format(n)] do n = n + 1 end
    local name = L.SET_NAME:format(n)
    local copy = {}
    for k, v in pairs(ns.char.list) do copy[k] = v end
    ns.char.sets[name] = copy
    ns.UseSet(name)
    return name
end

function ns.DeleteSet()
    local names = ns.SetNames()
    if #names < 2 then return false end
    ns.char.sets[ns.char.set] = nil
    names = ns.SetNames()
    ns.UseSet(names[1])
    return true
end

function ns.NextSet()
    local names = ns.SetNames()
    for i, name in ipairs(names) do
        if name == ns.char.set then ns.UseSet(names[i % #names + 1]) return names[i % #names + 1] end
    end
end

-- Vendor -------------------------------------------------------------------------------------

-- Room in the bags for `id`: free slots times the stack size, plus the room in its partial
-- stacks. Ammo also fits a quiver or ammo pouch. Also returns the partial room, the free slots
-- and the stack size, so a plan can share the free slots between items.
function ns.Room(id)
    local _, _, stack, classID = itemInfo(id)
    stack = math.max(1, stack or 1)
    local free, partial = 0, 0
    for _, bag in ipairs(ns.BAGS) do
        local n, family = freeSlots(bag)
        if family == 0 or classID == PROJECTILE then free = free + n end
        for slot = 1, numSlots(bag) do
            local sid, c = slotInfo(bag, slot)
            if sid == id and c < stack then partial = partial + stack - c end
        end
    end
    return partial + free * stack, partial, free, stack
end

-- The vendor's items: { [i] = { id, price, stack, available } } without token prices, and
-- id -> index.
local function vendorItems()
    local list, index = {}, {}
    for i = 1, merchantCount() do
        local id, price, stack, available, extended = merchantItem(i)
        if id and not extended and not index[id] then
            list[#list + 1] = { i = i, id = id, price = price, stack = math.max(1, stack), available = available }
            index[id] = #list
        end
    end
    return list, index
end

-- What to buy from the open vendor: { { index, id, key, buy, cost, purchases, stack, price, cut } }
-- and the total. Purchases stop at the room in the bags and at the gold to keep (`reserve`);
-- `cut` says why an entry got less ("bags", "money").
function ns.Plan()
    local plan, total = {}, 0
    local list, index = vendorItems()
    local offer = {}
    for _, v in ipairs(list) do offer[v.id] = true end
    local budget = money() - (ns.db.reserve or 0) * 10000
    local usedSlots = 0
    local keys = {}
    for key in pairs(ns.char.list) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        local want = ns.char.list[key]
        local kind = isBest(key)
        local id = kind and ns.BestItem(kind, offer) or key
        local v = id and index[id] and list[index[id]]
        if v then
            local need = want - ns.Have(key)
            if need > 0 then
                local purchases = math.ceil(need / v.stack)
                if v.available >= 0 then purchases = math.min(purchases, v.available) end
                local cut
                local _, partial, free, size = ns.Room(id)
                local fit = math.floor((partial + math.max(0, free - usedSlots) * size) / v.stack)
                if purchases > fit then purchases, cut = fit, "bags" end
                if v.price > 0 and purchases * v.price > budget then
                    purchases, cut = math.max(0, math.floor(budget / v.price)), "money"
                end
                local e = { index = v.i, id = id, key = key, buy = purchases * v.stack, cost = purchases * v.price,
                            purchases = purchases, stack = v.stack, price = v.price, cut = cut, on = true }
                usedSlots = usedSlots + math.max(0, math.ceil((purchases * v.stack - partial) / size))
                if purchases > 0 or cut then
                    plan[#plan + 1] = e
                    total = total + e.cost
                    budget = budget - e.cost
                end
            end
        end
    end
    return plan, total
end

-- Changes how many purchases one entry of a plan makes (the preview's -/+).
function ns.SetPurchases(e, n)
    e.purchases = math.max(0, n)
    e.buy = e.purchases * e.stack
    e.cost = e.purchases * e.price
end

function ns.PlanTotal(plan)
    local total = 0
    for _, e in ipairs(plan) do if e.on then total = total + e.cost end end
    return total
end

-- Buys the plan. Runs from the OK click. Stops before an item the money no longer covers.
function ns.Buy(plan)
    local left = money()
    local bought = 0
    for _, e in ipairs(plan) do
        if e.on ~= false and e.purchases > 0 then
            if e.cost > left then
                say(L.NO_MONEY:format(ns.ItemName(e.id)))
                break
            end
            if e.stack > 1 then
                -- Sold in fixed stacks (arrows, some food): one purchase per call.
                for _ = 1, e.purchases do BuyMerchantItem(e.index) end
            else
                local n, max = e.purchases, maxStack(e.index)
                while n > 0 do
                    local k = math.min(n, max)
                    BuyMerchantItem(e.index, k)
                    n = n - k
                end
            end
            left = left - e.cost
            bought = bought + 1
            ns.char.warned[e.key or e.id] = nil
        end
    end
    return bought
end

-- Items of this vendor worth keeping stocked (food, drink, reagents, ammo) that are not on the
-- list yet: { { id, price, stack } }.
function ns.VendorOffers()
    local out = {}
    local covered = {}
    for key in pairs(ns.char.list) do
        local kind = isBest(key)
        if kind then for _, e in ipairs(ns.BEST[kind]) do covered[e[1]] = true end end
    end
    for _, v in ipairs((vendorItems())) do
        local _, _, _, classID, subclassID = itemInfo(v.id)
        local useful = classID == CONSUMABLE or classID == REAGENT or classID == PROJECTILE
            or (classID == MISC and subclassID == 1)
        if useful and not ns.char.list[v.id] and not covered[v.id] then out[#out + 1] = v end
    end
    return out
end

-- Buys `n` of one vendor item (the quick buy window): `n` units, in purchases of its stack.
function ns.QuickMax(i)
    local id, price, stack, available = merchantItem(i)
    if not id then return 0 end
    stack = math.max(1, stack)
    local n = math.floor(ns.Room(id) / stack)
    if price > 0 then n = math.min(n, math.floor(money() / price)) end
    if available >= 0 then n = math.min(n, available) end
    return math.max(0, n) * stack, price, stack
end

function ns.QuickBuy(i, units)
    local id, price, stack = merchantItem(i)
    if not id or units <= 0 then return 0 end
    stack = math.max(1, stack)
    local purchases = math.ceil(units / stack)
    ns.Buy({ { index = i, id = id, purchases = purchases, stack = stack, cost = purchases * price, price = price, on = true } })
    return purchases * stack
end

-- Bank ---------------------------------------------------------------------------------------

-- What to move at the bank: { { from = { bag, slot }, n, whole, id, dir = "take"|"put" } } and
-- a summary { { key, take, put } }. Takes from the bank what the bags miss; with `deposit`
-- puts what is over the amount into the bank.
function ns.BankPlan()
    local moves, sum = {}, {}
    for key, want in pairs(ns.char.list) do
        local have = ns.Have(key)
        local bank = ns.Have(key, true) - have
        local ids = {}
        local kind = isBest(key)
        if kind then for _, e in ipairs(ns.BEST[kind]) do ids[e[1]] = true end else ids[key] = true end
        local take = math.max(0, math.min(want - have, bank))
        local put = ns.db.deposit and math.max(0, have - want) or 0
        if take > 0 or put > 0 then sum[#sum + 1] = { key = key, take = take, put = put } end
        local function collect(bags, left, dir)
            local stacks = {}
            for _, bag in ipairs(bags) do
                for slot = 1, numSlots(bag) do
                    local id, n, locked = slotInfo(bag, slot)
                    if id and ids[id] and not locked then stacks[#stacks + 1] = { bag = bag, slot = slot, n = n, id = id } end
                end
            end
            -- Whole stacks first, the smallest last, so a split happens at most once.
            table.sort(stacks, function(a, b) return a.n > b.n end)
            for _, s in ipairs(stacks) do
                if left <= 0 then break end
                local n = math.min(left, s.n)
                moves[#moves + 1] = { from = { s.bag, s.slot }, n = n, whole = n == s.n, id = s.id, dir = dir }
                left = left - n
            end
        end
        if take > 0 then collect(ns.BankBags(), take, "take") end
        if put > 0 then collect(ns.BAGS, put, "put") end
    end
    return moves, sum
end

-- A free slot in `bags` (normal bags only for the player's bags).
local function freeSlot(bags)
    for _, bag in ipairs(bags) do
        local _, family = freeSlots(bag)
        if family == 0 then
            for slot = 1, numSlots(bag) do
                if not slotInfo(bag, slot) then return bag, slot end
            end
        end
    end
end

-- One move: a whole stack goes with a right-click (bank open), a part is split onto a free
-- slot on the other side.
function ns.Move(m)
    local id, n = slotInfo(m.from[1], m.from[2])
    if id ~= m.id then return false end
    if m.whole or m.n >= n then
        useItem(m.from[1], m.from[2])
        return true
    end
    local bag, slot = freeSlot(m.dir == "take" and ns.BAGS or ns.BankBags())
    if not bag then return false end
    ClearCursor()
    split(m.from[1], m.from[2], m.n)
    pickup(bag, slot)
    if GetCursorInfo and GetCursorInfo() then ClearCursor() end
    return true
end

-- Runs the bank plan from the OK click, one move per short step.
local queue = {}
local function bankStep()
    local m = table.remove(queue, 1)
    if not m then if ns.Refresh then ns.Refresh() end return end
    if ns.atBank and not InCombatLockdown() then ns.Move(m) end
    C_Timer.After(0.3, bankStep)
end
function ns.RunBank(moves)
    local idle = #queue == 0
    for _, m in ipairs(moves) do queue[#queue + 1] = m end
    if idle and #queue > 0 then bankStep() end
    return #moves
end

-- Low stock and the forecast ------------------------------------------------------------------

-- Use per item: amounts that left the bags away from a vendor, the bank and the mailbox, with
-- the play time when they left. use[key] = { { played, n } }.
local last = {}
function ns.TrackUse()
    if ns.atVendor or ns.atBank or ns.atMail then
        for key in pairs(ns.char.list) do last[key] = ns.Have(key) end
        return
    end
    for key in pairs(ns.char.list) do
        local have = ns.Have(key)
        -- The first entry marks when watching began, so the rate has a real time span.
        if not ns.char.use[key] then ns.char.use[key] = { { ns.Played(), 0 } } end
        if last[key] and have < last[key] then
            local u = ns.char.use[key]
            u[#u + 1] = { ns.Played(), last[key] - have }
            while #u > 200 do table.remove(u, 1) end
        end
        last[key] = have
    end
end

-- Seconds played by this character, counted by the addon.
local loginAt = GetTime and GetTime() or 0
function ns.Played() return (ns.char and ns.char.played or 0) + ((GetTime and GetTime() or 0) - loginAt) end

-- Hours the stock of an entry lasts at the use of the last hours of play, or nil.
function ns.Lasts(key)
    local u = ns.char and ns.char.use[key]
    if not u or #u == 0 then return nil end
    local now = ns.Played()
    local used = 0
    for _, e in ipairs(u) do
        if now - e[1] <= USE_WINDOW then used = used + e[2] end
    end
    if used == 0 then return nil end
    local span = math.max(math.min(now - u[1][1], USE_WINDOW), 600)
    local perHour = used / (span / 3600)
    return ns.Have(key) / perHour
end

-- Prints one warning when an item drops low (or, with the forecast, lasts less than
-- EARLY_HOURS); again only after it was restocked.
function ns.CheckLow()
    local low = {}
    for id, want in pairs(ns.char.list) do
        local have = ns.Have(id)
        local hours = ns.db.forecast and ns.Lasts(id)
        if have <= math.floor(want * LOW_SHARE) or (hours and hours < EARLY_HOURS) then
            if not ns.char.warned[id] then
                ns.char.warned[id] = true
                low[#low + 1] = ns.EntryName(id) .. " (" .. have .. ")"
            end
        elseif have >= want then
            ns.char.warned[id] = nil
        end
    end
    if #low == 0 then return nil end
    table.sort(low)
    local msg = L.LOW:format(table.concat(low, ", "))
    say(msg)
    notify(msg)
    return msg
end

-- What the list misses, for Gulli DungeonPrep's checklist: { { name, have, want } }.
function ns.Missing()
    local out = {}
    for _, e in ipairs(ns.List()) do
        if e.have < e.want then out[#out + 1] = { name = ns.EntryName(e.id), have = e.have, want = e.want } end
    end
    return out
end
GulliRestock = GulliRestock or {}
GulliRestock.Missing = function() return ns.char and ns.Missing() or {} end

-- Events -------------------------------------------------------------------------------------

ns.DEFAULTS = { auto = false, deposit = false, reserve = 0, forecast = true }

local pending = false
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliRestockDB = GulliRestockDB or {}
        ns.db = GulliRestockDB
        for k, v in pairs(ns.DEFAULTS) do if ns.db[k] == nil then ns.db[k] = v end end
        GulliRestockCharDB = GulliRestockCharDB or {}
        ns.char = GulliRestockCharDB
        -- Lists come in sets; an older save's one list becomes the first set.
        if not ns.char.sets then
            ns.char.sets = { [L.SET_FIRST] = ns.char.list or {} }
            ns.char.set = L.SET_FIRST
        end
        if not ns.char.sets[ns.char.set or ""] then ns.char.set = ns.SetNames()[1] end
        ns.char.list = ns.char.sets[ns.char.set]
        ns.char.warned = ns.char.warned or {}
        ns.char.use = ns.char.use or {}
        ns.char.played = ns.char.played or 0
        self:RegisterEvent("MERCHANT_SHOW")
        self:RegisterEvent("MERCHANT_CLOSED")
        self:RegisterEvent("BANKFRAME_OPENED")
        self:RegisterEvent("BANKFRAME_CLOSED")
        self:RegisterEvent("MAIL_SHOW")
        self:RegisterEvent("MAIL_CLOSED")
        self:RegisterEvent("BAG_UPDATE_DELAYED")
        self:RegisterEvent("PLAYER_LOGOUT")
        if MerchantItemButton_OnModifiedClick then
            hooksecurefunc("MerchantItemButton_OnModifiedClick", function(btn)
                if IsAltKeyDown and IsAltKeyDown() and ns.ShowQuick then ns.ShowQuick(btn and btn.GetID and btn:GetID()) end
            end)
        end
        return
    end
    if event == "MERCHANT_SHOW" then
        ns.atVendor = true
        if ns.Refresh then ns.Refresh() end
        -- Shift skips this visit.
        if IsShiftKeyDown and IsShiftKeyDown() then return end
        local plan, total = ns.Plan()
        local buyable = 0
        for _, e in ipairs(plan) do buyable = buyable + e.purchases end
        if buyable == 0 and #plan == 0 then return end
        if ns.db.auto and buyable > 0 then
            ns.Buy(plan)
        elseif ns.ShowPlan then
            ns.ShowPlan(plan, total)
        end
    elseif event == "MERCHANT_CLOSED" then
        ns.atVendor = false
        if ns.HidePlan then ns.HidePlan() end
        if ns.HideQuick then ns.HideQuick() end
        if ns.Refresh then ns.Refresh() end
    elseif event == "BANKFRAME_OPENED" then
        ns.atBank = true
        if IsShiftKeyDown and IsShiftKeyDown() then return end
        local moves, sum = ns.BankPlan()
        if #moves > 0 and ns.ShowBank then ns.ShowBank(moves, sum) end
    elseif event == "BANKFRAME_CLOSED" then
        ns.atBank = false
        if ns.HideBank then ns.HideBank() end
    elseif event == "MAIL_SHOW" then
        ns.atMail = true
    elseif event == "MAIL_CLOSED" then
        ns.atMail = false
    elseif event == "PLAYER_LOGOUT" then
        ns.char.played = ns.Played()
    elseif event == "BAG_UPDATE_DELAYED" then
        ns.TrackUse()
        if pending then return end
        pending = true
        C_Timer.After(1, function()
            pending = false
            ns.CheckLow()
            if ns.Refresh then ns.Refresh() end
        end)
    end
end)

SLASH_GULLIRESTOCK1 = "/grs"
SLASH_GULLIRESTOCK2 = "/gullirestock"
SlashCmdList.GULLIRESTOCK = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    if (cmd or ""):lower() == "add" and rest ~= "" then
        -- /grs add <link|id|water|food|arrow|bullet> [amount]
        local what, n = rest:match("^(.-)%s+(%d+)$")
        local key = ns.AddFromText(what or rest, tonumber(n))
        if key then say(L.ADDED:format(ns.EntryName(key), ns.char.list[key])) else say(L.ADD_HELP) end
        return
    end
    if (cmd or ""):lower() == "set" then
        local name = ns.NextSet()
        if name then say(L.SET_NOW:format(name)) end
        return
    end
    ns.Toggle()
end

function GulliRestock_Toggle() ns.Toggle() end

ns.OPT_ICON = {
    auto = "Interface\\Icons\\INV_Misc_Bag_08",
    deposit = "Interface\\Minimap\\Tracking\\Banker",
    forecast = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    reserve = "Interface\\Icons\\INV_Misc_Coin_02",
}

local function option(key, label)
    return { label = label, icon = ns.OPT_ICON[key], get = function() return ns.db ~= nil and ns.db[key] == true end,
             set = function(on) if ns.db then ns.db[key] = on and true or false end end }
end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "Restock",
        icon = "Interface\\AddOns\\Gulli-Restock\\icon",
        slash = "/grs",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        options = { option("auto", ns.L.AUTO), option("deposit", ns.L.OPT_DEPOSIT), option("forecast", ns.L.OPT_FORECAST) },
    })
end
