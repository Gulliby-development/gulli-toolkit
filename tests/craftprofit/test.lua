-- Run from the repository root: lua5.1 tests/craftprofit/test.lua
local W = dofile("tests/craftprofit/wow.lua")
local test, eq = W.test, W.eq

-- A small tailoring example: own cloth in bags and bank, bolts made from cloth, threads and
-- dyes from a vendor, a pattern from a vendor, two trainer recipes, one pattern on the auction.
local function state()
    local items = {
        silk = { name = "Silk Cloth", ah = 160, age = 0.1, vend = 38, bags = 120, bank = 80 },
        mage = { name = "Mageweave Cloth", ah = 330, age = 0.1, vend = 63, bags = 40, bank = 60 },
        rune = { name = "Runecloth", ah = 720, age = 0.2, vend = 100, bank = 30 },
        bSilk = { name = "Bolt of Silk Cloth", ah = 900, age = 1.5, vend = 150 },
        bMage = { name = "Bolt of Mageweave", ah = 1500, age = 0.6, vend = 250 },
        bRune = { name = "Bolt of Runecloth", ah = 3600, age = 0.4, vend = 400 },
        fine = { name = "Fine Thread", buy = 100, vend = 25 },
        silken = { name = "Silken Thread", buy = 300, vend = 75 },
        heavy = { name = "Heavy Silken Thread", buy = 400, vend = 100 },
        rthread = { name = "Rune Thread", buy = 2500, vend = 625 },
        red = { name = "Red Dye", buy = 50, vend = 12 },
        blue = { name = "Blue Dye", buy = 50, vend = 12 },
        bleach = { name = "Bleach", buy = 25, vend = 6 },
        hood = { name = "Azure Silk Hood", ah = 1500, age = 1, vend = 420 },
        band = { name = "Silk Headband", ah = 2600, age = 0.5, vend = 520 },
        shirt = { name = "Formal White Shirt", ah = 1300, age = 6, vend = 380 },
        pants = { name = "Crimson Silk Pantaloons", ah = 5600, age = 0.8, vend = 1100 },
        vest = { name = "Black Mageweave Vest", ah = 2400, age = 2, vend = 900 },
        legs = { name = "Black Mageweave Leggings", ah = 3800, age = 0.7, vend = 1100 },
        gloves = { name = "Black Mageweave Gloves", ah = 3000, age = 1.2, vend = 800 },
        mhead = { name = "Black Mageweave Headband", ah = 6200, age = 0.4, vend = 1100 },
        bag = { name = "Red Mageweave Bag", ah = 14000, age = 0.3, vend = 1500 },
        belt = { name = "Runecloth Belt", ah = 9000, age = 0.9, vend = 1900 },
    }
    local recipes = {
        boltSilk = { name = "Bolt of Silk Cloth", skill = { 125, 135, 145 }, r = { silk = 4 }, out = "bSilk", learned = true },
        hood = { name = "Azure Silk Hood", skill = { 145, 160, 175 }, r = { bSilk = 2, blue = 2 }, out = "hood", learned = true },
        band = { name = "Silk Headband", skill = { 160, 170, 185 }, r = { bSilk = 3, fine = 2 }, out = "band", learned = true },
        shirt = { name = "Formal White Shirt", skill = { 170, 180, 195 }, r = { bSilk = 3, bleach = 2, fine = 1 }, out = "shirt", learned = true },
        pants = { name = "Crimson Silk Pantaloons", skill = { 175, 185, 200 }, r = { bSilk = 4, red = 2, silken = 2 }, out = "pants",
                  src = { t = "vendor", cost = 10000 } },
        boltMage = { name = "Bolt of Mageweave", skill = { 175, 180, 185 }, r = { mage = 2 }, out = "bMage", learned = true },
        vest = { name = "Black Mageweave Vest", skill = { 175, 190, 205 }, r = { bMage = 2, heavy = 1 }, out = "vest", learned = true },
        legs = { name = "Black Mageweave Leggings", skill = { 180, 195, 210 }, r = { bMage = 2, heavy = 3 }, out = "legs", learned = true },
        gloves = { name = "Black Mageweave Gloves", skill = { 185, 200, 215 }, r = { bMage = 2, heavy = 2 }, out = "gloves", learned = true },
        mhead = { name = "Black Mageweave Headband", skill = { 200, 215, 230 }, r = { bMage = 3, heavy = 2 }, out = "mhead",
                  src = { t = "trainer", cost = 2500 } },
        bag = { name = "Red Mageweave Bag", skill = { 215, 225, 240 }, r = { bMage = 4, heavy = 2, red = 2 }, out = "bag",
                src = { t = "ah", cost = 30000 } },
        belt = { name = "Runecloth Belt", skill = { 225, 240, 255 }, r = { bRune = 3, rthread = 1 }, out = "belt",
                 src = { t = "trainer", cost = 5000 } },
        boltRune = { name = "Bolt of Runecloth", skill = { 250, 255, 260 }, r = { rune = 5 }, out = "bRune",
                     src = { t = "trainer", cost = 5000 } },
    }
    return { skill = 150, cap = 225, level = 38, items = items, recipes = recipes }
end

local ns
local function core()
    if not ns then Fake({}); ns = Load() end
    return ns
end
local function prefs(t)
    local P = core().Prefs(t)
    return P
