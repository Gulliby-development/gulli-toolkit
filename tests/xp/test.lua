-- Run from the repository root: lua5.1 tests/xp/test.lua
local W = dofile("tests/xp/wow.lua")
local test, eq = W.test, W.eq

test("every language has every text", function()
    Fake({})
    W.CheckLocales(Load())
end)

test("the rate counts the last hour of play", function()
    Fake({ level = 20, now = 0 })
    local ns = Load()
    W.now = 600; W.Gain(500)
    W.now = 1200; W.Gain(500)
    eq(ns.Rate(1200), 1000 * 3600 / 1200)
    eq(ns.Rate(3600 + 601), 500, "the first gain left the hour")
end)

test("a level up counts the rest of the old level", function()
    Fake({ level = 20, xp = 900, xpMax = 1000, now = 0 })
    local ns = Load()
    W.now = 300
    W.Gain(300) -- 100 to finish the level, 200 into the next
    eq(ns.s.gained, 300)
    eq(W.level, 21)
end)

test("time and kills to the next level", function()
    Fake({ level = 20, xp = 0, xpMax = 10000, now = 0 })
    local ns = Load()
    W.now = 1800
    for _ = 1, 10 do
        W.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Boar dies, you gain 100 experience.")
        W.Gain(100)
    end
    local st = ns.Stats(1800)
    eq(st.rate, 2000)
    eq(st.killsToLevel, 90)
    eq(st.toLevel, 9000 / 2000 * 3600)
    eq(ns.Span(st.toLevel), "4 h 30 min")
end)

test("quest XP is counted apart", function()
    Fake({ level = 20 })
    local ns = Load()
    W.Fire("QUEST_TURNED_IN", 123, 850, 100)
    W.Gain(850)
    eq(ns.Stats().quests, 1)
    eq(ns.Stats().questXP, 850)
    eq(ns.Stats().kills, 0)
end)

test("short numbers", function()
    Fake({})
    local ns = Load()
    eq(ns.Short(950), "950"); eq(ns.Short(1234), "1.2k"); eq(ns.Short(45678), "45k")
end)

test("the bar hides at the top level and when switched off", function()
    Fake({ level = 20, now = 0 })
    local ns = Load()
    W.now = 120; W.Gain(100)
    assert(ns.BarText():find("3.0k XP/h", 1, true), ns.BarText())
    W.level = 60
    ns.Refresh()
    eq(ns.MaxLevel(), true)
    ns.Toggle()
    W.Fire("PLAYER_LOGIN")
    eq(ns.s.gained, 0, "a new login starts a new session")
end)

W.finish()
