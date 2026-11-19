-- Run from the repository root: lua5.1 tests/vendorflip/test.lua
local W = dofile("tests/vendorflip/wow.lua")
local test, eq = W.test, W.eq

local ORE, FANG, BELT, CLOAK, ROCK = 2770, 3300, 5001, 5002, 2836
local ITEMS = {
    [ORE] = { "Copper Ore", 1, 10, 20, 7 },      -- vendor pays 10c, stacks of 20, a trade good
    [FANG] = { "Broken Fang", 0, 230, 10, 15 },
    [BELT] = { "Warrior's Belt", 2, 11200, 1, 4 }, -- armour
    [CLOAK] = { "Shore Cloak", 2, 3500, 1, 4 },
    [ROCK] = { "Coarse Stone", 1, 3, 20, 7 },
}

local function market(extra)
    local spec = { items = ITEMS, money = 1000000, free = 10,
        browse = { { ORE, 4 }, { FANG, 75 }, { BELT, 4800 }, { CLOAK, 2000 }, { ROCK, 8 } },
        commodity = { [ORE] = { { 4, 30 }, { 6, 10 }, { 12, 100 } }, [FANG] = { { 75, 12 }, { 300, 5 } },
                      [ROCK] = { { 8, 50 } } },
        lots = { [BELT] = { { 901, 1, 4800 }, { 902, 1, 20000 } }, [CLOAK] = { { 911, 1, 2000, true } } } }
    for k, v in pairs(extra or {}) do spec[k] = v end
    return spec
end

local function find(ns, id)
    for _, line in ipairs(ns.lines) do if line.id == id then return line end end
end

test("every language has every text", function()
    Fake({})
    W.CheckLocales(Load())
end)

