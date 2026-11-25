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

test("a quest a player shares waits for the switch and for Gulli Social", function()
    Fake({})
    local ns = Load()
    local sharer
    UnitIsPlayer = function(u) return u == "questnpc" and sharer ~= nil end
    local baseName = UnitName
    UnitName = function(u) if u == "questnpc" then return sharer end return baseName(u) end
    sharer = "Bob"
    W.Fire("QUEST_DETAIL"); eq(#W.did, 0, "shared quests need their switch")
    ns.db.shared = true
    GulliSocial = { DeclinesShare = function(name) return name == "Bob" end }
    W.Fire("QUEST_DETAIL"); W.Fire("QUEST_ACCEPT_CONFIRM", "Bob")
    eq(#W.did, 0, "Social turns Bob away")
    sharer = "Ann"
    W.Fire("QUEST_DETAIL")
    eq(#W.did > 0, true)
    GulliSocial, UnitIsPlayer = nil, nil
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

test("a talk line alone goes on by itself; a service line, two lines or Shift never", function()
    Fake({ npc = { active = {}, available = {} } })
    local ns = Load()
    local talk = function(id) return { gossipOptionID = id, icon = 132053, status = 0, flags = 0 } end
    W.options = { talk(42) }
    W.Fire("GOSSIP_SHOW"); eq(W.did[1], "option:42", "on by default")
    W.options = { talk(43) }
    W.Fire("GOSSIP_SHOW"); eq(W.did[2], "option:43", "the next step of the talk")
    W.Fire("GOSSIP_SHOW"); eq(#W.did, 2, "the same line again waits for the player")
    W.Fire("GOSSIP_CLOSED")
    for _, icon in ipairs({ 132060, 132057, 132058, 132050, 132052, 0 }) do
        W.options = { { gossipOptionID = 7, icon = icon, status = 0, flags = 0 } }
        W.Fire("GOSSIP_SHOW"); eq(#W.did, 2, "a vendor, flight, trainer, bank or inn line: " .. icon)
    end
    W.options = { { gossipOptionID = 8, icon = 132060, status = 0, flags = 1 } }
    W.Fire("GOSSIP_SHOW"); eq(W.did[3], "option:8", "a line the game marks as a quest line")
    W.options = { { gossipOptionID = 9, icon = 132053, status = 0, flags = 0, spellID = 1234 } }
    W.Fire("GOSSIP_SHOW"); eq(#W.did, 3, "a line that casts a spell")
    W.options = { { gossipOptionID = 10, icon = 132053, status = 2, flags = 0 } }
    W.Fire("GOSSIP_SHOW"); eq(#W.did, 3, "a locked line")
    W.options = { talk(1), talk(2) }
    W.Fire("GOSSIP_SHOW"); eq(#W.did, 3, "two lines: the player picks")
    W.options = { talk(11) }
    W.shift = true
    W.Fire("GOSSIP_SHOW"); eq(#W.did, 3, "Shift skips it")
    W.shift = false
    ns.db.gossip = false
    W.Fire("GOSSIP_SHOW"); eq(#W.did, 3, "the switch stops it")
    ns.db.gossip = true
    W.Fire("GOSSIP_CLOSED")
    for i = 1, ns.TALK_MAX + 3 do W.options = { talk(100 + i) }; W.Fire("GOSSIP_SHOW") end
    eq(#W.did, 3 + ns.TALK_MAX, "a talk that never ends stops")
end)

test("older saves get talk lines on once", function()
    Fake({ db = { gossip = false } })
    local ns = Load()
    eq(ns.db.gossip, true)
    ns.db.gossip = false
    W.Fire("ADDON_LOADED", "Gulli-AutoQuest")
    eq(ns.db.gossip, false, "the player's own choice stays")
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
    W.Fire("PLAYER_LOGOUT")
    W.Fire("PLAYER_ENTERING_WORLD", true, false)
    eq(ns.db.session.taken, 1, "a quick relog keeps the session")
    W.now = W.now + ns.Skin.RELOG_KEEP + 1
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
    eq(ns.EVENT_QUESTS[94927], true, "Dunston Checks Out is an escort")
    eq(ns.EVENT_QUESTS[86796], true, "Later, Satyr is an escort")
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
    eq(b:GetAttribute("macrotext"), mac(false, "Young Wolf", "Kobold Vermin", "Forest Spider"), "the next kind comes first, the others in the list's order")
    tgt = { name = "Young Wolf" }
    eq(click(b), mac(true, "Young Wolf", "Kobold Vermin", "Forest Spider"), "a living wolf: the next wolf, the target stays")
    eq(b:GetAttribute("macrotext"), mac(false, "Young Wolf", "Kobold Vermin", "Forest Spider"), "the macro back, no kind skipped")
    tgt = { name = "Kobold Vermin" }
    eq(click(b), mac(true, "Kobold Vermin", "Young Wolf", "Forest Spider"), "a living kobold: the next kobold")
    tgt.dead = true
    eq(click(b), mac(false, "Young Wolf", "Kobold Vermin", "Forest Spider"), "a corpse is no reason to stay")
    tgt = { name = "Stormwind Guard" }
    eq(click(b), mac(false, "Kobold Vermin", "Young Wolf", "Forest Spider"), "another unit: cleared, the next pick (the top kind again)")
    eq(b:GetAttribute("macrotext"), mac(false, "Forest Spider", "Kobold Vermin", "Young Wolf"), "then the last kind, in turn")
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
    eq(btn:GetAttribute("macrotext"), mac(false, "Murloc", "Kobold Vermin", "Young Wolf", "Forest Spider"),
       "the big button tries the kinds in the list's order too")
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
    eq(rows[2].face.tex:IsShown(), true, "the icon stays while there is no model")
    eq(#W.timers > 0, true, "tried again later")
    cached = true
    W.RunTimers()
    eq(rawget(wolf, "creature"), 299, "drawn once the client has it")
    eq(wolf:IsShown(), true)
    eq(rows[2].face.tex:IsShown(), false, "no icon behind the model")
    -- The big button shows the mob its next press tries first.
    ns.db.mobIds["Forest Spider"] = 300
    cached = true
    ns.PaintFaces()
    eq(rawget(btn.model, "creature"), 300, "the spider, at the top of the list")
    eq(btn.icon:IsShown(), false, "no icon behind the button's model")
    UnitName = function(u) if u == "player" then return "Tester" end end
    eq(click(btn), mac(false, "Forest Spider", "Young Wolf", "Murloc", "Kobold Vermin"), "the top kind first, the others in the list's order")
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

test("quest mob list: the mobs that drop an item to collect join it, with the item's count", function()
    Fake({ qlog = { { title = "Elwynn Forest", isHeader = true },
                    { questID = 50, obj = { { type = "monster", text = "Kobold Vermin slain: 3/10" },
                                            { type = "item", text = "Gnoll Paw: 2/8", numFulfilled = 2, numRequired = 8 },
                                            { type = "item", text = "Wolf Fang: 8/8", finished = true } } } } })
    local ns = Load()
    ns.DROPS = { [50] = { { 900, 7001, 7002 }, { 901, 7003 } } }
    ns.NPC_NAME = { [7001] = "Riverpaw Gnoll", [7002] = "Kobold Vermin", [7003] = "Gray Wolf" }
    local list = ns.QuestMobList()
    local t = {}
    for i, m in ipairs(list) do t[i] = m.name .. " " .. m.have .. "/" .. m.need end
    eq(table.concat(t, ","), "Kobold Vermin 3/10,Riverpaw Gnoll 2/8",
       "a dropper with the item's count; a mob to kill once; a finished item's droppers left out")
    eq(list[2].id, 7001)
    eq(ns.db.mobIds["Riverpaw Gnoll"], 7001, "its face by id")
    -- The item named by the text wins over the order.
    C_Item.GetItemNameByID = function(id) return id == 901 and "Gnoll Paw" or "Wolf Fang" end
    list = ns.QuestMobList()
    eq(list[2] and list[2].name, "Gray Wolf", "the row of the item the text names")
    C_Item.GetItemNameByID = nil
    -- Another client language: the client's own name by id, once it has the creature.
    GetLocale = function() return "ruRU" end
    local cached = false
    C_TooltipInfo = { GetHyperlink = function(link)
        if cached and link:find("%-7001%-") then return { lines = { { leftText = "Гнолл Речной Лапы" } } } end
    end }
    local l2, pending = ns.QuestMobList()
    eq(#l2, 1, "no English name on a Russian client")
    eq(pending, true)
    W.timers = {}
    local got = made("GulliAutoQuestTarget")
    ns.SetTargetButton(true)
    local b = got()
    eq(#W.timers > 0, true, "asked again later")
    cached = true
    W.RunTimers()
    eq(b:GetAttribute("macrotext"), mac(false, "Kobold Vermin", "Гнолл Речной Лапы"), "the button looks for it too")
    C_TooltipInfo = nil
end)

test("quest mob button: the kinds at the top of the list come up more often, each in turn", function()
    local ns = Load and (function() Fake({ qlog = {} }); return Load() end)()
    ns.picks = {}
    local seen, now = {}, 1
    for _ = 1, 1900 do
        local r = ns.NextPick(19, now)
        eq(r ~= now, true, "never the kind just tried")
        seen[r] = (seen[r] or 0) + 1
        now = r
    end
    for r = 1, 19 do eq((seen[r] or 0) > 0, true, "kind " .. r .. " comes up") end
    eq(seen[1] > seen[3] and seen[3] > seen[10] and seen[10] > seen[19], true, "the top ones more often")
    eq(seen[1] > 2.5 * seen[19], true)
    eq(ns.NextPick(1, 1), 1)
    local o = ns.PressOrder({ "a", "b", "c", "d" }, 3)
    eq(table.concat(o, ","), "c,a,b,d")
end)

test("quest mob list: where the mobs live decides, from the data", function()
    Fake({ qlog = { { title = "Un'Goro Crater", isHeader = true },
                    { questID = 60, obj = { { type = "monster", text = "Diemetradon slain: 2/8" },
                                            { type = "item", text = "Raptor Head: 1/5", numFulfilled = 1, numRequired = 5 } } },
                    { questID = 62, obj = { { type = "monster", text = "Servants of Grol Freed: 0/1" } } },
                    { title = "Tanaris", isHeader = true },
                    { questID = 4504, obj = { { type = "item", text = "Super Sticky Tar: 7/12", numFulfilled = 7, numRequired = 12 } } },
                    { questID = 61, obj = { { type = "monster", text = "Sandfury Troll slain: 0/10" },
                                            { type = "monster", text = "Tar Beast slain: 1/4" } } } } })
    GetRealZoneText = function() return "Un'Goro Crater" end
    local ns = Load()
    ns.DROPS = { [4504] = { { 11834, 7246, 6518, 6519 } }, [60] = { { 900, 6505, 6506 } } }
    ns.KILLS = { [60] = { { 9163 } }, [61] = { { 5646 }, { 6527 } }, [62] = { { 7669 } } }
    ns.NPC_NAME = { [6518] = "Tar Lurker", [6519] = "Tar Lord", [7246] = "Sandfury Shadowhunter",
                    [6505] = "Ravasaur", [6506] = "Ravasaur Runner", [9163] = "Diemetradon",
                    [5646] = "Sandfury Troll", [6527] = "Tar Beast", [7669] = "Servant of Grol" }
    ns.NPC_AREAS = { [6518] = { 490 }, [6519] = { 490 }, [7246] = { 440 }, [6505] = { 490 },
                     [6506] = { 490 }, [9163] = { 490 }, [5646] = { 440 }, [6527] = { 490 }, [7669] = { 4 } }
    C_Map = C_Map or {}
    local was = C_Map.GetAreaInfo
    C_Map.GetAreaInfo = function(a) return ({ [490] = "Un'Goro Crater", [440] = "Tanaris", [4] = "Blasted Lands" })[a] end
    local function names()
        local t = {}
        for i, m in ipairs(ns.QuestMobList()) do t[i] = m.name .. " " .. m.have .. "/" .. m.need end
        return table.concat(t, ",")
    end
    eq(names(), "Diemetradon 2/8,Servant of Grol 0/1,Tar Beast 1/4,Ravasaur 1/5,Ravasaur Runner 1/5,Tar Lurker 7/12,Tar Lord 7/12",
       "this zone's quests; the Tanaris quests only for their mobs here; a group text looks for the mob the data names")
    -- In Tanaris the Tanaris quests count, and a dropper of Un'Goro is no reason to go there.
    GetRealZoneText = function() return "Tanaris" end
    eq(names(), "Sandfury Troll 0/10,Tar Beast 1/4,Sandfury Shadowhunter 7/12")
    -- A home quest whose droppers the data places nowhere still looks for them.
    ns.NPC_AREAS = { [5646] = { 440 } }
    eq(names(), "Sandfury Troll 0/10,Tar Beast 1/4,Sandfury Shadowhunter 7/12,Tar Lurker 7/12,Tar Lord 7/12")
    C_Map.GetAreaInfo = was
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
