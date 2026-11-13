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
    eq(ns.Rate(3600 + 601), 500 * 3600 / (599 + ns.IDLE), "the first gain left the hour; the long gap since is a break")
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
    eq(st.rate, 6000, "30 minutes without XP count as a 10 minute break")
    eq(st.killsToLevel, 90)
    eq(st.toLevel, 9000 / 6000 * 3600)
    eq(ns.Span(st.toLevel), "1 h 30 min")
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
    W.Fire("PLAYER_ENTERING_WORLD", false, true)
    eq(ns.s.gained, 100, "a /reload keeps the session")
    W.Fire("PLAYER_ENTERING_WORLD", true, false)
    eq(ns.s.gained, 0, "a new login starts a new session")
end)

test("older saves get the bar's new settings", function()
    Fake({ db = { bar = false } })
    local ns = Load()
    eq(ns.db.bar, false, "a saved choice stays")
    eq(ns.db.locked, false); eq(ns.db.alpha, 100); eq(ns.db.scale, 100)
end)

test("the line under the bar: level done, then the rested part", function()
    Fake({ level = 20, xp = 250, xpMax = 1000, rested = 500 })
    local ns = Load()
    local done, rested = ns.BarParts(ns.Stats())
    eq(done, 0.25); eq(rested, 0.5)
    W.rested = 5000
    done, rested = ns.BarParts(ns.Stats())
    eq(rested, 0.75, "rested never runs past the level")
end)

local function theBar()
    for _, f in ipairs(W.frames) do
        if rawget(f, "_OnDragStart") then return f end
    end
end

test("a locked bar does not move, and the place is saved", function()
    Fake({ level = 20 })
    local ns = Load()
    ns.Refresh()
    local bar = assert(theBar(), "the bar is built")
    local moved = 0
    rawset(bar, "StartMoving", function() moved = moved + 1 end)
    rawset(bar, "GetPoint", function() return "CENTER", nil, "CENTER", 12, -34 end)
    ns.SetPref("locked", true)
    bar._OnDragStart(bar)
    eq(moved, 0, "locked")
    ns.SetPref("locked", false)
    bar._OnDragStart(bar)
    bar._OnDragStop(bar)
    eq(moved, 1, "unlocked")
    eq(ns.db.point[1], "CENTER"); eq(ns.db.point[3], -34)
    ns.SetPref("point", nil)
    eq(ns.db.point, nil, "Reset puts it back")
end)

test("opacity and size change the bar", function()
    Fake({ level = 20 })
    local ns = Load()
    ns.Refresh()
    local bar = theBar()
    local scale
    rawset(bar, "SetScale", function(_, v) scale = v end)
    ns.SetPref("scale", 150)
    eq(scale, 1.5)
    ns.SetPref("alpha", 0)
    eq(ns.db.alpha, 0)
end)

