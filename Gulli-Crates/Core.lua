-- Waylaid Crates: finds the cheapest bundle for each crate in the bags, from the bags, the bank
-- and Auctionator's prices, and buys what is missing at the auction house, one click a purchase.
-- The rules (ns.Bundles, ns.Plan, ns.ShoppingList) are plain Lua; the game calls go through the
-- wrappers at the top.

local ADDON, ns = ...
local L = ns.L

local CALLER = "Gulli-Crates"
local QUOTE_WAIT = 6 -- seconds the auction house has to answer a price request

ns.DEFAULTS = { auto = true, bank = true }

local function say(msg) print("|cff9ad0ffCrates|r: " .. msg) end
local function notify(msg) if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("Crates", msg) end end
ns.Say = say

-- ---------- game wrappers ----------

local I = C_Item or {}
local function itemName(id)
    local n = I.GetItemNameByID and I.GetItemNameByID(id)
    if not n and GetItemInfo then n = GetItemInfo(id) end
    return n
end
ns.ItemName = itemName
function ns.ItemIcon(id)
    return (I.GetItemIconByID and I.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id))
        or "Interface\\Icons\\INV_Misc_QuestionMark"
end
local function itemCount(id, bank)
    local f = I.GetItemCount or GetItemCount
    return f and (f(id, bank) or 0) or 0
end
local function requestItem(id)
    if I.RequestLoadItemDataByID then pcall(I.RequestLoadItemDataByID, id) end
end
local function numSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end
local function slotItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local i = C_Container.GetContainerItemInfo(bag, slot)
        return i and i.itemID, i and i.stackCount
    end
    if GetContainerItemInfo then
        local _, count, _, _, _, _, link = GetContainerItemInfo(bag, slot)
        return link and tonumber(link:match("item:(%d+)")), count
    end
end
-- The left lines of an item's tooltip, or nil when the client cannot give them.
local function tooltipLines(id)
    local T = C_TooltipInfo
    if not T or not T.GetItemByID then return nil end
    local ok, data = pcall(T.GetItemByID, id)
    if not ok or not data or not data.lines then return nil end
    local out = {}
    for _, line in ipairs(data.lines) do out[#out + 1] = line.leftText or "" end
    return out
end
ns.TooltipLines = tooltipLines

local function auctionator()
    return Auctionator and Auctionator.API and Auctionator.API.v1
end
function ns.HasAuctionator() return auctionator() ~= nil end
-- Auctionator's lowest price of one (copper), or nil.
function ns.AuctionPrice(id)
    local api = auctionator()
    if not api or not api.GetAuctionPriceByItemID then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemID, CALLER, id)
    if not ok or type(price) ~= "number" or price <= 0 then return nil end
    return price
end

-- ---------- the crates and their bundles ----------

-- Every item the table knows as a bundle item, by its name in the client's language, so a
-- tooltip line ("- 10 Wintersbite") finds its item.
local byName
local function nameIndex()
    if byName then return byName end
    local idx, missing = {}, false
    for _, c in pairs(ns.CRATES) do
        for _, b in ipairs(c[2]) do
            local n = itemName(b[1])
            if n then idx[n:lower()] = b[1] else missing = true; requestItem(b[1]) end
        end
    end
    if not missing then byName = idx end -- keep it only once every name has loaded
    return idx
end
function ns.ResetNames() byName = nil end

