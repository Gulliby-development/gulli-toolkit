-- Waylaid Crates: finds the cheapest bundle for each crate in the bags, from the bags, the bank
-- and Auctionator's prices, and buys what is missing at the auction house, one click a purchase.
-- The rules (ns.Bundles, ns.Plan, ns.ShoppingList) are plain Lua; the game calls go through the
-- wrappers at the top.

local ADDON, ns = ...
local L = ns.L

local CALLER = "Gulli-Crates"
local QUOTE_WAIT = 6 -- seconds the auction house has to answer a price request

ns.DEFAULTS = { auto = true, bank = true, live = true, goal = 30 }

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
-- The name to show: never the bare id, which means nothing to a player.
function ns.DisplayName(id)
    local n = id and itemName(id)
    if n then return n end
    if id then requestItem(id) end
    return ns.L.ITEM_LOADING
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
-- A price addon is loaded (Auctionator, auxForever, Naowh Forever, ...).
function ns.HasPrices() return ns.Skin and ns.Skin.HasPrices and ns.Skin.HasPrices() or false end
-- The lowest price of one (copper) from any price addon, through the shared reader, or nil.
function ns.AuctionPrice(id)
    return ns.Skin and ns.Skin.AuctionPrice and (ns.Skin.AuctionPrice(id)) or nil
end

-- How old Auctionator's prices are, in seconds, or nil when it cannot tell. Its saved state keeps
-- when the last scans ran (time() seconds); without them, the age in days of the bundle items'
-- prices (API v1) tells at least a day.
ns.STALE_HOURS = 4
local SCAN_FIELDS = { "TimeOfLastReplicateScan", "TimeOfLastGetAllScan", "TimeOfLastBrowseScan" }
function ns.PriceAge(items)
    local newest
    local saved = { Auctionator and Auctionator.SavedState or false, AUCTIONATOR_SAVEDVARS or false }
    for _, t in ipairs(saved) do
        if type(t) == "table" then
            for _, k in ipairs(SCAN_FIELDS) do
                local v = tonumber(t[k])
                if v and v > 0 and (not newest or v > newest) then newest = v end
            end
        end
    end
    if newest then return math.max(0, time() - newest) end
    local api = auctionator()
    if not api or not api.GetAuctionAgeByItemID then return nil end
    local days
    for _, id in ipairs(items or {}) do
        local ok, d = pcall(api.GetAuctionAgeByItemID, CALLER, id)
        if ok and type(d) == "number" and (not days or d < days) then days = d end
    end
    if days and days >= 1 then return days * 86400 end
    return nil
end

