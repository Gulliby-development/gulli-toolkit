-- The rules of Gulli-CraftProfit: what an item is worth, what a craft earns and which way to
-- level a profession. Everything here works on a plain "state" table, so the tests run it
-- without a game; Scan.lua builds that state from the game and Auctionator.
--
-- state = {
--   skill, cap, level,                    -- the profession's skill, its rank cap, the character level
--   items = { [id] = { name, ah, age, vend, buy, bags, bank, bop, mail, alts, altWho, gather, lots } },
--   recipes = { [rid] = { name, skill = { orange, yellow, grey }, r = { [id] = n }, out, count,
--                         learned, src = { t = "trainer"|"vendor"|"ah"|"rep"|"spec"|..., cost }, guess,
--                         skip } },  -- skip: the player does not want this craft in any route
-- }
-- Prices are in copper. Green starts halfway between yellow and grey, as in the game.

local ADDON, ns = ...

-- The separator between parts of a line: a dot texture (S.DOT), since the game's fonts lack "·".
function ns.Dot() return ns.Skin and ns.Skin.DOT or ", " end
local L = ns.L

-- Settings a player picks in the right column. A new one gets a default here, a control in
-- UI.lua, its texts in every language and a test that toggling it rebuilds the route.
ns.DEFAULTS = {
    mode = "auto", -- levelling: auto (the fastest within the budget) or l1..l4; profit only: own or earn
    budget = 0, -- copper the levelling may lose; 0: no limit
    maxCrafts = 0, -- crafts the whole way may take; 0: auto (the skill points + 5), -1: no limit
    level = true, -- off: no levelling routes, only the profit one
    target = 0,       -- 0: the rank cap
    useBags = true, useBank = true, buyAH = true, buyVendor = true,
    buyRecipes = true, trainer = true,
    sellAH = true, neutral = false, chance = 80, maxSell = 20, freshOnly = true,
    maxBuy = 40, -- units of one item a profit run buys at the auction: only a few sell at that price
    useMail = true, -- items waiting in the mailbox count as own
    useAlts = false, -- items on the other characters (Gulli Chores) count as own, sent by mail
    ahead = true, -- the first run's buy stops also buy what the later runs of the way need
    guard = 10, -- percent an auction price may be above the plan before the Buy button asks first; -1: never ask
    side = true, -- at the auction house the run's buy stop opens in the window beside it
    minGain = 500, -- copper a profit craft must gain at least; 0: any gain
    autoPin = true, -- the route pins itself at the first purchase or craft (Pin.lua)
    disenchant = false, -- an enchanter may disenchant crafted gear and sell the materials at the auction
}
-- Settings that change no plan: the window only redraws.
ns.NO_PLAN = { guard = true, side = true, ahead = true, autoPin = true }