-- The bundles a crate's tooltip lists: { { id, n }, ... }, or nil when a line names an item
-- the addon does not know (or the tooltip has no such lines).
function ns.ReadBundles(id)
    local lines = tooltipLines(id)
    if not lines then return nil end
    local idx, out = nameIndex(), {}
    for _, text in ipairs(lines) do
        for line in tostring(text):gmatch("[^\n]+") do
            local n, name = line:match("^%s*%-%s*(%d+)%s*[xX×]?%s+(.-)%s*$")
            if n and name and name ~= "" then
                local item = idx[name:lower()]
                if not item then return nil end
                out[#out + 1] = { item, tonumber(n) }
            end
        end
    end
    return #out > 0 and out or nil
end

-- What fills a crate: its tooltip when the game gives a full one, else the table.
local cache = {}
function ns.Bundles(id)
    if cache[id] then return cache[id] end
    local list = ns.ReadBundles(id)
    if list then cache[id] = list; return list end
    local c = ns.CRATES[id]
    return c and c[2] or nil
end
function ns.ClearCache() cache = {} end

local BAGS = { 0, 1, 2, 3, 4, 5 }

-- The crates in the bags, in bag order: { { id, count, name, icon } }. A bag item the table
-- lacks counts as a crate when its tooltip lists bundles of known items.
function ns.Crates()
    local seen, out = {}, {}
    for _, bag in ipairs(BAGS) do
        for slot = 1, numSlots(bag) do
            local id, n = slotItem(bag, slot)
            if id and not seen[id] then
                local crate = ns.CRATES[id] ~= nil
                if not crate and not ns.notCrate[id] then
                    crate = ns.ReadBundles(id) ~= nil
                    if not crate then ns.notCrate[id] = true end
                end
                if crate then
                    seen[id] = { id = id, count = 0, name = itemName(id) or ("item:" .. id), icon = ns.ItemIcon(id) }
                    out[#out + 1] = seen[id]
                end
            end
            if id and seen[id] then seen[id].count = seen[id].count + (n or 1) end
        end
    end
    return out
end
ns.notCrate = {}

-- How many of an item are in the bags and in the bank.
function ns.Stock(id)
    local bags = itemCount(id, false)
    local all = itemCount(id, true)
    return bags, math.max(0, all - bags)
end

-- ---------- the plan (no game calls) ----------

-- picks: { { id = crate id, count = n } }; bundles(id) -> list; stock(item) -> bags, bank;
-- price(item) -> copper or nil; useBank: bank items count too.
-- Each crate copy gets the bundle that costs least to complete; items the bags and the bank
-- hold cost nothing and are used once. The cheapest crate-and-bundle pair of all is settled
-- first, so a stock that completes one crate is not spent half on another.
-- Returns { crates = { { crate, k, bundle, rows, cost, buy, others } }, total, unpriced }.
function ns.Plan(picks, bundles, stock, price, useBank)
    local pool = {}
    local function have(id)
        if not pool[id] then
            local b, k = stock(id)
            pool[id] = { b or 0, useBank and (k or 0) or 0 }
        end
        return pool[id]
    end
    -- the cost of filling with this bundle now: rows and total (nil when an item has no price)
    local function cost(bundle)
        local rows, total, buy = {}, 0, 0
        for _, b in ipairs(bundle) do
            local id, n = b[1], b[2]
            local h = have(id)
            local fromBags = math.min(n, h[1])
            local fromBank = math.min(n - fromBags, h[2])
            local need = n - fromBags - fromBank
            local unit = need > 0 and price(id) or nil
            if need > 0 and not unit then return nil, rows end
            local c = need * (unit or 0)
            rows[#rows + 1] = { id = id, n = n, bags = fromBags, bank = fromBank, buy = need, unit = unit, cost = c }
            total, buy = total + c, buy + need
        end
        return total, rows, buy
    end

    local open = {}
    for _, p in ipairs(picks) do
        local list = bundles(p.id)
        if list then for k = 1, p.count or 1 do open[#open + 1] = { crate = p.id, k = k, list = list } end end
    end
    local result = { crates = {}, total = 0, unpriced = {} }
    local order = {}
    while #open > 0 do
        local best, bestI, bestB
        for i, o in ipairs(open) do
            for bi, bundle in ipairs(o.list) do
                local total, rows, buy = cost({ bundle })
                if total and (not best or total < best.cost or (total == best.cost and buy < best.buy)) then
                    best, bestI, bestB = { cost = total, rows = rows, buy = buy }, i, bi
                end
            end
        end
        if not best then
            -- nothing left can be priced: list those crates as open with what is missing
            for _, o in ipairs(open) do
                local e = { crate = o.crate, k = o.k, none = true, others = {} }
                for _, bundle in ipairs(o.list) do
                    if price(bundle[1]) == nil then result.unpriced[bundle[1]] = true end
                    e.others[#e.others + 1] = { bundle = bundle }
                end
                order[#order + 1] = e
            end
            break
        end
        local o = table.remove(open, bestI)
        local bundle = o.list[bestB]
        for _, r in ipairs(best.rows) do
            local h = have(r.id)
            h[1], h[2] = h[1] - r.bags, h[2] - r.bank
        end
        local e = { crate = o.crate, k = o.k, bundle = bundle, rows = best.rows, cost = best.cost, buy = best.buy, others = {} }
        result.total = result.total + best.cost
        order[#order + 1] = e
    end
    -- the other bundles of each crate, priced against what is left, cheapest first
    for _, e in ipairs(order) do
        if not e.none then
            for _, bundle in ipairs(bundles(e.crate)) do
                if bundle ~= e.bundle then
                    local c = cost({ bundle })
                    e.others[#e.others + 1] = { bundle = bundle, cost = c }
                end
            end
            table.sort(e.others, function(a, b)
                if (a.cost == nil) ~= (b.cost == nil) then return a.cost ~= nil end
                return (a.cost or 0) < (b.cost or 0)
            end)
        end
    end
    -- back in the order the player picked the crates
    local rank = {}
    for i, p in ipairs(picks) do rank[p.id] = i end
    table.sort(order, function(a, b)
        if a.crate ~= b.crate then return (rank[a.crate] or 0) < (rank[b.crate] or 0) end
        return a.k < b.k
    end)
    result.crates = order
    return result
end

-- What the plan buys: one line per item, in the order of the crates: { { id, n, unit, cost } }.
function ns.ShoppingList(plan)
    local out, at = {}, {}
    for _, e in ipairs(plan.crates) do
        for _, r in ipairs(e.rows or {}) do
            if r.buy > 0 then
                local line = at[r.id]
                if not line then
                    line = { id = r.id, n = 0, unit = r.unit, cost = 0 }
                    at[r.id] = line
                    out[#out + 1] = line
                end
                line.n = line.n + r.buy
                line.cost = line.cost + r.cost
            end
        end
    end
    return out
end

-- ---------- calculating ----------

ns.picked = {} -- crate id -> false when the player unticked it (ticked by default)
ns.plan = nil

function ns.Picks(crates)
    local out = {}
    for _, c in ipairs(crates or ns.Crates()) do
        if ns.picked[c.id] ~= false then out[#out + 1] = { id = c.id, count = c.count } end
    end
    return out
end

function ns.Calculate()
    ns.ClearCache()
    local picks = ns.Picks()
    ns.plan = ns.Plan(picks, ns.Bundles, ns.Stock, ns.AuctionPrice, ns.db.bank)
    ns.plan.at = time()
    ns.ResetBuy()
    if ns.Refresh then ns.Refresh() end
    return ns.plan
end

-- ---------- buying at the auction house ----------
-- The game runs both purchase calls only inside a click (asking the price is protected too).
-- So each line takes two clicks on the same button: one asks the auction house for the real
-- price (the button then shows it), the next buys at that price. Never call them from an event
-- or a timer.

ns.buy = { queue = {}, i = 1, phase = "idle" }

local function A() return C_AuctionHouse end
local function canBuy()
    local a = A()
    return a and a.StartCommoditiesPurchase and a.ConfirmCommoditiesPurchase and true or false
end
ns.CanBuy = canBuy

function ns.ResetBuy()
    local b = ns.buy
    if b.phase == "ready" and A() and A().CancelCommoditiesPurchase then pcall(A().CancelCommoditiesPurchase) end
    b.queue = ns.plan and ns.ShoppingList(ns.plan) or {}
    b.i, b.phase, b.quote, b.err, b.spent, b.bought = 1, "idle", nil, nil, 0, 0
    b.failed = {}
end

function ns.Current() return ns.buy.queue[ns.buy.i] end

local function ask()
    local b, line = ns.buy, ns.Current()
    if not line then b.phase = "done"; return end
    b.phase, b.quote, b.err = "quote", nil, nil
    local ok = pcall(A().StartCommoditiesPurchase, line.id, line.n)
    if not ok then b.phase, b.err = "idle", "ERR_START"; return end
    local token = {}
    b.token = token
    C_Timer.After(QUOTE_WAIT, function()
        if b.token == token and b.phase == "quote" then
            b.phase, b.err = "idle", "ERR_NO_ANSWER"
            if ns.Refresh then ns.Refresh() end
        end
    end)
end

local function nextLine()
    local b = ns.buy
    b.i = b.i + 1
    -- the next price is asked from the next click: StartCommoditiesPurchase is protected too
    if ns.Current() then b.phase, b.quote = "idle", nil else
        b.phase = "done"
        say(L.ALL_BOUGHT:format(b.bought, ns.Money(b.spent)))
        notify(L.ALL_BOUGHT:format(b.bought, ns.Money(b.spent)))
    end
end

-- The Buy button: one step a click.
function ns.BuyClick()
    local b = ns.buy
    if not ns.atAH or not canBuy() or ns.paused then return end
    if b.phase == "idle" then ask()
    elseif b.phase == "ready" then
        local line = ns.Current()
        b.phase = "buying"
        local ok = pcall(A().ConfirmCommoditiesPurchase, line.id, line.n)
        if not ok then b.phase, b.err = "idle", "ERR_BUY" end
    end
    if ns.Refresh then ns.Refresh() end
end

-- Skip the current line (sold out, too dear) and go on with the next.
function ns.Skip()
    local b = ns.buy
    if b.phase == "ready" and A().CancelCommoditiesPurchase then pcall(A().CancelCommoditiesPurchase) end
    if ns.Current() then b.failed[#b.failed + 1] = ns.Current() end
    b.phase = "idle"
    b.i = b.i + 1
    if not ns.Current() then b.phase = "done" end
    if ns.Refresh then ns.Refresh() end
end

-- The real price is far above what the plan expected.
function ns.Dear()
    local b, line = ns.buy, ns.Current()
    if not b.quote or not line or not line.unit then return false end
    return b.quote.unit > line.unit * 1.5
end

function ns.OnAuction(event, a1, a2)
    local b = ns.buy
    if event == "COMMODITY_PRICE_UPDATED" then
        if b.phase == "quote" then b.phase, b.quote = "ready", { unit = a1 or 0, total = a2 or 0 } end
    elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
        if b.phase == "quote" then b.phase, b.err = "idle", "ERR_SOLD_OUT" end
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
        if b.phase == "buying" then
            local line = ns.Current()
            b.spent = b.spent + (b.quote and b.quote.total or line.cost)
            ns.AddLot(line.id, line.n, b.quote and b.quote.total or line.cost)
            b.bought = b.bought + 1
            line.done = true
            nextLine()
        end
    elseif event == "COMMODITY_PURCHASE_FAILED" then
        if b.phase == "buying" then b.phase, b.err = "idle", "ERR_BUY" end
    end
    if ns.Refresh then ns.Refresh() end
end

-- Without the modern auction house (or for items it does not sell as commodities): the list
-- goes to Auctionator as a shopping list with the amounts.
function ns.ExportList()
    local api = auctionator()
    if not api or not api.CreateShoppingList or not ns.plan then return nil end
    local terms = {}
    for _, line in ipairs(ns.ShoppingList(ns.plan)) do
        local name = itemName(line.id)
        if name then
            local term = { searchString = name, isExact = true, quantity = line.n }
            local ok, text = false, nil
            if api.ConvertToSearchString then ok, text = pcall(api.ConvertToSearchString, CALLER, term) end
            terms[#terms + 1] = ok and text or ('"' .. name .. '"')
        end
    end
    if #terms == 0 then return 0 end
    local ok = pcall(api.CreateShoppingList, CALLER, L.LIST_NAME, terms)
    return ok and #terms or nil
end

function ns.Money(copper)
    copper = math.floor(copper or 0)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

-- ---------- history ----------
-- A crate is filled when it leaves the bags together with the items of one of its bundles (the
-- game may report the two in separate bag updates, so drops wait a few seconds for each other).
-- A crate that leaves alone (sold, mailed, banked) is not logged. What the auction house sold
-- for it comes from the lots bought here, oldest first; the rest came from the player's stock.

ns.HISTORY_MAX = 300
local MATCH_WAIT = 5 -- seconds a crate drop and an item drop may lie apart

local function charKey()
    return (UnitName and UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
end

-- Units bought at the auction house and not used yet: db.lots[char][item] = { { n, total } }.
function ns.AddLot(id, n, total)
    if not ns.db or not n or n <= 0 then return end
    local key = charKey()
    ns.db.lots[key] = ns.db.lots[key] or {}
    local list = ns.db.lots[key][id] or {}
    ns.db.lots[key][id] = list
    list[#list + 1] = { n, total or 0 }
end

-- Takes n units from the lots: the copper they cost and how many there were.
function ns.TakeLots(id, n)
    local mine = ns.db and ns.db.lots[charKey()]
    local list = mine and mine[id]
    local paid, got = 0, 0
    while list and list[1] and got < n do
        local lot = list[1]
        local take = math.min(n - got, lot[1])
        local part = math.floor(lot[2] * take / lot[1] + 0.5)
        paid, got = paid + part, got + take
        lot[1], lot[2] = lot[1] - take, lot[2] - part
        if lot[1] <= 0 then table.remove(list, 1) end
    end
    if list and not list[1] then mine[id] = nil end
    return paid, got
end

local snap, pendCrates, pendItems = nil, {}, {}

-- Bag counts of every crate in the bags and of every item their bundles name, and which are crates.
local function snapshot()
    local counts, crates = {}, {}
    for _, c in ipairs(ns.Crates()) do
        counts[c.id], crates[c.id] = c.count, true
        for _, b in ipairs(ns.Bundles(c.id) or {}) do counts[b[1]] = counts[b[1]] or itemCount(b[1], false) end
    end
    return { counts = counts, crates = crates }
end

local function logFill(crate, bundle)
    local paid, bought = ns.TakeLots(bundle[1], bundle[2])
    local unit = ns.AuctionPrice(bundle[1])
    local e = { at = time(), crate = crate, item = bundle[1], n = bundle[2], paid = paid, bought = bought,
                worth = unit and unit * bundle[2] or nil, who = UnitName and UnitName("player") or nil }
    local h = ns.db.history
    table.insert(h, 1, e)
    while #h > ns.HISTORY_MAX do table.remove(h) end
    if ns.Refresh then ns.Refresh() end
    return e
end

-- Pairs each crate that left the bags with a bundle whose items left too.
local function match(now)
    for i = #pendCrates, 1, -1 do if now - pendCrates[i].t > MATCH_WAIT then table.remove(pendCrates, i) end end
    for id, d in pairs(pendItems) do if now - d.t > MATCH_WAIT then pendItems[id] = nil end end
    for i = #pendCrates, 1, -1 do
        local c = pendCrates[i]
        for _, b in ipairs(ns.Bundles(c.id) or {}) do
            local d = pendItems[b[1]]
            if d and d.n >= b[2] then
                d.n = d.n - b[2]
                table.remove(pendCrates, i)
                logFill(c.id, b)
                break
            end
        end
    end
    for id, d in pairs(pendItems) do if d.n <= 0 then pendItems[id] = nil end end
end

-- Called on every bag update: notes what left the bags since the last look.
function ns.Track()
    if not ns.db then return end
    local now = time()
    local cur = snapshot()
    if snap then
        for id, was in pairs(snap.counts) do
            local now_n = cur.counts[id]
            if now_n == nil then now_n = snap.crates[id] and 0 or itemCount(id, false); cur.counts[id] = now_n end
            local left = was - now_n
            if left > 0 and snap.crates[id] then
                for _ = 1, left do pendCrates[#pendCrates + 1] = { id = id, t = now } end
            elseif left > 0 then
                local d = pendItems[id] or { n = 0 }
                d.n, d.t = d.n + left, now
                pendItems[id] = d
            end
        end
        match(now)
    end
    -- the items of a crate that left and waits for its match stay watched
    for _, c in ipairs(pendCrates) do
        for _, b in ipairs(ns.Bundles(c.id) or {}) do
            cur.counts[b[1]] = cur.counts[b[1]] or itemCount(b[1], false)
        end
    end
    for id in pairs(snap and snap.crates or {}) do if not cur.crates[id] and cur.counts[id] == 0 then cur.counts[id] = nil end end
    snap = cur
end

-- The history, newest first, filtered: period "day", "week" or "all"; and the totals.
ns.PERIODS = { "day", "week", "all" }
local PERIOD_SECONDS = { day = 86400, week = 7 * 86400 }
function ns.History(period)
    local out, spent, worth = {}, 0, 0
    local since = PERIOD_SECONDS[period] and (time() - PERIOD_SECONDS[period]) or nil
    for _, e in ipairs(ns.db and ns.db.history or {}) do
        if not since or e.at >= since then
            out[#out + 1] = e
            spent = spent + (e.paid or 0)
            worth = worth + (e.worth or 0)
        end
    end
    return out, { count = #out, spent = spent, avg = #out > 0 and math.floor(spent / #out + 0.5) or 0 }
end

-- ---------- keeping the window current ----------

local function busy()
    local p = ns.buy.phase
    return p == "quote" or p == "ready" or p == "buying"
end

-- Drops a plan that has nothing left to do: no crate in the bags, or all bought and the auction
-- house closed.
function ns.Tidy()
    if not ns.plan or busy() then return end
    if #ns.Crates() == 0 or (ns.buy.phase == "done" and not ns.atAH) then
        ns.plan = nil
        ns.ResetBuy()
    end
end

-- The refresh button: looks at the bags again and plans anew, or clears the plan.
function ns.Recheck()
    if ns.buy.phase == "buying" then return end
    ns.notCrate = {}
    ns.ClearCache()
    if #ns.Picks() > 0 then ns.Calculate()
    else
        ns.plan = nil
        ns.ResetBuy()
        if ns.Refresh then ns.Refresh() end
    end
end

-- ---------- events ----------

local function listen(frame, events)
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, e in ipairs(events) do
        if not valid or valid(e) then pcall(frame.RegisterEvent, frame, e) end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, a2)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliCratesDB = GulliCratesDB or {}
        ns.db = GulliCratesDB
        for k, v in pairs(ns.DEFAULTS) do if ns.db[k] == nil then ns.db[k] = v end end
        ns.db.picked = ns.db.picked or {}
        ns.picked = ns.db.picked
        ns.db.history = ns.db.history or {}
        ns.db.lots = ns.db.lots or {}
        listen(self, { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED",
                       "PLAYER_ENTERING_WORLD",
                       "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE",
                       "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED" })
        nameIndex() -- asks the client for the bundle names early
        return
    end
    if ns.paused then return end
    if event == "AUCTION_HOUSE_SHOW" then
        ns.atAH = true
        ns.ClearCache()
        if ns.db.auto and #ns.Crates() > 0 and ns.ShowAtAH then ns.ShowAtAH() end
        if ns.Refresh then ns.Refresh() end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        ns.atAH = false
        if ns.buy.phase ~= "done" then ns.buy.phase, ns.buy.quote = "idle", nil end
        ns.Tidy()
        if ns.HideAtAH then ns.HideAtAH() end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        ns.notCrate = {}
    elseif event == "PLAYER_ENTERING_WORLD" then
        ns.Track()
    elseif event == "BAG_UPDATE_DELAYED" then
        ns.Track()
        ns.Tidy()
        if ns.Refresh then ns.Refresh() end
    else
        ns.OnAuction(event, a1, a2)
    end
end)

-- ---------- slash command and hub ----------

SLASH_GULLICRATES1 = "/gcr"
SlashCmdList.GULLICRATES = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "calc" then ns.Calculate() if ns.Window then ns.Window():Show() end return end
    if ns.Toggle then ns.Toggle() end
end
function GulliCrates_Toggle() if ns.Toggle then ns.Toggle() end end

ns.OPT_ICON = {
    auto = "Interface\\Minimap\\Tracking\\Auctioneer",
    bank = "Interface\\Minimap\\Tracking\\Banker",
}

local function option(key)
    return { label = L["OPT_" .. key], icon = ns.OPT_ICON[key], tip = L["TIP_" .. key],
             get = function() return ns.db ~= nil and ns.db[key] == true end,
             set = function(on) if ns.db then ns.db[key] = on and true or false end end }
end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "Crates",
        icon = "Interface\\AddOns\\Gulli-Crates\\icon",
        slash = "/gcr",
        open = function() if ns.Toggle then ns.Toggle() end end,
        window = function() return ns.Window and ns.Window() end,
        options = { option("auto"), option("bank") },
        pause = function(on)
            ns.paused = on
            if on and ns.HideAtAH then ns.HideAtAH(true) end
        end,
        summary = function()
            if not ns.db then return nil end
            local n = 0
            for _, c in ipairs(ns.Crates()) do n = n + c.count end
            if n == 0 then return nil end
            return L.SUMMARY:format(n), ns.OPT_ICON.auto
        end,
        reset = function()
            if not ns.db then return end
            for k, v in pairs(ns.DEFAULTS) do ns.db[k] = v end
            for k in pairs(ns.picked) do ns.picked[k] = nil end
            if ns.Refresh then ns.Refresh() end
        end,
    })
end