test("candidates are the items a vendor pays more for, best gain first", function()
    Fake({ items = ITEMS })
    local ns = Load()
    local sell = function(id) return ITEMS[id] and ITEMS[id][3] end
    local res = {}
    for _, b in ipairs({ { ORE, 4 }, { ROCK, 8 }, { BELT, 4800 }, { 99999, 1 } }) do
        res[#res + 1] = { itemKey = { itemID = b[1] }, minPrice = b[2] }
    end
    local c = ns.Candidates(res, sell)
    eq(#c, 2, "rock costs more than a vendor pays, the unknown item waits")
    eq(c[1].id, BELT)
    eq(c[2].id, ORE)
    eq(c[2].gain, 6)
end)

test("a commodity is bought up the ladder only while a unit sells for more", function()
    Fake({})
    local ns = Load()
    local d = ns.CommodityDeal({ { 4, 30 }, { 6, 10 }, { 12, 100 } }, 10, 1000000, 10, 20)
    eq(d.n, 40)
    eq(d.cost, 30 * 4 + 10 * 6)
    eq(d.value, 400)
    eq(d.gain, 400 - 180)
    -- own units are skipped
    d = ns.CommodityDeal({ { 4, 30, 30 }, { 6, 10 } }, 10, 1000000, 10, 20)
    eq(d.n, 10)
    -- money and room cut it
    eq(ns.CommodityDeal({ { 4, 30 } }, 10, 41, 10, 20).n, 10)
    eq(ns.CommodityDeal({ { 4, 30 } }, 10, 1000000, 1, 20).n, 20)
    eq(ns.CommodityDeal({ { 10, 30 } }, 10, 1000000, 10, 20), nil, "equal price is no gain")
end)

test("an item is bought lot by lot, never a bid-only or an own lot", function()
    Fake({})
    local ns = Load()
    local d = ns.ItemDeals({ { 1, 1, 4800, 11200 }, { 2, 1, 20000, 11200 }, { 3, 1, nil, 11200 }, { 4, 1, 100, 11200, true },
                             { 5, 2, 1000, 600 } })
    eq(#d, 2)
    eq(d[1].auction, 1)
    eq(d[1].gain, 6400)
    eq(d[2].auction, 5)
    eq(d[2].value, 1200)
end)

test("a scan at the auction house finds the lines, best gain first", function()
    local w = Fake(market({ db = { minGain = 0 } }))
    local ns = Load()
    w.ScanAll(ns)
    eq(#w.queries, 1, "one browse")
    eq(w.queries[1].searchString, "")
    local shown = ns.Shown()
    eq(#shown, 3, "belt, fangs and ore; rock is dearer, the own cloak is skipped")
    eq(shown[1].id, BELT)
    eq(shown[1].kind, "i")
    eq(shown[2].id, FANG)
    eq(shown[2].n, 12)
    eq(shown[3].id, ORE)
    eq(shown[3].n, 40)
    eq(ns.Open(), 3)
    eq(ns.Top(), shown[1])
end)

test("the least gain setting hides small lines", function()
    local w = Fake(market({ db = { minGain = 2000 } }))
    local ns = Load()
    w.ScanAll(ns)
    eq(#ns.Shown(), 1)
    eq(ns.Shown()[1].id, BELT)
end)

test("lines that would take the gold reserve or the free slots are hidden", function()
    local w = Fake(market({ money = 6000, db = { reserve = 2000, minGain = 0 } }))
    local ns = Load()
    w.ScanAll(ns)
    for _, line in ipairs(ns.Shown()) do assert(line.id ~= BELT, "the belt would take the reserve") end
    w = Fake(market({ free = 2, db = { keepFree = 2 } }))
    ns = Load()
    w.ScanAll(ns)
    eq(#ns.Shown(), 0, "no slot left above the two kept free")
end)

test("a commodity takes two clicks: the price, then the purchase", function()
    local w = Fake(market())
    local ns = Load()
    w.ScanAll(ns)
    local ore = find(ns, ORE)
    ns.Click(ore)
    eq(w.calls[#w.calls], "start " .. ORE .. " 40")
    eq(ns.buy.phase, "quote")
    w.Fire("COMMODITY_PRICE_UPDATED", 5, 200)
    eq(ns.buy.phase, "ready")
    local spec = ns.RowButton(ore)
    assert(spec.primary and spec.on, "the row button buys now")
    ns.Click(ore)
    eq(w.calls[#w.calls], "buy " .. ORE .. " 40")
    w.Fire("COMMODITY_PURCHASE_SUCCEEDED")
    eq(ore.state, "bought")
    eq(#ns.db.history, 1)
    eq(ns.db.history[1].paid, 200)
    eq(ns.db.history[1].value, 400)
    eq(ns.Owed()[ORE], 40)
end)

test("a price that came back dearer than the vendor pays is never bought", function()
    local w = Fake(market())
    local ns = Load()
    w.ScanAll(ns)
    local ore = find(ns, ORE)
    ns.Click(ore)
    w.Fire("COMMODITY_PRICE_UPDATED", 10, 400)
    eq(ore.state, "lose")
    eq(w.calls[#w.calls], "cancel")
    ns.Click(ore)
    for _, c in ipairs(w.calls) do assert(not c:find("^buy"), "bought at a loss: " .. c) end
end)

test("an item lot is bought out with one click", function()
    local w = Fake(market())
    local ns = Load()
    w.ScanAll(ns)
    local belt = find(ns, BELT)
    ns.Click(ns.Top())
    eq(w.calls[#w.calls], "bid 901 4800")
    w.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 901)
    eq(belt.state, "bought")
    eq(ns.Top().id, FANG, "the big button goes on with the next line")
end)

test("a line without the gold for it buys nothing", function()
    local w = Fake(market())
    local ns = Load()
    w.ScanAll(ns)
    w.money = 100
    ns.Click(find(ns, BELT))
    eq(ns.buy.err, "ERR_ROOM")
    eq(#w.calls, 0)
end)

test("a buy click in the middle of a scan buys at once; the scan waits and goes on after", function()
    local w = Fake(market({ db = { minGain = 0 } }))
    local ns = Load()
    w.ScanAll(ns)
    w.now = w.now + ns.INTERVAL + 1
    ns.Tick()
    w.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    eq(ns.scan.phase, "detail")
    local sent = #w.searches
    -- the player clicks the belt of the last scan while the scan reads lots
    local belt
    for _, line in ipairs(ns.lines) do if line.id == BELT then belt = line end end
    ns.Click(belt)
    eq(w.calls[#w.calls], "bid 901 4800", "bought at once")
    w.AnswerSearches()
    w.RunTimers()
    eq(#w.searches, sent, "no new search while the purchase runs")
    eq(ns.scan.held, true)
    w.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 901)
    eq(belt.state, "bought")
    w.now = w.now + ns.HOLD + 1
    w.RunTimers()
    w.AnswerSearches()
    w.RunTimers()
    assert(#w.searches > sent, "the scan goes on")
    eq(ns.scan.phase, "idle")
end)

test("clicks during a purchase queue lines; the big button buys them in order", function()
    local w = Fake(market({ db = { minGain = 0 } }))
    local ns = Load()
    w.ScanAll(ns)
    local ore, belt, fang = find(ns, ORE), find(ns, BELT), find(ns, FANG)
    ns.Click(ore)
    eq(ns.buy.phase, "quote")
    ns.Click(belt)
    ns.Click(fang)
    eq(ns.QueuePos(belt), 1)
    eq(ns.QueuePos(fang), 2)
    eq(ns.RowButton(fang).text, ns.L.QUEUED:format(2))
    assert(ns.RowButton(fang).on, "a queued line can be clicked out of the queue")
    eq(#w.calls, 1, "a queued click buys nothing by itself")
    ns.Click(fang)
    eq(ns.QueuePos(fang), nil, "a second click takes it out")
    ns.Click(fang)
    w.Fire("COMMODITY_PRICE_UPDATED", 5, 200)
    ns.Click(ns.Top())
    eq(w.calls[#w.calls], "buy " .. ORE .. " 40")
    w.Fire("COMMODITY_PURCHASE_SUCCEEDED")
    eq(ns.Top(), belt, "the first queued line comes next")
    ns.Click(ns.Top())
    eq(w.calls[#w.calls], "bid 901 4800")
    w.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 901)
    eq(ns.Top(), fang)
    eq(ns.QueuePos(belt), nil)
    w.Fire("AUCTION_HOUSE_CLOSED")
    eq(#ns.queue, 0, "closing the auction house empties the queue")
end)

test("a purchase confirmed after the wait gave up is still in the history", function()
    local w = Fake(market({ db = { minGain = 0 } }))
    local ns = Load()
    w.ScanAll(ns)
    local belt, ore = find(ns, BELT), find(ns, ORE)
    ns.Click(belt)
    w.RunTimers() -- no answer in time
    eq(ns.buy.err, "ERR_NO_ANSWER")
    w.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 901)
    eq(belt.state, "bought")
    eq(#ns.db.history, 1)
    ns.Click(ore)
    w.Fire("COMMODITY_PRICE_UPDATED", 5, 200)
    ns.Click(ore)
    w.RunTimers()
    eq(ns.buy.phase, "idle")
    w.Fire("COMMODITY_PURCHASE_SUCCEEDED")
    eq(ore.state, "bought")
    eq(#ns.db.history, 2)
    eq(ns.db.history[1].paid, 200)
    w.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 901)
    eq(#ns.db.history, 2, "one confirmation, one entry")
end)

test("a click while the auction house is still busy queues the line and says to click again", function()
    local w = Fake(market({ db = { minGain = 0 } }))
    local ns = Load()
    w.ScanAll(ns)
    local belt = find(ns, BELT)
    w.throttled = true
    ns.Click(belt)
    eq(ns.buy.err, "ERR_WAIT")
    eq(ns.QueuePos(belt), 1)
    eq(#w.calls, 0)
    w.throttled = false
    ns.Click(ns.Top())
    eq(w.calls[#w.calls], "bid 901 4800")
end)

test("the scan waits while the player searches the auction house", function()
    local w = Fake(market())
    local ns = Load()
    w.Fire("AUCTION_HOUSE_SHOW")
    ns.OthersQuery()
    eq(ns.Scan(), false)
    w.now = w.now + ns.QUIET + 1
    eq(ns.Scan(), true)
    -- the player's query in the middle of ours stops ours
    ns.OthersQuery()
    eq(ns.Scanning(), false)
end)

test("the picked interval: from 5 seconds to 5 minutes, fewer lots per scan when short", function()
    local w = Fake(market({ db = { interval = 5 } }))
    local ns = Load()
    w.ScanAll(ns)
    eq(#w.queries, 1)
    w.now = w.now + 4
    ns.Tick()
    eq(#w.queries, 1)
    w.now = w.now + 2
    ns.Tick()
    eq(#w.queries, 2, "the next scan 5 seconds after the last ended")
    assert(ns.DetailMax(5) < ns.DETAIL_MAX, "a short interval reads fewer lots")
    eq(ns.DetailMax(60), ns.DETAIL_MAX)
    eq(ns.DetailMax(300), ns.DETAIL_MAX)
    for _, i in ipairs(ns.INTERVALS) do
        assert(ns.DetailMax(i) * 60 / i <= ns.SEARCHES_PER_MIN or ns.DetailMax(i) == ns.DETAIL_MIN, "too many searches at " .. i)
    end
    ns.SetPref("interval", 7)
    eq(ns.Interval(), ns.INTERVAL, "a value not in the list is a minute")
    ns.SetPref("interval", 300)
    eq(ns.Interval(), 300)
end)

test("the scan runs again every minute, and not with the switch off", function()
    local w = Fake(market())
    local ns = Load()
    w.ScanAll(ns)
    eq(#w.queries, 1)
    w.now = w.now + ns.INTERVAL - 5
    ns.Tick()
    eq(#w.queries, 1)
    w.now = w.now + 10
    ns.Tick()
    eq(#w.queries, 2)
    w.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    w.AnswerSearches()
    ns.SetPref("scan", false)
    w.now = w.now + 3 * ns.INTERVAL
    ns.Tick()
    eq(#w.queries, 2)
end)

test("a bought line keeps its state when the next scan finds it again", function()
    local w = Fake(market())
    local ns = Load()
    w.ScanAll(ns)
    ns.Click(find(ns, BELT))
    w.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 901)
    w.searches = {}
    w.now = w.now + ns.INTERVAL + 1
    ns.Tick()
    w.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    w.AnswerSearches()
    eq(find(ns, BELT).state, "bought")
end)

test("only what was bought here is sold at a vendor, and only with the switch or a click", function()
    local w = Fake(market({ bags = { { ORE, 20 }, { ORE, 20 }, { ORE, 15 }, { FANG, 3 }, { ROCK, 5 } } }))
    local ns = Load()
    w.ScanAll(ns)
    ns.Log(ORE, 40, 180, 400)
    ns.Log(FANG, 3, 225, 690)
    GulliToolkit = { IsProtected = function(id) return id == FANG end }
    w.Fire("MERCHANT_SHOW")
    eq(#w.used, 0, "with the switch off a notice asks first")
    ns.Sell()
    eq(#w.used, 2, "two stacks of 20 ore; the third stack is the player's, the fangs are protected")
    for _, u in ipairs(w.used) do eq(u.id, ORE) end
    eq(ns.Owed()[ORE], nil)
    eq(ns.db.history[2].sold, 40)
    GulliToolkit = nil
end)

test("the sell switch sells at once; a kept line is not sold", function()
    local w = Fake(market({ bags = { { ORE, 20 }, { BELT, 1 } }, db = { sell = true } }))
    local ns = Load()
    ns.Log(ORE, 20, 80, 200)
    ns.Log(BELT, 1, 4800, 11200)
    ns.Keep(ns.db.history[1])
    w.Fire("MERCHANT_SHOW")
    eq(#w.used, 1)
    eq(w.used[1].id, ORE)
    local _, sum = ns.History("all")
    eq(sum.profit, 120, "the kept belt is out of the totals")
end)

test("a paused module neither scans nor opens", function()
    local w = Fake(market())
    GulliToolkit = { Register = function(o) W.reg = o end }
    local ns = Load()
    GulliToolkit = nil
    W.reg.pause(true)
    w.Fire("AUCTION_HOUSE_SHOW")
    eq(ns.atAH, nil)
    eq(ns.Scan(true), false)
    W.reg.pause(false)
end)

test("at the auction house its tab opens beside it, unless the switch is off", function()
    local w = Fake(market())
    local ns = Load()
    w.Fire("AUCTION_HOUSE_SHOW")
    eq((ns.Skin.SideIs("VendorFlip")), true)
    w.Fire("AUCTION_HOUSE_CLOSED")
    eq((ns.Skin.SideIs("VendorFlip")), false)
    w = Fake(market({ db = { auto = false } }))
    ns = Load()
    w.Fire("AUCTION_HOUSE_SHOW")
    eq((ns.Skin.SideIs("VendorFlip")), false)
end)

test("the window builds and every tab draws", function()
    local w = Fake(market({ bags = { { ORE, 20 } } }))
    local ns = Load()
    w.ScanAll(ns)
    local f = ns.Window()
    f:Show()
    ns.Refresh()
    for i = 1, 3 do ns.ShowTab(i); ns.Refresh() end
    ns.ShowTab(1)
    local text = ns.ScanLine()
    assert(text:find("1:00") or text:find("0:5"), "next scan countdown: " .. text)
end)

test("money fields: gold, silver and copper each step by one coin and take a typed number", function()
    Fake({})
    local ns = Load()
    local S = ns.Skin
    assert(select(1, S.MoneyParts(123456)) == 12 and select(2, S.MoneyParts(123456)) == 34
           and select(3, S.MoneyParts(123456)) == 56, "parts")
    assert(S.MoneyJoin(1, 150, 7) == 19907, "silver over 99 is kept to 99")
    local v = 1
    local m = S.MoneyStepper(W.stub(), function() return v end, function(x) v = x end, ns.MIN_GAIN, ns.MAX_MONEY)
    local g, s, c = m.fields[1], m.fields[2], m.fields[3]
    c.minus:GetScript("OnClick")(c.minus)
    assert(v == 1, "the least gain goes no lower than one copper: " .. v)
    c.plus:GetScript("OnClick")(c.plus)
    assert(v == 2, "copper +1: " .. v)
    s.plus:GetScript("OnClick")(s.plus)
    g.plus:GetScript("OnClick")(g.plus)
    assert(v == 10102, "silver and gold +1: " .. v)
    s.box:SetText("45")
    s.box:GetScript("OnEnterPressed")(s.box)
    assert(v == 14502, "typed silver: " .. v)
    g.box:SetText("")
    g.box:GetScript("OnEditFocusLost")(g.box)
    assert(v == 4502, "an empty gold box is no gold: " .. v)
    assert(g.box:GetText() == "0" and s.box:GetText() == "45" and c.box:GetText() == "2", "the boxes show the amount")
end)

test("a least gain of one copper shows the smallest lines", function()
    local w = Fake(market({ db = { minGain = 1 } }))
    local ns = Load()
    w.ScanAll(ns)
    local all = Fake(market({ db = { minGain = 0 } }))
    local ns0 = Load()
    all.ScanAll(ns0)
    assert(#ns.Shown() == #ns0.Shown(), "every line gains at least a copper")
end)

test("Scan now on the deals page starts a scan at once", function()
    local w = Fake(market({ db = { scan = false } }))
    local ns = Load()
    w.Fire("AUCTION_HOUSE_SHOW")
    ns.Window():Show()
    ns.Refresh()
    assert(ns.scan.phase == "idle", "no scan while scanning is off")
    assert(ns.Scan(true), "the button's call starts a scan")
    assert(ns.scan.phase == "browse", "browsing")
end)

test("the filters: gear only, goods only, by quality", function()
    local function ids(db)
        db.minGain = 0
        local w = Fake(market({ db = db }))
        local ns = Load()
        w.ScanAll(ns)
        local out = {}
        for _, line in ipairs(ns.Shown()) do out[#out + 1] = line.id end
        table.sort(out)
        return table.concat(out, ","), w
    end
    eq(ids({ goods = false }), tostring(BELT), "gear only")
    eq(ids({ gear = false }), ORE .. "," .. FANG, "goods only")
    eq(ids({ q2 = false }), ORE .. "," .. FANG, "no greens")
    eq(ids({ q0 = false, q1 = false }), tostring(BELT), "greens and better")
    local got, w = ids({ gear = false, goods = false })
    eq(got, "", "nothing wanted")
    eq(#w.searches, 0, "an item left out is never searched")
end)

test("a filter changed after the scan hides its lines at once", function()
    local w = Fake(market({ db = { minGain = 0 } }))
    local ns = Load()
    w.ScanAll(ns)
    eq(#ns.Shown(), 3)
    ns.SetPref("gear", false)
    eq(#ns.Shown(), 2)
    ns.SetPref("gear", true)
    eq(#ns.Shown(), 3)
end)

test("the most per line and the least gain in percent", function()
    local w = Fake(market({ db = { minGain = 0, maxPrice = 100 } }))
    local ns = Load()
    w.ScanAll(ns)
    local got = {}
    for _, line in ipairs(ns.Shown()) do got[line.id] = line; assert(line.cost <= 100, "a line over the most") end
    assert(not got[BELT], "the belt costs 48 silver")
    eq(got[ORE].n, 25, "the ore is cut to what 100 copper buys")
    eq(got[FANG].n, 1, "one fang costs 75, two 150")
    w = Fake(market({ db = { minGain = 0, minPct = 100 } }))
    ns = Load()
    w.ScanAll(ns)
    got = {}
    for _, line in ipairs(ns.Shown()) do got[line.id] = line end
    eq(got[ORE].n, 30, "only the ore at 4 doubles its money; at 6 it gains 66%")
    assert(got[FANG] and got[BELT], "fangs and the belt gain more than 100%")
    eq(ns.PriceOK({ cost = 100, gain = 9 }, 0, 10), false)
    eq(ns.PriceOK({ cost = 100, gain = 10 }, 0, 10), true)
    eq(ns.PriceOK({ cost = 101, gain = 500 }, 100, 0), false)
    eq(ns.Wanted(5, 4, { q4 = false }), false, "legendary counts as purple")
end)

test("a big market is looked at a part per frame, loads few items and redraws once per burst", function()
    local browse = {}
    for k = 1, 2000 do browse[#browse + 1] = { 100000 + k, k } end -- items the client does not know yet
    browse[#browse + 1] = { BELT, 4800 }
    local w = Fake(market({ browse = browse, db = { minGain = 0 } }))
    local ns = Load()
    local draws = 0
    local real = ns.Refresh
    ns.Refresh = function() draws = draws + 1; return real() end
    w.Fire("AUCTION_HOUSE_SHOW")
    assert(ns.Scan(true))
    w.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    eq(ns.scan.phase, "sift", "not all in one frame")
    eq(ns.scan.sifted, ns.SIFT_STEP)
    local frames = 1
    while ns.scan.phase == "sift" do w.RunTimers(); frames = frames + 1 end
    assert(frames >= 2001 / ns.SIFT_STEP, "frames: " .. frames)
    eq(w.loads, ns.LOAD_MAX, "the client is asked for at most LOAD_MAX items")
    eq(ns.scan.phase, "detail")
    w.AnswerSearches()
    eq(find(ns, BELT) ~= nil, true, "the known deal past the unknown ones is found")
    draws = 0
    for _ = 1, 500 do w.Fire("GET_ITEM_INFO_RECEIVED", 1) end
    eq(draws, 0, "no redraw per item")
    w.RunTimers()
    eq(draws, 1, "one redraw for the burst")
end)

test("random markets: nothing is offered at a loss or past the limits", function()
    math.randomseed(20261119)
    local offered = 0
    for round = 1, 200 do
        local items, browse, commodity, lots = {}, {}, {}, {}
        for k = 1, 6 do
            local id = 1000 + k
            local sell = math.random(1, 3000)
            items[id] = { "Item " .. k, math.random(0, 4), sell, math.random(1, 20), math.random() < 0.4 and 4 or 7 }
            if math.random() < 0.5 then
                local l = {}
                for _ = 1, math.random(1, 4) do l[#l + 1] = { math.random(1, 4000), math.random(1, 30), math.random() < 0.2 and 1 or 0 } end
                table.sort(l, function(a, b) return a[1] < b[1] end)
                commodity[id] = l
                browse[#browse + 1] = { id, l[1][1] }
            else
                local l = {}
                for j = 1, math.random(1, 3) do l[#l + 1] = { round * 100 + k * 10 + j, 1, math.random(1, 4000), math.random() < 0.2 } end
                lots[id] = l
                browse[#browse + 1] = { id, l[1][3] }
            end
        end
        local money, free = math.random(0, 50000), math.random(0, 6)
        local w = Fake({ items = items, browse = browse, commodity = commodity, lots = lots, money = money, free = free,
                         db = { minGain = 0, reserve = math.random(0, 3) * 1000, keepFree = math.random(0, 2),
                                maxPrice = math.random() < 0.5 and 0 or math.random(1, 5000),
                                minPct = math.random() < 0.5 and 0 or math.random(0, 20) * 5,
                                gear = math.random() < 0.8, goods = math.random() < 0.8,
                                q0 = math.random() < 0.8, q2 = math.random() < 0.8 } })
        local ns = Load()
        w.ScanAll(ns)
        for _, line in ipairs(ns.Shown()) do
            offered = offered + 1
            assert(line.cost < line.value, "a line at a loss")
            assert(line.cost <= money - ns.db.reserve, "a line past the reserve")
            assert(line.slots <= free - ns.db.keepFree, "a line past the free slots")
            assert(ns.db.maxPrice == 0 or line.cost <= ns.db.maxPrice, "a line past the most per line")
            assert(line.gain * 100 >= line.cost * ns.db.minPct, "a line under the least percent")
            local it = items[line.id]
            assert(ns.Wanted(it[2], it[5], ns.db), "a line the filters leave out")
            if line.kind == "i" then
                for _, l in ipairs(lots[line.id]) do if l[1] == line.auction then assert(not l[4], "an own lot") end end
            end
        end
    end
    assert(offered > 50, "the rounds offered too little: " .. offered)
end)

W.finish()
