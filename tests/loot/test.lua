-- Run from the repository root: lua5.1 tests/loot/test.lua
local W = dofile("tests/loot/wow.lua")
local test, eq = W.test, W.eq

test("every language has every text", function()
    Fake({})
    W.CheckLocales(Load())
end)

test("by default gray is passed and everything else is left to the player", function()
    Fake({ rolls = { { 1, 0 }, { 2, 1 }, { 3, 2 } } })
    Load()
    for i = 1, 3 do W.Fire("START_LOOT_ROLL", i) end
    eq(W.rolled[1], 0)
    eq(W.rolled[2], nil); eq(W.rolled[3], nil)
end)

test("quality rules greed or pass; bind on pickup always stays with the player", function()
    Fake({ rolls = { { 1, 2 }, { 2, 2, true } }, db = { quality = { [2] = "greed" } } })
    Load()
    W.Fire("START_LOOT_ROLL", 1); W.Fire("START_LOOT_ROLL", 2)
    eq(W.rolled[1], 2)
    eq(W.rolled[2], nil)
end)

test("an item rule wins, even on bind on pickup, and its confirmation is answered", function()
    Fake({ rolls = { { 7, 3, true } }, db = { items = { [7] = "need" } } })
    local ns = Load()
    W.Fire("START_LOOT_ROLL", 1)
    eq(W.rolled[1], 1)
    W.Fire("CONFIRM_LOOT_ROLL", 1, 1)
    eq(W.confirmed[1], 1)
    eq(ns.OnConfirm(2, 1), false, "a roll we did not make is not confirmed")
end)

test("need falls back to greed; no greed leaves it to the player", function()
    Fake({ rolls = { { 7, 2, false, false }, { 8, 2, false, false, false } }, db = { items = { [7] = "need", [8] = "greed" } } })
    Load()
    W.Fire("START_LOOT_ROLL", 1); W.Fire("START_LOOT_ROLL", 2)
    eq(W.rolled[1], 2)
    eq(W.rolled[2], nil)
end)

test("protected items are not passed by a quality rule", function()
    Fake({ rolls = { { 9, 0 } } })
    Load()
    GulliToolkit = { IsProtected = function(id) return id == 9 end }
    W.Fire("START_LOOT_ROLL", 1)
    eq(W.rolled[1], nil)
end)

test("dropping an item adds a greed rule", function()
    Fake({})
    local ns = Load()
    ns.Toggle()
    W.cursor = 4306
    for _, fr in ipairs(W.frames) do
        local fn = rawget(fr, "_OnReceiveDrag")
        if fn then fn(fr) end
    end
    eq(ns.db.items[4306], "greed")
    eq(#ns.Items(), 1)
end)

W.finish()
