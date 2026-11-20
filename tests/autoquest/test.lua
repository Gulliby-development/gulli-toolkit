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

test("quest mob key: names from the objectives, the zone's last, bound to the secure button", function()
    Fake({ qlog = {
        { title = "Elwynn Forest", isHeader = true },
        { questID = 1, obj = { { type = "monster", text = "Kobold Vermin slain: 3/10" },
                                { type = "item", text = "Linen Cloth: 1/5" } } },
        { questID = 2, obj = { { type = "monster", text = "Murloc slain: 10/10", finished = true } } },
        { title = "Westfall", isHeader = true },
        { questID = 3, obj = { { type = "monster", text = "0/8 Harvest Watcher slain" },
                                { type = "monster", text = "Kobold Vermin slain: 0/2" } } },
    } })
    local ns = Load()
    eq(ns.MobName("Defias Pillager slain: 3/8"), "Defias Pillager")
    eq(ns.MobName("3/8 Defias Pillager slain"), "Defias Pillager")
    eq(ns.MobName(nil), nil)
    local mobs = ns.QuestMobs()
    eq(table.concat(mobs, ","), "Harvest Watcher,Kobold Vermin", "finished and item objectives left out, the zone's last")
    eq(ns.TargetMacro(mobs), "/targetexact Harvest Watcher\n/targetexact Kobold Vermin\n/cleartarget [dead]")
    eq(ns.TargetMacro({}), nil)
    ns.TARGET_MAX = 50
    eq(ns.TargetMacro(mobs), "/targetexact Kobold Vermin\n/cleartarget [dead]", "cut from the front")
    ns.TARGET_MAX = 900
    ns.SetTargetKey("F")
    eq(W.bindings.F, "GulliAutoQuestTarget")
    W.qlog[3].obj = {}
    W.Fire("QUEST_LOG_UPDATE")
    W.combat = true
    W.qlog[2].obj = { { type = "monster", text = "Murloc slain: 1/10" } }
    W.Fire("QUEST_LOG_UPDATE")
    W.combat = false
    W.Fire("PLAYER_REGEN_ENABLED")
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
    local made
    local create = CreateFrame
    CreateFrame = function(kind, name, ...)
        local f = create(kind, name, ...)
        if name == "GulliAutoQuestTarget" then made = f end
        return f
    end
    ns.SetTargetKey("F")
    eq(made:GetAttribute("macrotext"), "/targetexact Kobold Vermin\n/cleartarget [dead]")
    W.combat = true
    W.qlog[2].obj = { { type = "monster", text = "Murloc slain: 1/10" } }
    W.Fire("QUEST_LOG_UPDATE")
    eq(made:GetAttribute("macrotext"), "/targetexact Kobold Vermin\n/cleartarget [dead]", "no secure change in a fight")
    W.combat = false
    W.Fire("PLAYER_REGEN_ENABLED")
    eq(made:GetAttribute("macrotext"), "/targetexact Murloc\n/cleartarget [dead]", "after the fight")
    reg.pause(true)
    eq(W.bindings.F, nil, "paused from the hub")
    reg.pause(false)
    eq(W.bindings.F, "GulliAutoQuestTarget")
    CreateFrame = create
end)

test("quest mob key: each press goes to the next living quest mob, never a corpse", function()
    Fake({ qlog = { { title = "Elwynn Forest", isHeader = true },
                    { questID = 1, obj = { { type = "monster", text = "Kobold Vermin slain: 3/10" } } } } })
    local ns = Load()
    local made
    local create = CreateFrame
    CreateFrame = function(kind, name, ...)
        local f = create(kind, name, ...)
        if name == "GulliAutoQuestTarget" then made = f end
        return f
    end
    -- Five plates: a corpse nearest, two living kobolds, one tagged by another player, a wolf.
    local plates = {
        nameplate1 = { name = "Kobold Vermin", guid = "C-1", dead = true },
        nameplate2 = { name = "Kobold Vermin", guid = "C-3" },
        nameplate3 = { name = "Kobold Vermin", guid = "C-2" },
        nameplate4 = { name = "Kobold Vermin", guid = "C-4", tapped = true },
        nameplate5 = { name = "Young Wolf", guid = "C-5" },
    }
    local target
    C_NamePlate = { GetNamePlates = function()
        local list = {}
        for i = 1, 5 do if plates["nameplate" .. i] then list[#list + 1] = { namePlateUnitToken = "nameplate" .. i } end end
        return list
    end }
    UnitName = function(u) if u == "player" then return "Tester" end return plates[u] and plates[u].name end
    UnitGUID = function(u)
        if u == "target" then return target end
        return plates[u] and plates[u].guid
    end
    UnitIsDead = function(u) return plates[u] and plates[u].dead or false end
    UnitIsTapDenied = function(u) return plates[u] and plates[u].tapped or false end
    UnitCanAttack = function() return true end
    local live = ns.LiveQuestMobs(ns.QuestMobs())
    eq(#live, 2, "the corpse, the tagged mob and the wolf are left out")
    eq(live[1].unit, "nameplate3", "a fixed order")
    ns.SetTargetKey("F")
    eq(made:GetAttribute("type"), "target")
    eq(made:GetAttribute("unit"), "nameplate3", "no target: the first")
    target = "C-2"
    W.Fire("PLAYER_TARGET_CHANGED")
    eq(made:GetAttribute("unit"), "nameplate2", "the next one")
    target = "C-3"
    W.Fire("PLAYER_TARGET_CHANGED")
    eq(made:GetAttribute("unit"), "nameplate3", "round the list")
    target = "C-1"
    W.Fire("PLAYER_TARGET_CHANGED")
    eq(made:GetAttribute("unit"), "nameplate3", "from the corpse to a living one")
    -- A name the game hides is skipped, not an error.
    issecretvalue = function(v) return v == "C-3" end
    eq(#ns.LiveQuestMobs(ns.QuestMobs()), 1, "a secret guid is left out")
    issecretvalue = nil
    -- The fight: the names macro, which drops a corpse.
    W.Fire("PLAYER_REGEN_DISABLED")
    eq(made:GetAttribute("type"), "macro")
    eq(made:GetAttribute("macrotext"), "/targetexact Kobold Vermin\n/cleartarget [dead]")
    W.combat = true
    target = "C-2"
    W.Fire("PLAYER_TARGET_CHANGED")
    eq(made:GetAttribute("type"), "macro", "no secure change in a fight")
    W.combat = false
    W.Fire("PLAYER_REGEN_ENABLED")
    eq(made:GetAttribute("unit"), "nameplate2", "cycling again after the fight")
    -- Every quest mob dead: the macro again.
    plates.nameplate2.dead, plates.nameplate3.dead = true, true
    W.Fire("NAME_PLATE_UNIT_REMOVED")
    eq(made:GetAttribute("type"), "macro")
    C_NamePlate, UnitIsDead, UnitIsTapDenied, UnitCanAttack = nil, nil, nil, nil
    CreateFrame = create
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
