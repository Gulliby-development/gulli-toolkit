-- Run from the repository root: lua5.1 tests/chores/test.lua
local W = dofile("tests/chores/wow.lua")
local test, eq = W.test, W.eq

local function has(tasks, key)
    for _, t in ipairs(tasks) do if t.key == key then return t end end
end

test("every language has every text", function()
    Fake({})
    W.CheckLocales(Load())
end)

test("a fresh character has nothing to do and counts its trainer as visited", function()
    Fake({ level = 20 })
    local ns = Load()
    W.Fire("PLAYER_ENTERING_WORLD")
    local c = ns.db.chars[ns.CharKey()]
    eq(c.trainer, 20)
    eq(#ns.Tasks(c), 0)
end)

test("a new level asks for the trainer until the trainer window opens", function()
    Fake({ level = 20 })
    local ns = Load()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.level = 21
    local c = ns.Snapshot()
    assert(has(ns.Tasks(c), "TRAINER"))
    W.Fire("TRAINER_SHOW")
    assert(not has(ns.Tasks(ns.Snapshot()), "TRAINER"))
end)

test("mail, low durability and full bags show up", function()
    Fake({})
    local ns = Load()
    W.char.mail, W.char.free, W.char.durability = true, 1, { 80, 20 }
    local tasks = ns.Tasks(ns.Snapshot())
    assert(has(tasks, "MAIL"))
    eq(has(tasks, "REPAIR").text, "Repair: gear at 20%")
    eq(has(tasks, "BAGS").text, "Free bag slots: 1")
end)

test("rested XP grows offline and is full after enough days in an inn", function()
    Fake({ level = 30 })
    local ns = Load()
    W.char.rested, W.char.resting = 500, true -- half a level
    local c = ns.Snapshot()
    eq(ns.RestedNow(c, W.now), 0.5)
    assert(not has(ns.Tasks(c, W.now), "RESTED"))
    local full = W.now + 8 * 3600 * 20 -- one level more needs 20 x 8 hours
    eq(ns.RestedNow(c, full), 1.5)
    assert(has(ns.Tasks(c, full), "RESTED"))
    -- Outside an inn it grows four times slower.
    c.resting = false
    eq(ns.RestedNow(c, full), 0.5 + 0.25)
end)

test("no rested task at the top level", function()
    Fake({ level = 60 })
    local ns = Load()
    W.char.rested = 1500
    assert(not has(ns.Tasks(ns.Snapshot(), W.now + 86400 * 30), "RESTED"))
end)

test("a crafting cooldown is saved as real time and is ready later", function()
    Fake({ now = 50000 })
    local ns = Load()
    W.char.spells[18560] = true
    W.char.cooldowns[18560] = { 50000 - 3600, 4 * 86400 } -- started an hour ago, 4 days long
    local c = ns.Snapshot()
    local ready = 50000 - 3600 + 4 * 86400
    eq(c.cooldowns.CD_MOONCLOTH, ready)
    assert(not has(ns.Tasks(c, W.now), "CD"))
    eq(ns.NextReady(c, W.now), ready)
    eq(has(ns.Tasks(c, ready), "CD").text, "Mooncloth is ready")
    eq(ns.NextReady(c, ready), nil)
end)

test("a cooldown the character does not know is not tracked", function()
    Fake({})
    local ns = Load()
    W.char.cooldowns[18560] = { W.now, 86400 }
    eq(ns.Snapshot().cooldowns.CD_MOONCLOTH, nil)
    W.char.items[15846] = 1 -- the Salt Shaker is tracked while it is in the bags
    eq(has(ns.Tasks(ns.Snapshot()), "CD").text, "Salt Shaker is ready")
end)

test("login prints what waits on the other characters", function()
    Fake({ name = "Me", db = { chars = {
        ["Alt-Realm"] = { name = "Alt", level = 30, t = 1000, trainer = 30, mail = true, cooldowns = {} },
        ["Done-Realm"] = { name = "Done", level = 60, maxLevel = true, t = 1000, cooldowns = {} },
    } } })
    local ns = Load()
    local feed = {}
    GulliToolkit = { Notify = function(key, text) feed[#feed + 1] = key .. ":" .. text end }
    W.Fire("PLAYER_ENTERING_WORLD")
    local last = W.printed[#W.printed]
    assert(last:find("Alt: You have mail", 1, true), last)
    assert(not last:find("Done", 1, true))
    eq(#feed, 1)
end)

test("the list puts this character first and forget removes another one", function()
    Fake({ name = "Me", level = 10, db = { chars = {
        ["Alt-Realm"] = { name = "Alt", level = 50, t = 1000, cooldowns = {} },
    } } })
    local ns = Load()
    ns.Snapshot()
    local list = ns.Chars()
    eq(list[1].key, "Me-Realm")
    eq(list[2].key, "Alt-Realm")
    ns.Toggle()
    ns.Forget("Alt-Realm")
    eq(#ns.Chars(), 1)
end)

test("time spans read in days, hours and minutes", function()
    Fake({})
    local ns = Load()
    eq(ns.Span(2 * 86400 + 5), "2 d")
    eq(ns.Span(3 * 3600 + 59), "3 h")
    eq(ns.Span(20), "1 min")
end)

W.finish()
