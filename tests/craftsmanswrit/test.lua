-- Run from the repository root: lua5.1 tests/craftsmanswrit/test.lua
local W = dofile("tests/craftsmanswrit/wow.lua")
local test, eq = W.test, W.eq

local OGRE = 264011     -- Craftsman's Writ (J, Alchemy): 1 Elixir of Ogre's Strength, quest 94004
local OGRE_ITEM, OGRE_Q = 3391, 94004
local WISDOM = 264012   -- J, 1 Elixir of Wisdom
local WISDOM_ITEM, WISDOM_Q = 3383, 94212
local FROST = 264056    -- E, 1 Frost Protection Potion
local FROST_ITEM = 6050
local SHOT = 264037     -- J, 200 Crafted Solid Shot
local BOOTS = 264052    -- J, Alliance only
local KEY = 264023      -- J, no customer in the data
local SEALED_J, SEALED_E = 262888, 262889
local POUCH_J = 284584

local function writ(id, extra)
    local d = { id = id, rank = "J", rep = 75, item = 1, count = 1, own = 0 }
    for k, v in pairs(extra or {}) do d[k] = v end
    return d
end

-- A price function from a table of { [id] = unit price } (every unit the same) or of ladders.
local function prices(t)
    return function(id, n, skip)
        local p = t[id]
        if type(p) == "table" then
            local sum = 0
            for i = skip + 1, skip + n do
                if not p[i] then return nil end
                sum = sum + p[i]
            end
            return sum / n
        end
        return p
    end
end
local function stock(t) return function(id) return t and t[id] or 0 end end

test("every language has every text", function()
    Fake({})
    W.CheckLocales(Load())
end)

test("the data has 150 writs of three ranks, each with a quest and an item", function()
    Fake({})
    local ns = Load()
    local n, ranks, quests = 0, { J = 0, E = 0, A = 0 }, {}
    for id, d in pairs(ns.WRITS) do
        n = n + 1
        ranks[d[2]] = ranks[d[2]] + 1
        assert(d[1] >= 94000 and d[1] < 95000, "quest of " .. id)
        assert(not quests[d[1]], "quest twice: " .. d[1])
        quests[d[1]] = true
        assert(d[4] > 0 and d[5] > 0, "item of " .. id)
        assert(({ AL = 1, BS = 1, EN = 1, LW = 1, TA = 1 })[d[3]], "profession of " .. id)
        assert(d[6] == nil or d[6] == "A" or d[6] == "H", "side of " .. id)
        if d[8] then assert(d[9] > 0 and d[9] < 100 and d[10] > 0 and d[10] < 100, "spot of " .. id) end
        if d[7] then assert(ns.NPCS[d[7]], "customer name of " .. id) end
    end
    eq(n, 150, "writs")
    eq(ranks.J, 45); eq(ranks.E, 60); eq(ranks.A, 45)
    eq(ns.SEALED[SEALED_J], "J")
    eq(ns.WRITS[SHOT][5], 200, "the Solid Shot writ asks for 200")
end)

