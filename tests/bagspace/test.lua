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
    eq(deleted, 1, "one delete per click"); eq(sold, 0)
    eq(W.deleted[1], 1)
    eq(#ns.Leftover(plan), 1, "the next one waits for the next click")
    W.Click()
    sold, deleted = ns.Run(plan)
    eq(deleted, 1); eq(W.deleted[2], 2)
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
    W.Click()
    ns.Run(plan)
    W.Click()
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
    local _, _, stat = reg.summary()
    eq(stat.ready, "BAGS", "the hub's Ready card shows the same: the tile gives way")
end)

-- Random bags: whatever space is asked for, quest items, keys, the hearthstone, protected items
-- and anything better than white are never offered.
test("random bags: never offer what must stay", function()
    math.randomseed(20261114)
    local offered = 0
    for round = 1, 300 do
        local items, list = {}, {}
        for id = 1, 30 do
            local it = { name = "Item " .. id, quality = math.random(0, 3), price = math.random(0, 3) * 10,
                         classID = ({ 0, 2, 4, 7, 12, 13, 15 })[math.random(7)], maxStack = math.random() < 0.5 and 20 or 1 }
            items[id] = it
        end
        items[6948] = { name = "Hearthstone", quality = 1, price = 0, classID = 15 }
        local slots = { [1] = { id = 6948, count = 1 } }
        for slot = 2, 16 do
            if math.random() < 0.8 then slots[slot] = { id = math.random(30), count = 1 } end
        end
        local protectedId = math.random(30)
        Fake({ bags = { [0] = { size = 16, slots = slots } }, items = items })
        GulliToolkit = { IsProtected = function(id) return id == protectedId end }
        local ok, err = pcall(function()
            local ns = Load()
            local plan = ns.Plan(math.random(1, 16))
            offered = offered + #plan.items
            for _, it in ipairs(plan.items) do
                local id = tonumber(it.name:match("^Item (%d+)$"))
                assert(id, "offered " .. it.name)
                local def = items[id]
                assert(id ~= protectedId, "offered a protected item")
                assert(def.classID ~= 12 and def.classID ~= 13, "offered a quest item or a key: " .. it.name)
                assert(def.quality <= 1, "offered " .. it.name .. " of quality " .. def.quality)
            end
        end)
        GulliToolkit = nil
        if not ok then error("round " .. round .. ": " .. tostring(err), 0) end
    end
    assert(offered > 100, "the rounds offered too little to prove anything: " .. offered)
end)

test("a junk item's tooltip line goes into the Gulli block and warns", function()
    Fake({ bags = bags(), items = ITEMS })
    local ns = Load()
    ns.J.InstallMarks({ JUNK_TIP = "junk: sold at the vendor", ALWAYS_TIP = "on your \"always sell\" list" })
    ns.J.SetAlways(5, true)
    local l = ns.J.TipLines(5)[1]
    assert(l, "no line for a junk item")
    eq(l.group, "state"); eq(l.color, ns.Skin.WARN)
    assert(l.icon and l.left:match("^%u"), "an icon and a capital: " .. l.left)
    ns.J.SetAlways(5, false)
end)

-- Disenchant on a middle click ---------------------------------------------------------------

local DE_ITEMS = {
    [60] = { name = "Green Boots", quality = 2, price = 300, classID = 4 },
    [61] = { name = "Blue Sword", quality = 3, price = 900, classID = 2 },
    [62] = { name = "White Cap", quality = 1, price = 20, classID = 4 },
    [63] = { name = "Gray Rag", quality = 0, price = 2, classID = 4 },
    [64] = { name = "Green Shirt", quality = 2, price = 50, classID = 4, equipLoc = "INVTYPE_BODY" },
    [65] = { name = "Green Potion", quality = 2, price = 50, classID = 0 },
    [66] = { name = "Set Gloves", quality = 2, price = 50, classID = 4 },
    [67] = { name = "Kept Ring", quality = 3, price = 50, classID = 4 },
    [68] = { name = "Legend Axe", quality = 5, price = 50, classID = 2 },
}
local function deBags()
    local slots = {}
    for i = 0, 8 do slots[i + 1] = { id = 60 + i, count = 1 } end
    return { [0] = { size = 9, slots = slots } }
