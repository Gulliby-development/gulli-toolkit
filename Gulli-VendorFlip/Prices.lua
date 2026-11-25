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
-- What one disenchant brings, in copper after the auction's cut: the skin's table shared by every
-- module (S.DisenchantWorth: a green on the safe side, 85/13/2 for armour and 50/48/2 for a
-- weapon; a blue its shard; a purple three shards or a Nexus Crystal). nil when the item cannot be
-- disenchanted or a material it needs has no price. priceOf(id) is the auction price of one;
-- `class` the item class (2 a weapon, else armour).
function ns.DisenchantFloor(quality, ilvl, priceOf, class)
    local S = ns.Skin
    local worth = S and S.DisenchantWorth and S.DisenchantWorth(quality, ilvl, class or 4, priceOf, ns.DE_CUT)
    return worth and math.floor(worth) or nil
end
