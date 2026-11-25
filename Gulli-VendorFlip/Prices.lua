-- The module's own prices: every scan notes the lowest buyout of each item it saw, one price a
-- day for PRICE_DAYS days, per realm and faction. Other modules read them through the shared
-- price reader of the skin (the global GulliAuction), so they work without another price addon.
-- Also what disenchanting gives at the least. Plain Lua: the tests run it without a game.

local _, ns = ...

ns.PRICE_DAYS = 14    -- daily prices kept for an item
ns.PRICE_DROP = 30    -- days after which an item nobody listed leaves the list
ns.FULL_PAGES = 2000  -- browse pages the Read the whole market button reads at most
ns.DE_CUT = 0.95      -- what is left of a material's auction price after the auction's cut

function ns.Today(now) return math.floor((now or time()) / 86400) end

-- A market is { at = when the whole market was last read, n = items, items = { [id] = entry } },
-- an entry { day, price, quantity, "older,prices,newest,first" }.
function ns.NewMarket() return { n = 0, items = {} } end

-- The lowest buyout of one unit seen now. A later look on the same day replaces the price (it is
-- the market now); the first look of a new day moves the old price into the history.
function ns.NotePrice(market, id, price, qty, day)
    if not (market and id and price and price > 0) then return end
    local e = market.items[id]
    if not e then
        market.items[id] = { day, price, qty or 0, "" }
        market.n = (market.n or 0) + 1
        return
    end
    if e[1] ~= day then
        local kept, n = { tostring(e[2]) }, 1
        for p in (e[4] or ""):gmatch("%d+") do
            if n >= ns.PRICE_DAYS - 1 then break end
            n = n + 1
            kept[n] = p
        end
        e[4] = table.concat(kept, ",")
        e[1] = day
    end
    e[2], e[3] = price, qty or 0
end

-- The price of one and its age in days; nil when the item was never seen.
function ns.PriceOf(market, id, day)
    local e = market and market.items[id]
    if not e then return nil end
    return e[2], math.max(0, (day or ns.Today()) - e[1])
end

-- How many are on sale, as the last look saw it.
function ns.QuantityOf(market, id)
    local e = market and market.items[id]
    return e and e[3] or 0
end

-- The daily prices of an item, newest first.
function ns.PriceDays(market, id)
    local e = market and market.items[id]
    if not e then return {} end
    local out = { e[2] }
    for p in (e[4] or ""):gmatch("%d+") do out[#out + 1] = tonumber(p) end
    return out
end

-- The usual price: the median of the days kept, so one cheap or dear day does not move it.
function ns.NormalOf(market, id)
    local days = ns.PriceDays(market, id)
    if #days == 0 then return nil end
    table.sort(days)
    local mid = math.floor((#days + 1) / 2)
    if #days % 2 == 1 then return days[mid] end
    return math.floor((days[mid] + days[mid + 1]) / 2)
end

-- Items nobody listed for PRICE_DROP days leave, so the saved list does not grow for ever.
function ns.PrunePrices(market, day)
    if not market then return 0 end
    local gone = 0
    for id, e in pairs(market.items) do
        if day - e[1] > ns.PRICE_DROP then market.items[id] = nil; gone = gone + 1 end
    end
    market.n = math.max(0, (market.n or 0) - gone)
    return gone
end

-- ---------- disenchanting ----------
-- What a green or blue weapon or armour piece gives at the least (Vanilla's tiers by item level):
-- { highest item level, dust id, dust count, essence id, essence count, shard id }. A green gives
-- dust or an essence (rarely a shard, not counted), a blue its shard.
ns.DE_TIERS = {
    { 15, 10940, 1, 10938, 1, 10978 }, { 20, 10940, 2, 10939, 1, 10978 }, { 25, 10940, 4, 10998, 1, 10978 },
    { 30, 11083, 1, 11082, 1, 11084 }, { 35, 11083, 2, 11134, 1, 11138 }, { 40, 11137, 1, 11135, 1, 11139 },
    { 45, 11137, 2, 11174, 1, 11177 }, { 50, 11176, 1, 11175, 1, 11178 }, { 55, 11176, 2, 16202, 1, 14343 },
    { 60, 16204, 1, 16203, 1, 14344 }, { 65, 16204, 2, 16203, 2, 14344 },
}
ns.DE_MIN_LEVEL = 5

-- The least one disenchant brings, in copper after the auction's cut: for a green the cheaper of
-- its dust and its essence (both must have a price), for a blue its shard. nil when the item
-- cannot be disenchanted, its tier is not known or a material has no price. priceOf(id) is the
-- auction price of one.
function ns.DisenchantFloor(quality, ilvl, priceOf)
    if not ilvl or ilvl < ns.DE_MIN_LEVEL or (quality ~= 2 and quality ~= 3) then return nil end
    for _, t in ipairs(ns.DE_TIERS) do
        if ilvl <= t[1] then
            local worth
            if quality == 3 then
                worth = priceOf(t[6])
            else
                local dust, essence = priceOf(t[2]), priceOf(t[4])
                if not dust or not essence then return nil end
                worth = math.min(dust * t[3], essence * t[5])
            end
            if not worth or worth <= 0 then return nil end
            return math.floor(worth * ns.DE_CUT)
        end
    end
    return nil
end