-- Hours the prices are old when that is more than ns.STALE_HOURS, else nil.
function ns.StaleHours()
    local items, seen = {}, {}
    for _, c in ipairs(ns.Crates()) do
        for _, b in ipairs(ns.Bundles(c.id) or {}) do
            if not seen[b[1]] then seen[b[1]] = true; items[#items + 1] = b[1] end
        end
    end
    local age = ns.PriceAge(items)
    if age and age > ns.STALE_HOURS * 3600 then return math.floor(age / 3600) end
    return nil
end

-- ---------- auction lots ----------
-- At the auction house, Calculate reads the listings of what the plan buys, so buying many of one
-- item takes the dearer lots too. Away from it (or before an item is read) the price is
-- Auctionator's lowest one, and the plan is marked as an estimate.

ns.LOTS_FRESH = 10 * 60
ns.lots = {} -- item id -> { t = time read, l = { { unit price, count } } cheapest first }
ns.flat = {} -- the items the last plan priced from Auctionator's lowest price

-- Mean unit price of n units after the first skip ones bought from lots (cheapest first), or nil
-- when the lots hold fewer.
function ns.LadderPrice(lots, n, skip)
    n, skip = n or 1, skip or 0
    local cost, pos, got = 0, 0, 0
    for _, l in ipairs(lots or {}) do
        local from, to = math.max(pos, skip), math.min(pos + l[2], skip + n)
        if to > from then cost, got = cost + (to - from) * l[1], got + (to - from) end
        pos = pos + l[2]
        if got >= n then break end
    end
    if n <= 0 or got < n then return nil end
    return cost / n
end

-- The price the plans use: mean unit price of n units after skip ones (see ns.Plan).
function ns.Price(id, n, skip)
    local lots = ns.lots[id]
    if lots and time() - lots.t <= ns.LOTS_FRESH then return ns.LadderPrice(lots.l, n, skip) end
    local unit = ns.AuctionPrice(id)
    if unit then ns.flat[id] = true end
    return unit
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
                    seen[id] = { id = id, count = 0, name = itemName(id), icon = ns.ItemIcon(id) }
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
-- price(item, n, skip) -> the mean unit price (copper) of n units after skip already bought, or
-- nil (a plain price(item) works too); useBank: bank items count too.
-- Each crate copy gets the bundle that costs least to complete; items the bags and the bank
-- hold cost nothing and are used once. The cheapest crate-and-bundle pair of all is settled
-- first, so a stock that completes one crate is not spent half on another.
-- Returns { crates = { { crate, k, bundle, rows, cost, buy, others } }, total, unpriced }.
-- What the bags and the bank hold, used once each, and the cost of completing one bundle from
-- what is left: rows and total (nil when an item to buy has no price).
local function stockPool(stock, price, useBank)
    local pool, bought = {}, {}
    local function have(id)
        if not pool[id] then
            local b, k = stock(id)
            pool[id] = { b or 0, useBank and (k or 0) or 0 }
        end
        return pool[id]
    end
    local function cost(bundle)
        local rows, total, buy = {}, 0, 0
        for _, b in ipairs(bundle) do
            local id, n = b[1], b[2]
            local h = have(id)
            local fromBags = math.min(n, h[1])
            local fromBank = math.min(n - fromBags, h[2])
            local need = n - fromBags - fromBank
            local unit = need > 0 and price(id, need, bought[id] or 0) or nil
            if need > 0 and not unit then return nil, rows end
            local c = math.floor(need * (unit or 0) + 0.5)
            rows[#rows + 1] = { id = id, n = n, bags = fromBags, bank = fromBank, buy = need, unit = unit, cost = c }
            total, buy = total + c, buy + need
        end
        return total, rows, buy
    end
    local function use(rows)
        for _, r in ipairs(rows) do
            if not r.crate then
                local h = have(r.id)
                h[1], h[2] = h[1] - r.bags, h[2] - r.bank
                bought[r.id] = (bought[r.id] or 0) + r.buy
            end
        end
    end
    return cost, use
end

function ns.Plan(picks, bundles, stock, price, useBank)
    local cost, use = stockPool(stock, price, useBank)

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
        use(best.rows)
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

-- ---------- Merchant's Favor goal (no game calls) ----------
-- Each filled crate hands in for Merchant's Favor, by its tier and kind (ns.FAVOR). For a goal,
-- every crate type gets the cost of its 1st, 2nd, ... copy (crates in the bags are free, then the
-- auction house; each copy with its cheapest bundle from what is left), and a knapsack over the
-- Favor picks the counts that reach the goal for the least gold. Then one pass settles the
-- picked crates against the shared stock, cheapest first, for the rows and the real total.

ns.GOALS = { 5, 15, 20, 30, 45, 50, 180 }
ns.GOAL_MAX = 1000
local UNIT = 5 -- every crate pays a multiple of 5

-- ids: the crates that may be used; favorOf(id) -> Favor of one; crateStock(id) -> crates in bags.
-- Returns { crates = { { crate, k, bundle, rows, cost, own, favor } }, total, favor, short }:
-- rows start with the crate itself ({ crate = true, buy = 1 } when it is bought); short is the
-- Favor the priced crates cannot reach.
function ns.TokenPlan(goal, ids, favorOf, bundles, stock, price, useBank, crateStock)
    local U = math.max(0, math.ceil((goal or 0) / UNIT))
    local result = { crates = {}, total = 0, favor = 0, short = 0 }
    if U == 0 then return result end

    -- the cost of each further copy of one crate type, from its own view of the stock
    local types = {}
    for _, id in ipairs(ids) do
        local f = favorOf(id)
        local list = bundles(id)
        if f and f > 0 and list then
            local u = math.max(1, math.floor(f / UNIT))
            local cost, use = stockPool(stock, price, useBank)
            local own = crateStock and crateStock(id) or 0
            local steps, got = {}, 0
            for _ = 1, math.ceil(U / u) do
                local unit = own <= 0 and price(id, 1, got) or nil
                if own <= 0 and not unit then break end
                local best, bestRows
                for _, bundle in ipairs(list) do
                    local total, rows = cost({ bundle })
                    if total and (not best or total < best) then best, bestRows = total, rows end
                end
                if not best then break end
                use(bestRows)
                if own <= 0 then got = got + 1 end
                own = own - 1
                steps[#steps + 1] = best + (unit or 0)
            end
            if #steps > 0 then types[#types + 1] = { id = id, u = u, steps = steps } end
        end
    end

    -- knapsack: dp[x] = least gold for at least x units of Favor (x capped at U)
    local INF = math.huge
    local dp, pick = { [0] = 0 }, {}
    for x = 1, U do dp[x] = INF end
    for t, ty in ipairs(types) do
        local nd, np = {}, {}
        for x = 0, U do nd[x], np[x] = dp[x], 0 end
        for x = 0, U do
            if dp[x] < INF then
                local sum = 0
                for k, c in ipairs(ty.steps) do
                    sum = sum + c
                    local y = math.min(U, x + k * ty.u)
                    if dp[x] + sum < nd[y] then nd[y], np[y] = dp[x] + sum, k * 10000 + x end
                    if y == U then break end
                end
            end
        end
        dp, pick[t] = nd, np
    end
    -- the best reachable amount: the goal, or the most Favor when the goal cannot be reached
    local at = U
    if dp[U] == INF then
        at = 0
        for x = U, 0, -1 do if dp[x] < INF then at = x; break end end
        result.short = (U - at) * UNIT
    end
    local counts = {}
    for t = #types, 1, -1 do
        local p = pick[t][at]
        if p and p > 0 then
            counts[types[t].id] = math.floor(p / 10000)
            at = p % 10000
        end
    end

    -- settle the picked crates on the shared stock, the cheapest crate and bundle first
    local cost, use = stockPool(stock, price, useBank)
    local left, got = {}, {}
    for _, id in ipairs(ids) do left[id] = crateStock and crateStock(id) or 0 end
    local k = 0
    while true do
        local best
        for _, id in ipairs(ids) do
            if (counts[id] or 0) > 0 then
                local own = left[id] > 0
                local unit = not own and price(id, 1, got[id] or 0) or nil
                for _, bundle in ipairs(bundles(id)) do
                    local total, rows, buy = cost({ bundle })
                    if total and (own or unit) then
                        total, buy = total + (unit or 0), buy + (own and 0 or 1)
                        if not best or total < best.cost or (total == best.cost and buy < best.buy) then
                            best = { crate = id, bundle = bundle, rows = rows, cost = total, buy = buy, own = own, unit = unit }
                        end
                    end
                end
            end
        end
        if not best then break end
        use(best.rows)
        counts[best.crate] = counts[best.crate] - 1
        if best.own then left[best.crate] = left[best.crate] - 1 else got[best.crate] = (got[best.crate] or 0) + 1 end
        table.insert(best.rows, 1, { id = best.crate, n = 1, crate = true, bags = best.own and 1 or 0, bank = 0,
                                     buy = best.own and 0 or 1, unit = best.unit, cost = math.floor((best.unit or 0) + 0.5) })
        k = k + 1
        local f = favorOf(best.crate)
        result.crates[#result.crates + 1] = { crate = best.crate, k = k, bundle = best.bundle, rows = best.rows,
                                              cost = best.cost, own = best.own, favor = f, others = {} }
        result.total = result.total + best.cost
        result.favor = result.favor + f
    end
    return result
end

-- The token plan grouped for the list: one group per crate and bundle with how many times,
-- the crates bought and owned, and the bundle items added up.
function ns.TokenGroups(plan)
    local out, at = {}, {}
    for _, e in ipairs(plan and plan.crates or {}) do
        local key = e.crate .. ":" .. e.bundle[1]
        local g = at[key]
        if not g then
            g = { crate = e.crate, bundle = e.bundle, n = 0, own = 0, buy = 0, crateCost = 0, cost = 0, favor = e.favor,
                  item = { id = e.bundle[1], n = 0, bags = 0, bank = 0, buy = 0, cost = 0 } }
            at[key] = g
            out[#out + 1] = g
        end
        g.n, g.cost = g.n + 1, g.cost + e.cost
        for _, r in ipairs(e.rows) do
            if r.crate then
                if r.buy > 0 then g.buy, g.crateCost = g.buy + 1, g.crateCost + r.cost else g.own = g.own + 1 end
            else
                local x = g.item
                x.n, x.bags, x.bank, x.buy, x.cost = x.n + r.n, x.bags + r.bags, x.bank + r.bank, x.buy + r.buy, x.cost + r.cost
            end
        end
    end
    return out
end

-- ---------- calculating ----------

ns.picked = {} -- crate id -> false when the player unticked it (ticked by default)
ns.plan = nil       -- the Fill tab's plan
ns.tokenPlan = nil  -- the Favor tab's plan
ns.source = "fill"  -- which of the two the Buy button works through

-- The plan the Buy button works through.
function ns.ActivePlan()
    if ns.source == "tokens" then return ns.tokenPlan end
    return ns.plan
end

function ns.Picks(crates)
    local out = {}
    for _, c in ipairs(crates or ns.Crates()) do
        if ns.picked[c.id] ~= false then out[#out + 1] = { id = c.id, count = c.count } end
    end
    return out
end

-- Ticks or unticks a crate. A plan on screen follows at once, so the player sees the price
-- change; not while a purchase waits for its answer.
function ns.SetPicked(id, on)
    if on then ns.picked[id] = nil else ns.picked[id] = false end
    local p = ns.buy.phase
    if ns.plan and p ~= "quote" and p ~= "buying" then
        if #ns.Picks() > 0 then return ns.Calculate() end
        ns.plan = nil
        if ns.source == "fill" then ns.ResetBuy() end
    end
    if ns.Refresh then ns.Refresh() end
end

-- The check box of a crate row.
function ns.TogglePick(id) return ns.SetPicked(id, ns.picked[id] == false) end

-- True when a plan buys something priced from Auctionator's lowest price, not from read lots.
local function estimate(plan)
    for _, line in ipairs(ns.ShoppingList(plan)) do if ns.flat[line.id] then return true end end
    return false
end

local live -- reads the lots of what a plan buys, then plans again (defined below)

local function planFill(round)
    ns.ClearCache()
    ns.flat = {}
    local picks = ns.Picks()
    ns.plan = ns.Plan(picks, ns.Bundles, ns.Stock, ns.Price, ns.db.bank)
    ns.plan.at = time()
    ns.plan.estimate = estimate(ns.plan)
    ns.source = "fill"
    ns.ResetBuy()
    live("fill", round)
    if ns.Refresh then ns.Refresh() end
    return ns.plan
end

function ns.Calculate()
    ns.tried = {}
    return planFill(1)
end

-- The crates the Favor goal may use: every crate the table knows up to the player's level, in
-- id order so the plan does not change from one run to the next.
function ns.TokenCrates()
    local level = UnitLevel and UnitLevel("player") or nil
    if type(level) ~= "number" then level = nil end
    local ids = {}
    for id, c in pairs(ns.CRATES) do
        if not level or c[1] <= level then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
end

-- Merchant's Favor one crate pays.
function ns.FavorOf(id) return ns.FAVOR[id] end

-- How much Merchant's Favor the player holds, and its icon, or nil.
function ns.FavorHeld()
    local C = C_CurrencyInfo
    local info = C and C.GetCurrencyInfo and C.GetCurrencyInfo(ns.CURRENCY)
    if type(info) ~= "table" then return nil end
    return info.quantity, info.iconFileID
end

-- After a setting changed: the plan on screen (the one the Buy button works through) anew.
function ns.Replan()
    if ns.Busy() or ns.Scanning() then if ns.Refresh then ns.Refresh() end return end
    if ns.source == "tokens" and ns.tokenPlan then return ns.TokenCalculate() end
    if ns.plan then return ns.Calculate() end
    if ns.Refresh then ns.Refresh() end
end

function ns.SetGoal(n)
    if not ns.db then return end
    ns.db.goal = math.max(1, math.min(ns.GOAL_MAX, math.floor(tonumber(n) or ns.DEFAULTS.goal)))
    if ns.tokenPlan and not ns.Busy() and not ns.Scanning() then return ns.TokenCalculate() end
    if ns.Refresh then ns.Refresh() end
end

local function planTokens(round)
    ns.ClearCache()
    ns.flat = {}
    local function crateStock(id) return itemCount(id, false) end
    ns.tokenPlan = ns.TokenPlan(ns.db.goal, ns.TokenCrates(), ns.FavorOf, ns.Bundles, ns.Stock,
                                ns.Price, ns.db.bank, crateStock)
    ns.tokenPlan.at = time()
    ns.tokenPlan.estimate = estimate(ns.tokenPlan)
    ns.source = "tokens"
    ns.ResetBuy()
    live("tokens", round)
    if ns.Refresh then ns.Refresh() end
    return ns.tokenPlan
end

function ns.TokenCalculate()
    ns.tried = {}
    return planTokens(1)
end

-- ---------- reading the lots at the auction house ----------
-- One search at a time, the next one a moment after the answer (or after SEARCH_WAIT without
-- one). After the lots of what a plan buys are read, it plans again; the new plan may buy other
-- items, so this repeats up to LIVE_ROUNDS times.

local SEARCH_WAIT, SEARCH_GAP, LIVE_ROUNDS = 5, 0.3, 4
local scan = { queue = {}, busy = nil, n = 0, done = 0 }
ns.scan = scan
ns.tried = {}

local function canSearch()
    local a = C_AuctionHouse
    return a and a.SendSearchQuery and a.MakeItemKey and true or false
end
ns.CanSearch = canSearch

-- The answer to the search for id: { { unit price, count } }, cheapest first.
local function readLots(id)
    local a, lots = C_AuctionHouse, {}
    if a.GetNumCommoditySearchResults then
        for i = 1, a.GetNumCommoditySearchResults(id) or 0 do
            local r = a.GetCommoditySearchResultInfo(id, i)
            if r and r.unitPrice and (r.quantity or 0) > 0 then lots[#lots + 1] = { r.unitPrice, r.quantity } end
        end
    end
    if #lots == 0 and a.GetNumItemSearchResults and a.GetItemSearchResultInfo then
        local key = a.MakeItemKey(id)
        for i = 1, a.GetNumItemSearchResults(key) or 0 do
            local r = a.GetItemSearchResultInfo(key, i)
            if r and r.buyoutAmount and r.buyoutAmount > 0 then
                local n = math.max(1, r.quantity or 1)
                lots[#lots + 1] = { r.buyoutAmount, n }
            end
        end
    end
    table.sort(lots, function(x, y) return x[1] < y[1] end)
    return lots
end

local nextSearch
nextSearch = function()
    local id = table.remove(scan.queue, 1)
    scan.busy = id
    if not id or not ns.atAH then
        scan.busy, scan.queue = nil, {}
        local after = scan.after
        scan.after = nil
        if after and ns.atAH then after() elseif ns.Refresh then ns.Refresh() end
        return
    end
    local a = C_AuctionHouse
    if not pcall(a.SendSearchQuery, a.MakeItemKey(id), {}, false) then
        scan.done = scan.done + 1
        return nextSearch()
    end
    C_Timer.After(SEARCH_WAIT, function()
        if scan.busy == id then scan.done = scan.done + 1; nextSearch() end
    end)
    if ns.Refresh then ns.Refresh() end
end

-- An answer from the auction house: COMMODITY_SEARCH_RESULTS_UPDATED (item id) or
-- ITEM_SEARCH_RESULTS_UPDATED (item key).
function ns.OnSearch(arg)
    local id = scan.busy
    if not id then return end
    local got = type(arg) == "table" and arg.itemID or arg
    if got ~= nil and got ~= id then return end -- the player's own search
    ns.lots[id] = { t = time(), l = readLots(id) }
    scan.done = scan.done + 1
    C_Timer.After(SEARCH_GAP, function() if scan.busy == id then nextSearch() end end)
end

-- Searches each of ids in turn, then runs after().
function ns.ScanLots(ids, after)
    if not ns.atAH or not canSearch() or #ids == 0 then return 0 end
    for _, id in ipairs(ids) do scan.queue[#scan.queue + 1] = id end
    scan.n = scan.busy and scan.n + #ids or #ids
    if not scan.busy then scan.done = 0 end
    scan.after = after
    if not scan.busy then nextSearch() end
    return #ids
end

function ns.StopScan()
    scan.queue, scan.busy, scan.after, scan.n, scan.done = {}, nil, nil, 0, 0
end

function ns.Scanning() return scan.busy ~= nil end

live = function(kind, round)
    if not ns.db.live or not ns.atAH or not canSearch() or round > LIVE_ROUNDS then return end
    local plan = kind == "tokens" and ns.tokenPlan or ns.plan
    local ids = {}
    for _, line in ipairs(ns.ShoppingList(plan)) do
        if ns.flat[line.id] and not ns.tried[line.id] then
            ns.tried[line.id] = true
            ids[#ids + 1] = line.id
        end
    end
    ns.ScanLots(ids, function()
        if ns.Busy() then return end
        if kind == "tokens" then planTokens(round + 1) else planFill(round + 1) end
    end)
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
    local plan = ns.ActivePlan()
    b.queue = plan and ns.ShoppingList(plan) or {}
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
    local plan = ns.ActivePlan()
    if not api or not api.CreateShoppingList or not plan then return nil end
    local terms = {}
    for _, line in ipairs(ns.ShoppingList(plan)) do
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

-- The realm the game gives now; some WoW Forever sessions give an empty name, and then the last
-- realm seen, else the one realm saved for this name, stands in, so one character keeps one key.
local function charKey()
    local name = UnitName and UnitName("player") or "?"
    local r = GetRealmName and GetRealmName()
    if (not r or r == "") and GetNormalizedRealmName then r = GetNormalizedRealmName() end
    if type(r) == "string" and r ~= "" then
        if ns.db then ns.db.realm = r end
    else
        r = ns.db and ns.db.realm
        if not r and ns.db then
            for key in pairs(ns.db.lots or {}) do
                local n, kr = key:match("^(.-)%-(.+)$")
                if n == name then
                    if r and r ~= kr then r = nil; break end
                    r = kr
                end
            end
        end
    end
    return name .. "-" .. (r or "?")
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

-- What the next n units after the first skip ones cost at the auction house, without using them.
function ns.PeekLots(id, n, skip)
    local mine = ns.db and ns.db.lots[charKey()]
    local paid, got, pos = 0, 0, 0
    for _, lot in ipairs(mine and mine[id] or {}) do
        local from, to = math.max(pos, skip or 0), math.min(pos + lot[1], (skip or 0) + n)
        if to > from then
            paid = paid + math.floor(lot[2] * (to - from) / lot[1] + 0.5)
            got = got + (to - from)
        end
        pos = pos + lot[1]
    end
    return paid, got
end

-- Crates in the bags that the bags (and the bank) already fill, with what the auction house got
-- for their items: they wait at the top of the History until they are used.
function ns.Ready()
    if not ns.db then return {} end
    local picks = {}
    for _, c in ipairs(ns.Crates()) do picks[#picks + 1] = { id = c.id, count = c.count } end
    local plan = ns.Plan(picks, ns.Bundles, ns.Stock, function() return nil end, ns.db.bank)
    local out, used = {}, {}
    for _, e in ipairs(plan.crates) do
        if not e.none then
            local id, n = e.bundle[1], e.bundle[2]
            local paid, bought = ns.PeekLots(id, n, used[id])
            used[id] = (used[id] or 0) + n
            local bank = 0
            for _, r in ipairs(e.rows) do bank = bank + r.bank end
            out[#out + 1] = { ready = true, crate = e.crate, item = id, n = n, paid = paid, bought = bought, bank = bank }
        end
    end
    return out
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
ns.Busy = busy

-- Drops a plan that has nothing left to do: no crate in the bags, or all bought and the auction
-- house closed.
function ns.Tidy()
    if ns.source ~= "fill" or not ns.plan or busy() then return end
    if #ns.Crates() == 0 or (ns.buy.phase == "done" and not ns.atAH) then
        ns.plan = nil
        ns.ResetBuy()
    end
end

-- The refresh button: looks at the bags again and plans anew, or clears the plan. On the Favor
-- tab (what = "tokens") it plans the goal anew.
function ns.Recheck(what)
    if ns.buy.phase == "buying" then return end
    ns.notCrate = {}
    ns.ClearCache()
    if what == "tokens" then ns.TokenCalculate()
    elseif #ns.Picks() > 0 then ns.Calculate()
    else
        ns.plan = nil
        if ns.source == "fill" then ns.ResetBuy() end
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

-- The auction house closed (or the player walked away): reading and buying stop, the window goes.
function ns.AuctionClosed()
    ns.atAH = false
    ns.StopScan()
    if ns.buy.phase ~= "done" then ns.buy.phase, ns.buy.quote = "idle", nil end
    ns.Tidy()
    if ns.HideAtAH then ns.HideAtAH() end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, a2)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliCratesDB = GulliCratesDB or {}
        ns.db = GulliCratesDB
        for k, v in pairs(ns.DEFAULTS) do if ns.db[k] == nil then ns.db[k] = v end end
        ns.db.favor = nil -- 1.4.0 asked for it; the table knows it now
        ns.db.picked = ns.db.picked or {}
        ns.picked = ns.db.picked
        ns.db.history = ns.db.history or {}
        ns.db.lots = ns.db.lots or {}
        -- lots saved under an empty realm name join this character's
        local key = charKey()
        local name = key:match("^(.-)%-")
        local stray = ns.db.lots[name .. "-"]
        if stray and key ~= name .. "-" then
            local mine = ns.db.lots[key] or {}
            ns.db.lots[key] = mine
            for id, list in pairs(stray) do
                mine[id] = mine[id] or {}
                for _, lot in ipairs(list) do table.insert(mine[id], lot) end
            end
            ns.db.lots[name .. "-"] = nil
        end
        listen(self, { "AUCTION_HOUSE_SHOW", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED",
                       "PLAYER_ENTERING_WORLD",
                       "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE",
                       "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
                       "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED" })
        nameIndex() -- asks the client for the bundle names early
        -- every way the auction house closes, walking away too; also while paused
        if ns.Skin and ns.Skin.ClosesWith then ns.Skin.ClosesWith("auction", ns.AuctionClosed) end
        return
    end
    if ns.paused then return end
    if event == "AUCTION_HOUSE_SHOW" then
        ns.atAH = true
        ns.staleClosed = false -- the price warning shows again on each visit
        ns.ClearCache()
        -- what was bought on an earlier visit is in the bags now: plan anew, so it is not offered again
        if ns.buy.phase ~= "quote" and ns.buy.phase ~= "buying" then
            if ns.source == "tokens" and ns.tokenPlan then ns.TokenCalculate()
            elseif #ns.Picks() > 0 then ns.Calculate() end
        end
        if ns.db.auto and #ns.Crates() > 0 and ns.ShowAtAH then ns.ShowAtAH() end
        if ns.Refresh then ns.Refresh() end
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_UPDATED" then
        ns.OnSearch(a1)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        ns.notCrate = {}
        -- a burst of item answers redraws the names once
        if not ns.namesPending and C_Timer and ns.Refresh then
            ns.namesPending = true
            C_Timer.After(0.3, function()
                ns.namesPending = nil
                if ns.Refresh then ns.Refresh() end
            end)
        end
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
    live = "Interface\\Icons\\INV_Misc_Spyglass_03",
}

local function option(key)
    return { label = L["OPT_" .. key], icon = ns.OPT_ICON[key], tip = L["TIP_" .. key],
             get = function() return ns.db ~= nil and ns.db[key] == true end,
             set = function(on) if ns.db then ns.db[key] = on and true or false end end }
end

-- With the hub: its row and button there; alone: its own minimap button (Skin.lua).
do
    local register = GulliToolkit and GulliToolkit.Register or function(info) ns.alone = info end
    register({
        key = "Crates",
        icon = "Interface\\AddOns\\Gulli-Crates\\icon",
        slash = "/gcr",
        open = function() if ns.Toggle then ns.Toggle() end end,
        window = function() return ns.Window and ns.Window() end,
        options = { option("auto"), option("bank"), option("live") },
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
            if ns.tokenPlan and not busy() then ns.TokenCalculate() end
            if ns.Refresh then ns.Refresh() end
        end,
    })
end
