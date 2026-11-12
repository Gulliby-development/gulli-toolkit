-- Run from the repository root: lua5.1 tests/dungeonprep/test.lua
local W = dofile("tests/dungeonprep/wow.lua")
local test, eq = W.test, W.eq

local function ids(list)
    local t = {}
    for _, q in ipairs(list) do t[#t + 1] = q.id end
    table.sort(t)
    return table.concat(t, ",")
end

test("the data lists the dungeons in level order, each with its quests", function()
    Fake({})
    local ns = Load()
    local d = ns.Dungeons(20)
    eq(d[1].key, "RFC")
    eq(#d, 19)
    for _, x in ipairs(d) do assert(ns.Data.byDungeon[x.key], "no quests for " .. x.key) end
    for i = 2, #d do assert(d[i].min >= d[i - 1].min, "level order") end
end)

test("the suggestion is the highest dungeon that fits the level", function()
    Fake({})
    local ns = Load()
    eq(ns.Suggest(20).key, "DM")
    eq(ns.Suggest(60).key, "STRAT")
    eq(ns.Suggest(5).key, "RFC", "too low for any: the first one")
end)

test("Deadmines for a level 18 human: in the log, can take, needs an earlier quest, too low", function()
    Fake({ active = { [168] = true }, done = {} })
    local ns = Load()
    local q = ns.Quests("DM", 18)
    eq(ids(q.log), "168")
    eq(ids(q.take), "167,2040", "Oh Brother and Underground Assault")
    local later = {}
    for _, x in ipairs(q.later) do later[x.id] = x.why end
    eq(later[214], "WHY_EARLIER", "Red Silk Bandanas needs Westfall Stew first")
    eq(later[166], "WHY_EARLIER")
    eq(later[1654], nil, "a paladin quest is not for a warrior")
end)

test("done quests are counted; an earlier quest in the log is enough for one-of chains", function()
    Fake({ done = { [167] = true, [155] = true } })
    local ns = Load()
    local q = ns.Quests("DM", 14)
    eq(q.done, 1)
    local take, later = {}, {}
    for _, x in ipairs(q.take) do take[x.id] = true end
    for _, x in ipairs(q.later) do later[x.id] = x.why end
    assert(take[214], "Red Silk Bandanas once Westfall Stew is done")
    eq(later[2040], "WHY_LEVEL", "Underground Assault needs level 15")
end)

test("where: who starts it and the zone in the game's language", function()
    Fake({ areas = { [1519] = "Штормград" } })
    local ns = Load()
    local q = ns.Quests("DM", 20)
    for _, x in ipairs(q.take) do
        if x.id == 2040 then eq(ns.Where(x), "Shoni the Shilent, Штормград") end
    end
end)

test("Gnomeregan for a Horde tauren: no Alliance quests, no repeatable or machine turn-ins", function()
    Fake({ raceID = 6, faction = "Horde" })
    local ns = Load()
    local q = ns.Quests("GNOMER", 33)
    local seen = {}
    for _, list in ipairs({ q.take, q.later, q.log }) do
        for _, x in ipairs(list) do seen[x.id] = true end
    end
    assert(seen[2841], "Rig Wars is a Horde quest")
    assert(not seen[2922] and not seen[2929], "Alliance quests are left out")
    for id, x in pairs(ns.Data.quest) do
        assert(x[1] ~= "More Sparklematic Action" and x[1] ~= "The Sparklematic 5200!", "machine quest " .. id)
    end
end)

test("a quest for one faction only is left out for the other, even with an open race mask", function()
    Fake({ raceID = 1, faction = "Alliance" })
    local ns = Load()
    ns.Data.byDungeon.TEST = { 1 }
    ns.Data.quest[1] = { "Horde only", 20, 15, 0, 0, "Someone", 1637, {}, {}, {}, "H", 50, 50 }
    eq(#ns.Quests("TEST", 20).take, 0)
    ns.Data.quest[1][11] = ""
    eq(#ns.Quests("TEST", 20).take, 1)
end)

test("quest and dungeon colours follow the game's difficulty steps", function()
    Fake({})
    local ns = Load()
    eq(ns.GrayLevel(30), 22)
    eq(ns.Difficulty(35, 30), "IMPOSSIBLE")
    eq(ns.Difficulty(33, 30), "VERYDIFFICULT")
    eq(ns.Difficulty(28, 30), "DIFFICULT")
    eq(ns.Difficulty(23, 30), "STANDARD")
    eq(ns.Difficulty(22, 30), "TRIVIAL")
    local d = { min = 29, max = 38 }
    eq(ns.DungeonDifficulty(d, 25), "IMPOSSIBLE")
    eq(ns.DungeonDifficulty(d, 28), "VERYDIFFICULT")
    eq(ns.DungeonDifficulty(d, 30), "DIFFICULT")
    eq(ns.DungeonDifficulty(d, 36), "STANDARD")
    eq(ns.DungeonDifficulty(d, 40), "TRIVIAL")
    for _, x in ipairs(ns.Dungeons(30)) do assert(ns.ICONS[x.key], "an icon for " .. x.key) end
end)

local MAPS = { [1414] = { "Kalimdor", 2 }, [1415] = { "Eastern Kingdoms", 2 },
               [1454] = { "Orgrimmar", 3, 1414 }, [1413] = { "The Barrens", 3, 1414 },
               [1434] = { "Stranglethorn Vale", 3, 1415 } }
local AREAS = { [1637] = "Orgrimmar", [17] = "The Barrens", [33] = "Stranglethorn Vale" }

test("where the player is: zone, place on its map, continent", function()
    Fake({ map = { best = 1454, maps = MAPS, pos = { 0.5, 0.25 } } })
    local ns = Load()
    local h = ns.Here()
    eq(h.zone, "Orgrimmar"); eq(h.x, 50); eq(h.y, 25); eq(h.kalimdor, true)
    Fake({})
    eq(Load().Here().zone, nil, "no map: nothing known")
end)

test("the way: your zone nearest first, then the same continent, the other one, inside last", function()
    Fake({ areas = AREAS })
    local ns = Load()
    local function q(id, who, area, x, y) return { id = id, who = who, area = area, x = x, y = y } end
    local take = { q(1, "Scooty", 33, 27, 77), q(2, "Nogg", 1637, 76, 25), q(3, "Sovik", 1637, 75, 25),
                   q(4, "Far", 1637, 10, 10), q(5, "Barrens guy", 17, 50, 50), q(6, "Ring", 0, 0, 0) }
    local stops = ns.Route(take, { zone = "Orgrimmar", x = 12, y = 12, kalimdor = true })
    local names = {}
    for _, s in ipairs(stops) do names[#names + 1] = s.inside and "inside" or s.who end
    eq(table.concat(names, ","), "Far,Sovik,Nogg,Barrens guy,Scooty,inside")
    eq(stops[1].here, true); eq(stops[4].here, false)
    local two = 0
    for _, s in ipairs(ns.Route({ q(1, "Nogg", 1637, 76, 25), q(2, "Nogg", 1637, 76, 25) }, {})) do
        two = two + #s.quests
    end
    eq(two, 2, "one stop for two quests from the same NPC")
end)

test("a click on a stop sets a map pin in its zone", function()
    local W = Fake({ areas = AREAS, map = { maps = MAPS } })
    local ns = Load()
    local stop = ns.Route({ { id = 1, who = "Nogg", area = 1637, x = 76, y = 25 } }, {})[1]
    eq(ns.SetPin(stop), true)
    eq(W.pins[1].map, 1454); eq(W.pins[1].x, 0.76)
    eq(ns.SetPin({ inside = true, quests = {} }), false)
end)

test("checklist: gear, bags, food and drink, hearthstone", function()
    Fake({ durability = { [1] = { 30, 100 }, [5] = { 90, 100 } },
           bags = { [0] = { size = 16, slots = { [1] = { 4540, 12 }, [2] = { 25, 1 } } } },
           hearth = { 99000, 3600 }, now = 100000 })
    local ns = Load()
    local c = ns.Checklist()
    eq(c[1].key, "REPAIR"); eq(c[1].ok, false); eq(c[1].text, "Gear at 30%")
    eq(c[2].ok, true); eq(c[2].text, "14 free bag slots")
    eq(c[3].ok, true); eq(c[3].text, "12 food and drink")
    eq(c[4].ok, false); eq(c[4].text, "Hearthstone in 44 min")
end)

test("the window and /gdp <dungeon>", function()
    Fake({ level = 30, areas = AREAS, map = { best = 1454, maps = MAPS, pos = { 0.5, 0.5 } } })
    local ns = Load()
    SlashCmdList.GULLIDUNGEONPREP("sm")
    eq(ns.selected, "SM")
    ns.Refresh()
    SlashCmdList.GULLIDUNGEONPREP("gnomer")
    ns.Refresh()
end)

test("every language has every key, with the same placeholders", function()
    Fake({})
    W.CheckLocales(Load())
end)

W.finish()
