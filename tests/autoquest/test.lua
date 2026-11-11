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

W.finish()
