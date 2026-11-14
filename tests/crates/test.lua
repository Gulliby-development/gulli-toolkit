-- Run from the repository root: lua5.1 tests/crates/test.lua
local W = dofile("tests/crates/wow.lua")
local test, eq = W.test, W.eq

local FLOWER = 248691 -- 10 Wintersbite, 10 Firebloom, 20 Purple Lotus, 10 Arthas' Tears
local WB, FB, PL, AT = 3819, 4625, 8831, 8836
local NAMES = { [FLOWER] = "Waylaid Crate: Flowering Expert Herbs", [WB] = "Wintersbite", [FB] = "Firebloom",
                [PL] = "Purple Lotus", [AT] = "Arthas' Tears" }

local function names(extra)
    local t = {}
    for k, v in pairs(NAMES) do t[k] = v end
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end

test("every language has every text", function()
    Fake({})
    W.CheckLocales(Load())
end)

test("the table has thirty crates, each with bundles of positive counts", function()
    Fake({})
    local ns = Load()
    local n = 0
    for id, c in pairs(ns.CRATES) do
        n = n + 1
        assert(c[1] >= 10, "level of " .. id)
        assert(#c[2] >= 2, "bundles of " .. id)
        for _, b in ipairs(c[2]) do assert(b[1] > 0 and b[2] > 0, "bundle of " .. id) end
    end
    eq(n, 30, "crates")
end)

test("the crate's tooltip wins over the table", function()
    Fake({ names = names(), tooltips = { [FLOWER] = { NAMES[FLOWER], "Use: Fill the crate with any bundle from the following list:\n- 12 Wintersbite\n- 10 Firebloom\n- 20 Purple Lotus\n- 10 Arthas' Tears", "Requires Level 20" } } })
    local ns = Load()
    local b = ns.Bundles(FLOWER)
    eq(#b, 4)
    eq(b[1][1], WB); eq(b[1][2], 12)
    eq(b[4][1], AT)
end)

test("a tooltip line with an unknown item falls back to the table", function()
    Fake({ names = names(), tooltips = { [FLOWER] = { "- 10 Wintersbite", "- 5 Something New" } } })
    local ns = Load()
    eq(ns.Bundles(FLOWER)[1][2], 10)
    eq(#ns.Bundles(FLOWER), 4)
end)

test("a crate the table lacks is found by its tooltip, another item is not", function()
    Fake({ bags = { [999001] = 1, [999002] = 3 }, names = names({ [999001] = "Waylaid Crate: New", [999002] = "Rock" }),
           tooltips = { [999001] = { "Waylaid Crate: New", "- 5 Firebloom", "- 8 Purple Lotus" },
                        [999002] = { "Rock", "- 2 apples" } } })
    local ns = Load()
    local crates = ns.Crates()
    eq(#crates, 1)
    eq(crates[1].id, 999001)
    eq(ns.Bundles(999001)[2][2], 8)
end)

test("the cheapest bundle wins, and the bags and bank cost nothing", function()
    Fake({ bags = { [FLOWER] = 1, [FB] = 4 }, bank = { [FB] = 6 }, names = names(),
           prices = { [WB] = 300, [FB] = 1000, [PL] = 100, [AT] = 500 } })
    local ns = Load()
    local plan = ns.Calculate()
    local e = plan.crates[1]
    eq(e.bundle[1], FB, "Firebloom: all ten owned")
    eq(e.cost, 0)
    eq(e.rows[1].bags, 4); eq(e.rows[1].bank, 6); eq(e.rows[1].buy, 0)
    eq(#ns.ShoppingList(plan), 0)
    eq(e.others[1].bundle[1], PL, "next best: 20 Purple Lotus for 2000")
    eq(e.others[1].cost, 2000)
end)

test("without the bank switch the bank does not count", function()
    Fake({ bags = { [FLOWER] = 1, [FB] = 4 }, bank = { [FB] = 6 }, names = names(),
           prices = { [WB] = 300, [FB] = 1000, [PL] = 100, [AT] = 500 }, db = { bank = false } })
    local ns = Load()
    local e = ns.Calculate().crates[1]
    eq(e.bundle[1], PL)
    eq(e.cost, 2000)
end)

test("several crates share the stock: owned items fill one, the next buys", function()
    Fake({ bags = { [FLOWER] = 2, [WB] = 10 }, names = names(), prices = { [WB] = 300, [FB] = 1000, [PL] = 200, [AT] = 500 } })
    local ns = Load()
    local plan = ns.Calculate()
    eq(#plan.crates, 2)
    eq(plan.crates[1].bundle[1], WB); eq(plan.crates[1].cost, 0)
    eq(plan.crates[2].bundle[1], WB, "10 Wintersbite for 3000 beats 20 Lotus for 4000")
    eq(plan.crates[2].cost, 3000)
    eq(plan.total, 3000)
    local list = ns.ShoppingList(plan)
    eq(#list, 1); eq(list[1].id, WB); eq(list[1].n, 10)
end)

test("the shopping list adds up the same item over crates", function()
    Fake({ bags = { [FLOWER] = 3 }, names = names(), prices = { [WB] = 300, [FB] = 1000, [PL] = 200, [AT] = 500 } })
    local ns = Load()
    local list = ns.ShoppingList(ns.Calculate())
    eq(#list, 1); eq(list[1].n, 30); eq(list[1].cost, 9000)
end)

test("a part owned is used and only the rest is bought", function()
    Fake({ bags = { [FLOWER] = 1, [PL] = 15 }, names = names(), prices = { [WB] = 300, [FB] = 1000, [PL] = 200, [AT] = 500 } })
    local ns = Load()
    local e = ns.Calculate().crates[1]
    eq(e.bundle[1], PL, "5 Lotus for 1000 beat 10 Wintersbite for 3000")
    eq(e.rows[1].buy, 5); eq(e.cost, 1000)
end)

test("without prices only owned bundles count, and an unfillable crate says so", function()
    Fake({ bags = { [FLOWER] = 2, [AT] = 10 }, names = names(), noAuctionator = true })
    local ns = Load()
    local plan = ns.Calculate()
    eq(plan.crates[1].bundle[1], AT)
    assert(plan.crates[2].none, "the second crate has no price")
    assert(plan.unpriced[WB])
end)

test("an unticked crate is left out", function()
    Fake({ bags = { [FLOWER] = 1, [248682] = 1 }, names = names(), prices = { [WB] = 300, [2447] = 10 } })
    local ns = Load()
    ns.picked[FLOWER] = false
    local plan = ns.Calculate()
    eq(#plan.crates, 1)
    eq(plan.crates[1].crate, 248682)
end)

test("buying: one click for the price, one to buy, then one per line", function()
    Fake({ bags = { [FLOWER] = 2 }, names = names(), prices = { [WB] = 300, [FB] = 310, [PL] = 900, [AT] = 900 } })
    local ns = Load()
    W.Fire("AUCTION_HOUSE_SHOW")
    ns.Calculate()
    -- two crates: Wintersbite for the first, then Firebloom (the 20 Wintersbite would cost the same per crate)
    eq(#ns.buy.queue, 1, "both crates take 10 Wintersbite: one line of 20")
    ns.BuyClick()
    eq(W.calls[1], "start 3819 20")
    eq(ns.buy.phase, "quote")
    ns.BuyClick()
    eq(#W.calls, 1, "a click while waiting does nothing")
    W.Fire("COMMODITY_PRICE_UPDATED", 310, 6200)
    eq(ns.buy.phase, "ready")
    ns.BuyClick()
    eq(W.calls[2], "buy 3819 20")
    W.Fire("COMMODITY_PURCHASE_SUCCEEDED")
    eq(ns.buy.phase, "done")
    eq(ns.buy.spent, 6200)
    assert(W.printed[#W.printed]:find("bought 1 lines", 1, true), W.printed[#W.printed])
end)

test("after a purchase the next price waits for the next click", function()
    Fake({ bags = { [FLOWER] = 1, [248682] = 1 }, order = { FLOWER, 248682 }, names = names(),
           prices = { [WB] = 300, [2447] = 10 } })
    local ns = Load()
    W.Fire("AUCTION_HOUSE_SHOW")
    ns.Calculate()
    eq(#ns.buy.queue, 2)
    ns.BuyClick()
    W.Fire("COMMODITY_PRICE_UPDATED", 300, 3000)
    ns.BuyClick()
    W.Fire("COMMODITY_PURCHASE_SUCCEEDED")
    eq(#W.calls, 2, "no protected call from the event")
    eq(ns.buy.phase, "idle")
    ns.BuyClick()
    eq(W.calls[3], "start 2447 20")
    eq(ns.buy.phase, "quote")
end)

test("sold out: the line says so and Skip goes on", function()
    Fake({ bags = { [FLOWER] = 1, [248682] = 1 }, order = { FLOWER, 248682 }, names = names(),
           prices = { [WB] = 300, [2447] = 10 } })
    local ns = Load()
    W.Fire("AUCTION_HOUSE_SHOW")
    ns.Calculate()
    ns.BuyClick()
    W.Fire("COMMODITY_PRICE_UNAVAILABLE")
    eq(ns.buy.phase, "idle"); eq(ns.buy.err, "ERR_SOLD_OUT")
    ns.Skip()
    eq(ns.Current().id, 2447)
    eq(#ns.buy.failed, 1)
end)

test("no answer in time lets the button ask again", function()
    Fake({ bags = { [FLOWER] = 1 }, names = names(), prices = { [WB] = 300 } })
    local ns = Load()
    W.Fire("AUCTION_HOUSE_SHOW")
    ns.Calculate()
    ns.BuyClick()
    W.RunTimers()
    eq(ns.buy.phase, "idle"); eq(ns.buy.err, "ERR_NO_ANSWER")
end)

test("away from the auction house the button buys nothing", function()
    Fake({ bags = { [FLOWER] = 1 }, names = names(), prices = { [WB] = 300 } })
    local ns = Load()
    ns.Calculate()
    ns.BuyClick()
    eq(#W.calls, 0)
end)

test("a much dearer quote is flagged", function()
    Fake({ bags = { [FLOWER] = 1 }, names = names(), prices = { [WB] = 300 } })
    local ns = Load()
    W.Fire("AUCTION_HOUSE_SHOW")
    ns.Calculate()
    ns.BuyClick()
    W.Fire("COMMODITY_PRICE_UPDATED", 600, 6000)
    assert(ns.Dear())
end)

test("without the commodity auction house the list goes to Auctionator", function()
    Fake({ bags = { [FLOWER] = 1 }, names = names(), prices = { [WB] = 300 }, ah = false })
    local ns = Load()
    ns.Calculate()
    eq(ns.CanBuy(), false)
    eq(ns.ExportList(), 1)
    eq(W.list.terms[1], '"Wintersbite"')
end)

test("the window opens at the auction house only with a crate and the switch on", function()
    Fake({ bags = { [FLOWER] = 1 }, names = names() })
    local ns = Load()
    W.Fire("AUCTION_HOUSE_SHOW")
    assert(ns.Window():IsShown(), "opened")
    W.Fire("AUCTION_HOUSE_CLOSED")
    assert(not ns.Window():IsShown(), "closed with the auction house")
    Fake({ bags = { [FLOWER] = 1 }, names = names(), db = { auto = false } })
    ns = Load()
    W.Fire("AUCTION_HOUSE_SHOW")
    assert(not ns.Window():IsShown(), "switch off")
    Fake({ bags = { [2447] = 5 }, names = names() })
    ns = Load()
    W.Fire("AUCTION_HOUSE_SHOW")
    assert(not ns.Window():IsShown(), "no crate")
end)

test("a paused module does nothing at the auction house", function()
    local reg
    Fake({ bags = { [FLOWER] = 1 }, names = names() })
    GulliToolkit = { Register = function(m) reg = m end }
    local ns = Load()
    reg.pause(true)
    W.Fire("AUCTION_HOUSE_SHOW")
    assert(not ns.atAH and not ns.Window():IsShown())
end)

test("a filled crate goes into the history: crate and bundle leave the bags together", function()
    Fake({ bags = { [FLOWER] = 2, [WB] = 10, [PL] = 20 }, names = names(), prices = { [WB] = 300 } })
    local ns = Load()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.bags[FLOWER], W.bags[WB] = 1, nil
    W.Fire("BAG_UPDATE_DELAYED")
    eq(#ns.db.history, 1)
    local e = ns.db.history[1]
    eq(e.crate, FLOWER); eq(e.item, WB); eq(e.n, 10)
    eq(e.paid, 0, "all from the stock")
    eq(e.worth, 3000)
    eq(e.who, "Tester")
end)

test("the crate and its items may leave in separate bag updates, either first", function()
    Fake({ bags = { [FLOWER] = 2, [WB] = 10, [PL] = 20 }, names = names() })
    local ns = Load()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.bags[FLOWER] = 1
    W.Fire("BAG_UPDATE_DELAYED")
    eq(#ns.db.history, 0, "the crate alone is not yet a fill")
    W.bags[WB] = nil
    W.Fire("BAG_UPDATE_DELAYED")
    eq(#ns.db.history, 1, "crate first")
    W.bags[PL] = nil
    W.Fire("BAG_UPDATE_DELAYED")
    W.bags[FLOWER] = nil
    W.Fire("BAG_UPDATE_DELAYED")
    eq(#ns.db.history, 2, "items first")
    eq(ns.db.history[1].item, PL)
end)

test("a crate that leaves the bags alone is not a fill", function()
    Fake({ bags = { [FLOWER] = 1, [WB] = 10 }, names = names() })
    local ns = Load()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.bags[FLOWER] = nil
    W.Fire("BAG_UPDATE_DELAYED")
    W.now = W.now + 10
    W.bags[WB] = nil
    W.Fire("BAG_UPDATE_DELAYED")
    eq(#ns.db.history, 0)
    W.bags = { [FLOWER] = 1, [WB] = 10 }
    W.Fire("BAG_UPDATE_DELAYED")
    W.bags[WB] = nil
    W.Fire("BAG_UPDATE_DELAYED")
    W.now = W.now + 10
    W.bags[FLOWER] = nil
    W.Fire("BAG_UPDATE_DELAYED")
    eq(#ns.db.history, 0, "items that left long before do not make a fill")
end)

test("the history knows what the auction house got for a crate", function()
    Fake({ bags = { [FLOWER] = 1, [WB] = 4 }, names = names(), prices = { [WB] = 300, [FB] = 900, [PL] = 900, [AT] = 900 } })
    local ns = Load()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.Fire("AUCTION_HOUSE_SHOW")
    ns.Calculate()
    eq(ns.Current().n, 6)
    ns.BuyClick()
    W.Fire("COMMODITY_PRICE_UPDATED", 320, 1920)
    ns.BuyClick()
    W.Fire("COMMODITY_PURCHASE_SUCCEEDED")
    W.bags[WB] = 10
    W.Fire("BAG_UPDATE_DELAYED")
    W.bags[FLOWER], W.bags[WB] = nil, nil
    W.Fire("BAG_UPDATE_DELAYED")
    local e = ns.db.history[1]
    eq(e.paid, 1920); eq(e.bought, 6)
    eq(ns.TakeLots(WB, 5), 0, "the lot is used up")
end)

test("the history filters by period and adds up", function()
    Fake({ names = names(), db = { history = {
        { at = 100000 - 3600, crate = FLOWER, item = WB, n = 10, paid = 3000 },
        { at = 100000 - 3 * 86400, crate = FLOWER, item = WB, n = 10, paid = 1000 },
        { at = 100000 - 30 * 86400, crate = FLOWER, item = PL, n = 20, paid = 0 } } } })
    local ns = Load()
    local list, sum = ns.History("day")
    eq(#list, 1); eq(sum.spent, 3000)
    list, sum = ns.History("week")
    eq(#list, 2); eq(sum.avg, 2000)
    list, sum = ns.History("all")
    eq(sum.count, 3); eq(sum.spent, 4000)
end)

test("an old plan goes when no crate is left, or all is bought and the auction house closed", function()
    Fake({ bags = { [FLOWER] = 1 }, names = names(), prices = { [WB] = 300 } })
    local ns = Load()
    ns.Calculate()
    W.bags[FLOWER] = nil
    W.Fire("BAG_UPDATE_DELAYED")
    eq(ns.plan, nil, "no crate")
    W.bags[FLOWER] = 1
    W.Fire("AUCTION_HOUSE_SHOW")
    ns.Calculate()
    ns.BuyClick()
    W.Fire("COMMODITY_PRICE_UPDATED", 300, 3000)
    ns.BuyClick()
    W.Fire("COMMODITY_PURCHASE_SUCCEEDED")
    W.Fire("BAG_UPDATE_DELAYED")
    assert(ns.plan ~= nil, "kept while at the auction house")
    W.Fire("AUCTION_HOUSE_CLOSED")
    eq(ns.plan, nil, "all bought")
end)

test("the refresh button plans anew, or clears the plan without crates", function()
    Fake({ bags = { [FLOWER] = 1 }, names = names(), prices = { [WB] = 300 } })
    local ns = Load()
    ns.Recheck()
    assert(ns.plan and #ns.plan.crates == 1, "planned")
    W.bags[248682] = 1
    ns.Recheck()
    eq(#ns.plan.crates, 2, "the new crate counts")
    W.bags = {}
    ns.Recheck()
    eq(ns.plan, nil)
end)

test("the history tab draws without errors", function()
    Fake({ names = names(), db = { history = { { at = 99000, crate = FLOWER, item = WB, n = 10, paid = 3000, bought = 6, who = "Tester" } } } })
    local ns = Load()
    ns.Window():Show()
    ns.ShowTab(2)
    ns.Refresh()
    ns.ShowTab(1)
end)

test("the window draws a plan without errors", function()
    Fake({ bags = { [FLOWER] = 2, [WB] = 3 }, bank = { [WB] = 4 }, names = names(), prices = { [WB] = 300, [FB] = 1000 } })
    local ns = Load()
    W.Fire("AUCTION_HOUSE_SHOW")
    ns.Calculate()
    ns.Refresh()
    local rows = ns.PlanRows(ns.plan)
    eq(rows[1].kind, "crate")
    eq(rows[2].kind, "item")
    eq(ns.ShortName(NAMES[FLOWER]), "Flowering Expert Herbs")
end)

W.finish()
