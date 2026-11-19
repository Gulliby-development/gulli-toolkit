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

test("a quest started by an item has no pin, and never an error", function()
    Fake({ level = 20 })
    local ns = Load()
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

W.finish()