end
local function kinds(route)
    local out = {}
    for _, n in ipairs(route) do out[#out + 1] = n.title end
    return table.concat(out, " ")
end
local function has(route, title)
    for _, n in ipairs(route) do if n.title == title then return n end end
end
local function near(a, b, what) assert(math.abs(a - b) < 0.01, (what or "value") .. ": expected " .. b .. ", got " .. a) end

test("every language has every text", function()
    Fake({})
    W.CheckLocales(Load())
end)

-- ---------- economy ----------

test("auction value: 5% cut, unsold share loses the deposit, never below the vendor price", function()
    local c, st = core(), state()
    local v, how = c.SellValue(st, prefs({ chance = 100 }), "hood", 0)
    near(v, 1500 * 0.95); eq(how, "ah")
    v = c.SellValue(st, prefs({ chance = 80 }), "hood", 0)
    near(v, 0.8 * 1425 + 0.2 * (420 - c.Deposit(st.items.hood)))
    v = c.SellValue(st, prefs({ chance = 100, neutral = true }), "hood", 0)
    near(v, 1500 * 0.85, "neutral auction takes 15%")
    st.items.hood.ah = 400
    v, how = c.SellValue(st, prefs({}), "hood", 0)
    eq(v, 420); eq(how, "vendor")
end)

test("vendor instead of auction: switched off, old price, bound item, market full", function()
    local c, st = core(), state()
    local _, how = c.SellValue(st, prefs({ sellAH = false }), "band", 0)
    eq(how, "vendor")
    _, how = c.SellValue(st, prefs({}), "shirt", 0)
    eq(how, "vendor", "a 6 day old price is not trusted")
    _, how = c.SellValue(st, prefs({ freshOnly = false }), "shirt", 0)
    eq(how, "ah")
    st.items.band.bop = true
    _, how = c.SellValue(st, prefs({}), "band", 0)
    eq(how, "vendor", "bind on pickup")
    st.items.band.bop = nil
    _, how = c.SellValue(st, prefs({ maxSell = 5 }), "band", 5)
    eq(how, "vendor", "five are already listed")
end)

test("buying: the cheaper of vendor and auction, each one can be switched off", function()
    local c, st = core(), state()
    st.items.fine.ah = 80
    local v, how = c.BuyOption(st, prefs({}), "fine")
    eq(v, 80); eq(how, "ah")
    v, how = c.BuyOption(st, prefs({ buyAH = false }), "fine")
    eq(v, 100); eq(how, "vendor")
    v = c.BuyOption(st, prefs({ buyAH = false, buyVendor = false }), "fine")
    eq(v, nil)
end)

test("own items count at what they would sell for; bolts are made when that is cheaper", function()
    local c, st = core(), state()
    local P = prefs({})
    local own = c.SellValue(st, P, "silk", 0)
    local known = { boltSilk = true }
    local v, how = c.UnitCost(st, P, c.Stock(st, P), known, "silk")
    near(v, own); eq(how, "own")
    v, how = c.UnitCost(st, P, c.Stock(st, P), known, "bSilk")
    eq(how, "craft"); near(v, 4 * own)
end)

test("skill-up chance and colours", function()
    local c = core()
    local r = { skill = { 145, 160, 175 } }
    eq(c.Chance(r, 140), 0); eq(c.Color(r, 140), nil)
    eq(c.Chance(r, 150), 1); eq(c.Color(r, 150), "or_")
    near(c.Chance(r, 165), 10 / 15); eq(c.Color(r, 165), "ye")
    eq(c.Color(r, 168), "gr")
    eq(c.Chance(r, 175), 0); eq(c.Color(r, 175), "gy")
end)

test("thresholds guessed from the colours seen, short side first", function()
    local c = core()
    eq(c.Estimate({}), nil)
    local e = c.Estimate({ [150] = 0 })
    eq(e[2], 151, "orange at 150: yellow from 151 at the earliest")
    e = c.Estimate({ [150] = 0, [160] = 1 }, 175)
    eq(e[2], 151); eq(e[3], 175, "grey from the game")
    e = c.Estimate({ [170] = 2, [180] = 3 })
    assert(e[2] <= 169 and e[3] <= 180 and e[3] > 170)
end)

test("thresholds come from the data and follow the colours the game shows", function()
    local c = core()
    local vest = { 190, 205, 220 } -- Earthen Vest
    local t, guess = c.Thresholds(vest, { [173] = 0 }, nil, true)
    eq(guess, false); eq(t[1], 0); eq(t[2], 190); eq(t[3], 220)
    eq(c.Chance({ skill = t }, 173), 1, "orange: every craft is a point")
    near(c.Chance({ skill = t }, 205), 0.5)
    -- the game says yellow at 173: yellow starts there, grey stays
    t = c.Thresholds(vest, { [173] = 1 }, nil, true)
    eq(t[2], 173); eq(t[3], 220)
    assert(c.Chance({ skill = t }, 180) > 0.8, "a yellow recipe far from grey still gives most points")
    -- grey from the game wins; grey seen earlier than the data says
    t = c.Thresholds(vest, {}, 215, true); eq(t[3], 215)
    t = c.Thresholds(vest, { [200] = 3 }, nil, true); eq(t[3], 200)
    -- a recipe not learned yet starts orange at the skill it is learned at
    t = c.Thresholds({ 45, 70, 87, 105 }, nil, nil, false)
    eq(t[1], 45); eq(t[2], 70); eq(t[3], 105)
    -- no data: the guess, with the usual 20 points from yellow to grey
    t, guess = c.Thresholds(nil, { [173] = 1 }, nil, true)
    eq(guess, true); eq(t[1], 0); eq(t[2], 173); eq(t[3], 193)
    eq(c.Thresholds(nil, {}, nil, true), nil)
end)

test("Data.lua knows the Classic recipes by spell and by item", function()
    local c = core()
    eq(c.Data.spell[8764][3], 220, "Earthen Vest turns grey at 220")
    eq(c.Data.item[4238][1], 45, "Linen Bag is learned at 45")
    local n = 0
    for _ in pairs(c.Data.spell) do n = n + 1 end
    assert(n > 1000)
end)

-- ---------- the plan and the route ----------

test("default plan reaches the cap, walks bank, auction, vendor, crafts, trainer, sells", function()
    local c, st = core(), state()
    local plan = c.Plan(st, prefs({}))
    eq(plan.reached, 225)
    eq(plan.warn, nil)
    local route = c.Route(st, plan)
    eq(route[1].title, "STOP_BANK")
    eq(route[2].title, "STOP_AH_BUY")
    eq(route[3].title, "STOP_VENDOR_BUY")
    eq(route[#route].kind == "vendor" or route[#route].kind == "sell", true)
    local craftFrom = 150
    for _, n in ipairs(route) do
        if n.title == "STOP_CRAFT" then eq(n.from, craftFrom, "craft stops follow on"); craftFrom = n.to end
    end
    eq(craftFrom, 225)
    local t = has(route, "STOP_TRAINER")
    assert(t and t.at == 200, "Black Mageweave Headband is learned at 200, right before it is needed")
end)

test("the plan is the same every time", function()
    local c = core()
    local a = c.Route(state(), c.Plan(state(), prefs({})))
    local b = c.Route(state(), c.Plan(state(), prefs({})))
    eq(kinds(a), kinds(b))
    for i = 1, #a do eq(a[i].sig, b[i].sig) end
end)

test("without the bank the route has no bank stop and takes nothing from it", function()
    local c, st = core(), state()
    local plan = c.Plan(st, prefs({ useBank = false }))
    eq(next(plan.bank), nil)
    eq(has(c.Route(st, plan), "STOP_BANK"), nil)
end)

test("without the auction nothing is bought there; the plan stops where own silk runs out", function()
    local c, st = core(), state()
    local plan = c.Plan(st, prefs({ buyAH = false }))
    eq(next(plan.ahBuy), nil)
    eq(has(c.Route(st, plan), "STOP_AH_BUY"), nil)
    eq(plan.warn[1], "WARN_NONE")
    assert(plan.reached < 225)
end)

test("past the rank cap: the trainer teaches the next rank, or the plan stops there", function()
    local c, st = core(), state()
    local plan = c.Plan(st, prefs({ target = 250 }))
    eq(plan.reached, 250)
    local route = c.Route(st, plan)
    local rank = has(route, "STOP_RANK")
    assert(rank, "a rank stop")
    eq(rank.rank.cap, 300)
    assert(rank.at >= 200)
    plan = c.Plan(st, prefs({ target = 250, trainer = false }))
    eq(plan.reached, 225); eq(plan.warn[1], "WARN_TRAINER")
    st.level = 30
    plan = c.Plan(st, prefs({ target = 250 }))
    eq(plan.reached, 225); eq(plan.warn[1], "WARN_LEVEL"); eq(plan.warn[3], 35)
end)

test("speed takes fewer crafts, money keeps more gold", function()
    local c = core()
    local money = c.Plan(state(), prefs({ mode = "money" }))
    local speed = c.Plan(state(), prefs({ mode = "speed" }))
    assert(speed.crafts <= money.crafts, "speed " .. speed.crafts .. " vs money " .. money.crafts)
    assert(money.net >= speed.net, "money " .. money.net .. " vs speed " .. speed.net)
end)

test("a pattern that does not pay back is not bought; without patterns none is", function()
    local c, st = core(), state()
    st.recipes.pants.src.cost = 10000000
    local plan = c.Plan(st, prefs({}))
    eq(plan.buyRecipes.pants, nil)
    plan = c.Plan(state(), prefs({ buyRecipes = false }))
    for rid in pairs(plan.buyRecipes) do eq(state().recipes[rid].src.t, "trainer", rid) end
end)

test("at most maxSell of one item goes to the auction, the rest to a vendor", function()
    local c, st = core(), state()
    local plan = c.Plan(st, prefs({ maxSell = 3 }))
    for _, n in pairs(plan.sellAH) do assert(n <= 3) end
    assert(next(plan.sellVendor), "the rest is sold to a vendor")
    assert(has(c.Route(st, plan), "STOP_VENDOR_SELL"))
end)

test("the neutral auction and a lower sale share cost money", function()
    local c = core()
    local base = c.Plan(state(), prefs({})).net
    assert(c.Plan(state(), prefs({ neutral = true })).net < base)
    assert(c.Plan(state(), prefs({ chance = 40 })).net < base)
end)

test("changed stops: none for the same route, some after a setting changes", function()
    local c, st = core(), state()
    local a = c.Route(st, c.Plan(st, prefs({})))
    local same = c.Route(st, c.Plan(st, prefs({})))
    eq(next(c.Changed(a, same)), nil)
    local b = c.Route(st, c.Plan(st, prefs({ useBank = false })))
    assert(next(c.Changed(a, b)), "something changed")
    eq(next(c.Changed(nil, b)), nil, "the first draw lights nothing")
end)

test("crafts, items and recipes tabs", function()
    local c, st = core(), state()
    local P = prefs({})
    local crafts = c.Crafts(st, P)
    assert(#crafts >= 8)
    for i = 2, #crafts do assert(crafts[i - 1].profit >= crafts[i].profit) end
    local items = c.Items(st, P)
    eq(#items, 3, "silk, mageweave, runecloth")
    local recipes = c.Recipes(st, P)
    eq(#recipes, 5)
    for _, r in ipairs(recipes) do
        if r.pay then assert(r.pay * r.profit >= r.cost) end
    end
end)

test("a recipe with a reagent no one sells has no profit, not a broken number", function()
    local c, st = core(), state()
    st.items.ghost = { name = "Ghost Thread" }
    st.recipes.odd = { name = "Odd Robe", skill = { 150, 160, 170 }, r = { bSilk = 2, ghost = 1 }, out = "hood",
                       src = { t = "vendor", cost = 500 } }
    local P = prefs({})
    local found
    for _, r in ipairs(c.Recipes(st, P)) do if r.recipe == "odd" then found = r end end
    assert(found, "listed")
    eq(found.profit, nil)
    eq(found.pay, nil)
end)

test("money never shows nan or inf", function()
    Fake({})
    local n = Load()
    eq(n.Money(math.huge), "?")
    eq(n.Money(-math.huge), "?")
    eq(n.Money(0 / 0), "?")
    eq(n.Short(math.huge - math.huge), "?")
end)

-- ---------- the profit routes ----------

test("the profit route crafts only what gains, and the market cap lowers the gain", function()
    local c, st = core(), state()
    local P = prefs({ maxSell = 3 })
    local e = c.Earn(st, P)
    assert(e.earn and #e.segs > 0, "some crafts")
    assert(e.net > 0, "it earns: " .. e.net)
    eq(e.reached, st.skill)
    for _, sg in ipairs(e.segs) do eq(sg.from, sg.to) end
    for id, n in pairs(e.sellAH) do assert(n <= 3, id .. " at most maxSell at the auction") end
    -- a wider market takes more of the same craft
    local wide = c.Earn(st, prefs({ maxSell = 20 }))
    assert(wide.crafts >= e.crafts and wide.net >= e.net)
    assert(c.Route(st, e)[1], "a route")
    assert(has(c.Route(st, e), "STOP_EARN"), "a craft stop for sale")
end)

test("a limit of 0 means no limit: every unit goes to the auction", function()
    local c, st = core(), state()
    local plan = c.Plan(st, prefs({ maxSell = 0 }))
    local capped = c.Plan(st, prefs({ maxSell = 3 }))
    local any = false
    for id, n in pairs(capped.sellVendor) do if (capped.sellAH[id] or 0) > 0 then any = true end end
    assert(any, "the small market sends some units to a vendor")
    for id in pairs(plan.sellVendor) do assert(not plan.sellAH[id], id .. " sold at both places without a limit") end
    eq(c.Limit(0), math.huge); eq(c.Limit(nil), math.huge); eq(c.Limit(7), 7)
end)

test("a profit run buys at most maxBuy of one item at the auction, and stops at EARN_MAX crafts", function()
    local c = core()
    -- cheap cloth at the auction, a bag that a vendor buys for more: the run would never end
    local st = { skill = 100, cap = 150, level = 30, items = {
        cloth = { name = "Linen Cloth", ah = 1, age = 0, vend = 1 },
        bolt = { name = "Bolt of Linen Cloth", ah = 100, age = 0, vend = 1 },
        bag = { name = "Linen Bag", ah = 400, age = 0, vend = 100 },
    }, recipes = {
        bolt = { name = "Bolt of Linen Cloth", skill = { 1, 25, 50 }, r = { cloth = 2 }, out = "bolt", learned = true },
        bag = { name = "Linen Bag", skill = { 45, 70, 95 }, r = { bolt = 3 }, out = "bag", learned = true },
    } }
    local e = c.Earn(st, prefs({ maxBuy = 40 }))
    assert(e.net > 0)
    assert((e.ahBuy.cloth or 0) <= 40 + 6, "cloth bought: " .. tostring(e.ahBuy.cloth))
    local more = c.Earn(st, prefs({ maxBuy = 200 }))
    assert(more.crafts > e.crafts)
    assert(more.crafts <= c.EARN_MAX + 3, "crafts with the bolts: " .. more.crafts)
    -- without the auction, only own cloth counts
    st.items.cloth.bags = 12
    local own = c.Earn(st, prefs({}), true)
    eq(own.ahBuy.cloth, nil)
end)

test("from my stock buys nothing at the auction and no recipe", function()
    local c, st = core(), state()
    local P = prefs({})
    local own = c.Earn(st, P, true)
    eq(next(own.ahBuy), nil)
    eq(next(own.buyRecipes), nil)
    local buy = c.Earn(st, P)
    assert(buy.net >= own.net, "buying can only add")
end)

test("the profit route buys a recipe when it pays back", function()
    local c, st = core(), state()
    st.skill = 190
    -- a cheap pattern for a craft that sells well
    st.items.gold = { name = "Golden Robe", ah = 20000, age = 0.1, vend = 2000 }
    st.recipes.robe = { name = "Golden Robe", skill = { 180, 190, 200 }, r = { bMage = 2 }, out = "gold",
                        src = { t = "vendor", cost = 3000 } }
    local e = c.Earn(st, prefs({ buyRecipes = true, buyVendor = true }))
    assert(e.buyRecipes.robe, "the pattern is bought")
    local no = c.Earn(st, prefs({ buyRecipes = false }))
    eq(no.buyRecipes.robe, nil)
    assert(e.net > no.net)
end)

test("nothing gains: the profit route says so", function()
    local c, st = core(), state()
    for _, it in pairs(st.items) do it.ah = nil; it.age = nil; it.vend = 1 end
    local e = c.Earn(st, prefs({ buyAH = false }))
    eq(#e.segs, 0)
    eq(e.warn[1], "WARN_EARN")
end)

test("the levelling routes run from the cheapest to the fastest", function()
    local c, st = core(), state()
    local f = c.Frontier(st, prefs({ maxSell = 5 })) -- a small market makes speed cost gold)
    assert(#f >= 2 and #f <= c.LEVEL_ROUTES, "routes: " .. #f)
    for i = 2, #f do
        assert(f[i].net <= f[i - 1].net + 1, "each one costs more")
        assert(f[i].crafts < f[i - 1].crafts, "and takes fewer crafts")
        eq(f[i].reached, f[1].reached)
    end
end)

test("the loss budget: routes over it are marked, the fastest within it is the best", function()
    local c, st = core(), state()
    local f = c.Frontier(st, prefs({ maxSell = 5 }))
    local cheap, fast = -f[1].net, -f[#f].net
    assert(fast > cheap)
    local v = c.Variants(st, prefs({ maxSell = 5, budget = math.floor((cheap + fast) / 2) }))
    local best, over = nil, 0
    for i, x in ipairs(v) do
        if x.best then best = i end
        if x.over then over = over + 1 end
    end
    assert(best and best < #f, "a cheaper route is the best")
    assert(over >= 1)
    assert(not v[best].over)
    -- no limit: the fastest is the best
    local all = c.Variants(st, prefs({ maxSell = 5 }))
    assert(all[#f].best)
    -- too small a budget: the cheapest, marked as over
    local tiny = c.Variants(st, prefs({ maxSell = 5, budget = 1 }))
    assert(tiny[1].best and tiny[1].over)
end)

test("every route side by side; with levelling off only the profit ones", function()
    local c, st = core(), state()
    local v = c.Variants(st, prefs({}))
    eq(#v, #c.MODES)
    assert(v[1].plan and v[5].plan and v[6].plan)
    local off = c.Variants(st, prefs({ level = false }))
    for _, x in ipairs(off) do
        if c.EARN[x.mode] then assert(x.plan, x.mode) else eq(x.plan, nil, x.mode) end
    end
    st.skill = 225
    local top = c.Variants(st, prefs({}))
    eq(top[1].plan, nil, "nothing left to level")
end)

-- ---------- the game and the window ----------

local SKILL = 150
local function game(extra)
    local spec = {
        items = {
            [1] = { name = "Silk Cloth", ah = 160, sell = 38, bags = 120, bank = 80 },
            [2] = { name = "Bolt of Silk Cloth", ah = 900, sell = 150 },
            [3] = { name = "Blue Dye", sell = 12 },
            [4] = { name = "Azure Silk Hood", ah = 1500, sell = 420, quality = 2 },
            [5] = { name = "Fine Thread", sell = 25 },
            [6] = { name = "Silk Headband", ah = 2600, sell = 520, quality = 2 },
            [7] = { name = "Pattern Thing", sell = 1 },
        },
        prof = { name = "Tailoring", skill = SKILL, cap = 225, recipes = {
            { id = 101, name = "Bolt of Silk Cloth", learned = true, diff = 3, grey = 145, out = 2, r = { [1] = 4 } },
            { id = 102, name = "Azure Silk Hood", learned = true, diff = 0, grey = 175, out = 4, r = { [2] = 2, [3] = 2 } },
            { id = 103, name = "Silk Headband", learned = true, diff = 0, grey = 185, out = 6, r = { [2] = 3, [5] = 2 } },
            { id = 104, name = "Pattern Thing", learned = false, out = 7, r = { [1] = 1 }, source = "Vendor: Somebody" },
        } },
        vendor = { { 3, 50 }, { 5, 100 } },
        trainer = { { "Silk Headband", 300 } },
    }
    for k, v in pairs(extra or {}) do spec[k] = v end
    Fake(spec)
    local n = Load()
    W.Fire("MERCHANT_SHOW")
    W.Fire("TRADE_SKILL_SHOW")
    W.RunTimers()
    return n
end

test("the route is the next run: the first recipe of the whole way, planned again to there", function()
    local c, st = core(), state()
    st.cap = 300
    local P = prefs({ target = 300 })
    local full = c.Plan(st, P)
    assert(#full.segs >= 2, "the whole way uses several recipes")
    local run = c.NextRun(st, P, full)
    assert(run.full == full)
    eq(#run.segs, 1, "one recipe per run")
    eq(run.segs[1].rid, full.segs[1].rid)
    eq(run.reached, full.segs[1].to)
    assert(run.crafts < full.crafts)
    -- each levelling tile is its next run; the budget still counts the whole way
    for _, x in ipairs(c.Variants(st, P)) do
        if x.plan and not c.EARN[x.mode] then assert(x.plan.full and #x.plan.segs <= 1 + (x.plan.full == x.plan and 99 or 0)) end
        if x.plan and c.EARN[x.mode] then assert(#x.plan.segs <= 1, "a profit run is one recipe") end
    end
end)

test("the whole way as runs: one after another, from what the run before left, unknown stretches marked", function()
    local c, st = core(), state()
    st.cap = 300
    local P = prefs({ target = 300 })
    local full = c.Plan(st, P)
    local first = c.NextRun(st, P, full)
    local legs = c.Legs(st, P, first)
    assert(#legs >= 3, "runs: " .. #legs)
    eq(legs[1].plan, first, "the first leg is the run on screen")
    eq(legs[1].from, st.skill)
    for i = 2, #legs do eq(legs[i].from, legs[i - 1].to, "legs follow each other") end
    assert(#legs == c.MAX_LEGS or legs[#legs].to == 300, "to the target")
    local unknown = 0
    for _, l in ipairs(legs) do
        if l.unknown then unknown = unknown + 1; eq(l.plan, nil)
        else assert(#l.plan.segs >= 1 and l.to > l.from) end
    end
    assert(unknown >= 1, "nothing known raises the skill near the top")
    -- own silk used by one run is not there for the next one
    local silk = 0
    for _, l in ipairs(legs) do if l.plan then silk = silk + ((l.plan.bags or {}).silk or 0) + ((l.plan.bank or {}).silk or 0) end end
    assert(silk <= (st.items.silk.bags or 0) + (st.items.silk.bank or 0) + 1e-6, "own silk counted once: " .. silk)
    -- a gap in the middle: no recipe from 160 to 175, the runs go on after it
    local g = state()
    g.recipes.band = nil; g.recipes.shirt = nil
    g.recipes.hood.skill = { 145, 150, 160 }
    local gl = c.Legs(g, prefs({}), nil)
    local gap
    for i, l in ipairs(gl) do if l.unknown then gap = gap or i end end
    assert(gap and gl[gap].from == 160 and gl[gap].to == 175, "gap " .. tostring(gap and gl[gap].from) .. "-" .. tostring(gap and gl[gap].to))
    assert(gl[gap + 1] and not gl[gap + 1].unknown, "a known run after the gap")
end)

test("a cap the game did not give is the rank the skill is in", function()
    local c = core()
    eq(c.Cap({ skill = 147, cap = 0 }), 150)
    eq(c.Cap({ skill = 147, cap = 75 }), 150)
    eq(c.Cap({ skill = 150, cap = 150 }), 150)
    eq(c.Cap({ skill = 1, cap = 75 }), 75)
    local st = state()
    st.skill, st.cap = 147, 0
    local p = c.Plan(st, prefs({}))
    eq(p.target, 150)
    eq(p.rank, nil, "no trainer rank below the skill")
end)

test("a window that reports 0 takes the skill from the spellbook; 0/0 is never saved", function()
    local n = game({ prof = { name = "Tailoring", skill = 147, cap = 150, window0 = true, recipes = {
            { id = 101, name = "Bolt of Silk Cloth", learned = true, diff = 1, grey = 145, out = 2, r = { [1] = 4 } } } },
        spellbook = { { "Tailoring", 147, 150 } } })
    eq(n.char.profs.Tailoring.skill, 147); eq(n.char.profs.Tailoring.cap, 150)
    local m = game({ prof = { name = "Cooking", skill = 0, cap = 0, window0 = true, recipes = {} }, spellbook = {} })
    eq(m.char.profs.Cooking, nil, "nothing saved at 0/0")
    -- an old save at 0/0 is dropped and is not listed
    Fake({ prof = nil })
    GulliCraftProfitCharDB = { current = "Ghost", profs = { Ghost = { skill = 0, cap = 0, recipes = {} },
        Tailoring = { skill = 147, cap = 150, recipes = {} } } }
    local o = Load()
    eq(#o.Professions(), 1)
    eq(o.State().name, "Tailoring")
end)

test("the profession window is read with the modern API", function()
    local n = game()
    local p = n.char.profs.Tailoring
    eq(p.skill, SKILL); eq(p.cap, 225)
    eq(p.recipes[102].r[2], 2)
    eq(p.recipes[102].obs[SKILL], 0)
    eq(p.recipes[104].source, "Vendor: Somebody")
    local st = n.State()
    eq(st.recipes[102].skill[3], 175, "grey from maxTrivialLevel")
    eq(st.items[1].bank, 80); eq(st.items[1].bags, 120)
    eq(st.items[3].buy, 50, "price learned at the vendor")
    eq(st.items[4].quality, 2)
    eq(st.recipes[104].src.t, "text")
    eq(st.recipes[102].guess, true, "no data for this recipe: guessed")
    n.Data.spell[102] = { 160, 168, 180 }
    st = n.State()
    eq(st.recipes[102].guess, false, "the data knows it now")
    eq(st.recipes[102].skill[3], 175, "grey from the game still wins")
end)

test("a pattern's source and price come from the data; no pattern: the trainer", function()
    local n = game()
    -- sold by a vendor of each faction: the Alliance one counts; the price is four times its sell price
    n.Data.src[104] = { "v", 6, "Horde Guy|H", "Ally Gal|A" }
    local src = n.State().recipes[104].src
    eq(src.t, "vendor"); eq(src.cost, 520 * 4); eq(src.est, true); eq(src.who[1], "Ally Gal"); eq(#src.who, 1)
    eq(n.CanGet({ src = src }, n.Prefs({})), true)
    -- the vendor was seen: its own price
    n.db.vendor[6] = 1000
    src = n.State().recipes[104].src
    eq(src.cost, 1000); eq(src.est, false)
    -- on the auction for less: buy it there
    n.db.vendor[6] = 9000
    eq(n.State().recipes[104].src.t, "ah")
    -- only a drop, and nobody sells it: not a way to get it
    n.Data.src[104] = { "d", 7 }
    src = n.State().recipes[104].src
    eq(src.t, "drop"); eq(n.CanGet({ src = src }, n.Prefs({})), false)
    -- no pattern, but a known recipe: the trainer, at no known price yet
    n.Data.src[104] = nil
    n.Data.spell[104] = { 160, 170, 180 }
    src = n.State().recipes[104].src
    eq(src.t, "trainer"); eq(src.cost, nil)
    n.Data.spell[104] = nil
    eq(n.State().recipes[104].src.t, "text", "no data at all: the game's own text")
end)

test("each leg chip shows what the run gains or loses; craft reagents get their own rows", function()
    local n = game()
    n.Toggle(); n.Calculate()
    local v = n.view
    local chip = n.ui.chips[1]:GetText()
    local net = v.legs[1].plan.net
    assert(chip:find((net < 0 and "-" or "+") .. n.Short(net), 1, true), chip)
    local i
    for k, s in ipairs(v.route) do if s.segs then i = k end end
    n.Select(i)
    local rows = n.ui.detail.rows
    assert(rows[2] and rows[2].mid:GetText() == n.L.REAGENT, "a reagent row under the recipe")
end)

test("the classic API works too", function()
    local n = game({ classic = true })
    local p = n.char.profs.Tailoring
    eq(p.recipes[4].name, "Azure Silk Hood")
    eq(p.recipes[4].r[2], 2)
    eq(p.recipes[4].obs[SKILL], 0)
end)

test("trainer prices are learned", function()
    local n = game()
    W.Fire("TRAINER_SHOW")
    eq(n.db.trainer["Silk Headband"], 300)
end)

test("no profession read yet: the window says how to start", function()
    Fake({})
    local n = Load()
    n.Toggle(); n.Calculate()
    eq(n.ui.empty.title:GetText(), n.L.NO_PROF)
    assert(not n.ui.route:IsShown())
end)

test("open window: route stops, a setting click rebuilds and lights what changed", function()
    local n = game()
    n.db.prefs.useBags = false -- one run needs little: with the bags off it comes from the bank
    n.Toggle(); n.Calculate()
    assert(n.ui.frame:IsShown())
    local route = n.view.route
    assert(#route >= 3, "stops: " .. #route)
    for i = 1, #route do assert(n.ui.nodes[i]:IsShown()) end
    assert(n.ui.nodes[1].title:GetText())
    local hadBank = has(route, "STOP_BANK") ~= nil
    assert(hadBank)
    W.Click(n.ui.checks.useBank)
    eq(n.db.prefs.useBank, false)
    eq(has(n.view.route, "STOP_BANK"), nil, "the bank stop is gone")
    assert(next(n.view.changed), "changed stops")
    local lit = false
    for _, b in ipairs(n.ui.nodes) do if rawget(b, "lit") then lit = true end end
    assert(lit, "a changed stop lights up")
    assert(n.ui.toast:GetText():find("->", 1, true), "the toast shows before and after")
    W.RunTimers()
    for _, b in ipairs(n.ui.nodes) do eq(rawget(b, "lit"), nil) end
    W.Click(n.ui.checks.useBank)
    eq(n.db.prefs.useBank, true)
    assert(has(n.view.route, "STOP_BANK"))
end)

test("mode buttons, the target stepper and reset", function()
    local n = game()
    n.Toggle(); n.Calculate()
    W.Click(n.ui.modes.l1)
    eq(n.view.prefs.mode, "l1")
    eq(n.view.mode, "l1")
    W.Click(n.ui.budget.plus)
    eq(n.view.prefs.budget, 10000)
    W.Click(n.ui.target.minus)
    eq(n.db.prefs.target, 220)
    eq(n.view.plan.full.target, 220)
    W.Click(n.ui.chance.minus)
    eq(n.view.prefs.chance, 75)
    W.Click(n.ui.maxSell.plus)
    eq(n.view.prefs.maxSell, 21)
    W.Click(n.ui.maxBuy.minus)
    eq(n.view.prefs.maxBuy, 30)
    -- one step past the top is "no limit", saved as 0, and back down from it
    for _ = 1, 25 do W.Click(n.ui.maxSell.plus) end
    eq(n.view.prefs.maxSell, 0)
    W.Click(n.ui.maxSell.minus)
    eq(n.view.prefs.maxSell, 40)
    for _ = 1, 20 do W.Click(n.ui.maxBuy.plus) end
    eq(n.view.prefs.maxBuy, 0)
    W.Click(n.ui.reset)
    eq(n.view.prefs.mode, "auto"); eq(n.view.plan.full.target, 225); eq(n.view.prefs.chance, 80); eq(n.view.prefs.budget, 0)
end)

test("every switch in the column rebuilds the plan", function()
    local n = game()
    n.Toggle(); n.Calculate()
    for key, c in pairs(n.ui.checks) do
        local before = n.view.prefs[key]
        W.Click(c)
        eq(n.view.prefs[key], not before, key)
        eq(c:GetChecked(), not before, key .. " switch")
        W.Click(c)
    end
end)

test("the hub's switches change the same settings and rebuild the plan", function()
    local reg
    Fake({})
    GulliToolkit = { Register = function(t) reg = t end }
    local n = Load()
    GulliToolkit = nil
    eq(reg.key, "CraftProfit")
    assert(#reg.options >= 1 and #reg.options <= 6)
    for _, o in ipairs(reg.options) do assert(o.icon and o.label, "icon and label") end
    n.Recalc(false)
    local o = reg.options[1]
    local before = o.get()
    o.set(not before)
    eq(o.get(), not before)
    assert(next(n.db.prefs), "saved in the same prefs")
    o.set(before)
    eq(o.get(), before)
end)

test("an old saved choice still works", function()
    local n = game()
    n.db.prefs = { mode = "money" }
    n.Recalc(false)
    eq(n.view.mode, "l1")
end)

test("the levelling switch and the route tiles", function()
    local n = game()
    n.Toggle(); n.Calculate()
    assert(n.view.auto and n.view.mode:sub(1, 1) == "l", "the best levelling route")
    W.Click(n.ui.checks.level)
    eq(n.db.prefs.level, false)
    eq(n.view.mode, "earn", "only profit routes")
    assert(n.ui.varTiles[1].sub:GetText():find(n.L.VAR_OFF, 1, true))
    assert(has(n.view.route, "STOP_EARN") or #n.view.route == 0)
    W.Click(n.ui.modes.own)
    eq(n.view.mode, "own")
    W.Click(n.ui.modes.l1)
    eq(n.db.prefs.level, true, "a levelling tile turns levelling on")
    eq(n.view.mode, "l1")
    eq(n.ui.graphCard.title:GetText(), n.L.VAR_cheap)
    assert(n.ui.varTiles[1].label:GetText():find(n.L.TILE_cheap, 1, true))
end)

test("the leg chips pick a later run; the graph shows two rows and opens the rest", function()
    local n = game()
    n.Toggle(); n.Calculate()
    local v = n.view
    assert(#v.legs >= 2, "legs: " .. #v.legs)
    assert(n.ui.chips[1]:IsShown() and n.ui.chips[2]:IsShown())
    eq(v.leg, 1)
    W.Click(n.ui.chips[2])
    eq(v.leg, 2)
    assert(n.ui.graphCard.title:GetText():find(v.legs[2].from .. "-" .. v.legs[2].to, 1, true), "the title names the leg")
    if v.legs[2].unknown then eq(#v.route, 0); assert(n.ui.unknown:IsShown()) else assert(#v.route > 0) end
    -- a setting change keeps the chosen leg while it starts at the same skill
    W.Click(n.ui.checks.neutral)
    eq(v.leg, 2)
    W.Click(n.ui.checks.neutral)
    W.Click(n.ui.chips[1])
    -- many stops: two rows, then the button opens the graph and hides the stop list
    n.view.route = {}
    for i = 1, 10 do n.view.route[i] = { kind = "vendor", title = "STOP_VENDOR_BUY", lines = {}, index = i } end
    n.Refresh()
    -- Refresh rebuilds nothing: the route stays the ten stops
    assert(n.ui.expand:IsShown())
    assert(not n.ui.nodes[10]:IsShown(), "the third row waits")
    W.Click(n.ui.expand)
    assert(n.ui.nodes[10]:IsShown())
    assert(not n.ui.detailCard:IsShown())
    W.Click(n.ui.expand)
    assert(n.ui.detailCard:IsShown())
end)

test("a stop click shows its lines; tabs show the lists", function()
    local n = game()
    n.Toggle(); n.Calculate()
    local craft
    for i, s in ipairs(n.view.route) do if s.title == "STOP_CRAFT" then craft = i end end
    assert(craft)
    W.Click(n.ui.nodes[craft])
    eq((n.Selected()), craft)
    assert(#n.ui.detail.rows >= 1)
    n.Tab(2)
    assert(n.ui.listFrame:IsShown() and not n.ui.route:IsShown())
    assert(#n.ui.list.rows >= 3)
    n.Tab(4)
    assert(n.ui.list.rows[1].text:GetText():find("Pattern Thing", 1, true))
end)

test("a craft stop names its recipe and the crafts; the head shows the result with its sign", function()
    local n = game()
    n.Toggle(); n.Calculate()
    local i
    for k, s in ipairs(n.view.route) do if s.segs then i = k end end
    local s, b = n.view.route[i], n.ui.nodes[i]
    eq(b.title:GetText(), n.view.state.recipes[s.segs[1].rid].name)
    assert(b.kind:GetText():find(s.from .. "-" .. s.to, 1, true))
    assert(b.money:GetText():find(n.L.CRAFTS_N:format(s.crafts), 1, true))
    local head = n.ui.money:GetText()
    local net = n.view.plan.net
    assert(head:find((net < 0 and "-" or "+") .. n.Short(net), 1, true), head)
end)

test("the list heads sort the rows; rows have a tooltip; the recipe source in the game's words", function()
    local n = game()
    n.Toggle(); n.Calculate()
    n.Tab(2)
    local rows = n.Crafts(n.view.state, n.view.prefs)
    assert(n.ui.list.rows[1].text:GetText():find(rows[1].name, 1, true), "profit first")
    assert(n.ui.list.rows[1].tip and #n.ui.list.rows[1].tip >= 2, "reagents in the tooltip")
    assert(not n.ui.list.rows[1].text:GetText():find("■", 1, true), "no glyph the game font lacks")
    W.Click(n.ui.listHead[5])
    assert(n.ui.list.rows[1].text:GetText():find(rows[#rows].name, 1, true), "a second click turns the order")
    W.Click(n.ui.listHead[1])
    local names = {}
    for _, r in ipairs(rows) do names[#names + 1] = r.name end
    table.sort(names)
    assert(n.ui.list.rows[1].text:GetText():find(names[1], 1, true), "names A to Z")
    eq(n.SourceLabel("|cFFFFD200Vendor: |rSomebody|n|cFFFFD200Zone: |rIronforge"), "Vendor")
    eq(n.SourceLabel("Drop"), "Drop")
    eq(n.SourceLabel(nil), nil)
    n.Tab(4)
    eq(n.ui.list.rows[1].cols[1]:GetText(), "Vendor", "where, from the source text")
end)

test("without Auctionator only vendor prices count, and the window says so", function()
    local n = game({ auctionator = false })
    n.Toggle(); n.Calculate()
    eq(n.State().items[4].ah, nil)
    assert(n.ui.age:GetText():find(n.L.NO_AUCTIONATOR, 1, true))
end)

test("probe lists what the client offers", function()
    local n = game()
    local lines = n.Probe()
    assert(lines[1]:find("yes", 1, true))
    local all = table.concat(lines, "\n")
    assert(all:find("recipes: 4, learned 3", 1, true), all)
end)

-- ---------- the run outside the window ----------

test("a ladder of lots: n units cost the cheapest lots first", function()
    local c = core()
    local cost, got = c.LadderCost({ { 200, 5 }, { 100, 10 }, { 0, 3 } }, 12)
    eq(cost, 10 * 100 + 2 * 200); eq(got, 12)
    cost, got = c.LadderCost({ { 100, 2 } }, 5)
    eq(cost, 500, "past the lots: the dearest price"); eq(got, 2)
    eq((c.LadderCost({}, 5)), 0)
end)

test("dear lots raise the auction price of what the plan buys, and the plan changes", function()
    local c = core()
    local st = state()
    for _, it in pairs(st.items) do it.bags, it.bank = 0, 0 end
    local P = prefs({ mode = "l1" })
    local plan = c.Plan(st, P)
    local id = next(plan.ahBuy)
    assert(id, "the plan buys at the auction")
    local before = st.items[id].ah
    st.items[id].lots = { t = 1000, l = { { before, 1 }, { before * 3, 500 } } }
    eq(c.ApplyLadder(st, plan, 1000 + 3600), true)
    assert(st.items[id].ah > before * 2, "mean over the lots")
    assert(st.items[id].ladder)
    -- old lots are not used
    st.items[id].ah = before
    st.items[id].ladder = nil
    eq(c.ApplyLadder(st, plan, 1000 + 2 * 86400), false)
end)

test("mail, other characters and gathering are own stock with their own stops", function()
    local c = core()
    local st = state()
    for _, it in pairs(st.items) do it.bags, it.bank = 0, 0 end
    st.items.silk.mail = 40
    st.items.silk.alts, st.items.silk.altWho = 1000, "Banky"
    local P = prefs({ mode = "l1" })
    local route = c.Route(st, c.Plan(st, P))
    local mail = has(route, "STOP_MAIL")
    assert(mail, kinds(route))
    eq(mail.lines[1].src, "mail"); eq(mail.lines[1].n, 40)
    eq(#mail.lines, 1, "other characters are off by default")
    P = prefs({ mode = "l1", useAlts = true })
    mail = has(c.Route(st, c.Plan(st, P)), "STOP_MAIL")
    eq(mail.lines[2].src, "alts"); eq(mail.lines[2].who, "Banky")
    P = prefs({ mode = "l1", useMail = false })
    eq(has(c.Route(st, c.Plan(st, P)), "STOP_MAIL"), nil)
    -- gathered: never bought
    st.items.mage.gather = true
    P = prefs({ mode = "l1", target = 225 })
    local plan = c.Plan(st, P)
    eq(plan.ahBuy.mage, nil, "gathered mageweave is not bought")
    local full = plan.full or plan
    route = c.Route(st, full)
    if full.gather and full.gather.mage then assert(has(route, "STOP_GATHER")) end
end)

test("shopping list, run needs and the next craft come from the route", function()
    local c = core()
    local st = state()
    for _, it in pairs(st.items) do it.bags, it.bank = 0, 0 end
    local route = c.Route(st, c.Plan(st, prefs({ mode = "l1" })))
    local list = c.Shopping(route)
    assert(#list > 0)
    local needs = c.RunNeeds(st, route)
    for _, e in ipairs(list) do if e.id then assert(needs[e.id] and needs[e.id] >= 1, e.name) end end
    local craft
    for _, n in ipairs(route) do if n.segs then craft = n end end
    local rid, k = c.NextCraft(craft)
    eq(rid, craft.segs[1].rid); assert(k >= 1)
    eq(c.NextCraft({ kind = "ah" }), nil)
end)

test("the auction stop sends the list to Auctionator; a craft stop makes the crafts", function()
    local n = game()
    local made, list
    Auctionator.API.v1.ConvertToSearchString = function(_, t) return t.searchString .. ";" .. t.quantity end
    Auctionator.API.v1.CreateShoppingList = function(_, name, terms) list = { name = name, terms = terms } end
    C_TradeSkillUI.CraftRecipe = function(rid, k) made = { rid, k } end
    C_TradeSkillUI.OpenRecipe = function(rid) made = { rid, "open" } end
    n.db.prefs.useBags, n.db.prefs.useBank = false, false
    n.Toggle(); n.Calculate()
    local ah, craft
    for i, s in ipairs(n.view.route) do
        if s.kind == "ah" and s.title == "STOP_AH_BUY" then ah = ah or i end
        if s.segs then craft = craft or i end
    end
    assert(ah, kinds(n.view.route))
    n.Select(ah)
    assert(n.ui.act1:IsShown()); assert(not n.ui.act2:IsShown(), "no lots button away from the auction")
    W.Click(n.ui.act1)
    assert(list and #list.terms > 0 and list.terms[1]:find(";", 1, true))
    n.atAH = true
    n.Select(ah)
    assert(n.ui.act2:IsShown())
    n.atAH = false
    n.Select(craft)
    W.Click(n.ui.act1)
    eq(made[1], n.view.route[craft].segs[1].rid)
    eq(made[2], n.Ceil(n.view.route[craft].segs[1].n))
    W.Click(n.ui.act2)
    eq(made[2], "open")
    -- a click on the recipe row opens it too; a right-click on a reagent marks it gathered
    made = nil
    local row = n.ui.detail.rows[1]
    rawget(row.click, "_OnClick")(row.click, "LeftButton")
    eq(made[2], "open")
    local reagent = n.ui.detail.rows[2]
    local id = reagent.entry.id
    rawget(reagent.click, "_OnClick")(reagent.click, "RightButton")
    eq(n.db.gather[id], true)
    eq(n.view.state.items[id].gather, true)
end)

test("the lots of the run are read at the auction one item at a time", function()
    local n = game()
    local asked = {}
    C_AuctionHouse = {
        MakeItemKey = function(id) return { itemID = id } end,
        SendSearchQuery = function(key) asked[#asked + 1] = key.itemID end,
        GetNumCommoditySearchResults = function() return 2 end,
        GetCommoditySearchResultInfo = function(_, i) return { unitPrice = i * 1000, quantity = 3 } end,
    }
    n.db.prefs.useBags, n.db.prefs.useBank = false, false
    n.Toggle(); n.Calculate()
    eq(n.ScanLots(n.view.route), 0, "only at the auction")
    W.Fire("AUCTION_HOUSE_SHOW")
    local k = n.ScanLots(n.view.route)
    assert(k > 0)
    eq(#asked, 1)
    W.Fire("COMMODITY_SEARCH_RESULTS_UPDATED")
    local first = asked[1]
    eq(n.db.lots[first].l[1][1], 1000); eq(n.db.lots[first].l[2][2], 3)
    for _ = 1, 10 do W.RunTimers(); W.Fire("COMMODITY_SEARCH_RESULTS_UPDATED") end
    eq(#asked, k)
    eq(n.State().items[first].lots.l[1][1], 1000)
    W.Fire("AUCTION_HOUSE_CLOSED")
    eq(n.atAH, false)
    C_AuctionHouse = nil
end)

test("the mailbox and other characters are read", function()
    local n = game()
    GetInboxNumItems = function() return 2 end
    GetInboxHeaderInfo = function(i) return nil, nil, nil, nil, nil, i == 2 and 500 or 0 end
    GetInboxItem = function(i, a) if a == 1 then return "x", 1, nil, 7 end end
    W.Fire("MAIL_INBOX_UPDATE")
    eq(n.char.mail[1], 7, "a letter with cash on delivery does not count")
    GulliChoresDB = { chars = { ["Tester-Realm"] = { items = { [1] = 99 } },
                                ["Alt-Realm"] = { name = "Alt", items = { [1] = 5 }, bank = { [1] = 10 } } } }
    local alts, who = n.AltCount(1)
    eq(alts, 15); eq(who, "Alt")
    local it = n.State().items[1]
    eq(it.mail, 7); eq(it.alts, 15)
    GulliChoresDB, GetInboxNumItems, GetInboxHeaderInfo, GetInboxItem = nil, nil, nil, nil
end)

test("the run log compares the plan with the money and skill at the end", function()
    local n = game()
    n.Toggle(); n.Calculate()
    W.money = 10000
    GetMoney = function() return W.money end
    W.Click(n.ui.logBtn)
    assert(n.char.run, "a run started")
    eq(n.ui.logBtn:GetText(), n.L.LOG_FINISH)
    W.money = 7000
    n.char.profs.Tailoring.skill = SKILL + 5
    W.Click(n.ui.logBtn)
    eq(n.char.run, nil)
    local e = n.char.log[1]
    eq(e.real, -3000); eq(e.skill, SKILL + 5)
    assert(n.ui.logText:GetText():find(n.Money(-3000, true), 1, true))
    GetMoney = nil
end)

test("/gcp gather marks an item and frees it again", function()
    local n = game()
    SlashCmdList.GULLICRAFTPROFIT("gather |Hitem:5:0|h")
    eq(n.db.gather[5], true)
    SlashCmdList.GULLICRAFTPROFIT("gather 5")
    eq(n.db.gather[5], nil)
end)

test("the hub gets a summary, tips and reset", function()
    local reg
    Fake({})
    GulliToolkit = { Register = function(t) reg = t end }
    local n = Load()
    GulliToolkit = nil
    eq(reg.summary(), nil, "nothing read yet")
    for _, o in ipairs(reg.options) do assert(o.tip, "a tip for " .. o.label) end
    n.char.profs.Tailoring = { skill = 150, cap = 225, recipes = {}, icon = "ticon" }
    n.char.current = "Tailoring"
    local text, icon = reg.summary()
    eq(text, "Tailoring 150/225"); eq(icon, "ticon")
    n.db.prefs.chance = 50
    reg.reset()
    eq(n.db.prefs.chance, nil)
end)

-- ---------- calculating without freezing the game ----------

test("opening the window calculates nothing; Calculate builds the routes", function()
    local n = game()
    n.Toggle()
    eq(n.view.plan, nil, "nothing calculated on open")
    eq(n.ui.empty.title:GetText(), n.L.CALC_TITLE)
    eq(n.ui.calc:GetText(), n.L.CALC)
    assert(not n.ui.route:IsShown())
    -- a setting before the first calculation only changes the setting
    W.Click(n.ui.checks.useBank)
    eq(n.view.plan, nil)
    W.Click(n.ui.calc)
    assert(n.view.plan, "a plan after Calculate")
    assert(n.ui.route:IsShown())
    eq(n.ui.calc:GetText(), n.L.RECALC)
    eq(n.view.prefs.useBank, false, "the setting chosen before counts")
end)

test("the calculation runs in steps with a progress bar and keeps the last result until done", function()
    local n = game()
    n.Toggle(); n.Calculate()
    local old = n.view.plan
    local t = 0
    debugprofilestop = function() t = t + 5; return t end -- every look at the clock costs 5 ms
    W.Click(n.ui.checks.useBank)
    assert(n.Busy(), "still running after the first slice")
    assert(n.calcDriver:IsShown(), "the next frames go on")
    eq(n.view.plan, old, "the old result stays while it runs")
    assert(n.ui.progress:IsShown())
    assert(n.ui.empty.title:GetText():find("%%"), n.ui.empty.title:GetText())
    eq(n.ui.calc:GetText(), n.L.CALC_STOP)
    local last, frames = 0, 0
    while n.Busy() and frames < 10000 do
        W.Click(n.calcDriver, "OnUpdate")
        frames = frames + 1
        assert(n.progress.done >= last, "the bar never goes back")
        last = n.progress.done
    end
    debugprofilestop = nil
    assert(frames > 1, "it took several frames: " .. frames)
    assert(not n.Busy())
    assert(not n.calcDriver:IsShown())
    assert(n.view.plan ~= old, "the new result")
    eq(n.view.prefs.useBank, false)
    eq(n.progress.done, 1)
    assert(n.ui.route:IsShown())
end)

test("Stop ends a running calculation and keeps the last result", function()
    local n = game()
    n.Toggle(); n.Calculate()
    local old = n.view.plan
    local t = 0
    debugprofilestop = function() t = t + 5; return t end
    W.Click(n.ui.checks.useBank)
    assert(n.Busy())
    W.Click(n.ui.calc)
    debugprofilestop = nil
    assert(not n.Busy())
    eq(n.view.plan, old)
    assert(n.ui.route:IsShown())
end)

test("bags and prices only mark the result outdated", function()
    local n = game()
    n.Toggle(); n.Calculate()
    local old = n.view.plan
    W.Fire("BAG_UPDATE_DELAYED")
    W.RunTimers()
    eq(n.view.plan, old, "no calculation from an event")
    eq(n.view.stale, true)
    assert(n.ui.toast:GetText():find(n.L.CALC_STALE, 1, true))
    W.Click(n.ui.calc)
    eq(n.view.stale, nil)
end)

test("a big profession is planned in reasonable time", function()
    local ns = core()
    local st = state()
    -- 150 recipes over the whole range, each from bolts that a learned recipe makes
    for i = 1, 150 do
        local y = 100 + (i % 120)
        st.items["o" .. i] = { name = "Out " .. i, ah = 2000 + i * 7, age = 0.5, vend = 300 }
        st.recipes["x" .. i] = { name = "X " .. i, skill = { y - 10, y, y + 20 }, r = { bSilk = 1 + i % 3, bMage = i % 2, fine = 1 },
                                 out = "o" .. i, learned = i % 2 == 0, src = i % 2 == 1 and { t = "vendor", cost = 1000 + i } or nil }
    end
    st.skill = 169
    local t = os.clock()
    local P = ns.Prefs({ target = 225, maxSell = 0, maxBuy = 0 })
    local v = ns.Variants(st, P)
    local plan
    for _, x in ipairs(v) do if x.best then plan = x.plan end end
    ns.Legs(st, P, plan)
    local secs = os.clock() - t
    assert(secs < 4, "took " .. secs .. " s")
end)

W.finish()
