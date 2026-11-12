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
    n.Toggle()
    eq(n.ui.empty.title:GetText(), n.L.NO_PROF)
    assert(not n.ui.route:IsShown())
end)

test("open window: route stops, a setting click rebuilds and lights what changed", function()
    local n = game()
    n.Toggle()
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
    n.Toggle()
    W.Click(n.ui.modes.speed)
    eq(n.view.prefs.mode, "speed")
    W.Click(n.ui.target.minus)
    eq(n.db.prefs.target, 220)
    eq(n.view.plan.target, 220)
    W.Click(n.ui.chance.minus)
    eq(n.view.prefs.chance, 75)
    W.Click(n.ui.maxSell.plus)
    eq(n.view.prefs.maxSell, 6)
    W.Click(n.ui.reset)
    eq(n.view.prefs.mode, "balance"); eq(n.view.plan.target, 225); eq(n.view.prefs.chance, 80)
end)

test("every switch in the column rebuilds the plan", function()
    local n = game()
    n.Toggle()
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

test("a stop click shows its lines; tabs show the lists", function()
    local n = game()
    n.Toggle()
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

test("without Auctionator only vendor prices count, and the window says so", function()
    local n = game({ auctionator = false })
    n.Toggle()
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

W.finish()
