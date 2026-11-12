-- Run from the repository root: lua5.1 tests/tooltip/test.lua
local W = dofile("tests/tooltip/wow.lua")
local test, eq = W.test, W.eq

local LOG = {
    { 100, "Wolves", objectives = { { type = "item", text = "Wolf Pelt: 3/10", numFulfilled = 3, numRequired = 10 } } },
    { 101, "Kill boars", objectives = { { type = "monster", text = "Boar slain: 1/5", numFulfilled = 1, numRequired = 5 } } },
    { 102, "Done", objectives = { { type = "item", text = "Wolf Pelt: 5/5", numFulfilled = 5, numRequired = 5, finished = true } } },
}

test("every language has every text", function()
    Fake({})
    W.CheckLocales(Load())
end)

test("a stack item shows the full stack price; a single item does not", function()
    Fake({ items = { [1] = { "Linen", 20, 13 }, [2] = { "Sword", 1, 500 } } })
    Load()
    eq(W.HoverItem(1)[1], "Stack of 20=2s 60c")
    eq(#W.HoverItem(2), 0)
end)

test("an item a quest still needs shows the quest and the count", function()
    Fake({ items = { [7] = { "Wolf Pelt", 20, 0 } }, log = LOG })
    Load()
    local lines = W.HoverItem(7)
    eq(#lines, 1)
    eq(lines[1], "Quest: Wolves=3/10")
end)

test("the quest lines follow the log", function()
    Fake({ items = { [7] = { "Wolf Pelt", 20, 0 } }, log = LOG })
    Load()
    eq(#W.HoverItem(7), 1)
    W.log = {}
    W.Fire("QUEST_LOG_UPDATE")
    eq(#W.HoverItem(7), 0)
end)

test("ids on items and NPCs only when switched on", function()
    Fake({ items = { [2] = { "Sword", 1, 500 } } })
    local ns = Load()
    eq(#W.HoverUnit("Creature-0-1-2-3-299-0000"), 0)
    ns.db.id = true
    eq(W.HoverItem(2)[1], "Item ID=2")
    eq(W.HoverUnit("Creature-0-1-2-3-299-0000")[1], "NPC ID=299")
    eq(#W.HoverUnit("Player-1-00000001"), 0)
    issecretvalue = function() return true end
    eq(#W.HoverUnit("Creature-0-1-2-3-299-0000"), 0, "a secret guid is skipped")
    ns.Toggle()
end)

test("the count turns green once the bags hold enough", function()
    Fake({ items = { [7] = { "Wolf Pelt", 20, 0 } }, log = LOG })
    local ns = Load()
    local l = ns.ItemLines(7)[1]
    eq(l[4][1], 1, "3/10 stays white")
    ns.QuestNeeds("Wolf Pelt")[1].have = 10
    l = ns.ItemLines(7)[1]
    eq(l[4][1], 0.42, "10/10 is green")
end)

test("the whole name must match: Wolf Pelt is not Large Wolf Pelt", function()
    Fake({ items = { [7] = { "Wolf Pelt", 20, 0 }, [8] = { "Large Wolf Pelt", 20, 0 } }, log = {
        { 100, "Wolves", objectives = { { type = "item", text = "Large Wolf Pelt: 1/4", numFulfilled = 1, numRequired = 4 } } },
    } })
    Load()
    eq(#W.HoverItem(7), 0)
    eq(W.HoverItem(8)[1], "Quest: Wolves=1/4")
end)

test("a count in front of the name is read too", function()
    Fake({})
    local ns = Load()
    eq(ns.ObjectiveName("3/10 Wolf Pelt"), "Wolf Pelt")
    eq(ns.ObjectiveName("Wolf Pelt: 3/10"), "Wolf Pelt")
end)

test("a protected item says so, only with the core and the switch", function()
    Fake({ items = { [2] = { "Sword", 1, 500 } } })
    local ns = Load()
    eq(#W.HoverItem(2), 0)
    GulliToolkit = { IsProtected = function(id) return id == 2 end }
    eq(W.HoverItem(2)[1], "Protected in Gulli Toolkit=")
    ns.db.protect = false
    eq(#W.HoverItem(2), 0)
end)

test("the auction price comes from Auctionator when it is there", function()
    Fake({ items = { [2] = { "Sword", 1, 500 } } })
    local ns = Load()
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(caller, id)
        assert(caller == "Gulli-Tooltip"); return id == 2 and 12345 or nil end } } }
    eq(W.HoverItem(2)[1], "Auction=1g 23s 45c")
    ns.db.auction = false
    eq(#W.HoverItem(2), 0)
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() error("broken") end } } }
    ns.db.auction = true
    eq(#W.HoverItem(2), 0, "an error in Auctionator shows nothing")
    Auctionator = nil
end)

test("other characters' bags and banks come from Gulli Chores", function()
    Fake({ items = { [7] = { "Wolf Pelt", 20, 0 } } })
    Load()
    GulliChoresDB = { chars = {
        ["Tester-Realm"] = { name = "Tester", items = { [7] = 4 }, bank = { [7] = 6 } },
        ["Alt-Realm"] = { name = "Alt", items = { [7] = 3 }, bank = { [7] = 2 } },
        ["Bob-Realm"] = { name = "Bob", items = { [7] = 1 } },
        ["Empty-Realm"] = { name = "Empty", items = {} },
    } }
    local lines = W.HoverItem(7)
    eq(#lines, 3)
    eq(lines[1], "Your bank=6")
    eq(lines[2], "Alt=5 (bank 2)")
    eq(lines[3], "Bob=1")
    GulliChoresDB = nil
    eq(#W.HoverItem(7), 0, "no Chores, no lines")
end)

test("a reagent of a learned recipe names the profession", function()
    Fake({ items = { [7] = { "Wolf Pelt", 20, 0 } } })
    Load()
    GulliCraftProfitCharDB = { profs = {
        Leatherworking = { recipes = { { learned = true, r = { [7] = 2 } } } },
        Tailoring = { recipes = { { learned = false, r = { [7] = 1 } } } },
    } }
    eq(W.HoverItem(7)[1], "Reagent for: Leatherworking=")
    GulliCraftProfitCharDB = nil
end)

test("kill objectives on NPCs only when switched on, by the start of the name", function()
    Fake({ log = LOG })
    local ns = Load()
    local guid = "Creature-0-1-2-3-113-0000"
    eq(#W.HoverUnit(guid, "Boar"), 0)
    ns.db.mobs = true
    eq(W.HoverUnit(guid, "Boar")[1], "Quest: Kill boars=1/5")
    eq(#W.HoverUnit(guid, "Boa"), 0, "part of a word is no match")
    eq(#W.HoverUnit("Player-1-00000001", "Boar"), 0, "players are not mobs")
end)

test("with Shift mode prices and ids wait for Shift", function()
    Fake({ items = { [1] = { "Linen", 20, 13 } } })
    local ns = Load()
    ns.db.id, ns.db.shift = true, true
    local down = false
    IsShiftKeyDown = function() return down end
    eq(#W.HoverItem(1), 0)
    down = true
    eq(#W.HoverItem(1), 2)
    IsShiftKeyDown = nil
end)

test("spell ids under the id switch", function()
    Fake({})
    local ns = Load()
    eq(#W.HoverSpell(139), 0)
    ns.db.id = true
    eq(W.HoverSpell(139)[1], "Spell ID=139")
end)

test("summary, reset and the hub options", function()
    Fake({})
    local reg
    GulliToolkit = { Register = function(info) reg = info end }
    local ns = Load()
    eq(reg.key, "Tooltip")
    eq(#reg.options, 6)
    eq(reg.summary(), "6 of 8 tooltip lines on")
    reg.options[1].set(false)
    eq(ns.db.price, false)
    eq(reg.summary(), "5 of 8 tooltip lines on")
    reg.reset()
    eq(ns.db.price, true)
    eq(ns.db.mobs, false)
end)

test("the window builds and the example follows the switches", function()
    Fake({})
    local ns = Load()
    local f = ns.Window()
    assert(f, "no window")
    f:Show()
    ns.Refresh()
    ns.Set("id", true)
    ns.Toggle()
end)

W.finish()
