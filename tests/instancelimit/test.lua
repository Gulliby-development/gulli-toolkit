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

test("a secret system or error line is left alone", function()
    Fake({})
    local ns = Load()
    W.Go("The Deadmines", "party", 36)
    W.Go("Westfall", "none", 0)
    local limit = ns.db.limit
    issecretvalue = function(v) return type(v) == "string" end
    W.Fire("CHAT_MSG_SYSTEM", "The Deadmines has been reset.")
    W.Fire("UI_ERROR_MESSAGE", 0, TRANSFER_ABORT_TOO_MANY_INSTANCES or "You have entered too many instances recently.")
    issecretvalue = nil
    W.Go("The Deadmines", "party", 36)
    eq(#ns.db.entries, 1, "a secret reset line does not reopen the dungeon")
    eq(ns.db.limit, limit, "a secret refusal does not change the limit")
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

test("there is no day limit; an entry older than a day leaves the list", function()
    Fake({ now = 0 })
    local ns = Load()
    W.now = 100; W.Go("A", "party", 1); W.Go("Out", "none", 0)
    W.now = 4000; W.Go("B", "party", 2); W.Go("Out", "none", 0)
    W.now = 8000
    local s = ns.Status()
    eq(s.leftHour, 5); eq(s.left, 5); eq(s.wait, 0)
    eq(s.leftDay, nil)
    W.now = 100 + 86400
    ns.Status()
    eq(#ns.db.entries, 1, "an entry older than a day is dropped")
end)

test("settings of older versions go, and a limit typed by hand is 5 again", function()
    Fake({ db = { limit = 9, dayLimit = 12, warnDayAt = 2, fromExit = true, entries = {}, open = {} } })
    local ns = Load()
    eq(ns.db.limit, 5)
    eq(ns.db.dayLimit, nil); eq(ns.db.warnDayAt, nil); eq(ns.db.fromExit, nil); eq(ns.db.confirmed, nil)
    -- a limit the game showed stays
    Fake({ db = { limit = 3, confirmed = true, entries = {}, open = {} } })
    eq(Load().db.limit, 3)
    -- and the hour counts from the entry, whatever fromExit said
    Fake({ now = 1000, db = { fromExit = true, entries = {}, open = {} } })
    ns = Load()
    W.Go("A", "party", 1)
    W.now = 1000 + 1800; W.Go("Out", "none", 0)
    W.now = 1000 + 3700
    eq(ns.Status().hour, 0)
end)

test("the slots of the hour: the one that frees first, then the free ones", function()
    Fake({ now = 10000 })
    local ns = Load()
    W.Go("A", "party", 1); W.Go("Out", "none", 0)
    W.now = 10900; W.Go("B", "party", 2); W.Go("Out", "none", 0)
    W.now = 11800
    local slots = ns.Slots()
    eq(#slots, 5)
    eq(slots[1].name, "A"); eq(slots[1].free, 1800); eq(slots[1].frac, 0.5); eq(slots[1].first, true)
    eq(slots[2].name, "B"); eq(slots[2].free, 2700); eq(slots[2].first, false)
    eq(slots[3].isFree, true); eq(slots[5].isFree, true)
    eq(ns.Status().nextFree, 1800)
    ns.ShowPage(1)
    W.now = 10000 + 3600
    eq(ns.Slots()[1].name, "B", "A freed its slot")
    eq(ns.Slots()[2].isFree, true)
end)

test("a refusal from the game sets the limit to what we counted", function()
    Fake({})
    local ns = Load()
    W.Go("A", "party", 1); W.Go("Out", "none", 0)
    W.Go("B", "party", 2); W.Go("Out", "none", 0)
    W.Go("C", "party", 3); W.Go("Out", "none", 0)
    W.Fire("UI_ERROR_MESSAGE", 0, "You have entered too many instances recently.")
    eq(ns.db.limit, 3)
    eq(#ns.Slots(), 3, "a slot per entry the game allows")
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

test("run stats: time, XP with a level up, money and kills, and a summary", function()
    Fake({ now = 1000 })
    local ns = Load()
    W.xp, W.xpMax, W.money = 900, 1000, 500
    W.Go("The Deadmines", "party", 36)
    W.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Defias Pirate dies, you gain 80 experience.")
    W.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Mr. Smite dies, you gain 120 experience. (+40 exp Rested bonus)")
    W.Fire("CHAT_MSG_COMBAT_XP_GAIN", "You gain 2400 experience.") -- a quest, no kill
    W.xp, W.money = 150, 2500
    W.now = 1000 + 1500
    W.Go("Westfall", "none", 0)
    local e = ns.db.entries[1]
    eq(e.secs, 1500); eq(e.xp, 250); eq(e.money, 2000); eq(e.kills, 2)
    assert(W.Printed("The Deadmines:"), "the summary")
    local S = ns.Skin
    local line = ns.RunText(e)
    local plain = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "·")
    eq(plain, "25:00  ·  250 XP  ·  20s  ·  2 kills")
    -- every part has its own colour, and silver does not look like plain text
    for _, c in ipairs({ S.TIME, S.XP, S.SILVER, S.KILLS }) do
        assert(line:find(S.Hex(c), 1, true), "a coloured part")
    end
    local d = math.abs(S.SILVER[1] - S.TEXT[1]) + math.abs(S.SILVER[2] - S.TEXT[2]) + math.abs(S.SILVER[3] - S.TEXT[3])
    assert(d > 0.2, "silver stands out from the text")
end)

test("more entries than the limit raise it", function()
    Fake({ db = { limit = 2, limitFixed = true, entries = {}, open = {} } })
    local ns = Load()
    for i = 1, 3 do W.Go("D" .. i, "party", i); W.Go("Out", "none", 0) end
    eq(ns.db.limit, 3, "we got in three times")
    eq(ns.Status().limit, 3)
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
    ns.db.entries[2].out, ns.db.entries[2].secs = W.now - 5, 600
    ns.db.entries[3].out, ns.db.entries[3].secs = W.now - 5, 1200
    local day = ns.ListItems()
    eq(#day, 6)
    eq(day[1].header, true); eq(day[1].char, "Zed"); eq(day[1].count, 2)
    eq(day[4].char, "Ann"); eq(day[4].count, 2)
    local plain = ns.RunsHint(day):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "·")
    eq(plain, "Runs: 4  ·  15:00 on average")
    eq(ns.RunsHint({}), "")
    ns.ShowPage(1)
    ns.ShowPage(2)
end)

test("counter modes", function()
    Fake({})
    local ns = Load()
    local s = ns.Status()
    eq(ns.BadgeShown(s), false, "hidden by default")
    ns.db.badgeMode = "ALWAYS"
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
    W.group = false
    eq(ns.BadgeShown(s), false)
    eq(ns.db.badgeLocked, nil, "no lock of its own")
end)

test("the counter starts hidden, is hidden once after the update, and the hub brings back its mode", function()
    Fake({ db = { badgeMode = "GROUP", badgeLocked = false, entries = {}, open = {} } })
    local ns = Load()
    eq(ns.db.badgeMode, "HIDDEN", "hidden once")
    eq(ns.db.badgeLocked, nil)
    eq(ns.BadgeOn(), false)
    ns.SetBadgeOn(true)
    eq(ns.db.badgeMode, "GROUP", "the mode the player had")
    ns.SetBadgeOn(false)
    eq(ns.db.badgeMode, "HIDDEN")
    ns.SetBadgeOn(true)
    eq(ns.db.badgeMode, "GROUP")
    Fake({})
    ns = Load()
    eq(ns.db.badgeMode, "HIDDEN", "a new player starts without the counter")
    ns.SetBadgeOn(true)
    eq(ns.db.badgeMode, "ALWAYS")
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

test("the group shares what is left; every member shows", function()
    Fake({})
    local ns = Load()
    W.group = true
    W.Fire("CHAT_MSG_ADDON", "GulliIL", "STATE\t3\t20\t0", "PARTY", "Bob-Realm")
    W.Fire("CHAT_MSG_ADDON", "GulliIL", "STATE\t0\t20\t600", "PARTY", "Ann")
    W.Fire("CHAT_MSG_ADDON", "Other", "STATE\t0\t0\t0", "PARTY", "Cid")
    W.members = { { "Bob" }, { "Dan" } }
    local list = ns.GroupList()
    eq(#list, 3)
    eq(list[1].name, "Ann"); eq(list[1].left, 0); eq(list[1].wait, 600)
    eq(list[2].name, "Bob"); eq(list[2].left, 3)
    eq(list[3].name, "Dan"); eq(list[3].none, true, "in the group, without the addon")
    ns.ShowPage(1)
    W.now = W.now + 600
    eq(ns.GroupList()[1].left, 1, "that wait is over")
    W.addon = {}
    W.Fire("CHAT_MSG_ADDON", "GulliIL", "HELLO", "PARTY", "Cid")
    eq(W.addon[1], "PARTY:STATE\t5\t99\t0", "the old message keeps its day field")
end)

test("a group member whose name the game hides is left out", function()
    Fake({})
    local ns = Load()
    local hidden = {}
    issecretvalue = function(v) return v == hidden end
    W.group = true
    W.members = { { hidden }, { "Bob" } }
    local list = ns.GroupList()
    eq(#list, 1); eq(list[1].name, "Bob")
    issecretvalue = nil
end)

test("the hub gets a summary, a move and a reset", function()
    Fake({})
    local got
    GulliToolkit = { Register = function(info) got = info end }
    local ns = Load()
    eq(got.summary(), "5 of 5 entries left")
    local _, _, stat = got.summary()
    eq(stat.pips[1], 5, "the hub's tile: a pip per entry left")
    eq(stat.pips[2], 5)
    eq(stat.tone, "good")
    ns.db.badgeScale, ns.db.limit = 150, 3
    got.reset()
    eq(ns.db.badgeScale, 100); eq(ns.db.limit, 5)
    got.move(true); eq(ns.moving, true)
end)

test("the Settings page takes the footer's space when the footer hides", function()
    Fake({})
    local ns = Load()
    local f = ns.Window()
    local y
    rawset(f.body, "SetPoint", function(_, p, _, oy) if p == "BOTTOMRIGHT" then y = oy end end)
    f.footer:Hide(); f.footer._OnHide(f.footer)
    local hidden = y
    f.footer:Show(); f.footer._OnShow(f.footer)
    assert(hidden and y and hidden < y, "body reaches lower without the footer")
end)

test("the hub's session card: the runs of this character since the login", function()
    Fake({ now = 1000, db = { entries = { { t = 100, name = "Old", map = 9, char = "Tester", out = 400, secs = 300 } }, open = {} } })
    local got
    GulliToolkit = { Register = function(m) got = m end }
    local ns = Load()
    eq(got.session(), nil, "nothing before the first loading screen")
    W.Go("Out", "none", 0)
    eq(got.session(), nil, "a run before the login is not this session's")
    W.now = 1100; W.Go("Maraudon", "party", 1)
    W.now = 1100 + 2400; W.Go("Out", "none", 0)
    W.now = 4000; W.Go("Uldaman", "party", 2)
    table.insert(ns.db.entries, { t = 3900, name = "Alt's run", map = 3, char = "Other", out = 3950, secs = 50 })
    W.now = 4600
    local s = got.session()
    eq(s.value, 2)
    eq(s.unit, "Dungeons")
    eq(s.line, "40:00 on average, now Uldaman 10:00")
    eq(#s.bars, 2)
    eq(s.bars[2], 600, "the run that still goes on grows")
    eq(s.at, 4600, "inside a dungeon it gains right now")
    eq(s.tile.value, 2)
    eq(s.tip.rows[1][1], "Maraudon")
    eq(s.tip.rows[1][2], "40:00")
    W.now = 5000; W.Go("Out", "none", 0)
    W.now = 9000
    eq(got.session().at, 5000, "outside: when the last run ended")
    -- a /reload keeps the session, a login starts a new one
    W.Fire("PLAYER_ENTERING_WORLD", false, true)
    eq(got.session().value, 2)
    W.Fire("PLAYER_LOGOUT")
    W.Fire("PLAYER_ENTERING_WORLD", true, false)
    eq(got.session().value, 2, "a quick relog keeps the session")
    W.now = W.now + ns.Skin.RELOG_KEEP + 1
    W.Fire("PLAYER_ENTERING_WORLD", true, false)
    eq(got.session(), nil)
    GulliToolkit = nil
end)

test("a /reload or going out and in again keeps the run's kills, XP and money", function()
    Fake({ now = 1000 })
    local ns = Load()
    W.xp, W.xpMax, W.money = 100, 1000, 500
    W.Go("The Deadmines", "party", 36)
    W.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Defias Pirate dies, you gain 80 experience.")
    W.xp, W.money = 180, 600
    -- a /reload inside: the addon loads again with the saved entries
    local db = ns.db
    Fake({ now = 1200, db = db })
    ns = Load()
    W.xp, W.xpMax, W.money = 180, 1000, 600
    W.Go("The Deadmines", "party", 36)
    W.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Defias Miner dies, you gain 70 experience.")
    W.xp, W.money = 250, 700
    eq(#ns.db.entries, 1)
    eq(ns.db.entries[1].kills, 2, "the kill before the reload still counts")
    -- out and in again: the same copy, the run goes on
    W.now = 1500; W.Go("Westfall", "none", 0)
    local e = ns.db.entries[1]
    eq(e.kills, 2); eq(e.xp, 150); eq(e.money, 200)
    W.xp, W.money = 300, 650 -- spent on repairs outside, not part of the run
    W.now = 1600; W.Go("The Deadmines", "party", 36)
    eq(#ns.db.entries, 1)
    W.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Mr. Smite dies, you gain 120 experience.")
    W.xp, W.money = 420, 850
    W.now = 2000; W.Go("Westfall", "none", 0)
    eq(e.kills, 3, "kills from both visits")
    eq(e.xp, 270, "XP from both visits")
    eq(e.money, 400, "money from both visits")
    eq(e.secs, 1000)
end)

test("every language has every key, with the same placeholders", function()
    Fake({})
    W.CheckLocales(Load())
end)

W.finish()
