-- Run from the repository root: lua5.1 tests/worthit/test.lua
local W = dofile("tests/worthit/wow.lua")
local test, eq = W.test, W.eq

-- Poor Old Blanchy (Westfall, Alliance, from level 9) gives Old Blanchy's Feed Pouch.
local BLANCHY, POUCH, WESTFALL = 151, 1537, 40
-- The Night Watch: three steps in Duskwood, a bag or a quiver or a bandolier at the end.
local WATCH, WATCH_1, WATCH_2, GUNNYSACK = 58, 56, 57, 1729

local function find(list, quest)
    for _, e in ipairs(list) do if e.quest == quest then return e end end
end

-- Small data of our own, for the rules the real data has no clean case of.
local function fakeData(ns, rewards, quests, chains)
    ns.Data.rewards, ns.Data.quest, ns.Data.chain = rewards, quests, chains or {}
end
local function quest(name, level, req, x)
    return { name, level, req, 0, 0, "", "Giver" .. name, 40, x or 10, 10, "Taker" .. name, 40, (x or 10) + 1, 20, 40, (x or 10) + 2, 30 }
end

test("every language has every text", function()
    Fake({})
    W.CheckLocales(Load())
end)

test("the data: every reward has its quest, a kind and a chain that ends in it", function()
    Fake({})
    local D = Load().Data
    local kinds = {}
    for _, k in ipairs(D.kinds) do kinds[k] = true end
    assert(#D.rewards >= 20, "rewards")
    for _, r in ipairs(D.rewards) do
        assert(kinds[r[2]], "kind of " .. r[1])
        local q = D.quest[r[3]]
        assert(q and #q == 17, "quest row of " .. r[3])
    end
    for last, chain in pairs(D.chain) do
        eq(chain[#chain], last, "chain end")
        assert(#chain >= 2, "a chain has two steps or more")
        for _, id in ipairs(chain) do assert(D.quest[id], "chain step " .. id) end
    end
end)

test("quest bags the data does not link: the Hyjal Postal Satchel and the Old Toolbox's other choice", function()
    Fake({})
    local D = Load().Data
    local has = {}
    for _, r in ipairs(D.rewards) do has[r[1] .. ":" .. r[3]] = r[2] end
    eq(has["260307:93269"], "bag", "Hyjal Postal Satchel from Top of the Post")
    eq(has["1652:79192"], "bag", "Sturdy Lunchbox from Stepping Stones")
    eq(D.chain[93269][1], 93197, "the satchel's chain starts at Sebelia")
end)

test("a chain whose first step differs by side shows each side its own step", function()
    -- Stepping Stones (79192) follows ...and that note you found: 79007 for the Horde, 79008 for the Alliance.
    for _, side in ipairs({ { "Horde", 2, 79007 }, { "Alliance", 1, 79008 } }) do
        Fake({ level = 30, faction = side[1], raceId = side[2] })
        local ns = Load()
        local e = find((ns.Rewards()), 79192)
        assert(e, side[1] .. " sees the Old Toolbox quest")
        eq(e.chain[1], side[3], side[1] .. "'s first step")
        eq(e.cur, side[3], side[1] .. " starts at its own step")
    end
end)

test("a quest an item starts is taken where that item lies or drops", function()
    Fake({})
    local D = Load().Data
    local riddle = D.quest[624]
    eq(riddle[8], 33, "Cortello's Riddle lies in Stranglethorn Vale")
    assert(riddle[9] > 0 and riddle[10] > 0, "with a place on the map")
    local map = D.quest[136]
    assert(map[8] > 0 and map[9] > 0, "a dropped item has the place of its mob")
    assert(map[7]:find("%("), "and names the mob")
end)

test("the Wowhead link box lies over the hub", function()
    Fake({ level = 20, slots = { [POUCH] = 10 } })
    local ns = Load()
    ns.Toggle()
    local box = ns.ShowLink(ns.WowheadURL("quest", 624), "Cortello's Riddle")
    eq(box:IsShown(), true)
    eq(box.edit:GetText(), "https://www.wowhead.com/forever/quest=624")
end)

test("every reward has two to four steps of what to do, in every language", function()
    Fake({})
    local ns = Load()
    local seen, n = {}, 0
    for _, r in ipairs(ns.Data.rewards) do
        local q = r[3]
        if not seen[q] then
            seen[q], n = true, n + 1
            local en = ns.TIPS.en[q]
            assert(en and #en >= 2 and #en <= 4, "steps of quest " .. q)
            for _, tag in ipairs(ns.TAGS) do
                local t = ns.TIPS[tag] and ns.TIPS[tag][q]
                assert(t and #t == #en, tag .. ": steps of quest " .. q)
                for _, line in ipairs(t) do
                    assert(#line > 10 and #line <= (tag == "en" and 220 or 440), tag .. ": length, quest " .. q)
                    assert(not line:find("[|\n]"), tag .. ": plain text, quest " .. q)
                end
            end
        end
    end
    for tag, t in pairs(ns.TIPS) do
        for q in pairs(t) do assert(seen[q], tag .. ": steps for " .. q .. ", which gives no reward") end
    end
    assert(n >= 20, "rewards")
end)

test("the reward's page says what to do, then lists the chain; English when the language has none", function()
    Fake({ level = 20, slots = { [GUNNYSACK] = 10 } })
    local ns = Load()
    local e = find(ns.Rewards(), WATCH)
    local rows = ns.DetailRows(e, "CHAIN", "DO")
    eq(rows[1].head, "DO")
    eq(rows[2].tip, ns.TIPS.en[WATCH][1])
    eq(rows[2].n, 1)
    local tips = #ns.TIPS.en[WATCH]
    eq(rows[tips + 2].head, "CHAIN")
    eq(rows[tips + 3].id, WATCH_1)
    eq(#rows, tips + 2 + 3)
    ns.lang = "ru"
    eq(ns.Tips(WATCH)[1], ns.TIPS.ru[WATCH][1])
    ns.lang = "xx"
    eq(ns.Tips(WATCH)[1], ns.TIPS.en[WATCH][1], "the fallback")
    ns.TIPS.en[WATCH] = nil
    eq(ns.DetailRows(e, "CHAIN", "DO")[1].head, "CHAIN", "no steps, no head")
end)

test("a bag's slots are read from its tooltip, in the client's wording, and kept", function()
    Fake({ slots = { [POUCH] = 8 } })
    local ns = Load()
    eq(ns.Slots(POUCH), 8)
    W.slots[POUCH] = 12
    eq(ns.Slots(POUCH), 8, "read once")
    eq(ns.db.slots[POUCH], 8)
    Fake({ slots = { [POUCH] = 14 }, slotText = "%2$s (%1$d)" })
    eq(Load().Slots(POUCH), 14, "another word order")
    Fake({ slots = { [POUCH] = false } })
    eq(Load().Slots(POUCH), nil, "no slot line yet")
end)

test("a secret tooltip line is left alone", function()
    Fake({})
    local ns = Load()
    issecretvalue = function(v) return v == "SECRET" end
    C_TooltipInfo.GetItemByID = function() return { lines = { { leftText = "SECRET" } } } end
    eq(ns.Slots(POUCH), nil)
end)

test("the bags worn: the total, the empty bag slots and the smallest of each kind", function()
    Fake({ bags = { 6, 10, nil, 12 }, family = { [4] = 1 } })
    local b = Load().Bags()
    eq(b.total, 16 + 6 + 10 + 12)
    eq(b.open, 1)
    eq(b.smallest.bag.slots, 6)
    eq(b.smallest.ammo.slots, 12)
    eq(#b.list, 4, "the backpack and three bags")
end)

test("the gain: over the smallest bag of the kind, or the whole bag into an empty slot", function()
    Fake({ bags = { 6, 8, 8, 10 }, family = { [4] = 1 } })
    local ns = Load()
    local b = ns.Bags()
    eq(ns.Gain("bag", 10, b), 4)
    eq(ns.Gain("bag", 6, b), 0)
    eq(ns.Gain("ammo", 14, b), 4, "against the quiver worn")
    eq(ns.Gain("soul", 12, b), 6, "none worn: it takes the place of the smallest plain bag")
    eq(ns.Gain("prof", 12, b), 0, "a profession bag with none worn is no gain")
    eq(ns.Gain("bag", nil, b), nil, "slots not known yet")
    W.bags[2] = nil
    eq(ns.Gain("bag", 8, ns.Bags()), 8, "an empty bag slot")
end)

test("rewards are only the ones this character can get", function()
    Fake({ level = 20 })
    local ns = Load()
    local list = ns.Rewards()
    assert(find(list, BLANCHY), "an Alliance quest")
    eq(find(list, 791), nil, "a Horde quest")
    eq(find(list, 99053), nil, "a quest that gives only a quiver, for a priest")
    eq(find(list, WATCH).item, GUNNYSACK, "a priest takes the bag of the three")
    eq(#find(list, WATCH).options, 1)
    Fake({ level = 20, class = "HUNTER" })
    list = Load().Rewards()
    assert(find(list, 99053), "the quiver quest for a hunter")
    eq(#find(list, WATCH).options, 3)
    Fake({ level = 20, faction = "Horde", raceId = 2 })
    list = Load().Rewards()
    assert(find(list, 791))
    eq(find(list, BLANCHY), nil)
end)

test("the state follows the level, the log and the chain", function()
    Fake({ level = 8 })
    local ns = Load()
    local e = find(ns.Rewards(), BLANCHY)
    eq(e.state, "later"); eq(e.group, "later"); eq(e.req, 9)
    W.level = 9
    eq(find(ns.Rewards(), BLANCHY).state, "take")
    W.log[BLANCHY] = true
    eq(find(ns.Rewards(), BLANCHY).state, "log")
    W.ready[BLANCHY] = true
    e = find(ns.Rewards(), BLANCHY)
    eq(e.state, "ready"); eq(e.group, "now")
    W.log[BLANCHY], W.done[BLANCHY] = nil, true
    e = find(ns.Rewards(), BLANCHY)
    eq(e.state, "done"); eq(e.group, "done")
    -- a chain stands at its first step that is not done
    W.level = 30
    e = find(ns.Rewards(), WATCH)
    eq(e.cur, WATCH_1); eq(e.step, 1); eq(e.steps, 3)
    W.done[WATCH_1] = true
    e = find(ns.Rewards(), WATCH)
    eq(e.cur, WATCH_2); eq(e.step, 2)
    local steps = ns.Steps(e)
    eq(steps[1].done, true); eq(steps[2].now, true); eq(steps[3].done, false)
end)

test("the same reward behind two quests is listed once, by the branch further on", function()
    Fake({ level = 30 })
    local ns = Load()
    fakeData(ns, { { 900, "bag", 2 }, { 900, "bag", 4 } },
        { quest("One", 10, 5), quest("Two", 10, 5), quest("Three", 10, 5), quest("Four", 10, 5) },
        { [2] = { 1, 2 }, [4] = { 3, 4 } })
    local list = ns.Rewards()
    eq(#list, 1); eq(list[1].quest, 2, "no step done: the first branch")
    W.done[3] = true
    list = ns.Rewards()
    eq(#list, 1); eq(list[1].quest, 4, "the branch with a step done")
end)

test("the list: groups in order, and the three switches", function()
    Fake({ level = 30, bags = { 10, 10, 10, 10 }, slots = { [POUCH] = 8, [GUNNYSACK] = 12 } })
    local ns = Load()
    fakeData(ns, { { POUCH, "bag", 1 }, { GUNNYSACK, "bag", 2 }, { 901, "bag", 3 }, { 902, "bag", 4 } },
        { quest("Small", 10, 5), quest("Big", 10, 5), quest("Far", 50, 45), quest("Had", 10, 5) })
    W.slots[901], W.slots[902] = 14, 14
    W.done[4] = true
    local items, n = ns.List()
    eq(n, 3)
    eq(items[1].head, "now"); eq(items[2].quest, 2)
    eq(items[3].head, "later"); eq(items[4].quest, 3)
    eq(items[5].head, "done"); eq(items[6].quest, 4)
    ns.SetPref("better", false)
    items, n = ns.List()
    eq(n, 4, "the bag that is no bigger shows too")
    ns.SetPref("showDone", false)
    eq(select(2, ns.List()), 3)
    ns.SetHidden(2, true)
    eq(select(2, ns.List()), 2, "a hidden reward")
    eq(select(2, ns.List("ammo")), 0, "a kind with nothing")
    ns.Reset()
    eq(select(2, ns.List()), 3, "the defaults are back")
end)

test("what the open rewards add together, for the hub's line", function()
    Fake({ level = 30, bags = { 6, 8, 10, 10 }, slots = { [900] = 10, [901] = 12, [902] = 6 } })
    local ns = Load()
    fakeData(ns, { { 900, "bag", 1 }, { 901, "bag", 2 }, { 902, "bag", 3 } },
        { quest("A", 10, 5), quest("B", 10, 5), quest("C", 10, 5) })
    local gain, count = ns.Potential()
    eq(gain, (12 - 6) + (10 - 8)); eq(count, 2)
    local line, _, tile = ns.Summary()
    eq(line, "+8 slots · rewards: 2"); eq(tile.value, "+8")
    W.bags = { 14, 14, 14, 14 }
    eq(ns.Summary(), nil, "nothing beats the bags")
end)

test("the guide pins who gives the quest, then its work, then who takes it back", function()
    Fake({ level = 20, zone = WESTFALL, x = 50, y = 50, slots = { [POUCH] = 10 } })
    local ns = Load()
    assert(ns.StartGuide({ BLANCHY }))
    local pin = W.Pin()
    eq(pin[1], WESTFALL); eq(pin[2], 59.9); eq(pin[3], 19.4)
    eq(ns.stop.kind, "take")
    eq(GulliHUD.guide.owner, "WorthIt")
    W.log[BLANCHY] = true
    W.Fire("QUEST_ACCEPTED", 1, BLANCHY)
    W.now = W.now + 1; W.RunTimers()
    eq(ns.stop.kind, "work")
    eq(W.Pin()[2], 46.8)
    W.ready[BLANCHY] = true
    W.Fire("QUEST_LOG_UPDATE")
    W.now = W.now + 1; W.RunTimers()
    eq(ns.stop.kind, "turnin")
    eq(W.Pin()[3], 19.4)
    local pins = #W.pins
    W.Fire("QUEST_LOG_UPDATE")
    W.now = W.now + 1; W.RunTimers()
    eq(#W.pins, pins, "the same stop is not pinned again")
    W.log[BLANCHY] = nil
    W.Fire("QUEST_TURNED_IN", BLANCHY)
    eq(ns.Guiding(), false, "the last reward is got: the guide is done")
    eq(W.cleared, 1, "its pin is gone")
    eq(GulliHUD.guide, nil)
    eq(W.toasts[#W.toasts].key, "got")
    eq(find(ns.Rewards(), BLANCHY).state, "done", "before the game flags it")
end)

test("the guide goes to the nearest stop of the player's zone first", function()
    Fake({ level = 30, zone = WESTFALL, x = 80, y = 10 })
    local ns = Load()
    fakeData(ns, { { 900, "bag", 1 }, { 901, "bag", 2 }, { 902, "bag", 3 } },
        { quest("Near10", 10, 5, 10), quest("Near70", 10, 5, 70), quest("Later", 50, 45, 79) })
    assert(ns.StartGuide({ 1, 2, 3 }))
    local rows = ns.GuideRows()
    eq(rows[1].entry.quest, 2, "the nearest giver")
    eq(rows[2].entry.quest, 1)
    eq(rows[3].entry.quest, 3, "a reward that waits for a level goes last")
    local items = ns.TrackerItems()
    eq(#items, 3); eq(items[1].first, true)
    eq(items[1].what, "Take: Near70"); eq(items[1].where, "GiverNear70, Area40")
    eq(items[3].what, "From level 45"); eq(items[3].pin, nil)
    eq(ns.stop.quest, 2)
    local pins = #W.pins
    W.x = 10
    eq(ns.GuideRows()[1].entry.quest, 1, "the other giver is nearer now")
    ns.StepGuide()
    eq(ns.stop.quest, 2, "but the guide keeps the stop it leads to")
    eq(#W.pins, pins, "and sets no new pin")
end)

test("leading through all takes the open rewards that beat the bags", function()
    Fake({ level = 30, bags = { 10, 10, 10, 10 }, slots = { [900] = 8, [901] = 12 } })
    local ns = Load()
    fakeData(ns, { { 900, "bag", 1 }, { 901, "bag", 2 } }, { quest("Small", 10, 5), quest("Big", 10, 5) })
    assert(ns.StartGuide())
    eq(#ns.cdb.guide.targets, 1); eq(ns.cdb.guide.targets[1], 2)
    ns.SetHidden(2, true)
    eq(ns.Guiding(), false, "hiding the last reward ends the guide")
    eq(ns.StartGuide(), false, "nothing to lead to")
end)

test("one guide at a time: starting ours stops another module's", function()
    Fake({ level = 20 })
    local ns = Load()
    local stopped = 0
    GulliHUD = { guide = { owner = "DungeonPrep", stop = function() stopped = stopped + 1 end } }
    assert(ns.StartGuide({ BLANCHY }))
    eq(stopped, 1)
    eq(GulliHUD.guide.owner, "WorthIt")
    GulliHUD.guide.stop()
    eq(ns.Guiding(), false, "another module can stop ours")
end)

test("a guide kept over a reload leads on", function()
    Fake({ level = 20, cdb = { guide = { targets = { BLANCHY } }, told = {} } })
    local ns = Load()
    W.Fire("PLAYER_ENTERING_WORLD", false, true)
    W.now = W.now + 1; W.RunTimers()
    eq(GulliHUD.guide.owner, "WorthIt")
    eq(ns.stop.quest, BLANCHY)
    eq(#W.pins, 1)
end)

test("the map opens through the game's own event, never by the addon's call, and never in a fight", function()
    Fake({ level = 20, zone = WESTFALL, x = 50, y = 50, slots = { [POUCH] = 10 } })
    local ns = Load()
    local stop = ns.Stop(find(ns.Rewards(), BLANCHY))
    eq(ns.SetPin(stop, true), true)
    eq(W.maps[#W.maps], 10000 + WESTFALL, "C_Map.OpenWorldMap opens it")
    eq(W.tainted, nil, "OpenWorldMap would taint the map's pins")
    local n = #W.maps
    eq(ns.SetPin(stop), true)
    eq(#W.maps, n, "a pin alone, as the guide sets it, leaves the map shut")
    W.combat = true
    eq(ns.OpenMap(10000 + WESTFALL), false)
    eq(#W.maps, n)
    W.combat = nil
    C_Map.OpenWorldMap = nil
    eq(ns.OpenMap(10000 + WESTFALL), true)
    eq(W.tainted, 10000 + WESTFALL, "a client without it still opens the map")
end)

test("a giver on no map has no pin, and never an error", function()
    Fake({ level = 20 })
    local ns = Load()
    local q = ns.Data.quest[136]
    q[8], q[9], q[10] = 0, 0, 0
    local e = find(ns.Rewards(), 140)
    eq(e.cur, 136)
    local stop = ns.Stop(e)
    eq(stop.pin, false)
    eq(ns.SetPin(stop, true), false)
    assert(ns.StartGuide({ 140 }))
    eq(#W.pins, 0)
end)

test("a reward that opens is told once, never on the first login", function()
    Fake({ level = 8, hub = true, slots = { [POUCH] = 10 } })
    local ns = Load()
    W.Fire("PLAYER_ENTERING_WORLD", true, false)
    W.now = W.now + 1; W.RunTimers()
    eq(#W.toasts, 0, "the first look only notes what is open")
    W.level = 9
    W.Fire("PLAYER_LEVEL_UP", 9)
    W.now = W.now + 1; W.RunTimers()
    eq(#W.toasts, 1); eq(W.toasts[1].key, "new")
    eq(W.notes[#W.notes][1], "WorthIt")
    W.Fire("PLAYER_LEVEL_UP", 9)
    W.now = W.now + 1; W.RunTimers()
    eq(#W.toasts, 1, "told once")
end)

test("the notice switch stops the notice, the hub's feed still gets the line", function()
    Fake({ level = 8, hub = true, db = { notify = false }, cdb = { told = {} }, slots = { [POUCH] = 10 } })
    local ns = Load()
    W.level = 9
    eq(ns.CheckNew() > 0, true)
    eq(#W.toasts, 0)
    eq(#W.notes > 0, true)
end)

test("a paused module leads nowhere and tells nothing", function()
    Fake({ level = 20, hub = true, cdb = { told = {} } })
    local ns = Load()
    assert(ns.StartGuide({ BLANCHY }))
    W.registered.pause(true)
    eq(ns.Guiding(), false, "the guide ends")
    eq(ns.StartGuide({ BLANCHY }), false)
    eq(ns.CheckNew(), 0)
    eq(ns.Summary(), nil)
    W.Fire("QUEST_TURNED_IN", BLANCHY)
    eq(#W.toasts, 0)
    W.registered.pause(false)
    assert(ns.StartGuide({ BLANCHY }))
end)

test("it registers with the hub: window, summary, the tracker frame, three switches", function()
    Fake({ level = 20, hub = true })
    local ns = Load()
    local r = W.registered
    eq(r.key, "WorthIt"); eq(r.slash, "/gwi")
    eq(#r.options, 3)
    for _, o in ipairs(r.options) do
        local was = o.get()
        o.set(not was); eq(o.get(), not was); o.set(was)
    end
    assert(r.window(), "the window for the hub")
    eq(r.frames[1].get, nil, "the tracker shows by itself: no show switch")
    assert(r.frames[1].frame(), "the tracker for the Unlock mode")
    r.move(true)
    eq(ns.TrackerFrame():IsShown(), true, "shown to be placed")
    r.move(false)
    eq(ns.TrackerFrame():IsShown(), false)
    r.reset()
    eq(ns.db.better, true)
end)

test("the window opens, picks the first reward and follows the guide", function()
    Fake({ level = 20, slots = { [POUCH] = 10 } })
    local ns = Load()
    ns.Toggle()
    local frame, _, _, tabs, leadAll = ns.Parts()
    eq(frame:IsShown(), true)
    assert(ns.Selected(), "a reward is chosen")
    ns.Show(BLANCHY)
    eq(ns.Selected(), BLANCHY)
    leadAll._OnClick(leadAll)
    eq(ns.Guiding(), true)
    eq(ns.TrackerFrame():IsShown(), true)
    leadAll._OnClick(leadAll)
    eq(ns.Guiding(), false, "the same button stops")
    eq(ns.TrackerFrame():IsShown(), false)
    tabs:Select(2)
    ns.Slash("lead"); eq(ns.Guiding(), true)
    ns.Slash("stop"); eq(ns.Guiding(), false)
end)

test("random characters: the list and the guide never raise an error", function()
    math.randomseed(7)
    local classes = { "HUNTER", "WARLOCK", "PRIEST", "WARRIOR" }
    local seen = 0
    for round = 1, 60 do
        Fake({ level = math.random(1, 60), class = classes[math.random(#classes)],
               faction = round % 2 == 0 and "Horde" or "Alliance", raceId = math.random(1, 8),
               bags = { math.random(0, 16), math.random(0, 16), math.random(6, 16), math.random(6, 16) },
               family = { [4] = ({ 0, 1, 4, 32 })[math.random(4)] }, zone = ({ 40, 17, 10 })[math.random(3)],
               kalimdor = round % 3 == 0, x = 50, y = 50 })
        local ns = Load()
        for _, r in ipairs(ns.Data.rewards) do
            if math.random() < 0.3 then W.done[r[3]] = true end
            for _, id in ipairs(ns.Data.chain[r[3]] or {}) do
                local p = math.random()
                if p < 0.2 then W.done[id] = true elseif p < 0.4 then W.log[id] = true; W.ready[id] = math.random() < 0.5 end
            end
        end
        local items, n = ns.List()
        seen = seen + n
        for _, it in ipairs(items) do
            if not it.head then
                ns.Steps(it); ns.StateText(it); ns.GainText(it, ns.Bags())
                local stop = ns.Stop(it)
                if stop then ns.StopText(stop) end
                assert(it.state ~= "done" or it.group == "done")
            end
        end
        ns.Toggle()
        if ns.StartGuide() then ns.TrackerItems(); ns.StopGuide() end
        ns.Summary()
    end
    assert(seen > 100, "the rounds did list rewards")
end)

-- Class quests -------------------------------------------------------------------------------------

local CLASS_BITS = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128,
                     WARLOCK = 256, DRUID = 1024 }
-- Forged Steel (Horde warriors, Durotar, level 10): a weapon of four to choose from.
local FORGED, FORGED_1 = 1503, 1505

test("the data: class quests of every class, each with its quest, items and a chain that ends in it", function()
    Fake({})
    local D = Load().Data
    local by = {}
    assert(#D.class >= 80, "class quests")
    for _, r in ipairs(D.class) do
        local q = D.quest[r[1]]
        assert(q and #q == 17, "quest row of " .. r[1])
        assert(#r[3] >= 1, "items of " .. r[1])
        for bit = 0, 10 do if math.floor(r[2] / 2 ^ bit) % 2 == 1 then by[2 ^ bit] = true end end
        local chain = D.chain[r[1]]
        if chain then eq(chain[#chain], r[1], "chain end") end
    end
    for class, bit in pairs(CLASS_BITS) do assert(by[bit], class .. " has class quests") end
    local ids = {}
    for _, r in ipairs(D.class) do ids[r[1]] = r end
    -- raids WoW Forever has not opened stay out: Zul'Gurub, Ahn'Qiraj, Naxxramas; and quests past 60
    for _, gone in ipairs({ 8079, 8557, 9037, 8711, 84213 }) do eq(ids[gone], nil, "no quest " .. gone) end
    eq(#ids[FORGED][3], 4, "Forged Steel offers four weapons")
    eq(ids[1792][3][1], 6975, "Whirlwind Weapon gives the Whirlwind Axe")
end)

test("class quests are only the ones of the character's class and side", function()
    Fake({ level = 10, class = "WARRIOR", faction = "Horde", raceId = 2 })
    local ns = Load()
    local e = find(ns.ClassQuests(), FORGED)
    assert(e, "a Horde warrior sees Forged Steel")
    eq(e.class, true)
    eq(#e.options, 4)
    eq(e.chain[1], FORGED_1, "the chain starts at its first step")
    eq(e.state, "take")
    for _, x in ipairs(ns.ClassQuests()) do
        eq(math.floor(ns.Data.quest[x.quest][5] / 1) % 2 == 1 or ns.Data.quest[x.quest][5] == 0, true, "warrior quests only")
    end
    Fake({ level = 10, class = "WARRIOR", faction = "Alliance", raceId = 1 })
    eq(find(Load().ClassQuests(), FORGED), nil, "not for an Alliance warrior")
    Fake({ level = 10, class = "MAGE", faction = "Horde", raceId = 5 })
    eq(find(Load().ClassQuests(), FORGED), nil, "not for a mage")
end)

test("the class list: groups and the done switch, the bag switch does not hide a class quest", function()
    Fake({ level = 10, class = "WARRIOR", faction = "Horde", raceId = 2 })
    local ns = Load()
    ns.db.better = true
    local items = ns.List("class")
    eq(items[1].head, "now")
    assert(find(items, FORGED), "listed with only better on")
    W.done[FORGED] = true
    ns.db.showDone = true
    eq(find(ns.List("class"), FORGED).state, "done")
    ns.db.showDone = false
    eq(find(ns.List("class"), FORGED), nil, "done ones hidden with the switch off")
end)

test("the class quest's page lists its rewards, then the chain", function()
    Fake({ level = 10, class = "WARRIOR", faction = "Horde", raceId = 2 })
    local ns = Load()
    local e = find(ns.ClassQuests(), FORGED)
    local rows = ns.DetailRows(e)
    eq(rows[1].head, ns.L.CQ_CHOOSE_HEAD)
    for i = 2, 5 do assert(rows[i].item, "an item row") end
    local chain
    for _, r in ipairs(rows) do if r.head == ns.L.CHAIN then chain = true end end
    assert(chain, "the chain follows")
end)

test("the guide leads to a class quest, and through every open one", function()
    Fake({ level = 10, class = "WARRIOR", faction = "Horde", raceId = 2, zone = 17 })
    local ns = Load()
    eq(ns.StartGuide({ FORGED }), true)
    local items = ns.TrackerItems()
    eq(items[1].quest, FORGED)
    eq(ns.stop.quest, FORGED_1, "the first step of the chain")
    ns.StopGuide()
    eq(ns.StartGuide(nil, true), true)
    assert(#ns.cdb.guide.targets == #ns.Targets(true) and #ns.Targets(true) > 0, "every open class quest")
    ns.StopGuide()
end)

test("the window's class tab: picks a class quest, leads through all of them", function()
    Fake({ level = 10, class = "WARRIOR", faction = "Horde", raceId = 2, zone = 17 })
    local ns = Load()
    ns.Show(FORGED)
    local _, _, _, tabs, leadAll = ns.Parts()
    eq(ns.Selected(), FORGED, "Show opens the class tab on the quest")
    leadAll._OnClick(leadAll)
    eq(ns.Guiding(), true)
    eq(#ns.cdb.guide.targets, #ns.Targets(true), "leads through the class quests")
    leadAll._OnClick(leadAll)
    eq(ns.Guiding(), false)
    tabs:Select(1)
    assert(ns.Selected() ~= FORGED, "the rewards tab keeps its own choice")
end)

test("another class: its quests on this side, any race, nothing done or led", function()
    Fake({ level = 10, class = "MAGE", faction = "Horde", raceId = 5, zone = 17 })
    local ns = Load()
    eq(find(ns.ClassQuests(), FORGED), nil, "a mage's own list has no warrior quest")
    W.done[FORGED_1] = true
    local list = ns.ClassQuests(1)
    local e = find(list, FORGED)
    assert(e, "a Horde mage can look at the warriors' Forged Steel")
    eq(e.state, "other")
    eq(e.group, "all")
    eq(e.classId, 1)
    eq(e.chain[1], FORGED_1, "the whole chain from its first step")
    for _, st in ipairs(ns.Steps(e)) do eq(st.done, false, "nothing of this character counts") end
    for _, x in ipairs(list) do
        local mask = ns.Data.quest[x.quest][5]
        eq(mask == 0 or mask % 2 == 1, true, "warrior quests only")
        assert(ns.Data.quest[x.quest][6] ~= "A", "Horde side only")
    end
    for i = 2, #list do assert(list[i - 1].req <= list[i].req, "lowest level first") end
    local items, n = ns.List("class", 1)
    eq(items[1].head, "all")
    eq(n, #list)
    eq(#ns.Targets(true) == 0 or find(ns.Targets(true), FORGED) == nil, true, "the guide keeps to the own class")
    -- a class of the other side alone still shows its quests
    local ok = true
    for _, id in ipairs(ns.CLASSES) do
        if #ns.ClassQuests(id) == 0 then ok = false end
        assert(ns.ClassName(id) ~= "", "a name for class " .. id)
    end
    eq(ok, true, "every class has quests to look at")
    eq(#ns.ClassQuests(), #ns.ClassQuests(8), "the own class by id is the own list")
end)

test("the window's class picker: another class, then back to the own one with Show", function()
    Fake({ level = 10, class = "WARRIOR", faction = "Horde", raceId = 2, zone = 17 })
    local ns = Load()
    ns.Show(FORGED)
    ns.ViewClass(8)
    local _, list, detail, _, leadAll = ns.Parts()
    eq(leadAll:IsShown(), false, "no Lead all for another class")
    local sel = ns.Selected()
    assert(sel and sel ~= FORGED, "a mage quest is chosen")
    eq(detail.lead:IsShown(), false, "no Lead me on another class's quest")
    eq(detail.hide:IsShown(), false, "nor Hide")
    ns.Show(FORGED)
    eq(ns.Selected(), FORGED, "Show goes back to the own class")
    eq(detail.lead:IsShown(), true)
end)

test("random characters: the class list and its guide never raise an error", function()
    math.randomseed(11)
    local classes = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
    local seen = 0
    for round = 1, 45 do
        Fake({ level = math.random(1, 60), class = classes[(round - 1) % 9 + 1],
               faction = round % 2 == 0 and "Horde" or "Alliance", raceId = math.random(1, 8) })
        local ns = Load()
        for _, r in ipairs(ns.Data.class) do
            for _, id in ipairs(ns.Data.chain[r[1]] or { r[1] }) do
                local p = math.random()
                if p < 0.2 then W.done[id] = true elseif p < 0.3 then W.log[id] = true end
            end
        end
        local items, n = ns.List("class", round % 3 == 0 and ns.CLASSES[math.random(1, 9)] or nil)
        seen = seen + n
        for _, it in ipairs(items) do
            if not it.head then
                ns.DetailRows(it); ns.StateText(it)
                local stop = ns.Stop(it)
                if stop then ns.StopText(stop) end
            end
        end
        ns.Show((items[2] or {}).quest or 0)
        if ns.StartGuide(nil, true) then ns.TrackerItems(); ns.StopGuide() end
    end
    assert(seen > 100, "the rounds did list class quests")
end)

-- The library: Goaz Scrolls (Wetlands), Rumi of Gnomeregan (Loch Modan and Westfall), the first
-- reward (10 books) and a level-60 book that goes to a mage trainer.
local GOAZ, GOAZ_BOOK, RUMI, RUNES, POTATOES, TIER1, TIER2 = 78146, 209848, 79093, 78148, 84395, 78150, 79536
local LOCH = 38

-- n book quests of the lowest level, never Goaz Scrolls, Runes or Rumi.
local function bookIds(ns, n)
    local out, keep = {}, { [GOAZ] = true, [RUNES] = true, [RUMI] = true }
    for _, b in ipairs(ns.Data.books) do
        if #out == n then break end
        if not keep[b[1]] then out[#out + 1] = b[1] end
    end
    return out
end

test("the data: library books with their places and who takes them back, four rewards", function()
    Fake({})
    local ns = Load()
    local D = ns.Data
    assert(#D.books >= 39, "every book: " .. #D.books)
    local items = {}
    for _, b in ipairs(D.books) do
        assert(not items[b[2]], "one book per item")
        items[b[2]] = true
        assert(#b[4] >= 3 and #b[4] % 3 == 0, "a place for " .. b[1])
        assert(D.takers[b[5]], "who takes back " .. b[1])
    end
    eq(#D.tiers, 4)
    for i, t in ipairs(D.tiers) do
        assert(#t[4] > 0 and t[5].A and t[5].H, "rewards and givers of " .. t[1])
        if i > 1 then assert(t[2] > D.tiers[i - 1][2], "fewest books first") end
    end
    eq(D.takers[1].A[1], "Garion Wendell")
    eq(D.takers[2].H[1], "Oran Snakewrithe")
end)

test("a book is done, in the bags, to pick up or for later; the rewards follow the books", function()
    Fake({ level = 30, items = { [GOAZ_BOOK] = 1 } })
    local ns = Load()
    for _, id in ipairs(bookIds(ns, 9)) do W.done[id] = true end
    local lib = ns.Library()
    eq(lib.handed, 9)
    eq(lib.bags, 1)
    eq(find(lib.books, GOAZ).state, "bag")
    eq(find(lib.books, GOAZ).group, "bags")
    eq(find(lib.books, RUNES).state, "take")
    eq(find(lib.books, POTATOES).state, "later", "a level-60 book waits at 30")
    eq(lib.tiers[1].state, "wait")
    eq(lib.tiers[1].left, 1)
    W.done[GOAZ] = true
    lib = ns.Library()
    eq(lib.tiers[1].state, "ready")
    eq(lib.tiers[2].state, "wait")
    W.log[TIER1] = true
    eq(ns.Library().tiers[1].state, "log")
    W.done[TIER1] = true
    eq(ns.Library().tiers[1].state, "done")
    W.level = 10
    for _, id in ipairs(bookIds(ns, 20)) do W.done[id] = true end
    eq(ns.Library().tiers[2].state, "later", "enough books, the level missing")
end)

test("the book list: in the bags, to pick up, later, handed in; the done switch", function()
    Fake({ level = 30, items = { [GOAZ_BOOK] = 1 } })
    local ns = Load()
    W.done[RUNES] = true
    local items = ns.BookList()
    eq(items[1].head, "bags")
    eq(items[2].quest, GOAZ)
    eq(items[#items].quest ~= nil and items[#items].state, "done")
    ns.db.showDone = false
    eq(find(ns.BookList(), RUNES), nil)
end)

test("a book in two places is picked up in the player's zone, and handed in by side", function()
    Fake({ level = 30, zone = LOCH, faction = "Horde" })
    local ns = Load()
    local rumi = ns.Book(RUMI)
    eq(#rumi.places, 2)
    eq(ns.BookPlace(rumi).area, LOCH)
    W.zone = 40
    eq(ns.BookPlace(rumi).area, 40)
    W.items[ns.Book(RUMI).item] = 1
    local stop = ns.BookStop(ns.Book(RUMI))
    eq(stop.kind, "handin")
    eq(stop.who, "Owen Thadd")
    W.items[228132] = 1
    eq(ns.BookStop(ns.Book(POTATOES)).who, "Oran Snakewrithe", "a level-60 book goes to the mage trainer")
end)

test("the library guide: every book is a stop, the books in the bags one stop per taker, a ready reward its own", function()
    Fake({ level = 30, zone = LOCH, x = 70, y = 20, items = { [GOAZ_BOOK] = 1 } })
    local ns = Load()
    for _, id in ipairs(bookIds(ns, 8)) do W.done[id] = true end
    W.items[ns.Book(RUMI).item] = 1
    eq(ns.StartLibrary(), true)
    eq(ns.LeadsLibrary(), true)
    local rows = ns.GuideRows()
    local hand, claim, picks = 0, 0, 0
    for _, r in ipairs(rows) do
        if r.stop.kind == "handin" then hand = hand + 1; eq(r.stop.count, 2)
        elseif r.stop.kind == "claim" then claim = claim + 1
        else picks = picks + 1 end
    end
    eq(hand, 1, "both books go to the librarian in one stop")
    eq(claim, 0, "ten books are not handed in yet")
    local lib = ns.Library()
    local open = 0
    for _, e in ipairs(lib.books) do if e.state == "take" or e.state == "later" then open = open + 1 end end
    eq(picks, open, "every book to pick up is a stop")
    eq(rows[1].stop.zone, "Area" .. LOCH, "the player's zone first")
    eq(rows[1].stop.kind, "pick")
    eq(rows[#rows].later, true, "the books for later last")
    eq(W.Pin()[1], LOCH, "the first stop is pinned")
    ns.StopGuide()
    W.done[GOAZ], W.items[GOAZ_BOOK], W.done[RUMI] = true, 0, true
    ns.StartLibrary()
    local found
    for _, r in ipairs(ns.GuideRows()) do if r.stop.kind == "claim" then found = r.stop end end
    eq(found.who, "Garion Wendell", "the ready reward is a stop")
end)

test("the tracker shows at most ten library stops and counts the rest", function()
    Fake({ level = 60, zone = LOCH, x = 70, y = 20, hub = true })
    local ns = Load()
    ns.StartLibrary()
    local items, more = ns.TrackerItems()
    eq(#items, ns.TRACK_BOOKS)
    eq(ns.TRACK_BOOKS, 10)
    eq(more, #ns.GuideRows() - 10)
    assert(more > 0, "the rest is counted")
    for _, it in ipairs(items) do assert(it.book and it.name and it.where, "a two-line book row") end
    eq(items[1].first, true)
    ns.RefreshTracker()
    local tr = ns.TrackerFrame()
    local shown = 0
    for _, r in ipairs(tr.rows) do if r:IsShown() then shown = shown + 1 end end
    eq(shown, 10)
    eq(tr.more:IsShown(), true)
    eq(tr.title:GetText(), ns.L.TR_LIB)
    -- a reward guide keeps its own six rows
    ns.StopGuide()
    ns.StartGuide()
    local _, rest = ns.TrackerItems()
    assert(#ns.TrackerItems() <= ns.TRACK_MAX)
    eq(rest, math.max(0, #ns.GuideRows() - ns.TRACK_MAX))
end)

test("the library guide ends when there is nothing left, and one guide leads at a time", function()
    Fake({ level = 60 })
    local ns = Load()
    for _, b in ipairs(ns.Data.books) do W.done[b[1]] = true end
    for _, t in ipairs(ns.Data.tiers) do W.done[t[1]] = true end
    eq(ns.StartLibrary(), false)
    W.done[RUNES] = nil
    local stopped
    GulliHUD = { guide = { owner = "DungeonPrep", stop = function() stopped = true end } }
    eq(ns.StartLibrary(), true)
    eq(stopped, true)
    eq(GulliHUD.guide.owner, "WorthIt")
    ns.OnTurnedIn(RUNES)
    W.done[RUNES] = true
    eq(ns.Guiding(), false, "the last book handed in ends the guide")
end)

test("a book that comes into the bags and a reward that opens are told once, never on the first look", function()
    Fake({ level = 30, hub = true })
    local ns = Load()
    for _, id in ipairs(bookIds(ns, 9)) do W.done[id] = true end
    eq(ns.CheckBooks(), 0)
    W.items[GOAZ_BOOK] = 1
    eq(ns.CheckBooks(), 1)
    eq(#W.toasts, 1)
    assert(W.toasts[1].text:find("Garion Wendell", 1, true), "says who takes it")
    eq(ns.CheckBooks(), 0, "once")
    W.items[GOAZ_BOOK] = 0
    W.done[GOAZ] = true
    ns.db.notify = false
    eq(ns.CheckBooks(), 1, "the first reward opened")
    eq(#W.toasts, 1, "no notice with the switch off")
    eq(#W.notes, 2, "the hub's feed gets both")
    ns.Pause(true)
    W.items[ns.Book(RUNES).item] = 1
    eq(ns.CheckBooks(), 0, "a paused module tells nothing")
end)

test("the window's library tab: the rewards, the books, a book's page and the guide", function()
    Fake({ level = 30, zone = LOCH, items = { [GOAZ_BOOK] = 1 } })
    local ns = Load()
    ns.Show(RUMI)
    local frame, list, detail, tabs, leadAll, _, ladder = ns.Parts()
    eq(ns.Selected(), RUMI, "Show opens the library on the book")
    eq(#ladder.tiles, 4)
    eq(ladder.tiles[1].need:GetText() ~= nil, true)
    assert(detail.name:GetText():find("Item208860", 1, true), "the book's page")
    eq(detail.places[2]:IsShown(), true, "both places")
    leadAll._OnClick(leadAll)
    eq(ns.LeadsLibrary(), true)
    eq(leadAll:GetText(), ns.L.STOP)
    leadAll._OnClick(leadAll)
    eq(ns.Guiding(), false)
    detail.map._OnClick(detail.map)
    eq(W.Pin()[1], LOCH, "Show on map pins the place in the player's zone")
    tabs:Select(1)
    assert(ns.Selected() ~= RUMI, "the rewards tab keeps its own choice")
    tabs:Select(4)
end)

test("random characters: the library and its guide never raise an error, the tracker never passes ten", function()
    math.randomseed(23)
    local seen = 0
    for round = 1, 40 do
        Fake({ level = math.random(1, 60), faction = round % 2 == 0 and "Horde" or "Alliance",
               zone = ({ 38, 40, 17, 148, 10 })[math.random(5)], kalimdor = round % 3 == 0, x = 50, y = 50 })
        local ns = Load()
        for _, b in ipairs(ns.Data.books) do
            local p = math.random()
            if p < 0.4 then W.done[b[1]] = true elseif p < 0.6 then W.items[b[2]] = 1 end
        end
        for _, t in ipairs(ns.Data.tiers) do if math.random() < 0.3 then W.done[t[1]] = true end end
        local items, n = ns.BookList()
        seen = seen + n
        for _, it in ipairs(items) do if not it.head then ns.BookSub(it) end end
        ns.Show(ns.Data.books[math.random(#ns.Data.books)][1])
        ns.CheckBooks()
        if ns.StartLibrary() then
            local tr = ns.TrackerItems()
            assert(#tr <= 10, "at most ten rows")
            for _, it in ipairs(tr) do assert(it.name, "a name") end
            ns.StopGuide()
        end
    end
    assert(seen > 200, "the rounds did list books")
end)

W.finish()
