-- Run from the repository root: lua5.1 tests/attune/test.lua
local W = dofile("tests/attune/wow.lua")
local test, eq = W.test, W.eq

local function raid(ns, char, key)
    for _, r in ipairs(ns.RaidsFor(char)) do
        if r.key == key then return ns.Progress(char, r) end
    end
end

test("a scan saves done and active quests for this character", function()
    Fake({ done = { [7848] = true, [4182] = true }, active = { [4183] = true } })
    local ns = Load()
    ns.Scan()
    local c = ns.db.chars["Tester-Realm"]
    eq(c.done[7848], true)
    eq(c.active[4183], true)
    eq(c.faction, "Alliance")
    eq(raid(ns, c, "MC").ready, true)
    local ony = raid(ns, c, "ONY")
    eq(ony.done, 1)
    eq(ony.next[1], 4183, "the next step is the first one not done")
    eq(ony.steps[2].state, "active")
    eq(ony.ready, false)
end)

test("each faction sees its own Onyxia chain", function()
    Fake({ faction = "Horde" })
    local ns = Load()
    ns.Scan()
    local c = ns.db.chars["Tester-Realm"]
    local ony = raid(ns, c, "ONY")
    eq(ony.steps[1].step[1], 4903)
    eq(ony.total, 14)
end)

test("the amulet or the key in the bags means ready", function()
    Fake({ items = { [16309] = 1, [12344] = 1 } })
    local ns = Load()
    ns.Scan()
    local c = ns.db.chars["Tester-Realm"]
    eq(raid(ns, c, "ONY").ready, true)
    eq(raid(ns, c, "UBRS").ready, true)
    eq(raid(ns, c, "BWL").ready, false)
end)

test("Naxxramas: any of the three quests is enough", function()
    Fake({ done = { [9123] = true } })
    local ns = Load()
    ns.Scan()
    eq(raid(ns, ns.db.chars["Tester-Realm"], "NAXX").ready, true)
end)

test("other characters stay; this one comes first; forget removes one", function()
    Fake({ db = { chars = { ["Alt-Realm"] = { name = "Alt", level = 60, faction = "Alliance", done = {}, active = {} },
                            ["Low-Realm"] = { name = "Low", level = 20, faction = "Alliance", done = {}, active = {} } } },
           level = 10 })
    local ns = Load()
    ns.Scan()
    local list = ns.Chars()
    eq(list[1].key, "Tester-Realm"); eq(list[2].key, "Alt-Realm"); eq(list[3].key, "Low-Realm")
    ns.Forget("Low-Realm")
    eq(#ns.Chars(), 2)
end)

test("names: the game's quest and zone names first, then English", function()
    Fake({ titles = { [7848] = "Настройка на Недра" }, areas = { [25] = "Черная гора" } })
    local ns = Load()
    local mc
    for _, r in ipairs(ns.RAIDS) do if r.key == "MC" then mc = r end end
    local step = mc.steps[1]
    eq(ns.QuestName(step), "Настройка на Недра")
    eq(ns.Where(step), "Lothos Riftwaker, Черная гора")
    eq(ns.RaidName(mc), "Molten Core")
end)

test("events scan after a short pause; the window opens", function()
    Fake({})
    local ns = Load()
    W.Fire("QUEST_TURNED_IN")
    W.Fire("QUEST_ACCEPTED")
    eq(#W.timers, 1)
    W.RunTimers()
    assert(ns.db.chars["Tester-Realm"])
    SlashCmdList.GULLIATTUNE("")
    ns.Refresh()
end)

test("dungeon keys: the chain or the key in the bags; Scholomance has a chain per faction", function()
    Fake({ done = { [3801] = true, [3802] = true }, items = { [17191] = 1 } })
    local ns = Load()
    ns.Scan()
    local c = ns.db.chars["Tester-Realm"]
    eq(raid(ns, c, "BRD").ready, true)
    eq(raid(ns, c, "MARA").ready, true, "the Scepter of Celebras in the bags")
    local sch = raid(ns, c, "SCHOLO")
    eq(sch.steps[1].step[1], 5092)
    eq(sch.total, 8)
    Fake({ faction = "Horde", items = { [13704] = 1 } })
    ns = Load()
    ns.Scan()
    c = ns.db.chars["Tester-Realm"]
    sch = raid(ns, c, "SCHOLO")
    eq(sch.steps[1].step[1], 5096)
    eq(sch.ready, true, "the Skeleton Key in the bags")
end)

test("what Forever has now comes first; raids it has not opened are last and marked", function()
    Fake({})
    local ns = Load()
    eq(ns.RAIDS[1].key, "ONY")
    local seenLater = false
    for _, r in ipairs(ns.RAIDS) do
        if r.later then seenLater = true else assert(not seenLater, r.key .. " comes after a later raid") end
    end
    assert(seenLater)
    for _, r in ipairs(ns.RAIDS) do
        assert(ns.T.en["RAID_" .. r.key], "no name for " .. r.key)
    end
end)

test("every language has every key, with the same placeholders", function()
    Fake({})
    W.CheckLocales(Load())
end)

W.finish()
