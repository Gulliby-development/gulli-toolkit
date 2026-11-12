-- The rules of Gulli-CraftProfit: what an item is worth, what a craft earns and which way to
-- level a profession. Everything here works on a plain "state" table, so the tests run it
-- without a game; Scan.lua builds that state from the game and Auctionator.
--
-- state = {
--   skill, cap, level,                    -- the profession's skill, its rank cap, the character level
--   items = { [id] = { name, ah, age, vend, buy, bags, bank, bop } },
--   recipes = { [rid] = { name, skill = { orange, yellow, grey }, r = { [id] = n }, out, count,
--                         learned, src = { t = "trainer"|"vendor"|"ah", cost }, guess } },
-- }
-- Prices are in copper. Green starts halfway between yellow and grey, as in the game.

local ADDON, ns = ...
local L = ns.L

-- Settings a player picks in the right column. A new one gets a default here, a control in
-- UI.lua, its texts in every language and a test that toggling it rebuilds the route.
ns.DEFAULTS = {
    mode = "auto", -- levelling: auto (the fastest within the budget) or l1..l4; profit only: own or earn
    budget = 0, -- copper the levelling may lose; 0: no limit
    level = true, -- off: no levelling routes, only the profit one
    target = 0,       -- 0: the rank cap
    useBags = true, useBank = true, buyAH = true, buyVendor = true,
    buyRecipes = true, trainer = true,
    sellAH = true, neutral = false, chance = 80, maxSell = 20, freshOnly = true,
    maxBuy = 40, -- units of one item a profit run buys at the auction: only a few sell at that price
}

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
-- The most crafts one profit run plans, intermediates included, so one cheap recipe cannot run away.
ns.EARN_MAX = 200
-- Rank caps: the cap, the skill the trainer teaches it from, the level it needs, its cost.
ns.RANKS = { { 75, 0, 5, 10 }, { 150, 50, 10, 500 }, { 225, 125, 20, 10000 }, { 300, 200, 35, 50000 } }

-- Kinds of stops on the route, in walking order. A new kind gets a colour and a test.
ns.STOPS = {
    bank = { 0.71, 0.55, 1.00 }, ah = { 0.95, 0.79, 0.30 }, vendor = { 0.36, 0.82, 0.48 },
    trainer = { 0.25, 0.78, 0.92 }, craft = { 1.00, 0.62, 0.26 }, sell = { 0.95, 0.79, 0.30 },
}
ns.COLORS = { or_ = { 1, 0.5, 0.25 }, ye = { 1, 0.84, 0.25 }, gr = { 0.25, 0.75, 0.25 }, gy = { 0.55, 0.55, 0.55 } }

local function ceil(n) return math.ceil(n - 1e-9) end
ns.Ceil = ceil

-- Merges saved settings over the defaults; a missing key takes its default.
function ns.Prefs(saved)
    local p = {}
    for k, v in pairs(ns.DEFAULTS) do p[k] = v end
    for k, v in pairs(saved or {}) do if ns.DEFAULTS[k] ~= nil then p[k] = v end end
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

-- Value of one unit put up for sale. `sold`: how many the plan already lists; past maxSell the
-- market is full and the rest goes to a vendor. Returns the value and "ah" or "vendor".
function ns.SellValue(state, P, id, sold)
    local it = state.items[id] or {}
    local vend = it.vend or 0
    if it.bop or not P.sellAH or not ns.Fresh(it, P) or (sold or 0) >= ns.Limit(P.maxSell) then return vend, "vendor" end
    local p = P.chance / 100
    local cut = P.neutral and ns.NEUTRAL_CUT or ns.CUT
    local ev = p * it.ah * (1 - cut) + (1 - p) * (vend - ns.Deposit(it))
    if ev > vend then return ev, "ah" end
    return vend, "vendor"
end

