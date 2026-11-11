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

W.finish()
