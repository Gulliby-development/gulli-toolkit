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
    assert(W.Printed("No dungeon entries left"), "a warning at the limit")
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
    eq(ns.db.confirmed, true, "the game confirmed it")
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

test("an entry free again: one alert in chat, the hub and a sound", function()
    Fake({ now = 10000 })
    local sounds, notes = 0, {}
    PlaySound = function() sounds = sounds + 1 end
    GulliToolkit = { Notify = function(_, t) notes[#notes + 1] = t end }
    local ns = Load()
    for i = 1, 5 do W.now = 10000 + i; W.Go("D" .. i, "party", i); W.Go("Out", "none", 0) end
    ns.Tick()
    eq(sounds, 1, "the warning at the limit rings")
    W.now = 10001 + 3600
    ns.Tick()
    eq(sounds, 2)
    eq(notes[#notes], "A dungeon entry is free again.")
    ns.Tick()
    eq(sounds, 2, "only once")
end)

test("which limit blocks, hour or day", function()
    Fake({ now = 0, db = { limit = 5, dayLimit = 2, entries = {}, open = {} } })
    local ns = Load()
    W.now = 100; W.Go("A", "party", 1); W.Go("Out", "none", 0)
    W.now = 200; W.Go("B", "party", 2); W.Go("Out", "none", 0)
    eq(ns.Status().by, "DAY")
    ns.db.dayLimit, ns.db.limit = 30, 2
    local s = ns.Status()
    eq(s.by, "HOUR"); eq(s.wait, 100 + 3600 - 200)
    ns.db.limit = 5
    eq(ns.Status().by, nil)
end)

test("count from the exit: the hour starts when the player leaves", function()
    Fake({ now = 1000, db = { fromExit = true, entries = {}, open = {} } })
    local ns = Load()
    W.Go("A", "party", 1)
    W.now = 1000 + 1800
    W.Go("Out", "none", 0)
    eq(ns.db.entries[1].out, 2800)
    W.now = 1000 + 3700
    eq(ns.Status().hour, 1, "an hour after the entry but not after the exit")
    ns.db.fromExit = false
    eq(ns.Status().hour, 0)
end)

test("run stats: time, XP with a level up, money and kills, and a summary", function()
    Fake({ now = 1000 })
    local ns = Load()
    W.xp, W.xpMax, W.money = 900, 1000, 500
    W.Go("The Deadmines", "party", 36)
    W.Fire("CHAT_MSG_COMBAT_XP_GAIN", "x"); W.Fire("CHAT_MSG_COMBAT_XP_GAIN", "x")
    W.xp, W.money = 150, 2500
    W.now = 1000 + 1500
    W.Go("Westfall", "none", 0)
    local e = ns.db.entries[1]
    eq(e.secs, 1500); eq(e.xp, 250); eq(e.money, 2000); eq(e.kills, 2)
    assert(W.Printed("The Deadmines: 25:00, 250 XP"), "the summary")
end)

test("learning raises the limit too, and the limit is an estimate until confirmed", function()
    Fake({ db = { limit = 2, entries = {}, open = {} } })
    local ns = Load()
    eq(ns.LimitText(5), "≈5")
    for i = 1, 3 do W.Go("D" .. i, "party", i); W.Go("Out", "none", 0) end
    eq(ns.db.limit, 3, "we got in three times")
    ns.DefaultLimits()
    eq(ns.db.limit, 5); eq(ns.db.dayLimit, 30)
end)

test("early warnings at the chosen count", function()
    Fake({ db = { warnAt = 3, entries = {}, open = {} } })
    Load()
    W.Go("A", "party", 1); W.Go("Out", "none", 0)
    assert(not W.Printed("entries left this hour"))
    W.Go("B", "party", 2)
    assert(W.Printed("3 dungeon entries left this hour"))
end)

test("the list is grouped by character, mine first", function()
    Fake({ name = "Zed" })
    local ns = Load()
    ns.db.entries = { { t = W.now - 10, name = "A", char = "Ann" }, { t = W.now - 20, name = "B", char = "Zed" },
                      { t = W.now - 30, name = "C", char = "Zed" }, { t = W.now - 7200, name = "D", char = "Ann" } }
    local hour = ns.ListItems("HOUR")
    eq(#hour, 5)
    eq(hour[1].header, true); eq(hour[1].char, "Zed"); eq(hour[1].count, 2)
    eq(hour[4].char, "Ann")
    eq(#ns.ListItems("DAY"), 6)
    ns.ShowPage(1, "DAY")
    ns.ShowPage(2)
end)

test("counter modes", function()
    Fake({})
    local ns = Load()
    local s = ns.Status()
    eq(ns.BadgeShown(s), true)
    ns.db.badgeMode = "HIDDEN"
    eq(ns.BadgeShown(s), false)
    ns.MoveBadge(true)
    eq(ns.BadgeShown(s), true, "/gulli move shows it")
    ns.MoveBadge(false)
    ns.db.badgeMode = "GROUP"
    eq(ns.BadgeShown(s), false)
    W.group = true
    eq(ns.BadgeShown(s), true)
end)

test("the old counter switch becomes a mode", function()
    Fake({ db = { badge = false, entries = {}, open = {} } })
    local ns = Load()
    eq(ns.db.badgeMode, "HIDDEN"); eq(ns.db.badge, nil)
end)

test("a reset tells the group and the leader's reset reaches us", function()
    Fake({})
    local ns = Load()
    W.group, W.leader = true, true
    W.Go("The Deadmines", "party", 36); W.Go("Westfall", "none", 0)
    eq(ns.Reset(), true)
    W.Fire("CHAT_MSG_SYSTEM", "The Deadmines has been reset.")
    eq(W.said[1], "PARTY:Dungeons reset: The Deadmines.")
    eq(W.addon[#W.addon], "PARTY:RESET\tThe Deadmines")
    W.Go("The Deadmines", "party", 36); W.Go("Westfall", "none", 0)
    eq(#ns.db.entries, 2)
    W.Fire("CHAT_MSG_ADDON", "GulliIL", "RESET\tThe Deadmines", "PARTY", "Bob-Realm")
    W.Go("The Deadmines", "party", 36)
    eq(#ns.db.entries, 3, "someone else's reset opens it again for us")
    ns.db.sync = false
    W.Go("Westfall", "none", 0)
    W.Fire("CHAT_MSG_ADDON", "GulliIL", "RESET\tThe Deadmines", "PARTY", "Bob-Realm")
    W.Go("The Deadmines", "party", 36)
    eq(#ns.db.entries, 3, "the switch stops it")
end)

test("Reset asks again while members are inside", function()
    Fake({})
    local ns = Load()
    W.group, W.leader, W.members = true, true, { { "Bob", true }, { "Ann", false } }
    eq(ns.Reset(), "ask")
    eq(ns.insideNames[1], "Bob")
    eq(W.resets, 0)
    eq(ns.Reset(), true, "the second press resets")
    eq(W.resets, 1)
end)

test("the group shares what is left; the lowest shows", function()
    Fake({})
    local ns = Load()
    W.group = true
    W.Fire("CHAT_MSG_ADDON", "GulliIL", "STATE\t3\t20\t0", "PARTY", "Bob-Realm")
    W.Fire("CHAT_MSG_ADDON", "GulliIL", "STATE\t0\t20\t600", "PARTY", "Ann")
    W.Fire("CHAT_MSG_ADDON", "Other", "STATE\t0\t0\t0", "PARTY", "Cid")
    local low = ns.GroupLow()
    eq(low.name, "Ann"); eq(low.left, 0); eq(low.wait, 600)
    W.now = W.now + 600
    eq(ns.GroupLow().left, 1, "that wait is over")
    W.addon = {}
    W.Fire("CHAT_MSG_ADDON", "GulliIL", "HELLO", "PARTY", "Cid")
    eq(W.addon[1], "PARTY:STATE\t5\t30\t0")
end)

test("the hub gets a summary, a move and a reset", function()
    Fake({})
    local got
    GulliToolkit = { Register = function(info) got = info end }
    local ns = Load()
    eq(got.summary(), "5 of 5 entries left")
    ns.db.badgeScale, ns.db.limit = 150, 3
    got.reset()
    eq(ns.db.badgeScale, 100); eq(ns.db.limit, 5)
    got.move(true); eq(ns.moving, true)
end)

test("every language has every key, with the same placeholders", function()
    Fake({})
    W.CheckLocales(Load())
end)

W.finish()
