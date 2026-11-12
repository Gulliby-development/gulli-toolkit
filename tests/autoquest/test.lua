-- Run from the repository root: lua5.1 tests/autoquest/test.lua
local W = dofile("tests/autoquest/wow.lua")
local test, eq = W.test, W.eq

test("every language has every text", function()
    Fake({})
    W.CheckLocales(Load())
end)

test("at an NPC a finished quest comes before a new one", function()
    Fake({ npc = { active = { { 5, false }, { 6, true } }, available = { { 7, false } } } })
    Load()
    W.Fire("GOSSIP_SHOW")
    eq(W.did[1], "active:6")
    W.npc.active = { { 5, false } }
    W.Fire("GOSSIP_SHOW")
    eq(W.did[2], "available:7")
    eq(#W.did, 2)
end)

test("gray quests are skipped unless the switch is off", function()
    Fake({ npc = { active = {}, available = { { 7, true } } } })
    local ns = Load()
    W.Fire("GOSSIP_SHOW")
    eq(#W.did, 0)
    ns.db.skipTrivial = false
    W.Fire("GOSSIP_SHOW")
    eq(W.did[1], "available:7")
end)

test("the old greeting window works too", function()
    Fake({ npc = { active = { { 1, true } }, available = {} } })
    Load()
    W.Fire("QUEST_GREETING")
    eq(W.did[1], "active#1")
end)

test("accept, complete and take the only reward", function()
    Fake({})
    Load()
    W.Fire("QUEST_DETAIL")
    W.Fire("QUEST_PROGRESS")
    W.choices = 1
    W.Fire("QUEST_COMPLETE")
    eq(table.concat(W.did, ","), "accept,complete,reward:1")
end)

test("a choice of rewards is left to the player, with a hint", function()
    Fake({})
    Load()
    W.choices, W.prices = 3, { [1] = 10, [2] = 500, [3] = 20 }
    W.Fire("QUEST_COMPLETE")
    eq(#W.did, 0)
    assert(W.printed[#W.printed]:find("item:2", 1, true))
end)

test("a quest that asks for gold or is not ready is not handed in", function()
    Fake({})
    Load()
    W.moneyToGet = 100
    W.Fire("QUEST_PROGRESS")
    W.moneyToGet, W.completable = 0, false
    W.Fire("QUEST_PROGRESS")
    eq(#W.did, 0)
end)

test("Shift and the switches stop it", function()
    Fake({ npc = { active = { { 6, true } }, available = { { 7, false } } } })
    local ns = Load()
    W.shift = true
    W.Fire("GOSSIP_SHOW"); W.Fire("QUEST_DETAIL")
    eq(#W.did, 0)
    W.shift = false
    ns.db.accept, ns.db.turnIn = false, false
    W.Fire("GOSSIP_SHOW"); W.Fire("QUEST_DETAIL"); W.Fire("QUEST_PROGRESS")
    eq(#W.did, 0)
    ns.Toggle()
end)

test("pause: a switch, a timer and a chosen key; no Shift needed", function()
    Fake({ npc = { active = { { 6, true } }, available = {} } })
    local ns = Load()
    ns.SetPaused(true)
    W.Fire("GOSSIP_SHOW"); eq(#W.did, 0)
    ns.SetPaused(false)
    ns.PauseFor(5)
    W.Fire("GOSSIP_SHOW"); eq(#W.did, 0, "paused for 5 minutes")
    W.now = W.now + 301
    W.Fire("GOSSIP_SHOW"); eq(#W.did, 1, "the timer ran out")
    ns.db.pauseKey = "CTRL"
    W.shift, W.ctrl = true, false
    W.Fire("GOSSIP_SHOW"); eq(#W.did, 2, "Shift is no longer the key")
    W.ctrl = true
    W.Fire("GOSSIP_SHOW"); eq(#W.did, 2)
    ns.db.pauseKey = "NONE"
    W.Fire("GOSSIP_SHOW"); eq(#W.did, 3)
end)

test("an ignored NPC and an ignored quest are left alone", function()
    Fake({ npc = { active = {}, available = { { 7, false }, { 8, false } } }, npcID = 500 })
    local ns = Load()
    W.Fire("GOSSIP_SHOW")
    eq(ns.last.npc, 500)
    ns.IgnoreQuest(7, "Seven")
    W.Fire("GOSSIP_SHOW")
    eq(W.did[2], "available:8", "quest 7 is skipped")
    ns.IgnoreNpc(500, "Bob")
    W.Fire("GOSSIP_SHOW")
    eq(#W.did, 2)
    eq(#ns.Ignored(), 2); eq(ns.Ignored()[1].kind, "npc")
    ns.Unignore("npc", 500)
    W.Fire("GOSSIP_SHOW"); eq(#W.did, 3)
    SlashCmdList.GULLIAUTOQUEST("ignore")
    eq(ns.db.ignoreNpc[500] ~= nil, true)
end)

test("quests shared by the group wait for their switch", function()
    Fake({})
    local ns = Load()
    W.Fire("QUEST_ACCEPT_CONFIRM"); eq(#W.did, 0, "off by default")
    ns.db.shared = true
    W.Fire("QUEST_ACCEPT_CONFIRM"); eq(W.did[1], "confirm")
end)

test("a quest that takes non-quest items is not handed in unless allowed", function()
    Fake({})
    local ns = Load()
    W.required = { "item:2589" }; W.classes["item:2589"] = 7
    W.Fire("QUEST_PROGRESS"); eq(#W.did, 0)
    assert(W.printed[#W.printed]:find("2589"))
    W.classes["item:2589"] = 12
    W.Fire("QUEST_PROGRESS"); eq(W.did[1], "complete", "quest items are fine")
    W.classes["item:2589"] = 7; ns.db.itemQuests = true
    W.Fire("QUEST_PROGRESS"); eq(W.did[2], "complete")
end)

test("elite, dungeon and group quests and a full log follow their switches", function()
    Fake({})
    local ns = Load()
    W.tags[101] = { tagID = 81 }
    W.Fire("QUEST_DETAIL"); eq(W.did[1], "accept", "off by default")
    ns.db.skipDungeon = true
    W.Fire("QUEST_DETAIL"); eq(#W.did, 1)
    W.tags[101] = { tagID = 0, isElite = true }; ns.db.skipElite = true
    W.Fire("QUEST_DETAIL"); eq(#W.did, 1)
    W.tags[101] = nil; W.group = 3; ns.db.skipGroup = true
    W.Fire("QUEST_DETAIL"); eq(#W.did, 1)
    W.group = 0; ns.db.minFree = 2; W.log = 18
    W.Fire("QUEST_DETAIL"); eq(#W.did, 1, "two places left")
    W.log = 17
    W.Fire("QUEST_DETAIL"); eq(W.did[2], "accept")
end)

test("the best vendor price: marked, or taken when asked", function()
    Fake({})
    local ns = Load()
    W.choices, W.prices = 3, { [1] = 10, [2] = 500, [3] = 20 }
    W.Fire("QUEST_COMPLETE"); eq(#W.did, 0)
    ns.db.pickBest = true
    W.Fire("QUEST_COMPLETE"); eq(W.did[1], "reward:2")
end)

test("the only gossip line waits for its switch", function()
    Fake({ npc = { active = {}, available = {} } })
    local ns = Load()
    W.options = { { gossipOptionID = 42 } }
    W.Fire("GOSSIP_SHOW"); eq(#W.did, 0)
    ns.db.gossip = true
    W.Fire("GOSSIP_SHOW"); eq(W.did[1], "option:42")
    W.options = { { gossipOptionID = 1 }, { gossipOptionID = 2 } }
    W.Fire("GOSSIP_SHOW"); eq(#W.did, 1, "two lines: the player picks")
end)

test("counters survive a reload, a login resets them; undo abandons the last quest; feed and summary", function()
    local notes = {}
    Fake({})
    GulliToolkit = { Register = function(t) W.reg = t end, Notify = function(_, t) notes[#notes + 1] = t end }
    local ns = Load()
    W.Fire("QUEST_DETAIL")
    W.Fire("QUEST_ACCEPTED", 101)
    eq(ns.db.session.taken, 1)
    eq(ns.last.accepted, 101)
    W.RunTimers()
    eq(notes[1], ns.L.FEED:format(1, 0))
    eq(W.reg.summary(), ns.L.FEED:format(1, 0))
    W.Fire("PLAYER_ENTERING_WORLD", false, true)
    eq(ns.db.session.taken, 1, "a reload keeps the session")
    ns.Undo()
    eq(W.did[#W.did], "abandon")
    W.Fire("PLAYER_ENTERING_WORLD", true, false)
    eq(ns.db.session.taken, nil, "a new login starts over")
    ns.db.accept = false; ns.db.paused = true
    W.reg.reset()
    eq(ns.db.accept, true); eq(ns.db.paused, false)
    GulliToolkit = nil
end)

test("the window draws every tab", function()
    Fake({})
    local ns = Load()
    for i = 1, 3 do ns.ShowTab(i) end
end)

W.finish()
