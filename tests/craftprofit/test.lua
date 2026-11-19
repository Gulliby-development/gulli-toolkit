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
    t = t or {}
    -- the route tests compare whole frontiers; the crafts limit has its own test
    if t.maxCrafts == nil then t.maxCrafts = -1 end
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

test("Data.lua knows the recipes by spell and by item", function()
    local c = core()
    eq(c.Data.spell[8764][3], 185, "Earthen Vest turns grey at 185 in WoW Forever")
    eq(c.Data.item[4238][1], 5, "Linen Bag is learned at 5 in WoW Forever")
    local n = 0
    for _ in pairs(c.Data.spell) do n = n + 1 end
    assert(n > 1000)
    -- Season of Discovery recipes are not in WoW Forever: no thresholds, no source, marked gone
    eq(c.Data.gone[435841], true, "Invoker's Cord")
    eq(c.Data.spell[435841], nil); eq(c.Data.src[435841], nil)
    -- one stays only when a Forever pattern teaches it
    for sid in pairs(c.Data.spell) do
        assert(sid < 400000 or sid >= 1000000 or c.Data.src[sid], "SoD recipe " .. sid .. " has no Forever pattern")
    end
    assert(c.Data.src[1213622][2] > 245000, "Enchant Gloves - Holy Power from the Forever formula")
    for sid in pairs(c.Data.src) do assert(not c.Data.gone[sid], "gone recipe " .. sid .. " has a source") end
    eq(c.Data.gone[8764], nil, "Earthen Vest stays")
end)

