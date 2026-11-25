-- Vendor Flip: while the auction house is open it looks at the whole market every minute (or as often as the player set) and
-- lists the lots whose buyout is below what any vendor pays for them. Each line is bought with
-- the player's clicks; what was bought is sold at the next vendor. The rules (ns.Candidates,
-- ns.CommodityDeal, ns.ItemDeals, ns.Deals, ns.Fits) are plain Lua; the game calls go through
-- the wrappers at the top.

local ADDON, ns = ...
local L = ns.L

ns.DEFAULTS = { scan = true, auto = true, sell = false, sound = false, minGain = 500, reserve = 0, keepFree = 2,
                gear = true, goods = true, interval = 60, de = true, soundAt = 10000,
                gq0 = true, gq1 = true, gq2 = true, gq3 = true, gq4 = true,
                oq0 = true, oq1 = true, oq2 = true, oq3 = true, oq4 = true }
-- What the vendor list looks at: gear (weapons and armour) with its own qualities (gq0 grey ..
-- gq4 purple and better) and the rest with its own (oq0 .. oq4). soundAt is the gain of a new
-- line that rings, with `sound` on.
-- Settings of older versions: dropped on load. The one quality row (q0..q4) goes to both kinds.
ns.GONE = { "full", "maxPrice", "minPct" }
ns.GEAR_CLASSES = { [2] = true, [4] = true }
ns.QUALITIES = { 0, 1, 2, 3, 4 }
-- The money settings: the least gain per line goes down to one copper.
ns.MIN_GAIN, ns.MAX_MONEY = 1, 99999 * 10000 + 9999

ns.INTERVAL = 60      -- seconds between two scans, unless the player picked another
-- The intervals the player can pick. A scan starts this long after the last one ended.
ns.INTERVALS = { 5, 10, 20, 30, 40, 50, 60, 120, 180, 240, 300 }
-- The auction house answers about 100 searches a minute; a shorter interval reads fewer lots per
-- scan (the best first), so all scans together stay under this.
ns.SEARCHES_PER_MIN = 80
ns.DETAIL_MIN = 5
ns.QUIET = 20         -- seconds the scan waits after a search of the player (or another addon)
ns.MAX_PAGES = 40     -- browse pages a scan reads at most
ns.DETAIL_MAX = 30    -- lots read per scan (searches are limited to 100 a minute)
ns.PAGE_WAIT = 10     -- seconds a browse page may take
ns.SEARCH_WAIT = 4    -- seconds a search may take
ns.SEARCH_GAP = 0.2
ns.QUOTE_WAIT = 6     -- seconds the auction house has to answer a price or a purchase
ns.HOLD = 8           -- seconds the scan sends nothing after a buy click, so the next click buys at once
ns.HOLD_STEP = 0.5    -- how often a held scan looks again
ns.SIFT_STEP = 300    -- browse results looked at in one frame (a full market is tens of thousands)
ns.LOAD_MAX = 200     -- unknown items a scan asks the client to load (cheapest first; the rest next time)
ns.REDRAW = 0.25      -- the window redraws at most this often for the scan and item events
ns.SELL_STEP = 12     -- items sold at a vendor in one step
ns.HISTORY_MAX = 400

-- Seconds between two scans: the picked one, if it is one of the list.
function ns.Interval()
    local v = ns.db and ns.db.interval
    for _, i in ipairs(ns.INTERVALS) do if i == v then return v end end
    return ns.INTERVAL
end

-- Lots a scan reads at this interval.
function ns.DetailMax(interval)
    return math.max(ns.DETAIL_MIN, math.min(ns.DETAIL_MAX, math.floor(ns.SEARCHES_PER_MIN * interval / 60)))
end

local function say(msg) print("|cff9ad0ffVendor Flip|r: " .. msg) end
local function notify(msg) if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("VendorFlip", msg) end end
ns.Say = say

-- ---------- game wrappers ----------

local function A() return C_AuctionHouse end
local I = C_Item or {}

-- name, quality, icon, sell price of one, stack size, item class, item level; nil while the client does not
-- know the item (then the client is asked to load it, unless noLoad).
function ns.ItemInfo(item, noLoad)
    local name, q, stack, icon, sell, class, level
    if I.GetItemInfo then
        local n, _, q1, lv, _, _, _, st, _, ic, sp, cl = I.GetItemInfo(item)
        name, q, stack, icon, sell, class, level = n, q1, st, ic, sp, cl, lv
    elseif GetItemInfo then
        local n, _, q1, lv, _, _, _, st, _, ic, sp, cl = GetItemInfo(item)
        name, q, stack, icon, sell, class, level = n, q1, st, ic, sp, cl, lv
    end
    if not name then
        local id = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
        if id and not noLoad and I.RequestLoadItemDataByID then pcall(I.RequestLoadItemDataByID, id) end
        return nil
    end
    return name, q or 1, icon, sell or 0, math.max(1, stack or 1), class, level or 0
end

-- Does the player want items of this quality and class on the vendor list (prefs: gear with
-- gq0..gq4, goods with oq0..oq4)?
function ns.Wanted(quality, class, prefs)
    local gear = ns.GEAR_CLASSES[class or -1] or false
    if gear and prefs.gear == false then return false end
    if not gear and prefs.goods == false then return false end
    return prefs[(gear and "gq" or "oq") .. math.max(0, math.min(4, quality or 1))] ~= false
end

-- Moves the settings of an older version: the one quality row to both kinds, the rest dropped.
function ns.Migrate(db)
    for _, q in ipairs(ns.QUALITIES) do
        local old = db["q" .. q]
        if old ~= nil then
            if db["gq" .. q] == nil then db["gq" .. q] = old end
            if db["oq" .. q] == nil then db["oq" .. q] = old end
            db["q" .. q] = nil
        end
    end
    for _, key in ipairs(ns.GONE) do db[key] = nil end
end

function ns.Money()
    return (GetMoney and GetMoney()) or 0
end