ns.CUT, ns.NEUTRAL_CUT = 0.05, 0.15
ns.FRESH_DAYS = 3
-- What a craft is worth in time, in copper, by mode: speed counts crafts before money.
ns.TIME = { money = 0, balance = 300, speed = 1e6 }
-- The routes the window offers side by side, in tab order.
ns.MODES = { "l1", "l2", "l3", "l4", "own", "earn" }
-- Time weights tried for the levelling routes: from money only to speed only.
ns.SWEEP = { 0, 30, 100, 300, 1000, 3000, 1e6 }
ns.LEVEL_ROUTES = 4
-- Saved choices from before the routes were computed.
ns.OLD_MODES = { money = "l1", balance = "auto", speed = "l4" }
-- The two profit routes: "own" crafts from the bags and the bank (vendor thread and dye allowed),
-- "earn" may also buy reagents at the auction and buy recipes when they pay back.
ns.EARN = { own = true, earn = true }
-- A change of recipe costs a little, so the plan does not hop between two recipes for a point.
ns.SWITCH = 600
-- The most crafts of the product one profit run plans, fixed (owner's decision of 2026-11-20):
-- crafted, the next run is planned anew, so a cheap recipe never asks for thousands.
ns.EARN_MAX = 50
-- Crafts the game allows once per cooldown, recipe spell -> seconds (Classic's cooldowns; a
-- cooldown the game shows for another recipe is learned in Scan.lua). A route takes such a craft
-- at most once, and only while it is ready: levelling on them would take days.
local DAY = 86400
ns.DAY = DAY
ns.COOLDOWNS = {
    [18560] = 4 * DAY,                               -- Mooncloth
    [19047] = 3 * DAY,                               -- Cured Rugged Hide
    [11479] = 2 * DAY, [11480] = 2 * DAY,            -- Transmute: Iron to Gold, Mithril to Truesilver
    [17187] = 2 * DAY,                               -- Transmute: Arcanite
    [17559] = DAY, [17560] = DAY, [17561] = DAY, [17562] = DAY, -- the elemental transmutes
    [17563] = DAY, [17564] = DAY, [17565] = DAY, [17566] = DAY,
    [25146] = DAY,                                   -- Transmute: Elemental Fire
    [1317279] = DAY,                                 -- Transmute: Legionite (WoW Forever)
}
-- How many crafts of a recipe the game allows now: all for a recipe without a cooldown, else one
-- while it is ready (`cdReady`: when it is, from the game) and none before.
function ns.CdLeft(state, r)
    if not r.cd then return math.huge end
    if r.cdReady and r.cdReady > (state.now or 0) then return 0 end
    return 1
end
-- Rank caps: the cap, the skill the trainer teaches it from, the level it needs, its cost.
ns.RANKS = { { 75, 0, 5, 10 }, { 150, 50, 10, 500 }, { 225, 125, 20, 10000 }, { 300, 200, 35, 50000 } }

-- What a trainer asks for a recipe before any trainer window was open: the most a recipe of
-- that skill costs (skill below -> copper). The price seen at a trainer is kept for good and
-- replaces it.
ns.TRAINER_GUESS = { { 75, 5000 }, { 150, 10000 }, { 225, 20000 }, { math.huge, 25000 } }
function ns.TrainerGuess(skill)
    skill = skill or 0
    for _, t in ipairs(ns.TRAINER_GUESS) do
        if skill < t[1] then return t[2] end
    end
end

-- Kinds of stops on the route, in walking order. A new kind gets a colour and a test.
ns.STOPS = {
    bank = { 0.71, 0.55, 1.00 }, ah = { 0.95, 0.79, 0.30 }, vendor = { 0.36, 0.82, 0.48 },
    trainer = { 0.25, 0.78, 0.92 }, craft = { 1.00, 0.62, 0.26 }, sell = { 0.95, 0.79, 0.30 },
    mail = { 0.83, 0.75, 0.55 }, gather = { 0.45, 0.80, 0.35 },
}
-- Auction lots a ladder price may use: newer than this, in seconds.
ns.LOTS_FRESH = 24 * 3600
ns.COLORS = { or_ = { 1, 0.5, 0.25 }, ye = { 1, 0.84, 0.25 }, gr = { 0.25, 0.75, 0.25 }, gy = { 0.55, 0.55, 0.55 } }

local function ceil(n) return math.ceil(n - 1e-9) end
ns.Ceil = ceil

-- Merges saved settings over the defaults; a missing key takes its default.
function ns.Prefs(saved)
    local p = {}
    for k, v in pairs(ns.DEFAULTS) do p[k] = v end
    for k, v in pairs(saved or {}) do if ns.DEFAULTS[k] ~= nil then p[k] = v end end
    -- the simulation's own copy: the settings that mean nothing for a new character are fixed
    if ns.sim and saved == ns.sim.prefs and ns.SIM_FIXED then
        for k, v in pairs(ns.SIM_FIXED) do p[k] = v end
    end
    return p
end

-- ---------- what an item is worth ----------

function ns.Fresh(it, P)
    return it.ah ~= nil and it.ah > 0 and (not P.freshOnly or (it.age or 0) <= ns.FRESH_DAYS)
end

-- The deposit the auction keeps when an item does not sell. The game tells it only with the
-- auction open, so this is an estimate from the vendor price.
function ns.Deposit(it) return math.floor((it.vend or 0) * 0.3 + 0.5) end

-- A count setting where 0 (or none) means no limit.
function ns.Limit(v) return (v and v > 0) and v or math.huge end

-- How many of one item the auction takes: maxSell, and never more than are on sale there now
-- when the lots were read (a market of 12 does not take 300 more).
function ns.MarketTake(state, P, id)
    local m = ns.Limit(P.maxSell)
    local it = state.items[id]
    local lots = it and it.lots
    if lots and lots.l and (not state.now or state.now - (lots.t or 0) <= ns.LOTS_FRESH) then
        local n = 0
        for _, l in ipairs(lots.l) do n = n + (l[2] or 0) end
        if n > 0 then m = math.min(m, n) end
    end
    return m
end

-- Value of one unit put up for sale. `sold`: how many the plan already lists; past what the
-- market takes the rest goes to a vendor. Returns the value and "ah" or "vendor".
-- Items that are reagents of some recipe of the book (bolts, bars, Mooncloth): crafters buy
-- them all the time, so they always sell at the auction (owner's request of 2026-11-24). The
-- share that sells (`chance`) is for finished goods only.
local reagents
function ns.IsReagent(id)
    if not reagents then
        reagents = {}
        for _, rows in pairs(ns.Data and ns.Data.book or {}) do
            for _, row in ipairs(rows) do
                for k = 9, #row, 2 do reagents[row[k]] = true end
            end
        end
    end
    return reagents[id] == true
end

-- The share of an item that sells at the auction: all of a reagent, else the setting.
function ns.SellChance(P, id)
    if ns.IsReagent(id) then return 1 end
    return P.chance / 100
end

local function sellValue(state, P, id, sold)
    local it = state.items[id] or {}
    local vend = it.vend or 0
    if it.bop or not P.sellAH or not ns.Fresh(it, P) or (sold or 0) >= ns.MarketTake(state, P, id) then return vend, "vendor" end
    local p = ns.SellChance(P, id)
    local cut = P.neutral and ns.NEUTRAL_CUT or ns.CUT
    local ev = p * it.ah * (1 - cut) + (1 - p) * (vend - ns.Deposit(it))
    if ev > vend then return ev, "ah" end
    return vend, "vendor"
end

-- Selling, or with `disenchant` (an enchanter only) disenchanting when the materials bring more:
-- "vendor", "ah" or "de".
function ns.SellValue(state, P, id, sold)
    local v, how = sellValue(state, P, id, sold)
    if P.disenchant and state.enchanter then
        local de = ns.DisenchantValue(state, P, id)
        if de and de > v then return de, "de" end
    end
    return v, how
end

-- ---------- disenchanting ----------

-- What disenchanting gives, by the item's level (the Vanilla tables). Green: { up to item level,
-- dust, dust per item, essence, essence per item, shard or nil }; armour gives dust 75%, essence
-- 20%, a shard 5%; a weapon the dust and the essence the other way round. Blue: one shard.
ns.DE_GREEN = {
    { 15, 10940, 1.5, 10938, 1.5 },
    { 20, 10940, 2.5, 10939, 1.5, 10978 },
    { 25, 10940, 5, 10998, 1.5, 10978 },
    { 30, 11083, 1.5, 11082, 1.5, 11084 },
    { 35, 11083, 3.5, 11134, 1.5, 11138 },
    { 40, 11137, 1.5, 11135, 1.5, 11139 },
    { 45, 11137, 3.5, 11174, 1.5, 11177 },
    { 50, 11176, 1.5, 11175, 1.5, 11178 },
    { 55, 11176, 3.5, 16202, 1.5, 14343 },
    { 60, 16204, 1.5, 16203, 1.5, 14344 },
    { 999, 16204, 3.5, 16203, 2.5, 14344 },
}
ns.DE_BLUE = { { 25, 10978 }, { 30, 11084 }, { 35, 11138 }, { 40, 11139 }, { 45, 11177 }, { 50, 11178 },
               { 55, 14343 }, { 999, 14344 } }
local GEAR = { [2] = true, [4] = true }

-- The materials one disenchant of an item gives on average: { { id, n } }; nil for anything but
-- green or blue weapons and armour (the item's `class`, `quality` and `ilvl` from the scan).
function ns.DisenchantMats(it)
    if not (it and GEAR[it.class] and it.ilvl and it.ilvl > 0) then return nil end
    if it.quality == 2 then
        for _, t in ipairs(ns.DE_GREEN) do
            if it.ilvl <= t[1] then
                local weapon = it.class == 2
                local dust, ess = weapon and 0.2 or 0.75, weapon and 0.75 or 0.2
                local out = { { t[2], dust * t[3] }, { t[4], ess * t[5] } }
                if t[6] then out[3] = { t[6], 0.05 } end
                return out
            end
        end
    elseif it.quality == 3 then
        for _, t in ipairs(ns.DE_BLUE) do
            if it.ilvl <= t[1] then return { { t[2], 1 } } end
        end
    end
end

-- What one disenchant brings at the auction after its cut; nil while a material has no price.
-- A material without a fresh price counts nothing, so the guess stays low.
function ns.DisenchantValue(state, P, id)
    local mats = ns.DisenchantMats(state.items[id])
    if not mats then return nil end
    local cut = P.neutral and ns.NEUTRAL_CUT or ns.CUT
    local sum, any = 0, false
    for _, m in ipairs(mats) do
        local it = state.items[m[1]]
        if it and ns.Fresh(it, P) then sum, any = sum + m[2] * it.ah * (1 - cut), true end
    end
    return any and sum or nil
end

-- The cheapest way to buy one unit: "vendor" or "ah", or nil when it cannot be bought.
function ns.BuyOption(state, P, id)
    local it = state.items[id] or {}
    local v, how
    if P.buyVendor and it.buy then v, how = it.buy, "vendor" end
    -- `ahBought`: what this run already bought there; buying stops once it reaches maxBuy
    local room = not P.ahBought or (P.ahBought[id] or 0) < ns.Limit(P.maxBuy)
    if P.buyAH and room and ns.Fresh(it, P) and (not v or it.ah < v) then v, how = it.ah, "ah" end
    -- no usable auction price: a guess, so a route always exists (the line says it is a guess)
    if P.buyAH and room and not v then
        local g = ns.Guess(it, P)
        if g then v, how = g, "ah" end
    end
    return v, how
end

-- The auction price of an item no fresh price is known for: an old price when there is one,
-- else its vendor sell price times ns.AH_GUESS (trade goods sell for several times that).
-- Nil for an item that cannot be traded or has no sell price.
ns.AH_GUESS = 5
function ns.Guess(it, P)
    if ns.Fresh(it, P) or it.bop then return nil end
    if it.ah and it.ah > 0 then return it.ah end
    if (it.vend or 0) > 0 then return it.vend * ns.AH_GUESS end
end

-- Own items the plan may use: { [id] = { bags = n, bank = n } }.
function ns.Stock(state, P)
    local st = {}
    for id, it in pairs(state.items) do
        local b = P.useBags and (it.bags or 0) or 0
        local k = P.useBank and (it.bank or 0) or 0
        local m = P.useMail and (it.mail or 0) or 0
        local a = P.useAlts and (it.alts or 0) or 0
        -- an item the player gathers never runs out; it costs what it would sell for
        local g = it.gather and math.huge or 0
        if b + k + m + a + g > 0 then st[id] = { bags = b, bank = k, mail = m, alts = a, gather = g } end
    end
    return st
end
local function left(st, id)
    local s = st[id]
    return s and (s.bags + s.bank + s.mail + s.alts + s.gather) or 0
end

-- Which recipe makes an item, among the recipes the plan may use.
-- The makers of each item are indexed once per recipes table: a scan over every recipe here
-- ran for each reagent at each skill point and froze the game on a big profession.
local makers = setmetatable({}, { __mode = "k" })
local function maker(state, known, id)
    local idx = makers[state.recipes]
    if not idx then
        idx = {}
        for rid, r in pairs(state.recipes) do
            -- a cooldown craft never makes intermediates: one a few days is no supply
            if r.out and (r.count or 1) == 1 and r.learned and not r.cd then
                idx[r.out] = idx[r.out] or {}
                table.insert(idx[r.out], rid)
            end
        end
        for _, l in pairs(idx) do table.sort(l, function(a, b) return tostring(a) < tostring(b) end) end
        makers[state.recipes] = idx
    end
    for _, rid in ipairs(idx[id] or {}) do if known[rid] then return rid end end
end
-- A recipes table changed in place (tests, a new scan) gets a new index.
function ns.ForgetMakers(recipes) makers[recipes] = nil end

-- The cost of one unit now: own stock is worth what it would sell for.
local reagentCost
local function unitCost(state, P, st, known, id, depth)
    local best, how = math.huge, nil
    if left(st, id) > 0 then best, how = ns.SellValue(state, P, id, 0), "own" end
    local b, bh = ns.BuyOption(state, P, id)
    if b and b < best then best, how = b, bh end
    if (depth or 0) < 2 then
        local rid = maker(state, known, id)
        if rid then
            local c = reagentCost(state, P, st, known, rid, (depth or 0) + 1)
            if c < best then best, how = c, "craft" end
        end
    end
    return best, how
end
ns.UnitCost = unitCost

reagentCost = function(state, P, st, known, rid, depth)
    local sum = 0
    for id, n in pairs(state.recipes[rid].r) do sum = sum + n * unitCost(state, P, st, known, id, depth) end
    return sum
end
ns.ReagentCost = reagentCost

-- ---------- skill-up chance ----------

-- "or_", "ye", "gr", "gy", or nil while the recipe is above the skill.
function ns.Color(r, s)
    if not r.skill then return nil end
    local o, y, g = r.skill[1], r.skill[2], r.skill[3]
    if s < o then return nil end
    if s < y then return "or_" end
    if s < (y + g) / 2 then return "ye" end
    if s < g then return "gr" end
    return "gy"
end

-- The chance a craft raises the skill: always while orange, then (grey - skill) / (grey - yellow).
-- Blizzard never published it; this is the formula players measured.
function ns.Chance(r, s)
    local o, y, g = r.skill[1], r.skill[2], r.skill[3]
    if s < o or s >= g then return 0 end
    if s < y then return 1 end
    return (g - s) / (g - y)
end

-- The skill where a recipe turns yellow, green and grey ({ orange, yellow, grey } as
-- ns.Thresholds gives): green starts where ns.Color says so.
function ns.Levels(sk)
    local y, g = sk[2], sk[3]
    return y, math.ceil((y + g) / 2 - 1e-9), g
end

-- Yellow to grey in the data: 20 points is the most common gap, so a recipe without data
-- gets it too. A shorter gap would make the guess ask for far more crafts than the game does.
ns.GAP = 20

-- The game shows only the colour a recipe has at the current skill (0 orange, 1 yellow, 2 green,
-- 3 grey). For a recipe Data.lua does not know, this guesses { orange, yellow, grey } from the
-- colours seen at several skills, `obs` = { [skill] = colour }; `grey` from the game
-- (maxTrivialLevel) fixes the last one.
function ns.Estimate(obs, grey)
    local loY, hiY, loG, hiG = -math.huge, math.huge, -math.huge, math.huge
    local any = false
    for s, c in pairs(obs or {}) do
        any = true
        if c == 0 then loY = math.max(loY, s + 1)
        elseif c == 1 then hiY = math.min(hiY, s); loG = math.max(loG, s + 2)
        elseif c == 2 then hiY = math.min(hiY, s - 1); loG = math.max(loG, s + 1)
        elseif c == 3 then hiG = math.min(hiG, s) end
    end
    -- the game's grey, unless the window showed the recipe grey below it (as ns.Thresholds)
    if grey and grey > 0 then loG, hiG, any = math.min(grey, hiG), math.min(grey, hiG), true end
    if not any then return nil end
    local y
    if loY > -math.huge then y = math.min(loY, hiY)
    elseif hiY < math.huge then y = hiY
    elseif hiG < math.huge then y = hiG - ns.GAP
    else y = loG - ns.GAP end
    local g = math.max(loG, y + ns.GAP)
    if hiG < math.huge then g = math.min(g, hiG) end
    if g <= y then g = y + 1 end
    return { y - 10, y, g }
end

-- { orange, yellow, grey } of a recipe: the levels from Data.lua (`d` = { yellow, green, grey },
-- or { orange, yellow, green, grey }), moved where the game showed another colour, since the
-- game is right about its own recipes. Without data, the guess from the colours. The second
-- value is true for a guess. A learned recipe is orange from 0: it can always be crafted.
function ns.Thresholds(d, obs, grey, learned)
    if not d then
        local e = ns.Estimate(obs, grey)
        if e and learned then e[1] = 0 end
        return e, true
    end
    local o, y, gr, g
    if #d >= 4 then o, y, gr, g = d[1], d[2], d[3], d[4] else y, gr, g = d[1], d[2], d[3] end
    -- the game's grey wins; WoW Forever moved whole recipes, so the other levels move with it
    -- (Stormcloth Headband: 255/270/285 in the data, grey at 245 in the game)
    if grey and grey > 0 and grey ~= g then
        local dlt = grey - g
        y, g = y + dlt, grey
        if o and o > 1 then o = o + dlt end
    end
    local ks = {}
    for s in pairs(obs or {}) do ks[#ks + 1] = s end
    table.sort(ks)
    for _, s in ipairs(ks) do
        local c = obs[s]
        local green = (y + g) / 2
        if c == 0 and y <= s then g = g + (s + 1 - y); y = s + 1
        elseif c == 1 and y > s then y = s
        elseif c == 1 and s >= green then g = 2 * s - y + 2
        elseif c == 2 and s >= g then g = s + 1
        elseif c == 2 and s < green then y = math.min(y, 2 * s - g)
        elseif c == 3 and g > s then g = s; y = math.min(y, g - 1) end
    end
    if g <= y then g = y + 1 end
    o = learned and 0 or math.min(o and o > 1 and o or y - 10, y)
    return { o, y, g }, false
end

function ns.CanGet(r, P)
    -- a craft the player took out of the routes is never used, learned or not
    if r.skip then return false end
    if r.learned then return true end
    local t = r.src and r.src.t
    if t == "trainer" then return P.trainer end
    if t == "vendor" then return P.buyRecipes and P.buyVendor end
    if t == "ah" then return P.buyRecipes and P.buyAH end
    return false
end

-- ---------- the plan ----------

local function add(m, k, n) if n > 1e-9 then m[k] = (m[k] or 0) + n end end

-- Takes n units of an item: own stock first (bags, then bank), then the cheaper of buying and crafting.
local function take(state, P, st, known, acc, id, n, depth)
    local s = st[id]
    if s then
        local a = math.min(n, s.bags); s.bags = s.bags - a; n = n - a; add(acc.bags, id, a)
        local b = math.min(n, s.bank); s.bank = s.bank - b; n = n - b; add(acc.bank, id, b)
        local used = a + b
        for _, pool in ipairs({ "mail", "alts", "gather" }) do
            local c = math.min(n, s[pool] or 0)
            if c > 0 then
                s[pool] = s[pool] - c; n = n - c; used = used + c
                acc[pool] = acc[pool] or {}
                add(acc[pool], id, c)
            end
        end
        if used > 0 then acc.own = acc.own + used * ns.SellValue(state, P, id, 0) end
    end
    if n <= 1e-9 then return end
    local b, how = ns.BuyOption(state, P, id)
    local rid = (depth or 0) < 2 and maker(state, known, id)
    local craft = rid and reagentCost(state, P, st, known, rid, (depth or 0) + 1) or math.huge
    local make = craft < (b or math.huge)
    -- a pinned route keeps where each item came from when it was pinned, while that still works
    local forced = P.pin and P.pin.how and P.pin.how[id]
    if forced == "craft" and rid and craft < math.huge then make = true
    elseif forced == "buy" and b then make = false end
    if make then
        add(acc.prep, rid, n)
        for rid2, k in pairs(state.recipes[rid].r) do take(state, P, st, known, acc, rid2, k * n, (depth or 0) + 1) end
        return
    end
    if not b then acc.missing[id] = true; return end
    if how == "ah" and not ns.Fresh(state.items[id] or {}, P) then
        acc.guess = acc.guess or {}
        acc.guess[id] = b
    end
    add(how == "ah" and acc.ahBuy or acc.vendorBuy, id, n)
    acc.spend = acc.spend + n * b
end

local function rankAbove(cap)
    for _, r in ipairs(ns.RANKS) do if r[1] > cap then return r end end
end

-- The rank cap; a cap the game did not give (0, or below the skill) is the rank the skill is in.
function ns.Cap(state)
    local s, cap = state.skill, state.cap or 0
    if cap > 0 and cap >= s then return cap end
    for _, r in ipairs(ns.RANKS) do if r[1] >= s then return r[1] end end
    return math.max(cap, s)
end

function ns.Target(state, P)
    if P.target and P.target > state.skill then return P.target end
    return ns.Cap(state)
end

-- The most crafts a levelling route may take, or nil for no limit. Auto follows the target:
-- the skill points to go plus ns.CRAFTS_SPARE. Only the crafts that raise the skill count
-- (ns.LevelCrafts): smelting and other preparation is shown beside them, never limited.
ns.CRAFTS_SPARE = 5
function ns.LevelCrafts(p)
    return p.level or (p.crafts - (p.prepCrafts or 0))
end

function ns.CraftCap(state, P)
    -- the simulation asks what a profession costs, not how many clicks: no limit at all
    -- (owner's decision of 2026-11-23)
    if state.sim then return nil end
    local m = P.maxCrafts or 0
    if m < 0 then return nil end
    if m > 0 then return m end
    return math.max(0, ns.Target(state, P) - state.skill) + ns.CRAFTS_SPARE
end

-- Why a stretch of the route crafts its recipe: the planner's own reasons at the stretch's first
-- point, as { key, args... } entries for the window (WHY_<key> texts), and the next best recipes
-- with what they would cost more per point. Built from the same numbers the choice used.
ns.WHY_ALTS = 2
local POOLS = { "bags", "bank", "mail", "alts", "gather" }
function ns.Why(state, P, st, known, best, cands, w, s0)
    local r = state.recipes[best.rid]
    local out = { reasons = {}, alts = {} }
    local function why(...) out.reasons[#out.reasons + 1] = { ... } end
    if not best.earn then
        if best.ch >= 1 then why("ORANGE") else why("CHANCE", math.floor(best.ch * 100 + 0.5), best.n) end
    end
    if r.cd then why("CD") end
    -- where the reagents come from: the cheapest way of each, as the plan takes them
    local from = {}
    local ids = {}
    for id in pairs(r.r) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
    for _, id in ipairs(ids) do
        local _, how = unitCost(state, P, st, known, id)
        if how == "own" then
            local s = st[id]
            for _, pool in ipairs(POOLS) do
                if s and (s[pool] or 0) > 0 then how = pool; break end
            end
        end
        if how then
            from[how] = from[how] or {}
            table.insert(from[how], id)
        end
    end
    for _, how in ipairs({ "bags", "bank", "mail", "alts", "gather", "own", "craft", "vendor", "ah" }) do
        if from[how] then why("FROM_" .. how, from[how]) end
    end
    if best.value > 0 then why(best.how == "ah" and "SELL_AH" or best.how == "de" and "SELL_DE" or "SELL_VENDOR", best.value) end
    if best.earn then why("GAIN", -best.cost)
    elseif best.cost < 0 then why("EARN", -best.cost) else why("COST", best.cost) end
    if not r.learned and r.src and (r.src.cost or 0) > 0 then why("RECIPE_" .. (r.src.t or "trainer"), r.src.cost) end
    -- the others, best first: those the choice beat, and why a cheaper one lost
    local others = {}
    for _, c in ipairs(cands) do if c.rid ~= best.rid then others[#others + 1] = c end end
    table.sort(others, function(a, b)
        if math.abs(a.score - b.score) > 1e-9 then return a.score < b.score end
        return tostring(a.rid) < tostring(b.rid)
    end)
    if best.earn then
        -- a profit run weighs whole series; ns.Earn adds the other recipes it tried
    elseif #others == 0 then
        why("ONLY")
    else
        local cheaper
        for _, c in ipairs(others) do if c.cost < best.cost - 1 then cheaper = c; break end end
        -- a recipe that costs less gold lost on time: the route counts each craft (fewer crafts)
        if cheaper and w > 0 and cheaper.n > best.n + 1e-9 then why("FAST", cheaper.rid, best.cost - cheaper.cost)
        elseif not cheaper then why("CHEAPEST", others[1].cost - best.cost) end
    end
    for i = 1, math.min(ns.WHY_ALTS, #others) do
        local c = others[i]
        local cr = state.recipes[c.rid]
        out.alts[#out.alts + 1] = { rid = c.rid, cost = c.cost, more = c.cost - best.cost, n = c.n, color = ns.Color(cr, s0 or state.skill),
                                    buy = not cr.learned or nil }
    end
    return out
end

-- One pass: at each skill point the recipe with the lowest expected cost per point (plus time
-- by mode). `allowed`: the recipes it may use.
local function planWith(state, P, allowed)
    local st = ns.Stock(state, P)
    local acc = { bags = {}, bank = {}, ahBuy = {}, vendorBuy = {}, prep = {}, missing = {}, made = {},
                  segs = {}, buyRecipes = {}, spend = 0, own = 0, crafts = 0, cdUsed = {} }
    local s, cap, target = state.skill, ns.Cap(state), ns.Target(state, P)
    local w = P.w or ns.TIME[P.mode] or 0
    -- a sorted list keeps the plan the same from run to run
    -- only recipes that can raise the skill somewhere on the way; the rest still make intermediates
    local ids = {}
    for rid in pairs(allowed) do
        local sk = state.recipes[rid].skill
        if sk and sk[3] > s and sk[1] < target then ids[#ids + 1] = rid end
    end
    table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
    while s < target do
        ns.Tick()
        if s >= cap then
            local nxt = rankAbove(cap)
            if not P.trainer then acc.warn = { "WARN_TRAINER", cap }; break end
            if not nxt or (state.level or 0) < nxt[3] then acc.warn = { "WARN_LEVEL", cap, nxt and nxt[3] or 0 }; break end
            acc.rank = { at = nxt[2], cap = nxt[1], level = nxt[3], cost = nxt[4] }
            acc.spend = acc.spend + nxt[4]
            acc.rankCost = (acc.rankCost or 0) + nxt[4]
            cap = nxt[1]
        else
            local best
            local last = acc.segs[#acc.segs]
            -- every recipe that could take this point, for the reasons a stretch shows (ns.Why)
            local cands = {}
            -- a pinned route: the recipe it had at this skill, while that recipe can still take the point
            local want, pinned = P.pin and ns.PinRecipeAt(P.pin, s), nil
            for _, rid in ipairs(ids) do
                local r = state.recipes[rid]
                local ch = ns.Chance(r, s)
                -- a cooldown craft: once, and only a skill point it makes for sure
                if ch > 0 and r.cd and 1 / ch > ns.CdLeft(state, r) - (acc.cdUsed[rid] or 0) + 1e-9 then ch = 0 end
                if ch > 0 then
                    local n = 1 / ch
                    local value, how = 0, nil
                    if r.out then value, how = ns.SellValue(state, P, r.out, acc.made[r.out] or 0); value = value * (r.count or 1) end
                    local rc = reagentCost(state, P, st, allowed, rid)
                    local cost = n * (rc - value)
                    if cost < math.huge then
                        local raw = cost + n * w
                        -- in the simulation every recipe is still to learn: its price counts in the
                        -- choice, spread over the points it is good for (ns.Plan would otherwise try
                        -- the plan again without each of them, which takes minutes there)
                        local once = 0
                        if state.sim and not r.learned and not acc.buyRecipes[rid] then
                            local sk = r.skill
                            once = (r.src.cost or 0) / math.max(1, math.min(target, math.floor((sk[2] + sk[3]) / 2)) - s)
                        end
                        local c = { rid = rid, n = n, ch = ch, rc = rc, value = value, how = how, cost = cost, raw = raw,
                                    score = raw + once + ((last and last.rid ~= rid) and ns.SWITCH or 0) }
                        cands[#cands + 1] = c
                        -- `only`: a run of one recipe; the others still make its intermediates
                        if (not P.only or P.only == rid) and (not best or c.score < best.score - 1e-9) then best = c end
                        if want == rid and (not P.only or P.only == rid) then pinned = c end
                    end
                end
            end
            if not best then acc.warn = { "WARN_NONE", s }; break end
            best = pinned or best
            local r = state.recipes[best.rid]
            local why
            if not (last and last.rid == best.rid and last.to == s) then why = ns.Why(state, P, st, allowed, best, cands, w, s) end
            for id, k in pairs(r.r) do take(state, P, st, allowed, acc, id, k * best.n) end
            if r.out then add(acc.made, r.out, best.n * (r.count or 1)) end
            acc.crafts = acc.crafts + best.n
            acc.level = (acc.level or 0) + best.n
            if r.cd then acc.cdUsed[best.rid] = (acc.cdUsed[best.rid] or 0) + best.n end
            if not r.learned then acc.buyRecipes[best.rid] = true end
            if last and last.rid == best.rid and last.to == s then
                last.to = s + 1; last.n = last.n + best.n
            else
                acc.segs[#acc.segs + 1] = { rid = best.rid, from = s, to = s + 1, n = best.n, color = ns.Color(r, s), why = why }
            end
            s = s + 1
        end
    end
    acc.reached, acc.target = s, target
    -- what learning costs on the way (recipes, patterns, ranks), for the simulation's totals
    acc.learnCost = acc.rankCost or 0
    for rid in pairs(acc.buyRecipes) do
        local c = state.recipes[rid].src.cost or 0
        acc.spend, acc.learnCost = acc.spend + c, acc.learnCost + c
    end
    acc.level, acc.prepCrafts = acc.level or 0, 0
    for _, n in pairs(acc.prep) do acc.crafts = acc.crafts + n; acc.prepCrafts = acc.prepCrafts + n end
    acc.income, acc.sellAH, acc.sellVendor, acc.sellDE = 0, {}, {}, {}
    for id, n in pairs(acc.made) do
        n = ceil(n)
        local v, how = ns.SellValue(state, P, id, 0)
        if how == "de" then
            -- disenchanted: every unit goes, the materials to the auction
            acc.income = acc.income + n * v
            add(acc.sellDE, id, n)
            acc.deEach = acc.deEach or {}
            acc.deEach[id] = v
            n = 0
        end
        local toAH = how == "ah" and math.min(n, ns.MarketTake(state, P, id)) or 0
        acc.income = acc.income + toAH * v + (n - toAH) * ((state.items[id] or {}).vend or 0)
        add(acc.sellAH, id, toAH)
        add(acc.sellVendor, id, n - toAH)
    end
    acc.net = acc.income - acc.spend - acc.own
    -- falling short of the target outweighs any money
    acc.score = -acc.net + acc.crafts * w + (target - s) * 1e7
    return acc
end

-- The plan for the profession in `state` with settings P. Buying a recipe is a one-time cost the
-- per-point choice cannot see, so each bought recipe is dropped while that makes the plan better.
-- Reach comes first: with a heavy time weight the crafts can cost more than the shortfall's
-- penalty, and a drop must never trade skill points for fewer crafts.
function ns.Plan(state, P)
    local allowed = {}
    local pin = P.pin
    for rid, r in pairs(state.recipes) do
        -- a pinned route: only the recipes it had, and what the character knows
        if (r.skill or r.other) and ns.CanGet(r, P) and (not pin or r.learned or pin.rids[rid]) then allowed[rid] = true end
    end
    local best = planWith(state, P, allowed)
    -- its recipes are chosen already: nothing is dropped
    for _ = 1, pin and 0 or (state.sim and 3 or 8) do
        local better, drop
        local ids = {}
        for rid in pairs(best.buyRecipes) do
            -- the simulation weighs the trainer's recipes in the plan itself (see planWith)
            if not (state.sim and state.recipes[rid].src.t == "trainer") then ids[#ids + 1] = rid end
        end
        table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
        for _, rid in ipairs(ids) do
            allowed[rid] = nil
            local p = planWith(state, P, allowed)
            allowed[rid] = true
            local cur = better or best
            if p.reached >= cur.reached and p.score < cur.score - 1 then better, drop = p, rid end
        end
        if not better then break end
        best = better
        allowed[drop] = nil
    end
    return best
end

-- A profit run without levelling: one recipe, crafted while a craft still gains something. What
-- is already made sells lower (the market takes maxSell at the auction) and own stock runs out,
-- so the gain falls craft by craft. `known`: the recipes that may make its intermediates; a
-- recipe not learned yet costs its price once.
local function earnWith(state, P, known, rid)
    local st = ns.Stock(state, P)
    local ids = { rid }
    local acc = { bags = {}, bank = {}, ahBuy = {}, vendorBuy = {}, prep = {}, missing = {}, made = {},
                  segs = {}, buyRecipes = {}, spend = 0, own = 0, crafts = 0, earn = true, cdUsed = {},
                  reached = state.skill, target = state.skill }
    local Q = {}
    for k, v in pairs(P) do Q[k] = v end
    Q.ahBought = acc.ahBuy
    P = Q
    local bySeg = {}
    while acc.crafts < ns.EARN_MAX do
        ns.Tick()
        local best
        for _, rid in ipairs(ids) do
            local r = state.recipes[rid]
            local cost = reagentCost(state, P, st, known, rid)
            if (acc.cdUsed[rid] or 0) >= ns.CdLeft(state, r) then cost = math.huge end
            if cost < math.huge then
                local value = ns.SellValue(state, P, r.out, acc.made[r.out] or 0) * (r.count or 1)
                local gain = value - cost
                if gain >= math.max(1, P.minGain or 0) and (not best or gain > best.gain) then best = { rid = rid, gain = gain, value = value, how = select(2, ns.SellValue(state, P, r.out, acc.made[r.out] or 0)) } end
            end
        end
        if not best then break end
        local r = state.recipes[best.rid]
        -- the reasons of the run, from the stock before its first craft takes from it
        local why = not bySeg[best.rid] and ns.Why(state, P, st, known, { rid = best.rid, earn = true, cost = -best.gain, value = best.value, how = best.how }, {}, 0)
        for id, k in pairs(r.r) do take(state, P, st, known, acc, id, k) end
        add(acc.made, r.out, r.count or 1)
        acc.crafts = acc.crafts + 1
        if r.cd then acc.cdUsed[best.rid] = (acc.cdUsed[best.rid] or 0) + 1; acc.cd = r.cd end
        if not r.learned then acc.buyRecipes[best.rid] = true end
        local sg = bySeg[best.rid]
        if not sg then
            sg = { rid = best.rid, from = state.skill, to = state.skill, n = 0, color = ns.Color(r, state.skill), why = why }
            bySeg[best.rid] = sg
            acc.segs[#acc.segs + 1] = sg
        end
        sg.n = sg.n + 1
    end
    for rid in pairs(acc.buyRecipes) do acc.spend = acc.spend + (state.recipes[rid].src.cost or 0) end
    acc.level, acc.prepCrafts = acc.crafts, 0 -- the crafts of the product itself
    for _, n in pairs(acc.prep) do acc.crafts = acc.crafts + n; acc.prepCrafts = acc.prepCrafts + n end
    acc.income, acc.sellAH, acc.sellVendor, acc.sellDE = 0, {}, {}, {}
    for id, n in pairs(acc.made) do
        n = ceil(n)
        local v, how = ns.SellValue(state, P, id, 0)
        if how == "de" then
            -- disenchanted: every unit goes, the materials to the auction
            acc.income = acc.income + n * v
            add(acc.sellDE, id, n)
            acc.deEach = acc.deEach or {}
            acc.deEach[id] = v
            n = 0
        end
        local toAH = how == "ah" and math.min(n, ns.MarketTake(state, P, id)) or 0
        acc.income = acc.income + toAH * v + (n - toAH) * ((state.items[id] or {}).vend or 0)
        add(acc.sellAH, id, toAH)
        add(acc.sellVendor, id, n - toAH)
    end
    acc.net = acc.income - acc.spend - acc.own
    if #acc.segs == 0 then acc.warn = { "WARN_EARN" } end
    return acc
end

-- `own`: only what is in the bags and the bank, plus vendor reagents; otherwise reagents from the
-- auction and recipes that can be bought now (and crafted at this skill) count too. The run is
-- the one recipe whose series gains the most; the window plans the next run after it.
function ns.Earn(state, P, own)
    local Q = P
    if own then
        Q = {}
        for k, v in pairs(P) do Q[k] = v end
        Q.buyAH, Q.buyRecipes = false, false
    end
    local known, cands = {}, {}
    for rid, r in pairs(state.recipes) do
        if r.learned and not r.skip then known[rid] = true end
        if r.out and not r.skip and not r.other and (r.learned or (not own and r.src and r.src.cost and ns.CanGet(r, Q) and r.skill and state.skill >= r.skill[1])) then
            cands[#cands + 1] = rid
        end
    end
    table.sort(cands, function(a, b) return tostring(a) < tostring(b) end)
    local best
    local tried = {}
    for _, rid in ipairs(cands) do
        local k = known
        if not known[rid] then
            k = {}
            for x in pairs(known) do k[x] = true end
            k[rid] = true
        end
        local p = earnWith(state, Q, k, rid)
        if #p.segs > 0 and p.net >= 1 then
            tried[#tried + 1] = p
            if not best or p.net > best.net + 1 then best = p end
        end
    end
    -- the next best series, for the reasons of the run (ns.Why)
    local why = best and best.segs[1] and best.segs[1].why
    if why then
        table.sort(tried, function(a, b) return a.net > b.net end)
        for _, p in ipairs(tried) do
            if p ~= best and #why.alts < ns.WHY_ALTS then
                local pr = state.recipes[p.segs[1].rid]
                why.alts[#why.alts + 1] = { rid = p.segs[1].rid, net = p.net, more = best.net - p.net, color = p.segs[1].color,
                                            buy = not pr.learned or nil }
            end
        end
        if #tried > 1 then why.reasons[#why.reasons + 1] = { "BEST_RUN", best.net } end
    end
    return best or earnWith(state, Q, known, nil)
end

-- The levelling routes worth a choice: plans for each weight of ns.SWEEP, keeping only those
-- that are clearly faster than every cheaper one (2% fewer crafts for more gold), cheapest first. At most
-- ns.LEVEL_ROUTES, always with the cheapest and the fastest.
function ns.Frontier(state, P)
    local plans = {}
    local function at(w)
        local Q = {}
        for k, v in pairs(P) do Q[k] = v end
        Q.w = w
        local p = ns.Plan(state, Q)
        p.w = w
        plans[#plans + 1] = p
        return p
    end
    for i, w in ipairs(ns.SWEEP) do
        at(w)
        ns.Part(i / #ns.SWEEP)
    end
    local top = 0
    for _, p in ipairs(plans) do top = math.max(top, p.reached) end
    -- the crafts limit: only routes within it, and the cheapest of them found between the
    -- weights of the sweep; when none fits, the one with the fewest crafts, marked `many`
    local cap = ns.CraftCap(state, P)
    if cap then
        local fits = function(p) return p.reached == top and ns.LevelCrafts(p) <= cap + 0.5 end
        local lo, hi
        for _, p in ipairs(plans) do
            if fits(p) then hi = (not hi or p.w < hi) and p.w or hi end
        end
        if hi then
            for _, p in ipairs(plans) do if p.w < hi and not fits(p) then lo = math.max(lo or 0, p.w) end end
        end
        if lo then
            local a, b = math.max(lo, 1), hi
            for _ = 1, 5 do
                local m = math.sqrt(a * b)
                if fits(at(m)) then b = m else a = m end
            end
        end
        local kept = {}
        for _, p in ipairs(plans) do if fits(p) then kept[#kept + 1] = p end end
        if #kept == 0 then
            local few
            for _, p in ipairs(plans) do
                if p.reached == top and (not few or ns.LevelCrafts(p) < ns.LevelCrafts(few)) then few = p end
            end
            few = few or plans[#plans]
            few.many = true
            return { few }
        end
        plans = kept
    end
    table.sort(plans, function(a, b)
        if (a.reached == top) ~= (b.reached == top) then return a.reached == top end
        if math.abs(a.net - b.net) > 1 then return a.net > b.net end
        return a.crafts < b.crafts
    end)
    local front = {}
    for _, p in ipairs(plans) do
        local last = front[#front]
        if p.reached == top and (not last or p.crafts < last.crafts * 0.98 - 0.5) then front[#front + 1] = p end
    end
    if #front == 0 then front[1] = plans[1] end
    local n = ns.LEVEL_ROUTES
    if #front <= n then return front end
    local out = {}
    for i = 1, n do out[i] = front[1 + math.floor((i - 1) * (#front - 1) / (n - 1) + 0.5)] end
    return out
end

-- The next run of a levelling plan: its first recipe, crafted until the plan switches to the
-- next one, planned again to that skill so the shopping covers this run only. The window plans
-- the next run anew once the skill or the prices change. `full` keeps the whole way.
-- A run planned with one recipe (`only`) takes the reasons of the whole way it follows: there the
-- recipe was chosen against every other, in the run it had no rival.
local function borrowWhy(run, way)
    if not way or way == run then return end
    local stretches, cur = {}, nil
    for _, x in ipairs(way.segs) do
        if cur and cur.rid == x.rid and cur.to == x.from then cur.to = x.to
        else cur = { rid = x.rid, from = x.from, to = x.to, why = x.why }; stretches[#stretches + 1] = cur end
    end
    for _, sg in ipairs(run.segs) do
        for _, c in ipairs(stretches) do
            if c.why and c.rid == sg.rid and c.from <= sg.from and sg.from < c.to then sg.why = c.why; break end
        end
    end
end
ns.BorrowWhy = borrowWhy

function ns.NextRun(state, P, full)
    local first = full.segs[1]
    if not first or first.to >= full.reached then full.full = full; return full end
    local Q = {}
    for k, v in pairs(P) do Q[k] = v end
    Q.target, Q.only = first.to, first.rid
    local run = ns.Plan(state, Q)
    run.full = full
    borrowWhy(run, full)
    return run
end

-- The whole way to the target as runs one after another: each run starts from what the one
-- before left (skill, rank, own stock, recipes bought). Where no known recipe raises the skill,
-- a leg is `unknown` up to the skill where a recipe turns orange, and the runs go on from there.
-- `first`: the run the window shows now, so the first leg is the same plan. At most ns.MAX_LEGS.
ns.MAX_LEGS = 20
ns.SIM_LEGS = 40
-- The recipe of a plan that uses only one, else nil.
local function one(plan)
    local rid
    for _, sg in ipairs(plan.segs) do
        if rid and sg.rid ~= rid then return nil end
        rid = sg.rid
    end
    return rid
end
-- The state a run leaves: own stock it used is gone, recipes it bought are known, a new rank.
local function after(st, run)
    local nst = {}
    for k, v in pairs(st) do nst[k] = v end
    nst.items = {}
    for id, it in pairs(st.items) do
        local c = {}
        for k, v in pairs(it) do c[k] = v end
        c.bags = math.max(0, (c.bags or 0) - ((run.bags or {})[id] or 0))
        c.bank = math.max(0, (c.bank or 0) - ((run.bank or {})[id] or 0))
        nst.items[id] = c
    end
    nst.recipes = {}
    for rid, r in pairs(st.recipes) do
        local c = {}
        for k, v in pairs(r) do c[k] = v end
        if run.buyRecipes[rid] then c.learned = true end
        -- a cooldown craft the run made waits for its cooldown in the runs after it
        if c.cd and (run.cdUsed or {})[rid] then c.cdReady = (st.now or 0) + c.cd end
        nst.recipes[rid] = c
    end
    if run.rank then nst.cap = run.rank.cap end
    nst.skill = run.reached
    return nst
end
function ns.Legs(state, P, first)
    local target = ns.Target(state, P)
    local st = {}
    for k, v in pairs(state) do st[k] = v end
    st.items, st.recipes = {}, {}
    for id, it in pairs(state.items) do
        local c = {}
        for k, v in pairs(it) do c[k] = v end
        st.items[id] = c
    end
    for rid, r in pairs(state.recipes) do
        local c = {}
        for k, v in pairs(r) do c[k] = v end
        st.recipes[rid] = c
    end
    local Q = {}
    for k, v in pairs(P) do Q[k] = v end
    Q.w = (first and first.full and first.full.w) or P.w
    Q.target = target
    -- the way the route's tile shows: the runs follow it, so a run is never missing where it goes
    local whole = first and (first.full or first)
    local legs, s = {}, state.skill
    -- the simulation shows the whole way of a new character, which is longer
    local most = state.sim and ns.SIM_LEGS or ns.MAX_LEGS
    while s < target and #legs < most do
        ns.Part((s - state.skill) / math.max(1, target - state.skill))
        st.skill = s
        local run = (#legs == 0 and first) or nil
        if not run then
            local way = (whole and whole.reached > s) and whole or ns.Plan(st, Q)
            local sg
            for _, x in ipairs(way.segs) do
                if x.from <= s and s < x.to then sg = x; break end
            end
            if sg and way.reached > s then
                -- the recipe of the way from here, as far as the way keeps it
                local to = sg.to
                for _, x in ipairs(way.segs) do
                    if x.from >= to and x.from == to and x.rid == sg.rid then to = x.to end
                end
                local R = {}
                for k, v in pairs(Q) do R[k] = v end
                R.target, R.only = to, sg.rid
                run = ns.Plan(st, R)
                borrowWhy(run, way)
                if run.reached <= s then
                    -- that recipe alone does not get there from what the runs before left (stock
                    -- used up, a pattern dropped as not worth it for so short a run): any recipe
                    R.only = nil
                    run = ns.Plan(st, R)
                end
            end
        end
        if not run or #run.segs == 0 or run.reached <= s then
            -- no known recipe here: the next skill where one turns orange
            local nxt
            for _, r in pairs(st.recipes) do
                if r.skill and r.skill[1] > s and ns.CanGet(r, Q) and (not nxt or r.skill[1] < nxt) then nxt = r.skill[1] end
            end
            local to = math.min(nxt or target, target)
            legs[#legs + 1] = { from = s, to = to, unknown = true }
            s = to
        else
            -- the same recipe as the run before: one longer run of it
            local last = legs[#legs]
            local rid = one(run)
            local merged
            if #legs > 1 and last.plan and rid and one(last.plan) == rid then
                local M = {}
                for k, v in pairs(Q) do M[k] = v end
                M.target, M.only = run.reached, rid
                merged = ns.Plan(last.state, M)
                if merged.reached ~= run.reached then merged = nil else borrowWhy(merged, whole) end
            end
            if merged then
                last.to, last.plan = run.reached, merged
                st = after(last.state, merged)
            else
                legs[#legs + 1] = { from = s, to = run.reached, plan = run, state = st }
                st = after(st, run)
            end
            s = run.reached
        end
    end
    return legs
end

-- Every route at once, for the tiles: { mode, plan, over, best }. Levelling routes (l1..) come
-- from ns.Frontier, missing ones have no plan; `over`: it loses more than the budget; `best`:
-- the fastest one within the budget (the cheapest when none fits).
function ns.Variants(state, P)
    local out = {}
    -- a pinned route is the only one: its recipes, planned again from the stock as it is now
    if P.pin then
        local full = ns.Plan(state, P)
        full.w = P.w
        return { { mode = P.pin.mode, plan = ns.NextRun(state, P, full), best = true, over = false, many = false } }
    end
    local front = {}
    if P.level and state.skill < ns.Target(state, P) then
        local lo, hi = ns.PhaseRange()
        ns.Phase(lo, lo + (hi - lo) * 0.7)
        local plans = ns.Frontier(state, P)
        ns.Phase(lo + (hi - lo) * 0.7, lo + (hi - lo) * 0.85)
        for i, p in ipairs(plans) do front[i] = ns.NextRun(state, P, p); ns.Part(i / #plans) end
        ns.Phase(lo + (hi - lo) * 0.85, hi)
    end
    local best
    for i = 1, ns.LEVEL_ROUTES do
        local p = front[i]
        -- the budget is for the whole way; the tile and the route show the next run
        local over = p and P.budget > 0 and -p.full.net > P.budget or false
        local many = p and p.full.many or false
        out[i] = { mode = "l" .. i, plan = p, over = over, many = many }
        if p and not over and not many then best = i end
    end
    if front[1] and not best then best = 1 end
    if best then out[best].best = true end
    -- profit from guessed prices would only mislead: without a price addon only levelling shows
    for _, m in ipairs(ns.MODES) do
        -- nor in the simulation: it asks what the levelling costs, the profit comes after the target
        if ns.EARN[m] and not state.noPrices and not state.sim then out[#out + 1] = { mode = m, plan = ns.Earn(state, P, m == "own") } end
    end
    return out
end

-- ---------- the route ----------

local function sortedIds(m)
    local ids = {}
    for id, n in pairs(m) do if n == true or n > 1e-6 then ids[#ids + 1] = id end end
    table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
    return ids
end
local function lines(state, m, src, price)
    local out = {}
    for _, id in ipairs(sortedIds(m)) do
        local it = state.items[id] or {}
        out[#out + 1] = { id = id, name = it.name or tostring(id), n = ceil(m[id]), src = src, price = price and price(it) }
    end
    return out
end
local function total(ls)
    local t = 0
    for _, l in ipairs(ls) do t = t + (l.price or 0) * l.n end
    return t
end

-- Numbers the stops and gives each a signature: the same stop on a new route keeps it.
local function seal(nodes)
    for i, n in ipairs(nodes) do
        n.index = i
        local parts = { n.kind, n.title, tostring(n.from), tostring(n.to), tostring(n.crafts) }
        for _, l in ipairs(n.lines or {}) do parts[#parts + 1] = tostring(l.id or l.recipe or l.rank) .. "x" .. l.n end
        for _, sg in ipairs(n.segs or {}) do parts[#parts + 1] = tostring(sg.rid) .. sg.from .. "-" .. sg.to end
        n.sig = table.concat(parts, "|")
    end
    return nodes
end

-- The stops in walking order: bank, auction, vendor, intermediates, then crafts split by the
-- trainer visits they need, then selling. Each stop: { kind, title, lines, cost, from, to, segs }.
function ns.Route(state, plan)
    local nodes = {}
    local function push(n)
        nodes[#nodes + 1] = n
    end
    local gather = lines(state, plan.gather or {}, "gather")
    if #gather > 0 then push({ kind = "gather", title = "STOP_GATHER", lines = gather }) end
    local mail = lines(state, plan.mail or {}, "mail")
    for _, l in ipairs(lines(state, plan.alts or {}, "alts")) do
        l.who = (state.items[l.id] or {}).altWho
        mail[#mail + 1] = l
    end
    if #mail > 0 then push({ kind = "mail", title = "STOP_MAIL", lines = mail }) end
    local bank = lines(state, plan.bank, "bank")
    if #bank > 0 then push({ kind = "bank", title = "STOP_BANK", lines = bank }) end
    local ah = lines(state, plan.ahBuy, "ah", function(it) return it.ah end)
    for _, l in ipairs(ah) do
        local g = plan.guess and plan.guess[l.id]
        if g then l.price, l.guess = g, true end
    end
    local vend = lines(state, plan.vendorBuy, "vendor", function(it) return it.buy end)
    local rids = sortedIds(plan.buyRecipes)
    for _, rid in ipairs(rids) do
        local r = state.recipes[rid]
        -- `pattern`: the pattern's item, so the stop's button buys it like any other line
        local l = { recipe = rid, name = r.name, n = 1, src = r.src.t, price = r.src.cost, pattern = r.src.item,
                    pname = r.src.item and (state.items[r.src.item] or {}).name or nil,
                    npc = r.src.t == "vendor" and r.src.npc or nil }
        if r.src.t == "ah" then ah[#ah + 1] = l elseif r.src.t == "vendor" then vend[#vend + 1] = l end
    end
    if #ah > 0 then push({ kind = "ah", title = "STOP_AH_BUY", lines = ah, cost = total(ah) }) end
    if #vend > 0 then push({ kind = "vendor", title = "STOP_VENDOR_BUY", lines = vend, cost = total(vend) }) end
    local prep = {}
    for _, rid in ipairs(sortedIds(plan.prep)) do
        prep[#prep + 1] = { recipe = rid, name = state.recipes[rid].name, n = ceil(plan.prep[rid]), src = "prep" }
    end
    if #prep > 0 then push({ kind = "craft", title = "STOP_PREP", lines = prep, prep = true }) end

    -- the trainer teaches a recipe only once the skill reaches it: the visit sits before the
    -- first craft that needs it
    local first = {}
    for i, sg in ipairs(plan.segs) do if not first[sg.rid] then first[sg.rid] = i end end
    local run, rankDone = {}, false
    local function flush()
        if #run == 0 then return end
        local n = 0
        for _, sg in ipairs(run) do n = n + sg.n end
        push({ kind = "craft", title = plan.earn and "STOP_EARN" or "STOP_CRAFT", from = run[1].from, to = run[#run].to,
               crafts = ceil(n), segs = run })
        run = {}
    end
    for i, sg in ipairs(plan.segs) do
        local ls = {}
        local rank
        if plan.rank and not rankDone and sg.from >= plan.rank.at then
            rankDone, rank = true, plan.rank
            ls[#ls + 1] = { rank = plan.rank.cap, name = "", n = 1, src = "trainer", price = plan.rank.cost }
        end
        for _, rid in ipairs(rids) do
            local r = state.recipes[rid]
            if r.src.t == "trainer" and first[rid] == i then
                ls[#ls + 1] = { recipe = rid, name = r.name, n = 1, src = "trainer", price = r.src.cost,
                                 who = r.src.who and r.src.who[1], npc = r.src.npc }
            end
        end
        if #ls > 0 then
            flush()
            push({ kind = "trainer", title = rank and "STOP_RANK" or "STOP_TRAINER", at = sg.from, rank = rank,
                   lines = ls, cost = total(ls) })
        end
        run[#run + 1] = sg
    end
    flush()
    local sa = lines(state, plan.sellAH, "sellah", function(it) return it.ah end)
    if #sa > 0 then push({ kind = "sell", title = "STOP_AH_SELL", lines = sa, cost = total(sa) }) end
    local sv = lines(state, plan.sellVendor, "sellv", function(it) return it.vend end)
    -- the units the auction would sell too, past what it takes of one item (maxSell)
    for _, l in ipairs(sv) do l.over = (plan.sellAH[l.id] or 0) > 0 end
    if #sv > 0 then push({ kind = "vendor", title = "STOP_VENDOR_SELL", lines = sv, cost = total(sv) }) end
    -- disenchanting: the crafted gear, worth what its materials bring at the auction
    local de = lines(state, plan.sellDE or {}, "de")
    for _, l in ipairs(de) do l.price = plan.deEach and plan.deEach[l.id] end
    if #de > 0 then push({ kind = "sell", title = "STOP_DE", lines = de, cost = total(de) }) end
    return seal(nodes)
end

-- The buy stops of the first run also take what the later runs of the way buy (`ahead`), so the
-- player goes to the auction house and the vendor once for the whole way. `legs`: the runs of
-- the way (ns.Legs), the first one being this route. A line added for a later run carries
-- `ahead` (the skill that run reaches); a stop the first run lacks comes before its first craft.
-- `at` (optional, `{ ah = bool, vendor = bool }`): only the places the player stands at now, so
-- away from them each run shows its own purchases once (owner's request of 2026-11-25).
function ns.BuyAhead(route, legs, at)
    if not legs or #legs < 2 then return route end
    local function stopOf(kind, title)
        for _, n in ipairs(route) do if n.kind == kind and n.title == title then return n end end
    end
    local added = false
    for i = 2, #legs do
        local l = legs[i]
        if l.plan and l.state then
            for _, m in ipairs(ns.Route(l.state, l.plan)) do
                if ((m.kind == "ah" and m.title == "STOP_AH_BUY") or (m.kind == "vendor" and m.title == "STOP_VENDOR_BUY"))
                    and (not at or at[m.kind]) then
                    local n = stopOf(m.kind, m.title)
                    if not n then
                        n = { kind = m.kind, title = m.title, lines = {}, cost = 0 }
                        local at = #route + 1
                        for k, x in ipairs(route) do if x.kind == "craft" or x.kind == "trainer" or x.kind == "sell" then at = k; break end end
                        -- the auction before the vendor, as in a route of its own
                        if m.kind == "ah" and route[at - 1] and route[at - 1].kind == "vendor" then at = at - 1 end
                        table.insert(route, at, n)
                    end
                    for _, x in ipairs(m.lines) do
                        -- an item adds up; a pattern is bought once
                        local same
                        for _, y in ipairs(n.lines) do
                            if (x.recipe and y.recipe == x.recipe) or (not x.recipe and not y.recipe and x.id and y.id == x.id) then same = y; break end
                        end
                        if not (same and x.recipe) then
                            if same then
                                same.n = same.n + x.n
                                same.ahead = same.ahead or l.to
                            else
                                local c = {}
                                for k, v in pairs(x) do c[k] = v end
                                c.ahead = l.to
                                n.lines[#n.lines + 1] = c
                            end
                            n.cost = (n.cost or 0) + (x.price or 0) * x.n
                            added = true
                        end
                    end
                end
            end
        end
    end
    return added and seal(route) or route
end

-- ---------- the run outside the window ----------

-- The cost of n units bought from auction lots { { unit price, count } }, cheapest first.
-- Returns the cost and how many the lots cover; the rest is priced at the dearest lot.
function ns.LadderCost(lots, n)
    local sorted = {}
    for _, l in ipairs(lots or {}) do if l[1] and l[1] > 0 and (l[2] or 0) > 0 then sorted[#sorted + 1] = l end end
    table.sort(sorted, function(a, b) return a[1] < b[1] end)
    local cost, got, last = 0, 0, nil
    for _, l in ipairs(sorted) do
        if got >= n then break end
        local k = math.min(l[2], n - got)
        cost, got, last = cost + k * l[1], got + k, l[1]
    end
    if got < n and last then cost = cost + (n - got) * last end
    return cost, got
end

-- Buying many of one item takes the dearer lots too: the auction price of each item the plan
-- buys becomes the mean over the lots it needs. Returns true when a price went up.
function ns.ApplyLadder(state, plan, now)
    local changed = false
    for id, n in pairs(plan and plan.ahBuy or {}) do
        local it = state.items[id]
        local lots = it and it.lots
        if lots and lots.l and (now or 0) - (lots.t or 0) <= ns.LOTS_FRESH and it.ah then
            local k = ceil(n)
            local cost, got = ns.LadderCost(lots.l, k)
            if got > 0 then
                local mean = math.floor(cost / k + 0.5)
                if mean > it.ah * 1.01 then it.ah, it.ladder, changed = mean, true, true end
            end
        end
    end
    return changed
end

-- What the run buys at the auction, for an Auctionator shopping list: { { id, name, n } }.
-- A pattern line has no item id but its name.
function ns.Shopping(route)
    local out, at = {}, {}
    for _, node in ipairs(route or {}) do
        if node.kind == "ah" then
            for _, l in ipairs(node.lines or {}) do
                local key = l.id or l.pattern or l.name
                if at[key] then out[at[key]].n = out[at[key]].n + l.n
                else out[#out + 1] = { id = l.id or l.pattern, name = l.pname or l.name, n = l.n }; at[key] = #out end
            end
        end
    end
    return out
end

-- Units of each item the run needs: what it buys, takes and crafts with. For the tooltip.
function ns.RunNeeds(state, route)
    local out = {}
    for _, node in ipairs(route or {}) do
        if node.kind ~= "sell" and not (node.kind == "vendor" and node.title == "STOP_VENDOR_SELL") then
            for _, l in ipairs(node.lines or {}) do
                if l.id and node.kind ~= "craft" then out[l.id] = math.max(out[l.id] or 0, l.n) end
            end
        end
        for _, sg in ipairs(node.segs or {}) do
            local r = state.recipes[sg.rid]
            for id, k in pairs(r and r.r or {}) do out[id] = (out[id] or 0) + ceil(k * sg.n) end
        end
    end
    return out
end

-- The craft a craft stop is at: the first recipe of it not made yet (a stop of intermediates
-- makes several, one after another), and how many crafts of it are left, for the "Make" button.
-- `p`: the stop's progress (ns.Progress); without it the first one. nil when all are made.
function ns.NextCraft(node, p)
    if not node then return nil end
    if node.segs then
        for k, sg in ipairs(node.segs) do
            local e = p and p.segs and p.segs[k]
            if not (e and e.done) then return sg.rid, e and e.left or ceil(sg.n) end
        end
        return nil
    end
    for k, l in ipairs(node.lines or {}) do
        local e = p and p.lines and p.lines[k]
        if l.recipe and not (e and e.done) then return l.recipe, e and e.left or l.n end
    end
    return nil
end

-- ---------- how far the run is, and buying from its stops ----------

-- Stops whose items arrive in the bags by taking or buying them.
local function gets(node)
    return node.kind == "mail" or node.kind == "bank" or (node.kind == "ah" and node.title == "STOP_AH_BUY")
        or (node.kind == "vendor" and node.title == "STOP_VENDOR_BUY")
end
ns.Gets = gets

-- How far the run is: for each stop { done, left, marked, lines = { { got, left, done } },
-- segs = { { got, left, done } } }. `have(id)` is what the bags hold now, `state` what they held
-- when the plan was made: units that arrived since count for the stops in their order, so a stop
-- is done once its items are in the bags. A line without an item (a pattern) is never done by
-- itself. A craft stop counts its crafts: `made` (recipe -> crafts since the plan, read from the
-- game's casts), each recipe's crafts going to its lines in their order; a stretch of the skill
-- is also done once `skill` (the profession's skill now) reaches its end. `marks` (stop signature
-- -> true): stops the player marked done by hand. `learned(rid)`: the character knows that
-- recipe now, so a pattern bought for it is done although it left the bags. Other stops are
-- never done.
function ns.Progress(route, state, have, made, marks, skill, learned)
    local out, used, usedMade = {}, {}, {}
    local function crafted(rid, n, reached)
        -- a stretch the skill is past takes no casts: they go to the next stop of that recipe
        if reached then return n end
        local got = math.max(0, ((made or {})[rid] or 0) - (usedMade[rid] or 0))
        usedMade[rid] = (usedMade[rid] or 0) + n
        return math.min(n, got)
    end
    for i, node in ipairs(route or {}) do
        local p = { lines = {}, left = 0, done = false }
        local mark = marks and node.sig and marks[node.sig] or false
        if gets(node) then
            for k, l in ipairs(node.lines or {}) do
                local e = { got = 0, left = l.n, done = false }
                local id = l.id or l.pattern
                if not l.id and l.pattern and l.recipe and learned and learned(l.recipe) then
                    e.got, e.left, e.done = l.n, 0, true
                elseif id then
                    local base = ((state and state.items[id]) or {}).bags or 0
                    local gained = math.max(0, (have(id) or 0) - base - (used[id] or 0))
                    used[id] = (used[id] or 0) + l.n
                    e.got = math.min(l.n, gained)
                    e.left = l.n - e.got
                    e.done = e.left <= 0
                end
                if not e.done then p.left = p.left + 1 end
                p.lines[k] = e
            end
            p.done = #p.lines > 0 and p.left == 0
        elseif node.kind == "craft" then
            local any = false
            for k, l in ipairs(node.lines or {}) do
                if l.recipe then
                    any = true
                    local got = crafted(l.recipe, l.n)
                    local e = { got = got, left = l.n - got, done = got >= l.n }
                    if not e.done then p.left = p.left + 1 end
                    p.lines[k] = e
                end
            end
            p.segs = {}
            for k, sg in ipairs(node.segs or {}) do
                any = true
                local n = ceil(sg.n)
                local reached = skill and sg.to > sg.from and skill >= sg.to or false
                local got = crafted(sg.rid, n, reached)
                local e = { got = got, left = n - got, done = got >= n }
                if e.done then e.left = 0 else p.left = p.left + 1 end
                p.segs[k] = e
            end
            p.done = any and p.left == 0
        end
        if mark then
            p.done, p.marked, p.left = true, true, 0
            for _, e in pairs(p.lines) do e.done, e.left = true, 0 end
            for _, e in pairs(p.segs or {}) do e.done, e.left = true, 0 end
        end
        out[i] = p
    end
    return out
end

-- The stop the player stands at: the first one not done that the open place serves.
-- `place`: "ah", "vendor", "bank" or "mail" (nil: nowhere).
function ns.Here(route, prog, place)
    if not place then return nil end
    local later
    for i, node in ipairs(route or {}) do
        local kind = node.kind == "sell" and "ah" or node.kind
        if kind == place then
            if gets(node) then
                if not (prog[i] and prog[i].done) then return i end
            else
                later = later or i
            end
        end
    end
    return later
end

-- What is left to buy of an auction stop, in its order: { { id, name, n, unit, line, pattern } },
-- and how many lines the button cannot buy (no item id). A pattern is bought by its item, as an
-- auction of its own, not as a commodity.
function ns.BuyQueue(node, p)
    local q, byHand = {}, 0
    for k, l in ipairs(node and node.lines or {}) do
        local e = p and p.lines[k]
        if not (e and e.done) then
            local id = l.id or l.pattern
            -- a guessed price is no plan to guard: the real one decides
            if id then q[#q + 1] = { id = id, name = l.pname or l.name, n = e and e.left or l.n, unit = not l.guess and l.price or nil, line = k,
                                     pattern = l.pattern and not l.id or nil }
            else byHand = byHand + 1 end
        end
    end
    return q, byHand
end

-- The auction asks more than the plan by more than the guard (percent): ask before buying.
-- A guard below 0 is "never ask".
function ns.Dear(unit, planned, guard)
    if not unit or not planned or planned <= 0 or (guard and guard < 0) then return false end
    return unit > planned * (1 + (guard or 0) / 100)
end

-- The clicks of an auction stop: two per line (ask the price, buy). Returns the click the
-- button is at and how many there are in all.
function ns.BuyClicks(lines, i, priced)
    local all = 2 * lines
    return math.min(all, 2 * ((i or 1) - 1) + (priced and 2 or 1)), all
end

-- What one click buys at the open vendor for a vendor stop. `goods`: what the vendor sells,
-- { { index, id, price, stack, avail } } with the price of one stack and avail in stacks (nil or
-- below 0: no limit). A vendor sells whole stacks only, so the need is rounded up: need 4, sold
-- in fives, buys 5. Returns { buys = { { index, id, name, stacks, stack, units, need, extra,
-- cost, line } }, cost, missing (lines this vendor does not sell), short (the money ran out) }.
function ns.VendorPlan(node, p, goods, money)
    local byId = {}
    for _, g in ipairs(goods or {}) do if g.id and not byId[g.id] then byId[g.id] = g end end
    local out = { buys = {}, cost = 0, missing = 0, short = false }
    local left = money or math.huge
    for k, l in ipairs(node and node.lines or {}) do
        local e = p and p.lines[k]
        if not (e and e.done) then
            local g = byId[l.id or l.pattern or false]
            if not g or not g.price or g.price <= 0 then
                out.missing = out.missing + 1
            else
                local need = e and e.left or l.n
                local stack = math.max(1, g.stack or 1)
                local stacks = ceil(need / stack)
                if g.avail and g.avail >= 0 and stacks > g.avail then stacks, out.missing = g.avail, out.missing + 1 end
                if stacks * g.price > left then
                    stacks, out.short = math.floor(left / g.price), true
                end
                if stacks > 0 then
                    local units = stacks * stack
                    out.buys[#out.buys + 1] = { index = g.index, id = l.id or l.pattern, name = l.name, stacks = stacks, stack = stack,
                        units = units, need = need, extra = math.max(0, units - need), cost = stacks * g.price, line = k }
                    out.cost = out.cost + stacks * g.price
                    left = left - stacks * g.price
                end
            end
        end
    end
    return out
end

-- A run in the log: what the plan promised when it started.
function ns.LogStart(v, money, now)
    local plan = v and v.plan
    if not plan or not v.state then return nil end
    return { prof = v.state.name, mode = v.mode, from = v.state.skill, to = plan.reached or plan.target or v.state.skill,
             net = plan.net or 0, crafts = ceil(plan.crafts or 0), money = money, t = now }
end

-- Ends a run: the skill reached and the money it really made or cost.
function ns.LogFinish(e, skill, money, now)
    e.skill, e.real, e.secs = skill, money - e.money, now - e.t
    e.done = true
    return e
end

-- Which stops of the new route were not on the old one, by index: the window lights them up.
function ns.Changed(old, new)
    local seen, out = {}, {}
    for _, n in ipairs(old or {}) do seen[n.sig] = true end
    if not old then return out end
    for i, n in ipairs(new) do if not seen[n.sig] then out[i] = true end end
    return out
end

-- ---------- the other tabs ----------

local function learnedSet(state)
    local k = {}
    for rid, r in pairs(state.recipes) do if r.learned and not r.skip then k[rid] = true end end
    return k
end

-- Learned recipes by profit per craft, with how many the own stock makes.
function ns.Crafts(state, P)
    local known, st = learnedSet(state), ns.Stock(state, P)
    local rows = {}
    for rid in pairs(known) do
        local r = state.recipes[rid]
        local cost = reagentCost(state, P, st, known, rid)
        local value, how = 0, "vendor"
        if r.out then value, how = ns.SellValue(state, P, r.out, 0) end
        value = value * (r.count or 1)
        local can = math.huge
        for id, n in pairs(r.r) do can = math.min(can, math.floor(left(st, id) / n)) end
        can = math.min(can, ns.CdLeft(state, r))
        -- another profession's recipe only makes reagents here; it is no row of this list
        if cost < math.huge and not r.other then
            rows[#rows + 1] = { recipe = rid, name = r.name, cost = cost, value = value, how = how,
                                profit = value - cost, can = can == math.huge and 0 or can, cd = r.cd, cdReady = r.cdReady,
                                color = ns.Color(r, state.skill), stale = ((state.items[r.out] or {}).age or 0) > ns.FRESH_DAYS }
        end
    end
    table.sort(rows, function(a, b) if a.profit ~= b.profit then return a.profit > b.profit end return a.name < b.name end)
    return rows
end

-- Own items with the best thing to do with each: "ah", "vendor" or "craft" (with the recipe).
function ns.Items(state, P)
    local known = learnedSet(state)
    local rows = {}
    for id, it in pairs(state.items) do
        local q = (it.bags or 0) + (it.bank or 0)
        if q > 0 then
            local v, how = ns.SellValue(state, P, id, 0)
            local best = { how = how, v = v }
            local st = ns.Stock(state, P)
            for rid in pairs(known) do
                local r = state.recipes[rid]
                local need = r.r[id]
                if need then
                    local others = reagentCost(state, P, st, known, rid) - need * unitCost(state, P, st, known, id)
                    local per = ((r.out and ns.SellValue(state, P, r.out, 0) or 0) * (r.count or 1) - others) / need
                    if per > best.v + 1 then best = { how = "craft", v = per, recipe = rid, recipeName = r.name } end
                end
            end
            rows[#rows + 1] = { id = id, name = it.name or tostring(id), bags = it.bags or 0, bank = it.bank or 0,
                                how = best.how, each = best.v, total = best.v * q, recipe = best.recipe, recipeName = best.recipeName }
        end
    end
    table.sort(rows, function(a, b) if a.total ~= b.total then return a.total > b.total end return a.name < b.name end)
    return rows
end

-- Recipes not learned yet: where, the price, profit per craft and the craft that pays it back.
-- `mine`: the recipes the character knows (of this profession) instead of the ones to get.
function ns.Recipes(state, P, mine)
    local known, st = {}, ns.Stock(state, P)
    for rid, r in pairs(state.recipes) do if ns.CanGet(r, P) then known[rid] = true end end
    local rows = {}
    for rid, r in pairs(state.recipes) do
        if mine and r.learned and not r.other then
            local cost = reagentCost(state, P, st, known, rid)
            local profit = cost < math.huge
                and (r.out and ns.SellValue(state, P, r.out, 0) or 0) * (r.count or 1) - cost or nil
            rows[#rows + 1] = { recipe = rid, name = r.name, cd = r.cd, src = "learned", skill = r.skill and r.skill[1], profit = profit }
        elseif not mine and not r.learned and r.src then
            -- a reagent with no price anywhere makes the cost unknown, not a number
            local cost = reagentCost(state, P, st, known, rid)
            local profit = cost < math.huge
                and (r.out and ns.SellValue(state, P, r.out, 0) or 0) * (r.count or 1) - cost or nil
            local pay = (profit and profit > 0 and r.src.cost and r.src.cost > 0) and math.max(1, math.ceil(r.src.cost / profit)) or nil
            rows[#rows + 1] = { recipe = rid, name = r.name, cd = r.cd, src = r.src.t, text = r.src.text, cost = r.src.cost,
                                est = r.src.est, who = r.src.who,
                                skill = r.skill and r.skill[1],
                                profit = profit, pay = pay }
        end
    end
    table.sort(rows, function(a, b)
        if (a.pay or 1e9) ~= (b.pay or 1e9) then return (a.pay or 1e9) < (b.pay or 1e9) end
        return a.name < b.name
    end)
    return rows
end

-- The crafts taken out of the routes, by name: { recipe, name, out }. `set`: the saved marks
-- (recipe -> true), which win over the marks of `state`: a state is read only by a calculation,
-- so after a click its marks are old until the next one ends.
local function skipped(r, rid, set)
    if set then return set[rid] == true end
    return r.skip == true
end
function ns.Skipped(state, set)
    local rows = {}
    for rid, r in pairs(state and state.recipes or {}) do
        if skipped(r, rid, set) then rows[#rows + 1] = { recipe = rid, name = r.name, out = r.out, skip = true } end
    end
    table.sort(rows, function(a, b) if a.name ~= b.name then return a.name < b.name end return tostring(a.recipe) < tostring(b.recipe) end)
    return rows
end

-- Lower case for a search, Cyrillic too (string.lower knows only A to Z): А-П, Р-Я and Ё.
function ns.Fold(text)
    local s = tostring(text or ""):lower()
    s = s:gsub("\208([\144-\159])", function(c) return "\208" .. string.char(c:byte() + 32) end)
    s = s:gsub("\208([\160-\175])", function(c) return "\209" .. string.char(c:byte() - 32) end)
    s = s:gsub("\208\129", "\209\145")
    return s
end

-- Does a name have the search text in it (any case)? An empty search finds everything.
function ns.Matches(name, text)
    text = ns.Fold((tostring(text or ""):match("^%s*(.-)%s*$")))
    if text == "" then return true end
    return ns.Fold(name):find(text, 1, true) ~= nil
end

-- The recipes whose name has `text` in it (any case), names that start with it first; a number
-- or a link finds the recipe by its id. At most `max`. Second value: how many there are in all.
function ns.FindRecipes(state, text, max, set)
    local rows = {}
    text = tostring(text or "")
    if text == "" then return rows, 0 end
    local low = ns.Fold(text)
    -- a number is the recipe's id (or the id of the item it makes); a pasted link gives it too
    local id = tonumber(text) or tonumber(text:match("|H%a+:(%d+)")) or tonumber(text:match("^%a+:(%d+)"))
    for rid, r in pairs(state and state.recipes or {}) do
        local name = tostring(r.name or "")
        local at
        if id then at = (rid == id or r.out == id) and 1 or nil
        else at = ns.Fold(name):find(low, 1, true) or name:find(text, 1, true) end
        if at then rows[#rows + 1] = { recipe = rid, name = name, out = r.out, skip = skipped(r, rid, set), at = at } end
    end
    table.sort(rows, function(a, b)
        if (a.at == 1) ~= (b.at == 1) then return a.at == 1 end
        if a.name ~= b.name then return a.name < b.name end
        return tostring(a.recipe) < tostring(b.recipe)
    end)
    local all = #rows
    for i = all, (max or all) + 1, -1 do rows[i] = nil end
    return rows, all
end

-- ---------- settings and recalculation ----------

-- The current view: state, plan, route, stops that changed and the change of the totals.
ns.view = {}

-- ---------- calculating in steps ----------

-- The game has no threads: a long calculation runs in a coroutine (ns.RecalcJob) that gives the
-- frame back once its time slice is spent (ns.Tick); the window resumes it on the next frame.
-- Outside such a job ns.Tick does nothing, so ns.Recalc still runs at once.
local job, sliceEnd
local function clock() return debugprofilestop and debugprofilestop() or nil end
function ns.Tick()
    if not job or coroutine.running() ~= job then return end
    local now = clock()
    if now and now >= sliceEnd then coroutine.yield() end
end
-- The share done (0..1) and the stretch of it the current step fills.
ns.progress = { done = 0, lo = 0, hi = 1 }
function ns.Phase(lo, hi) ns.progress.lo, ns.progress.hi = lo, hi; ns.progress.done = math.max(ns.progress.done, lo) end
function ns.PhaseRange() return ns.progress.lo, ns.progress.hi end
function ns.Part(f)
    local p = ns.progress
    p.done = math.max(p.done, p.lo + (p.hi - p.lo) * math.min(1, math.max(0, f)))
end

-- Builds the whole view from the current state and settings without touching ns.view, so the
-- window keeps showing the last result while a job runs. `flash`: light up what changed.
-- `nopin`: as if the route were not pinned (the comparison with a new calculation).
local function build(flash, nopin)
    local v = ns.view
    local state = ns.State and ns.State()
    if not state then return { state = nil, plan = nil, route = {} } end
    local pin = not nopin and ns.PinFor(state) or nil
    local P = pin and ns.PinPrefs(pin) or ns.Prefs(ns.SavedPrefs())
    -- a new calculation beside a pinned route goes to the same target
    if nopin and v.pin then P.target, P.level = v.pin.to, true end
    local out = { state = state, prefs = P, pin = pin }
    ns.progress.done = 0
    ns.Phase(0, 0.45)
    out.variants = ns.Variants(state, P)
    -- dearer lots: price what the routes buy by the lots they take, then plan once more
    local now = time and time() or 0
    local raised = false
    for _, x in ipairs(out.variants) do if x.plan and ns.ApplyLadder(state, x.plan, now) then raised = true end end
    ns.Phase(0.45, 0.6)
    if raised then out.variants = ns.Variants(state, P) end
    -- nothing left to level: show the profit route, without changing the saved choice
    local want = ns.OLD_MODES[P.mode] or P.mode
    if not P.level and not ns.EARN[want] then want = "earn" end
    for _, x in ipairs(out.variants) do
        if x.plan and (x.mode == want or (want == "auto" and x.best)) then out.mode = x.mode end
    end
    -- the chosen route is gone (nothing left to level, fewer routes): the best one, else profit
    if not out.mode then
        for _, x in ipairs(out.variants) do if x.best then out.mode = x.mode end end
    end
    out.mode = out.mode or "earn"
    out.auto = want == "auto"
    for _, x in ipairs(out.variants) do if x.mode == out.mode then out.plan = x.plan end end
    -- the whole way as runs, for the leg chips; a chosen leg stays chosen while it still starts there
    ns.Phase(0.6, 1)
    local oldLeg = v.legs and v.leg and v.legs[v.leg]
    out.legs = (not ns.EARN[out.mode] and out.plan and not out.plan.earn) and ns.Legs(state, P, out.plan) or {}
    -- the simulation opens on the whole way (leg 0), a run by a click
    out.leg = state.sim and 0 or 1
    out.legsBy = { [out.mode] = out.legs }
    if oldLeg and not state.sim then
        for i, l in ipairs(out.legs) do if l.from == oldLeg.from and l.unknown == oldLeg.unknown then out.leg = i end end
    end
    out.route = ns.LegRoute(out)
    out.changed = flash and ns.Changed(v.route, out.route) or {}
    if flash and v.plan and out.plan then
        out.delta = { net = out.plan.net - v.plan.net, crafts = ceil(out.plan.crafts) - ceil(v.plan.crafts),
                      fromNet = v.plan.net, fromCrafts = ceil(v.plan.crafts) }
    end
    ns.progress.done = 1
    return out
end

local FIELDS = { "state", "prefs", "variants", "mode", "auto", "plan", "legs", "leg", "route", "changed", "delta", "legsBy",
                 "made", "marks", "pin" }
local function apply(out)
    local v = ns.view
    -- a result of another profession than the one chosen now never shows (a switch while it ran)
    local cur = ns.char and ns.char.current
    if ns.sim then cur = ns.sim.name end
    if out.state and cur and out.state.name ~= cur then return v end
    -- nor a simulated result outside the simulation, or a real one inside it
    if out.state and (out.state.sim ~= nil) ~= (ns.sim ~= nil) then return v end
    for _, k in ipairs(FIELDS) do v[k] = out[k] end
    v.route = v.route or {}
    v.changed = v.changed or {}
    -- a new plan starts from the bags as they are: what was crafted or marked before is in them
    v.made, v.marks = v.made or {}, v.marks or {}
    v.stale, v.compare = nil, nil
    if ns.nameLate then ns.nameLate = nil; ns.FixNames(v) end
    if v.pin then ns.PinNote(v) end
    return v
end
-- Shows a result that was built aside (the new calculation of a comparison).
function ns.ApplyResult(out) return apply(out) end

-- One result per profession for the session: a switch shows that profession's last result,
-- outdated, or nothing until Calculate. A switch never calculates (owner's decision of 2026-11-20).
ns.views = {}
function ns.SwitchView(from, to)
    local v = ns.view
    if from and from ~= to and v.state and v.state.name == from then
        local keep = {}
        for _, k in ipairs(FIELDS) do keep[k] = v[k] end
        ns.views[from] = keep
    end
    local saved = to and ns.views[to]
    for _, k in ipairs(FIELDS) do v[k] = saved and saved[k] or nil end
    v.route = v.route or {}
    v.changed, v.delta = {}, nil
    v.stale = saved and saved.plan and "pick" or nil
end

-- Rebuilds the plan at once. `flash`: light up what changed.
function ns.Recalc(flash)
    if job then job = nil end
    return apply(build(flash))
end

-- A job in steps: :Step(ms) works for about ms milliseconds and returns true when it is done
-- (or failed: then also the error). Without the game's frame clock (debugprofilestop) a step
-- runs to the end. `kind`: "all" (the whole result) or "legs" (the runs of one route).
local jobKind
local function newJob(kind, work, done)
    local co = coroutine.create(work)
    job, jobKind = co, kind
    local self = { kind = kind }
    function self:Step(ms)
        if job ~= co then return true, "cancelled" end
        local now = clock()
        sliceEnd = (now or 0) + (ms or 12)
        local ok, res = coroutine.resume(co)
        if not ok then job = nil; return true, res end
        if coroutine.status(co) == "dead" then
            job = nil
            done(res)
            return true
        end
        return false
    end
    function self:Cancel() if job == co then job = nil end end
    return self
end

function ns.RecalcJob(flash)
    return newJob("all", function() return build(flash) end, apply)
end

-- A new calculation beside a pinned route: built without the pin and not shown; `done(out)` gets it.
function ns.FreshJob(done)
    return newJob("fresh", function() return build(false, true) end, done)
end
-- The same at once, for the tests.
function ns.FreshOut() return build(false, true) end

-- The runs of the route `mode` of the current result, kept per route so switching back is instant.
function ns.LegsJob(mode)
    local v = ns.view
    local plan, state, P = v.plan, v.state, v.prefs
    return newJob("legs", function()
        ns.progress.done = 0
        ns.Phase(0, 1)
        local legs = ns.Legs(state, P, plan)
        ns.progress.done = 1
        return legs
    end, function(legs)
        if ns.view.state ~= state then return end
        ns.view.legsBy[mode] = legs
        if ns.nameLate then ns.nameLate = nil; ns.FixNames(legs) end
        if ns.view.mode == mode then
            ns.view.legs, ns.view.leg = legs, state.sim and 0 or 1
            -- the buy stops may now take the later runs in
            ns.view.route = ns.LegRoute(ns.view)
        end
    end)
end

-- Switches to another route of the current result without planning again: every route is
-- already in `variants`, only its runs may still be missing. Returns false when the result has
-- no such route (a full calculation is needed), else true and whether its runs must be built.
function ns.PickMode(want)
    local v = ns.view
    if not v.variants or not v.state then return false end
    local mode
    for _, x in ipairs(v.variants) do
        if x.plan and (x.mode == want or (want == "auto" and x.best)) then mode = x.mode end
    end
    if not mode then return false end
    v.mode, v.auto = mode, want == "auto"
    if v.prefs then v.prefs.mode = want end
    for _, x in ipairs(v.variants) do if x.mode == mode then v.plan = x.plan end end
    v.legsBy = v.legsBy or {}
    if ns.EARN[mode] or v.plan.earn then v.legsBy[mode] = v.legsBy[mode] or {} end
    v.legs, v.leg = v.legsBy[mode], v.state.sim and 0 or 1
    v.route = ns.LegRoute(v)
    v.changed, v.delta = {}, nil
    return true, v.legs == nil
end

function ns.Busy() return job ~= nil end
function ns.BusyKind() return job and jobKind or nil end

-- Rebuilds after a change. `why`: "open" or "event" (the window opened, bags or prices changed),
-- else the player changed something. The window replaces this with a calculation in steps that
-- starts only on the Calculate button or the player's own changes.
function ns.Rebuild(flash, why)
    ns.Recalc(flash)
    if ns.Refresh then ns.Refresh() end
end

-- The stops of the chosen leg (the current run for the first one); none for an unknown leg.
function ns.LegRoute(v)
    -- the simulation's shopping list: everything the whole way buys
    if v.leg == ns.SIM_SHOP and v.state and v.state.sim then return ns.SimShopping(v) end
    local l = v.legs and v.legs[v.leg or 1]
    if l and l.unknown then return {} end
    local pin = v.state and not v.state.sim and v.pin or nil
    local ahead = v.state and not v.state.sim and v.legs and ns.Prefs(ns.SavedPrefs()).ahead
    local route
    if l and v.leg > 1 then route = ns.Route(l.state, l.plan)
    else
        route = ns.Route(v.state, v.plan)
        -- the first run buys for the whole way at once (`ahead`), at the place the player stands at;
        -- elsewhere each run shows only its own purchases. A simulated run shows only its own.
        if ahead then route = ns.BuyAhead(route, v.legs, { ah = ns.atAH and true, vendor = ns.atVendor and true }) end
    end
    -- a pinned route counts its purchases over the whole way, whatever the stops show
    if pin then
        local whole = ns.Route(v.state, v.plan)
        if v.legs then whole = ns.BuyAhead(whole, v.legs) end
        ns.PinSync(pin, whole, v.state, route)
    end
    return route
end

function ns.SelectLeg(i)
    local v = ns.view
    -- 0: the whole way, which only the simulation shows
    -- and the shopping list of the whole way (ns.SIM_SHOP)
    if not v.legs or not (v.legs[i] or ((i == 0 or i == ns.SIM_SHOP) and v.state and v.state.sim)) then return end
    v.leg = i
    v.route = ns.LegRoute(v)
    v.changed = {}
    if ns.Refresh then ns.Refresh() end
end

-- The settings as saved: the player's, or in the simulation its own copy of them, which is
-- never saved (ns.SimOpen makes it, ns.SimStop drops it).
function ns.SavedPrefs()
    if ns.sim then return ns.sim.prefs end
    if not ns.db then return nil end
    ns.db.prefs = ns.db.prefs or {}
    return ns.db.prefs
end

-- Changes one setting and rebuilds at once. nil value: back to the default.
function ns.SetPref(key, value)
    if ns.DEFAULTS[key] == nil then return end
    -- a setting the simulation fixes stays as it is there
    if ns.sim and ns.SIM_FIXED[key] ~= nil then return end
    -- a pinned route keeps its target
    if key == "target" and ns.view.pin and not ns.sim then return end
    ns.SavedPrefs()[key] = value
    if ns.sim and key == "target" and value then ns.sim.to = value end
    if ns.NO_PLAN[key] then
        -- the buy stops take the later runs in or leave them out: the same plan, other stops
        if key == "ahead" and ns.view and ns.view.state and ns.view.plan then
            ns.view.route = ns.LegRoute(ns.view)
            ns.view.changed = {}
        end
        if ns.Refresh then ns.Refresh() end
        return
    end
    -- the target only marks the result outdated: the player presses Recalculate
    ns.Rebuild(true, key == "target" and "target" or nil)
end

-- Several settings in one rebuild, so the change summary compares the right two plans.
function ns.SetPrefs(t)
    local saved = ns.SavedPrefs()
    for k, v in pairs(t) do if ns.DEFAULTS[k] ~= nil then saved[k] = v end end
    ns.Rebuild(true)
end

function ns.ResetPrefs()
    -- in the simulation only its own copy goes back to the defaults; the target is its condition
    if ns.sim then ns.sim.prefs = { target = ns.sim.to, level = true }
    else ns.db.prefs = {} end
    ns.Rebuild(true)
end

function ns.Print(msg) print("|cff9ad0ffGulli CraftProfit|r: " .. msg) end

SLASH_GULLICRAFTPROFIT1 = "/gcp"
SLASH_GULLICRAFTPROFIT2 = "/gullicraftprofit"
SlashCmdList.GULLICRAFTPROFIT = function(msg)
    msg = strtrim and strtrim(msg or ""):lower() or ""
    if msg == "sim" then
        -- /gcp sim: the simulation on (with the window) or off
        if ns.sim then ns.SimStop() else ns.SimOpen(); if ns.Visible and not ns.Visible() then ns.Toggle() end end
    elseif msg == "probe" then
        if ns.Probe then for _, line in ipairs(ns.Probe()) do ns.Print(line) end end
    elseif msg:match("^gather") then
        -- /gcp gather <item link|id>: the plan counts it as gathered, never bought; again: off
        local id = tonumber(msg:match("item:(%d+)")) or tonumber(msg:match("(%d+)"))
        if id and ns.SetGather then
            local on = not ns.Gathered()[id]
            ns.SetGather(id, on)
            local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
            ns.Print((on and ns.L.GATHER_ON or ns.L.GATHER_OFF):format(name or ("#" .. id)))
        else
            ns.Print(ns.L.GATHER_HELP)
        end
    elseif ns.Toggle then
        ns.Toggle()
    end
end

function GulliCraftProfit_Toggle() if ns.Toggle then ns.Toggle() end end

-- One game icon per setting, in the window and beside the module in the hub.
ns.OPT_ICON = {
    useBags = "Interface\\Icons\\INV_Misc_Bag_08", useBank = "Interface\\Minimap\\Tracking\\Banker",
    buyAH = "Interface\\Minimap\\Tracking\\Auctioneer", buyVendor = "Interface\\Icons\\INV_Misc_Bag_11",
    buyRecipes = "Interface\\Icons\\INV_Scroll_03", trainer = "Interface\\Icons\\INV_Misc_Book_11",
    sellAH = "Interface\\Icons\\INV_Misc_Coin_02", neutral = "Interface\\Icons\\INV_Misc_Coin_04",
    freshOnly = "Interface\\Icons\\INV_Misc_PocketWatch_01", level = "Interface\\Icons\\Spell_ChargePositive", target = "Interface\\Icons\\INV_Misc_Note_01",
    budget = "Interface\\Icons\\INV_Misc_Coin_01",
    chance = "Interface\\Icons\\INV_Misc_Coin_02", maxSell = "Interface\\Icons\\Spell_Nature_TimeStop", minGain = "Interface\\Icons\\INV_Misc_Coin_01",
    maxBuy = "Interface\\Icons\\Spell_Nature_TimeStop", maxCrafts = "Interface\\Icons\\Spell_Nature_TimeStop",
    useMail = "Interface\\Icons\\INV_Letter_15", useAlts = "Interface\\Icons\\INV_Misc_GroupNeedMore",
    guard = "Interface\\Icons\\Spell_Nature_TimeStop", side = "Interface\\Minimap\\Tracking\\Auctioneer",
    autoPin = "Interface\\Icons\\INV_Misc_Map_01", disenchant = "Interface\\Icons\\INV_Enchant_Disenchant",
}

local function option(key)
    return { label = ns.L["P_" .. key], icon = ns.OPT_ICON[key], tip = ns.L["TIP_" .. key],
             get = function()
                 -- an auction switch shows off while no price addon is loaded; the choice is kept
                 if (key == "buyAH" or key == "sellAH") and ns.HasPrices and not ns.HasPrices() then return false end
                 return ns.Prefs(ns.SavedPrefs())[key] == true
             end,
             set = function(on) if ns.db then ns.SetPref(key, on and true or false) end end }
end

-- With the hub: its row and button there; alone: its own minimap button (Skin.lua).
do
    local register = GulliToolkit and GulliToolkit.Register or function(info) ns.alone = info end
    register({
        key = "CraftProfit",
        icon = "Interface\\AddOns\\Gulli-CraftProfit\\icon",
        slash = "/gcp",
        category = "Items",
        open = function() if ns.Toggle then ns.Toggle() end end,
        window = function() return ns.Window and ns.Window() end,
        options = { option("level"), option("useBank"), option("buyAH"), option("buyRecipes"), option("trainer"),
                    option("sellAH") },
        -- the profession and its skill; the result of the last plan when the window made one
        summary = function()
            -- a simulation says so: its numbers are not the character's
            local sim = ns.sim
            if sim and sim.prof then return ns.L.SIM_SUMMARY:format(sim.name, sim.from, sim.to), ns.SIM_ICON end
            local c = ns.char and ns.char.profs and ns.char.current and ns.char.profs[ns.char.current]
            if not c or (c.skill or 0) <= 0 then return nil end
            local text = ns.L.SUMMARY:format(ns.char.current, c.skill, c.cap or 0)
            local plan = ns.view and ns.view.plan
            if plan and ns.view.state and ns.view.state.name == ns.char.current and ns.Money then
                text = text .. ns.Dot() .. (plan.net < 0 and "-" or "+") .. ns.Short(plan.net)
            end
            return text, c.icon
        end,
        reset = function() if ns.db then ns.ResetPrefs() end end,
    })
end
