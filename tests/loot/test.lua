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

test("every roll goes into the log with its reason, newest first, at most 30, and who won", function()
    Fake({ rolls = { { 1, 0 }, { 2, 2, true }, { 3, 2 } } })
    local ns = Load()
    for i = 1, 3 do W.Fire("START_LOOT_ROLL", i) end
    eq(ns.db.log[1].reason, "ask"); eq(ns.db.log[2].reason, "bop"); eq(ns.db.log[3].reason, "quality")
    eq(ns.db.log[3].rule, "pass")
    local note
    GulliToolkit = { Notify = function(_, text) note = text end }
    W.Fire("CHAT_MSG_LOOT", "You won: |Hitem:3|h[Item]|h")
    eq(ns.db.log[1].winner, "Tester")
    assert(note and note:find("Item"), "the hub's Recent feed gets it")
    W.Fire("CHAT_MSG_LOOT", "Bob won: |Hitem:2|h[Item]|h")
    eq(ns.db.log[2].winner, "Bob")
    GulliToolkit = nil
    for i = 1, 40 do W.rolls[i] = { 100 + i, 0 }; W.Fire("START_LOOT_ROLL", i) end
    eq(#ns.db.log, 30)
end)

test("the main switch and Shift leave a roll to the player", function()
    Fake({ rolls = { { 1, 0 } } })
    local ns = Load()
    W.shift = true
    W.Fire("START_LOOT_ROLL", 1)
    eq(W.rolled[1], nil); eq(ns.db.log[1].reason, "shift")
    W.shift = false
    SlashCmdList.GULLILOOT("off")
    eq(ns.db.on, false)
    W.Fire("START_LOOT_ROLL", 1)
    eq(W.rolled[1], nil); eq(ns.db.log[1].reason, "off")
end)

test("rules by slash command and Alt-click; Ask on an item keeps a quality rule away", function()
    Fake({ rolls = { { 5, 0 } } })
    local ns = Load()
    SlashCmdList.GULLILOOT("ask |cff9d9d9d|Hitem:5::|h[Junk]|h|r")
    eq(ns.db.items[5], "ask")
    W.Fire("START_LOOT_ROLL", 1)
    eq(W.rolled[1], nil, "gray would be passed, but the item says ask")
    SlashCmdList.GULLILOOT("need 6")
    eq(ns.db.items[6], "need")
    ns.OnAltClick("|Hitem:6|h[x]|h")
    eq(ns.db.items[6], "greed", "Alt-click goes to the next rule")
    ns.OnAltClick("|Hitem:7|h[x]|h")
    eq(ns.db.items[7], "greed")
end)

test("type rules, where the rules apply, green you cannot use, upgrades", function()
    Fake({ rolls = { { 10, 2 }, { 11, 2, false, false }, { 12, 2 } },
           items = { [10] = { 9 }, [11] = { 4, "INVTYPE_CHEST", 30 }, [12] = { 4, "INVTYPE_CHEST", 30 } },
           worn = { [5] = 25 } })
    local ns = Load()
    ns.SetType(9, "pass")
    W.Fire("START_LOOT_ROLL", 1)
    eq(W.rolled[1], 0, "recipes: pass"); eq(ns.db.log[1].reason, "type")
    ns.SetPref("where", "raid")
    W.rolled = {}
    W.Fire("START_LOOT_ROLL", 1)
    eq(W.rolled[1], nil, "only in a raid")
    ns.SetPref("where", "always")
    ns.SetPref("greedUnusable", true)
    W.Fire("START_LOOT_ROLL", 2)
    eq(W.rolled[2], 2, "greed on green the class cannot use")
    ns.SetPref("needUpgrade", true)
    W.Fire("START_LOOT_ROLL", 3)
    eq(W.rolled[3], 1, "need: better than what is worn")
    W.worn[5] = 40
    W.rolled = {}
    W.Fire("START_LOOT_ROLL", 3)
    eq(W.rolled[3], nil, "not an upgrade: left to the player")
end)

test("/glt test tells what would happen, and chat lines come as one", function()
    Fake({ rolls = { { 20, 0 }, { 21, 0 } }, items = { [20] = { 15, nil, 5, 0 } } })
    local ns = Load()
    eq(ns.Test("20"), "|Hitem:20|h[Item20]|h: Pass (quality rule).")
    W.Fire("START_LOOT_ROLL", 1); W.Fire("START_LOOT_ROLL", 2)
    eq(#W.printed, 0)
    W.RunTimers()
    eq(#W.printed, 1)
    assert(W.printed[1]:find("Pass on ", 1, true), W.printed[1])
end)

test("fast loot takes every slot; the bind question is answered only alone", function()
    Fake({})
    local ns = Load()
    W.lootN = 3
    W.Fire("LOOT_READY")
    eq(#W.looted, 0, "off by default")
    ns.SetPref("fastLoot", true)
    W.Fire("LOOT_READY")
    eq(#W.looted, 3)
    ns.SetPref("soloConfirm", true)
    W.group = true
    eq(ns.OnBindConfirm(1), false)
    W.group = false
    eq(ns.OnBindConfirm(2), true); eq(W.confirmedSlot, 2)
end)

test("item rules are sorted by name and can be searched; the window has three pages", function()
    Fake({})
    local ns = Load()
    ns.SetItem(30, "greed"); ns.SetItem(4, "pass")
    eq(ns.Items()[1].id, 30, "Item30 before Item4 by name")
    eq(#ns.Items("item4"), 1)
    ns.Toggle()
    ns.Refresh()
end)

W.finish()