local function numSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end
-- Free slots of one bag and its family (0 for a normal bag).
local function freeSlots(bag)
    local get = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    if not get then return 0, 0 end
    local n, family = get(bag)
    return n or 0, family or 0
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
local function useItem(bag, slot)
    if C_Container and C_Container.UseContainerItem then return C_Container.UseContainerItem(bag, slot) end
    if UseContainerItem then return UseContainerItem(bag, slot) end
end

-- Room for a purchase: the backpack and the bags, never a quiver, a soul bag or the reagent bag.
function ns.FreeSlots()
    local n = 0
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        local free, family = freeSlots(bag)
        if family == 0 then n = n + free end
    end
    return n
end

local function protected(id)
    return GulliToolkit and GulliToolkit.IsProtected and GulliToolkit.IsProtected(id) or false
end

-- The realm the game gives now; some WoW Forever sessions give an empty name, and then the last
-- realm seen, else the one realm saved for this name, stands in, so one character keeps one key.
local function charKey()
    local name = UnitName and UnitName("player") or "?"
    local r = GetRealmName and GetRealmName()
    if type(r) == "string" and r ~= "" then
        if ns.db then ns.db.realm = r end
    else
        r = ns.db and ns.db.realm
        if not r and ns.db then
            for key in pairs(ns.db.owed or {}) do
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

-- ---------- own prices ----------

-- The prices of this character's auction house: one list per realm and faction.
function ns.MarketKey()
    local realm = charKey():match("%-(.+)$") or "?"
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    return realm .. "|" .. (type(faction) == "string" and faction or "?")
end

function ns.Market()
    if not ns.db then return nil end
    ns.db.markets = ns.db.markets or {}
    local key = ns.MarketKey()
    local m = ns.db.markets[key]
    if not m then
        -- prices noted while the realm name was still unknown join the real list
        local realm = key:match("^(.-)|")
        local stray = realm ~= "?" and ns.db.markets[key:gsub("^.-|", "?|")]
        if stray then ns.db.markets[key:gsub("^.-|", "?|")] = nil end
        m = stray or ns.NewMarket()
        ns.db.markets[key] = m
    end
    return m
end

-- The price of one at this auction house and its age in days, from the module's own scans.
function ns.OwnPrice(id)
    return ns.PriceOf(ns.Market(), id)
end

-- For the other modules, through the skin's price reader (S.PRICE_SOURCES).
GulliAuction = GulliAuction or {}
GulliAuction.Price = function(id) return ns.OwnPrice(id) end
GulliAuction.Normal = function(id) return ns.NormalOf(ns.Market(), id) end
GulliAuction.Ready = function()
    local m = ns.db and ns.Market()
    return m ~= nil and (m.n or 0) > 0
end

-- What a material sells for: the own price first, else any loaded price addon's.
function ns.MatPrice(id)
    local price = ns.OwnPrice(id)
    if price then return price end
    return ns.Skin and ns.Skin.AuctionPrice and (ns.Skin.AuctionPrice(id)) or nil
end

-- The character knows Enchanting (skill line 333).
function ns.Enchanter()
    if not (GetProfessions and GetProfessionInfo) then return false end
    for _, i in ipairs({ GetProfessions() }) do
        if i then
            local _, _, _, _, _, _, line = GetProfessionInfo(i)
            if line == 333 then return true end
        end
    end
    return false
end

-- ---------- the rules ----------

