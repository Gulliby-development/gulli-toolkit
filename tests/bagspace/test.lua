-- Run from the repository root: lua5.1 tests/bagspace/test.lua
local W = dofile("tests/bagspace/wow.lua")
local test, eq = W.test, W.eq

local ITEMS = {
    [1] = { name = "Broken Fang", quality = 0, price = 5, maxStack = 20 },
    [2] = { name = "Torn Hide", quality = 0, price = 50 },
    [3] = { name = "Worn Sword", quality = 1, price = 30, classID = 2 },
    [4] = { name = "Linen Cloth", quality = 1, price = 10, maxStack = 20, classID = 7 },
    [5] = { name = "Bread", quality = 1, price = 1, maxStack = 20, classID = 0 },
    [6] = { name = "Green Ring", quality = 2, price = 500, classID = 4 },
    [7] = { name = "Quest Thing", quality = 1, price = 0, classID = 12 },
    [6948] = { name = "Hearthstone", quality = 1, price = 0, classID = 15 },
    [8] = { name = "Herb", quality = 1, price = 2, maxStack = 20, classID = 7 },
}
local function bags()
    return {
        [0] = { size = 8, slots = {
            [1] = { id = 1, count = 3 }, [2] = { id = 2, count = 1 }, [3] = { id = 3, count = 1 },
            [4] = { id = 4, count = 15 }, [5] = { id = 4, count = 8 }, [6] = { id = 6, count = 1 },
            [7] = { id = 7, count = 1 }, [8] = { id = 6948, count = 1 } } },
        [1] = { size = 4, slots = { [1] = { id = 4, count = 5 }, [2] = { id = 5, count = 2 } } },
        [2] = { size = 4, family = 32, slots = { [1] = { id = 8, count = 3 } } },
    }
end

test("space counts normal bags only", function()
    Fake({ bags = bags(), items = ITEMS })
    local ns = Load()
    local free, total = ns.Space()
    eq(free, 2); eq(total, 12)
end)

test("merges fill the fullest stack from the emptiest", function()
    Fake({ bags = bags(), items = ITEMS })
    local ns = Load()
    local moves, freed = ns.Merges(ns.Items())
    eq(freed, 1, "28 cloth fit in two stacks of 20")
    eq(moves[1].from.slot, 1); eq(moves[1].from.bag, 1, "the 5 goes first")
    eq(moves[1].n, 5)
end)

