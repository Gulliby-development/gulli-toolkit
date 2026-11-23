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

-- Full normal bags (the herb bag keeps free slots) and a loot window with the given items.
local LOOT_ITEMS = {}
for k, v in pairs(ITEMS) do LOOT_ITEMS[k] = v end
LOOT_ITEMS[9] = { name = "Fur Cap", quality = 2, price = 80, classID = 4 }
LOOT_ITEMS[10] = { name = "Wolf Claw", quality = 2, price = 90, classID = 4 }
local function fullBags()
    local b = bags()
    b[1].slots[3] = { id = 2, count = 1 }
    b[1].slots[4] = { id = 3, count = 1 }
    return b
end
local function loot(list)
    GetNumLootItems = function() return #list end
    GetLootSlotLink = function(i) return "|Hitem:" .. list[i][1] .. ":0|h[x]|h" end
    GetLootSlotInfo = function(i) return 1, "x", list[i][2] or 1 end
end

test("two loot items that fit no stack need two slots, and the notice frees both", function()
    Fake({ bags = fullBags(), items = LOOT_ITEMS })
    local ns = Load()
    loot({ { 9 }, { 10 } })
    eq(ns.Space(), 0)
    eq(ns.LootShort(), 2)
    local items = ns.FreeItems(2)
    eq(#items, 2, "two items offered")
    W.Fire("UI_ERROR_MESSAGE", 3, "Inventory is full.")
    -- One delete per click: the first click frees one slot, the loot still misses one.
    W.Click()
    local _, deleted = ns.FreeSome(items)
    eq(deleted, 1)
    eq(ns.Space(), 1)
    eq(ns.LootShort(), 1, "one more slot missing")
    W.Click()
    ns.FreeSome(ns.FreeItems(ns.LootShort()))
    eq(ns.LootShort(), 0, "now everything fits")
    eq(#W.deleted, 2)
    ns.UpdatePopup()
    ns.LootClosed()
end)

test("loot that joins its own stacks or a special bag needs no slot", function()
    Fake({ bags = fullBags(), items = LOOT_ITEMS })
    local ns = Load()
    C_Item.GetItemFamily = function(id) if id == 8 then return 32 end return 0 end
    loot({ { 1, 5 }, { 4, 25 }, { 8, 10 } })
    eq(ns.LootShort(), 0, "fang onto 3/20, cloth into 32 free, herbs into the herb bag")
    loot({ { 1, 30 } })
    eq(ns.LootShort(), 1, "17 fit the stack, 13 need a new one")
    GetNumLootItems = function() return 0 end
    eq(ns.LootShort(), nil, "no loot window")
    eq(#ns.FreeItems(), 1)
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

-- A bag item button as the game's bags make it.
local function slotButton(bag, slot)
    local b = W.stub()
    rawset(b, "GetBagID", function() return bag end)
    rawset(b, "GetID", function() return slot end)
    return b
end
local function tipFor(owner)
    rawset(GameTooltip, "_owner", owner)
    return GameTooltip
end

test("disenchant: the key is bound only while a bag item that can go shows its tooltip", function()
    local ns = deFake(true, { deKey = "N" })
    eq(W.Bound("N"), nil, "nothing bound before")
    local lines = ns.DisenchantTip(61, tipFor(slotButton(0, 2)))
    eq(W.Bound("N"), "GulliBagSpaceDisenchant")
    local b = ns.DisenchantButton()
    eq(b:GetAttribute("type"), "spell"); eq(b:GetAttribute("spell"), 13262)
    eq(b:GetAttribute("target-bag"), 0); eq(b:GetAttribute("target-slot"), 2)
    assert(lines[1] and lines[1].left:match("^N"), "the line names the key: " .. tostring(lines[1] and lines[1].left))
    ns.DisenchantTip(62, tipFor(slotButton(0, 3)))
    eq(W.Bound("N"), nil, "a white cap lets go of the key")
    ns.DisenchantTip(61, tipFor(slotButton(0, 2)))
    ns.HideDisenchant()
    eq(W.Bound("N"), nil, "the tooltip hid")
    GulliToolkit = nil
end)

test("disenchant: no key set, no binding", function()
    local ns = deFake()
    eq(#ns.DisenchantTip(61, tipFor(slotButton(0, 2))), 0)
    eq(ns.Armed(), nil)
    GulliToolkit = nil
end)

test("disenchant: a fight lets go first, and nothing is bound in one", function()
    local ns = deFake(true, { deKey = "N" })
    ns.DisenchantTip(61, tipFor(slotButton(0, 2)))
    W.Fire("PLAYER_REGEN_DISABLED")
    eq(W.Bound("N"), nil, "let go before the lockdown")
    W.combat = true
    ns.DisenchantTip(61, tipFor(slotButton(0, 2)))
    eq(W.Bound("N"), nil, "never bound in a fight")
    GulliToolkit = nil
end)

test("disenchant: the item leaving its slot lets go of the key", function()
    local ns = deFake(true, { deKey = "N" })
    ns.DisenchantTip(61, tipFor(slotButton(0, 2)))
    W.bags[0].slots[2] = nil
    W.Fire("BAG_UPDATE_DELAYED")
    eq(W.Bound("N"), nil)
    GulliToolkit = nil
end)

test("disenchant: a bag addon's button without a bag id is found by its bag frame", function()
    local ns = deFake(true, { deKey = "ALT-B" })
    local frame = W.stub()
    rawset(frame, "GetName", function() return "Baganator_BackpackViewFrame" end)
    local button = W.stub()
    rawset(button, "GetParent", function() return frame end)
    rawset(button, "GetName", function() return nil end)
    rawset(button, "GetBagID", nil)
    ns.DisenchantTip(60, tipFor(button))
    eq(W.Bound("ALT-B"), "GulliBagSpaceDisenchant")
    eq(ns.DisenchantButton():GetAttribute("target-slot"), 1)
    -- an item shown anywhere else (a link, the auction house) never arms the key
    local other = W.stub()
    rawset(other, "GetName", function() return "AuctionHouseFrame" end)
    rawset(other, "GetParent", function() return nil end)
    ns.DisenchantTip(60, tipFor(other))
    eq(W.Bound("ALT-B"), nil)
    GulliToolkit = nil
end)

test("disenchant: the key button takes a key or a mouse button, right-click clears", function()
    local ns = deFake()
    local b = ns.KeyButton(W.stub())
    b:GetScript("OnClick")(b, "LeftButton")
    eq(b:GetText(), ns.L.KEY_PRESS)
    W.alt = true
    b:GetScript("OnKeyDown")(b, "N")
    W.alt = false
    eq(ns.db.deKey, "ALT-N")
    b:GetScript("OnClick")(b, "LeftButton")
    b:GetScript("OnClick")(b, "Button4")
    eq(ns.db.deKey, "BUTTON4")
    b:GetScript("OnClick")(b, "RightButton")
    eq(ns.db.deKey, nil)
    eq(b:GetText(), ns.L.KEY_NONE)
    GulliToolkit = nil
end)

test("disenchant: the switch in the hub turns it off at once", function()
    local opts
    Fake({ bags = deBags(), items = DE_ITEMS, known = { [13262] = true }, db = { deKey = "N" } })
    GulliToolkit = { Register = function(m) opts = m.options end }
    local ns = Load()
    local sw
    for _, o in ipairs(opts) do if o.icon == ns.OPT_ICON.disenchant then sw = o end end
    assert(sw and sw.get(), "on by default")
    ns.DisenchantTip(60, tipFor(slotButton(0, 1)))
    eq(W.Bound("N"), "GulliBagSpaceDisenchant")
    sw.set(false)
    eq(W.Bound("N"), nil, "off lets go of the key")
    eq(ns.DisenchantTarget(0, 1), nil)
    GulliToolkit = nil
end)

-- The bank helper ------------------------------------------------------------------------------

local BANK_ITEMS = {
    [1] = { name = "Broken Fang", quality = 0, price = 5, maxStack = 20 },
    [4] = { name = "Linen Cloth", quality = 1, price = 10, maxStack = 20, classID = 7 },
    [7] = { name = "Quest Thing", quality = 1, price = 0, classID = 12 },
    [20] = { name = "Pattern: Shirt", quality = 1, price = 50, classID = 9 },
    [21] = { name = "Big Sword", quality = 2, price = 900, classID = 2, subclassID = 8, minLevel = 40 },
    [22] = { name = "Plate Boots", quality = 2, price = 400, classID = 4, subclassID = 4, minLevel = 10 },
    [23] = { name = "Light Hide", quality = 1, price = 5, maxStack = 20, classID = 15 },
    [24] = { name = "Bread", quality = 1, price = 1, maxStack = 20, classID = 0 },
    [25] = { name = "Super Potion", quality = 1, price = 20, maxStack = 5, classID = 0, minLevel = 45 },
    [26] = { name = "Copper Ore", quality = 1, price = 5, maxStack = 20, classID = 7 },
    [6948] = { name = "Hearthstone", quality = 1, price = 0, classID = 15 },
}
local function bankBags()
    return {
        [0] = { size = 12, slots = {
            [1] = { id = 1, count = 3 }, [2] = { id = 4, count = 10 }, [3] = { id = 7, count = 1 },
            [4] = { id = 20, count = 1 }, [5] = { id = 21, count = 1 }, [6] = { id = 22, count = 1 },
            [7] = { id = 23, count = 4 }, [8] = { id = 24, count = 5 }, [9] = { id = 25, count = 2 },
            [10] = { id = 6948, count = 1 }, [11] = { id = 26, count = 3 } } },
        [-1] = { size = 4, slots = { [1] = { id = 23, count = 10 } } },
    }
end
local function bankFake(spec)
    spec = spec or {}
    Fake({ bags = bankBags(), items = BANK_ITEMS, level = 30, db = spec.db })
    ItemLocation = { CreateFromBagAndSlot = function(_, b, s) return { b, s } end }
    C_Item.IsBound = function() return false end
    BANK_CONTAINER, NUM_BAG_SLOTS, NUM_TOTAL_EQUIPPED_BAG_SLOTS, NUM_BANKBAGSLOTS = -1, 4, 5, 0
end
local function whys(list)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = e.id .. ":" .. e.why end
    return table.concat(out, " ")
end

test("bank: the plan lists what belongs in the bank, by reason", function()
    bankFake()
    local ns = Load()
    eq(whys(ns.BankPlan()), "23:stack 26:goods 4:goods 20:recipe 21:later 25:later 22:alt")
end)

test("bank: never quest items, junk, the hearthstone, protected or restocked items", function()
    bankFake()
    GulliToolkit = { Register = function() end, IsProtected = function(id) return id == 20 end }
    GulliRestockCharDB = { list = { [26] = 20, ["best:food"] = 10 } }
    local ns = Load()
    local plan = whys(ns.BankPlan())
    for _, id in ipairs({ 1, 7, 6948, 20, 26, 24 }) do
        assert(not plan:find("%f[%d]" .. id .. ":"), id .. " must stay: " .. plan)
    end
    GulliToolkit, GulliRestockCharDB = nil, nil
end)

test("bank: off by default, shows at the bank with the switch", function()
    bankFake()
    local ns = Load()
    eq(ns.db.bank, false)
    W.Fire("BANKFRAME_OPENED")
    assert(not ns.BankFrame():IsShown(), "off: no list")
    ns.db.bank = true
    W.Fire("BANKFRAME_OPENED")
    assert(ns.BankFrame():IsShown(), "on: the list shows")
    eq(ns.BankFrame().title:GetText(), ns.L.BANK_TITLE:format(7))
    W.Fire("BANKFRAME_CLOSED")
    assert(not ns.BankFrame():IsShown(), "closes with the bank")
end)

test("bank: a click banks one, right-click never offers it again, Bank all steps", function()
    bankFake({ db = { bank = true } })
    local ns = Load()
    W.Fire("BANKFRAME_OPENED")
    local row = ns.BankFrame().rows[1]
    eq(row.entry.id, 23)
    row:GetScript("OnClick")(row, "LeftButton")
    eq(W.sold[1], 23, "moved into the bank")
    ns.RefreshBank()
    row = ns.BankFrame().rows[1]
    row:GetScript("OnClick")(row, "RightButton")
    assert(ns.db.bankNever[26], "kept out")
    eq(ns.BankPlan()[1].id, 4)
    ns.BankAll()
    for _ = 1, 10 do W.RunTimers() end
    eq(#ns.BankPlan(), 0, "everything banked")
    eq(#W.sold, 6)
    SlashCmdList.GULLIBAGSPACE("reset")
    eq(next(ns.db.bankNever), nil, "reset brings it back")
end)

test("bank: nothing moves away from the bank or in a fight", function()
    bankFake({ db = { bank = true } })
    local ns = Load()
    local e = ns.BankPlan()[1]
    eq(ns.BankOne(e), false, "bank closed")
    W.Fire("BANKFRAME_OPENED")
    W.combat = true
    eq(ns.BankOne(e), false, "in a fight")
    W.combat = false
    eq(ns.BankOne(e), true)
end)

test("the hub's Tweaks page gets rows on the window's own saved keys", function()
    Fake({})
    local reg
    GulliToolkit = { Register = function(t) reg = t end }
    local ns = Load()
    GulliToolkit = nil
    local GROUPS = { level = true, quests = true, combat = true, loot = true, people = true, ui = true, requests = true }
    assert(#reg.tweaks >= 1)
    local seen = {}
    for _, o in ipairs(reg.tweaks) do
        assert(GROUPS[o.group], "a group of the page for " .. o.key)
        assert(type(o.label) == "string" and o.icon, "label and icon for " .. o.key)
        assert(not seen[o.key], "one row per key"); seen[o.key] = true
        o.set(true); eq(ns.db[o.key], true, o.key .. " on"); eq(o.get(), true)
        o.set(false); eq(ns.db[o.key], false, o.key .. " off"); eq(o.get(), false)
    end
    assert(seen.bank)
end)

test("junk rules keep gear whose look the player still collects", function()
    Fake({})
    local ns = Load()
    local gray = { id = 77, quality = 0, price = 5, classID = 4, subclassID = 1 }
    eq(ns.J.Tier(gray), 1, "gray gear is junk")
    GulliToolkit = { KeepsAppearance = function(id) return id == 77 end }
    eq(ns.J.Tier(gray), nil, "a new look stays")
    eq(ns.J.Tier({ id = 78, quality = 0, price = 5, classID = 4, subclassID = 1 }), 1, "others still go")
    GulliToolkit = nil
end)

W.finish()
