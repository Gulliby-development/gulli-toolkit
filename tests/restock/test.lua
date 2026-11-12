-- Run from the repository root: lua5.1 tests/restock/test.lua
local W = dofile("tests/restock/wow.lua")
local test, eq = W.test, W.eq

test("every language has every text", function()
    Fake({})
    W.CheckLocales(Load())
end)

test("the plan buys only what is missing, at the vendor that sells it", function()
    Fake({ bags = { [100] = 5 }, vendor = { { 100, 25 }, { 200, 10 }, { 300, 50 } } })
    local ns = Load()
    ns.Set(100, 20)
    ns.Set(300, 2)
    ns.Set(400, 10) -- this vendor does not sell it
    local plan, total = ns.Plan()
    eq(#plan, 2)
    eq(plan[1].id, 100); eq(plan[1].buy, 15); eq(plan[1].cost, 375)
    eq(plan[2].id, 300); eq(plan[2].buy, 2)
    eq(total, 475)
end)

test("items sold in stacks are bought in whole stacks, one purchase per call", function()
    Fake({ bags = { [2515] = 150 }, vendor = { { 2515, 10, 200 } } })
    local ns = Load()
    ns.Set(2515, 1000)
    local plan = ns.Plan()
    eq(plan[1].purchases, 5)
    eq(plan[1].buy, 1000)
    ns.Buy(plan)
    eq(#W.bought, 5)
    eq(W.bought[1][2], nil)
end)

test("single items are bought in chunks of the vendor's stack size", function()
    Fake({ vendor = { { 17020, 100 } } })
    local ns = Load()
    ns.Set(17020, 45)
    ns.Buy((ns.Plan()))
    eq(#W.bought, 3)
    eq(W.bought[1][2], 20); eq(W.bought[3][2], 5)
    eq(W.bags[17020], 45)
end)

test("limited stock, token prices and too little money", function()
    Fake({ money = 300, vendor = { { 1, 100, 1, 2 }, { 2, 0, 1, -1, true }, { 3, 500 } } })
    local ns = Load()
    ns.Set(1, 10); ns.Set(2, 10); ns.Set(3, 1)
    local plan = ns.Plan()
    eq(#plan, 2, "the token item is left out")
    eq(plan[1].buy, 2, "only what the vendor has")
    eq(plan[2].purchases, 0); eq(plan[2].cut, "money", "the money cut is shown")
    W.money = 100
    eq(ns.Buy(plan), 0, "stops at the item the money no longer covers")
    assert(W.printed[#W.printed]:find("not enough money", 1, true))
end)

test("a vendor opens the preview; only OK buys; auto buys at once", function()
    Fake({ vendor = { { 5, 10 } } })
    local ns = Load()
    ns.Set(5, 3)
    W.Fire("MERCHANT_SHOW")
    assert(ns.PlanShown(), "the preview is open")
    eq(#W.bought, 0)
    W.Fire("MERCHANT_CLOSED")
    assert(not ns.PlanShown())
    ns.db.auto = true
    W.Fire("MERCHANT_SHOW")
    eq(#W.bought, 1)
    eq(W.bags[5], 3)
end)

test("class reagents follow the level and keep only the best seed", function()
    Fake({ class = "DRUID", level = 52 })
    local ns = Load()
    eq(ns.AddPreset(), 2)
    eq(ns.char.list[17037], 5, "Hornbeam Seed at 50")
    eq(ns.char.list[17036], nil)
    eq(ns.char.list[17021], 20, "Wild Berries at 50")
    eq(ns.AddPreset(), 0, "nothing twice")
    Fake({ class = "WARRIOR", level = 60 })
    eq(Load().AddPreset(), 0)
end)

test("one low-stock warning until the item is restocked", function()
    Fake({ bags = { [7] = 20 } })
    local ns = Load()
    ns.Set(7, 20)
    eq(ns.CheckLow(), nil)
    W.bags[7] = 4
    assert(ns.CheckLow():find("Item7 (4)", 1, true))
    eq(ns.CheckLow(), nil, "not twice")
    W.bags[7] = 20; ns.CheckLow()
    W.bags[7] = 3
    assert(ns.CheckLow())
end)

test("an item dropped on the window joins the list; zero removes it", function()
    Fake({})
    local ns = Load()
    ns.Toggle()
    W.cursor = 4599
    for _, fr in ipairs(W.frames) do
        local fn = rawget(fr, "_OnReceiveDrag")
        if fn then fn(fr) end
    end
    eq(ns.char.list[4599], 20)
    ns.Set(4599, 0)
    eq(ns.char.list[4599], nil)
    eq(#ns.List(), 0)
end)

test("an older save's list becomes the first set; sets switch and copy", function()
    Fake({ char = { list = { [5] = 10 } } })
    local ns = Load()
    eq(ns.char.set, "Main")
    eq(ns.char.list[5], 10)
    local name = ns.NewSet()
    eq(name, "Set 2"); eq(ns.char.list[5], 10, "a new set copies the current one")
    ns.Set(6, 4)
    eq(ns.NextSet(), "Main")
    eq(ns.char.list[6], nil, "the first set is untouched")
    assert(ns.DeleteSet()); eq(ns.char.set, "Set 2")
    assert(not ns.DeleteSet(), "the last set stays")
end)

test("best water counts every water and buys the best one for the level", function()
    Fake({ level = 30, bags = { [1179] = 6, [1205] = 4 },
           vendor = { { 159, 5 }, { 1179, 20 }, { 1205, 50 }, { 1645, 100 } } })
    local ns = Load()
    eq(ns.AddFromText("water"), "best:water")
    ns.Set("best:water", 30)
    eq(ns.Have("best:water"), 10)
    local plan = ns.Plan()
    eq(#plan, 1)
    eq(plan[1].id, 1205, "level 25 water is not sold here, so the level 15 one")
    eq(plan[1].buy, 20)
    eq(ns.BestItem("water"), 1708)
end)

test("add by link, id and amount", function()
    Fake({ items = { [2512] = { stack = 200, classID = 6 } } })
    local ns = Load()
    eq(ns.AddFromText("|cffffffff|Hitem:4599::::|h[Meat]|h|r", 40), 4599)
    eq(ns.char.list[4599], 40)
    eq(ns.AddFromText("2512"), 2512)
    eq(ns.char.list[2512], 20, "a step of the stack, at most 20")
    eq(ns.AddFromText("rubbish"), nil)
    SlashCmdList.GULLIRESTOCK("add food 15")
    eq(ns.char.list["best:food"], 15)
end)

test("the plan stops at the room in the bags and the gold to keep", function()
    Fake({ money = 50000, items = { [10] = { stack = 5 } },
           containers = { [0] = { size = 2, [1] = { id = 10, n = 3 } } }, vendor = { { 10, 100 }, { 11, 1000 } } })
    local ns = Load()
    ns.Set(10, 20)
    ns.Set(11, 40)
    eq(ns.Room(10), 7, "one free slot of 5 and 2 on the partial stack")
    local plan = ns.Plan()
    eq(plan[1].buy, 7); eq(plan[1].cut, "bags")
    ns.db.reserve = 4 -- 4 gold of the 5 stay
    plan = ns.Plan()
    eq(plan[1].buy, 7)
    eq(plan[2].purchases, 0); eq(plan[2].cut, "bags")
    W.cont[0].size = 40
    plan = ns.Plan()
    eq(plan[2].cut, "money"); eq(plan[2].cost <= 10000 - plan[1].cost, true)
end)

test("an unticked or shortened plan entry buys less", function()
    Fake({ vendor = { { 1, 10 }, { 2, 10 } } })
    local ns = Load()
    ns.Set(1, 5); ns.Set(2, 5)
    local plan = ns.Plan()
    plan[1].on = false
    ns.SetPurchases(plan[2], 2)
    eq(ns.PlanTotal(plan), 20)
    ns.Buy(plan)
    eq(W.bags[1], nil); eq(W.bags[2], 2)
end)

test("Shift at the vendor skips the preview", function()
    Fake({ vendor = { { 5, 10 } } })
    local ns = Load()
    ns.Set(5, 3)
    W.shift = true
    W.Fire("MERCHANT_SHOW")
    assert(not ns.PlanShown())
end)

test("the vendor's food, drink and ammo are offered when not on the list", function()
    Fake({ items = { [1] = { classID = 0 }, [2] = { classID = 2 }, [3] = { classID = 6 } },
           vendor = { { 1, 10 }, { 2, 10 }, { 3, 10 } } })
    local ns = Load()
    W.Fire("MERCHANT_SHOW")
    local offers = ns.VendorOffers()
    eq(#offers, 2); eq(offers[1].id, 1); eq(offers[2].id, 3)
    ns.Set(1, 5)
    eq(#ns.VendorOffers(), 1)
end)

test("quick buy fills the room and the money", function()
    Fake({ money = 1000, items = { [9] = { stack = 10 } }, vendor = { { 9, 30 } } })
    local ns = Load()
    local max = ns.QuickMax(1)
    eq(max, 33, "money: 1000 / 30")
    eq(ns.QuickBuy(1, 12), 12)
    eq(W.bags[9], 12)
end)

test("the bank gives what the bags miss and takes the surplus", function()
    Fake({ items = { [7] = { stack = 20 }, [8] = { stack = 20 } },
           containers = { [0] = { size = 4, [1] = { id = 8, n = 20 }, [2] = { id = 8, n = 15 } },
                          [-1] = { size = 4, [1] = { id = 7, n = 20 }, [2] = { id = 7, n = 6 } } } })
    local ns = Load()
    ns.Set(7, 30); ns.Set(8, 10)
    local moves, sum = ns.BankPlan()
    eq(#sum, 1, "no deposit by default")
    eq(#moves, 2)
    eq(moves[1].n, 20); assert(moves[1].whole)
    eq(moves[2].n, 6); assert(moves[2].whole)
    ns.Set(7, 25)
    moves = ns.BankPlan()
    eq(moves[2].n, 5); assert(not moves[2].whole, "a part is split")
    ns.db.deposit = true
    moves, sum = ns.BankPlan()
    eq(#sum, 2)
    local put = 0
    for _, m in ipairs(moves) do if m.dir == "put" then put = put + m.n end end
    eq(put, 25)
    -- A split goes onto a free slot of the bags.
    eq(ns.Move({ from = { -1, 2 }, n = 5, id = 7, dir = "take" }), true)
    eq(W.moved[1][1], "split"); eq(W.moved[2][1], "drop"); eq(W.moved[2][2], 0); eq(W.moved[2][3], 3)
    eq(ns.Move({ from = { -1, 1 }, n = 20, whole = true, id = 7, dir = "take" }), true)
    eq(W.moved[3][1], "use")
    eq(ns.Move({ from = { -1, 3 }, n = 1, id = 7 }), false, "an empty slot")
end)

test("the forecast warns when the stock lasts less than two hours", function()
    Fake({ bags = { [3] = 100 } })
    local ns = Load()
    ns.Set(3, 100)
    W.Fire("BAG_UPDATE_DELAYED")
    W.now = W.now + 1800
    W.bags[3] = 60
    W.Fire("BAG_UPDATE_DELAYED")
    local h = ns.Lasts(3)
    assert(h and h > 0.7 and h < 0.8, "60 left at 80 an hour: " .. tostring(h))
    assert(ns.CheckLow():find("Item3", 1, true))
    ns.db.forecast = false
    ns.char.warned[3] = nil
    eq(ns.CheckLow(), nil, "60 of 100 is not low without the forecast")
end)

test("buying at a vendor is not counted as use", function()
    Fake({ bags = { [3] = 10 }, vendor = { { 3, 1 } } })
    local ns = Load()
    ns.Set(3, 20)
    W.Fire("BAG_UPDATE_DELAYED")
    W.Fire("MERCHANT_SHOW")
    W.bags[3] = 5
    W.Fire("BAG_UPDATE_DELAYED")
    eq(#ns.char.use[3], 1, "only the start mark"); eq(ns.Lasts(3), nil)
end)

test("DungeonPrep reads what the list misses", function()
    Fake({ bags = { [3] = 2 } })
    local ns = Load()
    ns.Set(3, 5)
    local m = GulliRestock.Missing()
    eq(#m, 1); eq(m[1].have, 2); eq(m[1].want, 5); eq(m[1].name, "Item3")
end)

test("the hub gets a summary, a reset and a tip on each switch", function()
    Fake({})
    local reg
    GulliToolkit = { Register = function(t) reg = t end }
    local ns = Load()
    GulliToolkit = nil
    for _, o in ipairs(reg.options) do assert(o.tip, "a tip for " .. o.label) end
    ns.db.auto = true
    reg.reset()
    eq(ns.db.auto, false)
    eq(reg.summary(), nil)
    ns.Set(3, 5)
    assert(reg.summary():find("1", 1, true))
end)

test("paused from the hub it buys nothing", function()
    Fake({ vendor = { { 5, 10 } } })
    local reg
    GulliToolkit = { Register = function(t) reg = t end }
    local ns = Load()
    GulliToolkit = nil
    ns.Set(5, 3)
    ns.db.auto = true
    reg.pause(true)
    W.Fire("MERCHANT_SHOW")
    eq(#W.bought, 0, "paused")
    W.Fire("MERCHANT_CLOSED")
    reg.pause(false)
    W.Fire("MERCHANT_SHOW")
    eq(#W.bought, 1, "started again")
end)

W.finish()
