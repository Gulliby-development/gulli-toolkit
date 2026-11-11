-- Run from the repository root: lua5.1 tests/questcleaner/test.lua
local W = dofile("tests/questcleaner/wow.lua")
local failed, count = 0, 0

local function test(name, fn)
    count = count + 1
    local ok, err = pcall(fn)
    if ok then
        io.write("ok   ", name, "\n")
    else
        failed = failed + 1
        io.write("FAIL ", name, "\n     ", tostring(err), "\n")
    end
end

local function eq(a, b, what)
    if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local function names(list)
    local t = {}
    for _, x in ipairs(list) do t[#t + 1] = x.name or x.title end
    table.sort(t)
    return table.concat(t, ",")
end

local QUESTS = {
    { title = "Zone", isHeader = true },
    { title = "Wolf Pelts", level = 5, questID = 101, objectives = { { text = "Wolf Pelt: 3/10" } } },
    { title = "Deliver Letter", level = 8, questID = 102, description = "Bring the Sealed Letter to Bob." },
    { title = "Ogres", level = 30, questID = 103, objectives = { { text = "Ogre Tooth: 1/5" } } },
}
local function bag()
    return {
        { id = 1, name = "Wolf Pelt", class = 12, count = 3 },
        { id = 2, name = "Sealed Letter", class = 12 },
        { id = 3, name = "Ogre Tooth", class = 12 },
        { id = 4, name = "Old Note", class = 12 },
        { id = 16309, name = "Drakefire Amulet", class = 12 },
        { id = 5, name = "Linen Cloth", class = 7 },
        { id = 6, name = "Done Starter", class = 15, starts = 55 },
        { id = 7, name = "Open Starter", class = 15, starts = 56 },
    }
end

test("quests at or below the level are planned, headers are not", function()
    Fake { quests = QUESTS, bag = bag() }
    local ns = Load()
    eq(names(ns.PlanQuests(10)), "Deliver Letter,Wolf Pelts")
    eq(#ns.PlanQuests(4), 0, "quests at level 4")
end)

test("items: leftovers go, items of quests that stay and permanent items stay", function()
    Fake { quests = QUESTS, bag = bag(), done = { [55] = true } }
    local ns = Load()
    local items = ns.PlanItems(ns.PlanQuests(10))
    eq(names(items), "Done Starter,Old Note,Sealed Letter,Wolf Pelt")
    for _, it in ipairs(items) do
        if it.name == "Wolf Pelt" then eq(it.links[1].title, "Wolf Pelts", "Wolf Pelt link") end
        if it.name == "Sealed Letter" then eq(it.links[1].title, "Deliver Letter", "letter link (found in the description)") end
        if it.name == "Old Note" then eq(#it.links, 0, "Old Note links"); eq(it.why, "WHY_NO_QUEST") end
        if it.name == "Done Starter" then eq(it.why, "WHY_DONE") end
    end
end)

test("unticking a quest keeps its items", function()
    Fake { quests = QUESTS, bag = bag() }
    local ns = Load()
    local quests = ns.PlanQuests(10)
    local items = ns.PlanItems(quests)
    for _, q in ipairs(quests) do if q.title == "Deliver Letter" then q.checked = false end end
    for _, it in ipairs(items) do
        eq(ns.ItemGoes(it), it.name ~= "Sealed Letter", it.name .. " goes")
    end
end)

test("OK abandons ticked quests and deletes ticked items only", function()
    local w = Fake { quests = QUESTS, bag = bag() }
    local ns = Load()
    local quests = ns.PlanQuests(10)
    local items = ns.PlanItems(quests)
    for _, it in ipairs(items) do if it.name == "Old Note" then it.checked = false end end
    local a, d = ns.Run(quests, items)
    eq(a, 2, "abandoned")
    eq(d, 2, "delete tries")
    eq(w.abandoned[101] and w.abandoned[102] and not w.abandoned[103], true, "abandoned the right quests")
    for _, it in ipairs(w.bag) do
        local gone = it.name == "Wolf Pelt" or it.name == "Sealed Letter"
        eq(it.gone == true, gone, it.name .. " deleted")
    end
end)

test("a refused delete leaves the item to be offered again", function()
    local w = Fake { quests = QUESTS, bag = bag() }
    local ns = Load()
    local quests = ns.PlanQuests(10)
    local items = ns.PlanItems(quests)
    w.refuseDelete = true
    ns.Run(quests, items)
    eq(w.cursor, nil, "cursor cleared")
    local _, left = ns.Leftover(quests, items)
    eq(#left, #items, "items left")
end)

test("one OK deletes every ticked item even when the cursor clears late", function()
    local w = Fake { quests = QUESTS, bag = bag(), done = { [55] = true } }
    local ns = Load()
    local quests = ns.PlanQuests(10)
    local items = ns.PlanItems(quests)
    w.slowCursor = true
    ns.Run(quests, items)
    local _, left = ns.Leftover(quests, items)
    eq(#left, 0, "items left after one OK")
    eq(w.cursor, nil, "cursor cleared")
end)

test("nothing happens in combat", function()
    local w = Fake { quests = QUESTS, bag = bag() }
    local ns = Load()
    w.combat = true
    local quests = ns.PlanQuests(10)
    local a, d = ns.Run(quests, ns.PlanItems(quests))
    eq(a + d, 0, "changes in combat")
end)

test("the window: Clear, then OK, cleans and reports", function()
    local w = Fake { quests = QUESTS, bag = bag(), level = 18 }
    local ns = Load()
    ns.Toggle()
    Find(function(f) return rawget(f, "_OnShow") end)._OnShow()
    Find(function(f) return TextOf(f) == ns.L.CLEAR and rawget(f, "_OnClick") end)._OnClick()
    Find(function(f) return TextOf(f) == ns.L.OK and rawget(f, "_OnClick") end)._OnClick()
    eq(w.abandoned[101] and w.abandoned[102], true, "abandoned")
    eq(w.printed[#w.printed]:find("2 quests abandoned", 1, true) ~= nil, true, "done message: " .. tostring(w.printed[#w.printed]))
end)

test("the addon speaks the client's language and falls back to English", function()
    Fake { locale = "ruRU" }
    eq(Load().L.CLEAR, "Очистить")
    Fake { locale = "deDE" }
    eq(Load().L.CLEAR, "Aufräumen")
    Fake { locale = "koKR" }
    eq(Load().L.CLEAR, "Clear")
end)

test("quests keep their zone and the plan is grouped by zone in log order", function()
    Fake { quests = {
        { title = "Westfall", isHeader = true },
        { title = "Stew", level = 14, questID = 1 },
        { title = "Elwynn Forest", isHeader = true },
        { title = "Wolves", level = 6, questID = 2 },
        { title = "Kobolds", level = 4, questID = 3 },
        { title = "Westfall", isHeader = true },
        { title = "Murlocs", level = 12, questID = 4 },
    } }
    local ns = Load()
    local zones = ns.Zones(ns.PlanQuests(20))
    eq(#zones, 2, "zones")
    eq(zones[1].name, "Westfall")
    eq(names(zones[1].quests), "Murlocs,Stew", "Westfall quests")
    eq(zones[2].name, "Elwynn Forest")
    eq(zones[2].quests[1].title, "Kobolds", "lower level first")
end)

test("a zone row ticks and unticks all of its quests", function()
    Fake { quests = QUESTS, bag = bag(), level = 18 }
    local ns = Load()
    ns.Toggle()
    Find(function(f) return rawget(f, "_OnShow") end)._OnShow()
    Find(function(f) return TextOf(f) == ns.L.CLEAR and rawget(f, "_OnClick") end)._OnClick()
    local zoneRow = Find(function(f) local d = rawget(f, "data"); return d and d.quests end)
    assert(zoneRow, "no zone row")
    zoneRow._OnClick()
    for _, q in ipairs(rawget(zoneRow, "data").quests) do eq(q.checked, false, q.title .. " after one click") end
    zoneRow._OnClick()
    for _, q in ipairs(rawget(zoneRow, "data").quests) do eq(q.checked, true, q.title .. " after two clicks") end
end)

test("every language has every key, with the same %d placeholders", function()
    Fake {}
    local ns = Load()
    local en = ns.T.en
    for i, tag in ipairs(ns.TAGS) do
        do
            local t = ns.T[tag]
            assert(t, "no table for " .. tag)
            for key, text in pairs(en) do
                assert(t[key], tag .. " is missing " .. key)
                local _, a = text:gsub("%%d", "")
                local _, b = t[key]:gsub("%%d", "")
                assert(a == b, tag .. "." .. key .. " has " .. b .. " %d, English has " .. a)
            end
            for key in pairs(t) do assert(en[key], tag .. " has unknown key " .. key) end
        end
    end
end)

-- Small quest data in place of the generated Data.lua.
local function fakeData(ns, d)
    ns.Data = { need = d.need or {}, quest = d.quest or {}, keep = d.keep or {},
                itemStart = d.itemStart or {}, chain = d.chain or {}, class = d.class or {} }
end

local function planned(ns, level)
    local quests = ns.PlanQuests(level)
    local items, future = ns.PlanItems(quests, level)
    return quests, items, future
end

local function has(list, name)
    for _, x in ipairs(list) do if (x.name or x.title) == name then return x end end
end

test("an item for a quest above the level the player can still take stays", function()
    Fake { quests = QUESTS, bag = bag() }
    local ns = Load()
    fakeData(ns, { need = { [4] = { 900 } }, quest = { [900] = { 35, 0, 0, 0 } } })
    local _, items, future = planned(ns, 10)
    eq(has(items, "Old Note"), nil, "Old Note offered")
    eq(has(future, "Old Note") ~= nil, true, "Old Note kept for a future quest")
end)

test("an item for a future quest goes when that quest is done, closed, low or not for this race", function()
    local cases = {
        { done = { [900] = true }, quest = { 35, 0, 0, 0 } },
        { done = { [901] = true }, quest = { 35, 0, 0, 0, { 901 } } },
        { quest = { 8, 0, 0, 0 } },
        { quest = { 35, 8589934770, 0, 0 } }, -- Horde races and a Forever race past 2^32
        { quest = { 35, 0, 1, 0 } },          -- warriors only
        { quest = { 35, 0, 0, 30 } },         -- up to level 30, player is 40
    }
    for i, c in ipairs(cases) do
        Fake { quests = QUESTS, bag = bag(), done = c.done }
        local ns = Load()
        fakeData(ns, { need = { [4] = { 900 } }, quest = { [900] = c.quest } })
        local _, items = planned(ns, 10)
        eq(has(items, "Old Note") ~= nil, true, "case " .. i .. ": Old Note offered")
    end
end)

test("a Forever race mask past 2^32 still matches its race", function()
    Fake { quests = QUESTS, bag = bag(), race = 34 }
    local ns = Load()
    fakeData(ns, { need = { [4] = { 900 } }, quest = { [900] = { 35, 8589934770, 0, 0 } } })
    local _, _, future = planned(ns, 10)
    eq(has(future, "Old Note") ~= nil, true, "kept for race 34")
end)

test("the data links items to quests in the log even when no text names them", function()
    Fake { quests = QUESTS, bag = bag() }
    local ns = Load()
    fakeData(ns, { need = { [4] = { 103 }, [3] = { 101 } } })
    local _, items = planned(ns, 10)
    eq(has(items, "Old Note"), nil, "Old Note stays for Ogres")
    -- Ogre Tooth: the text names Ogres (stays), so it stays whatever the data says.
    eq(has(items, "Ogre Tooth"), nil, "Ogre Tooth")
    fakeData(ns, { need = { [4] = { 101 } } })
    local note = has(select(2, planned(ns, 10)), "Old Note")
    eq(note.links[1].title, "Wolf Pelts", "Old Note linked by the data")
end)

test("quest items that stay useful after their quest are never offered", function()
    Fake { quests = QUESTS, bag = bag() }
    local ns = Load()
    fakeData(ns, { keep = { [4] = 1 } })
    eq(has(select(2, planned(ns, 10)), "Old Note"), nil, "Old Note")
end)

test("the real data loads and knows a reward key and an item a quest asks for", function()
    Fake {}
    local ns = Load()
    eq(ns.Data.keep[22057], 1, "Brazier of Invocation kept")
    eq(ns.Data.need[752][1], 18, "Red Burlap Bandana for Brotherhood of Thieves")
    eq(ns.Data.quest[18][1], 4, "Brotherhood of Thieves level")
    eq(ns.Data.itemStart[2], 1, "Sharptalon's Claw starts a quest")
end)

test("class, dungeon and elite quests are protected, and each switch turns that off", function()
    Fake { quests = QUESTS, bag = bag(), tags = { [102] = { tagID = 81 } } }
    local ns = Load()
    fakeData(ns, { class = { [101] = 1 } })
    eq(#ns.PlanQuests(10), 0, "planned with protection")
    ns.db().keepClass, ns.db().keepDungeon = false, false
    eq(#ns.PlanQuests(10), 2, "planned without protection")
    Fake { quests = QUESTS, bag = bag(), tags = { [101] = { tagID = 0, isElite = true } } }
    ns = Load()
    fakeData(ns, {})
    eq(names(ns.PlanQuests(10)), "Deliver Letter", "elite quest kept")
end)

test("a quest an item started starts unticked; a chain quest is marked", function()
    Fake { quests = QUESTS, bag = bag() }
    local ns = Load()
    fakeData(ns, { itemStart = { [101] = 1 }, chain = { [102] = 1 } })
    local q = ns.PlanQuests(10)
    local wolf, letter = has(q, "Wolf Pelts"), has(q, "Deliver Letter")
    eq(wolf.checked, false, "item quest ticked")
    eq(wolf.warn, "TAG_ITEM")
    eq(letter.checked, true, "chain quest ticked")
    eq(letter.warn, "TAG_CHAIN")
end)

test("the gray level", function()
    Fake { level = 40, greenRange = 8 }
    eq(Load().GrayLevel(), 31, "with the client's range")
    Fake { level = 40 }
    eq(Load().GrayLevel(), 31, "Vanilla rule at 40")
    Fake { level = 20 }
    eq(Load().GrayLevel(), 13, "Vanilla rule at 20")
    Fake { level = 4 }
    eq(Load().GrayLevel(), 0, "nothing is gray at 4")
end)

test("at a merchant, items with a price are sold instead of deleted", function()
    local b = bag()
    b[4].price = 25
    local w = Fake { quests = QUESTS, bag = b }
    local ns = Load()
    fakeData(ns, {})
    Fire("MERCHANT_SHOW")
    local quests, items = planned(ns, 10)
    local _, deleted, sold = ns.Run(quests, items)
    eq(sold, 1, "sold")
    eq(w.sold["Old Note"], true, "Old Note sold")
    eq(deleted, 2, "deleted")
    Fire("MERCHANT_CLOSED")
    eq(ns.atMerchant, false, "merchant closed")
end)

test("the last cleaning is saved per character and /gqc last prints it", function()
    local w = Fake { quests = QUESTS, bag = bag() }
    local ns = Load()
    fakeData(ns, {})
    local quests, items = planned(ns, 10)
    ns.Run(quests, items)
    local last = GulliQuestCleanerCharDB.last
    eq(#last.quests, 2, "quests saved")
    eq(#last.items, 3, "items saved")
    SlashCmdList.GULLIQUESTCLEANER("last")
    eq(w.printed[#w.printed - 5]:find("2 quests, 3 items", 1, true) ~= nil, true, "last: " .. tostring(w.printed[#w.printed - 5]))
end)

test("the level is per character and starts from the old account-wide one", function()
    Fake { db = { level = 12 } }
    local ns = Load()
    eq(ns.charDB().level, 12, "migrated")
    ns.charDB().level = 20
    eq(ns.db().level, 12, "account value untouched")
end)

test("a nearly full log gets one chat hint", function()
    local w = Fake { quests = QUESTS, bag = bag(), maxQuests = 5, charDB = { level = 10 } }
    local ns = Load()
    fakeData(ns, {})
    local before = #w.printed
    Fire("QUEST_ACCEPTED", 1)
    eq(#w.printed, before + 1, "hint printed")
    eq(w.printed[#w.printed]:find("3 of 5", 1, true) ~= nil, true, "hint: " .. w.printed[#w.printed])
    Fire("QUEST_ACCEPTED", 2)
    eq(#w.printed, before + 1, "only once")
end)

test("registers with Gulli Toolkit when it is loaded, works without it", function()
    Fake { quests = QUESTS, bag = bag() }
    local got
    GulliToolkit = { Register = function(info) got = info end }
    local ns = Load()
    GulliToolkit = nil
    assert(got, "registered")
    eq(got.key, "QuestCleaner")
    eq(got.slash, "/gqc")
    eq(type(got.open), "function")
    Fake { quests = QUESTS, bag = bag() }
    assert(Load().PlanQuests, "loads without the toolkit")
end)

io.write(count - failed, "/", count, " passed\n")
os.exit(failed == 0 and 0 or 1)