test("Data.lua takes the WoW Forever skill levels, recipes and trainer prices from Wowhead", function()
    local c = core()
    -- Forever moved Bolt of Mageweave down: grey at 150, not Classic's 185
    eq(c.Data.spell[3865][3], 150); eq(c.Data.item[4339][1], 140); eq(c.Data.item[4339][4], 150)
    eq(c.Data.train[3865], 1000, "its trainer price")
    -- the trainer teaches Transmute: Iron to Gold, though a vendor sells its recipe too
    eq(c.Data.train[11479], 2500); eq(c.Data.src[11479], nil)
    -- Forever's own Greater Healing Potion replaces the Classic recipe
    eq(c.Data.gone[7181], true); eq(c.Data.spell[7181], nil)
    eq(c.Data.spell[1244434][1], 175); eq(c.Data.src[1244434][2], 255723, "Manual: Greater Healing Potion")
    -- a recipe Wowhead marks unavailable is gone
    eq(c.Data.gone[16960], true, "Thorium Greatsword")
    -- the engineering trainers teach these despite the pattern
    eq(c.Data.gone[11454], nil)
    for sid in pairs(c.Data.train) do
        assert(not c.Data.src[sid] and not c.Data.gone[sid] and c.Data.spell[sid], "trainer price of " .. sid)
    end
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

test("the crafts limit: auto follows the target, routes over it go", function()
    local c, st = core(), state()
    local target = c.Target(st, prefs({}))
    eq(c.CraftCap(st, c.Prefs({})), target - st.skill + c.CRAFTS_SPARE, "auto: the points plus a spare")
    eq(c.CraftCap(st, c.Prefs({ target = st.skill + 10 })), 10 + c.CRAFTS_SPARE, "it follows the target")
    eq(c.CraftCap(st, c.Prefs({ maxCrafts = 40 })), 40)
    eq(c.CraftCap(st, c.Prefs({ maxCrafts = -1 })), nil)
    local all = c.Frontier(st, prefs({ maxSell = 5 }))
    local cheap, fast = all[1].crafts, all[#all].crafts
    assert(cheap > fast + 2)
    -- a limit between them: every route keeps within it, and the cheapest one within it is found
    local cap = math.floor((cheap + fast) / 2)
    local f = c.Frontier(st, prefs({ maxSell = 5, maxCrafts = cap }))
    assert(#f >= 1)
    for _, p in ipairs(f) do assert(p.crafts <= cap + 0.5, "crafts " .. p.crafts .. " over " .. cap); assert(not p.many) end
    for _, p in ipairs(all) do
        if p.crafts <= cap + 0.5 then assert(f[1].net >= p.net - 1, "the cheapest within the limit") end
    end
    -- a limit nobody keeps: only the route with the fewest crafts, marked
    f = c.Frontier(st, prefs({ maxSell = 5, maxCrafts = math.max(1, math.floor(fast / 2)) }))
    eq(#f, 1); assert(f[1].many); eq(f[1].crafts, fast)
    local v = c.Variants(st, prefs({ maxSell = 5, maxCrafts = math.max(1, math.floor(fast / 2)) }))
    assert(v[1].many and v[1].best, "still shown, marked")
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

test("a pattern that asks for a reputation the character lacks is never planned", function()
    local n = game()
    n.Data.src[104] = { "v", 6, "Ally Gal|A" }
    n.Data.spell[104] = { 150, 160, 170 }
    eq(n.State().recipes[104].src.t, "vendor", "no requirement on the pattern")
    -- the game paints the line red: not met, so neither the vendor nor the auction is a way
    W.tips[6] = { { "Pattern: Thing" }, { "Requires Cenarion Circle - Honored", 1, 0.125, 0.125 } }
    local src = n.State().recipes[104].src
    eq(src.t, "rep"); eq(src.text, "Requires Cenarion Circle - Honored")
    eq(n.CanGet({ src = src }, n.Prefs({})), false)
    n.db.vendor[6] = 9000
    eq(n.State().recipes[104].src.t, "rep", "the auction copy cannot be learned either")
    local P = n.Prefs({})
    local plan = n.Plan(n.State(), P)
    eq(plan.buyRecipes[104], nil, "the route does not buy it")
    local where
    for _, row in ipairs(n.Recipes(n.State(), P)) do if row.recipe == 104 then where = row.src end end
    eq(where, "rep", "the Recipes tab still lists it, with why")
    -- met (white line): bought as before
    W.tips[6][2] = { "Requires Cenarion Circle - Honored", 1, 1, 1 }
    eq(n.State().recipes[104].src.t, "ah")
    -- no colour from the client: the reputation list decides, and a faction it lacks is not met
    W.tips[6][2] = { "Requires Cenarion Circle - Honored" }
    eq(n.State().recipes[104].src.t, "rep")
    W.factions = { { "Cenarion Circle", 5 } }
    eq(n.State().recipes[104].src.t, "rep", "Friendly is below Honored")
    W.factions = { { "Cenarion Circle", 6 } }
    eq(n.State().recipes[104].src.t, "ah")
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
    -- no pattern, but a known recipe: the trainer, at a guessed price until a trainer was seen,
    -- so the plan can already use it
    n.Data.src[104] = nil
    n.Data.spell[104] = { 160, 170, 180 }
    local r = n.State().recipes[104]
    src = r.src
    eq(src.t, "trainer"); eq(src.cost, n.TrainerGuess(r.skill[1])); eq(src.est, true)
    assert(src.cost > 0)
    eq(n.CanGet({ src = src }, n.Prefs({})), true)
    eq(n.CanGet({ src = src }, n.Prefs({ trainer = false })), false, "the trainer switch still stops it")
    n.db.trainer[r.name] = 777
    src = n.State().recipes[104].src
    eq(src.cost, 777); eq(src.est, false)
    n.db.trainer[r.name] = nil
    -- Wowhead's trainer price, until a trainer was seen
    n.Data.train[104] = 4500
    src = n.State().recipes[104].src
    eq(src.cost, 4500); eq(src.est, false)
    n.db.trainer[r.name] = 777
    eq(n.State().recipes[104].src.cost, 777, "the price seen at a trainer wins")
    n.db.trainer[r.name] = nil
    n.Data.train[104] = nil
    -- a vendor Wowhead names without a faction, or none at all, sells to both
    n.db.vendor[6] = nil
    n.Data.src[104] = { "v", 6, "Somebody|AH" }
    src = n.State().recipes[104].src
    eq(src.t, "vendor"); eq(src.who[1], "Somebody")
    n.Data.src[104] = { "v", 6 }
    src = n.State().recipes[104].src
    eq(src.t, "vendor"); eq(src.who, nil); eq(src.cost, 520 * 4)
    -- the trainer teaches it too: learn it there, do not buy the pattern
    n.Data.train[104] = 4500
    src = n.State().recipes[104].src
    eq(src.t, "trainer"); eq(src.cost, 4500)
    n.Data.train[104] = nil
    n.db.trainer[r.name] = 900
    eq(n.State().recipes[104].src.t, "trainer", "a price seen at the trainer wins over the pattern")
    n.db.trainer[r.name] = nil
    n.Data.src[104] = nil
    n.Data.spell[104] = nil
    eq(n.State().recipes[104].src.t, "text", "no data at all: the game's own text")
    -- a recipe WoW Forever does not give is left out until the character knows it
    n.Data.gone[104] = true
    eq(n.State().recipes[104], nil, "not offered")
    n.char.profs.Tailoring.recipes[104].learned = true
    assert(n.State().recipes[104], "a learned one stays")
    n.Data.gone[104] = nil
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
    assert(rows[2] and rows[2].note:GetText() == n.L.REAGENT, "a reagent row under the recipe")
end)

test("the classic API works too", function()
    local n = game({ classic = true })
    local p = n.char.profs.Tailoring
    eq(p.recipes[4].name, "Azure Silk Hood")
    eq(p.recipes[4].r[2], 2)
    eq(p.recipes[4].obs[SKILL], 0)
end)

test("an unknown trainer price is the most a recipe of that skill costs", function()
    local n = game()
    eq(n.TrainerGuess(1), 5000); eq(n.TrainerGuess(74), 5000)
    eq(n.TrainerGuess(75), 10000); eq(n.TrainerGuess(149), 10000)
    eq(n.TrainerGuess(150), 20000); eq(n.TrainerGuess(224), 20000)
    eq(n.TrainerGuess(225), 25000); eq(n.TrainerGuess(300), 25000)
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
    assert(n.ui.nodes[1].head:GetText() and n.ui.nodes[1].sub:GetText())
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
        -- a setting of the buying itself (n.NO_PLAN) changes at once and plans nothing
        local function cur() if n.NO_PLAN[key] then return n.Prefs(n.db.prefs)[key] end return n.view.prefs[key] end
        local before, plan = cur(), n.view.plan
        W.Click(c)
        eq(cur(), not before, key)
        if n.NO_PLAN[key] then eq(n.view.plan, plan, key .. " keeps the plan") end
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
    eq(n.ui.varTiles[1].kind:GetText(), n.Skin.Upper(n.L.KIND_LEVEL), "a tile says what its route is for, in capitals")
    assert(n.ui.varTiles[1].label:GetText():find(n.L.TILE_cheap, 1, true))
end)

test("a levelling tile shows the target and the crafts of the whole way, not of the next run", function()
    local n = game()
    n.db.prefs.maxCrafts = -1
    n.Toggle(); n.Calculate()
    for i, x in ipairs(n.view.variants) do
        local p = x.plan
        if p and not p.earn and not x.over and not (x.best and n.view.prefs.budget > 0) then
            local full = p.full or p
            if full.reached >= full.target then
                eq(n.ui.varTiles[i].sub:GetText(), n.L.VAR_RUN:format(full.target, n.Ceil(full.crafts)))
            end
        end
    end
    -- a route of several runs: the tile still names the end of the way
    local x = n.view.variants[1]
    local run = { segs = {}, reached = x.plan.reached, target = x.plan.target, crafts = 2, net = -200, spend = 200, own = 0, income = 0 }
    run.full = { segs = {}, reached = run.target + 14, target = run.target + 14, crafts = 69, net = -2900 }
    run.reached = run.target; run.target = run.full.target
    x.plan = run
    n.Refresh()
    eq(n.ui.varTiles[1].sub:GetText(), n.L.VAR_RUN:format(run.full.target, 69))
end)

test("list money drops copper with gold and silver from 100 gold", function()
    local n = game()
    local real = GetCoinTextureString
    GetCoinTextureString = nil
    eq(n.Brief(4567), "45s 67c")
    eq(n.Brief(26 * 10000 + 87 * 100 + 53, true), "+26g 88s")
    eq(n.Brief(-(1 * 10000 + 5 * 100 + 77)), "-1g 6s")
    eq(n.Brief(123 * 10000 + 45 * 100 + 6), "123g")
    eq(n.Brief(0), "0c")
    GetCoinTextureString = real
end)

test("settings before Calculate never read the whole profession", function()
    local n = game()
    n.Toggle()
    local real, calls = n.State, 0
    n.State = function(...) calls = calls + 1; return real(...) end
    W.Click(n.ui.target.plus); W.Click(n.ui.target.minus)
    W.Click(n.ui.steppers.maxCrafts.plus); W.Click(n.ui.steppers.maxCrafts.minus)
    W.Click(n.ui.checks.useBank); W.Click(n.ui.checks.useBank)
    n.State = real
    eq(calls, 0, "no item counts or prices on a settings click")
    eq(n.view.plan, nil, "nothing calculated")
    eq(n.ui.target.value:GetText(), tostring(n.Target(n.Skill(), n.Prefs(n.db.prefs))))
end)

test("the crafts stepper starts on auto and binds to it again", function()
    local n = game()
    n.Toggle(); n.Calculate()
    local st = n.ui.steppers.maxCrafts
    local auto = n.CraftCap(n.view.state, n.Prefs({}))
    eq(st.value:GetText(), n.L.CRAFTS_AUTO:format(auto))
    W.Click(st.plus)
    eq(n.db.prefs.maxCrafts, auto + 5, "a number of its own")
    eq(st.value:GetText(), tostring(auto + 5))
    W.Click(st.minus)
    eq(n.db.prefs.maxCrafts, 0, "back on the auto value: auto again")
    n.db.prefs.maxCrafts = 500
    st:Refresh()
    W.Click(st.plus)
    eq(n.db.prefs.maxCrafts, -1)
    eq(st.value:GetText(), n.L.NO_LIMIT)
end)

test("the leg chips pick a later run; many stops scroll beside the chosen stop", function()
    local n = game()
    n.Toggle(); n.Calculate()
    local v = n.view
    assert(#v.legs >= 2, "legs: " .. #v.legs)
    assert(n.ui.chips[1]:IsShown() and n.ui.chips[2]:IsShown())
    eq(v.leg, 1)
    W.Click(n.ui.chips[2])
    eq(v.leg, 2)
    assert(rawget(n.ui.chips[2], "on") and not rawget(n.ui.chips[1], "on"), "the chosen run is marked")
    eq(n.ui.skillNow:GetText(), tostring(v.legs[2].from), "the way starts where that run starts")
    if v.legs[2].unknown then eq(#v.route, 0); assert(n.ui.unknown:IsShown()) else assert(#v.route > 0) end
    -- a setting change keeps the chosen leg while it starts at the same skill
    W.Click(n.ui.checks.neutral)
    eq(v.leg, 2)
    W.Click(n.ui.checks.neutral)
    W.Click(n.ui.chips[1])
    -- many stops: every one has its row in the list, which scrolls; the chosen stop stays beside it
    n.view.route = {}
    for i = 1, 10 do n.view.route[i] = { kind = "vendor", title = "STOP_VENDOR_BUY", lines = {}, index = i, sig = "s" .. i } end
    n.Refresh()
    for i = 1, 10 do assert(n.ui.nodes[i]:IsShown(), "stop " .. i) end
    assert(n.ui.act1:IsShown(), "the chosen stop keeps its button")
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
    assert(b.sub:GetText():find(n.view.state.recipes[s.segs[1].rid].name, 1, true))
    assert(b.sub:GetText():find("x" .. s.crafts, 1, true))
    n.Select(1) -- the skill stretch shows on a stop that is neither chosen nor "here"
    if not rawget(b.here, "shown") then assert((b.side:GetText() .. b.sub:GetText()) ~= "") end
    local head = n.ui.net:GetText()
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
    assert(n.ui.tool1:IsShown()); assert(not n.ui.tool2:IsShown(), "no lots button away from the auction")
    assert(n.ui.act1:IsShown() and not n.ui.act1:IsEnabled(), "the Buy button waits for the auction house")
    W.Click(n.ui.tool1)
    assert(list and #list.terms > 0 and list.terms[1]:find(";", 1, true))
    n.atAH = true
    n.Select(ah)
    assert(n.ui.tool2:IsShown())
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

test("a route tile switches at once from the result; the runs of each route are kept", function()
    local n = game()
    n.Toggle(); n.Calculate()
    local calls = { v = 0, l = 0 }
    local V, Lg = n.Variants, n.Legs
    n.Variants = function(...) calls.v = calls.v + 1; return V(...) end
    n.Legs = function(...) calls.l = calls.l + 1; return Lg(...) end
    local first = n.view.mode
    local other
    for _, x in ipairs(n.view.variants) do if x.plan and x.mode ~= first then other = x.mode end end
    assert(other, "a second route")
    W.Click(n.ui.modes[other])
    eq(n.view.mode, other)
    eq(calls.v, 0, "no new plans for a tile click")
    assert(#n.view.route > 0)
    assert(n.ui.route:IsShown(), "the graph stays, no full calculation screen")
    local legs = calls.l
    W.Click(n.ui.modes[first])
    W.Click(n.ui.modes[other])
    eq(calls.l, legs, "switching back uses the kept runs")
    eq(calls.v, 0)
    eq(n.db.prefs.mode, other)
    n.Variants, n.Legs = V, Lg
end)

test("the runs of a new route build in steps while its graph is shown", function()
    local n = game()
    n.Toggle(); n.Calculate()
    local first = n.view.mode
    local other
    for _, x in ipairs(n.view.variants) do
        if x.plan and x.mode ~= first and not n.EARN[x.mode] then other = x.mode end
    end
    if not other then return end
    local t = 0
    debugprofilestop = function() t = t + 5; return t end
    W.Click(n.ui.modes[other])
    local busy = n.BusyKind()
    if busy then
        eq(busy, "legs")
        assert(n.ui.route:IsShown(), "the graph shows while the runs build")
        assert(not n.ui.progress:IsShown(), "no full-screen progress")
        assert(n.ui.chipNote:GetText():find("%%"), n.ui.chipNote:GetText())
        eq(n.ui.calc:GetText(), n.L.RECALC)
        for _ = 1, 10000 do if not n.Busy() then break end; W.Click(n.calcDriver, "OnUpdate") end
    end
    debugprofilestop = nil
    assert(not n.Busy())
    assert(n.view.legs and #n.view.legs > 0, "the runs are there")
end)

test("many routes page with arrows instead of squeezing the tiles", function()
    local n = game()
    n.Toggle(); n.Calculate()
    local plan = n.view.plan
    for _, x in ipairs(n.view.variants) do x.plan = x.plan or plan end
    n.Refresh()
    local shown = 0
    for i = 1, #n.view.variants do
        local b = n.ui.varTiles[i]
        if b:IsShown() then shown = shown + 1; assert(b:GetWidth() >= 130, "tile width " .. b:GetWidth()) end
    end
    assert(shown < #n.view.variants, "not all tiles at once: " .. shown)
    assert(n.ui.varNext:IsShown())
    W.Click(n.ui.varNext)
    assert(n.ui.varPrev:IsEnabled())
    -- the chosen route comes into view
    W.Click(n.ui.modes[n.MODES[#n.MODES]])
    assert(n.ui.varTiles[#n.MODES]:IsShown())
end)

test("the stop card shows two rows without a scroll bar", function()
    local n = game()
    n.Toggle(); n.Calculate()
    -- the card's title takes 36 pixels and its bottom inset 12; the rows are 28 high
    assert(n.ui.detailH - 36 - 12 >= 2 * 28, "stop card body: " .. (n.ui.detailH - 48))
end)

test("an event the client does not know never stops the others from registering", function()
    -- the Forever client has no TRADE_SKILL_UPDATE or AUCTION_ITEM_LIST_UPDATE
    W.unknownEvents = { TRADE_SKILL_UPDATE = true, AUCTION_ITEM_LIST_UPDATE = true }
    local ok, err = pcall(game)
    W.unknownEvents = nil
    assert(ok, err)
    local f
    for _, x in ipairs(W.frames) do if rawget(x, "_events").MERCHANT_SHOW then f = x end end
    assert(f, "MERCHANT_SHOW registered")
    local ev = rawget(f, "_events")
    assert(ev.AUCTION_HOUSE_SHOW and ev.COMMODITY_SEARCH_RESULTS_UPDATED and ev.TRAINER_SHOW)
    assert(not ev.TRADE_SKILL_UPDATE)
    -- with C_EventUtils the unknown names are skipped before the call
    C_EventUtils = { IsEventValid = function(e) return e ~= "TRADE_SKILL_UPDATE" end }
    W.unknownEvents = { TRADE_SKILL_UPDATE = true }
    ok, err = pcall(game)
    W.unknownEvents, C_EventUtils = nil, nil
    assert(ok, err)
end)

-- ---------- the run as stops, and buying from them ----------

test("progress: a stop is done once its items are in the bags, in the stops' order", function()
    local c = core()
    local route = {
        { kind = "bank", title = "STOP_BANK", lines = { { id = 1, n = 10 } } },
        { kind = "ah", title = "STOP_AH_BUY", lines = { { id = 1, n = 20, price = 100, name = "Cloth" }, { n = 1, name = "Pattern" } } },
        { kind = "craft", title = "STOP_CRAFT", lines = {} },
        { kind = "sell", title = "STOP_AH_SELL", lines = { { id = 4, n = 2 } } },
    }
    local st = { items = { [1] = { bags = 5 } } }
    local bags = 5
    local function have() return bags end
    local p = c.Progress(route, st, have)
    eq(p[1].done, false); eq(p[1].lines[1].left, 10)
    bags = 15
    p = c.Progress(route, st, have)
    eq(p[1].done, true, "the bank's ten arrived")
    eq(p[2].lines[1].got, 0, "the same item of the next stop still waits")
    bags = 27
    p = c.Progress(route, st, have)
    eq(p[2].lines[1].left, 8)
    bags = 40
    p = c.Progress(route, st, have)
    eq(p[2].lines[1].done, true)
    eq(p[2].done, false, "a pattern has no item to count: never done by itself")
    eq(p[3].done, false); eq(p[4].done, false)
    -- where the player stands: the first stop of the open place that is not done
    eq(c.Here(route, p, nil), nil)
    eq(c.Here(route, p, "bank"), nil, "the bank stop is done")
    eq(c.Here(route, p, "ah"), 2)
    eq(c.Here(route, p, "vendor"), nil)
    p[2].done = true
    eq(c.Here(route, p, "ah"), 4, "then the selling stop")
    -- what is left to buy
    p = c.Progress(route, st, function() return 27 end)
    local q, hand = c.BuyQueue(route[2], p[2])
    eq(#q, 1); eq(q[1].n, 8); eq(q[1].unit, 100); eq(q[1].line, 1); eq(hand, 1)
end)

test("the price guard and the click counter", function()
    local c = core()
    eq(c.Dear(110, 100, 10), false, "at the guard: fine")
    eq(c.Dear(111, 100, 10), true)
    eq(c.Dear(100, 0, 10), false, "no planned price: nothing to compare")
    eq(c.Dear(500, 100, 0), true)
    local at, of = c.BuyClicks(2, 1, false)
    eq(at, 1); eq(of, 4)
    eq((c.BuyClicks(2, 1, true)), 2)
    eq((c.BuyClicks(2, 2, false)), 3)
    eq((c.BuyClicks(2, 2, true)), 4)
end)

test("a vendor sells whole stacks: need 4, sold in fives, buys 5", function()
    local c = core()
    local node = { kind = "vendor", title = "STOP_VENDOR_BUY", lines = {
        { id = 3, n = 4, name = "Blue Dye" }, { id = 5, n = 7, name = "Fine Thread" }, { id = 9, n = 1, name = "Elsewhere" } } }
    local goods = { { index = 1, id = 3, price = 250, stack = 5 }, { index = 2, id = 5, price = 100, stack = 1 } }
    local plan = c.VendorPlan(node, nil, goods, 100000)
    eq(#plan.buys, 2)
    local dye = plan.buys[1]
    eq(dye.stacks, 1); eq(dye.units, 5); eq(dye.need, 4); eq(dye.extra, 1); eq(dye.cost, 250)
    eq(plan.buys[2].units, 7); eq(plan.buys[2].extra, 0)
    eq(plan.cost, 950); eq(plan.missing, 1, "one line this vendor does not sell"); eq(plan.short, false)
    -- need 6 of fives is two stacks; what is in the bags already is not bought again
    local p = { lines = { { left = 6 }, { done = true, left = 0 }, { left = 1 } } }
    plan = c.VendorPlan(node, p, goods, 100000)
    eq(#plan.buys, 1); eq(plan.buys[1].stacks, 2); eq(plan.buys[1].units, 10)
    -- not enough money: as many stacks as it covers, and it says so
    plan = c.VendorPlan(node, nil, goods, 300)
    eq(plan.short, true); eq(plan.cost, 250); eq(#plan.buys, 1)
    -- a limited stock
    goods[2].avail = 3
    plan = c.VendorPlan(node, nil, goods, 100000)
    eq(plan.buys[2].units, 3); eq(plan.missing, 2)
end)

local function stopOf(n, title)
    for i, s in ipairs(n.view.route) do if s.title == title then return i end end
end

test("the auction stop buys by clicks: two a line, never from an event", function()
    local n = game()
    n.db.prefs.useBags, n.db.prefs.useBank = false, false
    n.Toggle(); n.Calculate()
    local ah = stopOf(n, "STOP_AH_BUY")
    assert(ah, kinds(n.view.route))
    n.Select(1)
    W.Fire("AUCTION_HOUSE_SHOW")
    eq((n.Selected()), ah, "arriving chooses the stop to do here")
    assert(rawget(n.ui.nodes[ah].here, "_shown"), "You are here")
    local node = n.view.route[ah]
    local all = #node.lines
    local line = node.lines[1]
    local a = n.StopAction(ah)
    eq(a.counter.at, 1); eq(a.counter.of, 2 * all)
    assert(n.ui.act1:IsEnabled())
    eq(#W.calls, 0, "nothing is asked before a click")
    W.Click(n.ui.act1)
    eq(W.calls[1][1], "start"); eq(W.calls[1][2], line.id); eq(W.calls[1][3], line.n)
    assert(not n.ui.act1:IsEnabled(), "waits for the price")
    W.Click(n.ui.act1)
    eq(#W.calls, 1, "a click while waiting does nothing")
    W.Fire("COMMODITY_PRICE_UPDATED", line.price, line.price * line.n)
    eq(#W.calls, 1, "the price coming in buys nothing")
    a = n.StopAction(ah)
    eq(a.counter.at, 2)
    assert(a.primary[2] and not a.primary.warn, "at the planned price: plain Buy")
    W.Click(n.ui.act1)
    eq(W.calls[2][1], "confirm"); eq(W.calls[2][2], line.id); eq(W.calls[2][3], line.n)
    W.Fire("COMMODITY_PURCHASE_SUCCEEDED")
    eq(#W.calls, 2)
    eq(n.buy.bought, 1); eq(n.buy.spent, line.price * line.n)
    a = n.StopAction(ah)
    if all > 1 then
        eq(a.counter.at, 3)
        assert(n.ui.detail.rows[1].mark:GetText():find(n.L.MARK_BOUGHT, 1, true))
    else
        eq(a.primary[2], nil, "all bought: the button rests")
    end
    -- leaving the auction house ends the buying; the button waits again
    W.Fire("AUCTION_HOUSE_CLOSED")
    a = n.StopAction(ah)
    eq(a.primary[2], nil); eq(a.hint, n.L.HINT_AH_AWAY)
end)

test("a price above the plan asks first; Skip leaves the line; a refusal is told", function()
    local n = game()
    n.db.prefs.useBags, n.db.prefs.useBank = false, false
    n.Toggle(); n.Calculate()
    local ah = stopOf(n, "STOP_AH_BUY")
    W.Fire("AUCTION_HOUSE_SHOW")
    local node = n.view.route[ah]
    local line = node.lines[1]
    W.Click(n.ui.act1)
    local dear = math.floor(line.price * 1.5)
    W.Fire("COMMODITY_PRICE_UPDATED", dear, dear * line.n)
    local a = n.StopAction(ah)
    assert(a.primary.warn and a.bad, "the button turns into Buy anyway")
    assert(a.primary[1]:find(n.L.BUY_ANYWAY:match("^[^%%]+"), 1, true), a.primary[1])
    -- a wider guard takes the same price without asking, and plans nothing
    local plan = n.view.plan
    n.SetPref("guard", 60)
    eq(n.view.plan, plan)
    assert(not n.StopAction(ah).primary.warn)
    n.SetPref("guard", 10)
    -- Skip: the price asked is given up, the next line comes
    local calls = #W.calls
    W.Click(n.ui.act2)
    eq(W.calls[calls + 1][1], "cancel")
    assert(n.ui.detail.rows[1].mark:GetText():find(n.L.MARK_SKIPPED, 1, true))
    if #node.lines > 1 then
        eq(n.buy.i, 2)
        -- sold out: the button asks again, with the reason under it
        W.Click(n.ui.act1)
        W.Fire("COMMODITY_PRICE_UNAVAILABLE")
        a = n.StopAction(ah)
        eq(a.hint, n.L.BUY_ERR_SOLD); assert(a.bad and a.primary[2])
        -- the game refused the purchase
        W.Click(n.ui.act1)
        local l2 = node.lines[2]
        W.Fire("COMMODITY_PRICE_UPDATED", l2.price, l2.price * l2.n)
        W.Click(n.ui.act1)
        W.Fire("COMMODITY_PURCHASE_FAILED")
        a = n.StopAction(ah)
        eq(a.hint, n.L.BUY_ERR_BUY); eq(n.buy.bought, 0)
        -- no answer at all: after a while the button is free again
        W.Click(n.ui.act1)
        W.RunTimers()
        eq(n.StopAction(ah).hint, n.L.BUY_ERR_SILENT)
    end
end)

test("an item that is not a commodity is left to the player; no purchase API, no button", function()
    local n = game({ handOnly = { [1] = true, [2] = true, [3] = true, [5] = true } })
    n.db.prefs.useBags, n.db.prefs.useBank = false, false
    n.Toggle(); n.Calculate()
    local ah = stopOf(n, "STOP_AH_BUY")
    W.Fire("AUCTION_HOUSE_SHOW")
    local lines = #n.view.route[ah].lines
    for _ = 1, lines do W.Click(n.ui.act1) end
    eq(#W.calls, 0, "never asked for")
    local a = n.StopAction(ah)
    eq(a.primary[2], nil); assert(a.bad)
    eq(a.hint, n.L.HINT_HAND:format(lines))
    assert(n.ui.detail.rows[1].mark:GetText():find(n.L.MARK_HAND, 1, true))
    C_AuctionHouse = nil
    n.buy.sig = nil
    a = n.StopAction(ah)
    eq(a.primary[2], nil); eq(a.hint, n.L.HINT_AH_NOAPI)
end)

test("the vendor stop buys everything in one click, whole stacks", function()
    local n = game({ vendor = { { 3, 250, 5 }, { 5, 100 } } })
    n.Toggle(); n.Calculate()
    local vs = stopOf(n, "STOP_VENDOR_BUY")
    assert(vs, kinds(n.view.route))
    local node = n.view.route[vs]
    W.Fire("MERCHANT_CLOSED")
    n.Select(vs)
    local a = n.StopAction(vs)
    eq(a.primary[2], nil); eq(a.hint, n.L.HINT_V_AWAY)
    W.Fire("MERCHANT_SHOW")
    eq((n.Selected()), vs)
    a = n.StopAction(vs)
    assert(a.primary[2], "one button")
    local want, cost = {}, 0
    for _, l in ipairs(node.lines) do
        if l.id == 3 then want[1] = math.ceil(l.n / 5) * 5; cost = cost + want[1] / 5 * 250 end
        if l.id == 5 then want[2] = l.n; cost = cost + l.n * 100 end
    end
    assert(want[1] or want[2])
    eq(a.vendor.cost, cost)
    local money = W.money
    W.Click(n.ui.act1)
    eq(W.bought[1], want[1]); eq(W.bought[2], want[2])
    eq(W.money, money - cost)
    -- the items are in the bags: the stop is done and the button rests
    W.Fire("BAG_UPDATE_DELAYED")
    a = n.StopAction(vs)
    eq(a.primary[2], nil); eq(a.pill[1], n.L.STOP_DONE)
    assert(rawget(n.ui.nodes[vs].tick, "_shown"), "a tick on the stop")
    W.Click(n.ui.act1)
    eq(W.bought[1], want[1], "nothing is bought twice")
end)

test("a vendor without the money buys what it covers and says so", function()
    local n = game({ vendor = { { 3, 250, 5 }, { 5, 100 } }, money = 120 })
    n.Toggle(); n.Calculate()
    local vs = stopOf(n, "STOP_VENDOR_BUY")
    n.Select(vs)
    local a = n.StopAction(vs)
    assert(a.bad and a.hint == n.L.HINT_V_MONEY)
    if a.primary[2] then
        W.Click(n.ui.act1)
        assert(W.money >= 0, "never more than the money")
    end
end)

test("at the auction house the buy stop opens in the window beside it; its tab counts what is left", function()
    local n = game()
    n.db.prefs.useBags, n.db.prefs.useBank = false, false
    n.Recalc(false)
    local ah = stopOf(n, "STOP_AH_BUY")
    assert(ah)
    local lines = #n.view.route[ah].lines
    eq(n.SideLeft(), lines)
    W.Fire("AUCTION_HOUSE_SHOW")
    local side = n.SideWindow()
    assert(side:IsShown(), "the big window is closed: the small one comes")
    local T = GulliHUD.side
    assert(T.open.CraftProfit and not (T.strip and T.strip:IsShown()), "alone there: no tabs")
    assert(n.sui.run:GetText():find(n.Skin.Upper(n.L.SIDE_STOP:format(ah, #n.view.route)), 1, true), n.sui.run:GetText())
    -- its button is the stop's button
    local p = n.sui.panel
    eq(p.act1:GetText(), n.StopAction(ah, true).primary[1])
    W.Click(p.act1)
    eq(W.calls[1][1], "start")
    local line = n.view.route[ah].lines[1]
    W.Fire("COMMODITY_PRICE_UPDATED", line.price, line.price * line.n)
    W.Click(p.act1)
    eq(W.calls[2][1], "confirm")
    W.Fire("COMMODITY_PURCHASE_SUCCEEDED")
    eq(n.buy.bought, 1)
    -- the bags got them: one line less on the tab
    W.items[line.id].bags = (W.items[line.id].bags or 0) + line.n
    W.Fire("BAG_UPDATE_DELAYED")
    eq(n.SideLeft(), lines - 1)
    -- with another module's window in the same place there are tabs
    local other = W.stub()
    rawset(other, "docked", false); rawset(other, "bar", W.stub())
    n.Skin.SideAdd({ key = "Crates", order = 10, title = "Gulli Waylaid Crates", icon = "i", window = function() return other end })
    n.Skin.SideOpen("Crates")
    assert(T.strip:IsShown())
    eq(T.strip.tabs[2].key, "CraftProfit")
    if lines > 1 then eq(T.strip.tabs[2].badge.text:GetText(), tostring(lines - 1)) end
    W.Fire("AUCTION_HOUSE_CLOSED")
    assert(not side:IsShown(), "it leaves with the auction house")
    -- the switch in Settings keeps it away, and so does the big window
    n.SetPref("side", false)
    W.Fire("AUCTION_HOUSE_SHOW")
    assert(not side:IsShown())
    W.Fire("AUCTION_HOUSE_CLOSED")
    n.SetPref("side", true)
    n.Toggle()
    W.Fire("AUCTION_HOUSE_SHOW")
    assert(not side:IsShown(), "the big window shows the stop itself")
end)

test("the buying settings: the guard stepper and the side window switch plan nothing", function()
    local n = game()
    n.Toggle(); n.Calculate()
    local plan = n.view.plan
    local st = n.ui.steppers.guard
    assert(st and n.ui.checks.side)
    W.Click(st.plus)
    eq(n.db.prefs.guard, 15)
    W.Click(st.minus); W.Click(st.minus)
    eq(n.db.prefs.guard, 5)
    eq(n.view.plan, plan)
    W.Click(n.ui.reset)
    eq(n.Prefs(n.db.prefs).guard, 10)
end)

W.finish()
