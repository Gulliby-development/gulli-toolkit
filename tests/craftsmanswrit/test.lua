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

test("a writ handed in today says when it can be handed in again, not just Handed in", function()
    Fake({ bags = { [WISDOM] = 1 }, done = { [WISDOM_Q] = true }, reset = 4 * 3600 + 33 * 60 })
    local ns = Load()
    ns.Toggle()
    eq(ns.DoneText(), "Again in 4 h 33 min")
    local found
    for _, l in ipairs(ns.TipLines and ns.TipLines(WISDOM) or {}) do
        if l.right == "Again in 4 h 33 min" then found = true; eq(l.rcolor, ns.Skin.BAD, "in red") end
    end
    assert(found, "the tooltip names the time to the reset")
    local before = #W.timers
    ns.TickClock(); ns.TickClock()
    eq(#W.timers, before + 1, "one clock counts the time down while the window shows")
end)

test("Today shows what handing in each held writ costs: the item less its pouch", function()
    Fake({ bags = { [OGRE] = 1 }, bank = { [WISDOM] = 1, [WISDOM_ITEM] = 1 }, prices = { [OGRE_ITEM] = 5000 } })
    local ns = Load()
    local pouch = ns.PouchOf("J")
    local rows = ns.TodayRows()
    local byId, heads = {}, {}
    for _, r in ipairs(rows) do
        if r.s then byId[r.s.w.id] = r elseif r.head then heads[#heads + 1] = r end
    end
    eq(byId[OGRE].s.status, "item")
    eq(byId[OGRE].close.item, 5000)
    eq(byId[OGRE].close.total, 5000 - pouch)
    eq(byId[OGRE].close.estimate, true)
    -- the writ and its item wait in the bank: handing it in only gives the pouch
    eq(byId[WISDOM].s.status, "bank")
    eq(byId[WISDOM].close.total, -pouch)
    eq(heads[1].cost, 5000 - pouch)
    eq(heads[2].cost, -pouch)
    -- the tooltip names it too
    local found
    for _, l in ipairs(ns.TipLines(OGRE)) do if l.left == ns.L.TIP_CLOSE then found = l end end
    eq(found ~= nil, true)
end)

test("a held writ without a price keeps its group's head without a sum", function()
    Fake({ bags = { [OGRE] = 1 } })
    local ns = Load()
    local rows = ns.TodayRows()
    eq(rows[1].cost, nil)
    eq(rows[2].close.total, nil)
end)

test("the writ and item names are asked for at login, only the missing ones", function()
    Fake({ names = { [OGRE] = "Craftsman's Writ: Elixir of Ogre's Strength" } })
    local ns = Load()
    W.requested = {}
    ns.prefetching = nil
    ns.Prefetch()
    -- the requests go out a few at a time
    for _ = 1, 30 do W.RunTimers() end
    eq(W.requested[OGRE], nil)
    eq(W.requested[OGRE_ITEM], true)
    eq(W.requested[SEALED_J], true)
    eq(W.requested[POUCH_J], true)
end)

test("the Writs tab sorts the best gain first and the writs without a price last", function()
    Fake({ prices = { [OGRE] = 100, [OGRE_ITEM] = 100, [WISDOM] = 90000, [WISDOM_ITEM] = 90000,
                      [FROST] = 100, [FROST_ITEM] = 50000 } })
    local ns = Load()
    local rows = ns.WritRows(nil, "gain")
    eq(rows[1].id, OGRE)
    local at = {}
    for i, w in ipairs(rows) do at[w.id] = i end
    eq(at[FROST] < at[WISDOM], true)
    eq(at[WISDOM] < at[SHOT], true) -- no price for the shot: at the end
    local plain = ns.WritRows(nil, "prof")
    eq(plain[1].id, ns.Writs()[1].id)
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

-- Three days of Elixir of Wisdom: the writ and the elixir are sold one auction at a time.
local function threeDays(extra)
    local spec = { rep = { 5, 8775 }, prices = { [WISDOM] = 100, [WISDOM_ITEM] = 200 },
                   db = { days = 3, sealed = false, live = false },
                   auctions = { [WISDOM] = { { 11, 120 }, { 12, 130 }, { 13, 140 } },
                                [WISDOM_ITEM] = { { 21, 200, 2 }, { 22, 210 }, { 23, 220 } } } }
    for k, v in pairs(extra or {}) do spec[k] = v end
    Fake(spec)
    local ns = Load()
    W.Fire("AUCTION_HOUSE_SHOW")
    ns.Calculate()
    return ns
end

test("the plan is bought in steps: a writ type a step, writs first, a node a day", function()
    local ns = threeDays({ bags = { [WISDOM_ITEM] = 1 } })
    eq(#ns.buy.steps, 1)
    local s = ns.buy.steps[1]
    eq(s.copies, 3)
    eq(s.writ.n, 3)
    eq(s.item.n, 2, "the elixir in the bags is one less to buy")
    local n = ns.StepNodes(s)
    eq(n.writ.done, 0); eq(n.item.done, 1, "the one in the bags is a filled node")
    eq(ns.Current().part, "writ")
    eq(ns.ShoppingList(ns.plan)[2].n, 2)
end)

test("items that are no commodity: one click finds the lot, then one click a unit", function()
    local ns = threeDays({ status = { [WISDOM] = 1, [WISDOM_ITEM] = 1 } })
    ns.BuyClick()
    eq(W.itemSearches[1], WISDOM, "the first click searches the writ's auctions")
    W.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = WISDOM })
    eq(ns.buy.phase, "ready")
    for i = 1, 3 do
        ns.BuyClick()
        eq(W.bids[i], (10 + i) .. " " .. (110 + 10 * i))
        W.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 10 + i)
        if i < 3 then eq(ns.buy.phase, "ready", "the next lot is ready at once, without the one just bought") end
    end
    eq(ns.StepNodes(ns.buy.steps[1]).writ.done, 3)
    eq(ns.Current().part, "item")
    eq(#W.itemSearches, 1, "no search while the results still have lots")
    ns.BuyClick()
    W.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = WISDOM_ITEM })
    ns.BuyClick()
    W.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 21)
    ns.BuyClick()
    eq(W.bids[5], "22 210")
    W.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 22)
    ns.BuyClick()
    W.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 23)
    eq(ns.buy.phase, "done")
    eq(ns.buy.bought, 6)
    eq(ns.buy.spent, 120 + 130 + 140 + 200 + 210 + 220)
