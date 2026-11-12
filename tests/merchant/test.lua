-- Run from the repository root: lua5.1 tests/merchant/test.lua
local W = dofile("tests/merchant/wow.lua")
local test, eq = W.test, W.eq

test("every language has every text", function()
    Fake({})
    W.CheckLocales(Load())
end)

test("at a vendor the gray items with a price are sold, nothing else", function()
    Fake({ slots = { { 0, 1, 10, 3, 0 }, { 0, 2, 11, 1, 1 }, { 0, 3, 12, 1, 0, true }, { 0, 4, 13, 1, 0 } },
           prices = { [10] = 5, [11] = 100, [13] = 0 } })
    Load()
    W.Fire("MERCHANT_SHOW")
    W.RunTimers()
    eq(#W.sold, 1)
    eq(W.sold[1], 10)
    assert(W.printed[#W.printed]:find("sold 1 gray items for 15c", 1, true), W.printed[#W.printed])
end)

test("protected items are never sold", function()
    Fake({ slots = { { 0, 1, 10, 1, 0 }, { 0, 2, 20, 1, 0 } }, prices = { [10] = 5, [20] = 5 } })
    Load()
    GulliToolkit = { IsProtected = function(id) return id == 20 end }
    W.Fire("MERCHANT_SHOW")
    W.RunTimers()
    eq(#W.sold, 1)
    eq(W.sold[1], 10)
end)

test("many items are sold in steps of twelve", function()
    local slots = {}
    for i = 1, 16 do slots[i] = { 0, i, 100 + i, 1, 0 } end
    local prices = {}
    for i = 1, 16 do prices[100 + i] = 1 end
    Fake({ slots = slots, prices = prices })
    Load()
    W.Fire("MERCHANT_SHOW")
    eq(#W.sold, 12)
    local t = W.timers; W.timers = {}
    for _, fn in ipairs(t) do fn() end
    eq(#W.sold, 16)
end)

test("closing the vendor stops the selling", function()
    local slots = {}
    for i = 1, 14 do slots[i] = { 0, i, 100 + i, 1, 0 } end
    local prices = {}
    for i = 1, 14 do prices[100 + i] = 1 end
    Fake({ slots = slots, prices = prices })
    Load()
    W.Fire("MERCHANT_SHOW")
    W.Fire("MERCHANT_CLOSED")
    W.RunTimers()
    eq(#W.sold, 12)
end)

test("repairs from the guild bank when allowed, else with own money", function()
    Fake({ repair = { 5000, guild = true } })
    Load()
    W.Fire("MERCHANT_SHOW")
    eq(W.repaired, "guild")
    Fake({ repair = { 5000, guild = true, limit = 100 } })
    Load()
    W.Fire("MERCHANT_SHOW")
    eq(W.repaired, "own", "the guild limit is too low")
    eq(W.money, 95000)
end)

test("switches and Shift turn it off", function()
    Fake({ slots = { { 0, 1, 10, 1, 0 } }, prices = { [10] = 5 }, repair = { 100 },
           db = { sell = false, repair = false } })
    Load()
    W.Fire("MERCHANT_SHOW")
    W.RunTimers()
    eq(#W.sold, 0); eq(W.repaired, nil)
    Fake({ slots = { { 0, 1, 10, 1, 0 } }, prices = { [10] = 5 }, repair = { 100 } })
    Load()
    W.shift = true
    W.Fire("MERCHANT_SHOW")
    eq(#W.sold, 0); eq(W.repaired, nil)
end)

test("short of money: sells the junk first, then repairs with what it brought", function()
    Fake({ slots = { { 0, 1, 10, 1, 0 } }, prices = { [10] = 600 }, repair = { 500 }, money = 100 })
    local use = C_Container.UseContainerItem
    C_Container.UseContainerItem = function(b, s) use(b, s); W.money = W.money + 600 end
    Load()
    W.Fire("MERCHANT_SHOW")
    eq(W.repaired, nil, "not before the sale")
    W.Drain()
    eq(W.repaired, "own")
    eq(W.money, 200)
    for _, line in ipairs(W.printed) do assert(not line:find("not enough money", 1, true), line) end
end)

test("selling more than 12 says only the last 12 come back; the safe switch sells 12", function()
    local slots, prices = {}, {}
    for i = 1, 15 do slots[i] = { 0, i, 100 + i, 1, 0 }; prices[100 + i] = 1 end
    Fake({ slots = slots, prices = prices })
    Load()
    W.Fire("MERCHANT_SHOW")
    W.Drain()
    eq(#W.sold, 15)
    assert(W.printed[#W.printed]:find("last 12", 1, true), W.printed[#W.printed])
    slots = {}
    for i = 1, 15 do slots[i] = { 0, i, 100 + i, 1, 0 } end
    Fake({ slots = slots, prices = prices, db = { safe = true } })
    Load()
    W.Fire("MERCHANT_SHOW")
    W.Drain()
    eq(#W.sold, 12)
    assert(not W.printed[#W.printed]:find("last 12", 1, true))
end)

test("no money, no repair", function()
    Fake({ repair = { 5000 }, money = 10 })
    Load()
    W.Fire("MERCHANT_SHOW")
    eq(W.repaired, nil)
    assert(W.printed[#W.printed]:find("not enough money", 1, true))
end)

test("the window shows the junk value", function()
    Fake({ slots = { { 0, 1, 10, 2, 0 } }, prices = { [10] = 12345 } })
    local ns = Load()
    ns.Toggle()
    local _, total = ns.Junk()
    eq(total, 24690)
    eq(ns.Money(total), "2g 46s 90c")
end)

W.finish()
