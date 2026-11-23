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

test("Show on map of a quest's page pins and opens the world map", function()
    local W = Fake({ areas = AREAS, map = { maps = MAPS }, level = 33, raceID = 2, faction = "Horde" })
    local opened
    C_Map.OpenWorldMap = function(id) opened = id end
    local ns = Load()
    ns.home, ns.selected = false, "GNOMER"
    ns.Toggle(); ns.ShowTab(3); ns.OpenQuest(2841)
    local d = ns.DetailFrame()
    d.startMap:GetScript("OnClick")(d.startMap)
    eq(#W.pins, 1, "Nogg is pinned")
    eq(opened, 1454, "and the map opens on Orgrimmar")
    opened = nil
    d.turninMap:GetScript("OnClick")(d.turninMap)
    eq(opened, 1454, "the turn-in too")
    OpenWorldMap = nil
end)

test("the map opened from the window is not hidden by it: the window lies under the map", function()
    Fake({ areas = AREAS, map = { maps = MAPS }, level = 33, raceID = 2, faction = "Horde" })
    C_Map.OpenWorldMap = function() end
    WorldMapFrame = CreateFrame("Frame")
    local ns = Load()
    ns.home, ns.selected = false, "GNOMER"
    ns.Toggle(); ns.ShowTab(3); ns.OpenQuest(2841)
    local w, strata = ns.Window(), "DIALOG"
    rawset(w, "GetFrameStrata", function() return strata end)
    rawset(w, "SetFrameStrata", function(_, s) strata = s end)
    rawset(w, "GetParent", function() return UIParent end)
    local d = ns.DetailFrame()
    d.startMap:GetScript("OnClick")(d.startMap)
    eq(strata, "LOW", "under the map while it shows")
    WorldMapFrame:GetScript("OnHide")(WorldMapFrame)
    eq(strata, "DIALOG", "and back up when the map closes")
    OpenWorldMap, WorldMapFrame = nil, nil
end)

test("the tracker's map button pins and opens the world map on the pin's zone", function()
    local W = Fake({ areas = AREAS, map = { maps = MAPS } })
    local opened
    C_Map.OpenWorldMap = function(id) opened = id end
    local tainted
    OpenWorldMap = function(id) tainted = id end -- the addon's own call taints the map's pins
    local ns = Load()
    eq(ns.PinAt("Nogg", 1637, 76, 25), true)
    eq(opened, nil, "a pin alone leaves the map closed")
    eq(ns.PinAt("Nogg", 1637, 76, 25, true), true)
    eq(opened, 1454, "the map opens on Orgrimmar")
    opened, W.combat = nil, true
    ns.PinAt("Nogg", 1637, 76, 25, true)
    eq(opened, nil, "never in combat")
    eq(tainted, nil, "the game opens the map from its own event")
    W.combat, C_Map.OpenWorldMap = false, nil
    ns.PinAt("Nogg", 1637, 76, 25, true)
    eq(tainted, 1454, "a client without C_Map.OpenWorldMap still opens it")
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
    eq(#W.printed, 1, "the hand-in line; the pin itself says nothing in chat")
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
    local _, _, stat = reg.summary()
    eq(stat.value, 5, "the hub's tile: the quests to take as its number")
    eq(stat.tone, "warn")
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
            for _, l in ipairs(b[9]) do
                -- Quality 0 with no chance: an item known only from AllTheThings, the game says.
                assert(l[2] >= 2 or (l[2] == 0 and l[3] == 0), key .. ": " .. b[2] .. " lists a white item")
            end
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
                assert((l[3] >= 1 or (l[2] == 0 and l[3] == 0)) and l[3] <= 100, key .. ": a chance out of range")
            end
            for _, s in ipairs(b[8]) do assert(s ~= 1604, "Dazed is no boss spell") end
        end
    end
    eq(ns.Data.boss.THANES[1][4], 16, "a Forever boss has the level the game shows")
    -- Dungeons Wowhead's zone pages had no NPC of take their bosses from AllTheThings.
    for _, key in ipairs({ "DALARAN", "KROLDOK", "SHAPERS" }) do
        assert(#(ns.Data.boss[key] or {}) >= 6, key .. " has its bosses")
    end
    eq(ns.Data.boss.DALARAN[1][2], "Atrexis the Grave Knight", "Dalaran in the order of the way")
    local kd = ns.Bosses("KROLDOK")
    eq(kd[#kd].name, "Kroog", "the rare last")
    eq(kd[#kd].rare, true)
    for _, b in ipairs(kd) do if b.name == "Overlord Mugg" then eq(b.min, 45) end end
    eq(ns.Data.walk.SHAPERS, true)
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

test("the guide keeps its stop while the player walks nearer to another one", function()
    local W = Fake({ level = 18, areas = { [1519] = "Stormwind City", [40] = "Westfall" },
        map = { best = 1453, maps = { [1415] = { "Eastern Kingdoms", 2 }, [1453] = { "Stormwind City", 3, 1415 },
                                      [1436] = { "Westfall", 3, 1415 } }, pos = { 0.5, 0.5 } } })
    local ns = Load()
    eq(ns.StartGuide("DM"), true)
    local first, pins = ns.guide.last, #W.pins
    local route = ns.Route
    ns.Route = function(...)
        local out, rev = route(...), {}
        for i = #out, 1, -1 do rev[#rev + 1] = out[i] end
        return rev
    end
    assert(#route(ns.Quests("DM", 18).take, ns.Here(), ns.Dungeons(18)[1]) > 1, "more than one stop")
    W.Fire("QUEST_ACCEPTED")
    eq(ns.guide.last, first, "the same stop")
    eq(#W.pins, pins, "no new pin")
    eq(#W.printed, 0, "and nothing in chat")
    ns.Route = route
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
    for i = 1, 5 do ns.ShowTab(i); ns.Refresh() end
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

test("State Secrets waits for the Document Box of More Valuable Than Gold (ATT's sourceQuest)", function()
    Fake({ level = 52, raceID = 2, faction = "Horde", className = "PRIEST" })
    local ns = Load()
    local d = ns.Data.quest
    eq(table.concat(d[96376][9], ","), "96337", "the Horde copy needs More Valuable Than Gold")
    eq(table.concat(d[96377][9], ","), "96337", "the Alliance copy too")
    eq(table.concat(d[96376][10], ","), "96377,96379", "the Steamwheedle and Alliance copies close it")
    eq(d[96335][6], "Mason Connery", "The Man in the Iron Chains: Mason Connery in the prison")
    eq(d[96335][3], 48, "ATT's level where QuestieDB has none")
    assert(ns.Data.inside.ALCAZ[96335]:find("t"), "taken inside the dungeon")
    eq(table.concat(d[95284][9], ","), "95283", "The Elite of the Elite after The Missing Kor'kron (ATT zone file)")
    local q = ns.Quests("ALCAZ", 52)
    local found
    for _, l in ipairs({ "log", "take", "later" }) do
        for _, e in ipairs(q[l]) do
            if e.id == 96376 then error("State Secrets is its own card: " .. l) end
            if e.head and e.head.id == 96376 then found = { list = l, e = e } end
        end
    end
    assert(found, "the Mason Connery steps and State Secrets are one card")
    eq(found.e.id, 96335, "the step to do now: The Man in the Iron Chains")
    eq(#found.e.members, 3)
    -- With the Document Box quest done, Nazgrel offers it.
    Fake({ level = 52, raceID = 2, faction = "Horde", className = "PRIEST", done = { [96335] = true, [96337] = true } })
    ns = Load()
    q = ns.Quests("ALCAZ", 52)
    local take
    for _, e in ipairs(q.take) do if e.id == 96376 then take = e end end
    assert(take, "can take State Secrets once More Valuable Than Gold is done")
    -- Before that, its own page says what it waits for.
    Fake({ level = 52, raceID = 2, faction = "Horde", className = "PRIEST" })
    ns = Load()
    local e = ns.Quest(96376, 53)
    eq(e.state, "later")
    eq(e.need and e.need.id, 96337)
end)

test("levelling chains: a quest the guides leave out comes in by hand (D.main, MAIN_EXTRA)", function()
    Fake({ level = 50, raceID = 2, faction = "Horde", className = "WARRIOR" })
    local ns = Load()
    eq(ns.Get("mainOnly"), true, "on by default")
    assert(ns.MainSet("MARA")[93404], "Rot and Regret is shown with Chains only")
    for key, ids in pairs({ RFD = { 93604 }, EXCAVATION = { 95737 }, KROLDOK = { 94969 },
        BLACKMAW = { 92065, 99187 }, DALARAN = { 92459, 97287 } }) do
        for _, id in ipairs(ids) do assert(ns.MainSet(key)[id], key .. ": " .. id .. " is a chain") end
    end
    local seen
    for _, l in ipairs({ "log", "take", "later", "hidden" }) do
        for _, x in ipairs(ns.Quests("MARA", 50)[l]) do
            if x.id == 93404 then seen = true end
            for _, m in ipairs(x.members or {}) do if m == 93404 then seen = true end end
        end
    end
    assert(seen, "Rot and Regret is in the Maraudon list")
end)

test("class quests: every class sees its own Sunken Temple quest with Chains only, and no other class's", function()
    -- classID -> its class quest of the temple (the guide leaves them to class guides).
    local ST = { [1] = 8425, [2] = 8418, [3] = 8232, [4] = 8236, [5] = 8257, [7] = 8413, [8] = 8253,
                 [9] = 8422, [11] = 9053 }
    local FILE = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", nil, "SHAMAN", "MAGE", "WARLOCK", nil, "DRUID" }
    for classID, id in pairs(ST) do
        Fake({ level = 52, raceID = 1, faction = "Alliance", classID = classID, className = FILE[classID] })
        local ns = Load()
        -- A quest for one faction only is checked on that faction.
        local side = ns.Data.quest[id][11]
        if side == "H" then
            Fake({ level = 52, raceID = 2, faction = "Horde", classID = classID, className = FILE[classID] })
            ns = Load()
        end
        eq(ns.Get("mainOnly"), true)
        assert(ns.MainSet("ST")[id], "a chain of the temple: " .. id)
        local seen = {}
        for _, l in ipairs({ "log", "take", "later", "hidden" }) do
            for _, x in ipairs(ns.Quests("ST", 52)[l]) do
                seen[x.id] = x
                for _, m in ipairs(x.members or {}) do seen[m] = x end
            end
        end
        assert(seen[id], FILE[classID] .. " sees " .. id)
        eq(seen[id].class, true, "marked as a class quest")
        for other, oid in pairs(ST) do
            if other ~= classID then assert(not seen[oid], FILE[classID] .. " does not see " .. oid) end
        end
    end
    -- Every class quest a dungeon lists is a chain of it, but the tier 0.5 set exchanges are not.
    Fake({ level = 60, raceID = 1, faction = "Alliance" })
    local ns = Load()
    for _, id in ipairs({ 1956, 80411, 82084, 81790, 7581, 7631, 7643, 7629, 7647, 8258, 97169, 7642 }) do
        local found
        for key in pairs(ns.Data.main) do if ns.MainSet(key)[id] then found = true end end
        assert(found, "a chain: " .. id)
    end
    for _, id in ipairs({ 8907, 8926, 8999, 8951, 97179 }) do
        for key in pairs(ns.Data.main) do assert(not ns.MainSet(key)[id], "a set exchange: " .. id) end
    end
    -- The Alliance Darkreaver Menace has its class from Wowhead (QuestieDB gives none).
    eq(ns.Data.quest[97169][5], 64, "shaman only")
end)

test("the tier 0.5 set: hidden while levelling, its own folded list at the top level", function()
    local function ids(q)
        local t = {}
        for _, l in ipairs({ q.log, q.take, q.later, q.hidden, q.finished }) do
            for _, x in ipairs(l) do
                t[x.id] = x
                for _, m in ipairs(x.members or {}) do t[m] = x end
            end
        end
        return t
    end
    for _, mainOnly in ipairs({ true, false }) do
        Fake({ level = 59, raceID = 1, faction = "Alliance", classID = 1, className = "WARRIOR" })
        local ns = Load()
        ns.Set("mainOnly", mainOnly)
        local setOf = ns.SetSet("STRAT")
        assert(setOf[8937], "Just Compensation is in the set chain")
        local q = ns.Quests("STRAT", 59)
        for id in pairs(ids(q)) do assert(not setOf[id], "no set quest while levelling: " .. id) end
        eq(#q.set.take + #q.set.later + #q.set.log, 0, "no set list below the top level")
        local before = ns.Quests("STRAT", 60)
        for id in pairs(ids(before)) do assert(not setOf[id], "never in the normal lists: " .. id) end
        local set = ids(before.set)
        local n = 0
        for id, x in pairs(set) do
            n = n + 1
            assert(setOf[id], "only set quests: " .. id)
            eq(x.set, true)
        end
        assert(n > 0, "the set list at the top level")
        -- Only the warrior's own pieces.
        for id in pairs(set) do
            local mask = ns.Data.quest[id][5]
            assert(mask == 0 or mask % 2 == 1, "a warrior quest: " .. id)
        end
        eq(ns.Counts("STRAT", 60).take, #before.take, "the counts leave the set out")
    end
end)

test("Ever After: WoW Forever's hidden quest in Blackrock Depths, inside, with its way there", function()
    Fake({ level = 50, raceID = 2, faction = "Horde", className = "WARRIOR" })
    local ns = Load()
    eq(ns.Get("mainOnly"), true)
    assert(ns.MainSet("BRD")[82062], "among the chains of Blackrock Depths")
    local found
    for _, x in ipairs(ns.Quests("BRD", 50).take) do if x.id == 82062 then found = x end end
    assert(found, "to take at level 50, for both factions")
    eq(found.who, "Rugged Traveler")
    local inside = ns.Inside("BRD", 82062)
    assert(inside.take and inside.turnin, "taken and handed in inside the dungeon")
    assert(ns.Data.tips[82062] and ns.Data.tips[82062].t, "the way to the ledge")
end)

test("Lost Thunderbrew Recipe: its work is in the Grim Guzzler, with the way to Hurley", function()
    Fake({ level = 55, raceID = 2, faction = "Horde", className = "WARRIOR", done = { [4133] = true } })
    local ns = Load()
    -- Hurley and his cronies have no spawns in the data: NPCS places them in the dungeon.
    for _, id in ipairs({ 4134, 4126 }) do
        assert(ns.Inside("BRD", id).work, id .. ": the recipe drops inside Blackrock Depths")
        assert(ns.Data.tips[id] and ns.Data.tips[id].d, id .. ": the kegs and Hurley")
    end
    -- INSIDE_WORK: work the data cannot place, marked by hand.
    assert(ns.Inside("BRS", 4735).work, "Egg Collection in the Rookery")
    assert(ns.Inside("ST", 3528).work, "The God Hakkar at the altar")
    assert(ns.Inside("ZF", 2770).work, "Gahz'rilla, summoned at the pool")
end)

test("Grark Lorkrub waits for KILL ON SIGHT: High Ranking Dark Iron Officials", function()
    local function find(q, id)
        for _, list in ipairs({ q.log, q.take, q.later }) do
            for _, x in ipairs(list) do
                if x.id == id then return x end
            end
        end
    end
    Fake({ level = 56, raceID = 2, faction = "Horde", className = "WARRIOR", done = { [4081] = true } })
    local ns = Load()
    -- ATT's quest before (QuestieDB has none); a breadcrumb never is one.
    eq(ns.Data.quest[4122][9][1], 4082)
    eq(#ns.Data.quest[2930][9], 0, "Castpipe's Task only sends the player on")
    local q = ns.Quests("BRD", 56)
    assert(not find(q, 4122), "one entry for the whole chain")
    local chain
    for _, x in ipairs(q.take) do
        for _, m in ipairs(x.members or {}) do if m == 4122 then chain = x end end
    end
    assert(chain, "the chain is to take")
    eq(chain.id, 4082, "the step to take now is the high ranking officials, not Grark")
    assert(ns.Data.tips[4122] and ns.Data.tips[4122].d, "the escort note")
end)

test("Lead me at the top level: the set quests in the log, the ones to take once the set began", function()
    local function has(list, id)
        for _, x in ipairs(list) do
            if x.id == id then return true end
            for _, m in ipairs(x.members or {}) do if m == id then return true end end
        end
    end
    Fake({ level = 59, raceID = 1, faction = "Alliance", classID = 1, className = "WARRIOR" })
    local ns = Load()
    local g = ns.GuideQuests("STRAT", 59)
    eq(#g.take, #ns.Quests("STRAT", 59).take, "nothing of the set while levelling")
    -- At 60, never started: the guide leaves the set's quests to take alone.
    Fake({ level = 60, raceID = 1, faction = "Alliance", classID = 1, className = "WARRIOR" })
    ns = Load()
    local q = ns.Quests("STRAT", 60)
    assert(#q.set.take > 0, "set quests to take at 60")
    local first = q.set.take[1].id
    g = ns.GuideQuests("STRAT", 60)
    assert(not has(g.take, first), "not led to a set nobody began")
    -- With its list open, Lead me and the tracker take them.
    ns.showSet = true
    g = ns.GuideQuests("STRAT", 60)
    assert(has(g.take, first), "led to the set once its list is open")
    local found
    for _, it in ipairs(select(1, ns.TrackerItems("STRAT", 60))) do if it.id == first then found = true end end
    local _, _, total = ns.TrackerItems("STRAT", 60)
    assert(found and total > 0, "the tracker has the set quest")
    ns.showSet = nil
    -- A set quest in the log: the guide follows the set, also with its list folded.
    Fake({ level = 60, raceID = 1, faction = "Alliance", classID = 1, className = "WARRIOR",
           active = { [first] = true } })
    ns = Load()
    q = ns.Quests("STRAT", 60)
    assert(#q.set.log > 0, "the set quest is in the log")
    g = ns.GuideQuests("STRAT", 60)
    assert(has(g.log, first), "the set quest in the log is led to")
    eq(ns.StartGuide("STRAT"), true, "Lead me starts on the set")
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
    local _, _, _, counts = ns.TrackerItems("GNOMER", 33)
    eq(total, #items, "every row is given: the panel scrolls")
    eq(counts.hand + counts.doing + counts.take + counts.later, total, "the groups add up to the total")
    eq(counts.hand, 1)
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

test("the tracker and the Chains tab: a fork, groups that add up, paging at a fixed size, lanes", function()
    Fake({ level = 54, raceID = 2, faction = "Horde", className = "WARRIOR", areas = AREAS,
           map = { best = 1454, maps = MAPS, pos = { 0.5, 0.5 } }, active = { [4134] = true } })
    local ns = Load()
    -- Disharmony of Flame opens three quests: the chain's next step and two side quests
    -- (The Last Element waits for it too, from ATT).
    local nexts = {}
    for _, n in ipairs(ns.Nexts(3906)) do nexts[n] = true end
    assert(nexts[3981] and nexts[3907] and nexts[7201], "the quests after Disharmony of Flame")
    local items, _, total, counts = ns.TrackerItems("BRD", 54)
    eq(counts.hand + counts.doing + counts.take + counts.later, total)
    local fork
    for _, it in ipairs(items) do
        assert(it.group and it.name, "a row knows its group")
        assert(not it.steps or (it.at and it.of), "a chain row knows its place")
        if it.id == 3906 then fork = it end
    end
    assert(fork, "the row is named by the quest to do now")
    -- Who to go to is an icon and a name, where an icon and the zone: no words such as "Take from".
    local tagged = ns.WhereTag({ who = "Thunderheart", area = 17 })
    assert(tagged:find(ns.WHO_ICON, 1, true) and tagged:find(ns.ZONE_ICON, 1, true), "both icons: " .. tagged)
    assert(tagged:find("Thunderheart", 1, true), "the name stays")
    eq(ns.WhereTag({ who = "", area = 0 }), "")
    assert(not ns.WhereTag({ who = "Thunderheart", area = 0 }):find(ns.ZONE_ICON, 1, true), "no zone, no zone icon")
    local takes = 0
    for _, it in ipairs(items) do
        if it.state == "take" and it.pin then
            takes = takes + 1
            assert(it.lines[1].text:find(ns.WHO_ICON, 1, true), "a take row names its giver by the icon: " .. it.lines[1].text)
        end
    end
    assert(takes > 0, "the list has quests to take")
    assert(ns.L.TR_TAKE == nil or ns.L.TR_TAKE == "TR_TAKE", "the words are gone")
    eq(fork.fork, 3)
    eq(fork.at, 1)
    assert(fork.goal and fork.goal ~= fork.name, "and names the chain's last quest as its goal")
    -- Its card: the step, the head of what it opens, the two quests (this chain's first), the rest.
    local rows = ns.TrackerCardRows(fork)
    eq(rows[1].step.id, 3906)
    eq(rows[2].opens, 3)
    eq(rows[3].open.id, 3981)
    assert(rows[3].open.main, "the chain's own next step is marked")
    local side = { [rows[4].open.id] = true, [rows[5].open.id] = true }
    assert(side[3907] and side[7201], "then the side quests")
    eq(rows[#rows].step.goal, true)
    -- A step before one in the log counts as done; more than three done steps fold into one line.
    W.active[3906], W.active[4134] = nil, nil
    W.active[4003] = true
    local long
    for _, it in ipairs(ns.TrackerItems("BRD", 54)) do if it.id == 4003 then long = it end end
    assert(long, "The Royal Rescue leads its chain")
    eq(long.steps[1].state, "done")
    local folded = ns.TrackerCardRows(long)
    assert(folded[1].folded and folded[1].folded >= 3, "the done steps fold")
    W.active[4003] = nil
    W.active[4134] = true
    -- The panel keeps its height and is always full: the list moves by pixels behind it. The
    -- wheel, the footer and the numbers on top move it, never past its ends.
    ns.ShowTracker("BRD")
    local f = ns.TrackerFrame()
    local h = f:GetHeight()
    local first, last, n, at, max = ns.TrackerView()
    eq(first, 1)
    eq(n, total)
    eq(at, 0)
    assert(last < total and max > 0, "more rows than fit")
    ns.TrackerScroll(1)
    eq(select(4, ns.TrackerView()), math.min(max, ns.TRACK_STEP), "one notch moves by pixels, not by a row")
    ns.TrackerScroll(-1)
    ns.TrackerNextPage()
    local first2 = ns.TrackerView()
    assert(first2 > 1 and first2 <= last + 1, "the first row that was cut off leads the next page")
    eq(f:GetHeight(), h, "the panel does not change its size")
    ns.TrackerScroll(1000)
    local _, lastEnd, _, atEnd = ns.TrackerView()
    eq(atEnd, max, "the list stops with its last row at the bottom: no empty room under it")
    eq(lastEnd, total)
    ns.TrackerNextPage()
    eq(select(4, ns.TrackerView()), 0, "after the end, the footer goes back to the top")
    ns.TrackerScroll(-100)
    eq((ns.TrackerView()), 1)
    ns.TrackerGoTo("later")
    local gf, gl = ns.TrackerView()
    assert(items[gf].group == "later" or gl == total, "the group is in view")
    -- A tooltip stands beside the panel, not over its rows.
    local point, rel = ns.TrackerTipPlace(f)
    assert((point == "TOPLEFT" or point == "TOPRIGHT") and rel == f, "the tooltip hangs on the panel's side")
    ns.HideTracker()
    -- The Chains tab: the side quest is a lane of its own, right under the chain it comes after.
    local map = ns.ChainMap("BRD", 54)
    eq(map.counts.take, counts.take)
    local branch
    for i, l in ipairs(map.lanes) do
        if l.from and l.from.id == 3906 then
            local above = map.lanes[i - 1]
            assert(above.steps[1].id == 3906 or (above.from and above.from.id == 3906),
                "it stands under its chain, or under another branch of it")
            if l.steps[1].id == 3907 then branch = l end
        end
    end
    assert(branch, "Disharmony of Fire branches from Disharmony of Flame")
    local seen, quests = {}, 0
    for _, l in ipairs(map.lanes) do
        for _, st in ipairs(l.steps) do
            assert(not seen[st.id], "a quest stands in one lane only")
            seen[st.id] = true
            quests = quests + 1
        end
    end
    eq(quests + #map.singles, map.quests)
    ns.home, ns.selected = false, "BRD"
    ns.Toggle(); ns.ShowTab(4)
    local shown = ns.ChainLanes()
    eq(#shown, #map.lanes + (#map.singles > 0 and 1 or 0))
    eq(shown[1].steps[1], map.lanes[1].steps[1].id)
    -- A step whose work is inside the dungeon carries the dungeon's icon.
    local marked, plain = 0, 0
    for i, l in ipairs(map.lanes) do
        for _, st in ipairs(l.steps) do
            eq(shown[i].inside[st.id] or false, st.inside and true or false, "the pill follows the step")
            if st.inside then marked = marked + 1 else plain = plain + 1 end
        end
    end
    assert(marked > 0, "some steps are done in the dungeon")
    assert(plain > 0, "and some outside it")
end)

test("a quest behind a quest still in the log waits in Later, not in Take", function()
    -- Disharmony of Fire (3907) opens when Disharmony of Flame (3906) is handed in.
    Fake({ level = 54, raceID = 2, faction = "Horde", className = "WARRIOR", active = { [3906] = true } })
    local ns = Load()
    local function find(list, id)
        for _, x in ipairs(list) do if x.id == id then return x end end
    end
    local q = ns.Quests("BRD", 54)
    assert(not find(q.take, 3907), "it cannot be taken yet")
    local e = find(q.later, 3907)
    assert(e, "it waits")
    eq(e.why, "WHY_EARLIER"); eq(e.need.id, 3906)
    eq(ns.Quest(3907, 54).state, "later")
    eq(ns.NeedText(e.need), ns.L.AFTER:format(e.need.name), "it says after which quest")
    local all, _, total, counts = ns.TrackerItems("BRD", 54)
    for _, it in ipairs(all) do
        if it.id == 3907 then eq(it.group, "later", "the tracker follows") end
    end
    eq(counts.hand + counts.doing + counts.take + counts.later, total)
    Fake({ level = 54, raceID = 2, faction = "Horde", className = "WARRIOR", done = { [3906] = true } })
    ns = Load()
    q = ns.Quests("BRD", 54)
    assert(find(q.take, 3907), "handed in: now it can be taken")
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
    eq(row.name, card.name, "the row is named by the quest to do now")
    eq(row.at, 4, "which step the chain is at")
    eq(row.of, 7)
    eq(#row.steps, 7)
    eq(row.group, "doing")
    eq(row.steps[3].state, "done")
    eq(row.steps[4].state, "now")
    eq(row.steps[5].state, "later")
    eq(row.steps[7].goal, true, "the last step is the chain's goal")
    ns.StartGuide("DM")
    eq(ns.TrackerOpen(166), false)
    local h = ns.TrackerFrame():GetHeight()
    ns.ToggleTracked(166)
    eq(ns.TrackerOpen(166), true, "a click opens the row to show every step")
    eq(ns.TrackerFrame():GetHeight(), h, "the panel keeps its size: the steps go into a card beside it")
    assert(ns.TrackerChainFrame():IsShown(), "the card with the steps shows")
    ns.ToggleTracked(166)
    eq(ns.TrackerOpen(166), false)
    assert(not ns.TrackerChainFrame():IsShown(), "a second click closes the card")
    -- The whole chain done: one done chain.
    W.done = { [65] = true, [132] = true, [135] = true, [141] = true, [142] = true, [155] = true, [166] = true }
    W.active = {}
    local finished = 0
    for _, x in ipairs(ns.Quests("DM", 18).finished) do if x.head and x.head.id == 166 then finished = finished + 1 end end
    eq(finished, 1)
end)

test("a pin button near the giver targets them, out of combat only, and never sets a raid mark", function()
    Fake({})
    local ns = Load()
    local forbidden
    SetRaidTarget = function() forbidden = true end
    -- The secure button over the pin: its macro targets by name, its click pins.
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
    o:GetScript("PostClick")(o, "LeftButton", true)
    eq(pinned, nil, "nothing on the press")
    o:GetScript("PostClick")(o, "LeftButton", false)
    eq(pinned, true, "the pin's own click runs")
    eq(forbidden, nil, "SetRaidTarget is forbidden to addons: never called")
    SetRaidTarget = nil
end)

test("an item's tooltip stands left of the worn item it is compared with", function()
    local W = Fake({ level = 48, raceID = 6, faction = "Horde", areas = { [405] = "Desolace", [2100] = "Maraudon" } })
    local ns = Load()
    local function tip(width, right)
        local t = W.stub()
        rawset(t, "points", {})
        rawset(t, "SetPoint", function(self, ...) self.points[#self.points + 1] = { ... } end)
        rawset(t, "ClearAllPoints", function(self) self.points = {} end)
        rawset(t, "GetWidth", function() return width end)
        rawset(t, "GetRight", function() return right end)
        rawset(t, "GetEffectiveScale", function() return 1 end)
        return t
    end
    local owner
    GameTooltip = tip(300)
    rawset(GameTooltip, "SetOwner", function(_, o) owner = o end)
    rawset(GameTooltip, "GetOwner", function() return owner end)
    ShoppingTooltip1, ShoppingTooltip2 = tip(280), tip(280)
    UIParent = tip(1920, 1920)
    local compared = 0
    GameTooltip_ShowCompareItem = function() compared = compared + 1; ShoppingTooltip1:Show() end
    local hooks = {}
    hooksecurefunc = function(name, fn) hooks[name] = fn end
    local row = tip(300, 900)
    ns.ItemTip(row, 17191)
    eq(compared, 1, "the worn item is asked for")
    local p = GameTooltip.points[1]
    eq(p[1], "TOPLEFT"); eq(p[2], row); eq(p[3], "TOPRIGHT")
    p = ShoppingTooltip1.points[1]
    eq(p[1], "TOPLEFT", "the worn item starts where the tooltip ends"); eq(p[2], GameTooltip); eq(p[3], "TOPRIGHT")
    eq(#ShoppingTooltip2.points, 0, "a second worn item only when the game shows one")
    -- at the screen's right edge both go left of the row, in the same order
    local edge = tip(300, 1800)
    ns.ItemTip(edge, 17191)
    p = GameTooltip.points[1]
    eq(p[1], "TOPRIGHT"); eq(p[2], edge); eq(p[3], "TOPLEFT"); eq(p[4], -284, "room for the worn item")
    p = ShoppingTooltip1.points[1]
    eq(p[1], "TOPLEFT"); eq(p[2], GameTooltip); eq(p[3], "TOPRIGHT")
    -- the game laid them out again (Shift): the order is put back, but only for our rows
    ShoppingTooltip1.points = { { "TOPRIGHT", GameTooltip, "TOPLEFT" } }
    hooks.GameTooltip_ShowCompareItem()
    eq(ShoppingTooltip1.points[1][1], "TOPLEFT")
    owner = tip(100, 100)
    ShoppingTooltip1.points = { { "TOPRIGHT", GameTooltip, "TOPLEFT" } }
    hooks.GameTooltip_ShowCompareItem()
    eq(ShoppingTooltip1.points[1][1], "TOPRIGHT", "another addon's tooltip is left alone")
    GameTooltip_ShowCompareItem, hooksecurefunc, ShoppingTooltip1, ShoppingTooltip2 = nil, nil, nil, nil
end)

test("Wowhead on a quest's page shows the quest's link in a box to copy", function()
    Fake({ level = 48, raceID = 6, faction = "Horde", areas = { [405] = "Desolace", [2100] = "Maraudon" },
           active = { [93404] = true } })
    local ns = Load()
    eq(ns.WowheadURL("quest", 93404), "https://www.wowhead.com/forever/quest=93404")
    eq(ns.WowheadURL("npc", 12201), "https://www.wowhead.com/forever/npc=12201")
    eq(ns.WowheadURL("quest", nil), nil, "no link without an id")
    ns.home, ns.selected = false, "MARA"
    ns.Toggle(); ns.ShowTab(3); ns.OpenQuest(93404)
    local d = ns.DetailFrame()
    d.link:GetScript("OnClick")(d.link)
    local box = ns.ShowLink(ns.WowheadURL("quest", 93404))
    eq(box:IsShown(), true)
    eq(box.url, "https://www.wowhead.com/forever/quest=93404")
    eq(box.edit:GetText(), box.url, "the link is in the box")
    box.close:GetScript("OnClick")(box.close)
    eq(box:IsShown(), false, "the cross closes it")
end)

test("a click on a chain step opens that step's page and sets no pin, also for a step outside the dungeon", function()
    local W = Fake({ level = 48, raceID = 6, faction = "Horde", areas = { [405] = "Desolace", [2100] = "Maraudon" },
                     active = { [93404] = true },
                     done = { [92914] = true, [96010] = true, [96018] = true, [93016] = true, [93394] = true,
                              [93341] = true, [93594] = true } })
    local opened
    C_Map.OpenWorldMap = function(id) opened = id end
    local ns = Load()
    ns.home, ns.selected = false, "MARA"
    ns.Toggle(); ns.ShowTab(3); ns.OpenQuest(93404)
    local d = ns.DetailFrame()
    local function click(n)
        local row = d.chain.rows[n]
        row.click:GetScript("OnClick")(row.click)
    end
    click(8)
    eq(ns.openQuest, 93404, "the step shown stays")
    click(9)
    eq(ns.openQuest, 93601, "Passing the Blame opens")
    eq(#W.pins, 0, "no pin")
    eq(opened, nil, "and no map")
    local q = d.q
    eq(q.outside, true); eq(q.name, "Passing the Blame"); eq(q.state, "later", "Rot and Regret comes first")
    eq(q.step, 9); eq(#q.chain, 11, "the same chain, at its own step")
    eq(q.chain[9].this, true); eq(q.chain[8].this, false)
    click(11)
    eq(ns.openQuest, 93606, "from a step outside to the next one")
    eq(d.q.step, 11)
    click(8)
    eq(ns.openQuest, 93404, "and back to the dungeon quest")
    eq(d.q.outside, nil)
    eq(#ns.Quest(93601).chain, 0, "without the quest it was opened from, a step outside has no chain")
    OpenWorldMap = nil
end)

test("inside the dungeon: the data's flags, the stages of a quest's way, the tracker's mark", function()
    local W = Fake({ level = 48, raceID = 6, faction = "Horde", areas = { [405] = "Desolace", [215] = "Mulgore", [2100] = "Maraudon" },
                     active = { [96776] = true }, done = { [7044] = true } })
    local ns = Load()
    -- An'she's Radiance: taken and handed in in Mulgore, done in Maraudon.
    local i = ns.Inside("MARA", 96776)
    eq(i.take, false); eq(i.work, true); eq(i.turnin, false)
    -- The Scepter of Celebras: all of it with Celebras, inside.
    i = ns.Inside("MARA", 7046)
    eq(i.take, true); eq(i.work, true); eq(i.turnin, true)
    -- Seed of Life is taken inside and carried to Moonglade; a talk in Booty Bay is not inside.
    i = ns.Inside("MARA", 7066)
    eq(i.take, true); eq(i.work, false); eq(i.turnin, false)
    eq(ns.Inside("GNOMER", 2842).work, false, "Chief Engineer Scooty is in Booty Bay")
    eq(ns.Inside("MARA", 1).work, false, "an unknown quest has no flag")
    eq(ns.Inside(nil, 96776).work, false)
    -- Agamaggan's Blood: the game moved its work out of Razorfen Downs (OUTSIDE_WORK).
    eq(ns.Inside("RFD", 93604).work, false, "Agamaggan's Blood is done outside too")
    -- The way of a quest in the log: taken, its work now, the hand-in waits.
    local function states(id)
        local out = {}
        for n, st in ipairs(ns.Stages(ns.Quest(id, 48), "MARA")) do out[n] = st.kind .. "=" .. st.state end
        return table.concat(out, " ")
    end
    eq(states(96776), "take=done work=now turnin=wait")
    eq(ns.Stages(ns.Quest(96776, 48), "MARA")[2].inside, true)
    W.complete[96776] = true
    eq(states(96776), "take=done work=done turnin=now")
    eq(states(7046), "take=now work=wait turnin=wait", "a quest to take")
    W.done[96776] = true
    eq(states(96776), "take=done work=done turnin=done")
    W.done[96776], W.complete[96776] = nil, nil
    -- The tracker marks the rows whose next thing happens inside.
    local byId = {}
    for _, it in ipairs(ns.TrackerItems("MARA", 48)) do byId[it.id] = it end
    eq(byId[96776].inside, true, "its work is in the dungeon")
    eq(byId[7046].inside, true, "taken from Celebras, inside")
    eq(byId[7068].inside, nil, "Shadowshard Fragments is taken in Orgrimmar")
    W.complete[96776] = true
    byId = {}
    for _, it in ipairs(ns.TrackerItems("MARA", 48)) do byId[it.id] = it end
    eq(byId[96776].state, "ready")
    eq(byId[96776].inside, nil, "handed in outside: no mark any more")
    -- The tracker row shows the dungeon's icon under its mark.
    W.complete[96776] = nil
    ns.ShowTracker("MARA")
    local shown = 0
    for _, child in ipairs(rawget(ns.TrackerFrame(), "rows")) do
        local mark = rawget(child, "inside")
        if child:IsShown() and mark and mark:IsShown() then shown = shown + 1 end
    end
    assert(shown >= 2, "rows with the dungeon's icon: " .. shown)
end)

test("a quest's page: the way in three stages, the dungeon's other quests beside it", function()
    Fake({ level = 48, raceID = 6, faction = "Horde", areas = { [405] = "Desolace", [215] = "Mulgore", [2100] = "Maraudon" },
           active = { [96776] = true } })
    local ns = Load()
    ns.home, ns.selected = false, "MARA"
    ns.Toggle(); ns.ShowTab(3); ns.OpenQuest(96776)
    local d = ns.DetailFrame()
    eq(d.start:GetText(), "Olana Brighthoof")
    eq(d.work.title:GetText(), "Inside Maraudon")
    assert(d.work.map:IsShown(), "the way in can be pinned")
    eq(d.stages[1].tag.text:GetText(), "Done")
    eq(d.stages[2].tag.text:GetText(), "Now")
    assert(not d.stages[3].tag:IsShown(), "the hand-in waits")
    -- A single quest without rewards: no chain card, the other quests take the column.
    assert(not d.chainCard:IsShown(), "no chain of one step")
    assert(d.othersCard:IsShown(), "the dungeon's other quests")
    assert(#d.othersData > 0, "some are listed")
    for _, it in ipairs(d.othersData) do assert(it.quest.id ~= 96776, "not the quest itself") end
    -- A chain shows its card; a step taken inside says so.
    ns.OpenQuest(7046)
    assert(d.chainCard:IsShown(), "The Scepter of Celebras is step 2 of 2")
    eq(d.start:GetText(), "Celebras the Redeemed")
    assert(d.startXY:GetText():find("Inside Maraudon", 1, true), "taken inside: " .. d.startXY:GetText())
    assert(not d.startMap:IsShown(), "no map pin inside a dungeon")
end)

test("a Russian client reads the objective and the guide tips in Russian (Data_ru.lua)", function()
    Fake({ level = 40, raceID = 3, faction = "Alliance", locale = "ruRU" })
    local ns = Load()
    eq(ns.lang, "ru")
    local q = ns.Quest(17, 40)
    eq(q.text, "Принесите 12 грибов-малиновиков Гхаку Целителю в Телcамар.", "the game's own text, from QuestieDB")
    eq(q.tips.d, "Ещё больше растёт внутри подземелья.", "our translation of the guide's note")
    Fake({ level = 40, raceID = 3, faction = "Alliance" })
    ns = Load()
    eq(ns.Quest(17, 40).text, "Bring 12 Magenta Fungus Caps to Ghak Healtouch in Thelsamar.", "English elsewhere")
    eq(ns.Data.L, nil, "no other language in memory")
end)

test("experience: the game's number for a quest in the log, else the data's, cut above the quest", function()
    Fake({ level = 47, raceID = 2, faction = "Horde", active = { [168] = true } })
    local ns = Load()
    local xp, exact = ns.QuestXP(168, 18)
    eq(xp, 1450); eq(exact, true, "in the log: the game says it")
    -- Twisted Evils is level 47 and gives 5250 at its level.
    eq(ns.Data.xp[7028], 5250)
    xp, exact = ns.QuestXP(7028, 47)
    eq(xp, 5250); eq(exact, false)
    eq(ns.QuestXP(7028, 52), 5250, "five levels above still gives all of it")
    eq(ns.QuestXP(7028, 53), 4200, "then a fifth less per level")
    eq(ns.QuestXP(7028, 57), 525, "a tenth at the end, rounded like the game")
    eq(ns.QuestXP(7028, 60), 0, "nothing at the top level")
    eq(ns.QuestXP(1, 47), 0, "an unknown quest")
    -- Brotherhood's End is a step of the Defias chain outside the dungeon (D.pre, level 31).
    eq(ns.Data.pre[395] ~= nil, true); eq(ns.Data.quest[395], nil)
    eq(ns.Data.xp[395], 630); eq(ns.QuestXP(395, 31), 625, "a chain step outside the dungeon has its experience too")
    eq(ns.Data.xp[99187], 7750, "a Forever quest QuestieDB has not measured takes its experience from the Wowhead snapshot")
    assert(ns.XPText(7028, 47):find("~5250 experience", 1, true), "the data's number is marked: " .. ns.XPText(7028, 47))
    eq(ns.XPText(7028, 60), nil)
    assert(not ns.XPText(168, 18):find("~", 1, true), "the game's number is not")
end)

test("one guide at a time: Lead me stops another module's guide, and can be stopped by one", function()
    local W = Fake({ level = 18, areas = { [1519] = "Stormwind City", [40] = "Westfall" },
        map = { best = 1453, maps = { [1415] = { "Eastern Kingdoms", 2 }, [1453] = { "Stormwind City", 3, 1415 },
                                      [1436] = { "Westfall", 3, 1415 } }, pos = { 0.5, 0.5 } } })
    local ns = Load()
    local stopped = 0
    GulliHUD = GulliHUD or {}
    GulliHUD.guide = { owner = "WorthIt", stop = function() stopped = stopped + 1 end }
    eq(ns.StartGuide("DM"), true)
    eq(stopped, 1)
    eq(GulliHUD.guide.owner, "DungeonPrep")
    GulliHUD.guide.stop()
    eq(ns.guide, nil, "another module's guide ends ours")
    eq(GulliHUD.guide, nil)
end)

test("a quest's way: guide tips per stage, quest items, the boss a quest needs, what comes next", function()
    Fake({ level = 50, raceID = 2, faction = "Horde", areas = { [5140] = "Alcaz Prison" } })
    local ns = Load()
    -- The tips of the Alcaz guide: taking it, its work, handing it in.
    local q = ns.Quest(96335, 50)
    local st = ns.Stages(q, "ALCAZ")
    assert(st[1].tip:find("Do not kill The Questioner", 1, true), "take: " .. tostring(st[1].tip))
    eq(st[2].tip, "Low drop rate.")
    assert(st[3].tip:find("turn it in together", 1, true), "turn in: " .. tostring(st[3].tip))
    -- Mason Connery takes it back, inside the prison.
    eq(st[3].who, "Mason Connery"); eq(st[3].inside, true)
    -- Before the log: the quest item without a count.
    local goals = ns.Goals(q)
    eq(#goals, 1); eq(goals[1].text, "Ornate Shackle Key"); eq(goals[1].item, 274029); eq(goals[1].have, nil)
    -- The Questioner is a boss of the prison, with its place in the order.
    local b = ns.QuestBosses(q, "ALCAZ")
    eq(#b, 1); eq(b[1].name, "The Questioner"); eq(b[1].min, 51)
    assert(b[1].n >= 1 and b[1].n <= b[1].of, "boss " .. b[1].n .. " of " .. b[1].of)
    -- No tips without a guide note, and no boss of another dungeon.
    eq(ns.Stages(q, "ALCAZ")[1].tip ~= nil, true)
    eq(#ns.QuestBosses(q, "RFC"), 0)

    -- In the log, the game's line gives the count, and the item its icon.
    Fake({ level = 50, raceID = 2, faction = "Horde", active = { [96335] = true },
           objectives = { [96335] = { { text = "Ornate Shackle Key: 0/1", finished = false } } } })
    ns = Load()
    goals = ns.Goals(ns.Quest(96335, 50))
    eq(goals[1].have, 0); eq(goals[1].need, 1); eq(goals[1].item, 274029); eq(goals[1].done, false)

    -- The page: the tips show, the boss row opens the boss page, the summary names the next steps.
    ns.home, ns.selected = false, "ALCAZ"
    ns.Toggle(); ns.ShowTab(3); ns.OpenQuest(96335)
    local d = ns.DetailFrame()
    eq(d.turnin:GetText(), "Mason Connery")
    assert(not d.stages[1].tip:IsShown(), "taken: no tip for taking it")
    for i = 2, 3 do assert(d.stages[i].tip:IsShown(), "tip of stage " .. i) end
    assert(d.objRows[1]:IsShown(), "the key's row")
    eq(d.objRows[1].count:GetText(), "0/1")
    assert(d.bossRows[1]:IsShown(), "The Questioner's row")
    assert(d.bossRows[1].name:GetText():find("The Questioner", 1, true), d.bossRows[1].name:GetText())
    assert(not d.mobs:IsShown(), "the boss is not named twice")
    assert(d.summary:IsShown(), "the summary strip")
    local sum = d.summary.gives:GetText() .. "|" .. d.summary.next:GetText()
    assert(sum:find("More Valuable Than Gold", 1, true), sum)
    d.bossRows[1]:GetScript("OnClick")(d.bossRows[1])
    eq(ns.boss, 256236, "the boss page shows The Questioner")
end)

W.finish()