test("the plan: grays always, white gear while short, other whites unticked; never quest items or better", function()
    Fake({ bags = bags(), items = ITEMS })
    local ns = Load()
    local plan = ns.Plan(7)
    local names = {}
    for _, it in ipairs(plan.items) do names[#names + 1] = it.name .. (it.checked and "+" or "-") end
    eq(table.concat(names, ","), "Broken Fang+,Torn Hide+,Worn Sword+,Bread-,Linen Cloth-,Linen Cloth-,Linen Cloth-")
    eq(#ns.Plan(6).items, 3, "with enough slots, no suggestions")
    local slots, value = ns.Summary(plan)
    eq(slots, 4, "1 merge + 3 items")
    eq(value, 15 + 50 + 30)
end)

test("white gear is left alone when the grays are enough", function()
    Fake({ bags = bags(), items = ITEMS })
    local ns = Load()
    local plan = ns.Plan(3)
    for _, it in ipairs(plan.items) do assert(it.name ~= "Worn Sword", "the sword is not needed") end
end)

test("protected items are never offered", function()
    Fake({ bags = bags(), items = ITEMS })
    local ns = Load()
    GulliToolkit = { IsProtected = function(id) return id == 2 end }
    local plan = ns.Plan(6)
    for _, it in ipairs(plan.items) do assert(it.name ~= "Torn Hide") end
    GulliToolkit = nil
end)

test("OK deletes away from a vendor, sells at one, then merges stacks", function()
    Fake({ bags = bags(), items = ITEMS })
    local ns = Load()
    local plan = ns.Plan(6)
    plan.items[3].checked = false
    local sold, deleted = ns.Run(plan)
    eq(deleted, 2); eq(sold, 0)
    eq(W.deleted[1], 1); eq(W.deleted[2], 2)
    eq(W.bags[0].slots[3].id, 3, "the unticked sword stays")
    while #W.timers > 0 do W.RunTimers() end
    eq(W.bags[1].slots[1], nil, "the 5 cloth went into another stack")
    eq(W.bags[0].slots[4].count + W.bags[0].slots[5].count, 28)

    Fake({ bags = bags(), items = ITEMS })
    ns = Load()
    W.Fire("MERCHANT_SHOW")
    sold, deleted = ns.Run(ns.Plan(3))
    while #W.timers > 0 do W.RunTimers() end
    eq(sold, 2); eq(deleted, 0); eq(#W.sold, 2)
    eq(#W.deleted, 0)
end)

test("profession tools, fishing poles and equipment set items are never offered", function()
    local items = {
        [2901] = { name = "Mining Pick", quality = 1, price = 10, classID = 2 },
        [50] = { name = "Odd Pole", quality = 1, price = 10, classID = 2, subclassID = 20 },
        [51] = { name = "Set Helm", quality = 1, price = 10, classID = 4 },
        [52] = { name = "Old Axe", quality = 1, price = 10, classID = 2 },
    }
    Fake({ items = items, sets = { [0] = { [3] = true } }, bags = { [0] = { size = 4, slots = {
        [1] = { id = 2901, count = 1 }, [2] = { id = 50, count = 1 }, [3] = { id = 51, count = 1 },
        [4] = { id = 52, count = 1 } } } } })
    local ns = Load()
    local plan = ns.Plan(10)
    eq(#plan.items, 1)
    eq(plan.items[1].name, "Old Axe")
end)

test("a vendor sells in steps of 12; more than 12 says only the last 12 come back", function()
    local items, slots = {}, {}
    for i = 1, 15 do items[100 + i] = { name = "Junk" .. i, quality = 0, price = 1 }; slots[i] = { id = 100 + i, count = 1 } end
    Fake({ items = items, bags = { [0] = { size = 16, slots = slots } } })
    local ns = Load()
    W.Fire("MERCHANT_SHOW")
    local plan = ns.Plan(1)
    eq(ns.ToSell(plan), 15)
    eq(ns.Run(plan), 15)
    eq(#W.sold, 12, "the first step")
    W.RunTimers()
    eq(#W.sold, 15)
    eq(#ns.Leftover(plan), 0)
end)

test("what the game did not delete is offered again", function()
    Fake({ bags = bags(), items = ITEMS })
    local ns = Load()
    local plan = ns.Plan(6)
    W.refuse = { [2] = true }
    ns.Run(plan)
    local left = ns.Leftover(plan)
    eq(#left, 1)
    eq(left[1].name, "Torn Hide")
end)

test("an unticked item stays out of later plans until /gbs reset", function()
    Fake({ bags = bags(), items = ITEMS })
    local ns = Load()
    local plan = ns.Plan(6)
    eq(plan.items[1].name, "Broken Fang")
    ns.SetKept(plan.items[1], true)
    for _, it in ipairs(ns.Plan(6).items) do assert(it.name ~= "Broken Fang") end
    eq(ns.KeptCount(), 1)
    SlashCmdList.GULLIBAGSPACE("reset")
    eq(ns.KeptCount(), 0)
    eq(ns.Plan(6).items[1].name, "Broken Fang")
end)

test("always-sell items come first, ticked", function()
    Fake({ bags = bags(), items = ITEMS })
    local ns = Load()
    ns.J.SetAlways(5, true)
    local plan = ns.Plan(3)
    local bread
    for _, it in ipairs(plan.items) do if it.name == "Bread" then bread = it end end
    assert(bread and bread.checked and bread.tier == 1, "bread is junk now")
end)

test("an item worth more at the auction house is never ticked", function()
    Fake({ bags = bags(), items = ITEMS, ah = { [3] = 500 } })
    local ns = Load()
    local plan = ns.Plan(7)
    for _, it in ipairs(plan.items) do
        if it.name == "Worn Sword" then eq(it.checked, false); eq(it.ah, 500) end
    end
end)

test("Free 1 slot takes the cheapest junk in one click", function()
    Fake({ bags = bags(), items = ITEMS })
    local ns = Load()
    W.Fire("UI_ERROR_MESSAGE", 3, "Inventory is full.")
    local it = ns.FreeOne()
    eq(it.name, "Broken Fang")
    eq(W.deleted[1], 1)
end)

test("nothing in combat", function()
    Fake({ bags = bags(), items = ITEMS, combat = true })
    local ns = Load()
    local sold, deleted = ns.Run(ns.Plan(6))
    eq(sold + deleted, 0)
end)

test("a hint when the bags are almost full, once", function()
    Fake({ bags = bags(), items = ITEMS })
    Load()
    W.Fire("BAG_UPDATE_DELAYED")
    W.Fire("BAG_UPDATE_DELAYED")
    eq(#W.printed, 1)
end)

test("the window and /gbs <n>", function()
    Fake({ bags = bags(), items = ITEMS })
    local ns = Load()
    SlashCmdList.GULLIBAGSPACE("8")
    eq(ns.db.want, 8)
    ns.Refresh(true)
    eq(ns.Money(12345), "1g 23s 45c")
end)

test("every language has every key, with the same placeholders", function()
    Fake({})
    W.CheckLocales(Load())
end)

test("the hub gets a summary, a reset and a tip on each switch", function()
    Fake({})
    local reg
    GulliToolkit = { Register = function(t) reg = t end }
    local ns = Load()
    GulliToolkit = nil
    for _, o in ipairs(reg.options) do assert(o.tip, "a tip for " .. o.label) end
    ns.db.popup = false
    reg.reset()
    eq(ns.db.popup, true)
    assert(reg.summary())
end)

W.finish()
