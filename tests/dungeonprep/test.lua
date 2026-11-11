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
    Fake({ level = 30 })
    local ns = Load()
    SlashCmdList.GULLIDUNGEONPREP("sm")
    eq(ns.selected, "SM")
    ns.Refresh()
end)

test("every language has every key, with the same placeholders", function()
    Fake({})
    W.CheckLocales(Load())
end)

W.finish()
