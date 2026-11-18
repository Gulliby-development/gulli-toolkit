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
    eq(#d, 28, "19 classic and 9 Forever dungeons")
    for _, x in ipairs(d) do assert(ns.Data.byDungeon[x.key], "no quests for " .. x.key) end
    for i = 2, #d do assert(d[i].min >= d[i - 1].min, "level order") end
    -- Quests filed under a dungeon's second zone id (Uldaman 1517, Razorfen Kraul 1717).
    local function has(key, id)
        for _, x in ipairs(ns.Data.byDungeon[key]) do if x == id then return true end end
    end
    for _, id in ipairs({ 2342, 709, 2418, 2279, 17 }) do assert(has("ULDA", id), "Uldaman quest " .. id) end
    assert(has("RFK", 1221), "Razorfen Kraul quest 1221")
end)

test("the suggestion is the highest dungeon that fits the level", function()
    Fake({})
    local ns = Load()
    eq(ns.Suggest(20).key, "DM")
    eq(ns.Suggest(60).key, "SHAPERS")
    eq(ns.Suggest(5).key, "RFC", "too low for any: the first one")
end)

test("Deadmines for a level 18 human: in the log, can take, needs an earlier quest, too low", function()
    Fake({ active = { [168] = true }, done = {} })
    local ns = Load()
    local q = ns.Quests("DM", 18)
    eq(ids(q.log), "168")
    eq(ids(q.take), "65,167,373,2040,92744",
       "the Westfall chains (one card each), Oh Brother, The Unsent Letter and Underground Assault")
    local later, take = {}, {}
    for _, x in ipairs(q.later) do later[x.id] = x.why end
    for _, x in ipairs(q.take) do take[x.id] = x end
    eq(later[214], "WHY_EARLIER", "Red Silk Bandanas needs Westfall Stew first")
    eq(take[65].head.id, 166, "the Defias chain is one card, named by its last step")
    eq(take[65].head.name, "The Defias Brotherhood")
    eq(take[92744].head.id, 92819, "two quests that lead to one end share its card")
    eq(later[166], nil, "a later step is no card of its own")
    eq(later[1654], nil, "a paladin quest is not for a warrior")
end)