-- The cheapest way to buy one unit: "vendor" or "ah", or nil when it cannot be bought.
function ns.BuyOption(state, P, id)
    local it = state.items[id] or {}
    local v, how
    if P.buyVendor and it.buy then v, how = it.buy, "vendor" end
    -- `ahBought`: what this run already bought there; buying stops once it reaches maxBuy
    local room = not P.ahBought or (P.ahBought[id] or 0) < ns.Limit(P.maxBuy)
    if P.buyAH and room and ns.Fresh(it, P) and (not v or it.ah < v) then v, how = it.ah, "ah" end
    return v, how
end

-- Own items the plan may use: { [id] = { bags = n, bank = n } }.
function ns.Stock(state, P)
    local st = {}
    for id, it in pairs(state.items) do
        local b = P.useBags and (it.bags or 0) or 0
        local k = P.useBank and (it.bank or 0) or 0
        if b + k > 0 then st[id] = { bags = b, bank = k } end
    end
    return st
end
local function left(st, id) local s = st[id]; return s and (s.bags + s.bank) or 0 end

-- Which recipe makes an item, among the recipes the plan may use.
local function maker(state, known, id)
    for rid in pairs(known) do
        local r = state.recipes[rid]
        if r.out == id and (r.count or 1) == 1 and r.learned then return rid end
    end
end

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
    if grey and grey > 0 then loG, hiG, any = grey, grey, true end
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
    if grey and grey > 0 then g = grey end
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
        if a + b > 0 then acc.own = acc.own + (a + b) * ns.SellValue(state, P, id, 0) end
    end
    if n <= 1e-9 then return end
    local b, how = ns.BuyOption(state, P, id)
    local rid = (depth or 0) < 2 and maker(state, known, id)
    local craft = rid and reagentCost(state, P, st, known, rid, (depth or 0) + 1) or math.huge
    if craft < (b or math.huge) then
        add(acc.prep, rid, n)
        for rid2, k in pairs(state.recipes[rid].r) do take(state, P, st, known, acc, rid2, k * n, (depth or 0) + 1) end
        return
    end
    if not b then acc.missing[id] = true; return end
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