test("the plan takes the cheapest writs to the goal", function()
    Fake({})
    local ns = Load()
    local plan = ns.Plan({ need = 150, days = 1,
        writs = { writ(1, { item = 11 }), writ(2, { item = 12 }), writ(3, { item = 13 }) },
        price = prices({ [1] = 100, [2] = 100, [3] = 100, [11] = 500, [12] = 50, [13] = 900 }),
        stock = stock() })
    eq(#plan.lines, 2)
    eq(plan.rep, 150)
    eq(plan.total, 100 + 50 + 100 + 500, "the two cheapest")
    eq(plan.short, 0)
end)

test("a writ goes at most once a day, so fewer days fall short", function()
    Fake({})
    local ns = Load()
    local input = { need = 225, writs = { writ(1, { item = 11 }) }, price = prices({ [1] = 100, [11] = 100 }), stock = stock() }
    input.days = 3
    local plan = ns.Plan(input)
    eq(#plan.lines, 3)
    eq(plan.lines[1].day, 1); eq(plan.lines[3].day, 3)
    input.days = 1
    plan = ns.Plan(input)
    eq(#plan.lines, 1)
    eq(plan.short, 150)
end)

test("a writ handed in today starts tomorrow", function()
    Fake({})
    local ns = Load()
    local plan = ns.Plan({ need = 75, days = 2, writs = { writ(1, { item = 11, done = true }) },
        price = prices({ [1] = 100, [11] = 100 }), stock = stock() })
    eq(#plan.lines, 1)
    eq(plan.lines[1].day, 2)
end)

test("the k-th copy pays the k-th cheapest lot, and the bags come first", function()
    Fake({})
    local ns = Load()
    local plan = ns.Plan({ need = 225, days = 3, writs = { writ(1, { item = 11, own = 1 }) },
        price = prices({ [1] = { 100, 300 }, [11] = { 10, 20, 30 } }), stock = stock({ [11] = 1 }) })
    eq(#plan.lines, 3)
    local l = plan.lines
    eq(l[1].writFrom, "own"); eq(l[1].writ, 0); eq(l[1].itemFrom, "own"); eq(l[1].item, 0)
    eq(l[2].writ, 100); eq(l[2].item, 10)
    eq(l[3].writ, 300); eq(l[3].item, 20)
    local list = ns.ShoppingList(plan)
    eq(#list, 2)
end)

test("the Coin Pouch is taken off every line, and a writ that pays is always taken", function()
    Fake({})
    local ns = Load()
    local plan = ns.Plan({ need = 75, days = 3, writs = { writ(1, { item = 11 }), writ(2, { item = 12 }) },
        price = prices({ [1] = 100, [11] = 100, [2] = 5000, [12] = 5000 }), stock = stock(),
        pouch = function() return 3000 end })
    -- writ 1 costs 200 and pays 3000: every copy is taken, beyond the goal
    eq(#plan.lines, 3)
    eq(plan.buy, 600); eq(plan.pouch, 9000); eq(plan.total, 600 - 9000)
    eq(plan.profit, 3)
    eq(plan.lines[1].cost, -2800)
end)

test("a Sealed Writ is an estimate at the mean item price of its rank", function()
    Fake({})
    local ns = Load()
    local plan = ns.Plan({ need = 75, days = 1,
        writs = { writ(1, { item = 11 }), writ(2, { item = 12 }) },
        sealed = { { id = SEALED_J, rank = "J", own = 0 } },
        price = prices({ [11] = 100, [12] = 300, [SEALED_J] = 50 }), stock = stock() })
    -- the writs themselves have no price: only the Sealed Writ is on sale
    eq(#plan.lines, 1)
    eq(plan.lines[1].kind, "sealed")
    eq(plan.lines[1].item, 200, "the mean of 100 and 300")
    eq(plan.estimate, true)
end)

test("the goal is the next standing, or the one picked", function()
    Fake({})
    local ns = Load()
    local need, goal = ns.Need({ reaction = 5, value = 4000 }, 0)
    eq(goal, 6); eq(need, 5000)
    need, goal = ns.Need({ reaction = 5, value = 4000 }, 8)
    eq(goal, 8); eq(need, 38000)
    need = ns.Need({ reaction = 8, value = 42500 }, 0)
    eq(need, 0)
end)

test("Today sorts the writs held: ready, missing their item, handed in", function()
    Fake({ bags = { [OGRE] = 1, [OGRE_ITEM] = 1, [WISDOM] = 1 }, done = { [94256] = true } })
    local ns = Load()
    local t = ns.Today()
    eq(t.ready, 1); eq(t.item, 1); eq(t.done, 1)
    eq(t.readyRep, 75)
    local rows = ns.TodayRows()
    eq(rows[1].head, ns.L.GROUP_ready)
    eq(rows[2].s.w.id, OGRE)
    eq(rows[4].s.w.id, WISDOM)
end)

test("a writ taken into the log needs no writ item", function()
    Fake({ log = { [OGRE_Q] = true }, bags = { [OGRE_ITEM] = 1 } })
    local ns = Load()
    eq(ns.StateOf(ns.Writ(OGRE)).status, "ready")
end)

test("the other side's writs are left out", function()
    Fake({ faction = "Horde" })
    local ns = Load()
    for _, w in ipairs(ns.Writs()) do assert(w.id ~= BOOTS, "an Alliance writ for the Horde") end
    Fake({ faction = "Alliance" })
    ns = Load()
    local found
    for _, w in ipairs(ns.Writs()) do if w.id == BOOTS then found = true end end
    assert(found, "the Alliance writ")
end)

test("Calculate plans from the game, and the bank counts only with its switch", function()
    Fake({ rep = { 5, 8925 }, bank = { [OGRE] = 1, [OGRE_ITEM] = 1 },
           prices = { [OGRE] = 50000, [OGRE_ITEM] = 50000, [WISDOM] = 10000, [WISDOM_ITEM] = 10000 },
           db = { days = 1, sealed = false } })
    local ns = Load()
    local plan = ns.Calculate()
    eq(plan.need, 75)
    eq(#plan.lines, 1)
    eq(plan.lines[1].id, OGRE, "the bank's writ and item are free")
    eq(plan.lines[1].writFrom, "own")
    ns.SetPref("bank", false)
    eq(ns.stale, true, "a change marks the plan outdated")
    plan = ns.Calculate()
    eq(plan.lines[1].id, WISDOM)
    eq(ns.stale, nil)
end)

test("buying: price, then purchase, in two clicks, and the history pays it", function()
    Fake({ rep = { 5, 8925 }, prices = { [WISDOM] = 100, [WISDOM_ITEM] = 200 }, db = { days = 1, sealed = false, live = false } })
    local ns = Load()
    W.Fire("AUCTION_HOUSE_SHOW")
    ns.Calculate()
    eq(#ns.buy.queue, 2)
    local first = ns.Current().id
    ns.BuyClick()
    eq(W.calls[1], "start " .. first .. " 1")
    W.Fire("COMMODITY_PRICE_UPDATED", 150, 150)
    eq(ns.buy.phase, "ready")
    ns.BuyClick()
    eq(W.calls[2], "buy " .. first .. " 1")
    W.Fire("COMMODITY_PURCHASE_SUCCEEDED")
    eq(ns.buy.i, 2)
    ns.BuyClick()
    W.Fire("COMMODITY_PRICE_UPDATED", 200, 200)
    ns.BuyClick()
    W.Fire("COMMODITY_PURCHASE_SUCCEEDED")
    eq(ns.buy.phase, "done")
    eq(ns.buy.spent, 350)
    local e = ns.TurnedIn(WISDOM_Q)
    eq(e.paid, 350)
    eq(e.rep, 75)
    eq(#ns.db.history, 1)
    local _, sum = ns.History("all")
    eq(sum.count, 1)
end)

test("the Buy button never works away from the auction house or while paused", function()
    Fake({ rep = { 5, 8925 }, prices = { [WISDOM] = 100, [WISDOM_ITEM] = 200 }, db = { days = 1, sealed = false } })
    local ns = Load()
    ns.Calculate()
    ns.BuyClick()
    eq(#W.calls, 0)
    W.Fire("AUCTION_HOUSE_SHOW")
    ns.alone.pause(true)
    ns.BuyClick()
    eq(#W.calls, 0)
end)

test("the window closes its auction work when the player walks away", function()
    Fake({})
    local ns = Load()
    W.Fire("AUCTION_HOUSE_SHOW")
    eq(ns.atAH, true)
    W.Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 21)
    eq(ns.atAH, false)
end)

test("a paused module does not react to the auction house", function()
    Fake({ bags = { [OGRE] = 1 } })
    local ns = Load()
    ns.alone.pause(true)
    W.Fire("AUCTION_HOUSE_SHOW")
    assert(not ns.atAH, "paused")
    eq(ns.TipLines(OGRE), nil, "no tooltip lines while paused")
end)

test("an opened Coin Pouch teaches what it holds", function()
    Fake({ bags = { [POUCH_J] = 2 } })
    local ns = Load()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Fire("LOOT_OPENED")
    W.bags[POUCH_J] = 1
    W.money = W.money + 5000
    W.Fire("PLAYER_MONEY")
    local avg, n = ns.PouchAvg("J")
    eq(n, 1)
    eq(avg, math.floor((10 * 3490 + 5000) / 11 + 0.5))
    eq(ns.Today().pouchGold, 5000)
    ns.SetPref("pouch", false)
    eq(ns.PouchOf("J"), 0, "the switch takes the pouch out of the plan")
end)

test("money from a vendor is no pouch", function()
    Fake({ bags = { [POUCH_J] = 2 } })
    local ns = Load()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Fire("MERCHANT_SHOW")
    W.Fire("LOOT_OPENED")
    W.bags[POUCH_J] = 1
    W.money = W.money + 5000
    W.Fire("PLAYER_MONEY")
    local _, n = ns.PouchAvg("J")
    eq(n, 0)
end)

test("the Diplomat bonus is learned from the reputation a turn-in gives", function()
    Fake({ rep = { 5, 4000 } })
    local ns = Load()
    W.Fire("PLAYER_ENTERING_WORLD")
    ns.TurnedIn(OGRE_Q)
    W.rep = { 5, 4000 + 81 }
    W.Fire("UPDATE_FACTION")
    eq(ns.Mult(), 1.08)
    eq(ns.db.history[1].rep, 81)
end)

test("a customer the data lacks is learned at the turn-in, never from a secret name", function()
    Fake({ map = 1453, x = 0.5, y = 0.4 })
    local ns = Load()
    issecretvalue = function(v) return v == "SECRET" end
    local real = UnitName
    UnitName = function(u) if u == "npc" then return "SECRET" end return real(u) end
    ns.TurnedIn(264023 - 264023 + 94223)
    local s = ns.db.spots[94223]
    eq(s.map, 1453)
    eq(s.name, nil, "the secret name is not kept")
    UnitName = function(u) if u == "npc" then return "Smith" end return real(u) end
    ns.TurnedIn(94223)
    eq(ns.Customer(ns.Writ(KEY)), "Smith")
    issecretvalue = nil
end)

test("an empty realm name saves nothing under Name- and joins the realm on load", function()
    Fake({ bags = { [OGRE] = 1 }, db = { chars = { ["Tester-"] = { side = "A", writs = { [OGRE] = 3 } } } } })
    GetRealmName = function() return "" end
    local ns = Load()
    W.Fire("PLAYER_ENTERING_WORLD")
    eq(ns.db.chars["Tester-"] ~= nil, true, "no realm known: the stray entry stays")
    Fake({ db = { realm = "Realm", chars = { ["Tester-"] = { side = "A", writs = { [OGRE] = 3 } } } } })
    GetRealmName = function() return "" end
    ns = Load()
    eq(ns.db.chars["Tester-"], nil)
    eq(ns.db.chars["Tester-Realm"].writs[OGRE], 3)
end)

test("other characters' writs show in the tooltip", function()
    Fake({ db = { chars = { ["Alt-Realm"] = { side = "A", class = "MAGE", writs = { [OGRE] = 2 }, items = {} } } } })
    local ns = Load()
    local found
    for _, l in ipairs(ns.TipLines(OGRE)) do if l.group == "stock" and l.left == "Alt" then found = l.right end end
    eq(found, "2")
end)

test("tooltip lines for a writ, a Sealed Writ, a pouch and a needed item", function()
    Fake({ names = { [OGRE] = "Craftsman's Writ: Elixir of Ogre's Strength", [OGRE_ITEM] = "Elixir of Ogre's Strength" },
           bags = { [OGRE_ITEM] = 1 }, prices = { [OGRE] = 1000, [OGRE_ITEM] = 1000 } })
    local ns = Load()
    local lines = ns.TipLines(OGRE)
    eq(lines[1].group, "quest")
    eq(lines[2].rcolor, ns.Skin.GOOD, "the item is in the bags")
    assert(lines[4] and lines[4].group == "quest", "the customer")
    local price
    for _, l in ipairs(lines) do if l.group == "price" then price = l end end
    assert(price, "the cost per 100 reputation")
    eq(#ns.TipLines(SEALED_J), 2)
    eq(ns.TipLines(POUCH_J)[1].group, "price")
    local item = ns.TipLines(OGRE_ITEM)
    eq(item[1].left, ns.Skin.Cap(ns.L.TIP_FOR_WRIT:format("Elixir of Ogre's Strength")))
    eq(ns.TipLines(12345), nil, "an item no writ asks for")
    ns.SetPref("tooltip", false)
    eq(ns.TipLines(OGRE), nil)
end)

test("the guide pins the nearest customer and takes over another module's guide", function()
    Fake({ bags = { [OGRE] = 1, [OGRE_ITEM] = 1, [WISDOM] = 1, [WISDOM_ITEM] = 1 }, map = 1416, x = 0.38, y = 0.61 })
    local ns = Load()
    local stopped
    GulliHUD = GulliHUD or {}
    GulliHUD.guide = { owner = "WorthIt", stop = function() stopped = true end }
    assert(ns.StartGuide(), "two writs are ready")
    eq(stopped, true)
    eq(GulliHUD.guide.owner, "CraftsmansWrit")
    eq(#ns.stops, 2)
    eq(ns.stop.spot.map, 1416, "the customer in the player's zone first")
    eq(W.waypoints[1].map, 1416)
    eq(#W.opened, 0, "a pin the guide sets opens no map")
    eq(#ns.TrackerItems(), 2)
    ns.StopGuide()
    eq(GulliHUD.guide, nil)
end)

test("no guide without a writ ready", function()
    Fake({ bags = { [OGRE] = 1 } })
    local ns = Load()
    eq(ns.StartGuide(), false)
end)

test("the window builds every tab, with a plan and without", function()
    Fake({ bags = { [OGRE] = 1, [OGRE_ITEM] = 1, [SEALED_E] = 1 }, rep = { 5, 8800 },
           prices = { [WISDOM] = 100, [WISDOM_ITEM] = 100, [FROST] = 300, [FROST_ITEM] = 50 } })
    local ns = Load()
    local w = ns.Window()
    w:Show()
    for i = 1, 5 do ns.ShowTab(i) end
    ns.Calculate()
    ns.ShowTab(2)
    ns.Refresh()
    local rows = ns.PlanRows(ns.plan)
    assert(#rows > 0)
    assert(ns.LineParts(ns.plan.lines[1]):find("pouch", 1, true), "every line shows its pouch")
    eq(ns.CostText(-500):sub(1, 1) ~= "", true)
    W.Fire("AUCTION_HOUSE_SHOW")
    ns.MoveTracker(true)
    assert(ns.TrackerFrame(), "the tracker for the Unlock mode")
    ns.MoveTracker(false)
end)

test("the module registers for the hub with its window and its tracker", function()
    Fake({})
    local ns = Load()
    local a = ns.alone
    eq(a.key, "CraftsmansWrit")
    eq(a.slash, "/gcw")
    assert(a.window() == ns.Window())
    eq(a.frames[1].key, "tracker")
    assert(a.frames[1].frame())
    assert(#a.options >= 3)
    for _, o in ipairs(a.options) do assert(o.label and o.icon, "option") end
end)

W.finish()
