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

test("crafting materials always sell; the share that sells is for finished goods", function()
    Fake({})
    local n = Load()
    for _, id in ipairs({ 4339, 14342, 2840, 3575 }) do assert(n.IsReagent(id), "reagent " .. id) end
    local robe = 14152 -- Robe of the Archmage: no recipe asks for it
    assert(not n.IsReagent(robe))
    local st = { items = { [4339] = { ah = 1000, vend = 100, age = 0 }, [robe] = { ah = 1000, vend = 100, age = 0 } } }
    local P = n.Prefs({ chance = 50 })
    near(n.SellValue(st, P, 4339, 0), 1000 * 0.95, "a bolt sells every time")
    near(n.SellValue(st, P, robe, 0), 0.5 * 950 + 0.5 * (100 - n.Deposit(st.items[robe])), "a robe by the share")
    eq(n.SellChance(P, 4339), 1); eq(n.SellChance(P, robe), 0.5)
    -- the value tooltip says so
    local tip = {}
    n.ValueTip(tip, st, P, { out = 4339, count = 1 }, { how = "ah", value = 950 })
    eq(tip[#tip][1], n.L.TIP_SURE)
    assert(tip[1][1]:find("100%%"), "sold 100% of the time")
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
    -- the game's grey moves the whole recipe: Stormcloth Headband is 255/270/285 in the data
    -- and grey at 245 in WoW Forever, so it never counts as orange past its grey
    t = c.Thresholds({ 255, 270, 285 }, nil, 245, false)
    eq(t[3], 245); eq(t[2], 215); eq(t[1], 205)
    eq(c.Chance({ skill = t }, 245), 0, "grey gives no point")
    near(c.Chance({ skill = t }, 243), 2 / 30)
    assert(c.Chance({ skill = t }, 230) < 1, "past yellow a craft is no sure point")
    t = c.Thresholds({ 180, 200, 215, 230 }, nil, 250, false)
    eq(t[1], 200); eq(t[2], 220); eq(t[3], 250)
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
    -- Wowhead gives only green and grey for some recipes: they still win over Classic's levels
    local hat = c.Data.spell[12081]
    eq(hat[3], 245, "Admiral's Hat grey"); eq(hat[2], 240); eq(hat[1], 235)
    eq(c.Data.spell[3304][3], 75, "Smelt Tin grey"); eq(c.Data.spell[3304][2], 65)
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
    local e = c.Earn(st, prefs({ maxBuy = 40, minGain = 0 }))
    assert(e.net > 0)
    assert((e.ahBuy.cloth or 0) <= 40 + 6, "cloth bought: " .. tostring(e.ahBuy.cloth))
    local more = c.Earn(st, prefs({ maxBuy = 200, minGain = 0 }))
    assert(more.crafts > e.crafts)
    -- 50 bags at most; the bolts for them are preparation, beside them
    eq(c.EARN_MAX, 50)
    assert(c.LevelCrafts(more) <= c.EARN_MAX, "bags: " .. c.LevelCrafts(more))
    assert(more.prepCrafts > 0, "the bolts")
    -- without the auction, only own cloth counts
    st.items.cloth.bags = 12
    local own = c.Earn(st, prefs({}), true)
    eq(own.ahBuy.cloth, nil)
end)

-- A profit craft must gain at least minGain (5 silver at first), and the auction never takes
-- more of one item than are on sale there now (when the lots were read).
test("a profit run keeps to the least gain per craft and to what the market takes", function()
    local c = core()
    local function st()
        return { skill = 100, cap = 150, level = 30, items = {
            cloth = { name = "Linen Cloth", ah = 1, age = 0, vend = 1, bags = 1000 },
            bag = { name = "Linen Bag", ah = 400, age = 0, vend = 100 },
            good = { name = "Good Bag", ah = 5000, age = 0, vend = 100 },
        }, recipes = {
            bag = { name = "Linen Bag", skill = { 45, 70, 95 }, r = { cloth = 3 }, out = "bag", learned = true },
            good = { name = "Good Bag", skill = { 45, 70, 95 }, r = { cloth = 4 }, out = "good", learned = true },
        } }
    end
    eq(c.DEFAULTS.minGain, 500, "5 silver at first")
    local s1 = st()
    s1.recipes.good = nil
    local e = c.Earn(s1, prefs({ maxSell = 0 }), true)
    eq(e.crafts, 0, "a bag that gains under 5 silver is no profit run")
    local any = c.Earn(s1, prefs({ maxSell = 0, minGain = 0 }), true)
    assert(any.crafts > 0, "with any gain it is")
    -- no market depth known: up to EARN_MAX
    local s2 = st()
    local free = c.Earn(s2, prefs({ maxSell = 0 }), true)
    eq(c.LevelCrafts(free), c.EARN_MAX)
    -- 7 on sale: the auction takes 7, the rest would go to a vendor at a loss
    s2.items.good.lots = { t = 1000, l = { { 5000, 4 }, { 5100, 3 } } }
    s2.now = 1000 + 60
    eq(c.MarketTake(s2, prefs({ maxSell = 0 }), "good"), 7)
    eq(c.MarketTake(s2, prefs({ maxSell = 5 }), "good"), 5, "maxSell when smaller")
    local held = c.Earn(s2, prefs({ maxSell = 0 }), true)
    eq(c.LevelCrafts(held), 7)
    -- lots older than a day say nothing
    s2.now = 1000 + c.LOTS_FRESH + 1
    eq(c.MarketTake(s2, prefs({ maxSell = 0 }), "good"), math.huge)
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
    local L = c.LevelCrafts
    local cheap, fast = L(all[1]), L(all[#all])
    assert(cheap > fast + 2)
    -- a limit between them: every route keeps within it, and the cheapest one within it is found
    local cap = math.floor((cheap + fast) / 2)
    local f = c.Frontier(st, prefs({ maxSell = 5, maxCrafts = cap }))
    assert(#f >= 1)
    for _, p in ipairs(f) do assert(L(p) <= cap + 0.5, "crafts " .. L(p) .. " over " .. cap); assert(not p.many) end
    for _, p in ipairs(all) do
        if L(p) <= cap + 0.5 then assert(f[1].net >= p.net - 1, "the cheapest within the limit") end
    end
    -- a limit nobody keeps: only the route with the fewest crafts, marked
    f = c.Frontier(st, prefs({ maxSell = 5, maxCrafts = math.max(1, math.floor(fast / 2)) }))
    eq(#f, 1); assert(f[1].many); eq(L(f[1]), fast)
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

-- Blacksmithing at 170 with no auction addon: iron and steel come only from the auction, so
-- without a price no recipe could be priced and the route stopped at once ("no known recipe").
local function smith()
    local items = {
        iron = { name = "Iron Bar", vend = 200 },
        steel = { name = "Steel Bar", vend = 250 },
        stone = { name = "Heavy Grinding Stone", vend = 200 },
        dye = { name = "Green Dye", buy = 200, vend = 50 },
        buckle = { name = "Green Iron Bracers", vend = 900 },
        helm = { name = "Green Iron Helm", vend = 1500 },
        boots = { name = "Steel Plate Boots", vend = 1800 },
        soul = { name = "Soulbound Thing", vend = 300, bop = true },
    }
    local recipes = {
        bracers = { name = "Green Iron Bracers", skill = { 165, 180, 200 }, r = { iron = 6, dye = 1 }, out = "buckle", learned = true },
        helm = { name = "Green Iron Helm", skill = { 170, 190, 210 }, r = { iron = 12, stone = 1, dye = 1 }, out = "helm", learned = true },
        boots = { name = "Steel Plate Boots", skill = { 185, 205, 225 }, r = { steel = 8, stone = 2 }, out = "boots",
                  src = { t = "trainer", cost = 3000 } },
    }
    return { skill = 170, cap = 225, level = 40, items = items, recipes = recipes }
end

test("no auction prices at all: the route still goes on, at guessed auction prices", function()
    local c, st = core(), smith()
    local P = prefs({ target = 225 })
    local plan = c.Plan(st, P)
    eq(plan.reached, 225, "the whole way, not a stop at 170")
    eq(plan.warn, nil)
    local ah = has(c.Route(st, plan), "STOP_AH_BUY")
    assert(ah, "the bars come from the auction")
    for _, l in ipairs(ah.lines) do
        if l.id then
            eq(l.guess, true, l.name .. " is a guess")
            eq(l.price, st.items[l.id].vend * c.AH_GUESS)
        end
    end
    -- the way as runs has no unknown stretch either
    for _, l in ipairs(c.Legs(st, P)) do eq(l.unknown, nil) end
    -- a guess is no plan to guard: the real price decides
    for _, q in ipairs(c.BuyQueue(ah)) do if q.id then eq(q.unit, nil) end end
end)

test("no price addon: the auction switches are off and grey, a banner says so, only levelling routes", function()
    local n = game({ auctionator = false })
    n.Toggle(); n.Calculate()
    local v = n.view
    eq(v.state.noPrices, true)
    for _, x in ipairs(v.variants) do assert(not n.EARN[x.mode], "no profit route from guessed prices: " .. x.mode) end
    assert(v.plan, "a levelling route all the same")
    assert(n.ui.priceBanner:IsShown(), "the banner tells why")
    assert(n.ui.priceBanner.text:GetText():find("x" .. n.AH_GUESS, 1, true))
    n.Tab(5)
    for _, k in ipairs({ "buyAH", "sellAH" }) do
        eq(n.ui.checks[k]:GetChecked(), false, k .. " shows off")
        eq(n.ui.checks[k]:IsEnabled(), false, k .. " is grey")
    end
    eq(n.ui.checks.useBags:IsEnabled(), true)
    eq(n.ui.steppers.maxSell.plus:IsEnabled(), false, "the auction steppers are grey too")
    eq(n.Prefs(n.db.prefs).buyAH, true, "the player's own choice is kept for when prices come")
    n.Tab(1)
    -- with a price addon: profit routes, no banner, the switches work
    n = game()
    n.Toggle(); n.Calculate()
    eq(n.view.state.noPrices, nil)
    local earn = false
    for _, x in ipairs(n.view.variants) do if n.EARN[x.mode] then earn = true end end
    assert(earn, "the profit routes are back")
    assert(not n.ui.priceBanner:IsShown())
    n.Tab(5)
    eq(n.ui.checks.buyAH:IsEnabled(), true)
    eq(n.ui.checks.buyAH:GetChecked(), true)
    n.Tab(1)
end)

test("a guessed price: an old price first, else the sell price times AH_GUESS; never for soulbound items", function()
    local c, st = core(), smith()
    local P = prefs()
    eq(c.Guess(st.items.iron, P), 200 * c.AH_GUESS)
    eq(c.Guess(st.items.soul, P), nil)
    eq(c.Guess({ vend = 0 }, P), nil)
    eq(c.Guess({ ah = 700, age = 30, vend = 10 }, P), 700)
    eq(c.Guess({ ah = 700, age = 0, vend = 10 }, P), nil, "a fresh price is no guess")
    -- a real price wins over the guess
    st.items.iron.ah, st.items.iron.age = 500, 0
    local plan = c.Plan(st, prefs({ target = 225 }))
    for _, l in ipairs(has(c.Route(st, plan), "STOP_AH_BUY").lines) do
        if l.id == "iron" then eq(l.guess, nil); eq(l.price, 500) end
    end
end)

test("every price addon is read: auxForever, Naowh Forever, TSM, Hammerprice; a fresh price wins", function()
    local n = game({ auctionator = false })
    eq(n.AuctionPrice(1), nil)
    eq(n.HasPrices(), false)
    W.now = 1700000000
    local now = W.now
    NaowhForever = { AuctionPrice = function(id) if id == 1 then return 150, now - 10 * 86400 end end }
    local p, age = n.AuctionPrice(1)
    eq(p, 150); assert(age > 9.9 and age < 10.1, "age from the time it was seen")
    AuxForeverAPI = { IsReady = function() return true end, GetLatestPrice = function(id) if id == 1 then return 170, 1 end end }
    eq(n.AuctionPrice(1), 170, "aux has the fresher price")
    AuxForeverAPI.IsReady = function() return false end
    eq(n.AuctionPrice(1), 150, "aux before its prices loaded knows nothing")
    AuxForeverAPI = nil
    TSM_API = { GetCustomPriceValue = function(src, s) eq(src, "DBMinBuyout"); eq(s, "i:1"); return 160 end }
    eq(n.AuctionPrice(1), 160)
    TSM_API = nil
    Hammerprice = { GetPrice = function() error("broken") end }
    eq(n.AuctionPrice(1), 150, "an addon that fails is skipped")
    eq(table.concat(n.PriceAddons(), ","), "Naowh Forever,Hammerprice")
    eq(n.HasPrices(), true)
    NaowhForever, Hammerprice = nil, nil
end)

test("Gulli's own scans are a price source, the first one, once they hold a price", function()
    local n = game({ auctionator = false })
    local ready = false
    GulliAuction = { Ready = function() return ready end,
                     Price = function(id) if id == 1 then return 140, 0 elseif id == 2 then return 90, 9 end end }
    eq(n.HasPrices(), false, "an empty list is no price addon: the price settings stay grey")
    eq(n.AuctionPrice(1), nil)
    ready = true
    eq(n.HasPrices(), true)
    eq(n.PriceAddons()[1], "Gulli Auction")
    eq(n.AuctionPrice(1), 140)
    local now = W.now
    NaowhForever = { AuctionPrice = function(id) return 100, now end }
    eq(n.AuctionPrice(1), 140, "the own scan of this realm goes first")
    eq(n.AuctionPrice(2), 100, "an old own price gives way to a fresh one")
    eq(n.AuctionPrice(3), 100, "what the own scan never saw comes from the others")
    GulliAuction, NaowhForever = nil, nil
end)

test("another player's profession (a trade link) is never saved; one the spellbook lacks is not listed", function()
    local n = game({ linked = true, spellbook = { { "Blacksmithing", 170, 225 } } })
    eq(n.char.profs.Tailoring, nil, "a linked window is not this character's")
    -- an older save that holds a profession the character does not have
    n = game({ spellbook = { { "Tailoring", SKILL, 225 } } })
    n.char.profs.Enchanting = { skill = 270, cap = 300, recipes = {} }
    n.char.current = "Enchanting"
    local names = {}
    for _, p in ipairs(n.Professions()) do names[#names + 1] = p.name end
    eq(table.concat(names, ","), "Tailoring")
    n.SetProfession("Enchanting")
    local st = n.State()
    eq(st and st.name, "Tailoring")
end)

test("Enchanting never keeps Tailoring recipes the game listed during a switch", function()
    local ench = { name = "Enchanting", skill = 168, cap = 225, recipes = {
        { id = 201, name = "Enchant Bracer - Minor Health", learned = true, diff = 0, grey = 190, r = { [1] = 1 } },
        { id = 101, name = "Bolt of Silk Cloth", learned = true, diff = 0, grey = 190, out = 2, r = { [1] = 4 }, prof = "Tailoring" },
    } }
    local n = game({ prof = ench, spellbook = { { "Tailoring", SKILL, 225 }, { "Enchanting", 168, 225 } } })
    local e = n.char.profs.Enchanting
    assert(e and e.recipes[201], "the enchant is saved")
    eq(e.recipes[101], nil, "a Tailoring recipe in the list is not Enchanting's")
    -- an older save that took them in: the next scan drops them, the plan never sees them
    e.recipes[103] = { name = "Silk Headband", learned = true, out = 6, r = { [2] = 3 } }
    W.otherRecipes = { [103] = "Tailoring" }
    n.char.current = "Enchanting"
    local st = n.State()
    eq(st.recipes[103], nil, "the plan leaves out a saved Tailoring recipe")
    W.Fire("TRADE_SKILL_LIST_UPDATE"); W.RunTimers()
    eq(e.recipes[103], nil, "the scan removes it")
    -- right after the switch the whole list is still Tailoring's: nothing is saved under Enchanting
    for _, r in ipairs(ench.recipes) do r.prof = "Tailoring" end
    e.recipes = { [201] = { name = "Enchant Bracer - Minor Health", learned = true, r = { [1] = 1 } } }
    W.Fire("TRADE_SKILL_LIST_UPDATE"); W.RunTimers()
    eq(e.recipes[101], nil, "a stale list is not saved")
    assert(e.recipes[201], "and what was saved stays")
    W.otherRecipes = nil
end)

test("a second profession makes a reagent when that is cheaper (Smelting for the bars), if it knows the recipe", function()
    local n = game({ spellbook = { { "Tailoring", SKILL, 225, "picon", 197 }, { "Mining", 120, 150, "micon", 186 } } })
    n.char.profs.Mining = { skill = 120, cap = 150, recipes = {
        [901] = { name = "Smelt Silk", learned = true, out = 1, count = 1, r = { [10] = 1 } },
        [902] = { name = "Smelt Better Silk", learned = false, out = 1, count = 1, r = { [11] = 1 } },
    } }
    W.items[10] = { name = "Silk Ore", ah = 5, age = 0, sell = 1 }
    W.items[11] = { name = "Rare Ore", ah = 1, age = 0, sell = 1 }
    W.items[1].bags, W.items[1].bank = 0, 0
    n.Toggle(); n.Calculate()
    local st = n.view.state
    eq(st.recipes[901] and st.recipes[901].other, "Mining")
    eq(st.recipes[901].skill, nil, "it never levels Tailoring")
    eq(st.recipes[902], nil, "a recipe the miner has not learned (too low a skill) is not offered")
    local prep
    for _, x in ipairs(n.view.route) do if x.prep then prep = x end end
    assert(prep, "the bars are made, not bought")
    local smelt = false
    for _, l in ipairs(prep.lines) do if l.recipe == 901 then smelt = true end end
    assert(smelt, "Smelt Silk is a line of the stop")
    for _, row in ipairs(n.Crafts(st, n.view.prefs)) do assert(row.recipe ~= 901, "no row of Tailoring's crafts") end
    for _, x in ipairs(n.view.variants) do
        if n.EARN[x.mode] and x.plan then
            for _, sg in ipairs(x.plan.segs) do assert(sg.rid ~= 901, "never a profit run of Tailoring") end
        end
    end
    -- its stop opens the Mining window, which does not become the current profession
    eq(n.ProfOf(901), "Mining")
    eq(n.ProfOf(101), "Tailoring")
    local opened
    C_TradeSkillUI.OpenTradeSkill = function(line) opened = line; return true end
    assert(n.OpenProfession(901))
    eq(opened, 186, "the Mining window")
    eq(n.helperOpen, "Mining")
    eq(n.char.current, "Tailoring")
    W.Fire("TRADE_SKILL_CLOSE")
    eq(n.helperOpen, nil)
end)

test("Enchanting: enchants make no item, so they only level; a wand can also earn", function()
    local n = game({
        items = { [8] = { name = "Strange Dust", sell = 10 }, [9] = { name = "Lesser Magic Wand", sell = 100 } },
        prof = { name = "Enchanting", skill = 100, cap = 150, recipes = {
            { id = 201, name = "Enchant Bracer - Minor Health", learned = true, diff = 0, grey = 125, r = { [8] = 1 } },
            { id = 202, name = "Lesser Magic Wand", learned = true, diff = 1, grey = 130, out = 9, r = { [8] = 1 } },
        } },
        spellbook = { { "Enchanting", 100, 150 } } })
    n.Toggle(); n.Calculate()
    local v = n.view
    eq(v.state.name, "Enchanting")
    assert(v.plan and v.plan.reached > 100, "an Enchanting route with guessed dust prices")
    for _, x in ipairs(v.variants) do
        if x.plan and n.EARN[x.mode] then
            for _, sg in ipairs(x.plan.segs) do assert(sg.rid ~= 201, "an enchant is never a profit run") end
        end
    end
end)

test("a result of the profession chosen before never shows after a switch", function()
    local n = game({ spellbook = { { "Tailoring", SKILL, 225 }, { "Cooking", 50, 75 } } })
    n.char.profs.Cooking = { skill = 50, cap = 75, recipes = {} }
    n.Toggle()
    local t = 0
    debugprofilestop = function() t = t + 3; return t end
    local job = n.RecalcJob(false)
    assert(not job:Step(1), "the Tailoring job runs in steps")
    n.char.current = "Cooking"
    while not job:Step(1) do end
    debugprofilestop = nil
    eq(n.view.plan, nil, "the Tailoring result is dropped")
end)

test("switching the profession never calculates: its last result, outdated, or Calculate", function()
    local n = game({ spellbook = { { "Tailoring", SKILL, 225 }, { "Cooking", 50, 75 } } })
    n.char.profs.Cooking = { skill = 50, cap = 75, recipes = {} }
    n.Toggle(); n.Calculate()
    local plan = n.view.plan
    assert(plan, "Tailoring calculated")
    n.SetProfession("Cooking")
    eq(n.char.current, "Cooking")
    eq(n.view.plan, nil, "Cooking waits for Calculate")
    eq(n.Busy(), false)
    n.SetProfession("Tailoring")
    eq(n.view.plan, plan, "the last Tailoring result comes back")
    eq(n.view.stale, "pick")
    eq(n.Busy(), false)
end)

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
    -- a white line before the reputation was read proves nothing: left out, and the banner asks for it
    W.tips[6][2] = { "Requires Cenarion Circle - Honored", 1, 1, 1 }
    eq(n.State().recipes[104].src.t, "rep")
    eq(n.RepUnknown()[1], "Cenarion Circle")
    -- no colour from the client: the reputation list decides
    W.tips[6][2] = { "Requires Cenarion Circle - Honored" }
    eq(n.State().recipes[104].src.t, "rep")
    W.factions = { { "Cenarion Circle", 5 } }
    eq(n.State().recipes[104].src.t, "rep", "Friendly is below Honored")
    eq(#n.RepUnknown(), 0, "the standing is known now")
    W.factions = { { "Cenarion Circle", 6 } }
    eq(n.State().recipes[104].src.t, "ah")
    W.tips[6][2] = { "Requires Cenarion Circle - Honored", 1, 1, 1 }
    eq(n.State().recipes[104].src.t, "ah", "met (white line, standing known): bought as before")
end)

test("the reputation is saved per character; until it is read, reputation patterns stay out", function()
    local n = game()
    n.Data.src[104] = { "v", 6, "Ally Gal|A" }
    n.Data.spell[104] = { 150, 160, 170 }
    n.db.vendor[6] = 9000
    W.tips[6] = { { "Pattern: Thing" }, { "Requires Thorium Brotherhood - Friendly", 1, 1, 1 } }
    -- the game gave no list yet (the reputation window was never opened)
    eq(n.State().recipes[104].src.t, "rep")
    eq(n.RepUnknown()[1], "Thorium Brotherhood")
    -- a folded group: what it shows is saved, the rest is still unknown
    W.factions = { { "Classic", 0, true, true }, { "Darnassus", 6 } }
    eq(n.State().recipes[104].src.t, "rep")
    eq(n.char.rep["Darnassus"], 6, "saved in the character's saved variables")
    eq(n.char.repFull, nil, "a folded group: not the whole list")
    eq(n.RepUnknown()[1], "Thorium Brotherhood")
    -- the reputation window opens the list: the plan goes stale and the banner has nothing to ask
    n.Toggle(); n.Calculate()
    eq(n.view.stale, nil)
    n.Refresh()
    assert(n.ui.repBanner:IsShown(), "the banner asks for the reputation window")
    assert(n.ui.repBanner.text:GetText():find("Thorium Brotherhood", 1, true))
    W.factions = { { "Classic", 0, true, false }, { "Darnassus", 6 }, { "Thorium Brotherhood", 5 } }
    n.RepChanged()
    eq(n.view.stale, true, "a new standing makes the plan outdated")
    eq(#n.RepUnknown(), 0)
    assert(not n.ui.repBanner:IsShown(), "read: the banner goes away")
    eq(n.char.repFull, true)
    eq(n.State().recipes[104].src.t, "ah", "Friendly is met")
    -- after a reload the list is empty again, the saved standing still counts
    W.factions = {}
    eq(n.State().recipes[104].src.t, "ah")
    -- a faction never met, once the whole list was read: not met, and nothing to ask for
    W.tips[6][2] = { "Requires Cenarion Circle - Friendly", 1, 1, 1 }
    eq(n.State().recipes[104].src.t, "rep")
    eq(#n.RepUnknown(), 0)
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
    -- no limit is the stepper's own button: + does nothing there, the button gives a number back
    W.Click(n.ui.budget.plus)
    eq(n.view.prefs.budget, 0)
    eq(n.ui.budget.plus:IsEnabled(), false)
    W.Click(n.ui.budget.inf)
    eq(n.view.prefs.budget, 50000)
    W.Click(n.ui.budget.plus)
    eq(n.view.prefs.budget, 100000)
    -- the target only marks the plan outdated: Recalculate plans it (owner's decision)
    W.Click(n.ui.target.minus)
    eq(n.db.prefs.target, 220)
    eq(n.view.plan.full.target, 225)
    eq(n.view.stale, "target")
    assert(n.ui.calc.tip == n.L.CALC_STALE_SET)
    n.Calculate()
    eq(n.view.plan.full.target, 220)
    eq(n.view.stale, nil)
    W.Click(n.ui.chance.minus)
    eq(n.view.prefs.chance, 75)
    W.Click(n.ui.maxSell.plus)
    eq(n.view.prefs.maxSell, 21)
    W.Click(n.ui.maxBuy.minus)
    eq(n.view.prefs.maxBuy, 30)
    -- + stops at the top (no hidden step past it); the button is no limit, saved as 0, and - or
    -- the button again bring back the number shown before
    for _ = 1, 25 do W.Click(n.ui.maxSell.plus) end
    eq(n.view.prefs.maxSell, 40)
    eq(n.ui.maxSell.plus:IsEnabled(), false)
    W.Click(n.ui.maxSell.minus); W.Click(n.ui.maxSell.minus)
    W.Click(n.ui.maxSell.inf)
    eq(n.view.prefs.maxSell, 0)
    eq(n.ui.maxSell.value:GetText(), n.L.NO_LIMIT)
    W.Click(n.ui.maxSell.minus)
    eq(n.view.prefs.maxSell, 38, "the number from before")
    W.Click(n.ui.maxBuy.inf)
    eq(n.view.prefs.maxBuy, 0)
    W.Click(n.ui.maxBuy.inf)
    eq(n.view.prefs.maxBuy, 30)
    W.Click(n.ui.maxBuy.inf)
    W.Click(n.ui.minGain.inf)
    eq(n.view.prefs.minGain, 0)
    eq(n.ui.minGain.value:GetText(), n.L.GAIN_ANY)
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

test("the crafts stepper: auto, a number of its own and no limit from its button's list", function()
    local n = game()
    n.Toggle(); n.Calculate()
    local st = n.ui.steppers.maxCrafts
    local auto = n.CraftCap(n.view.state, n.Prefs({}))
    eq(st.value:GetText(), n.L.CRAFTS_AUTO:format(auto))
    W.Click(st.plus)
    local own = n.db.prefs.maxCrafts
    assert(own > 0 and own > auto - 5, "a number of its own: " .. tostring(own))
    eq(st.value:GetText(), tostring(own))
    W.Click(st.minus)
    assert(n.db.prefs.maxCrafts > 0, "- stays a number: auto is picked from the list")
    -- the button opens a list of three; the chosen one is marked
    W.Click(st.inf)
    local m = n.Skin.limitMenu
    assert(m and m:IsShown(), "the list shows")
    eq(m.rows[1]:GetText(), n.L.CRAFTS_AUTO:format(auto))
    eq(m.rows[3]:GetText(), n.L.NO_LIMIT)
    W.Click(m.rows[3])
    eq(n.db.prefs.maxCrafts, -1)
    eq(st.value:GetText(), n.L.NO_LIMIT)
    assert(not m:IsShown())
    eq(st.plus:IsEnabled(), false, "+ does nothing without a limit")
    W.Click(st.inf); W.Click(m.rows[2])
    eq(n.db.prefs.maxCrafts, own - 5, "own: the number shown before")
    W.Click(st.inf); W.Click(m.rows[1])
    eq(n.db.prefs.maxCrafts, 0, "auto again")
    -- - from no limit brings the number back too
    n.db.prefs.maxCrafts = -1
    st:Refresh()
    W.Click(st.minus)
    assert(n.db.prefs.maxCrafts > 0)
end)

test("the guard's button is never ask: no price is dear then", function()
    local n = game()
    n.Toggle(); n.Calculate()
    local st = n.ui.steppers.guard
    W.Click(st.inf)
    eq(n.db.prefs.guard, -1)
    eq(st.value:GetText(), n.L.GUARD_NEVER)
    eq(n.Dear(1000, 10, n.Prefs(n.db.prefs).guard), false)
    eq(n.Dear(1000, 10, 0), true, "0% still asks at any rise")
    W.Click(st.inf)
    eq(n.db.prefs.guard, 10, "back to the number")
end)

test("a locked stepper greys its no limit button too", function()
    local n = game()
    n.Toggle(); n.Calculate()
    n.SetPref("level", false)
    n.Tab(5)
    local st = n.ui.steppers.budget
    eq(st.inf:IsEnabled(), false); eq(st.minus:IsEnabled(), false); eq(st.plus:IsEnabled(), false)
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
    assert(n.ui.tool1:IsShown())
    eq(n.ui.tool2:GetText(), n.L.MARK_DONE, "no lots button away from the auction: the mark tool instead")
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

test("a craft the player avoids is in no route, learned or not, and comes back", function()
    local c = core()
    local st, P = state(), prefs()
    local function used(plan, rid)
        for _, seg in ipairs(plan.segs) do if seg.rid == rid then return true end end
        return (plan.prep and plan.prep[rid] or 0) > 0 or plan.buyRecipes[rid] == true
    end
    local plan = c.Plan(st, P)
    local first = plan.segs[1].rid
    assert(st.recipes[first].learned, "the first craft of the plan is a learned one")
    st.recipes[first].skip = true
    c.ForgetMakers(st.recipes)
    local without = c.Plan(st, P)
    assert(not used(without, first), "the plan goes without it")
    for _, v in ipairs(c.Frontier(st, P)) do assert(not used(v, first), "no levelling route uses it") end
    for _, own in ipairs({ true, false }) do
        local e = c.Earn(st, P, own)
        assert(not used(e, first), "no profit route uses it")
    end
    for _, x in ipairs(c.Crafts(st, P)) do assert(x.recipe ~= first, "not offered as a craft now") end
    -- a recipe to buy or learn can be avoided too
    local st2 = state()
    for rid, r in pairs(st2.recipes) do if not r.learned then r.skip = true end end
    local p2 = c.Plan(st2, P)
    eq(next(p2.buyRecipes), nil, "no avoided recipe is bought or learned")
    eq(c.CanGet(st2.recipes.pants, P), false)
    -- the lists for the Settings card
    eq(#c.Skipped(st), 1); eq(c.Skipped(st)[1].recipe, first)
    local found, all = c.FindRecipes(st, "bolt of", 2)
    eq(#found, 2); assert(all >= 3, "three bolts in the example")
    assert(found[1].name:find("^Bolt of"))
    eq(#c.FindRecipes(st, "", 5), 0)
    -- by id: the recipe's own, the made item's, or a pasted link
    local byId = { recipes = { [3840] = { name = "Bolt of Silk Cloth", out = 4305 }, [8762] = { name = "Silk Headband", out = 7050 } } }
    eq(c.FindRecipes(byId, "8762", 5)[1].recipe, 8762)
    eq(c.FindRecipes(byId, "4305", 5)[1].recipe, 3840, "the id of the item it makes")
    eq(c.FindRecipes(byId, "|cffffd000|Henchant:8762|h[Silk Headband]|h|r", 5)[1].recipe, 8762)
    eq(c.FindRecipes(byId, "spell:3840", 5)[1].recipe, 3840)
    eq(#c.FindRecipes(byId, "999", 5), 0)
    st.recipes[first].skip = nil
    assert(used(c.Plan(st, P), first), "back in the plan")
end)

test("Without this craft at a craft stop plans again without it; Settings puts it back", function()
    local n = game()
    n.Toggle(); n.Calculate()
    local craft
    for i, s in ipairs(n.view.route) do if s.segs then craft = craft or i end end
    assert(craft, kinds(n.view.route))
    local a = n.StopAction(craft)
    local tool
    for _, t in ipairs(a.tools) do if t.skip then tool = t end end
    assert(tool and tool[1] == n.L.SKIP_CRAFT)
    local rid = tool.skip
    tool[2]()
    eq(n.db.skip[rid], true)
    eq(n.view.state.recipes[rid].skip, true)
    for _, s in ipairs(n.view.route) do
        for _, seg in ipairs(s.segs or {}) do assert(seg.rid ~= rid, "the new route has no such craft") end
    end
    -- the Settings card lists it; its button puts it back
    n.Tab(5)
    local rows, note = n.SkipRows()
    eq(#rows, 1); eq(rows[1].recipe, rid); eq(note, nil)
    local row = n.ui.skipRows[1]
    assert(row:IsShown()); eq(row.btn:GetText(), n.L.SKIP_BACK)
    W.Click(row.btn)
    eq(n.db.skip[rid], nil)
    eq(n.view.state.recipes[rid].skip, nil)
    rows, note = n.SkipRows()
    eq(#rows, 0); eq(note, n.L.SKIP_EMPTY)
    -- typing a name finds recipes to avoid
    n.ui.skipEdit:SetText(n.view.state.recipes[rid].name)
    rows = n.SkipRows()
    assert(#rows >= 1 and rows[1].skip == false)
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
    -- the game gives no realm name: this character is still not one of the others
    GetRealmName = function() return "" end
    GulliChoresDB.realm = "Realm"
    eq((n.AltCount(1)), 15)
    GulliChoresDB.chars["Tester-"] = { name = "Tester", items = { [1] = 50 } }
    eq((n.AltCount(1)), 15, "an entry without a realm is this character too")
    GulliChoresDB.chars["Tester-"] = nil
    GetRealmName = function() return "Realm" end
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

-- The fastest route weighs each craft heavily. A bought recipe whose reagents take many crafts
-- of a second profession (smelting) once cost more in that weight than falling short of the
-- target, so the plan dropped the recipe and stopped: a "?" in the middle of the bar.
test("a plan never drops a bought recipe it needs to reach the target, however heavy the time weight", function()
    local ns = core()
    local st = {
        skill = 171, cap = 300, level = 60,
        items = {
            ore = { name = "Ore", ah = 10, age = 0.1, vend = 2 },
            bar = { name = "Bar", vend = 5 },
            out = { name = "Bracers", ah = 100, age = 0.1, vend = 50 },
        },
        recipes = {
            smelt = { name = "Smelt Bar", r = { ore = 1 }, out = "bar", learned = true, other = "Mining" },
            bracer = { name = "Bracers", skill = { 160, 185, 210 }, r = { bar = 10 }, out = "out",
                       src = { t = "trainer", cost = 500 } },
        },
    }
    local P = prefs({ target = 175 })
    P.w = 1e6
    local plan = ns.Plan(st, P)
    eq(plan.reached, 175, "the plan reaches the target")
    P.only = "bracer"
    eq(ns.Plan(st, P).reached, 175, "a run of that one recipe reaches it too")
end)

-- The crafts limit counts only the crafts that raise the skill. Smelting the bars for them is
-- preparation: shown beside them ("4 + 40 prep"), never limited (owner's decision of 2026-11-20).
test("the crafts limit counts only the crafts that raise the skill, not the preparation", function()
    local ns = core()
    local st = {
        skill = 171, cap = 300, level = 60,
        items = {
            ore = { name = "Ore", ah = 10, age = 0.1, vend = 2 },
            bar = { name = "Bar", vend = 5 },
            out = { name = "Bracers", ah = 100, age = 0.1, vend = 50 },
        },
        recipes = {
            smelt = { name = "Smelt Bar", r = { ore = 1 }, out = "bar", learned = true, other = "Mining" },
            bracer = { name = "Bracers", skill = { 160, 185, 210 }, r = { bar = 10 }, out = "out", learned = true },
        },
    }
    local P = prefs({ target = 175, maxCrafts = 0 })
    eq(ns.CraftCap(st, P), 9, "auto: 4 points + 5")
    local routes = ns.Frontier(st, P)
    eq(#routes > 0, true, "a route")
    local p = routes[1]
    eq(p.reached, 175, "it reaches the target")
    eq(p.many, nil, "within the limit")
    eq(ns.LevelCrafts(p), 4, "4 crafts raise the skill")
    eq(p.prepCrafts, 40, "40 bars smelted beside them")
    eq(p.crafts, 44, "the time counts both")
    -- a limit below the skill crafts still gives the way, marked over the limit
    local Q = prefs({ target = 175, maxCrafts = 2 })
    local over = ns.Frontier(st, Q)
    eq(over[1].reached, 175, "the way is still planned")
    eq(over[1].many, true, "marked over the limit")
end)

-- The runs follow the route the tile shows: a stretch the route crafts through is never "?",
-- whatever the limits, the prices or the stock (a run planned anew from what the runs before
-- left could miss a recipe the whole way had, and left a hole in the middle of the bar).
test("the runs of every route cover the whole way it goes", function()
    local ns = core()
    for _, start in ipairs({ 150, 165, 175, 190 }) do
        for _, mc in ipairs({ 0, 30, 100, -1 }) do
            for _, noBags in ipairs({ false, true }) do
                local st = state()
                st.skill = start
                if noBags then for _, it in pairs(st.items) do it.bags, it.bank = 0, 0 end end
                local P = ns.Prefs({ target = math.min(225, start + 40), maxCrafts = mc, useBags = not noBags })
                for _, x in ipairs(ns.Variants(st, P)) do
                    if x.plan and not ns.EARN[x.mode] then
                        local whole = x.plan.full or x.plan
                        local legs = ns.Legs(st, P, x.plan)
                        local at = st.skill
                        for _, l in ipairs(legs) do
                            eq(l.from, at, "runs follow each other")
                            assert(not (l.unknown and l.from < whole.reached),
                                ("a hole at %d-%d in %s (from %d, limit %d), the route goes to %d"):format(l.from, l.to, x.mode, start, mc, whole.reached))
                            at = l.to
                        end
                        assert(at >= whole.reached, "the runs reach where the route goes")
                    end
                end
            end
        end
    end
end)

test("a route tile switches at once from the result; the runs of each route are kept", function()
    local n = game()
    n.db.prefs = n.db.prefs or {}
    n.db.prefs.minGain = 0
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
    for _, x in ipairs(W.frames) do if rawget(x, "_events").TRADE_SKILL_SHOW then f = x end end
    assert(f, "the events registered")
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
    eq(p[2].done, false, "a line with no item to count is never done by itself")
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

test("a pattern on the auction is bought by clicks: search, then the cheapest buyout", function()
    local n = game({ itemAH = true, handOnly = { [6] = true } })
    n.Toggle(); n.Calculate()
    n.db.prefs.autoPin = false   -- the stop below is made by hand; a pin would build the route's own
    -- the route's pattern line carries the pattern's item and its name
    n.Data.src[104] = { "v", 6, "Ally Gal|A" }
    n.Data.spell[104] = { 150, 160, 170 }
    n.db.vendor[6] = 9000
    local st = n.State()
    eq(st.recipes[104].src.t, "ah")
    -- at the auction house first: arriving there builds the first run's stops anew
    W.Fire("AUCTION_HOUSE_SHOW")
    local line = { recipe = 104, name = "Thing", n = 1, src = "ah", price = 500, pattern = 6, pname = "Pattern: Thing" }
    n.view.route = { { kind = "ah", title = "STOP_AH_BUY", index = 1, sig = "p", cost = 500, lines = { line } } }
    local q, hand = n.BuyQueue(n.view.route[1], nil)
    eq(#q, 1); eq(hand, 0); eq(q[1].id, 6); eq(q[1].pattern, true); eq(q[1].name, "Pattern: Thing")
    eq(n.Shopping(n.view.route)[1].name, "Pattern: Thing", "the Auctionator list searches the pattern")
    n.Select(1)
    W.calls = {}
    -- first click: the search, no purchase
    W.Click(n.ui.act1)
    eq(W.calls[1][1], "search"); eq(W.calls[1][2], 6); eq(#W.calls, 1)
    eq(n.buy.phase, "quote")
    -- the answer: the player's own auction and a bid-only one never count, the cheapest buyout wins
    W.itemLots[6] = {
        { auctionID = 11, buyoutAmount = 700, quantity = 1 },
        { auctionID = 12, buyoutAmount = 300, quantity = 1, containsOwnerItem = true },
        { auctionID = 13, quantity = 1 },
        { auctionID = 14, buyoutAmount = 450, quantity = 1 },
    }
    W.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 6 })
    eq(n.buy.phase, "ready"); eq(n.buy.quote.auction, 14); eq(n.buy.quote.total, 450)
    local a = n.StopAction(1)
    assert(a.primary[2] and a.primary[1]:find("Pattern: Thing", 1, true), a.primary[1])
    -- second click: the buyout of that auction
    W.Click(n.ui.act1)
    eq(W.calls[2][1], "bid"); eq(W.calls[2][2], 14); eq(W.calls[2][3], 450)
    W.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 14)
    eq(n.buy.bought, 1); eq(n.buy.spent, 450); eq(n.buy.phase, "done")
    -- nobody sells it: told, and the button asks again
    n.view.route[1].sig = "p2"
    n.Refresh()
    W.itemLots[6] = {}
    W.Click(n.ui.act1)
    W.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 6 })
    eq(n.buy.phase, "idle"); eq(n.StopAction(1).hint, n.L.BUY_ERR_SOLD)
    -- the game refuses the bid
    W.itemLots[6] = { { auctionID = 21, buyoutAmount = 500, quantity = 1 } }
    W.Click(n.ui.act1)
    W.Click(n.ui.act1)
    W.Fire("AUCTION_HOUSE_SHOW_ERROR")
    eq(n.StopAction(1).hint, n.L.BUY_ERR_BUY); eq(n.buy.bought, 0)
end)

test("a pattern a vendor sells is bought with the vendor stop's click", function()
    local n = game({ vendor = { { 6, 6000 } } })
    n.Toggle(); n.Calculate()
    local line = { recipe = 104, name = "Thing", n = 1, src = "vendor", price = 6000, pattern = 6 }
    local node = { kind = "vendor", title = "STOP_VENDOR_BUY", index = 1, sig = "v", cost = 6000, lines = { line } }
    local plan = n.VendorPlan(node, nil, { { index = 1, id = 6, price = 6000, stack = 1 } }, 10000)
    eq(#plan.buys, 1); eq(plan.buys[1].id, 6); eq(plan.missing, 0)
    -- bought: the stop counts it from the bags
    local st = { items = { [6] = { bags = 0 } } }
    local p = n.Progress({ node }, st, function(id) return id == 6 and 1 or 0 end)
    eq(p[1].done, true)
end)

test("a craft stop opens the profession window first, then crafts", function()
    local n = game({ spellbook = { { "Tailoring", SKILL, 225, "picon", 197 } } })
    local calls = {}
    C_TradeSkillUI.OpenTradeSkill = function(line) calls[#calls + 1] = { "open", line }; return true end
    C_TradeSkillUI.OpenRecipe = function(rid) calls[#calls + 1] = { "recipe", rid } end
    C_TradeSkillUI.CraftRecipe = function(rid, k) calls[#calls + 1] = { "craft", rid, k } end
    n.Toggle(); n.Calculate()
    local cs
    for i, node in ipairs(n.view.route) do if node.kind == "craft" then cs = cs or i end end
    assert(cs, kinds(n.view.route))
    n.Select(cs)
    -- the window is closed: the button opens it, it does not craft
    W.Fire("TRADE_SKILL_CLOSE")
    local a = n.StopAction(cs)
    eq(a.primary[1], n.L.OPEN_PROF_BTN:format("Tailoring")); eq(a.hint, n.L.HINT_CRAFT_OPEN)
    assert(a.tools[1] and a.tools[1].skip, "Without this craft stays")
    W.Click(n.ui.act1)
    eq(calls[1][1], "open"); eq(calls[1][2], 197); eq(#calls, 1)
    -- the window opens: the recipe shows in it and the button crafts
    W.Fire("TRADE_SKILL_SHOW")
    W.RunTimers()
    eq(calls[2][1], "recipe")
    a = n.StopAction(cs)
    assert(a.primary[1]:find(n.L.MAKE_N:match("^[^%%]*"), 1, true) or a.primary[1]:find("%d"), a.primary[1])
    eq(a.hint, n.L.HINT_CRAFT)
    W.Click(n.ui.act1)
    eq(calls[3][1], "craft")
    -- closed again: back to Open
    W.Fire("TRADE_SKILL_CLOSE")
    eq(n.StopAction(cs).primary[1], n.L.OPEN_PROF_BTN:format("Tailoring"))
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

test("at a vendor that sells what the run needs, the small window comes beside it and buys", function()
    local n = game({ vendor = { { 3, 250, 5 }, { 5, 100 } } })
    n.Toggle(); n.Calculate()
    local vs = stopOf(n, "STOP_VENDOR_BUY")
    assert(vs, kinds(n.view.route))
    n.Toggle() -- the big window closes: the small one takes its place at the vendor
    W.Fire("MERCHANT_CLOSED")
    local side = n.SideWindow()
    side:Hide()
    W.Fire("MERCHANT_SHOW")
    assert(side:IsShown(), "the small window comes at the vendor")
    assert(n.sui.run:GetText():find(n.Skin.Upper(n.L.SIDE_STOP:format(vs, #n.view.route)), 1, true), n.sui.run:GetText())
    local p = n.sui.panel
    eq(p.act1:GetText(), n.StopAction(vs, true).primary[1])
    local money = W.money
    W.Click(p.act1)
    assert(W.money < money, "its button buys from the vendor")
    W.Fire("MERCHANT_CLOSED")
    assert(not side:IsShown(), "it leaves with the vendor")
    -- a vendor that sells nothing of the stop gets no window
    W.vendor = {}
    n.Recalc(false)
    W.Fire("MERCHANT_SHOW")
    assert(not side:IsShown(), "nothing to buy here")
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
    W.Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 8) -- the bank: not this place
    assert((n.Skin.SideIs("CraftProfit")), "another place leaves its tab")
    W.Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 21) -- walked away: no AUCTION_HOUSE_CLOSED
    assert(not side:IsShown(), "it leaves with the auction house")
    assert(not (n.Skin.SideIs("CraftProfit")), "and its tab with it")
    eq(n.atAH, false)
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

test("a craft stop goes from one craft to the next as the game makes them; any stop can be marked done", function()
    local c = core()
    local node = { kind = "craft", title = "STOP_PREP", prep = true, sig = "prep",
                   lines = { { recipe = "a", n = 3, src = "prep" }, { recipe = "b", n = 2, src = "prep" }, { recipe = "c", n = 1, src = "prep" } } }
    local run = { kind = "craft", title = "STOP_CRAFT", sig = "run", segs = {
        { rid = "x", n = 4, from = 150, to = 154 }, { rid = "y", n = 2.2, from = 154, to = 156 } } }
    local route = { node, run }
    local function prog(made, marks, skill) return c.Progress(route, { items = {} }, function() return 0 end, made, marks, skill) end
    local p = prog({})
    eq(c.NextCraft(node, p[1]), "a"); eq(select(2, c.NextCraft(node, p[1])), 3)
    eq(p[1].done, false)
    -- the first reagent made: the button goes to the second one, not the first again
    p = prog({ a = 3 })
    assert(p[1].lines[1].done)
    local rid, k = c.NextCraft(node, p[1])
    eq(rid, "b"); eq(k, 2)
    p = prog({ a = 3, b = 1 })
    eq(select(2, c.NextCraft(node, p[1])), 1, "what is left of it")
    p = prog({ a = 3, b = 2, c = 1 })
    eq(p[1].done, true); eq(c.NextCraft(node, p[1]), nil)
    -- a run of the skill: crafts counted, or the skill reached
    p = prog({ x = 4 })
    eq(c.NextCraft(run, p[2]), "y"); eq(select(2, c.NextCraft(run, p[2])), 3)
    p = prog({}, nil, 154)
    eq(c.NextCraft(run, p[2]), "y", "the skill is past the first stretch")
    p = prog({}, nil, 156)
    eq(p[2].done, true)
    -- by hand: done, whatever the bags or the casts say
    p = prog({}, { prep = true })
    eq(p[1].done, true); eq(p[1].marked, true); eq(c.NextCraft(node, p[1]), nil)
    eq(p[2].done, false)
end)

test("in the game: each finished craft moves the stop on; Mark done ticks a stop off and back", function()
    local n = game()
    local made
    C_TradeSkillUI.CraftRecipe = function(rid, k) made = { rid, k } end
    n.db.prefs.useBags, n.db.prefs.useBank = false, false
    n.Toggle(); n.Calculate()
    local craft
    for i, s in ipairs(n.view.route) do if s.segs then craft = craft or i end end
    local node = n.view.route[craft]
    n.Select(craft)
    W.Click(n.ui.act1)
    local first, k = node.segs[1].rid, n.Ceil(node.segs[1].n)
    eq(made[1], first)
    -- the game casts the recipe k times: the stop is done (or goes to its next recipe)
    for _ = 1, k do W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", first) end
    eq(n.view.made[first], k)
    local p = n.RunProgress()[craft]
    assert(p.segs[1].done, "the first stretch is made")
    if node.segs[2] then
        n.Select(craft); W.Click(n.ui.act1)
        eq(made[1], node.segs[2].rid, "the button makes the next recipe")
    end
    -- another player's cast or a spell that is no recipe counts nothing
    W.Fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "guid", first)
    W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 999999)
    eq(n.view.made[first], k)
    -- Mark done on the first stop, then back
    n.Select(1)
    local a = n.StopAction(1)
    local tool
    for _, t in ipairs(a.tools) do if t.mark then tool = t end end
    assert(tool, "a Mark done tool")
    tool[2]()
    assert(n.RunProgress()[1].done and n.RunProgress()[1].marked)
    a = n.StopAction(1)
    for _, t in ipairs(a.tools) do if t.mark == false then tool = t end end
    eq(tool[1], n.L.MARK_UNDO)
    tool[2]()
    eq(n.RunProgress()[1].marked, nil)
    -- a new plan starts fresh
    n.Calculate()
    eq(next(n.view.made), nil); eq(next(n.view.marks), nil)
end)

test("the profession window counts as open while the game shows it, whatever order its events came in", function()
    local n = game()
    W.Fire("TRADE_SKILL_CLOSE")
    eq(n.ProfessionShown("Tailoring"), false)
    ProfessionsFrame = W.stub(); ProfessionsFrame:Show()
    eq(n.ProfessionShown("Tailoring"), true)
    ProfessionsFrame = nil
end)

test("the game's profession window: an item's tooltip tells the skill-up chance and the colour levels", function()
    local n = game()
    eq(#n.RecipeTipLines(4), 0, "no line while the game's window is closed")
    ProfessionsFrame = W.stub(); ProfessionsFrame:Show()
    local lines = n.RecipeTipLines(4)
    eq(#lines, 2)
    local rec
    for rid, r in pairs(n.char.profs.Tailoring.recipes) do if r.out == 4 then rec = { rid, r } end end
    local sk = n.RecipeSkill(rec[1], rec[2])
    local y, g, gy = n.Levels(sk)
    local pct = math.floor(n.Chance({ skill = sk }, SKILL) * 100 + 0.5)
    assert(lines[1].left:find(tostring(pct), 1, true), "the chance: " .. lines[1].left)
    for _, v in ipairs({ y, g, gy }) do assert(lines[2].left:find(tostring(v), 1, true), "level " .. v) end
    assert(y <= g and g <= gy)
    eq(#n.RecipeTipLines(1), 0, "Silk Cloth is no craft of this profession")
    -- the colours follow ns.Color: green from the middle between yellow and grey
    local a, b, c = n.Levels({ 0, 100, 120 })
    eq(a, 100); eq(b, 110); eq(c, 120)
    eq(n.Color({ skill = { 0, 100, 120 } }, 109), "ye"); eq(n.Color({ skill = { 0, 100, 120 } }, 110), "gr")
    a, b, c = n.Levels({ 0, 100, 115 })
    eq(b, 108); eq(n.Color({ skill = { 0, 100, 115 } }, 107), "ye"); eq(n.Color({ skill = { 0, 100, 115 } }, 108), "gr")
    ProfessionsFrame = nil
end)

test("the first run's buy stops also buy what the later runs need, behind a switch that plans nothing", function()
    local c = core()
    local st = state()
    for _, it in pairs(st.items) do it.bags, it.bank = 0, 0 end
    st.cap = 225
    local P = prefs({ target = 225 })
    local first = c.NextRun(st, P, c.Plan(st, P))
    local legs = c.Legs(st, P, first)
    assert(#legs >= 2, "runs: " .. #legs)
    local alone = c.Route(st, first)
    local want = {}
    local function add(route)
        for _, e in ipairs(c.Shopping(route)) do want[e.id or e.name] = (want[e.id or e.name] or 0) + e.n end
    end
    local later = 0
    for i, l in ipairs(legs) do
        if l.plan then
            local r = c.Route(l.state, l.plan)
            add(r)
            if i > 1 then later = later + #c.Shopping(r) end
        end
    end
    assert(later > 0, "a later run buys at the auction")
    local merged = c.BuyAhead(c.Route(st, first), legs)
    local got = {}
    for _, e in ipairs(c.Shopping(merged)) do got[e.id or e.name] = (got[e.id or e.name] or 0) + e.n end
    for k, v in pairs(want) do eq(got[k], v, tostring(k)) end
    local ah = has(merged, "STOP_AH_BUY")
    local tagged = false
    for _, l in ipairs(ah.lines) do if l.ahead then tagged = true end end
    assert(tagged, "lines for later runs say so")
    for i, nd in ipairs(merged) do eq(nd.index, i) end
    assert(#merged >= #alone)
    -- one run: nothing to add
    eq(c.BuyAhead(alone, { legs[1] }), alone)
end)

test("the ahead switch changes the buy stops, not the plan", function()
    local n = game()
    n.Toggle(); n.Calculate()
    local plan = n.view.plan
    assert(n.ui.checks.ahead, "a switch on the Settings tab")
    eq(n.Prefs(n.db.prefs).ahead, true)
    n.SetPref("ahead", false)
    eq(n.view.plan, plan)
    n.SetPref("ahead", true)
    eq(n.view.plan, plan)
end)

test("with ahead a purchase shows once, in its own stage, and the first stage buys ahead at the place", function()
    local n = game({
        items = {
            [1] = { name = "Silk Cloth", ah = 160, sell = 38 },
            [2] = { name = "Bolt of Silk Cloth", ah = 900, sell = 150 },
            [3] = { name = "Blue Dye", sell = 12 },
            [4] = { name = "Azure Silk Hood", ah = 1500, sell = 420, quality = 2 },
            [5] = { name = "Fine Thread", sell = 25 },
            [6] = { name = "Silk Headband", ah = 2600, sell = 520, quality = 2 },
            [8] = { name = "Bolt of Mageweave", ah = 4000, sell = 250 },
            [9] = { name = "Black Mageweave Vest", ah = 2400, sell = 900, quality = 2 },
        },
        prof = { name = "Tailoring", skill = SKILL, cap = 225, recipes = {
            { id = 101, name = "Bolt of Silk Cloth", learned = true, diff = 3, grey = 145, out = 2, r = { [1] = 4 } },
            { id = 102, name = "Azure Silk Hood", learned = true, diff = 0, grey = 175, out = 4, r = { [2] = 2, [3] = 2 } },
            { id = 103, name = "Silk Headband", learned = true, diff = 0, grey = 185, out = 6, r = { [2] = 3, [5] = 2 } },
            { id = 105, name = "Black Mageweave Vest", learned = true, diff = 0, grey = 230, out = 9, r = { [2] = 2, [8] = 1 } },
        } },
    })
    n.db.prefs.ahead, n.db.prefs.target = true, 225
    n.Toggle(); n.Calculate()
    local legs = n.view.legs or {}
    local function aheadLines()
        local c = 0
        for _, s in ipairs(n.view.route) do
            for _, l in ipairs(s.lines or {}) do if l.ahead then c = c + 1 end end
        end
        return c
    end
    -- away from the auction house each stage shows only its own purchases, once
    eq(aheadLines(), 0, "the first stage shows only its own purchases")
    local own = false
    for i = 2, #legs do
        if legs[i].plan then
            n.SelectLeg(i)
            for _, s in ipairs(n.view.route) do
                if s.kind == "ah" and s.title == "STOP_AH_BUY" then own = true end
            end
        end
    end
    assert(own, "a later stage shows its own purchases")
    -- at the auction house the first stage buys for the whole way at once
    n.SelectLeg(1)
    n.atAH = true; n.Arrive("ah")
    assert(aheadLines() > 0, "at the auction house it buys ahead")
    for k, s in ipairs(n.view.route) do eq(s.index, k) end
    n.atAH = false; n.Arrive(nil)
    eq(aheadLines(), 0, "and away from it again only its own")
end)

test("a later stage's buy stop buys for that stage now; what came in goes to the stages before it first", function()
    -- a second stage: past 185 only the vest raises the skill
    local n = game({
        items = {
            [1] = { name = "Silk Cloth", ah = 160, sell = 38 },
            [2] = { name = "Bolt of Silk Cloth", ah = 900, sell = 150 },
            [3] = { name = "Blue Dye", sell = 12 },
            [4] = { name = "Azure Silk Hood", ah = 1500, sell = 420, quality = 2 },
            [5] = { name = "Fine Thread", sell = 25 },
            [6] = { name = "Silk Headband", ah = 2600, sell = 520, quality = 2 },
            [8] = { name = "Bolt of Mageweave", ah = 4000, sell = 250 },
            [9] = { name = "Black Mageweave Vest", ah = 2400, sell = 900, quality = 2 },
        },
        prof = { name = "Tailoring", skill = SKILL, cap = 225, recipes = {
            { id = 101, name = "Bolt of Silk Cloth", learned = true, diff = 3, grey = 145, out = 2, r = { [1] = 4 } },
            { id = 102, name = "Azure Silk Hood", learned = true, diff = 0, grey = 175, out = 4, r = { [2] = 2, [3] = 2 } },
            { id = 103, name = "Silk Headband", learned = true, diff = 0, grey = 185, out = 6, r = { [2] = 3, [5] = 2 } },
            { id = 105, name = "Black Mageweave Vest", learned = true, diff = 0, grey = 230, out = 9, r = { [2] = 2, [8] = 1 } },
        } },
    })
    n.db.prefs.ahead, n.db.prefs.target = false, 225
    n.Toggle(); n.Calculate()
    local legs = n.view.legs or {}
    local leg, stop
    for i = 2, #legs do
        if legs[i].plan then
            n.SelectLeg(i)
            for k, s in ipairs(n.view.route) do if s.kind == "ah" and s.title == "STOP_AH_BUY" then leg, stop = i, k end end
            if stop then break end
        end
    end
    assert(stop, "a later stage buys at the auction")
    eq(n.view.leg, leg)
    local a = n.StopAction(stop)
    eq(a.hint, n.L.HINT_STAGE:format(legs[leg].to), "away from the auction it says it can buy now")
    n.atAH = true
    a = n.StopAction(stop)
    assert(a.primary and a.primary[2], "the Buy button works for a later stage")
    n.atAH = false
    -- the earlier stages' buys come first: their units do not tick this stage off
    local line, before
    for _, l in ipairs(n.view.route[stop].lines) do
        local b = 0
        for k = 1, leg - 1 do
            local plan = k == 1 and legs[1].plan or legs[k].plan
            local st = legs[k].state or n.view.state
            for _, nd in ipairs(n.Route(st, plan)) do
                if nd.kind == "ah" then for _, x in ipairs(nd.lines) do if x.id == l.id then b = b + x.n end end end
            end
        end
        if l.id and b > 0 then line, before = l, b end
    end
    assert(line, "an item both stages buy")
    local at
    for k, l in ipairs(n.view.route[stop].lines) do if l == line then at = k end end
    W.items[line.id].bags = before
    eq(n.RunProgress()[stop].lines[at].done, false)
    W.items[line.id].bags = before + line.n
    eq(n.RunProgress()[stop].lines[at].done, true)
end)

-- Two stages: past 185 only the vest raises the skill.
local function twoStages()
    return game({
        items = {
            [1] = { name = "Silk Cloth", ah = 160, sell = 38 },
            [2] = { name = "Bolt of Silk Cloth", ah = 900, sell = 150 },
            [3] = { name = "Blue Dye", sell = 12 },
            [4] = { name = "Azure Silk Hood", ah = 1500, sell = 420, quality = 2 },
            [5] = { name = "Fine Thread", sell = 25 },
            [6] = { name = "Silk Headband", ah = 2600, sell = 520, quality = 2 },
            [8] = { name = "Bolt of Mageweave", ah = 4000, sell = 250 },
            [9] = { name = "Black Mageweave Vest", ah = 2400, sell = 900, quality = 2 },
        },
        prof = { name = "Tailoring", skill = SKILL, cap = 225, recipes = {
            { id = 101, name = "Bolt of Silk Cloth", learned = true, diff = 3, grey = 145, out = 2, r = { [1] = 4 } },
            { id = 102, name = "Azure Silk Hood", learned = true, diff = 0, grey = 175, out = 4, r = { [2] = 2, [3] = 2 } },
            { id = 103, name = "Silk Headband", learned = true, diff = 0, grey = 185, out = 6, r = { [2] = 3, [5] = 2 } },
            { id = 105, name = "Black Mageweave Vest", learned = true, diff = 0, grey = 230, out = 9, r = { [2] = 2, [8] = 1 } },
        } },
    })
end

test("the bug of 2026-11-25: a later stage the skill has reached is walked like the first, crafts and Mark done too", function()
    local n = twoStages()
    n.db.prefs.target = 225
    n.Toggle(); n.Calculate()
    local legs = n.view.legs or {}
    local leg, cs
    for i = 2, #legs do
        if legs[i].plan then
            n.SelectLeg(i)
            for k, s in ipairs(n.view.route) do
                for _, sg in ipairs(s.segs or {}) do if sg.rid == 105 then leg, cs = i, cs or k end end
            end
            if cs then break end
        end
    end
    assert(cs, "a later stage crafts the vest")
    local function markTool(a) for _, t in ipairs(a.tools) do if t.mark ~= nil then return t end end end
    -- not reached yet: only a plan, but Mark done is there
    eq(n.LegNow(n.view, leg), false)
    assert(markTool(n.StopAction(cs)), "Mark done on a craft stop of a later stage")
    -- the skill went on since the plan: this stage is the one to walk now
    n.char.profs.Tailoring.skill = legs[leg].from
    eq(n.LegNow(n.view, leg), true)
    local a = n.StopAction(cs)
    eq(a.pill[1], n.L.CRAFT_WAITS:format(1), "it waits for its own purchases, as the first stage does")
    assert(markTool(a) and markTool(a).mark, "Mark done on the craft of the stage now")
    -- the crafts the game makes count for it
    local sg = n.view.route[cs].segs[1]
    eq(sg.rid, 105)
    for _ = 1, n.Ceil(sg.n) do W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 105) end
    assert(n.RunProgress()[cs].segs[1].done, "the vests made tick the stretch off")
    -- and the skill reached does too, without casts
    n.view.made = {}
    eq(n.RunProgress()[cs].segs[1].done, false)
    n.char.profs.Tailoring.skill = sg.to
    assert(n.RunProgress()[cs].segs[1].done, "the skill is past the stretch")
    -- Mark done ticks it off and back
    n.char.profs.Tailoring.skill = legs[leg].from
    markTool(n.StopAction(cs))[2]()
    assert(n.RunProgress()[cs].done and n.RunProgress()[cs].marked)
    markTool(n.StopAction(cs))[2]()
    eq(n.RunProgress()[cs].marked, nil)
end)

test("a pattern bought ahead and learned since counts as bought, although it left the bags", function()
    local c = core()
    local node = { kind = "ah", title = "STOP_AH_BUY", sig = "ah", lines = {
        { recipe = 300, name = "Runecloth Headband", n = 1, src = "ah", price = 14900, pattern = 14630 } } }
    local st = { items = { [14630] = { bags = 0 } } }
    local none = function() return 0 end
    eq(c.Progress({ node }, st, none)[1].done, false)
    eq(c.Progress({ node }, st, none, nil, nil, nil, function() return false end)[1].done, false)
    local p = c.Progress({ node }, st, none, nil, nil, nil, function(rid) return rid == 300 end)
    eq(p[1].done, true); eq(p[1].lines[1].got, 1)
end)

test("Make N shows a bar of the batch: the crafts made, then it ends; the game stopping it ends it too", function()
    local n = twoStages()
    local crafted
    C_TradeSkillUI.CraftRecipe = function(rid, k) crafted = { rid, k } end
    n.db.prefs.useBags, n.db.prefs.useBank = false, false
    n.Toggle(); n.Calculate()
    local cs
    for i, s in ipairs(n.view.route) do if s.segs then cs = cs or i end end
    n.Select(cs)
    local rid = n.NextCraft(n.view.route[cs], n.RunProgress()[cs])
    eq(n.StopAction(cs).counter, nil, "no bar before Make")
    assert(n.Craft(rid, 3)); eq(crafted[2], 3)
    local a = n.StopAction(cs)
    assert(a.counter and a.counter.bar, "the bar")
    eq(a.counter.text, n.L.CRAFTED_OF:format(0, 3)); eq(a.primary[1], n.L.CRAFT_BUSY); eq(a.primary[2], nil)
    eq(a.hint, n.L.HINT_CRAFTING)
    n.Select(cs)
    assert(n.ui.panel.bar:IsShown(), "the panel shows it")
    W.Fire("UNIT_SPELLCAST_START", "player", "guid", rid)
    W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", rid)
    eq(n.StopAction(cs).counter.text, n.L.CRAFTED_OF:format(1, 3))
    W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", rid)
    W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", rid)
    eq(n.batch, nil, "all made: the bar goes")
    -- another batch the game stops
    n.Craft(rid, 2)
    W.Fire("UNIT_SPELLCAST_START", "player", "guid", 999)
    assert(n.batch, "another spell leaves it alone")
    W.Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "guid", rid)
    eq(n.batch, nil)
    -- nothing came of it for a while
    n.Craft(rid, 2)
    W.now = W.now + 60
    eq(n.Batch(), nil)
end)

test("an item the client had not loaded gets its name once the game sends it", function()
    local n = game()
    W.items[3].pending = true
    n.Toggle(); n.Calculate()
    eq(n.view.state.items[3].name, "#3")
    assert(W.asked and W.asked[3], "the game is asked for it")
    local function shown(t, seen)
        seen = seen or {}
        if seen[t] then return false end
        seen[t] = true
        if rawget(t, "name") == "#3" then return true end
        for _, v in pairs(t) do if type(v) == "table" and shown(v, seen) then return true end end
        return false
    end
    assert(shown(n.view), "the result carries the stand-in")
    -- another item's event changes nothing; the item's own event renames every line
    W.Fire("GET_ITEM_INFO_RECEIVED", 5, true); W.RunTimers()
    eq(n.view.state.items[3].name, "#3")
    W.items[3].pending = nil
    W.Fire("GET_ITEM_INFO_RECEIVED", 3, true); W.RunTimers()
    eq(n.view.state.items[3].name, "Blue Dye")
    assert(not shown(n.view), "no line keeps #3")
    eq(next(n.nameWaiting), nil)
    -- a later calculation has the name at once
    n.Calculate()
    eq(n.view.state.items[3].name, "Blue Dye")
    -- a pattern that was not loaded could not show its reputation line: once it is, the result is outdated
    n = game()
    n.Data.src[104] = { "v", 6, "Ally Gal|A" }
    n.Data.spell[104] = { 150, 160, 170 }
    W.items[6].pending = true
    n.Toggle(); n.Calculate()
    assert(n.repWaiting[6] and not n.view.stale)
    W.items[6].pending = nil
    W.Fire("GET_ITEM_INFO_RECEIVED", 6, true); W.RunTimers()
    eq(n.repWaiting[6], nil)
    eq(n.view.stale, true)
end)

test("a trade supply has its vendor price before the player saw it at a vendor", function()
    local n = game({ vendor = {} })
    local P = n.Prefs({})
    -- Blue Dye (3) has no auction price and was never seen at a vendor: nowhere to buy it
    eq(n.State().items[3].buy, nil)
    n.VENDOR_ITEMS[3], n.VENDOR_ITEMS[5] = true, true
    local st = n.State()
    eq(st.items[3].buy, 48, "four times what a vendor pays"); eq(st.items[3].buyEst, true)
    local v, how = n.BuyOption(st, P, 3)
    eq(v, 48); eq(how, "vendor")
    -- the auction wins only when it is cheaper than the vendor
    W.items[5].ah = 150
    v, how = n.BuyOption(n.State(), P, 5)
    eq(v, 100); eq(how, "vendor")
    W.items[5].ah = 90
    v, how = n.BuyOption(n.State(), P, 5)
    eq(v, 90); eq(how, "ah")
    -- the standing with the best capital takes its share off: Honored 10%, so the vendor beats the auction
    W.items[5].ah = 95
    W.standing = { [72] = 6, [47] = 5 }
    near(n.VendorDiscount(), 0.10)
    st = n.State()
    eq(st.items[5].buy, 90)
    v, how = n.BuyOption(st, P, 5)
    eq(v, 90); eq(how, "vendor")
    W.standing = { [72] = 8 }
    near(n.VendorDiscount(), 0.20)
    W.standing = { [72] = 2 }
    near(n.VendorDiscount(), 0, "no surcharge below Neutral")
    W.standing = nil
    -- the list comes from Data.lua: threads and dyes, never what vendors keep a few of
    local c = core()
    assert(c.Data.vend[8343] and c.Data.vend[2324] and c.Data.vend[2320] and c.Data.vend[3371], "supplies")
    assert(not c.Data.vend[10940] and not c.Data.vend[2319] and not c.Data.vend[765], "limited supply")
    for id in pairs(c.Data.vend) do assert(not c.Data.item[id], "a made item is no supply: " .. id) end
    -- a price seen at a vendor replaces the estimate
    n.db.vendor[3] = 50
    st = n.State()
    eq(st.items[3].buy, 50); eq(st.items[3].buyEst, nil)
end)

test("Legacy's Bartering lowers every vendor price, per character", function()
    local n = game({ vendor = {} })
    n.VENDOR_ITEMS[5] = true
    local function later() W.now = (W.now or 0) + 10 end
    eq(n.BarterRank(), 0)
    eq(n.State().items[5].buy, 100, "no node: four times what a vendor pays")
    -- the spell known: one rank, 5% off
    W.spells[n.BARTER_SPELL] = true; later()
    eq(n.BarterRank(), 1)
    near(n.VendorDiscount(), 0.05)
    eq(n.State().items[5].buy, 95)
    -- with the standing: the two shares one after the other (Honored 10%, then 5%)
    W.standing = { [72] = 6 }; later()
    near(n.VendorDiscount(), 0.145)
    eq(n.State().items[5].buy, 86)
    W.standing = nil
    -- the Legacy tree says how many ranks
    C_Traits = { GetConfigIDByTreeID = function(tree) return tree == 1187 and 7 or nil end,
                 GetTreeNodes = function(tree) return tree == 1187 and { 40, 41 } or {} end,
                 GetNodeInfo = function(cfg, node) return { entryIDs = { node * 10 }, currentRank = node == 41 and 2 or 1 } end,
                 GetEntryInfo = function(cfg, e) return { definitionID = e } end,
                 GetDefinitionInfo = function(d) return { spellID = d == 410 and n.BARTER_SPELL or 99 } end }
    later()
    eq(n.BarterRank(), 2)
    eq(n.State().items[5].buy, 90)
    -- a price seen at a vendor is this character's own; the account keeps it without Bartering
    C_Traits = nil; later()
    W.vendor = { { 5, 95 } }
    W.Fire("MERCHANT_SHOW")
    eq(n.char.vendor[5], 95)
    eq(n.db.vendor[5], 100, "without the 5% of this character")
    local st = n.State()
    eq(st.items[5].buy, 95); eq(st.items[5].buyEst, nil)
    -- another character without the node pays the full price the first saw
    n.char.vendor = {}
    W.spells[n.BARTER_SPELL] = nil; later()
    eq(n.State().items[5].buy, 100)
    W.spells = {}
end)

test("the skill a trainer asks for wins over the data's learning level", function()
    local n = game({ trainer = { { "Pattern Thing", 300, 150 } } })
    n.Data.spell[104] = { 120, 130, 140 }
    n.Data.item[7] = { 105, 120, 130, 140 }
    local was = n.State().recipes[104].skill
    eq(was[1], 105, "the data alone")
    W.Fire("TRAINER_SHOW")
    eq(n.db.trainerReq["Pattern Thing"], 150)
    local sk = n.State().recipes[104].skill
    eq(sk[1], 150, "the trainer's skill")
    for i = 2, #was do eq(sk[i], was[i] + 45, "the other levels move with it") end
    -- a learned recipe keeps what the game shows for it
    eq(n.State().recipes[103].skill[1] ~= nil, true)
end)

test("a recipe only one trainer teaches names that trainer and the city", function()
    local n = game({ prof = { name = "Tailoring", skill = 176, cap = 225, recipes = {
        { id = 101, name = "Bolt of Silk Cloth", learned = true, diff = 3, grey = 145, out = 2, r = { [1] = 4 } },
        { id = 12052, name = "Shadoweave Pants", learned = false, out = 4, r = { [2] = 2 } },
        { id = 104, name = "Pattern Thing", learned = false, out = 7, r = { [1] = 1 } },
    } }, trainer = {} })
    local src = n.State().recipes[12052].src
    eq(src.t, "trainer"); eq(src.cost, 5000)
    eq(src.who[1], "Jalane Ayrole, Stormwind City")
    local saw
    for _, row in ipairs(n.Recipes(n.State(), n.Prefs({}))) do
        if row.recipe == 12052 then saw = row.who and row.who[1] end
    end
    eq(saw, "Jalane Ayrole, Stormwind City", "the Recipes tab has it for the tooltip")
    -- the Horde's own trainer; an ordinary trainer recipe names nobody
    n = game({ faction = "Horde", prof = { name = "Tailoring", skill = 176, cap = 225, recipes = {
        { id = 12052, name = "Shadoweave Pants", learned = false, out = 4, r = { [2] = 2 } },
        { id = 8489, name = "Red Swashbuckler's Shirt", learned = false, out = 6, r = { [2] = 2 } },
    } }, trainer = {} })
    eq(n.State().recipes[12052].src.who[1], "Josephine Lister, Undercity")
    eq(n.State().recipes[8489].src.t, "trainer"); eq(n.State().recipes[8489].src.who, nil)
    -- every such recipe is one the data gives to a trainer
    for rid in pairs(n.TRAINERS) do assert(n.Data.train[rid], "trainer recipe " .. rid) end
end)

test("Shadoweave is learned from skill 200 while the game bug lasts", function()
    local n = game({ faction = "Horde", prof = { name = "Tailoring", skill = 176, cap = 225, recipes = {
        { id = 12052, name = "Shadoweave Pants", learned = false, out = 4, r = { [2] = 2 } },
        { id = 12055, name = "Shadoweave Robe", learned = true, out = 5, r = { [2] = 2 } },
    } }, trainer = {} })
    local r = n.State().recipes[12052]
    eq(r.skill[1], 200, "the learn level is raised")
    eq(r.skill[2], 190); eq(r.skill[3], 220)
    eq(n.Chance(r, 199), 0, "nothing to learn below 200")
    assert(n.Chance(r, 200) > 0, "a skill point from 200")
    eq(n.State().recipes[12055].skill[1], 0, "a recipe the character knows is not touched")
    for rid in pairs(n.TRAINERS) do eq(n.LEARN_MIN[rid], 200) end
end)

test("a vendor or trainer line names who to go to, and Show on map pins the map there", function()
    local n = game({ prof = { name = "Tailoring", skill = 176, cap = 225, recipes = {
        { id = 101, name = "Bolt of Silk Cloth", learned = true, diff = 3, grey = 145, out = 2, r = { [1] = 4 } },
        { id = 12052, name = "Shadoweave Pants", learned = false, out = 4, r = { [2] = 2 } },
        { id = 104, name = "Pattern Thing", learned = false, out = 7, r = { [1] = 1 } },
    } }, trainer = {} })
    -- the data knows where the named NPCs stand
    local spot = n.NpcSpot("Jalane Ayrole")
    eq(spot.zone, "Stormwind City"); eq(spot.label, "Jalane Ayrole, Stormwind City"); assert(spot.x > 0 and spot.y > 0)
    eq(n.NpcSpot("Nobody At All"), nil)
    for rid in pairs(n.TRAINERS) do
        for _, t in pairs(n.TRAINERS[rid]) do assert(n.Data.npc[t[1]], "no place for " .. t[1]) end
    end
    -- the sources carry the names: the trainer's, and the pattern's vendors of this faction
    eq(n.State().recipes[12052].src.npc[1], "Jalane Ayrole")
    n.Data.src[104] = { "v", 6, "Narkk|AH", "Jalane Ayrole|A" }
    n.Data.train[104] = nil
    local src = n.State().recipes[104].src
    eq(src.t, "vendor"); eq(src.npc[1], "Narkk"); eq(src.npc[2], "Jalane Ayrole")
    -- the first with a place, the one in the player's zone when there is one, a bare name else
    eq(n.PickNpc(src.npc).who, "Narkk")
    W.here = 84
    eq(n.PickNpc(src.npc).who, "Jalane Ayrole")
    W.here = nil
    local bare = n.PickNpc({ "Nobody At All" })
    eq(bare.label, "Nobody At All"); eq(bare.zone, nil)
    eq(n.SetPin(bare, true), false, "no place, no pin"); eq(#W.pins, 0)
    -- the stops: a tool with the pin of the first open line; the auction stop has none
    n.Toggle(); n.Calculate()
    n.view.route = {
        { kind = "vendor", title = "STOP_VENDOR_BUY", index = 1, sig = "v",
          lines = { { recipe = 104, name = "Pattern Thing", n = 1, src = "vendor", price = 100, npc = src.npc } } },
        { kind = "trainer", title = "STOP_TRAINER", index = 2, sig = "t",
          lines = { { recipe = 8489, name = "Plain", n = 1, src = "trainer", price = 100 },
                    { recipe = 12052, name = "Shadoweave Pants", n = 1, src = "trainer", price = 100, npc = { "Jalane Ayrole" } } } },
        { kind = "trainer", title = "STOP_TRAINER", index = 3, sig = "t2",
          lines = { { recipe = 8489, name = "Plain", n = 1, src = "trainer", price = 100 } } },
    }
    local a = n.StopAction(1)
    eq(a.tools[1][1], n.L.SHOW_ON_MAP); eq(a.tools[1].pin.who, "Narkk")
    a.tools[1][2]()
    eq(#W.pins, 1); eq(W.pins[1].map, 1434); eq(W.mapOpened, 1434)
    assert(math.abs(W.pins[1].x - n.Data.npc["Narkk"][2] / 100) < 1e-9)
    a = n.StopAction(2)
    eq(a.tools[1].pin.who, "Jalane Ayrole")
    a.tools[1][2]()
    eq(W.pins[2].map, 84); eq(W.mapOpened, 84)
    for _, t in ipairs(n.StopAction(3).tools) do assert(not t.pin, "an ordinary trainer is anyone's: no pin") end
    -- in a fight the pin is set but the map stays shut
    W.combat, W.mapOpened = true, nil
    eq(n.SetPin(spot, true), true); eq(W.mapOpened, nil)
    W.combat = nil
    eq(W.tainted, nil, "the map opens through C_Map.OpenWorldMap, never the addon's OpenWorldMap call")
    -- every vendor the data names for a pattern is a string the place table can be asked for
    local known, all = 0, 0
    for _, d in pairs(n.Data.src) do
        for i = 3, #d do
            all = all + 1
            if n.Data.npc[d[i]:match("^(.-)|")] then known = known + 1 end
        end
    end
    assert(all > 100 and known > all * 0.9, "places for " .. known .. " of " .. all)
end)

test("a recipe of a specialization is offered only with that specialization", function()
    local recipes = {
        { id = 101, name = "Bolt of Silk Cloth", learned = true, diff = 3, grey = 145, out = 2, r = { [1] = 4 } },
        { id = 12899, name = "Gnomish Shrink Ray", learned = false, out = 4, r = { [2] = 2 } },
        { id = 12716, name = "Goblin Mortar", learned = false, out = 6, r = { [2] = 2 } },
        { id = 12897, name = "Gnomish Goggles", learned = false, out = 7, r = { [1] = 1 } },
    }
    local n = game({ prof = { name = "Engineering", skill = 210, cap = 225, recipes = recipes }, trainer = {} })
    local st, P = n.State(), n.Prefs({})
    -- no specialization: neither branch, and the Recipes tab says why
    for _, rid in ipairs({ 12899, 12716, 12897 }) do
        eq(st.recipes[rid].src.t, "spec", "recipe " .. rid); eq(n.CanGet(st.recipes[rid], P), false)
    end
    eq(st.recipes[12899].src.text, "Gnomish Engineer")
    local listed
    for _, row in ipairs(n.Recipes(st, P)) do if row.recipe == 12716 then listed = row.src end end
    eq(listed, "spec")
    -- the Gnomish Engineer: its recipes come back, the goblin ones stay out
    W.spells[20219] = true
    st = n.State()
    eq(st.recipes[12899].src.t, "trainer"); eq(n.CanGet(st.recipes[12899], P), true)
    eq(st.recipes[12716].src.t, "spec")
    -- a client that names the spell otherwise: a learned recipe of the branch shows it too
    W.spells = {}
    recipes[4].learned = true
    n = game({ prof = { name = "Engineering", skill = 210, cap = 225, recipes = recipes }, trainer = {} })
    st = n.State()
    eq(st.recipes[12899].src.t, "trainer", "knows Gnomish Goggles, so is a Gnomish Engineer")
    eq(st.recipes[12716].src.t, "spec")
    eq(st.recipes[12897].learned, true)
    -- every recipe of the table is one WoW Forever has, and in one branch only
    local seen = {}
    for spec, list in pairs(n.SPECS) do
        for _, rid in ipairs(list) do
            assert((n.Data.spell[rid] or n.Data.train[rid]) and not n.Data.gone[rid], "recipe " .. rid .. " of " .. spec)
            assert(not seen[rid], "recipe " .. rid .. " twice"); seen[rid] = true
        end
    end
end)

test("the lists' search keeps the rows whose name has the text, and a row shows its item's own tooltip", function()
    local n = game()
    eq(n.Matches("Bolt of Silk Cloth", " silk "), true)
    eq(n.Matches("Bolt of Silk Cloth", "wool"), false)
    eq(n.Matches("Шёлковая повязка", "ШЁЛК"), true, "Cyrillic in any case")
    eq(n.Matches("Anything", ""), true)
    n.Toggle(); n.Calculate()
    n.Tab(4)
    assert(n.ui.listFrame:IsShown(), "the list with its search shows")
    assert(n.ui.mine:IsShown(), "Only mine on Recipes")
    local all = n.ListRows(4)
    assert(#all >= 1, "rows: " .. #all)
    local name = all[1].keys[1]
    n.ui.find:SetText(name:sub(1, 4):upper())
    local rows = n.ListRows(4)
    assert(#rows >= 1 and #rows <= #all)
    for _, row in ipairs(rows) do assert(n.Matches(row.keys[1], name:sub(1, 4)), row.keys[1]) end
    n.ui.find:SetText("no such recipe at all")
    eq(#n.ListRows(4), 0)
    n.ui.find:SetText("")
    eq(#n.ListRows(4), #all)
    -- Only mine: the recipes the character knows instead of the ones to get, and it is kept
    local learned = {}
    for rid, r in pairs(n.view.state.recipes) do if r.learned and not r.other then learned[#learned + 1] = rid end end
    W.Click(n.ui.mine)
    eq(n.db.onlyMine, true)
    local mine = n.ListRows(4)
    eq(#mine, #learned)
    for _, row in ipairs(mine) do eq(row.cols[1], n.L.WHERE_learned) end
    W.Click(n.ui.mine)
    eq(n.db.onlyMine, nil)
    eq(#n.ListRows(4), #all)
    n.Tab(2)
    eq(n.ui.mine:IsShown(), false, "only on Recipes")
    -- a row with an item: the game's own tooltip of that item, the row's lines under it
    local seen = {}
    GameTooltip = setmetatable({}, { __index = function(_, k)
        return function(_, a) seen[#seen + 1] = { k, a } end
    end })
    local row
    for _, x in ipairs(all) do if type(x.item) == "number" then row = row or x end end
    assert(row, "a recipe row with the item it makes")
    local made = n.ItemTip(row.item)
    eq(made, true)
    eq(seen[1][1], "SetItemByID"); eq(seen[1][2], row.item)
    eq(n.ItemTip(nil), false, "no item, no item tooltip")
    GameTooltip = W.stub()
end)

test("a craft with a cooldown is taken once, only while ready; runs after it wait for it", function()
    local c = core()
    local function moonState()
        local st = state()
        st.items.moon = { name = "Mooncloth", ah = 90000, age = 0.1, vend = 1000 }
        st.recipes.moon = { name = "Mooncloth", skill = { 150, 200, 210 }, r = { silk = 2 }, out = "moon", learned = true }
        st.now = 1000
        return st
    end
    local function uses(plan)
        local n = 0
        for _, sg in ipairs(plan.segs) do if sg.rid == "moon" then n = n + sg.n end end
        return n
    end
    -- without a cooldown it gains so much that every skill point takes it
    local free = c.Plan(moonState(), prefs({ target = 160 }))
    assert(uses(free) >= 5, "without a cooldown: " .. uses(free))
    -- with one: a single craft, and the plan still reaches the target with other crafts
    local st = moonState()
    st.recipes.moon.cd = 4 * c.DAY
    local p = c.Plan(st, prefs({ target = 160 }))
    eq(uses(p), 1); eq(p.reached, 160)
    -- not ready yet: none
    st.recipes.moon.cdReady = st.now + 3600
    eq(uses(c.Plan(st, prefs({ target = 160 }))), 0)
    eq(c.CdLeft(st, st.recipes.moon), 0)
    st.recipes.moon.cdReady = st.now - 1
    eq(c.CdLeft(st, st.recipes.moon), 1, "ready again")
    -- a profit run: one craft of it at most
    st.recipes.moon.cdReady = nil
    local e = c.Earn(st, prefs({ minGain = 0 }))
    local moonRun = e.segs[1] and e.segs[1].rid == "moon"
    if moonRun then eq(e.segs[1].n, 1); eq(e.cd, 4 * c.DAY) end
    for _, sg in ipairs(e.segs) do if sg.rid == "moon" then eq(sg.n, 1) end end
    -- the whole way: only the first run may take it
    local legs = c.Legs(st, prefs({ target = 175 }), nil)
    local total = 0
    for _, leg in ipairs(legs) do if leg.plan then total = total + uses(leg.plan) end end
    assert(total <= 1, "the runs after the first wait for the cooldown: " .. total)
    -- the Crafts now list: at most one, none while it waits
    for _, row in ipairs(c.Crafts(st, prefs())) do if row.recipe == "moon" then assert(row.can <= 1); eq(row.cd, 4 * c.DAY) end end
    -- the value tooltip names the auction price, the cut and the share that sells
    do
        local tip = {}
        local it = { ah = 10000 }
        local fst = { items = { cloth = it } }
        c.ValueTip(tip, fst, { chance = 80 }, { out = "cloth", count = 1 }, { how = "ah", value = 7600 })
        eq(#tip, 1)
        assert(tip[1][1]:find("80") and tip[1][1]:find("5"), tip[1][1])
        local none = {}
        c.ValueTip(none, fst, { chance = 80 }, { out = "cloth" }, { how = "vendor", value = 1 })
        eq(#none, 0, "a vendor price has no auction line")
    end
    -- the lists name the time left in red beside the recipe
    eq(c.CdLeftText({ cd = 4 * c.DAY, cdReady = 1000 + 3 * c.DAY + 4 * 3600 }, 1000), c.L.CD_DH:format(3, 4))
    eq(c.CdLeftText({ cd = 4 * c.DAY, cdReady = 1000 + 5 * 3600 }, 1000), c.L.CD_HOURS:format(5))
    eq(c.CdLeftText({ cd = 4 * c.DAY, cdReady = 900 }, 1000), nil, "ready")
    eq(c.CdLeftText({}, 1000), nil)
    -- Mooncloth and the transmutes are known
    assert(c.COOLDOWNS[18560] and c.COOLDOWNS[17187] and c.COOLDOWNS[19047])
end)

test("the game's cooldown of a recipe is saved: when it is ready, and that it has one", function()
    local rec = {}
    local n = core()
    n.NoteCooldown(rec, 7200)
    eq(rec.cdReady, time() + 7200); eq(rec.cd, 7200)
    n.NoteCooldown(rec, 0)
    eq(rec.cdReady, nil); eq(rec.cd, 7200, "it still has a cooldown")
    -- read at the profession window: the plan of that character waits for it
    local g = game({ prof = { name = "Tailoring", skill = SKILL, cap = 225, recipes = {
        { id = 101, name = "Bolt of Silk Cloth", learned = true, diff = 3, grey = 145, out = 2, r = { [1] = 4 } },
        { id = 103, name = "Silk Headband", learned = true, diff = 0, grey = 185, out = 6, r = { [2] = 3, [5] = 2 }, cooldown = 90000 },
    } } })
    local st = g.State()
    eq(st.recipes[103].cdReady, time() + 90000)
    eq(st.recipes[103].cd, 25 * 3600)
    eq(g.CdLeft(st, st.recipes[103]), 0)
    eq(st.recipes[101].cd, nil)
end)


test("each stretch of a route says why its recipe was chosen, and the next best ones", function()
    local c = core()
    local st = state()
    local plan = c.Plan(st, prefs())
    local saw = {}
    for i, sg in ipairs(plan.segs) do
        local prev = plan.segs[i - 1]
        if not (prev and prev.rid == sg.rid and prev.to == sg.from) then
            assert(sg.why, "a stretch has its reasons: " .. tostring(sg.rid) .. " " .. sg.from)
            local first = sg.why.reasons[1][1]
            assert(first == "ORANGE" or first == "CHANCE", "the colour comes first")
            for _, x in ipairs(sg.why.reasons) do saw[x[1]] = true end
        end
    end
    assert(saw.COST or saw.EARN, "the cost or gain of a point")
    assert(saw.FROM_bags or saw.FROM_bank or saw.FROM_craft, "where the reagents come from")
    -- every reason and alternative is a text in the window, with no format left over
    c.view.state = st
    for _, sg in ipairs(plan.segs) do
        for _, x in ipairs(sg.why and sg.why.reasons or {}) do
            local t = c.WhyText(x)
            assert(t and not t:find("%%[sd]"), x[1])
        end
        for _, a in ipairs(sg.why and sg.why.alts or {}) do assert(c.WhyAltSide(a) ~= "") end
        if sg.why then assert(c.WhyTip(sg)) end
    end

    -- two orange recipes: the cheaper is chosen and says so; the other is the alternative
    local function two(extra)
        local s2 = { skill = 100, cap = 150, level = 30, items = {
            cloth = { name = "Cloth", ah = 100, age = 0.1, vend = 10, bags = 200 },
            a = { name = "A", vend = 1 }, b = { name = "B", vend = 1 },
        }, recipes = {
            ra = { name = "Cheap", skill = { 90, 110, 130 }, r = { cloth = 1 }, out = "a", learned = true },
            rb = { name = "Dear", skill = { 90, 110, 130 }, r = { cloth = 3 }, out = "b", learned = true },
        } }
        for k, v in pairs(extra or {}) do s2.recipes[k] = v end
        return s2
    end
    local s2 = two()
    local p2 = c.Plan(s2, prefs({ target = 101 }))
    local w2 = p2.segs[1].why
    eq(p2.segs[1].rid, "ra")
    local keys = {}
    for _, x in ipairs(w2.reasons) do keys[x[1]] = x end
    assert(keys.ORANGE and keys.FROM_bags and keys.CHEAPEST, "orange, own cloth, cheapest")
    eq(w2.alts[1].rid, "rb")
    assert(w2.alts[1].more > 0, "the alternative costs more a point")
    -- alone: the only recipe that gives a point
    local s3 = two()
    s3.recipes.rb = nil
    c.ForgetMakers(s3.recipes)
    local w3 = c.Plan(s3, prefs({ target = 101 })).segs[1].why
    local only = false
    for _, x in ipairs(w3.reasons) do if x[1] == "ONLY" then only = true end end
    assert(only and #w3.alts == 0, "the only recipe")
    -- speed: an orange craft beats a cheaper green one that needs more crafts
    local s4 = two({ rc = { name = "Slow", skill = { 50, 60, 104 }, r = {}, out = "a", learned = true } })
    s4.recipes.rb = nil
    s4.recipes.ra.r = { cloth = 2 }
    c.ForgetMakers(s4.recipes)
    local P4 = prefs({ target = 101 }); P4.w = 1e6
    local p4 = c.Plan(s4, P4)
    eq(p4.segs[1].rid, "ra")
    local fast
    for _, x in ipairs(p4.segs[1].why.reasons) do if x[1] == "FAST" then fast = x end end
    assert(fast and fast[2] == "rc", "faster than the cheaper green one")
    -- a profit run: what one craft gains, and the series it beat
    local e = c.Earn(state(), prefs())
    local we = e.segs[1] and e.segs[1].why
    assert(we, "a profit run has its reasons")
    local gain, best = false, false
    for _, x in ipairs(we.reasons) do
        if x[1] == "GAIN" then gain = true end
        if x[1] == "BEST_RUN" then best = true end
        assert(x[1] ~= "ORANGE" and x[1] ~= "CHANCE", "a profit run does not level")
        assert(not c.WhyText(x):find("%%[sd]"), x[1])
    end
    assert(gain, "the gain of a craft")
    if #we.alts > 0 then assert(best, "the best series against the next"); assert(c.WhyAltSide(we.alts[1]) ~= "") end
end)

-- ---------- the simulation ----------

-- A character without Tailoring, and a price for everything the Tailoring book names.
local function simGame(extra)
    local spec = { items = {}, spellbook = {} }
    for k, v in pairs(extra or {}) do spec[k] = v end
    Fake(spec)
    local n = Load()
    for _, row in ipairs(n.Data.book[197]) do
        for k = 9, #row, 2 do W.items[row[k]] = W.items[row[k]] or { name = "R" .. row[k], ah = 100, sell = 10, age = 0.1 } end
        if row[2] > 0 then W.items[row[2]] = W.items[row[2]] or { name = "Out" .. row[2], ah = 150, sell = 30, age = 0.1 } end
    end
    W.items[14342] = { name = "Mooncloth", ah = 150000, sell = 4000, age = 0.1 }
    W.items[14256] = { name = "Felcloth", ah = 40000, sell = 1000, age = 0.1 }
    return n
end
-- A table as text, keys sorted: two saves are the same when their texts are.
local function dump(t, seen)
    if type(t) ~= "table" then return tostring(t) end
    seen = seen or {}
    if seen[t] then return "<again>" end
    seen[t] = true
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. dump(t[k], seen) end
    return "{" .. table.concat(out, ",") .. "}"
end
local function simRun(n, opts)
    n.SimOpen()
    n.SimSet(opts)
    assert(n.SimStart(), "the simulated profession is built")
    n.Recalc(false)
    return n.view
end

test("the recipe book: every profession of the simulation, whole rows, starters free", function()
    local n = simGame()
    local B = n.Data.book
    for _, line in ipairs(n.SIM_LINES) do
        assert(B[line] and #B[line] >= 10, "recipes of " .. line)
        assert(n.SIM_PROF_ICON[line] and n.T.en["PROF_" .. line], "icon and name of " .. line)
        for _, row in ipairs(B[line]) do
            assert(#row >= 10 and #row % 2 == 0, "row of " .. row[1])
            assert(row[4] >= 1 and row[5] <= row[6] and row[4] <= row[6], "levels of " .. row[1])
            for k = 10, #row, 2 do assert(row[k] > 0, "reagent count of " .. row[1]) end
            assert(not n.Data.gone[row[1]] or true)
        end
    end
    local bolt, moon
    for _, row in ipairs(B[197]) do
        if row[1] == 2963 then bolt = row end
        if row[1] == 18560 then moon = row end
    end
    -- Bolt of Linen Cloth is known from the start: learned at 1, free
    eq(bolt[4], 1); eq(bolt[7], 1)
    assert(moon and moon[8] == 1 and moon[2] == 14342, "Mooncloth comes from a pattern")
end)

test("the simulation plans a profession the character does not have, from skill 1", function()
    local n = simGame()
    local v = simRun(n, { line = 197, from = 1, to = 75 })
    assert(v.state and v.state.sim, "a simulated state")
    eq(v.state.name, n.SimProfName(197)); eq(v.state.skill, 1)
    for _, r in pairs(v.state.recipes) do assert(not r.learned, "no recipe is learned") end
    local full = v.plan.full or v.plan
    eq(full.reached, 75, "the way reaches the target")
    assert(#v.legs > 0 and v.leg == 0, "the whole way shows first")
    -- no profit routes: the simulation is about the way
    for _, x in ipairs(v.variants) do assert(not n.EARN[x.mode], "no profit route") end
    -- the totals add up to the result
    local t = n.SimTotals(full)
    near(t.materials + t.learn - t.sales, -t.net, "totals")
    assert(t.learn > 0, "recipes and ranks cost something")
    eq(t.level, 5, "the Apprentice rank's level")
    eq(n.SimLevel(230), 35); eq(n.SimLevel(150), 10)
    n.SimStop()
end)

test("nothing of the simulation is saved, and the exit brings the real profession back", function()
    local n = game()
    n.Recalc(false)
    local plan, name = n.view.plan, n.view.state.name
    assert(plan, "a real plan")
    local before = dump(GulliCraftProfitDB) .. dump(GulliCraftProfitCharDB)
    n.SimOpen()
    n.SimSet({ line = 171, from = 20, to = 60, empty = true })
    n.SetPref("chance", 55)
    n.SetSkip(2330, true)
    n.SetGather(765, true)
    assert(n.SimStart())
    n.Recalc(false)
    assert(n.view.state.sim and n.view.plan ~= plan, "the simulation has its own result")
    eq(n.view.prefs.chance, 55, "the simulation uses its own settings")
    n.MarkDone(1); n.StartRun(); n.OnCast(2330)
    eq(dump(GulliCraftProfitDB) .. dump(GulliCraftProfitCharDB), before, "the saved variables are untouched")
    assert(n.SimStop())
    eq(n.sim, nil)
    eq(n.view.plan, plan, "the real result is back")
    eq(n.view.state.name, name)
    eq(n.Prefs(n.SavedPrefs()).chance, n.Prefs(n.db.prefs).chance)
    assert(n.Prefs(n.SavedPrefs()).chance ~= 55, "the changed setting is forgotten")
    assert(not n.SkipSet()[2330] and not n.Gathered()[765], "and the avoided craft and the gathered item")
    eq(dump(GulliCraftProfitDB) .. dump(GulliCraftProfitCharDB), before)
    -- a second simulation starts clean
    n.SimOpen()
    eq(n.sim.from, 1); eq(n.sim.goal, nil); eq(n.sim.empty, false); eq(n.sim.prof, nil)
    n.SimStop()
end)

test("settings changed inside the simulation are named, and the player's own come back", function()
    local n = simGame()
    simRun(n, { line = 197, from = 1, to = 30 })
    eq(#n.SimChanged(), 0)
    n.SetPref("chance", 55); n.SetPref("useBank", false)
    eq(table.concat(n.SimChanged(), " "), "chance useBank")
    eq(n.view.prefs.chance, 55, "the plan was built again with it")
    n.SimRevert()
    eq(#n.SimChanged(), 0)
    eq(n.view.prefs.target, 30, "the target is the simulation's own")
    -- the target stepper moves the simulation's target, not a saved one
    n.SetPref("target", 40)
    eq(n.sim.to, 40); eq(n.db.prefs.target, nil)
    n.SimStop()
end)

test("a goal recipe moves the target, and the payback counts crafts and cooldown days", function()
    local n = simGame()
    n.SimOpen()
    n.SimSet({ line = 197, from = 215, goal = 18560 })
    eq(n.sim.to, 230, "the target stands at the skill the recipe is learned at")
    assert(n.SimStart()); n.Recalc(false)
    local res = n.SimResult()
    assert(res and res.goal, "the goal recipe is the one after the target")
    local p, t = res.pay, res.totals
    eq(p.recipe, 18560); eq(p.reach, true); eq(p.need, 230)
    near(p.cost, 80000, "two Felcloth")
    assert(p.gain > 0 and p.value > p.cost, "it gains")
    eq(p.cd, n.COOLDOWNS[18560])
    assert(t.net < 0, "the way costs money")
    eq(p.crafts, n.Ceil((-t.net + p.extra) / p.gain))
    eq(p.days, n.Ceil(p.crafts * p.cd / n.DAY))
    local left, right = n.SimPayText(res)
    assert(left == n.L.SIM_PAY and right:find(tostring(p.crafts), 1, true) and right:find(tostring(p.days), 1, true))
    -- without a goal: the craft that gains the most at the end of the way
    n.SimSet({ goal = false })
    eq(n.sim.goal, nil); eq(n.sim.prof, nil, "new conditions drop the result")
    assert(n.SimStart()); n.Recalc(false)
    res = n.SimResult()
    eq(res.goal, false)
    assert(res.pay and res.after.recipes[res.pay.recipe].learned, "the best craft is one the way has learned")
    -- a craft that loses money never pays back
    W.items[14342].ah = 100
    n.SimSet({ goal = 18560 }); assert(n.SimStart()); n.Recalc(false)
    res = n.SimResult()
    assert(res.pay.gain <= 0 and res.pay.crafts == nil)
    assert(select(2, n.SimPayText(res)):find(n.L.SIM_PAY_NEVER, 1, true))
    n.SimStop()
end)

test("reputation patterns and specialization recipes are no part of a simulation", function()
    local n = simGame({ tips = { [14526] = { { "Pattern: Mooncloth" }, { "Requires Timbermaw Hold - Friendly" } } } })
    local v = simRun(n, { line = 197, from = 225, to = 235 })
    local r = v.state.recipes[18560]
    eq(r.src.t, "rep", "a new character has no reputation")
    assert(not n.CanGet(r, v.prefs))
    local res = n.SimResult()
    assert(not res.after.recipes[18560].learned, "so the way never learns it")
    n.SimStop()
    -- every specialization recipe of Engineering
    v = simRun(n, { line = 202, from = 200, to = 205 })
    local seen = 0
    for _, list in pairs(n.SPECS) do
        for _, rid in ipairs(list) do
            local x = v.state.recipes[rid]
            if x then seen = seen + 1; eq(x.src.t, "spec"); assert(not n.CanGet(x, v.prefs)) end
        end
    end
    assert(seen >= 10, "the book has specialization recipes: " .. seen)
    n.SimStop()
end)

test("empty bags: the simulation buys everything; else the own stock counts", function()
    local n = simGame()
    W.items[2589] = { name = "Linen Cloth", ah = 100, sell = 10, age = 0.1, bags = 60, bank = 40 }
    W.items[2996] = { name = "Bolt of Linen Cloth", ah = 5000, sell = 10, age = 0.1 } -- dear: weaving the own cloth wins
    local v = simRun(n, { line = 197, from = 1, to = 20 })
    eq(v.state.items[2589].bags, 60); eq(v.state.items[2589].bank, 40)
    local own = (v.plan.full or v.plan).own
    assert(own > 0, "own cloth is used")
    n.SimSet({ empty = true }); assert(n.SimStart()); n.Recalc(false)
    v = n.view
    eq(v.state.items[2589].bags, 0); eq(v.state.items[2589].bank, 0)
    eq((v.plan.full or v.plan).own, 0, "nothing is own")
    n.SimStop()
end)

test("the conditions keep within their bounds", function()
    local n = simGame()
    n.SimOpen()
    n.SimSet({ from = 500 }); eq(n.sim.from, 299); eq(n.sim.to, 300)
    n.SimSet({ from = 100, to = 50 }); assert(n.sim.from < n.sim.to)
    n.SimSet({ to = 150 }); n.SimSet({ from = 150 }); eq(n.sim.to, 151, "the target stays above the start")
    n.SimSet({ line = 171 }); eq(n.sim.name, n.SimProfName(171)); eq(n.sim.goal, nil)
    n.SimSet({ goal = 18560 }); eq(n.sim.goal, nil, "a recipe of another profession is no goal")
    local list, all = n.SimFind(197, "moon", 5)
    assert(all >= 1 and list[1].name:lower():find("moon"), "the goal box finds by name")
    eq(n.SimFind(197, "18560", 5)[1].recipe, 18560, "and by id")
    eq(#n.SimFind(197, "", 5), 0)
    n.SimStop()
end)

test("the window in the simulation: switch, strip, conditions, the whole way, read-only stops", function()
    local n = simGame()
    n.Toggle()
    local u = n.simUI
    assert(u.toggle and not u.strip:IsShown() and n.ui.simTry:IsShown(), "no profession: the simulation is offered")
    W.Click(u.toggle)
    assert(n.sim and u.strip:IsShown() and u.setup:IsShown() and not n.ui.main:IsShown(), "the conditions page")
    eq(u.toggle.switch:GetChecked(), true)
    W.Click(u.tiles[1]); eq(n.sim.line, n.SIM_LINES[1])
    W.Click(u.tiles[6]); eq(n.sim.line, 197)
    W.Click(u.to.chips[1]); eq(n.sim.to, 150)
    W.Click(u.from.chips[2]); eq(n.sim.from, 75)
    W.Click(u.from.stepper.plus); eq(n.sim.from, 80)
    W.Click(u.from.stepper.minus); W.Click(u.from.stepper.minus); eq(n.sim.from, 70)
    n.SimSet({ from = 1, to = 40 })
    W.Click(u.empty.switch); eq(n.sim.empty, true)
    W.Click(u.empty.switch); eq(n.sim.empty, false)
    W.Click(u.go)
    local v = n.view
    assert(v.plan and v.state.sim, "Calculate plans the simulated profession")
    assert(n.ui.main:IsShown() and not u.setup:IsShown())
    assert(u.way:IsShown() and not n.ui.stopsBox:IsShown() and not n.ui.detailCard:IsShown(), "the whole way first")
    eq(n.ui.chips[1]:GetText():match("^(.-)%s*$"), n.L.SIM_WHOLE)
    eq(n.ui.tabs.buttons[2]:GetText(), n.L.SIM_TAB_CRAFTS:format(40))
    eq(n.ui.tabs.buttons[3]:IsEnabled(), false, "My items is no part of a simulation")
    assert(n.ui.prof:GetText():find("1 » 40", 1, true))
    -- a run: its stops, with nothing to press
    n.SelectLeg(1)
    assert(not u.way:IsShown() and n.ui.stopsBox:IsShown() and #v.route > 0)
    for i = 1, #v.route do
        local a = n.StopAction(i)
        eq(a.pill[1], n.L.SIM_PILL)
        assert(not a.primary and not a.second and #a.tools == 0, "a simulated stop has no buttons")
    end
    for _, p in ipairs(n.RunProgress()) do assert(not p.done) end
    eq(#n.TipLines(2589), 0, "no line in the item tooltips")
    assert(not n.SideShow("ah"), "no window beside the auction house")
    -- the lists and the settings
    n.Tab(2); n.Tab(4); n.Tab(5)
    n.SetPref("chance", 55)
    assert(u.back:IsShown(), "the footer gives the player's own settings back")
    W.Click(u.back); eq(#n.SimChanged(), 0); assert(not u.back:IsShown())
    -- the profession pill leads back to the conditions
    n.Tab(1)
    W.Click(n.ui.prof)
    assert(n.sim and not n.sim.prof and u.setup:IsShown())
    -- closing the window keeps the simulation; the exit ends it
    n.Toggle(); assert(n.sim, "a closed window keeps the simulation")
    n.Toggle()
    W.Click(u.strip.exit)
    assert(not n.sim and not u.strip:IsShown() and not u.setup:IsShown() and n.ui.main:IsShown())
    eq(u.toggle.switch:GetChecked(), false)
    eq(n.ui.tabs.buttons[2]:GetText(), n.L.TAB_CRAFTS); eq(n.ui.tabs.buttons[3]:IsEnabled(), true)
end)

test("/gcp sim turns the simulation on with the window, and off again", function()
    local n = simGame()
    SlashCmdList.GULLICRAFTPROFIT("sim")
    assert(n.sim and n.Visible())
    SlashCmdList.GULLICRAFTPROFIT("sim")
    assert(not n.sim)
end)

test("the simulation has no crafts limit, and the settings it does not read are fixed and dim", function()
    local n = simGame()
    local v = simRun(n, { line = 197, from = 1, to = 60 })
    eq(n.CraftCap(v.state, v.prefs), nil)
    eq(n.CraftCap(v.state, n.Prefs({ maxCrafts = 40 })), nil, "a set limit does not count either")
    for _, x in ipairs(v.variants) do assert(not x.many, "no route is refused for its crafts") end
    -- fixed: it levels, learns from the trainer, has no limit, whatever is set
    n.SetPref("trainer", false); n.SetPref("maxCrafts", 40); n.SetPref("level", false)
    local P = n.Prefs(n.SavedPrefs())
    eq(P.trainer, true); eq(P.maxCrafts, -1); eq(P.level, true)
    n.sim.prefs.minGain, n.sim.prefs.ahead = 0, false
    eq(#n.SimChanged(), 0, "a setting the simulation does not read is no change")
    -- the Settings tab dims them and says why
    n.Toggle(); n.Tab(5)
    for k in pairs(n.SIM_IGNORED) do eq(n.ui.rows[k]:GetAlpha(), 0.4, k .. " is dim") end
    eq(n.ui.checks.trainer:IsEnabled(), false); eq(n.ui.steppers.maxCrafts.plus:IsEnabled(), false)
    eq(n.ui.rows.chance:GetAlpha(), 1, "the others stay")
    eq(n.ui.toast:GetText(), n.L.SIM_IGNORED)
    n.SimStop()
    eq(n.ui.rows.maxCrafts:GetAlpha(), 1, "back to normal after the simulation")
    eq(n.Prefs(n.SavedPrefs()).trainer, true); eq(n.db.prefs.maxCrafts, nil, "the player's own settings untouched")
end)

test("the simulation's shopping list buys the whole way at the auction house, for another character", function()
    local n = simGame({ money = 100000000 })
    n.Toggle()
    n.SimOpen()
    n.SimSet({ line = 197, from = 1, to = 60, empty = true })
    n.SimCalculate()
    local v = n.view
    assert(v.plan and v.legs and #v.legs > 0, "the simulation is calculated")
    -- the list adds up what every run buys at the auction
    local want = {}
    for _, l in ipairs(v.legs) do
        if l.plan and not l.unknown then
            for _, m in ipairs(n.Route(l.state, l.plan)) do
                if m.kind == "ah" and m.title == "STOP_AH_BUY" then
                    for _, x in ipairs(m.lines) do if x.id then want[x.id] = (want[x.id] or 0) + x.n end end
                end
            end
        end
    end
    local shop = n.SimShopping(v)
    local ah
    for i, x in ipairs(shop) do if x.kind == "ah" then ah = i end end
    assert(ah, "an auction stop")
    local got = {}
    for _, x in ipairs(shop[ah].lines) do
        assert(not x.ahead, "no run note on the list")
        if x.id then got[x.id] = (got[x.id] or 0) + x.n end
    end
    for id, k in pairs(want) do eq(got[id], k, "units of " .. id) end
    -- its chip stands after the whole way
    eq(n.ui.chips[2]:GetText():match("^(.-)%s*$"), n.L.SIM_SHOP_CHIP)
    eq(v.leg, 0)
    -- at the auction house the list comes up, with a live button
    W.Fire("AUCTION_HOUSE_SHOW")
    eq(v.leg, n.SIM_SHOP)
    assert(n.simUI.strip.text:GetText():find(n.L.SIM_STRIP_SHOP:format(n.sim.name, 1, 60), 1, true))
    local i = (n.Selected())
    local node = v.route[i]
    eq(node.kind, "ah")
    local line = node.lines[1]
    local a = n.StopAction(i)
    assert(a.primary and a.primary[2] and not a.sim, "the list buys for real")
    for _, t in ipairs(a.tools) do assert(t[1] ~= n.L.LOTS_UPDATE, "no lots read in the simulation") end
    W.calls = {}
    W.Click(n.ui.act1)
    eq(W.calls[1][1], "start"); eq(W.calls[1][2], line.id); eq(W.calls[1][3], line.n)
    W.Fire("COMMODITY_PRICE_UPDATED", line.price, line.price * line.n)
    W.Click(n.ui.act1)
    eq(W.calls[2][1], "confirm")
    W.Fire("COMMODITY_PURCHASE_SUCCEEDED")
    eq(n.sim.bought[line.id], line.n, "noted for the list")
    assert(n.RunProgress()[i].lines[1].done, "the line is ticked off")
    -- the run stops stay read-only
    n.SelectLeg(1)
    for k = 1, #v.route do eq(n.StopAction(k).sim, true) end
    -- with the big window closed, the list opens beside the auction house
    n.SelectLeg(0)
    n.Toggle()
    W.Fire("AUCTION_HOUSE_CLOSED")
    W.Fire("AUCTION_HOUSE_SHOW")
    eq(v.leg, n.SIM_SHOP)
    assert(n.SideWindow():IsShown(), "the window beside the auction house")
    eq(#n.TipLines(line.id), 0, "still no tooltip line")
    n.SimStop()
    assert(not n.sim)
end)

-- ---------- pinned routes ----------

-- The tailoring of game() bought at the auction, calculated, with the window closed.
local function pinGame(extra)
    local n = game(extra)
    W.items[1].bags, W.items[1].bank = 0, 0
    n.Recalc(false)
    return n
end
local function segsOf(n)
    local out = {}
    for _, sg in ipairs((n.view.plan.full or n.view.plan).segs) do out[#out + 1] = sg.rid .. ":" .. sg.from .. "-" .. sg.to end
    return table.concat(out, " ")
end
local function lineOf(n, title, id)
    local i = stopOf(n, title)
    for _, l in ipairs(i and n.view.route[i].lines or {}) do if l.id == id then return l, i end end
end

test("a pinned route keeps its recipes and where each item comes from, whatever the prices do", function()
    local n = pinGame()
    local segs = segsOf(n)
    assert(lineOf(n, "STOP_AH_BUY", 1) and not lineOf(n, "STOP_AH_BUY", 2), "the route weaves its bolts from bought cloth")
    local pin = n.PinNow()
    assert(pin and n.view.pin == pin and n.db.pins[1] == pin)
    eq(pin.how[1], "buy"); eq(pin.how[2], "craft"); eq(pin.from, SKILL); eq(pin.to, 185, "as far as the route goes")
    -- bolts turn cheap at the auction and the hood dear: a free calculation takes both
    W.items[2].ah, W.items[4].ah = 100, 90000
    local out = n.FreshOut()
    local function has(route, id)
        for _, node in ipairs(route) do
            if node.title == "STOP_AH_BUY" then for _, l in ipairs(node.lines) do if l.id == id then return true end end end
        end
    end
    assert(has(out.route, 2), "free: it buys the bolts")
    local other = {}
    for _, sg in ipairs((out.plan.full or out.plan).segs) do other[#other + 1] = sg.rid .. ":" .. sg.from .. "-" .. sg.to end
    assert(table.concat(other, " ") ~= segs, "free: another recipe")
    eq(out.pin, nil, "a free calculation is not the pinned route")
    -- the pinned one does not move
    n.Recalc(false)
    eq(n.view.pin, pin)
    eq(segsOf(n), segs)
    assert(lineOf(n, "STOP_AH_BUY", 1) and not lineOf(n, "STOP_AH_BUY", 2), "still cloth, no bolts")
    assert(n.view.plan.prep[101], "the bolts are still woven")
    eq(n.view.prefs.target, 185)
    -- one variant only: the route itself
    eq(#n.view.variants, 1)
    -- the target cannot be changed while it is pinned
    n.SetPref("target", 170)
    eq(n.Prefs(n.SavedPrefs()).target ~= 170, true)
end)

test("the bug that started it: reagents bought along the route, Recalculate, the same route", function()
    local n = pinGame()
    local segs = segsOf(n)
    local cloth = lineOf(n, "STOP_AH_BUY", 1)
    local need, price = cloth.n, cloth.price
    local pin = n.PinNow()
    eq(pin.ofN, 2); eq(pin.haveN, 0); eq(pin.spent, 0)
    eq(cloth.pinOf, nil, "the line of the old route table is not the shown one")
    cloth = lineOf(n, "STOP_AH_BUY", 1)
    eq(cloth.pinOf, need); eq(cloth.pinHave, 0); eq(cloth.pinPrice, price)
    local left = pin.left
    -- the player buys 1000 of the cloth and the price climbs behind them
    W.items[1].bags = 1000
    W.items[1].ah = 400
    -- before any calculation the tiles count what came into the bags
    local st = n.PinStatus()
    eq(st.spent, 1000 * price); eq(st.planLeft, left - 1000 * price); eq(st.haveN, 0)
    n.Recalc(false)
    eq(n.view.pin, pin)
    eq(segsOf(n), segs, "the recipes stay")
    cloth = lineOf(n, "STOP_AH_BUY", 1)
    eq(cloth.n, need - 1000, "only the rest is bought")
    eq(cloth.pinOf, need); eq(cloth.pinHave, 1000)
    eq(cloth.pinPrice, price); eq(cloth.price, 400, "the price now, beside the price of the plan")
    eq(pin.spent, 1000 * price)
    eq(pin.planLeft, left - 1000 * price)
    assert(pin.left > pin.planLeft, "what is left costs more now")
    -- all of it bought: the line leaves the stop and stands among the bought ones
    W.items[1].bags = need + 5
    n.Recalc(false)
    eq(lineOf(n, "STOP_AH_BUY", 1), nil)
    local b = pin.buys.i1
    eq(b.left, 0); eq(b.n, need)
    eq(pin.haveN, 1)
    local v = stopOf(n, "STOP_VENDOR_BUY")
    eq(#n.view.route[v].bought, 0, "the vendor stop has its own")
end)

test("the first purchase or craft pins the route, with Undo; the switch turns that off", function()
    local n = pinGame()
    n.Toggle()
    local ah = stopOf(n, "STOP_AH_BUY")
    W.Fire("AUCTION_HOUSE_SHOW")
    n.Select(ah)
    local line = n.view.route[ah].lines[1]
    W.Click(n.ui.act1)
    W.Fire("COMMODITY_PRICE_UPDATED", line.price, line.price * line.n)
    eq(n.view.pin, nil, "a price asked pins nothing")
    W.Click(n.ui.act1)
    W.Fire("COMMODITY_PURCHASE_SUCCEEDED")
    local pin = n.view.pin
    assert(pin and pin.auto, "the purchase pinned it")
    eq(#n.db.pins, 1)
    -- Undo: free again, and no second try in this session
    n.PinUndo(pin)
    eq(n.view.pin, nil); eq(#n.db.pins, 0)
    eq(n.AutoPin(), nil)
    -- a craft of the route pins too, one that is not of the route does not
    local m = pinGame()
    m.OnCast(102)
    eq(m.view.pin, nil, "the hood is not on the route")
    m.OnCast(101)
    assert(m.view.pin and m.view.pin.auto, "weaving a bolt is")
    -- the vendor's one click
    local k = pinGame()
    local vs = stopOf(k, "STOP_VENDOR_BUY")
    k.BuyVendor(k.view.route[vs], k.RunProgress()[vs])
    assert(k.view.pin)
    -- the switch
    local o = pinGame()
    o.SetPref("autoPin", false)
    assert(o.view.plan and not o.view.stale, "the switch plans nothing")
    o.OnCast(101)
    eq(o.view.pin, nil)
    assert(o.PinNow(), "the button still pins")
    -- a profit route is never pinned
    local e = pinGame()
    e.view.mode = "own"; e.view.plan = { earn = true, segs = {} }
    eq(select(2, e.PinNow()), "none")
end)

test("a pinned route survives a reload, ends at its target, and ten go on at most", function()
    local n = pinGame()
    local segs = segsOf(n)
    local pin = n.PinNow()
    -- a reload: the view is gone, the saved pin is found again by character and profession
    for k in pairs(n.view) do n.view[k] = nil end
    n.view.route, n.view.changed = {}, {}
    eq(n.PinHere(), pin)
    n.Recalc(false)
    eq(n.view.pin, pin); eq(segsOf(n), segs)
    -- one per character and profession: pinning again replaces it
    n.Unpin(pin)
    eq(#n.db.pins, 0); assert(n.view.stale, "unpinned: the result is marked outdated")
    local second = n.PinNow()
    assert(second ~= pin and #n.db.pins == 1)
    n.PinNow()
    eq(#n.db.pins, 1)
    -- ten that still go on: the eleventh is refused, a finished one does not count
    for i = 1, n.PIN_MAX - 1 do n.db.pins[#n.db.pins + 1] = { key = "other|" .. i, prof = "Tailoring", from = 1, to = 50, segs = {}, buys = {} } end
    eq(n.PinCount(), n.PIN_MAX)
    n.Unpin(second)
    n.db.pins[#n.db.pins + 1] = { key = "other|x", prof = "Tailoring", from = 1, to = 50, segs = {}, buys = {} }
    local none, why = n.PinNow()
    eq(none, nil); eq(why, "full")
    n.db.pins[#n.db.pins].done = 5
    assert(n.PinNow(), "a finished route frees its place")
    -- the target reached: finished, and the next calculation is free
    pin = n.view.pin
    W.skill = pin.to
    n.char.profs.Tailoring.skill = pin.to
    eq(n.PinFor({ name = "Tailoring", skill = pin.to }), nil)
    assert(pin.done, "kept in the list as finished")
    local rows = n.PinRows()
    eq(rows[1].head, "active"); eq(rows[#rows].pin.done ~= nil, true)
    local heads = 0
    for _, r in ipairs(rows) do if r.head then heads = heads + 1 end end
    eq(heads, 2)
    -- only the newest finished ones stay
    for i = 1, n.PIN_DONE + 3 do
        local p = { key = "done|" .. i, prof = "Tailoring", from = 1, to = 50, segs = {}, buys = {} }
        table.insert(n.db.pins, 1, p)
        n.PinFinish(p)
    end
    local done = 0
    for _, p in ipairs(n.db.pins) do if p.done then done = done + 1 end end
    eq(done, n.PIN_DONE)
end)

test("is there a better route: both counted from the stock as it is, the verdict, the switch", function()
    local n = pinGame()
    local pin = n.PinNow()
    local segs = segsOf(n)
    -- nothing changed: the new calculation is the same route
    local c = n.PinCompare(n.view, n.FreshOut())
    eq(c.verdict, "same"); eq(c.diff, 0); eq(#c.rows, 0)
    eq(c.mine.cost, c.fresh.cost)
    -- bolts turn very cheap: the new one buys them and saves
    W.items[2].ah = 50
    n.Recalc(false)
    eq(segsOf(n), segs)
    c = n.PinCompare(n.view, n.FreshOut())
    eq(c.verdict, "better")
    assert(c.diff > 0 and c.diff == c.mine.cost - c.fresh.cost)
    local drop, add
    for _, r in ipairs(c.rows) do
        if r.kind == "drop" and r.id == 1 then drop = r end
        if r.kind == "add" and r.id == 2 then add = r end
    end
    assert(drop and add, "it names what the new one buys instead")
    -- cloth already bought for the pinned route is of no use to the new one
    W.items[1].bags = 400
    n.Recalc(false)
    c = n.PinCompare(n.view, n.FreshOut())
    eq(c.mine.full.bags[1] ~= nil, true, "mine uses the cloth")
    -- a new one that is dearer: stay
    W.items[2].ah = 900
    n.Recalc(false)
    c = n.PinCompare(n.view, n.FreshOut())
    eq(c.verdict, "same")
    -- going over: the new route is shown and pinned in place of the old one
    W.items[2].ah = 50
    n.Recalc(false)
    n.view.compare = n.PinCompare(n.view, n.FreshOut())
    assert(n.PinSwitch())
    assert(n.view.pin and n.view.pin ~= pin and pin.gone)
    eq(#n.db.pins, 1)
    eq(n.view.pin.how[2], "buy", "the new route buys its bolts")
    eq(n.view.compare, nil)
end)

test("the window of a pinned route: button, strip, tiles, have N of M, no Outdated tag", function()
    local n = pinGame()
    n.Toggle()
    local w = n.pinUI
    assert(w.button:IsShown() and not w.strip:IsShown() and not w.tiles:IsShown())
    eq(w.button:GetText(), n.L.PIN)
    eq(w.chip:GetText(), n.L.PINS_CHIP:format(0))
    assert(n.ui.varTiles[1]:IsShown(), "the routes to choose from")
    local need = lineOf(n, "STOP_AH_BUY", 1).n
    -- the pin button
    W.Click(w.button)
    local pin = n.view.pin
    assert(pin, "pinned by the button")
    assert(w.strip:IsShown() and w.tiles:IsShown())
    assert(not n.ui.varTiles[1]:IsShown(), "the tiles of the pinned route stand in their place")
    eq(w.button:GetText(), n.L.PIN_OFF)
    eq(w.chip:GetText(), n.L.PINS_CHIP:format(1))
    eq(n.ui.calc:GetText(), n.L.PIN_REFRESH)
    assert(w.strip.text:GetText():find(n.L.PIN_STRIP_TEXT:format(""):sub(1, 5), 1, true))
    assert(w.tiles.spent.sub:GetText():find("0", 1, true))
    -- the bags change: no Outdated tag, the tiles count at once
    W.items[1].bags = 500
    W.Fire("BAG_UPDATE_DELAYED")
    W.RunTimers()
    assert(not n.ui.stale:IsShown(), "a pinned route is never outdated")
    local _, i = lineOf(n, "STOP_AH_BUY", 1)
    n.Select(i)
    local rows = n.DetailRows(n.view.route[i], i, n.StopAction(i))
    local row
    for _, r in ipairs(rows) do if r.id == 1 then row = r end end
    eq(row.pinHave, 500); eq(row.pinOf, need)
    eq(row.note, n.L.PIN_HAVE:format(500, need))
    -- Refresh stock: the same route, the rest to buy
    W.Click(n.ui.calc)
    eq(n.view.pin, pin)
    eq(lineOf(n, "STOP_AH_BUY", 1).n, need - 500)
    rows = n.DetailRows(n.view.route[i], i, n.StopAction(i))
    for _, r in ipairs(rows) do if r.id == 1 then row = r end end
    eq(row.note, n.L.PIN_HAVE:format(500, need))
    -- a price that climbed past the guard is told on the line
    W.items[1].ah = 900
    W.Click(n.ui.calc)
    rows = n.DetailRows(n.view.route[i], i, n.StopAction(i))
    for _, r in ipairs(rows) do if r.id == 1 then row = r end end
    assert(row.dear and row.note:find("500", 1, true), row.note)
    -- all there: the line stays in sight, ticked off
    W.items[1].bags = need + 1
    W.Click(n.ui.calc)
    _, i = nil, stopOf(n, "STOP_AH_BUY")
    if i then
        rows = n.DetailRows(n.view.route[i], i, n.StopAction(i))
        local last = rows[#rows]
        assert(last.bought and last.done and last.id == 1)
    end
    assert(w.tiles.spent.sub:GetText():find("1", 1, true))
    -- a setting changed: the route keeps its recipes and its own settings
    local segs = segsOf(n)
    n.SetPref("chance", 55)
    eq(n.view.pin, pin); eq(segsOf(n), segs)
    assert(n.view.prefs.chance ~= 55, "the settings it was pinned with")
    -- the target stepper is no way out
    n.SetPref("target", 160)
    assert(n.Prefs(n.SavedPrefs()).target ~= 160)
    -- Unpin: free again, and the result is marked outdated
    W.Click(w.strip.off)
    eq(n.view.pin, nil)
    assert(not w.strip:IsShown() and not w.tiles:IsShown() and n.ui.varTiles[1]:IsShown())
    assert(n.ui.stale:IsShown())
    eq(n.ui.calc:GetText(), n.L.RECALC)
    eq(w.chip:GetText(), n.L.PINS_CHIP:format(0))
end)

test("the comparison page and the list of routes in the window", function()
    local n = pinGame()
    n.Toggle()
    local w = n.pinUI
    W.Click(w.button)
    local pin = n.view.pin
    W.items[2].ah = 50
    W.Click(n.ui.calc)
    -- Is there a better route?
    W.Click(w.strip.better)
    eq(n.PinPageShown(), "compare")
    assert(w.cmp:IsShown() and not n.ui.main:IsShown())
    local c = n.view.compare
    assert(c and c.verdict == "better", "the new calculation is ready")
    eq(n.view.pin, pin, "looking changes nothing")
    local text = n.PinVerdict(c)
    assert(w.cmp.verdict:GetText():find(text, 1, true))
    assert(#w.cmp.list.rows >= #c.rows and #c.rows > 0)
    for _, r in ipairs(c.rows) do assert(n.PinChangeText(r) ~= "", r.kind) end
    -- Keep my route
    W.Click(w.cmp.keep)
    eq(n.PinPageShown(), nil); eq(n.view.pin, pin)
    assert(n.ui.main:IsShown() and not w.cmp:IsShown())
    -- Go over to the new one
    W.Click(w.strip.better)
    W.Click(w.cmp.go)
    eq(n.PinPageShown(), nil)
    assert(n.view.pin and n.view.pin ~= pin and n.view.pin.how[2] == "buy")
    assert(w.strip:IsShown())
    -- the list behind the header chip
    W.Click(w.chip)
    eq(n.PinPageShown(), "list")
    assert(w.list:IsShown() and not n.ui.main:IsShown())
    local rows = w.list.rows
    eq(rows[1].head, "active"); eq(rows[2].pin, n.view.pin); eq(rows[2].opens, "here")
    local title, sub, tag = n.PinRowText(rows[2])
    assert(title:find("Tailoring", 1, true) and title:find("185", 1, true)); eq(tag, n.L.PINS_OPEN_TAG)
    assert(sub ~= "")
    -- another character's route: only to look at; delete takes it away
    n.db.pins[#n.db.pins + 1] = { key = "Other|Alchemy", guid = "Other", who = "Twink", class = "MAGE", prof = "Alchemy", from = 1, to = 75,
                                  skill = 20, left = 12345, ofN = 3, segs = {}, buys = {} }
    n.Refresh()
    rows = w.list.rows
    eq(#rows, 3); eq(rows[3].opens, nil)
    assert(select(2, n.PinRowText(rows[3])):find("Twink", 1, true))
    n.Unpin(rows[3].pin); n.Refresh()
    eq(#w.list.rows, 2)
    W.Click(w.list.head.back)
    eq(n.PinPageShown(), nil)
    assert(n.ui.main:IsShown())
end)

test("the simulation saves a route by its button, the only thing it keeps; it opens again and can be walked", function()
    local n = simGame({ money = 100000000 })
    n.Toggle()
    n.SimOpen()
    n.SimSet({ line = 197, from = 1, to = 60, empty = true })
    n.SimCalculate()
    local before = dump(GulliCraftProfitCharDB)
    local w = n.pinUI
    assert(w.button:IsShown() and not w.strip:IsShown(), "the pin button saves here")
    eq(w.button:GetText(), n.L.SIM_SAVE)
    eq(#n.db.pins, 0)
    local segs = segsOf(n)
    W.Click(w.button)
    local pin = n.db.pins[1]
    assert(pin and pin.sim and n.sim.pin == pin and pin.key == "sim|197")
    eq(pin.from, 1); eq(pin.to, 60)
    eq(w.button:GetText(), n.L.SIM_SAVED)
    assert((pin.ofN or 0) > 0 and (pin.left or 0) > 0, "its shopping list is counted")
    -- nothing else of the simulation is saved
    local keep = n.db.pins
    n.db.pins = nil
    local rest = dump(GulliCraftProfitDB)
    n.db.pins = keep
    n.SimStop()
    eq(n.sim, nil)
    n.db.pins = nil
    eq(dump(GulliCraftProfitDB), rest, "the exit leaves the saved variables as they were, but for the route")
    n.db.pins = keep
    eq(dump(GulliCraftProfitCharDB), before)
    eq(#n.db.pins, 1)
    -- the prices move; the saved route opens again as it was
    for id, it in pairs(W.items) do if it.ah then it.ah = it.ah * (id % 3 + 1) end end
    local rows = n.PinRows()
    eq(rows[2].pin, pin); eq(rows[2].opens, "sim")
    n.PinRowOpen(rows[2])
    assert(n.sim and n.sim.pin == pin and n.sim.line == 197 and n.sim.empty)
    assert(n.view.plan and n.view.pin == pin, "calculated along the saved route")
    eq(segsOf(n), segs)
    eq(w.button:GetText(), n.L.SIM_SAVED)
    -- a second press takes the saved route away, a third saves it again
    W.Click(w.button)
    eq(#n.db.pins, 0); eq(n.sim.pin, nil)
    W.Click(w.button)
    pin = n.db.pins[1]
    assert(pin and n.sim.pin == pin)
    -- other conditions are another route: the saved one stays, this one is free
    n.SimSet({ to = 40 })
    eq(n.sim.pin, nil); eq(#n.db.pins, 1)
    n.SimStop()
    -- no profession of that line: nothing to walk
    eq(n.PinAdoptable(pin), nil)
end)

test("a character with the profession walks a saved simulation as its own pinned route", function()
    local n = game()
    W.items[1].bags, W.items[1].bank = 0, 0
    n.Recalc(false)
    local segs = segsOf(n)
    -- a saved simulation of Tailoring, as the planner made it
    local own = n.SimOwn(197)
    assert(own, "the character's Tailoring is the simulation's line 197")
    local real = n.PinNow()
    local saved = { key = "sim|197", prof = "Tailoring", from = 100, to = real.to, skill = 100, mode = real.mode, w = real.w,
                    segs = real.segs, how = real.how, rids = real.rids, buys = {}, prefs = {},
                    sim = { line = 197, from = 100, to = real.to } }
    n.Unpin(real)
    n.db.pins[1] = saved
    assert(n.PinAdoptable(saved))
    local rows = n.PinRows()
    eq(rows[2].adopt, true)
    local mine = n.PinAdopt(saved)
    assert(mine and mine.key ~= saved.key and mine.from == SKILL and mine.to == saved.to)
    eq(#n.db.pins, 2, "the simulation's route stays")
    n.Recalc(false)
    eq(n.view.pin, mine)
    eq(segsOf(n), segs)
    -- below its start or past its end there is nothing to walk
    saved.from = SKILL + 10
    eq(n.PinAdoptable(saved), nil)
end)

test("every skill point counts its chance: Wizardweave Robe from 256 to 295 takes about 65 crafts", function()
    local c = core()
    -- the Forever data: orange 255, yellow 270, green 285, grey 300
    eq(c.Thresholds({ 255, 270, 285, 300 })[1], 255)
    local st = { skill = 256, cap = 300, level = 60, items = {
        bolt = { name = "Bolt of Runecloth", ah = 3000, age = 0.1, vend = 400 },
        dust = { name = "Dream Dust", ah = 1000, age = 0.1, vend = 100 },
        thread = { name = "Rune Thread", buy = 2500, vend = 625 },
        robe = { name = "Wizardweave Robe", vend = 1500 } },
        recipes = { robe = { name = "Wizardweave Robe", skill = { 255, 270, 300 }, r = { bolt = 8, dust = 2, thread = 1 },
                             out = "robe", learned = true } } }
    local plan = c.Plan(st, prefs({ target = 295, sellAH = false }))
    eq(plan.reached, 295)
    -- 14 orange points at one craft each, then 30 / (300 - skill) crafts a point from 270 to 294
    local want = 14
    for s = 270, 294 do want = want + 30 / (300 - s) end
    near(plan.crafts, want)
    assert(plan.crafts > 65 and plan.crafts < 66, plan.crafts)
    -- yellow at 280 is two thirds, green at 290 one third
    near(c.Chance(st.recipes.robe, 280), 20 / 30); near(c.Chance(st.recipes.robe, 290), 10 / 30)
end)

-- ---------- disenchanting ----------

test("disenchanting: the materials by item level, worth them at the auction, only for an enchanter", function()
    local c = core()
    -- green armour of level 57: illusion dust 75% of 1.5, greater eternal essence 20% of 1.5, a shard 5%
    local m = c.DisenchantMats({ class = 4, quality = 2, ilvl = 57 })
    eq(m[1][1], 16204); near(m[1][2], 1.125); eq(m[2][1], 16203); near(m[2][2], 0.3); eq(m[3][1], 14344); near(m[3][2], 0.05)
    -- a weapon the other way round; blue gear one shard; no gear, white gear or a bag nothing
    near(c.DisenchantMats({ class = 2, quality = 2, ilvl = 57 })[2][2], 1.125)
    eq(c.DisenchantMats({ class = 4, quality = 3, ilvl = 45 })[1][1], 11177)
    eq(c.DisenchantMats({ class = 4, quality = 1, ilvl = 57 }), nil)
    eq(c.DisenchantMats({ class = 1, quality = 2, ilvl = 57 }), nil)
    eq(c.DisenchantMats({ class = 7, quality = 2, ilvl = 57 }), nil)
    local st = state()
    st.items.robe = { name = "Wizardweave Robe", vend = 1500, ah = 2000, age = 0.1, class = 4, quality = 2, ilvl = 57 }
    st.items[16204] = { name = "Illusion Dust", ah = 4000, age = 0.1 }
    st.items[16203] = { name = "Greater Eternal Essence", ah = 20000, age = 0.1 }
    local P = prefs({ chance = 100, disenchant = true })
    local de = c.DisenchantValue(st, P, "robe")
    near(de, (1.125 * 4000 + 0.3 * 20000) * 0.95, "the shard has no price and counts nothing")
    -- an enchanter disenchants when it brings more; without Enchanting or the switch it sells
    eq(select(2, c.SellValue(st, P, "robe", 0)), "ah")
    st.enchanter = true
    local v, how = c.SellValue(st, P, "robe", 0)
    eq(how, "de"); near(v, de)
    eq(select(2, c.SellValue(st, prefs({ chance = 100 }), "robe", 0)), "ah", "the switch is off by default")
    st.items[16204].ah, st.items[16203].ah = 100, 100
    eq(select(2, c.SellValue(st, P, "robe", 0)), "ah", "cheap dust: the robe sells")
end)

test("a plan that disenchants lists a Disenchant stop with what the materials bring", function()
    local c = core()
    local st = state()
    st.enchanter = true
    for _, id in ipairs({ "hood", "band", "shirt", "pants" }) do
        local it = st.items[id]
        it.class, it.quality, it.ilvl = 4, 2, 30
    end
    st.items[11083] = { name = "Soul Dust", ah = 5000, age = 0.1 }
    st.items[11082] = { name = "Greater Astral Essence", ah = 9000, age = 0.1 }
    local P = prefs({ disenchant = true })
    local plan = c.Plan(st, P)
    assert(next(plan.sellDE), "something is disenchanted")
    local route = c.Route(st, plan)
    local stop
    for _, n in ipairs(route) do if n.title == "STOP_DE" then stop = n end end
    assert(stop and stop.kind == "sell", kinds(route))
    for _, l in ipairs(stop.lines) do
        eq(l.src, "de"); assert(l.price and l.price > 0)
        eq(plan.sellAH[l.id], nil, "a disenchanted item is not sold too")
        eq(plan.sellVendor[l.id], nil)
    end
    -- without the switch the same plan sells everything
    local off = c.Plan(st, prefs())
    eq(next(off.sellDE), nil)
    assert(off.net < plan.net, "disenchanting pays here")
end)

test("the Disenchant switch: grey without Enchanting, works with it", function()
    local n = game()
    n.Toggle(); n.Calculate()
    n.Tab(5)
    eq(n.ui.checks.disenchant:IsEnabled(), false, "no Enchanting on this character")
    eq(n.view.state.enchanter or false, false)
    n.Tab(1)
    n = game({ spellbook = { { "Tailoring", SKILL, 225, "picon", 197 }, { "Enchanting", 150, 225, "eicon", 333 } } })
    n.Toggle(); n.Calculate()
    eq(n.view.state.enchanter, true)
    n.Tab(5)
    eq(n.ui.checks.disenchant:IsEnabled(), true)
    W.Click(n.ui.checks.disenchant)
    eq(n.db.prefs.disenchant, true)
    eq(n.view.prefs.disenchant, true, "the plan is made again with it")
    n.Tab(1)
end)

test("Use again shows at once, also while the calculation it starts still runs or the shown result is old", function()
    local n = game()
    n.Toggle(); n.Calculate()
    local rid = 103
    n.SetSkip(rid, true)
    n.Tab(5)
    eq(#n.SkipRows(), 1)
    -- a result kept from before (another profession, the simulation) still has the old mark
    W.Click(n.ui.skipRows[1].btn)
    eq(n.db.skip[rid], nil)
    n.view.state.recipes[rid].skip = true
    local rows, note = n.SkipRows()
    eq(#rows, 0, "the saved marks decide what the card shows"); eq(note, n.L.SKIP_EMPTY)
    assert(not n.ui.skipRows[1]:IsShown(), "the row went at the click")
    -- a second click on an old row never puts it back by mistake
    n.ui.skipEdit:SetText(n.view.state.recipes[rid].name)
    rows = n.SkipRows()
    eq(rows[1].skip, false)
    W.Click(n.ui.skipRows[1].btn)
    eq(n.db.skip[rid], true, "the button adds it, as its text said")
    n.ui.skipEdit:SetText("")
    n.Tab(1)
end)

W.finish()