-- One pass: at each skill point the recipe with the lowest expected cost per point (plus time
-- by mode). `allowed`: the recipes it may use.
local function planWith(state, P, allowed)
    local st = ns.Stock(state, P)
    local acc = { bags = {}, bank = {}, ahBuy = {}, vendorBuy = {}, prep = {}, missing = {}, made = {},
                  segs = {}, buyRecipes = {}, spend = 0, own = 0, crafts = 0 }
    local s, cap, target = state.skill, ns.Cap(state), ns.Target(state, P)
    local w = P.w or ns.TIME[P.mode] or 0
    -- a sorted list keeps the plan the same from run to run
    local ids = {}
    for rid in pairs(allowed) do ids[#ids + 1] = rid end
    table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
    while s < target do
        if s >= cap then
            local nxt = rankAbove(cap)
            if not P.trainer then acc.warn = { "WARN_TRAINER", cap }; break end
            if not nxt or (state.level or 0) < nxt[3] then acc.warn = { "WARN_LEVEL", cap, nxt and nxt[3] or 0 }; break end
            acc.rank = { at = nxt[2], cap = nxt[1], level = nxt[3], cost = nxt[4] }
            acc.spend = acc.spend + nxt[4]
            cap = nxt[1]
        else
            local best
            local last = acc.segs[#acc.segs]
            for _, rid in ipairs(ids) do
                local r = state.recipes[rid]
                -- `only`: a run of one recipe; the others still make its intermediates
                local ch = (not P.only or P.only == rid) and ns.Chance(r, s) or 0
                if ch > 0 then
                    local n = 1 / ch
                    local value = r.out and ns.SellValue(state, P, r.out, acc.made[r.out] or 0) * (r.count or 1) or 0
                    local cost = n * (reagentCost(state, P, st, allowed, rid) - value)
                    if cost < math.huge then
                        local score = cost + n * w + ((last and last.rid ~= rid) and ns.SWITCH or 0)
                        if not best or score < best.score - 1e-9 then best = { rid = rid, n = n, score = score } end
                    end
                end
            end
            if not best then acc.warn = { "WARN_NONE", s }; break end
            local r = state.recipes[best.rid]
            for id, k in pairs(r.r) do take(state, P, st, allowed, acc, id, k * best.n) end
            if r.out then add(acc.made, r.out, best.n * (r.count or 1)) end
            acc.crafts = acc.crafts + best.n
            if not r.learned then acc.buyRecipes[best.rid] = true end
            if last and last.rid == best.rid and last.to == s then
                last.to = s + 1; last.n = last.n + best.n
            else
                acc.segs[#acc.segs + 1] = { rid = best.rid, from = s, to = s + 1, n = best.n, color = ns.Color(r, s) }
            end
            s = s + 1
        end
    end
    acc.reached, acc.target = s, target
    for rid in pairs(acc.buyRecipes) do acc.spend = acc.spend + (state.recipes[rid].src.cost or 0) end
    for _, n in pairs(acc.prep) do acc.crafts = acc.crafts + n end
    acc.income, acc.sellAH, acc.sellVendor = 0, {}, {}
    for id, n in pairs(acc.made) do
        n = ceil(n)
        local v, how = ns.SellValue(state, P, id, 0)
        local toAH = how == "ah" and math.min(n, ns.Limit(P.maxSell)) or 0
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
function ns.Plan(state, P)
    local allowed = {}
    for rid, r in pairs(state.recipes) do if r.skill and ns.CanGet(r, P) then allowed[rid] = true end end
    local best = planWith(state, P, allowed)
    for _ = 1, 8 do
        local better, drop
        local ids = {}
        for rid in pairs(best.buyRecipes) do ids[#ids + 1] = rid end
        table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
        for _, rid in ipairs(ids) do
            allowed[rid] = nil
            local p = planWith(state, P, allowed)
            allowed[rid] = true
            if p.score < (better or best).score - 1 then better, drop = p, rid end
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
                  segs = {}, buyRecipes = {}, spend = 0, own = 0, crafts = 0, earn = true,
                  reached = state.skill, target = state.skill }
    local Q = {}
    for k, v in pairs(P) do Q[k] = v end
    Q.ahBought = acc.ahBuy
    P = Q
    local bySeg = {}
    local function made()
        local n = acc.crafts
        for _, k in pairs(acc.prep) do n = n + k end
        return n
    end
    while made() < ns.EARN_MAX do
        local best
        for _, rid in ipairs(ids) do
            local r = state.recipes[rid]
            local cost = reagentCost(state, P, st, known, rid)
            if cost < math.huge then
                local value = ns.SellValue(state, P, r.out, acc.made[r.out] or 0) * (r.count or 1)
                local gain = value - cost
                if gain >= 1 and (not best or gain > best.gain) then best = { rid = rid, gain = gain } end
            end
        end
        if not best then break end
        local r = state.recipes[best.rid]
        for id, k in pairs(r.r) do take(state, P, st, known, acc, id, k) end
        add(acc.made, r.out, r.count or 1)
        acc.crafts = acc.crafts + 1
        if not r.learned then acc.buyRecipes[best.rid] = true end
        local sg = bySeg[best.rid]
        if not sg then
            sg = { rid = best.rid, from = state.skill, to = state.skill, n = 0, color = ns.Color(r, state.skill) }
            bySeg[best.rid] = sg
            acc.segs[#acc.segs + 1] = sg
        end
        sg.n = sg.n + 1
    end
    for rid in pairs(acc.buyRecipes) do acc.spend = acc.spend + (state.recipes[rid].src.cost or 0) end
    for _, n in pairs(acc.prep) do acc.crafts = acc.crafts + n end
    acc.income, acc.sellAH, acc.sellVendor = 0, {}, {}
    for id, n in pairs(acc.made) do
        n = ceil(n)
        local v, how = ns.SellValue(state, P, id, 0)
        local toAH = how == "ah" and math.min(n, ns.Limit(P.maxSell)) or 0
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
        if r.learned then known[rid] = true end
        if r.out and (r.learned or (not own and r.src and r.src.cost and ns.CanGet(r, Q) and r.skill and state.skill >= r.skill[1])) then
            cands[#cands + 1] = rid
        end
    end
    table.sort(cands, function(a, b) return tostring(a) < tostring(b) end)
    local best
    for _, rid in ipairs(cands) do
        local k = known
        if not known[rid] then
            k = {}
            for x in pairs(known) do k[x] = true end
            k[rid] = true
        end
        local p = earnWith(state, Q, k, rid)
        if #p.segs > 0 and p.net >= 1 and (not best or p.net > best.net + 1) then best = p end
    end
    return best or earnWith(state, Q, known, nil)
end

-- The levelling routes worth a choice: plans for each weight of ns.SWEEP, keeping only those
-- that are clearly faster than every cheaper one (2% fewer crafts for more gold), cheapest first. At most
-- ns.LEVEL_ROUTES, always with the cheapest and the fastest.
function ns.Frontier(state, P)
    local plans = {}
    for _, w in ipairs(ns.SWEEP) do
        local Q = {}
        for k, v in pairs(P) do Q[k] = v end
        Q.w = w
        local p = ns.Plan(state, Q)
        p.w = w
        plans[#plans + 1] = p
    end
    local top = 0
    for _, p in ipairs(plans) do top = math.max(top, p.reached) end
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
function ns.NextRun(state, P, full)
    local first = full.segs[1]
    if not first or first.to >= full.reached then full.full = full; return full end
    local Q = {}
    for k, v in pairs(P) do Q[k] = v end
    Q.target, Q.only = first.to, first.rid
    local run = ns.Plan(state, Q)
    run.full = full
    return run
end

-- The whole way to the target as runs one after another: each run starts from what the one
-- before left (skill, rank, own stock, recipes bought). Where no known recipe raises the skill,
-- a leg is `unknown` up to the skill where a recipe turns orange, and the runs go on from there.
-- `first`: the run the window shows now, so the first leg is the same plan. At most ns.MAX_LEGS.
ns.MAX_LEGS = 20
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
    local legs, s = {}, state.skill
    while s < target and #legs < ns.MAX_LEGS do
        st.skill = s
        local run = (#legs == 0 and first) or nil
        if not run then
            local full = ns.Plan(st, Q)
            local sg = full.segs[1]
            if sg and full.reached > s then
                -- the first recipe of the way from here, as far as the way keeps it
                local to = sg.to
                for i = 2, #full.segs do
                    if full.segs[i].rid ~= sg.rid or full.segs[i].from ~= to then break end
                    to = full.segs[i].to
                end
                local R = {}
                for k, v in pairs(Q) do R[k] = v end
                R.target, R.only = to, sg.rid
                run = ns.Plan(st, R)
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
                if merged.reached ~= run.reached then merged = nil end
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
    local front = {}
    if P.level and state.skill < ns.Target(state, P) then
        for i, p in ipairs(ns.Frontier(state, P)) do front[i] = ns.NextRun(state, P, p) end
    end
    local best
    for i = 1, ns.LEVEL_ROUTES do
        local p = front[i]
        -- the budget is for the whole way; the tile and the route show the next run
        local over = p and P.budget > 0 and -p.full.net > P.budget or false
        out[i] = { mode = "l" .. i, plan = p, over = over }
        if p and not over then best = i end
    end
    if front[1] and not best then best = 1 end
    if best then out[best].best = true end
    for _, m in ipairs(ns.MODES) do
        if ns.EARN[m] then out[#out + 1] = { mode = m, plan = ns.Earn(state, P, m == "own") } end
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

-- The stops in walking order: bank, auction, vendor, intermediates, then crafts split by the
-- trainer visits they need, then selling. Each stop: { kind, title, lines, cost, from, to, segs }.
function ns.Route(state, plan)
    local nodes = {}
    local function push(n)
        nodes[#nodes + 1] = n
    end
    local bank = lines(state, plan.bank, "bank")
    if #bank > 0 then push({ kind = "bank", title = "STOP_BANK", lines = bank }) end
    local ah = lines(state, plan.ahBuy, "ah", function(it) return it.ah end)
    local vend = lines(state, plan.vendorBuy, "vendor", function(it) return it.buy end)
    local rids = sortedIds(plan.buyRecipes)
    for _, rid in ipairs(rids) do
        local r = state.recipes[rid]
        local l = { recipe = rid, name = r.name, n = 1, src = r.src.t, price = r.src.cost }
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
                ls[#ls + 1] = { recipe = rid, name = r.name, n = 1, src = "trainer", price = r.src.cost }
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
    for i, n in ipairs(nodes) do
        n.index = i
        local parts = { n.kind, n.title, tostring(n.from), tostring(n.to), tostring(n.crafts) }
        for _, l in ipairs(n.lines or {}) do parts[#parts + 1] = tostring(l.id or l.recipe or l.rank) .. "x" .. l.n end
        for _, sg in ipairs(n.segs or {}) do parts[#parts + 1] = tostring(sg.rid) .. sg.from .. "-" .. sg.to end
        n.sig = table.concat(parts, "|")
    end
    return nodes
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
    for rid, r in pairs(state.recipes) do if r.learned then k[rid] = true end end
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
        if cost < math.huge then
            rows[#rows + 1] = { recipe = rid, name = r.name, cost = cost, value = value, how = how,
                                profit = value - cost, can = can == math.huge and 0 or can,
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
function ns.Recipes(state, P)
    local known, st = {}, ns.Stock(state, P)
    for rid, r in pairs(state.recipes) do if r.learned or ns.CanGet(r, P) then known[rid] = true end end
    local rows = {}
    for rid, r in pairs(state.recipes) do
        if not r.learned and r.src then
            -- a reagent with no price anywhere makes the cost unknown, not a number
            local cost = reagentCost(state, P, st, known, rid)
            local profit = cost < math.huge
                and (r.out and ns.SellValue(state, P, r.out, 0) or 0) * (r.count or 1) - cost or nil
            local pay = (profit and profit > 0 and r.src.cost and r.src.cost > 0) and math.max(1, math.ceil(r.src.cost / profit)) or nil
            rows[#rows + 1] = { recipe = rid, name = r.name, src = r.src.t, text = r.src.text, cost = r.src.cost,
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

-- ---------- settings and recalculation ----------

-- The current view: state, plan, route, stops that changed and the change of the totals.
ns.view = {}

-- Rebuilds the plan from the current state and settings. `flash`: light up what changed.
function ns.Recalc(flash)
    local state = ns.State and ns.State()
    local v = ns.view
    if not state then v.state, v.plan, v.route = nil, nil, {}; return v end
    local P = ns.Prefs(ns.db and ns.db.prefs)
    local before = v.plan
    local oldRoute = v.route
    v.state, v.prefs = state, P
    v.variants = ns.Variants(state, P)
    -- nothing left to level: show the profit route, without changing the saved choice
    local want = ns.OLD_MODES[P.mode] or P.mode
    if not P.level and not ns.EARN[want] then want = "earn" end
    v.mode = nil
    for _, x in ipairs(v.variants) do
        if x.plan and (x.mode == want or (want == "auto" and x.best)) then v.mode = x.mode end
    end
    -- the chosen route is gone (nothing left to level, fewer routes): the best one, else profit
    if not v.mode then
        for _, x in ipairs(v.variants) do if x.best then v.mode = x.mode end end
    end
    v.mode = v.mode or "earn"
    v.auto = want == "auto"
    for _, x in ipairs(v.variants) do if x.mode == v.mode then v.plan = x.plan end end
    -- the whole way as runs, for the leg chips; a chosen leg stays chosen while it still starts there
    local oldLeg = v.legs and v.leg and v.legs[v.leg]
    v.legs = (not ns.EARN[v.mode] and v.plan and not v.plan.earn) and ns.Legs(state, P, v.plan) or {}
    v.leg = 1
    if oldLeg then
        for i, l in ipairs(v.legs) do if l.from == oldLeg.from and l.unknown == oldLeg.unknown then v.leg = i end end
    end
    v.route = ns.LegRoute(v)
    v.changed = flash and ns.Changed(oldRoute, v.route) or {}
    if flash and before then
        v.delta = { net = v.plan.net - before.net, crafts = ceil(v.plan.crafts) - ceil(before.crafts),
                    fromNet = before.net, fromCrafts = ceil(before.crafts) }
    else
        v.delta = nil
    end
    return v
end

-- The stops of the chosen leg (the current run for the first one); none for an unknown leg.
function ns.LegRoute(v)
    local l = v.legs and v.legs[v.leg or 1]
    if l and l.unknown then return {} end
    if l and v.leg > 1 then return ns.Route(l.state, l.plan) end
    return ns.Route(v.state, v.plan)
end

function ns.SelectLeg(i)
    local v = ns.view
    if not v.legs or not v.legs[i] then return end
    v.leg = i
    v.route = ns.LegRoute(v)
    v.changed = {}
    if ns.Refresh then ns.Refresh() end
end

-- Changes one setting and rebuilds at once. nil value: back to the default.
function ns.SetPref(key, value)
    if ns.DEFAULTS[key] == nil then return end
    ns.db.prefs = ns.db.prefs or {}
    ns.db.prefs[key] = value
    ns.Recalc(true)
    if ns.Refresh then ns.Refresh() end
end

-- Several settings in one rebuild, so the change summary compares the right two plans.
function ns.SetPrefs(t)
    ns.db.prefs = ns.db.prefs or {}
    for k, v in pairs(t) do if ns.DEFAULTS[k] ~= nil then ns.db.prefs[k] = v end end
    ns.Recalc(true)
    if ns.Refresh then ns.Refresh() end
end

function ns.ResetPrefs()
    ns.db.prefs = {}
    ns.Recalc(true)
    if ns.Refresh then ns.Refresh() end
end

function ns.Print(msg) print("|cff9ad0ffGulli CraftProfit|r: " .. msg) end

SLASH_GULLICRAFTPROFIT1 = "/gcp"
SLASH_GULLICRAFTPROFIT2 = "/gullicraftprofit"
SlashCmdList.GULLICRAFTPROFIT = function(msg)
    msg = strtrim and strtrim(msg or ""):lower() or ""
    if msg == "probe" then
        if ns.Probe then for _, line in ipairs(ns.Probe()) do ns.Print(line) end end
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
    chance = "Interface\\Icons\\INV_Misc_Coin_02", maxSell = "Interface\\Icons\\Spell_Nature_TimeStop",
    maxBuy = "Interface\\Icons\\Spell_Nature_TimeStop",
}

local function option(key)
    return { label = ns.L["P_" .. key], icon = ns.OPT_ICON[key],
             get = function() return ns.Prefs(ns.db and ns.db.prefs)[key] == true end,
             set = function(on) if ns.db then ns.SetPref(key, on and true or false) end end }
end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "CraftProfit",
        icon = "Interface\\AddOns\\Gulli-CraftProfit\\icon",
        slash = "/gcp",
        category = "Items",
        open = function() if ns.Toggle then ns.Toggle() end end,
        window = function() return ns.Window and ns.Window() end,
        options = { option("level"), option("useBank"), option("buyAH"), option("buyRecipes"), option("trainer"),
                    option("sellAH") },
    })
end