end)

test("a lot sold to someone else: the next click takes the next one", function()
    local ns = threeDays({ status = { [WISDOM] = 1, [WISDOM_ITEM] = 1 } })
    ns.BuyClick()
    W.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = WISDOM })
    ns.BuyClick()
    W.Fire("AUCTION_HOUSE_SHOW_ERROR")
    eq(ns.buy.err, "ERR_GONE")
    ns.BuyClick()
    eq(ns.buy.phase, "ready")
    eq(ns.buy.quote.auction, 12)
end)

test("an item the client does not know yet: no commodity, so it is searched as an item", function()
    local ns = threeDays()
    ns.BuyClick()
    eq(W.calls[1], "start " .. WISDOM .. " 3")
    W.Fire("COMMODITY_PRICE_UNAVAILABLE")
    eq(ns.buy.err, nil)
    eq(W.itemSearches[1], WISDOM)
    W.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = WISDOM })
    eq(ns.buy.phase, "ready")
end)

test("a busy auction house: the click waits instead of failing", function()
    local ns = threeDays({ status = { [WISDOM] = 1 } })
    W.throttled = true
    ns.BuyClick()
    eq(ns.buy.err, "ERR_WAIT")
    eq(ns.buy.phase, "idle")
    W.throttled = false
    ns.BuyClick()
    eq(ns.buy.phase, "quote")
end)

test("a commodity of several units is bought at once, and the step's nodes fill", function()
    local ns = threeDays({ status = { [WISDOM] = 2, [WISDOM_ITEM] = 2 } })
    ns.BuyClick()
    eq(W.calls[1], "start " .. WISDOM .. " 3")
    W.Fire("COMMODITY_PRICE_UPDATED", 110, 330)
    ns.BuyClick()
    eq(W.calls[2], "buy " .. WISDOM .. " 3")
    W.Fire("COMMODITY_PURCHASE_SUCCEEDED")
    eq(ns.StepNodes(ns.buy.steps[1]).writ.done, 3)
    eq(ns.Current().part, "item")
end)

