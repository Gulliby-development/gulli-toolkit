-- Run from the repository root: lua5.1 tests/instancelimit/test.lua
local W = dofile("tests/instancelimit/wow.lua")
local test, eq = W.test, W.eq

test("entering a dungeon counts once; going out and in again does not", function()
    Fake({})
    local ns = Load()
    W.Go("The Deadmines", "party", 36)
    W.Go("Westfall", "none", 0)
    W.Go("The Deadmines", "party", 36)
    eq(#ns.db.entries, 1)
    eq(ns.Status().leftHour, 4)
    W.Go("Westfall", "none", 0)
    W.Go("Wailing Caverns", "party", 43)
    eq(ns.Status().leftHour, 3)
    W.Go("Stormwind", "scenario", 0)
    eq(#ns.db.entries, 2, "only dungeons and raids count")
end)

test("a reset or a new group makes the same dungeon count again", function()
    Fake({})
    local ns = Load()
    W.Go("The Deadmines", "party", 36)
    W.Go("Westfall", "none", 0)
    W.Fire("CHAT_MSG_SYSTEM", "The Deadmines has been reset.")
    W.Go("The Deadmines", "party", 36)
    eq(#ns.db.entries, 2)
    W.Go("Westfall", "none", 0)
    W.Fire("GROUP_LEFT")
    W.Go("The Deadmines", "party", 36)
    eq(#ns.db.entries, 3)
end)

test("the same dungeon counts again after an hour", function()
    Fake({ now = 1000 })
    local ns = Load()
    W.Go("A", "party", 1); W.Go("Out", "none", 0)
    W.now = 1000 + 3600
    W.Go("A", "party", 1)
    eq(#ns.db.entries, 2)
end)

test("the next entry frees an hour after the oldest one that keeps us at the limit", function()
    Fake({ now = 10000 })
    local ns = Load()
    for i = 1, 5 do
        W.now = 10000 + i * 60
        W.Go("Dungeon " .. i, "party", i)
        W.Go("Outside", "none", 0)
    end
    W.now = 10000 + 600
    local s = ns.Status()
    eq(s.leftHour, 0)
    eq(s.wait, 10060 + 3600 - 10600)
    assert(W.printed[#W.printed]:find("No dungeon entries left", 1, true), "a warning at the limit")
    W.now = 10060 + 3600
    eq(ns.Status().leftHour, 1)
    eq(ns.Status().wait, 0)
end)

test("the day limit and old entries", function()
    Fake({ now = 0, db = { limit = 5, dayLimit = 2, entries = {}, open = {} } })
    local ns = Load()
    W.now = 100; W.Go("A", "party", 1); W.Go("Out", "none", 0)
    W.now = 4000; W.Go("B", "party", 2); W.Go("Out", "none", 0)
    W.now = 8000
    local s = ns.Status()
    eq(s.leftDay, 0)
    eq(s.wait, 100 + 86400 - 8000)
    W.now = 100 + 86400
    eq(ns.Status().leftDay, 1)
    eq(#ns.db.entries, 1, "an entry older than a day is dropped")
end)

test("a refusal from the game sets the limit to what we counted", function()
    Fake({})
    local ns = Load()
    W.Go("A", "party", 1); W.Go("Out", "none", 0)
    W.Go("B", "party", 2); W.Go("Out", "none", 0)
    W.Go("C", "party", 3); W.Go("Out", "none", 0)
    W.Fire("UI_ERROR_MESSAGE", 0, "You have entered too many instances recently.")
    eq(ns.db.limit, 3)
end)

test("reset only outside, as leader or alone", function()
    Fake({})
    local ns = Load()
    eq(ns.CanReset(), true)
    W.group = true
    eq(ns.CanReset(), false)
    W.leader = true
    ns.Reset()
    eq(W.resets, 1)
    W.Go("A", "party", 1)
    eq(ns.CanReset(), false)
end)

test("the window, the counter and /gil status", function()
    Fake({})
    local ns = Load()
    SlashCmdList.GULLIINSTANCELIMIT("")
    ns.Refresh()
    SlashCmdList.GULLIINSTANCELIMIT("status")
    assert(W.printed[#W.printed]:find("5 of 5", 1, true))
    eq(ns.Clock(3725), "1:02:05")
    eq(ns.Clock(65), "1:05")
end)

test("every language has every key, with the same placeholders", function()
    Fake({})
    W.CheckLocales(Load())
end)

W.done()
