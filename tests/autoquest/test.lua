-- Run from the repository root: lua5.1 tests/autoquest/test.lua
local W = dofile("tests/autoquest/wow.lua")
local test, eq = W.test, W.eq

test("every language has every text", function()
    Fake({})
    W.CheckLocales(Load())
end)

test("at an NPC a finished quest comes before a new one", function()
    Fake({ npc = { active = { { 5, false }, { 6, true } }, available = { { 7, false } } } })
    Load()
    W.Fire("GOSSIP_SHOW")
    eq(W.did[1], "active:6")
    W.npc.active = { { 5, false } }
    W.Fire("GOSSIP_SHOW")
    eq(W.did[2], "available:7")
    eq(#W.did, 2)
end)

test("gray quests are skipped unless the switch is off", function()
    Fake({ npc = { active = {}, available = { { 7, true } } } })
    local ns = Load()
    W.Fire("GOSSIP_SHOW")
    eq(#W.did, 0)
    ns.db.skipTrivial = false
    W.Fire("GOSSIP_SHOW")
    eq(W.did[1], "available:7")
end)

test("the old greeting window works too", function()
    Fake({ npc = { active = { { 1, true } }, available = {} } })
    Load()
    W.Fire("QUEST_GREETING")
    eq(W.did[1], "active#1")
end)

test("accept, complete and take the only reward", function()
    Fake({})
    Load()
    W.Fire("QUEST_DETAIL")
    W.Fire("QUEST_PROGRESS")
    W.choices = 1
    W.Fire("QUEST_COMPLETE")
    eq(table.concat(W.did, ","), "accept,complete,reward:1")
end)

test("a choice of rewards is left to the player, with a hint", function()
    Fake({})
    Load()
    W.choices, W.prices = 3, { [1] = 10, [2] = 500, [3] = 20 }
    W.Fire("QUEST_COMPLETE")
    eq(#W.did, 0)
    assert(W.printed[#W.printed]:find("item:2", 1, true))
end)

test("a quest that asks for gold or is not ready is not handed in", function()
    Fake({})
    Load()
    W.moneyToGet = 100
    W.Fire("QUEST_PROGRESS")
    W.moneyToGet, W.completable = 0, false
    W.Fire("QUEST_PROGRESS")
    eq(#W.did, 0)
end)

test("Shift and the switches stop it", function()
    Fake({ npc = { active = { { 6, true } }, available = { { 7, false } } } })
    local ns = Load()
    W.shift = true
    W.Fire("GOSSIP_SHOW"); W.Fire("QUEST_DETAIL")
    eq(#W.did, 0)
    W.shift = false
    ns.db.accept, ns.db.turnIn = false, false
    W.Fire("GOSSIP_SHOW"); W.Fire("QUEST_DETAIL"); W.Fire("QUEST_PROGRESS")
    eq(#W.did, 0)
    ns.Toggle()
end)

test("pause: a switch, a timer and a chosen key; no Shift needed", function()
    Fake({ npc = { active = { { 6, true } }, available = {} } })
    local ns = Load()
    ns.SetPaused(true)
    W.Fire("GOSSIP_SHOW"); eq(#W.did, 0)
    ns.SetPaused(false)
    ns.PauseFor(5)
    W.Fire("GOSSIP_SHOW"); eq(#W.did, 0, "paused for 5 minutes")
    W.now = W.now + 301
    W.Fire("GOSSIP_SHOW"); eq(#W.did, 1, "the timer ran out")
    ns.db.pauseKey = "CTRL"
    W.shift, W.ctrl = true, false
    W.Fire("GOSSIP_SHOW"); eq(#W.did, 2, "Shift is no longer the key")
    W.ctrl = true
    W.Fire("GOSSIP_SHOW"); eq(#W.did, 2)
    ns.db.pauseKey = "NONE"
    W.Fire("GOSSIP_SHOW"); eq(#W.did, 3)
end)

test("an ignored NPC and an ignored quest are left alone", function()
    Fake({ npc = { active = {}, available = { { 7, false }, { 8, false } } }, npcID = 500 })
    local ns = Load()
    W.Fire("GOSSIP_SHOW")
    eq(ns.last.npc, 500)
    ns.IgnoreQuest(7, "Seven")
    W.Fire("GOSSIP_SHOW")
    eq(W.did[2], "available:8", "quest 7 is skipped")
    ns.IgnoreNpc(500, "Bob")
    W.Fire("GOSSIP_SHOW")
    eq(#W.did, 2)
    eq(#ns.Ignored(), 2); eq(ns.Ignored()[1].kind, "npc")
    ns.Unignore("npc", 500)
    W.Fire("GOSSIP_SHOW"); eq(#W.did, 3)
    SlashCmdList.GULLIAUTOQUEST("ignore")
    eq(ns.db.ignoreNpc[500] ~= nil, true)
end)

test("quests shared by the group wait for their switch", function()
    Fake({})
    local ns = Load()
    W.Fire("QUEST_ACCEPT_CONFIRM"); eq(#W.did, 0, "off by default")
    ns.db.shared = true
    W.Fire("QUEST_ACCEPT_CONFIRM"); eq(W.did[1], "confirm")
end)

test("a quest that takes non-quest items is not handed in unless allowed", function()
    Fake({})
    local ns = Load()
    W.required = { "item:2589" }; W.classes["item:2589"] = 7
    W.Fire("QUEST_PROGRESS"); eq(#W.did, 0)
    assert(W.printed[#W.printed]:find("2589"))
    W.classes["item:2589"] = 12
    W.Fire("QUEST_PROGRESS"); eq(W.did[1], "complete", "quest items are fine")
    W.classes["item:2589"] = 7; ns.db.itemQuests = true
    W.Fire("QUEST_PROGRESS"); eq(W.did[2], "complete")
end)

test("elite, dungeon and group quests and a full log follow their switches", function()
    Fake({})
    local ns = Load()
    W.tags[101] = { tagID = 81 }
    W.Fire("QUEST_DETAIL"); eq(W.did[1], "accept", "off by default")
    ns.db.skipDungeon = true
    W.Fire("QUEST_DETAIL"); eq(#W.did, 1)
    W.tags[101] = { tagID = 0, isElite = true }; ns.db.skipElite = true
    W.Fire("QUEST_DETAIL"); eq(#W.did, 1)
    W.tags[101] = nil; W.group = 3; ns.db.skipGroup = true
    W.Fire("QUEST_DETAIL"); eq(#W.did, 1)
    W.group = 0; ns.db.minFree = 2; W.log = 18
    W.Fire("QUEST_DETAIL"); eq(#W.did, 1, "two places left")
    W.log = 17
    W.Fire("QUEST_DETAIL"); eq(W.did[2], "accept")
end)

test("the best vendor price: marked, or taken when asked", function()
    Fake({})
    local ns = Load()
    W.choices, W.prices = 3, { [1] = 10, [2] = 500, [3] = 20 }
    W.Fire("QUEST_COMPLETE"); eq(#W.did, 0)
    ns.db.pickBest = true
    W.Fire("QUEST_COMPLETE"); eq(W.did[1], "reward:2")
end)

test("the only gossip line waits for its switch", function()
    Fake({ npc = { active = {}, available = {} } })
    local ns = Load()
    W.options = { { gossipOptionID = 42 } }
    W.Fire("GOSSIP_SHOW"); eq(#W.did, 0)
    ns.db.gossip = true
    W.Fire("GOSSIP_SHOW"); eq(W.did[1], "option:42")
    W.options = { { gossipOptionID = 1 }, { gossipOptionID = 2 } }
    W.Fire("GOSSIP_SHOW"); eq(#W.did, 1, "two lines: the player picks")
end)

test("counters survive a reload, a login resets them; undo abandons the last quest; feed and summary", function()
    local notes = {}
    Fake({})
    GulliToolkit = { Register = function(t) W.reg = t end, Notify = function(_, t) notes[#notes + 1] = t end }
    local ns = Load()
    W.Fire("QUEST_DETAIL")
    W.Fire("QUEST_ACCEPTED", 101)
    eq(ns.db.session.taken, 1)
    eq(ns.last.accepted, 101)
    W.RunTimers()
    eq(notes[1], ns.L.FEED:format(1, 0))
    eq(W.reg.summary(), ns.L.FEED:format(1, 0))
    W.Fire("PLAYER_ENTERING_WORLD", false, true)
    eq(ns.db.session.taken, 1, "a reload keeps the session")
    ns.Undo()
    eq(W.did[#W.did], "abandon")
    W.Fire("PLAYER_ENTERING_WORLD", true, false)
    eq(ns.db.session.taken, nil, "a new login starts over")
    ns.db.accept = false; ns.db.paused = true
    W.reg.reset()
    eq(ns.db.accept, true); eq(ns.db.paused, false)
    GulliToolkit = nil
end)

test("the window draws every tab", function()
    Fake({})
    local ns = Load()
    for i = 1, 3 do ns.ShowTab(i) end
end)

test("paused from the hub it takes no quest", function()
    Fake({ npc = { active = { { 6, true } }, available = {} } })
    local reg
    GulliToolkit = { Register = function(t) reg = t end }
    Load()
    GulliToolkit = nil
    reg.pause(true)
    W.Fire("GOSSIP_SHOW")
    eq(#W.did, 0, "paused")
    reg.pause(false)
    W.Fire("GOSSIP_SHOW")
    eq(W.did[1], "active:6", "started again")
end)

test("an escort or event quest waits for the player while others are in the group", function()
    Fake({ questID = 155, npc = { active = {}, available = { { 155, false }, { 7, false } } } })
    local ns = Load()
    eq(ns.EVENT_QUESTS[155], true, "The Defias Brotherhood is an escort")
    eq(ns.EVENT_QUESTS[7], nil)
    IsInGroup = function() return true end
    GetNumGroupMembers = function() return 3 end
    W.Fire("QUEST_DETAIL")
    eq(#W.did, 0, "not taken in a group")
    eq(ns.SkipNew(155), "WHY_EVENT")
    W.Fire("GOSSIP_SHOW")
    eq(W.did[1], "available:7", "the NPC's other quest is opened, not the escort")
    GetNumGroupMembers = function() return 1 end
    IsInGroup = function() return false end
    W.did = {}
    W.Fire("QUEST_DETAIL")
    eq(W.did[1], "accept", "alone it is taken as before")
    IsInGroup, GetNumGroupMembers = nil, nil
end)

-- The quest mob macro: no target out of a fight, then the names from the first on; keep leaves
-- the target for a press on a living mob of the first name.
local function mac(keep, ...)
    local l = {}
    if not keep then l[1] = "/cleartarget [nocombat]" end
    for i, n in ipairs({ ... }) do
        l[#l + 1] = (i == 1 and "/targetexact " or "/targetexact [noexists] ") .. n
        l[#l + 1] = "/cleartarget [dead]"
    end
    return table.concat(l, "\n")
end

local function made(name)
    local found
    local create = CreateFrame
    CreateFrame = function(kind, n, ...)
        local f = create(kind, n, ...)
        if n == name then found = f end
        return f
    end
    return function() CreateFrame = create; return found end
end

-- A click as the game makes it: the press half, then the release that runs the macro.
local function click(b)
    for _, down in ipairs({ true, false }) do
        local pre, post = rawget(b, "_PreClick"), rawget(b, "_PostClick")
        if pre then pre(b, "LeftButton", down) end
        local text = b:GetAttribute("macrotext")
        if post then post(b, "LeftButton", down) end
        if not down then return text end
    end
end

test("quest mob key: names and counts from the objectives of the zone only, bound to the secure button", function()
    Fake({ qlog = {
        { title = "Elwynn Forest", isHeader = true },
        { questID = 1, obj = { { type = "monster", text = "Kobold Vermin slain: 3/10" },
                                { type = "item", text = "Linen Cloth: 1/5" } } },
        { questID = 2, obj = { { type = "monster", text = "Murloc slain: 10/10", finished = true } } },
        { title = "Westfall", isHeader = true },
        { questID = 3, obj = { { type = "monster", text = "0/8 Harvest Watcher slain", numFulfilled = 2, numRequired = 8 },
                                { type = "monster", text = "Kobold Vermin slain: 0/2" } } },
    } })
    local ns = Load()
    eq(ns.MobName("Defias Pillager slain: 3/8"), "Defias Pillager")
    eq(ns.MobName("3/8 Defias Pillager slain"), "Defias Pillager")
    eq(ns.MobName(nil), nil)
    local mobs = ns.QuestMobs()
    eq(table.concat(mobs, ","), "Kobold Vermin", "finished, item and other zones' objectives left out")
    local list = ns.QuestMobList()
    eq(list[1].have .. "/" .. list[1].need, "3/10", "read from the text")
    W.zone = "Westfall"
    list = ns.QuestMobList()
    eq(list[1].name .. " " .. list[1].have .. "/" .. list[1].need, "Harvest Watcher 2/8", "another zone, the game's numbers win")
    eq(#list, 2)
    W.zone = "Tanaris"
    eq(#ns.QuestMobList(), 0, "no quest of the zone, no mob")
    W.zone = nil
    mobs = { "Kobold Vermin", "Harvest Watcher" }
    eq(ns.TargetMacro(mobs), mac(false, "Kobold Vermin", "Harvest Watcher"))
    eq(ns.TargetMacro(mobs, 2), mac(false, "Harvest Watcher", "Kobold Vermin"), "from the second, round the list")
    eq(ns.TargetMacro(mobs, 2, true), mac(true, "Harvest Watcher", "Kobold Vermin"))
    eq(ns.TargetMacro({}), nil)
    ns.TARGET_MAX = 90
    eq(ns.TargetMacro(mobs), mac(false, "Kobold Vermin"), "cut from the end, the first stays")
    ns.TARGET_MAX = 255
    ns.SetTargetKey("F")
    eq(W.bindings.F, "GulliAutoQuestTarget")
    ns.SetTargetKey(nil)
    eq(W.bindings.F, nil, "no key, no binding")
end)

test("quest mob key: the macro follows the quest log, waits for the end of a fight, and pausing frees the key", function()
    local reg
    GulliToolkit = { Register = function(t) reg = t end }
    Fake({ qlog = { { title = "Elwynn Forest", isHeader = true },
                    { questID = 1, obj = { { type = "monster", text = "Kobold Vermin slain: 3/10" } } } } })
    GulliToolkit = { Register = function(t) reg = t end }
    local ns = Load()
    GulliToolkit = nil
    local got = made("GulliAutoQuestTarget")
    ns.SetTargetKey("F")
    local b = got()
    eq(b:GetAttribute("type"), "macro")
    eq(b:GetAttribute("useOnKeyDown"), false, "the macro runs on the release")
    eq(b:GetAttribute("macrotext"), mac(false, "Kobold Vermin"))
    W.combat = true
    W.qlog[2].obj = { { type = "monster", text = "Murloc slain: 1/10" } }
    W.Fire("QUEST_LOG_UPDATE")
    eq(b:GetAttribute("macrotext"), mac(false, "Kobold Vermin"), "no secure change in a fight")
    W.combat = false
    W.Fire("PLAYER_REGEN_ENABLED")
    eq(b:GetAttribute("macrotext"), mac(false, "Murloc"), "after the fight")
    reg.pause(true)
    eq(W.bindings.F, nil, "paused from the hub")
    reg.pause(false)
    eq(W.bindings.F, "GulliAutoQuestTarget")
end)

test("quest mob key: a press on a living quest mob goes to the next of it, else the next kind", function()
    Fake({ qlog = { { title = "Elwynn Forest", isHeader = true },
                    { questID = 1, obj = { { type = "monster", text = "Kobold Vermin slain: 3/10" },
                                           { type = "monster", text = "Young Wolf slain: 0/5" },
                                           { type = "monster", text = "Forest Spider slain: 1/4" } } } } })
    local ns = Load()
    local got = made("GulliAutoQuestTarget")
    ns.SetTargetKey("F")
    local b = got()
    local tgt
    UnitExists = function(u) return u == "target" and tgt ~= nil end
    UnitIsDead = function(u) return u == "target" and tgt and tgt.dead or false end
    UnitName = function(u) if u == "player" then return "Tester" end if u == "target" then return tgt and tgt.name end end
    eq(click(b), mac(false, "Kobold Vermin", "Young Wolf", "Forest Spider"), "no target: the first kind, the others behind it")
    eq(b:GetAttribute("macrotext"), mac(false, "Young Wolf", "Forest Spider", "Kobold Vermin"), "the next kind comes first")
    tgt = { name = "Young Wolf" }
    eq(click(b), mac(true, "Young Wolf", "Forest Spider", "Kobold Vermin"), "a living wolf: the next wolf, the target stays")
    eq(b:GetAttribute("macrotext"), mac(false, "Young Wolf", "Forest Spider", "Kobold Vermin"), "the macro back, no kind skipped")
    tgt = { name = "Kobold Vermin" }
    eq(click(b), mac(true, "Kobold Vermin", "Young Wolf", "Forest Spider"), "a living kobold: the next kobold")
    tgt.dead = true
    eq(click(b), mac(false, "Young Wolf", "Forest Spider", "Kobold Vermin"), "a corpse is no reason to stay")
    tgt = { name = "Stormwind Guard" }
    eq(click(b), mac(false, "Forest Spider", "Kobold Vermin", "Young Wolf"), "another unit: cleared, the next kind")
    -- A name the game hides counts as no target.
    tgt = { name = "Young Wolf" }
    issecretvalue = function(v) return v == "Young Wolf" end
    eq(ns.CycleIndex(ns.QuestMobs()), nil)
    issecretvalue = nil
    -- In a fight nothing secure changes: the press runs the macro set before it.
    W.Fire("PLAYER_REGEN_DISABLED")
    W.combat = true
    local before = b:GetAttribute("macrotext")
    eq(click(b), before)
    eq(b:GetAttribute("macrotext"), before)
    W.combat = false
    UnitExists, UnitIsDead = nil, nil
end)

test("quest mob list: a row per kind with its count, a click targets that kind, its face once seen", function()
    Fake({ qlog = { { title = "Elwynn Forest", isHeader = true },
                    { questID = 1, obj = { { type = "monster", text = "Kobold Vermin slain: 3/10" },
                                           { type = "monster", text = "Young Wolf slain: 0/5" } } } } })
    local ns = Load()
    local rows = {}
    local create = CreateFrame
    CreateFrame = function(kind, n, ...)
        local f = create(kind, n, ...)
        local i = n and tonumber(n:match("^GulliAutoQuestTargetRow(%d+)$"))
        if i then rows[i] = f end
        return f
    end
    ns.SetTargetButton(true)
    eq(#rows, 2)
    eq(rows[1]:IsShown() and rows[2]:IsShown(), true)
    eq(rows[2]:GetAttribute("macrotext"), mac(false, "Young Wolf"))
    eq(rows[1].count:GetText():find("10") ~= nil, true, "the count of the kind")
    local tgt
    UnitExists = function(u) return u == "target" and tgt ~= nil end
    UnitName = function(u) if u == "player" then return "Tester" end if u == "target" or u == "nameplate1" then return tgt and tgt.name end end
    tgt = { name = "Young Wolf" }
    eq(click(rows[2]), mac(true, "Young Wolf"), "again: the next wolf")
    eq(rows[2]:GetAttribute("macrotext"), mac(false, "Young Wolf"))
    local faced
    SetPortraitTexture = function(tex, unit) faced = unit end
    W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    eq(faced, "nameplate1", "the wolf's face")
    -- A kind done in a fight keeps its row, dimmed; after the fight the rows follow the log.
    W.combat = true
    W.qlog[2].obj[2].finished = true
    W.Fire("QUEST_LOG_UPDATE")
    eq(rows[2]:IsShown(), true, "a secure row waits for the end of the fight")
    W.combat = false
    W.Fire("PLAYER_REGEN_ENABLED")
    eq(rows[2]:IsShown(), false)
    eq(rows[2]:GetAttribute("macrotext"), nil)
    CreateFrame, UnitExists, SetPortraitTexture = create, nil, nil
end)

test("quest mob list: the kinds worked on last come first, the faces are models once the client has them", function()
    Fake({ qlog = { { title = "Elwynn Forest", isHeader = true },
                    { questID = 1, obj = { { type = "monster", text = "Kobold Vermin slain: 3/10" },
                                           { type = "monster", text = "Young Wolf slain: 0/5" },
                                           { type = "monster", text = "Forest Spider slain: 1/4" },
                                           { type = "monster", text = "Murloc slain: 0/6" } } } } })
    local ns = Load()
    eq(ns.NpcId("Creature-0-1-2-3-299-0000"), 299)
    eq(ns.NpcId("Player-1-0000"), nil)
    eq(ns.NpcId(nil), nil)
    local rows, models = {}, {}
    local create = CreateFrame
    CreateFrame = function(kind, n, ...)
        local f = create(kind, n, ...)
        local i = n and tonumber(n:match("^GulliAutoQuestTargetRow(%d+)$"))
        if i then rows[i] = f end
        if kind == "PlayerModel" then
            models[#models + 1] = f
            rawset(f, "SetCreature", function(self, id) rawset(self, "creature", id) end)
        end
        return f
    end
    local b = made("GulliAutoQuestTarget")
    ns.SetTargetButton(true)
    local btn = b()
    local function mobs() local t = {} for i = 1, 3 do t[i] = rawget(rows[i], "mob") end return table.concat(t, ",") end
    eq(#rows, 3, "three rows")
    eq(mobs(), "Kobold Vermin,Young Wolf,Forest Spider", "the log's order at first")
    W.now = W.now + 10
    W.qlog[2].obj[4].text = "Murloc slain: 1/6"
    W.Fire("QUEST_LOG_UPDATE")
    eq(mobs(), "Murloc,Kobold Vermin,Young Wolf", "a murloc killed: its row comes first")
    eq(rows[1]:GetAttribute("macrotext"), mac(false, "Murloc"))
    eq(btn:GetAttribute("macrotext"), mac(false, "Kobold Vermin", "Young Wolf", "Forest Spider", "Murloc"),
       "the big button keeps every kind in the log's order")
    -- A fight with a wolf: the wolf first, set just before the lockdown.
    local tgt = { name = "Young Wolf" }
    UnitName = function(u) if u == "player" then return "Tester" end if u == "target" then return tgt.name end end
    UnitGUID = function(u) if u == "target" then return "Creature-0-1-2-3-299-0000" end end
    W.now = W.now + 10
    W.Fire("PLAYER_REGEN_DISABLED")
    eq(mobs(), "Young Wolf,Murloc,Kobold Vermin", "the mob fought comes first")
    W.combat = true
    W.now = W.now + 10
    W.qlog[2].obj[3].text = "Forest Spider slain: 2/4"
    W.Fire("QUEST_LOG_UPDATE")
    eq(mobs(), "Young Wolf,Murloc,Kobold Vermin", "no secure change in a fight")
    W.combat = false
    W.Fire("PLAYER_REGEN_ENABLED")
    eq(mobs(), "Forest Spider,Young Wolf,Murloc", "after the fight, the spider killed in it first")
    -- The wolf's face: its npc id is kept once the game shows it, the model waits for the client.
    local cached = false
    C_TooltipInfo = { GetHyperlink = function() if cached then return { lines = { { leftText = "Young Wolf" } } } end end }
    W.timers = {}
    W.Fire("PLAYER_TARGET_CHANGED")
    eq(ns.db.mobIds["Young Wolf"], 299, "the id kept by name")
    local wolf = rows[2].model
    eq(rawget(wolf, "creature"), nil, "not in the client's cache yet")
    eq(#W.timers > 0, true, "tried again later")
    cached = true
    W.RunTimers()
    eq(rawget(wolf, "creature"), 299, "drawn once the client has it")
    eq(wolf:IsShown(), true)
    -- The big button shows the mob its next press tries first.
    ns.db.mobIds["Kobold Vermin"] = 300
    cached = true
    ns.PaintFaces()
    eq(rawget(btn.model, "creature"), 300)
    UnitName = function(u) if u == "player" then return "Tester" end end
    eq(click(btn), mac(false, "Kobold Vermin", "Young Wolf", "Forest Spider", "Murloc"))
    eq(rawget(btn.model, "creature"), 299, "the next kind's face")
    -- A name the game hides is never kept.
    issecretvalue = function(v) return v == "Murloc" end
    tgt = { name = "Murloc" }
    UnitName = function(u) if u == "player" then return "Tester" end if u == "target" then return tgt.name end end
    W.Fire("PLAYER_TARGET_CHANGED")
    eq(ns.db.mobIds.Murloc, nil)
    issecretvalue = nil
    -- The number of rows is the player's: 0 to ns.LIST_MAX, 3 at first.
    eq(ns.db.mobRows, 3)
    ns.SetMobRows(4)
    eq(rows[4] and rows[4]:IsShown(), true, "a fourth row")
    ns.SetMobRows(1)
    eq(rows[1]:IsShown() and not rows[2]:IsShown(), true, "one row")
    W.combat = true
    ns.SetMobRows(0)
    eq(rows[1]:IsShown(), true, "a secure row waits for the end of the fight")
    W.combat = false
    W.Fire("PLAYER_REGEN_ENABLED")
    eq(rows[1]:IsShown(), false, "no list")
    eq(btn:GetAttribute("macrotext") ~= nil, true, "the button still works")
    CreateFrame, C_TooltipInfo = create, nil
end)

test("quest mob button: shows from the hub's switch while a quest needs a mob, clicks like the key", function()
    local reg
    GulliToolkit = { Register = function(t) reg = t end }
    Fake({ qlog = { { title = "Elwynn Forest", isHeader = true },
                    { questID = 1, obj = { { type = "monster", text = "Kobold Vermin slain: 3/10" } } } } })
    GulliToolkit = { Register = function(t) reg = t end }
    local ns = Load()
    GulliToolkit = nil
    local fr = reg.frames[1]
    eq(fr.get(), false, "starts hidden")
    local holder = fr.frame()
    eq(holder:IsShown(), false)
    fr.set(true)
    eq(holder:IsShown(), true, "on, and a quest needs a mob")
    eq(W.bindings.F, nil, "no key needed")
    W.qlog[2].obj = {}
    W.Fire("QUEST_LOG_UPDATE")
    eq(holder:IsShown(), false, "nothing to kill")
    reg.move(true)
    eq(holder:IsShown(), true, "the Unlock mode shows it")
    reg.move(false)
    eq(holder:IsShown(), false)
    W.qlog[2].obj = { { type = "monster", text = "Murloc slain: 1/10" } }
    W.Fire("QUEST_LOG_UPDATE")
    eq(holder:IsShown(), true)
    W.combat = true
    fr.set(false)
    eq(holder:IsShown(), true, "a secure frame waits for the end of the fight")
    W.combat = false
    W.Fire("PLAYER_REGEN_ENABLED")
    eq(holder:IsShown(), false)
    fr.set(true)
    reg.pause(true)
    eq(holder:IsShown(), false, "paused from the hub")
end)

W.finish()