test("Recalculate at the auction house reads every lot again; away from it no lot counts", function()
    Fake({ rep = { 5, 8925 }, prices = { [WISDOM] = 100, [WISDOM_ITEM] = 200 }, db = { days = 1, sealed = false },
           lots = { [WISDOM] = { { 100, 5 } }, [WISDOM_ITEM] = {} } })
    local ns = Load()
    ns.lots[WISDOM_ITEM] = { t = time(), l = {} } -- read earlier: sold out
    local plan = ns.Calculate()
    eq(#plan.lines, 1, "away from the auction house the old lots say nothing")
    W.Fire("AUCTION_HOUSE_SHOW") -- plans anew, as Recalculate does
    local n = W.AnswerSearches()
    assert(n >= 2, "both lots read again, got " .. n)
    eq(#ns.plan.lines, 0, "the elixir is sold out now, never free")
end)

test("the Writs search finds by every word: name, item, trade and zone", function()
    Fake({})
    local ns = Load()
    local w = ns.Writ(OGRE)
    eq(ns.WritMatches(w, ""), true)
    local spot = ns.Spot(w)
    if spot then
        local zone = ns.ZoneName(spot.map)
        eq(ns.WritMatches(w, zone:upper()), true)
    end
    eq(ns.WritMatches(w, "alchemy"), true)
    eq(ns.WritMatches(w, "alchemy nothinglikethis"), false)
    local all, some = #ns.WritRows(nil, "prof", ""), #ns.WritRows(nil, "prof", "alchemy")
    assert(some > 0 and some < all, "the search narrows the list")
    eq(ns.Fold("ХИНТЕРЛАНД"), "хинтерланд")
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
    eq(ns.CostText(500, true):find("~", 1, true), nil)
    eq(ns.CostText(500):find(ns.Skin.Hex(ns.Skin.BAD) .. "-", 1, true) ~= nil, true)
    W.Fire("AUCTION_HOUSE_SHOW")
    ns.MoveTracker(true)
    assert(ns.TrackerFrame(), "the tracker for the Unlock mode")
    ns.MoveTracker(false)
end)

test("a long plan is calculated over several frames, with its share for the bar", function()
    local prices = {}
    Fake({ rep = { 5, 3000 }, db = { days = 13, goal = 7, sealed = true, live = false }, prices = prices })
    local ns = Load()
    for id, d in pairs(ns.WRITS) do prices[id] = 20000 + id % 97 * 1000; prices[d[4]] = 5000 + d[4] % 53 * 2000 end
    -- the game's frame clock: each look at it is a millisecond later
    local ms = 0
    debugprofilestop = function() ms = ms + 1; return ms end
    local w = ns.Window()
    w:Show()
    ns.ShowTab(2)
    eq(ns.Calculate(), nil)
    local running, share = ns.Calculating()
    eq(running, true)
    eq(ns.plan, nil)
    -- the job's frame steps it each frame
    local frames, last = 0, share
    while ns.Calculating() and frames < 10000 do
        for _, g in ipairs(W.frames) do
            local fn = rawget(g, "_OnUpdate")
            if fn then fn(g, 0.016) end
        end
        frames = frames + 1
        local _, now = ns.Calculating()
        if ns.Calculating() then assert(now >= last, "the bar only moves forward"); last = now end
    end
    debugprofilestop = nil
    eq(ns.Calculating(), false)
    assert(frames > 3, "it took several frames: " .. frames)
    assert(ns.plan and #ns.plan.lines > 0, "the plan came at the end")
end)

test("the window reads the bags and prices once until they change", function()
    Fake({ bags = { [OGRE] = 1 }, prices = { [OGRE_ITEM] = 100 } })
    local ns = Load()
    local a = ns.States()
    eq(ns.States() == a, true)
    W.Fire("BAG_UPDATE_DELAYED")
    eq(ns.States() == a, false)
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
