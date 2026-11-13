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
    assert(W.printed[#W.printed]:find("sold 1 junk items for 15c", 1, true), W.printed[#W.printed])
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

test("the always-sell list: /gmc junk adds a white item, it sells, and protected items cannot join", function()
    Fake({ slots = { { 0, 1, 10, 1, 1 }, { 0, 2, 11, 1, 1 } }, prices = { [10] = 5, [11] = 7 } })
    local ns = Load()
    SlashCmdList.GULLIMERCHANT("junk item:10")
    eq(ns.db.junk[10], true)
    SlashCmdList.GULLIMERCHANT("junk 10")
    eq(ns.db.junk[10], nil, "a second time takes it off")
    SlashCmdList.GULLIMERCHANT("junk 10")
    GulliToolkit = { IsProtected = function(id) return id == 11 end }
    SlashCmdList.GULLIMERCHANT("junk 11")
    eq(ns.db.junk[11], nil)
    W.Fire("MERCHANT_SHOW")
    W.Drain()
    eq(#W.sold, 1); eq(W.sold[1], 10)
    GulliToolkit = nil
end)

test("both addons share the always-sell list", function()
    Fake({})
    local ns = Load()
    local other = {}
    ns.J.Attach(other)
    ns.J.SetAlways(42, true)
    eq(ns.db.junk[42], true); eq(other[42], true)
    eq(ns.J.IsAlways(42), true)
end)

test("bound gear the class cannot use sells only with its switch", function()
    -- A priest: plate (armour subclass 4) and an axe (weapon subclass 0) are no use; cloth is.
    local info = { [20] = { classID = 4, subclassID = 4, quality = 2 }, [21] = { classID = 2, subclassID = 0, quality = 1 },
                   [22] = { classID = 4, subclassID = 1, quality = 2 }, [23] = { classID = 4, subclassID = 4, quality = 2 } }
    local slots = { { 0, 1, 20, 1, 2 }, { 0, 2, 21, 1, 1 }, { 0, 3, 22, 1, 2 }, { 0, 4, 23, 1, 2 } }
    Fake({ slots = slots, info = info, prices = { [20] = 100, [21] = 50, [22] = 80, [23] = 90 },
           bound = { [1] = true, [2] = true, [3] = true } })
    local ns = Load()
    eq(#ns.Junk(), 0, "off by default")
    ns.db.unusable = true
    local junk = ns.Junk()
    eq(#junk, 2, "the unbound plate can still go to the auction house")
    eq(junk[1].id, 20); eq(junk[2].id, 21)
end)

test("an item sold by hand twice is suggested, and can be added or dismissed", function()
    Fake({ slots = { { 0, 1, 30, 1, 1 }, { 0, 2, 31, 1, 1 } }, prices = { [30] = 5, [31] = 5 } })
    local ns = Load()
    W.Fire("MERCHANT_SHOW")
    W.hooks.UseContainerItem(0, 1)
    eq(#ns.Suggestions(), 0)
    W.hooks.UseContainerItem(0, 1)
    W.hooks.UseContainerItem(0, 2)
    W.hooks.UseContainerItem(0, 2)
    eq(#ns.Suggestions(), 2)
    ns.J.SetAlways(30, true)
    ns.Dismiss(31)
    eq(#ns.Suggestions(), 0)
    W.Fire("MERCHANT_CLOSED")
    W.hooks.UseContainerItem(0, 1)
    eq(ns.db.manual[31], nil, "away from a vendor a right-click uses the item")
end)

test("an unticked row is kept this session", function()
    Fake({ slots = { { 0, 1, 10, 1, 0 }, { 0, 2, 11, 1, 0 } }, prices = { [10] = 5, [11] = 5 } })
    local ns = Load()
    ns.skip[11] = true
    local sell = ns.ToSell()
    eq(#sell, 1); eq(sell[1].id, 10)
    ns.Toggle()
    local rows = ns.Rows()
    eq(#rows, 2)
end)

test("one chat line per visit", function()
    Fake({ slots = { { 0, 1, 10, 1, 0 } }, prices = { [10] = 5 }, repair = { 100 } })
    Load()
    W.Fire("MERCHANT_SHOW")
    W.Drain()
    eq(#W.printed, 1)
    assert(W.printed[1]:find("sold 1 junk", 1, true) and W.printed[1]:find("repaired", 1, true), W.printed[1])
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

test("the hub gets a summary, a reset and a tip on each switch", function()
    Fake({})
    local reg
    GulliToolkit = { Register = function(t) reg = t end }
    local ns = Load()
    GulliToolkit = nil
    for _, o in ipairs(reg.options) do assert(o.tip, "a tip for " .. o.label) end
    ns.db.sell = false
    reg.reset()
    eq(ns.db.sell, true)
    ns.session.sold, ns.session.value = 3, 120
    assert(reg.summary():find("3", 1, true))
end)

test("paused from the hub it sells nothing until it is started again", function()
    Fake({ slots = { { 0, 1, 10, 3, 0 } }, prices = { [10] = 5 } })
    local reg
    GulliToolkit = { Register = function(t) reg = t end }
    Load()
    GulliToolkit = nil
    reg.pause(true)
    W.Fire("MERCHANT_SHOW")
    W.RunTimers()
    eq(#W.sold, 0, "paused")
    W.Fire("MERCHANT_CLOSED")
    reg.pause(false)
    W.Fire("MERCHANT_SHOW")
    W.RunTimers()
    eq(#W.sold, 1, "started again")
end)

test("bag coins read each slot once, and a burst of updates redraws them once", function()
    local slots = {}
    for s = 1, 16 do slots[s] = { 0, s, 100 + s, 1, s % 2 == 0 and 0 or 1 } end
    local prices = {}
    for s = 1, 16 do prices[100 + s] = 5 end
    Fake({ slots = slots, prices = prices })
    local ns = Load()
    local buttons = {}
    for s = 1, 16 do
        local b = { GetBagID = function() return 0 end, GetID = function() return s end }
        b.CreateTexture = function()
            return { SetTexture = function() end, SetSize = function() end, SetPoint = function() end,
                     SetShown = function(_, v) b.shown = v end }
        end
        buttons[s] = b
    end
    ContainerFrame1 = { IsShown = function() return true end,
                        EnumerateValidItems = function() return ipairs(buttons) end }
    local reads, get = 0, C_Container.GetContainerItemInfo
    C_Container.GetContainerItemInfo = function(...) reads = reads + 1; return get(...) end
    ns.J.UpdateCoins()
    assert(reads <= 2 * 16, "slot reads: " .. reads)
    assert(buttons[2].shown and not buttons[1].shown, "coin on the gray item only")
    W.Drain()
    for _ = 1, 5 do W.Fire("BAG_UPDATE_DELAYED") end
    if W.hooks.ContainerFrame_Update then W.hooks.ContainerFrame_Update() end
    eq(#W.timers, 1, "one redraw queued")
    reads = 0
    W.RunTimers()
    assert(reads > 0 and reads <= 2 * 16, "redraw reads: " .. reads)
    ContainerFrame1 = nil
end)

W.finish()