-- Browse results (one per item key, its lowest buyout) that are worth more than they cost:
-- { key, id, unit, sell, gain, mode }, the best gain of one first. sellOf(id) gives what one is
-- worth (the vendor price, or for mode "d" what disenchanting gives at the least), nil while
-- unknown.
function ns.Candidates(results, sellOf, mode)
    local out = {}
    for _, r in ipairs(results or {}) do
        local key = r.itemKey
        local id = key and key.itemID
        local unit = tonumber(r.minPrice)
        if id and unit and unit > 0 and not (key.battlePetSpeciesID and key.battlePetSpeciesID > 0) then
            local sell = sellOf(id)
            if sell and sell > unit then
                out[#out + 1] = { key = key, id = id, unit = unit, sell = sell, gain = sell - unit, mode = mode }
            end
        end
    end
    table.sort(out, function(a, b) return a.gain > b.gain end)
    return out
end

-- A commodity's lots ({ unitPrice, quantity, own }) cheapest first: how many to buy so that each
-- unit sells for more than it cost, within money copper and room bag
-- slots of stack each. Returns { n, cost, value, gain } or nil.
function ns.CommodityDeal(lots, sell, money, room, stack)
    local n, cost = 0, 0
    local maxN = math.max(0, room or 0) * math.max(1, stack or 1)
    for _, l in ipairs(lots or {}) do
        local price, q = l[1], l[2] - (l[3] or 0)
        if price >= sell then break end
        if q > 0 then
            local take = math.min(q, maxN - n)
            if price > 0 then take = math.min(take, math.floor((money - cost) / price)) end
            if take <= 0 then break end
            n, cost = n + take, cost + take * price
        end
    end
    if n <= 0 then return nil end
    local value = n * sell
    -- one click buys every unit: what it pays is the whole cost
    return { n = n, cost = cost, value = value, gain = value - cost, pay = cost, per = n, each = cost / n, sellEach = sell }
end

-- An item's search results ({ auctionID, quantity, buyout, sell of one, own }). The auction house
-- shows the same item at the same price as one result: quantity is how many are on sale, the
-- buyout is the price of one, and PlaceBid buys one. So a line is one price with its count, and
-- each click buys one of them. So an item line is always one item (n 1) and its prices and gain
-- are for that one; `left` is how many are on sale at that price, and the line stays until the
-- last of them is bought.
function ns.ItemDeals(lots)
    local out = {}
    for _, l in ipairs(lots or {}) do
        local id, q, buyout, sell, own = l[1], l[2] or 1, l[3], l[4], l[5]
        if buyout and buyout > 0 and sell and not own and sell > buyout then
            out[#out + 1] = { auction = id, n = 1, left = q, cost = buyout, value = sell, gain = sell - buyout,
                              pay = buyout, per = 1, each = buyout, sellEach = sell }
        end
    end
    return out
end

-- Can the player take this line now: money above the reserve, slots above the ones kept free.
function ns.Fits(line, money, reserve, free, keepFree)
    if (line.pay or line.cost) > money - (reserve or 0) then return false end
    return (line.slots or 1) <= free - (keepFree or 0)
end

-- The list to show: lines worth at least minGain that fit, best gain first; bought and gone lines
-- stay where they are until the next scan.
function ns.Deals(lines, minGain, money, reserve, free, keepFree)
    local out = {}
    for _, line in ipairs(lines or {}) do
        if line.state or (line.gain >= (minGain or 0) and ns.Fits(line, money, reserve, free, keepFree)) then
            out[#out + 1] = line
        end
    end
    table.sort(out, function(a, b) return a.gain > b.gain end)
    return out
end

-- ---------- the scan ----------
-- A browse of the whole market sorted by price (page after page while the throttle allows),
-- then a search for each item that sells to a vendor for more, for its lots. It waits while the
-- player (or another addon) searches, since one query replaces the other's results.

local scan = { phase = "idle", results = {}, queue = {}, pages = 0, maxPages = ns.MAX_PAGES, next = 0, quietUntil = 0, done = 0, n = 0 }
ns.scan = scan
ns.lines = {}

local ours = false -- the query being sent is our own

local function canScan()
    local a = A()
    return a and a.SendBrowseQuery and a.GetBrowseResults and a.SendSearchQuery and true or false
end
ns.CanScan = canScan

local function ready()
    local a = A()
    return not a.IsThrottledMessageSystemReady or a.IsThrottledMessageSystemReady()
end

-- The vendor price of one, nil while unknown or when the filters leave the item out. A scan asks
-- the client to load at most LOAD_MAX unknown items: each answer is an event.
local function sellOf(id)
    local load = (scan.loads or 0) < ns.LOAD_MAX
    local name, q, _, sell, _, class = ns.ItemInfo(id, not load)
    if not name and load then scan.loads = (scan.loads or 0) + 1 end
    if not name or not ns.Wanted(q, class, ns.db) then return nil end
    return sell
end

-- What disenchanting one gives on the safe side, for the "buy to disenchant" list: only green and
-- blue weapons and armour, only for an enchanter with the `de` switch on, and only while the
-- materials have a price. The vendor list's kinds and qualities do not apply to it.
local function deOf(id)
    if not scan.de then return nil end
    local name, q, _, _, _, class, level = ns.ItemInfo(id, true)
    if not name or not ns.GEAR_CLASSES[class or -1] then return nil end
    return ns.DisenchantFloor(q, level, ns.MatPrice, class)
end

local function wantedLine(line)
    if line.mode == "d" then return true end
    local name, q, _, _, _, class = ns.ItemInfo(line.id)
    return not name or ns.Wanted(q, class, ns.db)
end

local function refresh() if ns.Refresh then ns.Refresh() end end

-- One redraw for a burst of events (item loads, scan steps), never one per event.
local redrawPending = false
local function refreshSoon()
    if redrawPending then return end
    redrawPending = true
    C_Timer.After(ns.REDRAW, function() redrawPending = false; refresh() end)
end
ns.RefreshSoon = refreshSoon

-- A line found again keeps its table (the queue and a purchase point to it) and its "bought".
local function merge(was, d)
    local state = was.state == "bought" and "bought" or nil
    for k in pairs(was) do was[k] = nil end
    for k, v in pairs(d) do was[k] = v end
    was.state = state
    return was
end

-- Each search shows its finds at once, so a deal can be bought while the scan goes on: the lines
-- of that item are replaced by what the search found now.
local function publish(c, deals)
    local old, keep = {}, {}
    for _, line in ipairs(ns.lines) do
        local mine = (line.key == c.key or line.id == c.id) and line.mode == c.mode
        if mine and line.state ~= "bought" and not (line == ns.buy.line and ns.Busy()) then old[line.uid] = line
        else keep[#keep + 1] = line end
    end
    for _, d in ipairs(deals) do
        local was = old[d.uid]
        local line = was and merge(was, d) or d
        if not was and d.gain >= (ns.db.soundAt or 0) then scan.ring = true end
        keep[#keep + 1] = line
        if scan.found then scan.found[line.uid] = true end
    end
    ns.lines = keep
    if scan.ring and not scan.rang and ns.db.sound and PlaySound and SOUNDKIT and SOUNDKIT.AUCTION_WINDOW_OPEN then
        scan.rang = true
        pcall(PlaySound, SOUNDKIT.AUCTION_WINDOW_OPEN, "Master")
    end
end

local function finish()
    scan.phase, scan.busy = "idle", nil
    scan.at = time()
    scan.next = time() + ns.Interval()
    -- what this scan did not find again is gone from the market or the top of the list
    local fresh = {}
    for _, line in ipairs(ns.lines) do
        if scan.found and scan.found[line.uid] then fresh[#fresh + 1] = line end
    end
    ns.lines = fresh
    scan.found, scan.ring, scan.rang = nil, nil, nil
    refresh()
end

local nextSearch

local function readCommodity(c)
    local a, lots = A(), {}
    for i = 1, (a.GetNumCommoditySearchResults and a.GetNumCommoditySearchResults(c.id)) or 0 do
        local r = a.GetCommoditySearchResultInfo(c.id, i)
        if r and r.unitPrice and (r.quantity or 0) > 0 then lots[#lots + 1] = { r.unitPrice, r.quantity, r.numOwnerItems or 0 } end
    end
    table.sort(lots, function(x, y) return x[1] < y[1] end)
    local _, _, _, _, stack = ns.ItemInfo(c.id)
    local room = math.max(0, ns.FreeSlots() - ns.db.keepFree)
    local money = math.max(0, ns.Money() - ns.db.reserve)
    local d = ns.CommodityDeal(lots, c.sell, money, room, stack)
    if d then
        d.kind, d.id, d.key, d.uid = "c", c.id, c.key, "c" .. c.id
        d.slots = math.ceil(d.n / (stack or 1))
    end
    publish(c, d and { d } or {})
end

local function readItems(c)
    local a, lots = A(), {}
    for i = 1, (a.GetNumItemSearchResults and a.GetNumItemSearchResults(c.key)) or 0 do
        local r = a.GetItemSearchResultInfo(c.key, i)
        if r and r.buyoutAmount and r.buyoutAmount > 0 and r.auctionID then
            -- a vendor's price is the lot's own (a suffix changes it); a disenchant is by level
            local sell = not c.mode and select(4, ns.ItemInfo(r.itemLink or c.id)) or nil
            lots[#lots + 1] = { r.auctionID, math.max(1, r.quantity or 1), r.buyoutAmount, sell or c.sell, r.containsOwnerItem }
        end
    end
    local deals = ns.ItemDeals(lots)
    for _, d in ipairs(deals) do
        d.kind, d.id, d.key, d.uid, d.slots, d.mode = "i", c.id, c.key, (c.mode or "i") .. d.auction, 1, c.mode
    end
    publish(c, deals)
end

nextSearch = function()
    -- a purchase goes first: one query at a time, so the scan sends nothing while the player buys
    if ns.atAH and ns.Holding() then
        scan.held = true
        C_Timer.After(ns.HOLD_STEP, function() if scan.phase == "detail" and not scan.busy then nextSearch() end end)
        return refreshSoon()
    end
    scan.held = nil
    local c = table.remove(scan.queue, 1)
    if not ns.atAH then scan.phase = "idle"; return end
    if not c then return finish() end
    scan.busy = c
    local a = A()
    local info = a.GetItemKeyInfo and a.GetItemKeyInfo(c.key)
    c.commodity = info and info.isCommodity or false
    ours = true
    local ok = pcall(a.SendSearchQuery, c.key, { { sortOrder = 0, reverseSort = false } }, true)
    ours = false
    if not ok then scan.done = scan.done + 1; return nextSearch() end
    C_Timer.After(ns.SEARCH_WAIT, function()
        if scan.busy == c then scan.done = scan.done + 1; nextSearch() end
    end)
    refreshSoon()
end

-- An answer to a search: COMMODITY_SEARCH_RESULTS_UPDATED (item id) or
-- ITEM_SEARCH_RESULTS_UPDATED (item key).
function ns.OnSearch(event, arg)
    local id = type(arg) == "table" and arg.itemID or arg
    local r = ns.refetch
    if r and r.id == id then
        ns.refetch = nil
        if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then readCommodity(r) else readItems(r) end
        refreshSoon()
    end
    local c = scan.busy
    if scan.phase ~= "detail" or not c then return end
    if id ~= c.id then return end
    scan.busy = nil
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then readCommodity(c) else readItems(c) end
    scan.done = scan.done + 1
    refreshSoon()
    C_Timer.After(ns.SEARCH_GAP, function() if scan.phase == "detail" and not scan.busy then nextSearch() end end)
end

local function startDetail()
    local cands = scan.cands or {}
    table.sort(cands, function(a, b) return a.gain > b.gain end)
    scan.queue, scan.found, scan.cands = {}, {}, nil
    for i = 1, math.min(#cands, ns.DetailMax(ns.Interval())) do scan.queue[i] = cands[i] end
    scan.phase, scan.done, scan.n = "detail", 0, #scan.queue
    nextSearch()
end

-- The browse results are looked at SIFT_STEP per frame, so a market of tens of thousands of
-- lots never stops the game.
local function sift()
    if scan.phase ~= "sift" then return end
    local res, i = scan.results, scan.sifted
    local last = math.min(#res, i + ns.SIFT_STEP)
    local part = {}
    for k = i + 1, last do part[#part + 1] = res[k] end
    ns.NotePrices(part)
    for _, c in ipairs(ns.Candidates(part, sellOf)) do scan.cands[#scan.cands + 1] = c end
    for _, c in ipairs(ns.Candidates(part, deOf, "d")) do scan.cands[#scan.cands + 1] = c end
    scan.sifted = last
    if last >= #res then
        -- the whole market was read: the Prices card tells when
        local m = ns.Market()
        if scan.full and m then m.at = time() end
        return startDetail()
    end
    refreshSoon()
    C_Timer.After(0, sift)
end

-- Every browse result is the lowest buyout of its item key: the cheapest key of an item is the
-- item's price. scan.low keeps what this scan saw, so a dearer key never replaces a cheaper one.
function ns.NotePrices(results)
    local m = ns.Market()
    if not m then return end
    local day, low = ns.Today(), scan.low or {}
    scan.low = low
    for _, r in ipairs(results) do
        local key = r.itemKey
        local id, unit = key and key.itemID, tonumber(r.minPrice)
        if id and unit and unit > 0 and not (key.battlePetSpeciesID and key.battlePetSpeciesID > 0)
           and (not low[id] or unit < low[id]) then
            low[id] = unit
            ns.NotePrice(m, id, unit, tonumber(r.totalQuantity) or 0, day)
        end
    end
end

local function startSift()
    scan.phase, scan.sifted, scan.cands, scan.loads, scan.low = "sift", 0, {}, 0, {}
    scan.de = ns.db.de ~= false and ns.Enchanter()
    sift()
end

local function morePage()
    local a = A()
    if ns.Holding() then
        scan.held = true
        local page = scan.pages
        C_Timer.After(ns.HOLD_STEP, function() if scan.phase == "browse" and scan.pages == page then morePage() end end)
        return refreshSoon()
    end
    scan.held = nil
    if not ready() then scan.waitReady = true; return end
    scan.waitReady = nil
    scan.pages = scan.pages + 1
    ours = true
    pcall(a.RequestMoreBrowseResults)
    ours = false
    local page = scan.pages
    C_Timer.After(ns.PAGE_WAIT, function()
        if scan.phase == "browse" and scan.pages == page then startSift() end
    end)
end

-- AUCTION_HOUSE_BROWSE_RESULTS_UPDATED / _ADDED while our browse runs.
-- A page adds its results (the _ADDED event brings them), so the whole list is read only once.
function ns.OnBrowse(added)
    if scan.phase ~= "browse" then return end
    local a = A()
    if type(added) == "table" then
        for _, r in ipairs(added) do scan.results[#scan.results + 1] = r end
    else
        scan.results = a.GetBrowseResults() or {}
    end
    refreshSoon()
    if (a.HasFullBrowseResults and a.HasFullBrowseResults()) or scan.pages >= scan.maxPages or not a.RequestMoreBrowseResults then
        return startSift()
    end
    morePage()
end

function ns.OnThrottleReady()
    if scan.phase == "browse" and scan.waitReady then morePage() end
end

-- Starts a scan now, when nothing stands in the way. A scan reads the cheapest pages, for the
-- deals; only `whole` (the Read the whole market button) reads every page, for the prices.
function ns.Scan(force, whole)
    if not ns.atAH or ns.paused or not canScan() or scan.phase ~= "idle" then return false end
    if not force and (not ns.db.scan or time() < scan.quietUntil or ns.Holding()) then return false end
    if ns.Busy() or not ready() then return false end
    scan.phase, scan.pages, scan.results, scan.done, scan.n = "browse", 1, {}, 0, 0
    scan.full = whole == true
    scan.maxPages = scan.full and ns.FULL_PAGES or ns.MAX_PAGES
    ours = true
    local ok = pcall(A().SendBrowseQuery, { searchString = "", sorts = { { sortOrder = 0, reverseSort = false } },
                                           filters = {}, itemClassFilters = {} })
    ours = false
    if not ok then scan.phase = "idle"; scan.next = time() + ns.Interval(); return false end
    C_Timer.After(ns.PAGE_WAIT, function()
        if scan.phase == "browse" and scan.pages == 1 and #scan.results == 0 then
            scan.phase = "idle"; scan.next = time() + ns.Interval(); refresh()
        end
    end)
    refresh()
    return true
end

-- Somebody else sent a query (the player in the auction window, another addon): ours waits.
function ns.OthersQuery()
    if ours then return end
    scan.quietUntil = time() + ns.QUIET
    if scan.phase ~= "idle" then scan.phase, scan.busy, scan.queue = "idle", nil, {} end
    if scan.next < scan.quietUntil then scan.next = scan.quietUntil end
end

function ns.StopScan()
    scan.phase, scan.busy, scan.queue, scan.waitReady = "idle", nil, {}, nil
end

function ns.Scanning() return scan.phase ~= "idle" end

-- Seconds to the next scan, or nil while one runs or scanning is off.
function ns.NextIn()
    if scan.phase ~= "idle" or not ns.db.scan then return nil end
    return math.max(0, scan.next - time())
end

-- Every second at the auction house.
function ns.Tick()
    if not ns.atAH or ns.paused then return end
    if scan.phase == "idle" and ns.db.scan and time() >= scan.next then ns.Scan() end
    refresh()
end

-- The two lists of the Deals page: "v" sells to a vendor for more, "d" disenchants for more.
ns.VIEWS = { "v", "d" }
ns.view = "v"

-- The lines on screen: those of the list shown, or of every list with view "all".
function ns.Shown(view)
    if not ns.db then return {} end
    view = view or ns.view
    local lines = {}
    for _, line in ipairs(ns.lines) do
        if (view == "all" or (line.mode or "v") == view) and (line.state or wantedLine(line)) then lines[#lines + 1] = line end
    end
    return ns.Deals(lines, ns.db.minGain, ns.Money(), ns.db.reserve, ns.FreeSlots(), ns.db.keepFree)
end

-- The lines the player clicked while another purchase ran, in click order. Each one still needs
-- a click of its own (the game buys only inside a click): the big button takes them first.
ns.queue = {}

local function tidyQueue()
    local q, live = ns.queue, {}
    for _, line in ipairs(ns.lines) do live[line] = true end
    for i = #q, 1, -1 do
        if q[i].state or not live[q[i]] or q[i] == ns.buy.line then table.remove(q, i) end
    end
end

-- The place of a line in the queue, or nil.
function ns.QueuePos(line)
    tidyQueue()
    for i, l in ipairs(ns.queue) do if l == line then return i end end
end

-- The scan waits while the player buys: a purchase runs or waits for its click, lines are queued,
-- or a buy click came less than HOLD seconds ago.
function ns.Holding()
    tidyQueue()
    return ns.Busy() or #ns.queue > 0 or time() < (ns.holdUntil or 0)
end

-- The line the big button works on: the one in a purchase, else the first queued, else the best
-- one left.
function ns.Top()
    if ns.buy.line and ns.Busy() then return ns.buy.line end
    tidyQueue()
    if ns.queue[1] then return ns.queue[1] end
    for _, line in ipairs(ns.Shown()) do if not line.state then return line end end
end

-- Lines still to buy: of one list, or of both for the number on the side tab.
function ns.Open(view)
    local n = 0
    for _, line in ipairs(ns.Shown(view or "all")) do if not line.state then n = n + 1 end end
    return n
end

function ns.SetView(view)
    ns.view = view == "d" and "d" or "v"
    refresh()
end

-- ---------- buying ----------
-- The game runs a purchase only inside the player's click. A commodity takes two: the first asks
-- the price (StartCommoditiesPurchase), the second buys at it (ConfirmCommoditiesPurchase). An
-- item's lot is known after the scan, so one click buys it out (PlaceBid with the buyout). It
-- never buys a line whose price came back at or above what the vendor pays. Never call these
-- from an event or a timer.

ns.buy = { phase = "idle" }

function ns.Busy()
    local p = ns.buy.phase
    return p == "quote" or p == "ready" or p == "buying"
end

local function cancelQuote()
    local b = ns.buy
    if b.phase == "ready" and A() and A().CancelCommoditiesPurchase then pcall(A().CancelCommoditiesPurchase) end
end

local function wait(token)
    C_Timer.After(ns.QUOTE_WAIT, function()
        local b = ns.buy
        if b.token == token and (b.phase == "quote" or b.phase == "buying") then
            b.phase, b.err = "idle", "ERR_NO_ANSWER"
            refresh()
        end
    end)
end

-- Purchases sent and not yet confirmed: item lots by auction id, commodities in the order sent.
-- A confirmation that comes after the wait gave up (a lag) is still written to the history.
ns.pending, ns.pendingC = {}, {}

local function bought(line, paid)
    local b = ns.buy
    if b.line == line then b.phase, b.line, b.quote, b.err = "idle", nil, nil, nil end
    if line.state == "bought" then return refresh() end
    ns.Log(line.id, line.n, paid, line.value, line.mode)
    ns.session = (ns.session or 0) + (line.value - paid)
    if (line.left or 1) > 1 then
        -- one of an item's lot is bought: the rest stays, under a new auction id the next search gives
        line.left = line.left - 1
        line.stale = true
        ns.Refetch(line)
    else
        line.state = "bought"
    end
    refresh()
end

-- Search one item again after a purchase, so the rest of its lot can be bought: the auction id
-- just bought is gone. It waits while a purchase or a scan search runs.
function ns.Refetch(line)
    ns.refetchWant = { id = line.id, key = line.key, sell = line.sellEach, mode = line.mode }
    local function try()
        local c = ns.refetchWant
        if not c or not ns.atAH or ns.refetch then return end
        local a = A()
        if ns.Busy() or scan.busy or not ready() or not (a and a.SendSearchQuery) then
            return C_Timer.After(ns.HOLD_STEP, try)
        end
        ns.refetchWant, ns.refetch = nil, c
        ours = true
        local ok = pcall(a.SendSearchQuery, c.key, { { sortOrder = 0, reverseSort = false } }, true)
        ours = false
        if not ok then ns.refetch = nil; return end
        C_Timer.After(ns.SEARCH_WAIT, function() if ns.refetch == c then ns.refetch = nil end end)
    end
    try()
end

-- A click on a line (or the big button on the top line). While another purchase runs or waits
-- for its second click, a click on a line queues it (again: takes it out of the queue).
function ns.Click(line)
    local b = ns.buy
    if not line or line.state or line.stale or not ns.atAH or ns.paused or not A() then return end
    ns.holdUntil = time() + ns.HOLD
    if ns.Busy() and b.line ~= line then
        local pos = ns.QueuePos(line)
        if pos then table.remove(ns.queue, pos) else ns.queue[#ns.queue + 1] = line end
        return refresh()
    end
    if b.phase == "quote" or b.phase == "buying" then return end
    -- the auction house still answers the scan's last question: this click cannot buy yet
    if not ready() then
        if not ns.QueuePos(line) then table.insert(ns.queue, 1, line) end
        b.err, b.errLine = "ERR_WAIT", line
        return refresh()
    end
    local pos = ns.QueuePos(line)
    if pos then table.remove(ns.queue, pos) end
    b.err = nil
    if not ns.Fits(line, ns.Money(), ns.db.reserve, ns.FreeSlots(), ns.db.keepFree) then
        b.err, b.errLine = "ERR_ROOM", line
        refresh()
        return
    end
    -- the last guard: an item's click pays for one, and that one must sell to a vendor for more
    if line.kind == "i" and (line.pay or line.cost) >= (line.sellEach or line.value) then
        line.state = "lose"
        return refresh()
    end
    local token = {}
    b.token = token
    if line.kind == "i" then
        if not A().PlaceBid then return end
        b.phase, b.line = "buying", line
        if not pcall(A().PlaceBid, line.auction, line.pay) then b.phase, b.err = "idle", "ERR_BUY"
        else ns.pending[line.auction] = line; wait(token) end
    elseif b.phase == "ready" then
        b.phase = "buying"
        if not pcall(A().ConfirmCommoditiesPurchase, line.id, line.n) then b.phase, b.err = "idle", "ERR_BUY"
        else
            ns.pendingC[#ns.pendingC + 1] = { line = line, total = b.quote and b.quote.total or line.cost }
            wait(token)
        end
    else
        if not A().StartCommoditiesPurchase then return end
        b.phase, b.line, b.quote = "quote", line, nil
        if not pcall(A().StartCommoditiesPurchase, line.id, line.n) then b.phase, b.err = "idle", "ERR_START" else wait(token) end
    end
    b.errLine = b.err and line or nil
    refresh()
end

function ns.OnAuction(event, a1, a2)
    local b, line = ns.buy, ns.buy.line
    if event == "COMMODITY_PRICE_UPDATED" then
        if b.phase ~= "quote" or not line then return end
        local total = tonumber(a2) or 0
        if total >= line.value then
            -- dearer now than the vendor pays: never buy it
            b.phase = "ready"
            cancelQuote()
            b.phase, b.line, b.quote = "idle", nil, nil
            line.state = "lose"
        else
            b.phase, b.quote = "ready", { unit = a1 or 0, total = total }
        end
    elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
        if b.phase == "quote" and line then line.state = "gone"; b.phase, b.line = "idle", nil end
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
        local p = table.remove(ns.pendingC, 1)
        if p then bought(p.line, p.total) end
    elseif event == "COMMODITY_PURCHASE_FAILED" then
        local p = table.remove(ns.pendingC, 1)
        if p and b.phase == "buying" and line == p.line then b.phase, b.err, b.errLine = "idle", "ERR_BUY", line end
    elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
        local l = a1 and ns.pending[a1]
        if l then ns.pending[a1] = nil; bought(l, l.pay or l.cost) end
    elseif event == "AUCTION_HOUSE_SHOW_ERROR" then
        -- the lot is gone or cannot be bought
        if b.phase == "buying" and line and line.kind == "i" then
            ns.pending[line.auction] = nil
            line.state = "gone"
            b.phase, b.line = "idle", nil
        end
    end
    refresh()
end

-- ---------- history and selling ----------
-- db.history: { at, id, n, paid, value, sold, keep }, newest first. db.owed[char][id]: units
-- bought here to sell to a vendor.

-- A purchase goes into the history. One bought to sell to a vendor is owed to the next vendor;
-- one bought to disenchant (mode "d") is the player's to disenchant, never sold by the module.
function ns.Log(id, n, paid, value, mode)
    local h = ns.db.history
    table.insert(h, 1, { at = time(), id = id, n = n, paid = paid, value = value, sold = 0, who = charKey(),
                         de = mode == "d" or nil })
    while #h > ns.HISTORY_MAX do table.remove(h) end
    if mode == "d" then return end
    local o = ns.Owed()
    o[id] = (o[id] or 0) + n
end

function ns.Owed()
    local key = charKey()
    ns.db.owed[key] = ns.db.owed[key] or {}
    return ns.db.owed[key]
end

-- n units of id were sold to a vendor: the oldest entries of this character count them.
local function markSold(id, n)
    local h, key = ns.db.history, charKey()
    for i = #h, 1, -1 do
        local e = h[i]
        if n <= 0 then break end
        if e.id == id and e.who == key and not e.keep and not e.de and e.sold < e.n then
            local take = math.min(n, e.n - e.sold)
            e.sold, n = e.sold + take, n - take
        end
    end
end

-- A history line the player keeps for themselves: no longer sold.
function ns.Keep(e)
    if not e or e.keep or e.de or e.who ~= charKey() then return end
    e.keep = true
    local o, left = ns.Owed(), e.n - e.sold
    o[e.id] = math.max(0, (o[e.id] or 0) - left)
    if o[e.id] == 0 then o[e.id] = nil end
    refresh()
end

-- The bag slots holding what this character bought to sell: { bag, slot, id, n }, and the copper
-- a vendor pays for them.
function ns.ToSell()
    local o, out, worth, left = ns.Owed(), {}, 0, {}
    for id, n in pairs(o) do left[id] = n end
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        for slot = 1, numSlots(bag) do
            local id, count = slotItem(bag, slot)
            if id and left[id] and left[id] >= (count or 1) and not protected(id) then
                left[id] = left[id] - (count or 1)
                out[#out + 1] = { bag = bag, slot = slot, id = id, n = count or 1 }
                local _, _, _, sell = ns.ItemInfo(id)
                worth = worth + (sell or 0) * (count or 1)
            end
        end
    end
    return out, worth
end

-- Sells what was bought here, a step of SELL_STEP slots at a time while the vendor is open.
function ns.Sell()
    if not ns.atVendor then return end
    local list = ns.ToSell()
    local o = ns.Owed()
    for i = 1, math.min(ns.SELL_STEP, #list) do
        local s = list[i]
        useItem(s.bag, s.slot)
        o[s.id] = (o[s.id] or 0) - s.n
        if o[s.id] <= 0 then o[s.id] = nil end
        markSold(s.id, s.n)
    end
    if #list > ns.SELL_STEP then C_Timer.After(0.3, ns.Sell) end
    refresh()
end

function ns.OfferSale()
    ns.FixGroupedHistory()
    local list, worth = ns.ToSell()
    if #list == 0 then return end
    if ns.db.sell then return ns.Sell() end
    if ns.Skin and ns.Skin.Toast then
        ns.Skin.Toast({ key = "sell", icon = "Interface\\Icons\\INV_Misc_Coin_02", title = L.SELL_TITLE:format(#list),
                        text = L.SELL_TEXT:format(ns.Skin.MoneyText(worth)), seconds = 0,
                        buttons = { { text = L.SELL, primary = true, onClick = function() ns.Sell() end } } })
    end
end

ns.PERIODS = { "day", "week", "all" }
local PERIOD_SECONDS = { day = 86400, week = 7 * 86400 }
-- The history in a period and its totals: profit (value less paid), paid, count.
-- Before 1.4.1 a click on an item's lot (one item bought) was logged as the whole lot: n of them,
-- worth n at a vendor. An item that does not stack was bought one at a time, so such an entry is
-- one item, worth one, and the owed count drops by the rest. Runs until every such item's
-- data was there (`db.groupFix`).
function ns.FixGroupedHistory()
    local db = ns.db
    if not db or db.groupFix then return end
    local done = true
    for _, e in ipairs(db.history or {}) do
        if (e.n or 1) > 1 and not e.fixed then
            local name, _, _, _, stack = ns.ItemInfo(e.id)
            if not name then done = false
            else
                if stack == 1 then
                    local extra = e.n - 1
                    e.value = math.floor(e.value / e.n + 0.5)
                    e.n, e.sold = 1, math.min(e.sold or 0, 1)
                    local o = db.owed and db.owed[e.who]
                    if o and o[e.id] then
                        o[e.id] = o[e.id] - extra
                        if o[e.id] <= 0 then o[e.id] = nil end
                    end
                end
                e.fixed = true
            end
        end
    end
    if done then db.groupFix = 1 end
end

function ns.History(period)
    ns.FixGroupedHistory()
    local out, paid, value = {}, 0, 0
    local since = PERIOD_SECONDS[period] and (time() - PERIOD_SECONDS[period]) or nil
    for _, e in ipairs(ns.db and ns.db.history or {}) do
        if not since or e.at >= since then
            out[#out + 1] = e
            if not e.keep then paid, value = paid + e.paid, value + e.value end
        end
    end
    return out, { count = #out, paid = paid, profit = value - paid,
                  pct = paid > 0 and math.floor((value - paid) * 100 / paid + 0.5) or 0 }
end

-- ---------- settings ----------

function ns.SetPref(key, value)
    if not ns.db then return end
    ns.db[key] = value
    if key == "scan" and value and ns.atAH then scan.next = math.min(scan.next, time()) end
    if key == "interval" and scan.phase == "idle" then scan.next = math.min(scan.next, time() + ns.Interval()) end
    refresh()
end

-- ---------- events ----------

local function listen(frame, events)
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, e in ipairs(events) do
        if not valid or valid(e) then pcall(frame.RegisterEvent, frame, e) end
    end
end

local hooked = false
local function hookQueries()
    local a = A()
    if hooked or not a or not hooksecurefunc then return end
    hooked = true
    for _, fn in ipairs({ "SendBrowseQuery", "SendSearchQuery", "SendSellSearchQuery", "RequestMoreBrowseResults" }) do
        if a[fn] then pcall(hooksecurefunc, a, fn, function() ns.OthersQuery() end) end
    end
end

local ticker
-- The auction house closed (or the player walked away): scanning and buying stop, the window goes.
function ns.AuctionClosed()
    ns.atAH = false
    ns.StopScan()
    if ticker then ticker:Cancel(); ticker = nil end
    local b = ns.buy
    b.phase, b.line, b.quote = "idle", nil, nil
    ns.queue, ns.holdUntil = {}, 0
    ns.refetch, ns.refetchWant = nil, nil
    if ns.HideAtAH then ns.HideAtAH() end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, a2)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliVendorFlipDB = GulliVendorFlipDB or {}
        ns.db = GulliVendorFlipDB
        ns.Migrate(ns.db)
        for k, v in pairs(ns.DEFAULTS) do if ns.db[k] == nil then ns.db[k] = v end end
        ns.db.history = ns.db.history or {}
        ns.db.owed = ns.db.owed or {}
        ns.db.markets = ns.db.markets or {}
        for _, m in pairs(ns.db.markets) do ns.PrunePrices(m, ns.Today()) end
        -- what was saved under an empty realm name joins this character's
        local key = charKey()
        local name = key:match("^(.-)%-")
        local strayKey = name .. "-"
        if key ~= strayKey then
            local stray = ns.db.owed[strayKey]
            if stray then
                local mine = ns.db.owed[key] or {}
                ns.db.owed[key] = mine
                for id, n in pairs(stray) do mine[id] = (mine[id] or 0) + n end
                ns.db.owed[strayKey] = nil
            end
            for _, e in ipairs(ns.db.history) do if e.who == strayKey then e.who = key end end
        end
        listen(self, { "AUCTION_HOUSE_SHOW", "MERCHANT_SHOW",
                       "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
                       "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
                       "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
                       "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE",
                       "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED",
                       "AUCTION_HOUSE_PURCHASE_COMPLETED", "AUCTION_HOUSE_SHOW_ERROR",
                       "BAG_UPDATE_DELAYED", "PLAYER_MONEY", "GET_ITEM_INFO_RECEIVED" })
        -- every way a place closes, walking away too; also while paused
        if ns.Skin and ns.Skin.ClosesWith then
            ns.Skin.ClosesWith("auction", ns.AuctionClosed)
            ns.Skin.ClosesWith("merchant", function() ns.atVendor = false end)
        end
        return
    end
    if ns.paused then return end
    if event == "AUCTION_HOUSE_SHOW" then
        ns.atAH = true
        hookQueries()
        scan.next = time() + 1 -- a moment for the auction window to settle
        if not ticker and C_Timer.NewTicker then ticker = C_Timer.NewTicker(1, ns.Tick) end
        if ns.db.auto and ns.ShowAtAH then ns.ShowAtAH() end
        refresh()
    elseif event == "MERCHANT_SHOW" then
        ns.atVendor = true
        ns.OfferSale()
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
        ns.OnBrowse()
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        ns.OnBrowse(a1)
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        ns.OnThrottleReady()
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_UPDATED" then
        ns.OnSearch(event, a1)
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_MONEY" or event == "GET_ITEM_INFO_RECEIVED" then
        if ns.atAH then refreshSoon() end
    else
        ns.OnAuction(event, a1, a2)
    end
end)

-- ---------- slash command and hub ----------

SLASH_GULLIVENDORFLIP1 = "/gvf"
SlashCmdList.GULLIVENDORFLIP = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "scan" then ns.Scan(true) return end
    if ns.Toggle then ns.Toggle() end
end
function GulliVendorFlip_Toggle() if ns.Toggle then ns.Toggle() end end

ns.OPT_ICON = {
    scan = "Interface\\Icons\\INV_Misc_Spyglass_03",
    auto = "Interface\\Minimap\\Tracking\\Auctioneer",
    sell = "Interface\\Icons\\INV_Misc_Coin_02",
    sound = "Interface\\Icons\\INV_Misc_Bell_01",
    prices = "Interface\\Icons\\INV_Misc_Book_09",
    de = "Interface\\Icons\\INV_Enchant_Disenchant",
    minGain = "Interface\\Icons\\INV_Misc_Coin_01",
    reserve = "Interface\\Icons\\INV_Misc_Bag_11",
    keepFree = "Interface\\Icons\\INV_Misc_Bag_08",
    gear = "Interface\\Icons\\INV_Chest_Chain_05",
    goods = "Interface\\Icons\\INV_Misc_Herb_07",
    soundAt = "Interface\\Icons\\INV_Misc_Coin_04",
    interval = "Interface\\Icons\\INV_Misc_PocketWatch_01",
}

local function option(key)
    return { label = L["OPT_" .. key], icon = ns.OPT_ICON[key], tip = L["TIP_" .. key],
             get = function() return ns.db ~= nil and ns.db[key] == true end,
             set = function(on) ns.SetPref(key, on and true or false) end }
end

-- With the hub: its row and button there; alone: its own minimap button (Skin.lua).
do
    local register = GulliToolkit and GulliToolkit.Register or function(info) ns.alone = info end
    register({
        key = "VendorFlip",
        icon = "Interface\\AddOns\\Gulli-VendorFlip\\icon",
        slash = "/gvf",
        category = "Items",
        open = function() if ns.Toggle then ns.Toggle() end end,
        window = function() return ns.Window and ns.Window() end,
        options = { option("scan"), option("auto"), option("sell") },
        pause = function(on)
            ns.paused = on
            if on then
                ns.StopScan()
                if ns.HideAtAH then ns.HideAtAH() end
            end
        end,
        summary = function()
            if not ns.db then return nil end
            local _, sum = ns.History("day")
            if sum.count == 0 then return nil end
            return L.SUMMARY:format(ns.Skin and ns.Skin.MoneyText(sum.profit, true) or tostring(sum.profit)), ns.OPT_ICON.sell
        end,
        reset = function()
            if not ns.db then return end
            for k, v in pairs(ns.DEFAULTS) do ns.db[k] = v end
            refresh()
        end,
    })
end