test("done quests are counted; an earlier quest in the log is enough for one-of chains", function()
    Fake({ done = { [167] = true, [155] = true } })
    local ns = Load()
    local q = ns.Quests("DM", 14)
    eq(q.done, 1, "a chain counts once, when its last step is done")
    eq(ids(q.finished), "167", "the done quests are listed for the Done filter")
    local c = ns.Counts("DM", 14)
    eq(c.done, 1)
    eq(c.log + c.take + c.later, #q.log + #q.take + #q.later, "counts match the lists")
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

test("the tracker's map button pins and opens the world map on the pin's zone", function()
    local W = Fake({ areas = AREAS, map = { maps = MAPS } })
    local opened
    OpenWorldMap = function(id) opened = id end
    local ns = Load()
    eq(ns.PinAt("Nogg", 1637, 76, 25), true)
    eq(opened, nil, "a pin alone leaves the map closed")
    eq(ns.PinAt("Nogg", 1637, 76, 25, true), true)
    eq(opened, 1454, "the map opens on Orgrimmar")
    opened, W.combat = nil, true
    ns.PinAt("Nogg", 1637, 76, 25, true)
    eq(opened, nil, "never in combat")
    OpenWorldMap = nil
end)

test("big dungeons: one refresh for a burst of item answers, bosses only on their page", function()
    local W = Fake({ level = 50, areas = AREAS, map = { best = 1454, maps = MAPS, pos = { 0.5, 0.5 } } })
    local ns = Load()
    SlashCmdList.GULLIDUNGEONPREP("brd")
    local refreshes, bosses = 0, 0
    local refresh, getBosses = ns.Refresh, ns.Bosses
    ns.Refresh = function() refreshes = refreshes + 1; return refresh() end
    ns.Bosses = function(k) bosses = bosses + 1; return getBosses(k) end
    W.timers = {}
    for _ = 1, 200 do W.Fire("GET_ITEM_INFO_RECEIVED", 1, true) end
    eq(refreshes, 0, "no refresh per item")
    eq(#W.timers, 1, "one waiting refresh")
    W.RunTimers()
    eq(refreshes, 1)
    ns.ShowTab(3); bosses = 0; refresh()
    eq(bosses, 0, "the quest page builds no boss loot")
    ns.ShowTab(1); bosses = 0; refresh()
    eq(bosses, 1)
end)

test("rewards: which fit the class and which beat what is worn", function()
    Fake({ level = 22, items = {
        [2041] = { "Tunic of Westfall", 2, 26, "INV_CHEST_MAIL", 4, 2 },   -- leather tunic
        [2042] = { "Staff of Westfall", 2, 26, "INV_2HWEAPON", 2, 10 },
        [6087] = { "Chausses of Westfall", 2, 26, "INVTYPE_LEGS", 4, 3 },  -- mail legs
        [9001] = { "Worn Legs", 1, 30, "INVTYPE_LEGS", 4, 3 },
    }, worn = { [7] = 9001 } })
    local ns = Load()
    local r = ns.Rewards({ reward = { 2041, 2042, 6087 } })
    eq(r[1].fits, false, "a warrior below 40 wears mail, not leather")
    eq(r[2].fits, true, "warriors can learn staves")
    eq(r[3].fits, true); eq(r[3].better, false, "worn legs have a higher item level")
    eq(ns.Fits(4, 4, "INVTYPE_CHEST", "WARRIOR", 40), true, "plate from 40")
    eq(ns.Fits(4, 1, "INVTYPE_CLOAK", "WARRIOR", 20), true, "a cloak fits everyone")
    eq(ns.Fits(2, 19, "INVTYPE_RANGEDRIGHT", "WARRIOR", 20), false, "no wands for warriors")
    eq(ns.Fits(4, 6, "INVTYPE_SHIELD", "PRIEST", 20), false)
    local unknown = ns.Rewards({ reward = { 5 } })[1]
    eq(unknown.name, nil); eq(unknown.fits, nil, "not judged before the game has the item")
end)

test("quests carry who takes them back, their chain step, mobs and the missing earlier quest", function()
    Fake({ areas = { [40] = "Westfall" } })
    local ns = Load()
    local q = ns.Quests("DM", 22)
    local later = {}
    for _, x in ipairs(q.later) do later[x.id] = x end
    local stew = later[214]
    assert(stew and stew.need, "Red Silk Bandanas names what is missing")
    eq(stew.need.id, 155)
    eq(ns.NeedText(stew.need), "Needs The Defias Brotherhood (The Defias Traitor, Westfall)")
    local vc = ns.Quest(166, 22)
    eq(vc.turnin.who, "Gryan Stoutmantle")
    assert(vc.steps > 1 and vc.step == vc.steps, "the last step of the Defias chain")
    eq(vc.targets[1], "Edwin VanCleef")
    eq(ns.NeedText(nil), "Needs an earlier quest")
end)

test("the way ends at the dungeon entrance, before the quests inside", function()
    Fake({ areas = { [40] = "Westfall", [1519] = "Stormwind City" } })
    local ns = Load()
    local dm
    for _, d in ipairs(ns.Dungeons(20)) do if d.key == "DM" then dm = d end end
    eq(dm.entrance.area, 40)
    local stops = ns.Route({ { id = 1, who = "Nogg", area = 1519, x = 50, y = 50 }, { id = 2, who = "", area = 0, x = 0, y = 0 } },
                           {}, dm)
    eq(#stops, 3)
    eq(stops[2].entrance, true); eq(stops[2].zone, "Westfall"); eq(stops[2].x, 42.5)
    eq(stops[3].inside, true)
    for _, d in ipairs(ns.Dungeons(20)) do assert(d.entrance and d.entrance.area > 0, "an entrance for " .. d.key) end
end)

test("hidden quests and the search", function()
    Fake({ active = { [168] = true } })
    local ns = Load()
    ns.SetHidden(2040, true)
    local q = ns.Quests("DM", 18)
    eq(#q.hidden, 1); eq(q.hidden[1].id, 2040)
    for _, x in ipairs(q.take) do assert(x.id ~= 2040, "hidden is not in take") end
    ns.SetHidden(2040, false)
    eq(#ns.Quests("DM", 18).hidden, 0)
    local found = ns.Quests("DM", 18, "oh brother")
    eq(#found.take, 1); eq(found.take[1].id, 167)
    local vc = ns.Quests("DM", 18, "VanCleef")
    eq(#vc.take, 1, "a chain is found by the mob its last step needs")
    eq(vc.take[1].head.id, 166)
end)

test("the dungeon key in the header follows its switch", function()
    Fake({ counts = { [7146] = 1 }, items = { [7146] = { "The Scarlet Key", 1, 1, "", 13, 0 } } })
    local ns = Load()
    local k = ns.KeyState("SM")[1]
    eq(k.have, true); eq(k.name, "The Scarlet Key")
    eq(#ns.KeyState("DM"), 0, "the Deadmines need no key")
    Fake({})
    ns = Load()
    eq(ns.KeyState("SM")[1].have, false)
end)

test("leaving a dungeon: finished quests and where to hand them in, unless switched off", function()
    local W = Fake({ active = { [168] = true, [167] = true }, complete = { [168] = true }, instance = "party",
                     areas = { [1519] = "Stormwind City" }, map = { maps = { [1415] = { "Eastern Kingdoms", 2 },
                     [1453] = { "Stormwind City", 3, 1415 } } } })
    local ns = Load()
    local notes = {}
    GulliToolkit = { Notify = function(_, text) notes[#notes + 1] = text end }
    W.Fire("PLAYER_ENTERING_WORLD")
    W.instance = "none"
    W.Fire("ZONE_CHANGED_NEW_AREA")
    eq(#W.printed, 2, "the hand-in line and the map pin line")
    assert(W.printed[1]:find("Collecting Memories: Wilder Thistlenettle, Stormwind City", 1, true), W.printed[1])
    eq(notes[1], "1 dungeon quests to hand in")
    eq(W.pins[1].map, 1453)
    W.printed = {}
    ns.Set("remind", false)
    W.instance = "party"; W.Fire("ZONE_CHANGED_NEW_AREA")
    W.instance = "none"; W.Fire("ZONE_CHANGED_NEW_AREA")
    eq(#W.printed, 0, "the switch stops the reminder")
    GulliToolkit = nil
end)

test("group: who else has the quest, share it, the TomTom arrow", function()
    local W = Fake({ active = { [168] = true }, party = { { name = "Bob", quests = { [168] = true } }, { name = "Ann", quests = {} } },
                     tomtom = true, areas = AREAS, map = { maps = MAPS } })
    local ns = Load()
    eq(table.concat(ns.GroupOn(168), ","), "Bob")
    eq(ns.Share(168), true); eq(W.shared[1], 168)
    local xp, money = ns.LogReward(168)
    eq(xp, 1450); eq(money, 2500)
    ns.SetPin({ who = "Nogg", zone = "Orgrimmar", x = 76, y = 25 })
    eq(W.tomtom[1], 1454); eq(W.tomtom[4], "Nogg")
    W.tomtom = nil
    ns.Set("tomtom", false)
    ns.SetPin({ who = "Nogg", zone = "Orgrimmar", x = 76, y = 25 })
    eq(W.tomtom, nil, "the switch stops the arrow")
end)

test("hub: a summary line, reset and the switches", function()
    local reg
    Fake({ level = 18, active = { [168] = true } })
    GulliToolkit = { Register = function(t) reg = t end }
    local ns = Load()
    local line = reg.summary()
    eq(line, "The Deadmines: 1 in log, 5 to pick up")
    eq(#reg.options, 5)
    for _, o in ipairs(reg.options) do assert(o.tip and o.icon and o.label, "option fields") end
    reg.options[1].set(false)
    eq(ns.Get("remind"), false)
    reg.reset()
    eq(ns.Get("remind"), true)
    GulliToolkit = nil
end)

test("the window and /gdp <dungeon>", function()
    Fake({ level = 30, areas = AREAS, map = { best = 1454, maps = MAPS, pos = { 0.5, 0.5 } } })
    local ns = Load()
    SlashCmdList.GULLIDUNGEONPREP("sm")
    eq(ns.selected, "SM")
    ns.Refresh()
    SlashCmdList.GULLIDUNGEONPREP("gnomer")
    ns.Refresh()
    ns.ShowTab(2)
    ns.ShowTab(1)
end)

test("the Forever dungeons: their quests, names without a client area, entrances", function()
    Fake({ raceID = 2, faction = "Horde", level = 42 })
    local ns = Load()
    local byKey = {}
    for _, d in ipairs(ns.Dungeons(42)) do byKey[d.key] = d end
    for _, key in ipairs({ "THANES", "LORDAERON", "EXCAVATION", "DALARAN", "DROWNED", "KROLDOK", "ALCAZ",
                           "BLACKMAW", "SHAPERS" }) do
        local d = byKey[key]
        assert(d, "listed: " .. key)
        assert(#ns.Data.byDungeon[key] > 0, "quests for " .. key)
        assert(d.entrance and d.entrance.area > 0, "an entrance for " .. key)
        assert(ns.ICONS[key], "an icon for " .. key)
    end
    eq(ns.DungeonName(byKey.ALCAZ), "Alcaz Prison", "no client area: the DG_ text")
    local q = ns.Quests("KROLDOK", 42)
    local seen = {}
    for _, list in ipairs({ q.take, q.later, q.log }) do for _, x in ipairs(list) do seen[x.id] = true end end
    assert(seen[94968] and seen[94972] and seen[94975], "the Horde quests: Eye of Mugg, Tome of Twilight, Token of Vengeance")
    assert(not seen[94982], "the Alliance Eye of Mugg is left out")
end)

test("a quest's page: chain with the missing step, objectives from the log, track, pins", function()
    local W = Fake({ raceID = 2, faction = "Horde", level = 38, done = { [629] = true, [95748] = true },
                     areas = AREAS, map = { maps = MAPS },
                     objectives = { [95775] = { { text = "Tablet rubbing: 0/1", finished = false } } } })
    local ns = Load()
    local q = ns.Quest(95775, 38)
    eq(q.state, "later")
    local names, missing = {}, nil
    for _, st in ipairs(q.chain) do
        names[#names + 1] = st.id
        if st.missing then missing = st.id end
    end
    eq(names[#names - 1], 95775, "the quest itself in its chain")
    eq(missing, 95770, "Locating the Lost City is the step still missing")
    eq(q.objectives[1].text:sub(1, 12), "Use the hide", "the data's objective before it is taken")
    W.active[95775] = true
    W.done[95770] = true
    q = ns.Quest(95775, 38)
    eq(q.state, "log")
    eq(q.objectives[1].text, "Tablet rubbing: 0/1", "the game's own objective while in the log")
    eq(ns.Track(95775), true); eq(ns.Tracked(95775), true)
    eq(ns.Track(95775), false, "a second click stops tracking")
    eq(ns.PinAt(q.who, q.area, q.x, q.y), true, "Kin'weelay in Stranglethorn Vale")
    eq(ns.PinAt("Inside", 0, 0, 0), false, "no pin inside a dungeon")
    ns.selected = "DROWNED"
    ns.Toggle()
    ns.OpenQuest(95775)
    ns.OpenQuest(nil)
end)

test("every language has every key, with the same placeholders", function()
    Fake({})
    W.CheckLocales(Load())
end)

-- A small journal: the Deadmines with two bosses and a rare.
local function journal(ns)
    ns.Data.boss = { DM = {
        { 639, "Edwin VanCleef", "", 21, 21, 2029, 0, { 5200 }, { { 5193, 3, 18.2 }, { 5191, 3, 9.5 }, { 2874, 1, 100 } } },
        { 644, "Rhahk'Zor", "The Foreman", 19, 19, 1234, 0, {}, { { 872, 3, 25 } } },
        { 596, "Brainwashed Noble", "", 18, 18, 0, 1, {}, { { 3902, 3, 40 } } },
    } }
end
strsplit = function(sep, s)
    local out = {}
    for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%-", "%%-")) do out[#out + 1] = part end
    return unpack(out)
end

test("bosses in order with the rare last, loot best first", function()
    Fake({ items = { [5193] = { "Cape of the Brotherhood", 3, 24, "INVTYPE_CLOAK", 4, 1 } } })
    local ns = Load()
    journal(ns)
    local b = ns.Bosses("DM")
    eq(#b, 3)
    eq(b[1].name, "Edwin VanCleef"); eq(b[1].n, 1); eq(b[1].of, 2, "boss 1 of 2, the rare apart")
    eq(b[3].rare, true, "the rare comes last")
    eq(b[1].loot[1].item, 5193, "blue before white, the best chance first")
    eq(b[1].loot[1].name, "Cape of the Brotherhood")
    eq(b[1].loot[1].fits, true, "a cloak fits everyone")
    eq(ns.Runs, nil, "no runs to count: the chance says it")
    eq(#ns.Bosses("RFC"), 0, "no data yet")
    eq(ns.NpcOf("Creature-0-1-2-3-639-0000AB"), 639)
    eq(ns.NpcOf("Player-1-0ABC"), nil)
end)

test("boss pictures come from the Encounter Journal by display id, then by name", function()
    Fake({})
    local ns = Load()
    journal(ns)
    EJ_GetEncounterInfoByIndex = function(i, instance)
        if instance ~= 63 or i > 2 then return nil end
        return "Boss " .. i, "", 100 + i
    end
    EJ_GetCreatureInfo = function(j, encounter)
        if j > 1 then return nil end
        if encounter == 101 then return 1, "Someone else", "", 2029, 5001 end
        return 2, "Rhahk'Zor", "", 9999, 5002
    end
    local b = ns.Bosses("DM")
    eq(ns.BossIcon("DM", b[1]), 5001, "VanCleef by his display id")
    eq(ns.BossIcon("DM", b[2]), 5002, "Rhahk'Zor by his name")
    eq(ns.BossIcon("DM", b[3]), nil, "the rare has no picture")
    eq(next(ns.BossIcons("THANES")), nil, "a Forever dungeon has no journal")
    EJ_GetEncounterInfoByIndex, EJ_GetCreatureInfo = nil, nil
end)

test("the wishlist: the Loot list puts it first, the filter shows only it", function()
    Fake({})
    local ns = Load()
    journal(ns)
    ns.SetWish(872, true)
    local all = ns.Loot("DM", "all")
    eq(all[1].item, 872, "wished first")
    eq(#ns.Loot("DM", "wish"), 1)
    eq(#ns.Loot("DM", "all", "rhahk"), 1, "found by the boss")
    eq(ns.WishCount(), 1)
    ns.SetWish(872, false)
    eq(#ns.Loot("DM", "wish"), 0)
    local where = ns.DropsOf(5193)
    eq(where[1].boss, "Edwin VanCleef"); eq(where[1].pct, 18.2)
    eq(GulliDungeonJournal.DropsOf(5193)[1].key, "DM", "for Gulli Tooltip")
    assert(type(GulliDungeonJournal.Name("DM")) == "string", "the dungeon's name by its key")
    eq(GulliDungeonJournal.Name("NOPE"), nil)
    eq(GulliDungeonJournal.Wished(5193), false)
    ns.SetWish(5193, true)
    eq(GulliDungeonJournal.Wished(5193), true)
    ns.SetWish(5193, false)
end)

test("the journal data: bosses in the order of the way, the skull boss at level 0, no world drops", function()
    Fake({})
    local ns = Load()
    local dm = ns.Data.boss.DM
    assert(dm and #dm >= 8, "the Deadmines has its bosses")
    eq(dm[1][2], "Rhahk'Zor", "the first boss first")
    local names = {}
    for _, b in ipairs(ns.Bosses("DM")) do names[#names + 1] = b.name end
    eq(names[#names], "Miner Johnson", "the rare comes last")
    eq(names[#names - 2], "Edwin VanCleef", "VanCleef on his ship")
    eq(names[#names - 1], "Cookie", "the cook comes after him, before the rares")
    local zf = ns.Bosses("ZF")
    eq(zf[1].name, "Theka the Martyr", "not Sergeant Bly, the lowest level")
    eq(zf[10].name, "Chief Ukorz Sandscalp", "the last boss last")
    eq(zf[11].rare, true)
    eq(ns.Data.walk.ZF, true, "every boss has its place on the way")
    local wings = {}
    for _, b in ipairs(ns.Bosses("SM")) do if not b.rare and wings[#wings] ~= b.wing then wings[#wings + 1] = b.wing end end
    eq(table.concat(wings, " "), "GRAVEYARD LIBRARY ARMORY CATHEDRAL ", "the monastery wing by wing")
    local L = ns.L
    for key, list in pairs(ns.Data.boss) do
        for _, b in ipairs(list) do
            assert(b[10] == "" or L["WING_" .. b[10]], key .. ": a wing without a name: " .. tostring(b[10]))
            assert(#b[8] <= 6, key .. ": more abilities than the page shows")
            for _, sp in ipairs(b[8]) do assert(sp ~= 5101 and sp ~= 13496 and sp ~= 15571, "Dazed is no boss spell") end
            for _, l in ipairs(b[9]) do assert(l[2] >= 2, key .. ": " .. b[2] .. " lists a white item") end
        end
    end
    for key, zone in pairs(ns.Data.zone) do
        local boss = {}
        for _, b in ipairs(ns.Data.boss[key] or {}) do for _, l in ipairs(b[9]) do boss[l[1]] = true end end
        for _, z in ipairs(zone) do assert(not boss[z[1]], key .. ": a boss drop among the mobs' loot") end
    end
    for key, list in pairs(ns.Data.boss) do
        local known = false
        for _, d in ipairs(ns.Data.dungeons) do if d[1] == key then known = true end end
        assert(known, key .. " is a DungeonPrep dungeon")
        local seen = {}
        for _, b in ipairs(list) do
            assert(not seen[b[2]], key .. ": " .. b[2] .. " is listed twice")
            seen[b[2]] = true
            for _, l in ipairs(b[9]) do
                assert(l[1] ~= 1210 and l[1] ~= 7909, key .. ": " .. b[2] .. " has a world drop")
                assert(l[3] >= 1 and l[3] <= 100, key .. ": a chance out of range")
            end
            for _, s in ipairs(b[8]) do assert(s ~= 1604, "Dazed is no boss spell") end
        end
    end
    eq(ns.Data.boss.THANES[1][4], 0, "a Forever boss of skull level")
end)

-- A corpse with these items: { { link, quality } }, from one creature GUID.
local function corpse(guid, loot)
    GetNumLootItems = function() return #loot end
    GetLootSlotLink = function(i) return loot[i][1] end
    GetLootSlotInfo = function(i) return "icon", "name", 1, nil, loot[i][2] end
    GetLootSourceInfo = function() return guid, 1 end
end

test("own drops: kills count once per corpse, chances take over after 10, unknown loot is added", function()
    local W = Fake({})
    local ns = Load()
    journal(ns)
    for i = 1, 10 do
        corpse("Creature-0-1-2-3-639-" .. i, { { "|Hitem:5193::|h", 3 }, { "|Hitem:9999::|h", 2 } })
        W.Fire("LOOT_READY")
        if i == 1 then W.Fire("LOOT_READY") end
    end
    eq(ns.Kills(639), 10, "the same corpse twice counts once")
    local b = ns.Bosses("DM")[1]
    local by = {}
    for _, l in ipairs(b.loot) do by[l.item] = l end
    eq(by[5193].pct, 100); eq(by[5193].own, true, "your own chance after 10 kills")
    eq(by[9999].seen, true, "loot the table lacks is added")
    corpse("Creature-0-1-2-3-12345-1", { { "|Hitem:5193::|h", 3 } })
    W.Fire("LOOT_READY")
    eq(ns.Kills(12345), 0, "a mob that is no boss is not counted")
    ns.Set("learn", false)
    corpse("Creature-0-1-2-3-644-1", { { "|Hitem:872::|h", 3 } })
    W.Fire("LOOT_READY")
    eq(ns.Kills(644), 0, "the switch stops the counting")
end)

test("a wished item that drops: chat, a sound and the hub's feed, unless switched off", function()
    local W = Fake({})
    local ns = Load()
    journal(ns)
    local notes = {}
    GulliToolkit = { Notify = function(_, text) notes[#notes + 1] = text end }
    ns.SetWish(872, true)
    corpse("Creature-0-1-2-3-644-1", { { "|Hitem:872::|h[Rockslicer]", 3 } })
    W.Fire("LOOT_READY")
    eq(#notes, 1)
    assert(W.printed[1]:find("Rockslicer", 1, true), W.printed[1])
    ns.Set("wishAlert", false)
    corpse("Creature-0-1-2-3-644-2", { { "|Hitem:872::|h[Rockslicer]", 3 } })
    W.Fire("LOOT_READY")
    eq(#notes, 1, "the switch stops the alert")
    GulliToolkit = nil
end)

test("entering a dungeon with quests not taken: one warning per entry, and the journal opens on it", function()
    local W = Fake({ level = 18, active = { [168] = true }, instance = "party" })
    GetInstanceInfo = function() return "The Deadmines" end
    local ns = Load()
    W.Fire("PLAYER_ENTERING_WORLD")
    eq(ns.selected, "DM")
    local n = #W.printed
    assert(n >= 1 and W.printed[n]:find("The Deadmines", 1, true), "warned")
    W.Fire("ZONE_CHANGED_NEW_AREA")
    eq(#W.printed, n, "only once per entry")
    W.instance = "none"; W.Fire("ZONE_CHANGED_NEW_AREA")
    W.printed = {}
    ns.Set("warnEnter", false)
    W.instance = "party"; W.Fire("ZONE_CHANGED_NEW_AREA")
    for _, l in ipairs(W.printed) do assert(not l:find("did not take", 1, true), "the switch stops the warning") end
    GetInstanceInfo = nil
end)

test("the guide pins the first stop, then the next after a quest is taken, and ends at the entrance", function()
    local W = Fake({ level = 18, areas = { [1519] = "Stormwind City", [40] = "Westfall" },
        map = { best = 1453, maps = { [1415] = { "Eastern Kingdoms", 2 }, [1453] = { "Stormwind City", 3, 1415 },
                                      [1436] = { "Westfall", 3, 1415 } }, pos = { 0.5, 0.5 } } })
    local ns = Load()
    eq(ns.StartGuide("DM"), true)
    eq(#W.pins, 1, "the first stop")
    local first = ns.guide.last
    local take = ns.Quests("DM", 18).take
    for _, q in ipairs(take) do
        if (q.who .. "@" .. q.area) == first then W.active[q.id] = true end
    end
    W.Fire("QUEST_ACCEPTED")
    assert(#W.pins >= 2, "the pin moved on")
    for _ = 1, 10 do
        for _, q in ipairs(ns.Quests("DM", 18).take) do W.active[q.id] = true end
        W.Fire("QUEST_ACCEPTED")
    end
    eq(ns.guide, nil, "done at the entrance")
end)

test("Lead me with only quests in the log: who takes back a finished one, then the entrance", function()
    local W = Fake({ level = 18, areas = { [1519] = "Stormwind City", [40] = "Westfall" },
        map = { best = 1453, maps = { [1415] = { "Eastern Kingdoms", 2 }, [1453] = { "Stormwind City", 3, 1415 },
                                      [1436] = { "Westfall", 3, 1415 } }, pos = { 0.5, 0.5 } } })
    local ns = Load()
    for _, q in ipairs(ns.Quests("DM", 18).take) do W.active[q.id] = true end
    local c = ns.Counts("DM", 18)
    eq(c.take, 0); assert(c.log > 0, "quests in the log")
    W.complete[167] = true
    eq(ns.StartGuide("DM"), true, "nothing to take, still something to lead to")
    assert(ns.guide and ns.guide.stop.turnin, "the first pin is a hand-in")
    eq(ns.guide.stop.who, "Wilder Thistlenettle")
    W.active[167], W.complete[167], W.done[167] = nil, nil, true
    W.Fire("QUEST_TURNED_IN")
    eq(ns.guide, nil, "then the entrance, and the guide is done")
end)

test("kills: how many bosses are down, the list's headers, the model of the boss the page opens on", function()
    local W = Fake({ level = 20, areas = AREAS, map = { best = 1454, maps = MAPS, pos = { 0.5, 0.5 } } })
    local ns = Load()
    journal(ns)
    ns.db.kills = { [639] = 2, [596] = 1 }
    local killed, all = ns.BossProgress("DM")
    eq(killed, 1); eq(all, 2, "the rare is no boss")
    ns.selected = "DM"
    local items = ns.BossItems(ns.Bosses("DM"))
    eq(#items, 5, "two bosses and a rare under two headers")
    eq(items[1].header, true); eq(items[1].text, ns.L.TAB_BOSSES)
    eq(items[4].rare, true, "the rares have their own header")
    eq(items[5].b.name, "Brainwashed Noble")
    ns.Data.boss.DM[1][10], ns.Data.boss.DM[2][10] = "EAST", "WEST"
    items = ns.BossItems(ns.Bosses("DM"))
    eq(items[1].text, ns.L.WING_EAST); eq(items[3].text, ns.L.WING_WEST, "a header per wing")
    -- The page opens on the first boss: its model comes a moment later, not with the window.
    W.timers = {}
    SlashCmdList.GULLIDUNGEONPREP("dm")
    ns.ShowTab(1)
    eq(ns.modelBoss, nil, "no model while the window opens")
    W.RunTimers()
    eq(ns.modelBoss, 639, "then the model of the boss shown")
end)

test("the Loot page: the mobs' drops without white and quest items, the class's loot boss by boss", function()
    Fake({ level = 20, items = {
        [5193] = { "Cape of the Brotherhood", 3, 24, "INVTYPE_CLOAK", 4, 1 },
        [872] = { "Rockslicer", 3, 24, "INVTYPE_2HWEAPON", 2, 1 },
        [100] = { "Green Belt", 2, 20, "INVTYPE_WAIST", 4, 1 },
        [101] = { "Troll Temper", 1, 1, "", 12, 0 },
        [102] = { "Quest Trophy", 2, 1, "", 12, 0 },
    } })
    local instant = C_Item.GetItemInfoInstant
    C_Item.GetItemInfoInstant = function(id)
        if id == 101 or id == 102 then return id, "", "", "", 1, 12, 0 end
        return instant(id)
    end
    local ns = Load()
    journal(ns)
    ns.Data.zone = { DM = { { 100, 2 }, { 101, 0 }, { 102, 2 }, { 103, 0 } } }
    local mobs = ns.Loot("DM", "mobs")
    eq(#mobs, 1, "no white item, no quest item, nothing the game does not know yet")
    eq(mobs[1].item, 100); eq(mobs[1].zone, true)
    local mine = ns.Loot("DM", "mine")
    eq(mine[1].npc, 639, "boss by boss in their order")
    eq(mine[1].bossN, 1)
    eq(mine[#mine].rare, true, "the rare's loot last")
    ns.SetWish(100, true)
    local wish = ns.Loot("DM", "wish")
    eq(#wish, 1, "a wished drop of the mobs is on the wishlist too")
    eq(#ns.Loot("DM", "mobs", "belt"), 1); eq(#ns.Loot("DM", "mobs", "cape"), 0, "the search narrows it")
    SlashCmdList.GULLIDUNGEONPREP("dm")
    for _, f in ipairs({ "mobs", "mine", "wish" }) do ns.lootFilter = f; ns.ShowTab(2); ns.Refresh() end
end)

test("notes on a boss and a quest are kept, trimmed and short", function()
    Fake({})
    local ns = Load()
    ns.SetNote("n639", "  kill adds first  ")
    eq(ns.Note("n639"), "kill adds first")
    ns.SetNote("q168", string.rep("x", 400))
    eq(#ns.Note("q168"), 300)
    ns.SetNote("n639", "")
    eq(ns.Note("n639"), "")
end)

test("the journal window: every tab with and without boss data", function()
    Fake({ level = 20, areas = AREAS, map = { best = 1454, maps = MAPS, pos = { 0.5, 0.5 } } })
    local ns = Load()
    journal(ns)
    SlashCmdList.GULLIDUNGEONPREP("dm")
    for i = 1, 4 do ns.ShowTab(i); ns.Refresh() end
    ns.boss = 644
    ns.ShowTab(1); ns.Refresh()
    ns.selected = "RFC"
    ns.ShowTab(1); ns.Refresh()
    ns.ShowTab(2); ns.Refresh()
    ns.lootFilter = "wish"; ns.Refresh()
end)

test("dungeon pictures: the loading screen, then the journal banner, then ours", function()
    Fake({})
    local ns = Load()
    local b = ns.Banners("RFC", 2.6)
    eq(b[1][1], 131862)
    eq(b[2][1], "Interface\\EncounterJournal\\UI-EJ-DUNGEONBUTTON-RagefireChasm")
    _G.EJ_GetInstanceInfo = function(id) if id == 226 then return "Ragefire Chasm", "", 1, 4242 end end
    eq(ns.Banners("RFC")[2][1], 4242)
    _G.EJ_GetInstanceInfo = function() error("no journal") end
    eq(ns.Banners("SFK")[2][1], "Interface\\EncounterJournal\\UI-EJ-DUNGEONBUTTON-ShadowfangKeep")
    _G.EJ_GetInstanceInfo = nil
    local own = ns.Banners("THANES", 2.6)
    eq(own[1][1], 7963781)
    eq(#own, 2)
    eq(own[2][1], "Interface\\AddOns\\Gulli-DungeonPrep\\Banners\\THANES")
    -- The band keeps the screen's shape and stays inside its picture.
    local function inside(key, aspect, top, bottom, ratio)
        local tc = ns.LoadingCoords(key, aspect)
        eq(tc[1], 0); eq(tc[2], 1)
        assert(tc[3] >= top - 1e-9 and tc[4] <= bottom + 1e-9, key .. " inside the picture")
        assert(math.abs(ratio / (tc[4] - tc[3]) - aspect) < 0.01, key .. " keeps the aspect")
    end
    inside("ZF", 2.6, 0.17, 0.80, 4 / 3)
    inside("BFD", 2.8, 0.17, 0.80, 4 / 3)
    inside("KROLDOK", 2.6, 266 / 1684, 1418 / 1684, 2992 / 1684)
    -- A band wider than the picture shows the whole picture.
    local tall = ns.LoadingCoords("ALCAZ", 1.5)
    assert(math.abs(tall[3] - 266 / 1684) < 1e-9 and math.abs(tall[4] - 1418 / 1684) < 1e-9)
    -- Every dungeon has its loading screen, and ours ships with the addon for Forever's own.
    for _, d in ipairs(ns.Data.dungeons) do
        local key = d[1]
        assert(ns.LOADING[key], "a loading screen for " .. key)
        assert(ns.ART[key] or ns.OWN_BANNERS[key], "a second picture for " .. key)
        if ns.OWN_BANNERS[key] then
            local f = io.open("Gulli-DungeonPrep/Banners/" .. key .. ".tga", "rb")
            assert(f, "Banners/" .. key .. ".tga is there")
            local head = f:read(18)
            f:close()
            eq(head:byte(3), 2, "an uncompressed TGA")
            eq(head:byte(13) + head:byte(14) * 256, 512)
            eq(head:byte(15) + head:byte(16) * 256, 256)
        end
    end
    eq(#ns.Portraits("THANES"), 0)
    eq(ns.Portraits("ZF")[2], "Interface\\LFGFrame\\LFGIcon-ZulFarak")
    for key in pairs(ns.ART) do assert(ns.ICONS[key], "an icon behind the picture of " .. key) end
end)

test("the journal opens on the dungeon grid, those for the level first; a tile opens the dungeon", function()
    Fake({ level = 20, areas = AREAS, map = { best = 1454, maps = MAPS, pos = { 0.5, 0.5 } } })
    local ns = Load()
    journal(ns)
    ns.Toggle()
    eq(ns.home, true, "the grid first")
    local order = ns.GridOrder(ns.Dungeons(20))
    assert(order[1].fits, "a dungeon for the level comes first")
    local seenOther = false
    for _, d in ipairs(order) do
        if not d.fits then seenOther = true end
        assert(not (seenOther and d.fits), "every fitting dungeon before the others")
    end
    SlashCmdList.GULLIDUNGEONPREP("dm")
    eq(ns.home, false, "a slash key opens the dungeon")
    eq(ns.selected, "DM")
end)

test("a quest card lists its chain's steps under each other; a single quest has none", function()
    Fake({ level = 20, areas = AREAS, map = { best = 1454, maps = MAPS, pos = { 0.5, 0.5 } } })
    local ns = Load()
    journal(ns)
    ns.Toggle()
    local steps = ns.CardSteps({ quest = { id = 166 } })
    assert(steps and #steps == 7, "The Defias Brotherhood has seven steps")
    eq(steps[1].n, 1)
    assert(steps[7].this, "the card's own quest is marked")
    eq(ns.CardSteps({ quest = { id = 999999 } }), nil, "no chain, no steps")
    -- The quest list draws the cards with their steps.
    SlashCmdList.GULLIDUNGEONPREP("dm")
    ns.filter = "all"
    ns.Refresh()
end)

test("a quest started by an item that drops in the dungeon belongs to it (Krol'dok Moulding)", function()
    Fake({})
    local ns = Load()
    local function has(key, id)
        for _, x in ipairs(ns.Data.byDungeon[key]) do if x == id then return true end end
    end
    assert(has("KROLDOK", 94973), "the Horde Krol'dok Moulding, from Tunk's drop")
    assert(has("KROLDOK", 94980), "the Alliance one")
    eq(table.concat(ns.Data.chain[94973], ","), "94973,94974")
end)

test("AllTheThings fills the gaps: its dungeon quests join, its faction wins for Forever quests", function()
    Fake({ level = 15, raceID = 2, faction = "Horde", className = "WARRIOR" })
    local ns = Load()
    local q = ns.Quests("THANES", 15)
    eq(ids(q.take), "96395,96403", "a Horde player gets An Ancient Grudge and Important Heirlooms")
    eq(ns.Data.quest[96403][11], "", "Important Heirlooms is for both factions")
    eq(ns.Data.quest[96403][4], 0)
    local function has(key, id)
        for _, x in ipairs(ns.Data.byDungeon[key]) do if x == id then return true end end
    end
    assert(has("KROLDOK", 94969), "Krol'dok No More!, which only ATT ties to the dungeon")
    assert(has("ALCAZ", 96376), "State Secrets")
    assert(not has("GNOMER", 2951), "a Sparklematic exchange stays out")
end)

test("levelling chains: only the guide's chains while mainOnly is on, every quest without it", function()
    Fake({ level = 58, raceID = 2, faction = "Horde", className = "WARRIOR" })
    local ns = Load()
    eq(ns.Get("mainOnly"), true, "on by default")
    local function all(q)
        local t = {}
        for _, l in ipairs({ q.log, q.take, q.later, q.hidden }) do
            for _, x in ipairs(l) do
                t[x.id] = x
                for _, m in ipairs(x.members or {}) do t[m] = t[m] or x end
            end
        end
        return t
    end
    local q = ns.Quests("SCHOLO", 58)
    local shown = all(q)
    for _, id in ipairs({ 5096, 5341, 5466, 5529, 4771 }) do
        assert(shown[id], "a Horde chain step: " .. id)
        eq(shown[id].main, true)
    end
    assert(not shown[5343], "the Alliance Barov Family Fortune is not for the Horde")
    assert(q.more > 0, "other dungeon quests are left out")
    local main = ns.MainSet("SCHOLO")
    for id in pairs(shown) do assert(main[id], "only chain quests: " .. id) end
    ns.Set("mainOnly", false)
    local every = ns.Quests("SCHOLO", 58)
    eq(every.more, 0)
    local n = 0
    for _ in pairs(all(every)) do n = n + 1 end
    local m = 0
    for _ in pairs(shown) do m = m + 1 end
    eq(n, m + q.more, "every quest once the switch is off")
    eq(ns.Counts("SCHOLO", 58).take, #every.take, "the counts follow the switch")
    -- A dungeon whose guide the data lacks shows every quest.
    ns.Set("mainOnly", true)
    ns.Data.main.SHAPERS = nil
    eq(ns.Quests("SHAPERS", 60).more, 0)
end)

test("the tracker: ready quests first, objectives, quests to take; Lead me shows it, the cross hides it", function()
    Fake({ level = 33, raceID = 2, faction = "Horde", className = "HUNTER", areas = AREAS,
           map = { best = 1454, maps = MAPS, pos = { 0.5, 0.5 } },
           active = { [2841] = true }, complete = { [2841] = true } })
    local ns = Load()
    local items, ready, total = ns.TrackerItems("GNOMER", 33)
    eq(items[1].id, 2841)
    eq(items[1].state, "ready")
    eq(ready, 1)
    assert(total >= #items and #items <= ns.TRACK_MAX, "at most TRACK_MAX rows")
    local states = {}
    for _, it in ipairs(items) do states[it.state] = true end
    assert(states.take, "quests to take are listed")
    for i = 2, #items do
        local order = { ready = 1, log = 2, take = 3, chain = 4 }
        assert(order[items[i - 1].state] <= order[items[i].state], "ready, log, take, chain")
    end
    -- An unfinished quest lists its objectives.
    W.complete[2841] = nil
    items = ns.TrackerItems("GNOMER", 33)
    eq(items[1].state, "log")
    -- Lead me shows the tracker and keeps it over a reload; the cross hides it.
    ns.StartGuide("GNOMER")
    eq(GulliDungeonPrepDB.tracker, "GNOMER")
    assert(ns.TrackerFrame():IsShown(), "the tracker shows")
    ns.OpenTracked("GNOMER", 2841)
    eq(ns.selected, "GNOMER")
    eq(ns.openQuest, 2841)
    ns.HideTracker()
    eq(GulliDungeonPrepDB.tracker, nil)
    assert(not ns.TrackerFrame():IsShown(), "the cross hides it")
    -- In the Unlock mode it shows to be placed even with nothing tracked; after it, it hides.
    ns.MoveTracker(true)
    assert(ns.TrackerFrame():IsShown(), "in the Unlock mode, it shows")
    ns.MoveTracker(false)
    assert(not ns.TrackerFrame():IsShown(), "with nothing tracked, it hides")
end)

test("the tracker starts hidden, once also for older saves; the hub's switch shows it", function()
    Fake({ level = 33, db = { tracker = "GNOMER", trackerLocked = false } })
    local got
    GulliToolkit = { Register = function(m) got = m end }
    local ns = Load()
    GulliToolkit = nil
    eq(GulliDungeonPrepDB.tracker, nil, "hidden once"); eq(GulliDungeonPrepDB.trackerLocked, nil)
    local fr = got.frames[1]
    eq(fr.get(), false)
    assert(fr.frame(), "the hub gets the tracker")
    assert(not fr.frame():IsShown(), "built hidden")
    fr.set(true)
    eq(fr.get(), true)
    assert(fr.frame():IsShown(), "the switch shows it")
    fr.set(false)
    eq(GulliDungeonPrepDB.tracker, nil)
end)

test("chains: one card per chain, at the step to do now; the tracker opens one to show its steps", function()
    Fake({ level = 18, done = { [65] = true, [132] = true, [135] = true }, active = { [141] = true } })
    local ns = Load()
    local q = ns.Quests("DM", 18)
    local card
    for _, x in ipairs(q.log) do if x.head and x.head.id == 166 then card = x end end
    assert(card, "the Defias chain is in the log at its step in the log")
    eq(card.id, 141)
    eq(#card.members, 7)
    for _, l in ipairs({ q.take, q.later, q.finished }) do
        for _, x in ipairs(l) do assert(not (x.head and x.head.id == 166), "the chain shows once") end
    end
    local items = ns.TrackerItems("DM", 18)
    local row
    for _, it in ipairs(items) do if it.key == 166 then row = it end end
    assert(row, "the chain is one tracker row")
    eq(row.id, 141, "a click on the map or the journal goes to the step to do now")
    eq(row.name, "The Defias Brotherhood")
    eq(row.lines[1].text, "Step 4 of 7:  " .. card.name, "which step the chain is at")
    eq(#row.steps, 7)
    ns.StartGuide("DM")
    eq(ns.TrackerOpen(166), false)
    ns.ToggleTracked(166)
    eq(ns.TrackerOpen(166), true, "a click opens the row to show every step")
    ns.ToggleTracked(166)
    eq(ns.TrackerOpen(166), false)
    -- The whole chain done: one done chain.
    W.done = { [65] = true, [132] = true, [135] = true, [141] = true, [142] = true, [155] = true, [166] = true }
    W.active = {}
    local finished = 0
    for _, x in ipairs(ns.Quests("DM", 18).finished) do if x.head and x.head.id == 166 then finished = finished + 1 end end
    eq(finished, 1)
end)

test("a pin button near the giver targets and marks them, out of combat only", function()
    Fake({})
    local ns = Load()
    local target, mark = nil, nil
    UnitExists = function(u) return u == "target" and target ~= nil end
    local name = UnitName
    UnitName = function(u) if u == "target" then return target end return name(u) end
    GetRaidTargetIndex = function() return mark end
    SetRaidTarget = function(_, i) mark = (mark ~= i) and i or nil end
    eq(ns.MarkTarget("Gryan Stoutmantle"), false, "nobody targeted")
    target = "Defias Pillager"
    eq(ns.MarkTarget("Gryan Stoutmantle"), false, "another target is not marked")
    eq(mark, nil)
    target = "Gryan Stoutmantle"
    eq(ns.MarkTarget("Gryan Stoutmantle"), true)
    eq(mark, 3, "a diamond")
    ns.MarkTarget("Gryan Stoutmantle")
    eq(mark, 3, "a second click keeps the mark")
    issecretvalue = function() return true end
    mark = nil
    eq(ns.MarkTarget("Gryan Stoutmantle"), false, "a secret name is not compared")
    issecretvalue = nil
    -- The secure button over the pin: its macro targets by name, its click pins and marks.
    local pinned
    local btn = W.stub()
    btn.GetCenter = function() return 100, 200 end
    btn.GetEffectiveScale = function() return 1 end
    btn:SetScript("OnClick", function() pinned = true end)
    UIParent.GetEffectiveScale = function() return 1 end
    W.combat = true
    eq(ns.TargetOver(btn, "Gryan Stoutmantle"), false, "never in combat")
    W.combat = false
    eq(ns.TargetOver(btn, "Gryan Stoutmantle"), true)
    local o = ns.TargetOverlay()
    eq(o.who, "Gryan Stoutmantle", "the macro targets by name")
    mark = nil
    o:GetScript("PostClick")(o, "LeftButton", true)
    eq(pinned, nil, "nothing on the press")
    o:GetScript("PostClick")(o, "LeftButton", false)
    eq(pinned, true, "the pin's own click runs")
    eq(mark, 3)
end)

W.finish()