end
local function deFake(known, db)
    Fake({ bags = deBags(), items = DE_ITEMS, sets = { [0] = { [7] = true } },
           known = known == false and {} or { [13262] = true }, db = db })
    GulliToolkit = { IsProtected = function(id) return id == 67 end }
    local ns = Load()
    W.Fire("PLAYER_LOGIN")
    return ns
end

test("disenchant: only green, blue and purple gear, never what the junk rules keep", function()
    local ns = deFake()
    local yes = {}
    for slot = 1, 9 do
        local it = ns.DisenchantTarget(0, slot)
        if it then yes[#yes + 1] = it.name end
    end
    eq(table.concat(yes, ","), "Green Boots,Blue Sword")
    eq(ns.DisenchantTarget(-1, 1), nil, "not the bank")
    GulliToolkit = nil
end)

test("disenchant: nothing without Enchanting, with the switch off or in combat", function()
    local ns = deFake(false)
    eq(ns.DisenchantTarget(0, 1), nil, "no Enchanting")
    ns = deFake(true, { disenchant = false })
    eq(ns.DisenchantTarget(0, 1), nil, "switch off")
    ns = deFake()
    W.combat = true
    eq(ns.DisenchantTarget(0, 1), nil, "in combat")
    GulliToolkit = nil
end)

test("disenchant: the secure button lies over the slot and takes only the middle button", function()
    local ns = deFake()
    local slotButton = W.stub()
    ns.OnBagTip(slotButton, 0, 2)
    local b = ns.DisenchantButton()
    assert(b and b:IsShown(), "the button shows over a blue sword")
    eq(b:GetAttribute("type3"), "spell"); eq(b:GetAttribute("spell3"), 13262)
    eq(b:GetAttribute("target-bag3"), 0); eq(b:GetAttribute("target-slot3"), 2)
    eq(b:GetAttribute("type"), nil, "left and right clicks do nothing of ours")
    eq(b:GetAttribute("type1"), nil); eq(b:GetAttribute("type2"), nil)
    ns.OnBagTip(slotButton, 0, 3)
    assert(not b:IsShown(), "a white cap hides it")
    ns.OnBagTip(slotButton, 0, 1)
    assert(b:IsShown())
    W.Fire("PLAYER_REGEN_DISABLED")
    assert(not b:IsShown(), "it hides before a fight")
    ns.OnBagTip(slotButton, 0, 1)
    W.combat = true
    W.Fire("PLAYER_REGEN_DISABLED")
    assert(b:IsShown(), "a secure frame is never hidden in combat lockdown")
    W.combat = false
    -- the item left the slot (disenchanted): the button goes
    W.bags[0].slots[1] = nil
    b:GetScript("OnUpdate")(b)
    assert(not b:IsShown(), "an empty slot hides it")
    GulliToolkit = nil
end)

test("disenchant: the switch in the hub turns it off at once", function()
    local opts
    Fake({ bags = deBags(), items = DE_ITEMS, known = { [13262] = true } })
    GulliToolkit = { Register = function(m) opts = m.options end }
    local ns = Load()
    local sw
    for _, o in ipairs(opts) do if o.icon == ns.OPT_ICON.disenchant then sw = o end end
    assert(sw and sw.get(), "on by default")
    local owner = W.stub()
    ns.OnBagTip(owner, 0, 1)
    assert(ns.DisenchantButton():IsShown())
    sw.set(false)
    assert(not ns.DisenchantButton():IsShown(), "off hides the button")
    eq(ns.DisenchantTarget(0, 1), nil)
    GulliToolkit = nil
end)

test("disenchant: a client that cannot pass clicks through gets no button", function()
    Fake({ bags = deBags(), items = DE_ITEMS, known = { [13262] = true } })
    local make = CreateFrame
    CreateFrame = function(...)
        local f = make(...)
        rawset(f, "SetPassThroughButtons", false)
        return f
    end
    local ns = Load()
    ns.OnBagTip(W.stub(), 0, 1)
    eq(ns.DisenchantButton(), nil)
end)

test("disenchant: the tooltip line names the middle click", function()
    local ns = deFake()
    local owner = W.stub()
    ns.OnBagTip(owner, 0, 2)
    local tip = W.stub()
    rawset(tip, "_owner", owner)
    local l = ns.DisenchantTip(61, tip)[1]
    assert(l and l.left:match("^%u"), "a line with a capital")
    eq(l.group, "note")
    eq(#ns.DisenchantTip(60, tip), 0, "another item")
    GulliToolkit = nil
end)

W.finish()