test("the hub shows the bar and lock switches", function()
    Fake({ level = 20 })
    local got
    GulliToolkit = { Register = function(m) got = m end }
    local ns = Load()
    eq(#got.options, 3)
    got.options[2].set(true)
    eq(ns.db.locked, true)
    eq(got.options[2].get(), true)
end)

test("the session survives a /reload, a long break starts a new one", function()
    Fake({ level = 20, now = 0 })
    local ns = Load()
    W.now = 300; W.Gain(400)
    local saved = GulliXPCharDB
    eq(saved.s.gained, 400, "the session is saved per character")
    -- /reload: the files run again with the saved variables.
    Fake({ level = 20, now = 400, cdb = saved, xp = 400 })
    ns = Load()
    eq(ns.s.gained, 400, "kept")
    W.now = 500; W.Gain(100)
    eq(ns.s.gained, 500)
    Fake({ level = 20, now = 500 + 3 * ns.IDLE, cdb = saved, xp = 500 })
    ns = Load()
    eq(ns.s.gained, 0, "after a long break a new session")
end)

test("breaks do not count as play time", function()
    Fake({ level = 20, now = 0 })
    local ns = Load()
    W.now = 100; W.Gain(10)
    W.now = 5000; W.Gain(10)
    eq(ns.Active(5000), 100 + ns.IDLE)
    eq(ns.Stats(5000).session, 100 + ns.IDLE)
end)

test("finished quests: their XP, the gold part of the line and the level after hand-in", function()
    Fake({ level = 20, xp = 200, xpMax = 1000, rested = 300 })
    local quests = { { questID = 1, done = true, xp = 150 }, { isHeader = true }, { questID = 2, done = false, xp = 900 },
                     { questID = 3, done = true, xp = 50 } }
    C_QuestLog = {
        GetNumQuestLogEntries = function() return #quests end,
        GetInfo = function(i) return quests[i] end,
        IsComplete = function(id) for _, q in ipairs(quests) do if q.questID == id then return q.done end end end,
    }
    GetQuestLogRewardXP = function(id) for _, q in ipairs(quests) do if q.questID == id then return q.xp end end end
    local ns = Load()
    local st = ns.Stats()
    eq(st.ready, 200); eq(st.readyN, 2)
    eq(st.readyPercent, 40)
    local done, rested, ready = ns.BarParts(st)
    eq(done, 0.2); eq(ready, 0.2); eq(rested, 0.3)
    quests[3].done = true
    eq(ns.Stats().ready, 200, "cached until the log changes")
    W.Fire("QUEST_LOG_UPDATE")
    eq(ns.Stats().ready, 1100)
    local _, r2, rd2 = ns.BarParts(ns.Stats())
    eq(rd2, 0.8, "never past the end of the level")
    eq(r2, 0)
    local tip = table.concat(ns.TipLines(), "\n")
    assert(tip:find("1.1k", 1, true), tip)
    C_QuestLog, GetQuestLogRewardXP = nil, nil
end)

test("each level goes into the history with its play time, and the hub hears of it", function()
    Fake({ level = 20, xp = 0, xpMax = 1000, now = 0 })
    local notes = {}
    GulliToolkit = { Register = function() end, Notify = function(k, t) notes[#notes + 1] = t end }
    local ns = Load()
    W.now = 300; W.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Boar dies, you gain 600 experience."); W.Gain(600)
    W.now = 600; W.Fire("QUEST_TURNED_IN", 1, 500, 0); W.Gain(500)
    W.Fire("PLAYER_LEVEL_UP", 21)
    local e = ns.Levels()[1]
    eq(e.level, 20); eq(e.time, 600); eq(e.kills, 1); eq(e.killXP, 600); eq(e.questXP, 500)
    eq(#notes, 1)
    assert(notes[1]:find("21", 1, true) and notes[1]:find("10 min", 1, true), notes[1])
    GulliToolkit = nil
end)

test("other XP, quests to level and the bar's text choices", function()
    Fake({ level = 20, xp = 0, xpMax = 10000, now = 0 })
    local ns = Load()
    W.now = 60
    W.Fire("QUEST_TURNED_IN", 1, 1000, 0); W.Gain(1000)
    W.Gain(500) -- exploring
    local st = ns.Stats()
    eq(st.otherXP, 500)
    eq(st.questsToLevel, 9)
    for _, m in ipairs(ns.TEXTS) do
        ns.SetPref("text", m)
        assert(ns.BarText() ~= "", m)
        assert(ns.L["TEXT_" .. m:upper()], "no label for " .. m)
    end
    ns.SetPref("text", "pct")
    eq(ns.BarText(), "Level 20: 15%")
    ns.SetPref("text", "left")
    eq(ns.BarText(), "8.5k XP to go (15%)")
end)

test("summary, shift-click to chat, move and reset for the hub", function()
    Fake({ level = 20, xp = 0, xpMax = 10000, now = 0 })
    local got
    GulliToolkit = { Register = function(m) got = m end }
    local ns = Load()
    W.now = 600; W.Gain(1000)
    assert(got.summary():find("Level 21", 1, true), got.summary())
    assert(ns.ShareText():find("Level 20", 1, true))
    local sent
    IsInGroup = function() return true end
    SendChatMessage = function(text, ch) sent = ch end
    ns.Share()
    eq(sent, "PARTY")
    IsInGroup, SendChatMessage = nil, nil
    ns.SetPref("locked", true)
    eq(ns.Locked(), true)
    got.move(true)
    eq(ns.Locked(), false, "/gulli move unlocks the bar")
    got.move(false)
    ns.SetPref("alpha", 30)
    got.reset()
    eq(ns.db.alpha, 100); eq(ns.db.locked, false)
    W.level = 60
    GetWatchedFactionInfo = function() return "Darnassus", 5, 3000, 9000, 4500 end
    FACTION_STANDING_LABEL5 = "Friendly"
    eq(got.summary(), "Darnassus: Friendly, 25%", "at the top level: the watched reputation")
    ns.Refresh()
    GetWatchedFactionInfo, FACTION_STANDING_LABEL5, GulliToolkit = nil, nil, nil
end)

test("the window builds with its three tabs", function()
    Fake({ level = 20 })
    local ns = Load()
    ns.Toggle()
    local tabs, pages = ns.Tabs()
    eq(#pages, 3)
    tabs:Select(2)
    tabs:Select(3)
    ns.Refresh()
end)

test("the tooltip comes in blocks and the bar can be filled or a thin line", function()
    Fake({ level = 20, xp = 200, xpMax = 1000, now = 0 })
    local ns = Load()
    local heads = {}
    for _, r in ipairs(ns.TipRows()) do if r.head then heads[#heads + 1] = r.head end end
    eq(table.concat(heads, ","), "Pace,Level,Session")
    eq(ns.db.style, "fill")
    ns.Refresh()
    ns.SetPref("style", "line")
    eq(ns.db.style, "line")
    for _, k in ipairs(ns.STYLES) do assert(ns.L["STYLE_" .. k:upper()], k) end
end)

W.finish()
