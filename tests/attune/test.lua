-- Run from the repository root: lua5.1 tests/attune/test.lua
local W = dofile("tests/attune/wow.lua")
local test, eq = W.test, W.eq

local function raid(ns, char, key)
    for _, r in ipairs(ns.RaidsFor(char)) do
        if r.key == key then return ns.Progress(char, r) end
    end
end

test("a scan saves done and active quests for this character", function()
    Fake({ done = { [4742] = true, [4743] = true, [4182] = true }, active = { [4183] = true } })
    local ns = Load()
    ns.Scan()
    local c = ns.db.chars["Tester-Realm"]
    eq(c.done[4742], true)
    eq(c.active[4183], true)
    eq(c.faction, "Alliance")
    eq(raid(ns, c, "UBRS").ready, true)
    local ony = raid(ns, c, "ONY")
    eq(ony.done, 1)
    eq(ony.next[1], 4183, "the next step is the first one not done")
    eq(ony.steps[2].state, "active")
    eq(ony.ready, false)
end)

test("each faction sees its own Onyxia chain", function()
    Fake({ faction = "Horde" })
    local ns = Load()
    ns.Scan()
    local c = ns.db.chars["Tester-Realm"]
    local ony = raid(ns, c, "ONY")
    eq(ony.steps[1].step[1], 4903)
    eq(ony.total, 14)
end)

test("the amulet or the key in the bags means ready", function()
    Fake({ items = { [16309] = 1, [12344] = 1 } })
    local ns = Load()
    ns.Scan()
    local c = ns.db.chars["Tester-Realm"]
    eq(raid(ns, c, "ONY").ready, true)
    eq(raid(ns, c, "UBRS").ready, true)
    eq(raid(ns, c, "BRD").ready, false)
end)

test("other characters stay; this one comes first; forget removes one", function()
    Fake({ db = { chars = { ["Alt-Realm"] = { name = "Alt", level = 60, faction = "Alliance", done = {}, active = {} },
                            ["Low-Realm"] = { name = "Low", level = 20, faction = "Alliance", done = {}, active = {} } } },
           level = 10 })
    local ns = Load()
    ns.Scan()
    local list = ns.Chars()
    eq(list[1].key, "Tester-Realm"); eq(list[2].key, "Alt-Realm"); eq(list[3].key, "Low-Realm")
    ns.Forget("Low-Realm")
    eq(#ns.Chars(), 2)
end)

test("names: the game's quest and zone names first, then English", function()
    Fake({ titles = { [4182] = "Угроза драконов" }, areas = { [46] = "Пылающие степи" } })
    local ns = Load()
    local ony = ns.RAIDS[1]
    local step = ony.steps[1]
    eq(ns.QuestName(step), "Угроза драконов")
    eq(ns.Where(step), "Helendis Riverhorn, Пылающие степи")
    eq(ns.RaidName(ony), "Onyxia's Lair")
end)

test("events scan after a short pause; the window opens", function()
    Fake({})
    local ns = Load()
    W.Fire("QUEST_TURNED_IN")
    W.Fire("QUEST_ACCEPTED")
    eq(#W.timers, 1)
    W.RunTimers()
    assert(ns.db.chars["Tester-Realm"])
    SlashCmdList.GULLIATTUNE("")
    ns.Refresh()
end)

test("dungeon keys: the chain or the key in the bags; Scholomance has a chain per faction", function()
    Fake({ done = { [3801] = true, [3802] = true }, items = { [17191] = 1 } })
    local ns = Load()
    ns.Scan()
    local c = ns.db.chars["Tester-Realm"]
    eq(raid(ns, c, "BRD").ready, true)
    eq(raid(ns, c, "MARA").ready, true, "the Scepter of Celebras in the bags")
    local sch = raid(ns, c, "SCHOLO")
    eq(sch.steps[1].step[1], 5092)
    eq(sch.total, 8)
    Fake({ faction = "Horde", items = { [13704] = 1 } })
    ns = Load()
    ns.Scan()
    c = ns.db.chars["Tester-Realm"]
    sch = raid(ns, c, "SCHOLO")
    eq(sch.steps[1].step[1], 5096)
    eq(sch.ready, true, "the Skeleton Key in the bags")
end)

test("City of Dalaran (Forever): the sewer key chain per faction, or the key in the bags", function()
    Fake({ faction = "Horde", done = { [544] = true, [93680] = true } })
    local ns = Load()
    ns.Scan()
    local c = ns.db.chars["Tester-Realm"]
    local d = raid(ns, c, "DALARAN")
    eq(d.total, 5)
    eq(d.steps[1].step[1], 544, "Prison Break In for the Horde")
    eq(d.ready, false)
    Fake({ faction = "Alliance", items = { [277507] = 1 } })
    ns = Load()
    ns.Scan()
    c = ns.db.chars["Tester-Realm"]
    d = raid(ns, c, "DALARAN")
    eq(d.steps[1].step[1], 92432, "An Alarming Request for the Alliance")
    eq(d.ready, true, "the Dalaran Sewer Key in the bags")
end)

test("only what WoW Forever has: Onyxia first, no Molten Core, Blackwing Lair or Naxxramas", function()
    Fake({})
    local ns = Load()
    eq(ns.RAIDS[1].key, "ONY")
    for _, r in ipairs(ns.RAIDS) do
        assert(r.key ~= "MC" and r.key ~= "BWL" and r.key ~= "NAXX", r.key .. " is not in Forever")
        assert(ns.T.en["RAID_" .. r.key], "no name for " .. r.key)
    end
end)

test("steps side by side: the four Tests of Skulls open together, Ascension after all four", function()
    Fake({ faction = "Horde", done = { [4903] = true, [4941] = true, [4974] = true, [6566] = true, [6567] = true,
                                       [6568] = true, [6569] = true, [6570] = true, [6583] = true } })
    local ns = Load()
    ns.Scan()
    local ony = raid(ns, ns.db.chars["Tester-Realm"], "ONY")
    local open = {}
    for _, s in ipairs(ony.nexts) do open[#open + 1] = s[1] end
    eq(table.concat(open, ","), "6582,6584,6585", "three tests left, all open at once")
    eq(ony.next[1], 6582)
    for _, x in ipairs(ony.steps) do
        if x.step[1] == 6601 then eq(x.open, false, "Ascension waits for every test") end
    end
    eq(ony.pct, math.floor(9 * 100 / 14))
end)

test("what a step needs: level, kind and items, with the bag count", function()
    Fake({ faction = "Horde", items = { [16786] = 1 } })
    local ns = Load()
    local ony
    for _, r in ipairs(ns.RAIDS) do if r.key == "ONY" and r.faction == "Horde" then ony = r end end
    local n = ns.Needs(ony.steps[9])
    eq(n.level, 55); eq(n.tag, "elite"); eq(n.items[1].id, 16869)
    eq(ns.Needs(ony.steps[14]).tag, "raid")
    eq(ns.Needs(ns.RAIDS[3].steps[1]).tag, "dungeon", "a step inside Blackrock Spire")
    eq(ns.Needs(ony.steps[7]).items[1].id, 16786, "Oculus Illusions asks for the Black Dragonflight Molt")
    eq(ns.Have(16786), 1)
    for _, r in ipairs(ns.RAIDS) do
        for _, s in ipairs(r.steps) do assert(ns.INFO[s[1]], "no info for " .. s[1]) end
    end
end)

test("only reachable chains: a level 30 sees no Onyxia until it starts it", function()
    Fake({ level = 30 })
    local ns = Load()
    ns.Scan()
    local c = ns.db.chars["Tester-Realm"]
    eq(ns.Available(c, ns.RAIDS[1]), false)
    eq(ns.Available(c, ns.RAIDS[#ns.RAIDS]), false, "Maraudon from 41 is too far at 30")
    c.level = 36
    eq(ns.Available(c, ns.RAIDS[#ns.RAIDS]), true, "five levels away is near enough")
    c.done[4182] = true
    eq(ns.Available(c, ns.RAIDS[1]), true, "a started chain always shows")
end)

test("a map pin on the next step, in its zone", function()
    local W = Fake({ areas = { [46] = "Burning Steppes" }, maps = { [1428] = { "Burning Steppes", 1415 } } })
    local ns = Load()
    eq(ns.SetPin(ns.RAIDS[1].steps[1]), true)
    eq(W.pins[1].map, 1428); eq(W.pins[1].x, 0.858)
    eq(ns.SetPin(ns.RAIDS[1].steps[9]), false, "inside Blackrock Depths: no spot")
end)

test("group: state goes out on the prefix, comes back in, fills tooltips and who lacks access", function()
    local W = Fake({ party = { "Bob", "Ann" }, done = { [4742] = true, [4743] = true } })
    local ns = Load()
    ns.Scan()
    eq(ns.SendState("PARTY"), true)
    eq(W.addon[1].prefix, "GulliAT")
    eq(W.addon[1].msg, "S\tONY=0/16,UBRS=R,BRD=0/2,SCHOLO=0/8,DALARAN=0/2,MARA=0/2")
    ns.Receive("GulliAT", "S\tONY=9/16,UBRS=R", "PARTY", "Bob-Realm")
    eq(ns.others.Bob.raids.ONY.done, 9)
    eq(ns.others.Bob.raids.UBRS.ready, true)
    local tt = ns.TooltipLines("Bob")
    eq(tt[1], "Onyxia's Lair: 9 of 16 steps"); eq(tt[2], "Upper Blackrock Spire: Ready")
    eq(table.concat(ns.Missing("ONY"), ","), "Tester,Bob,Ann", "Ann did not answer: counted as without")
    eq(table.concat(ns.Missing("UBRS"), ","), "Ann")
    ns.TellGroup("ONY")
    eq(W.chat[1].channel, "PARTY"); eq(W.chat[1].msg, "Without Onyxia's Lair: Tester, Bob, Ann")
    ns.Receive("GulliAT", "H", "PARTY", "Ann")
    eq(#W.addon, 2, "a question gets our state")
    ns.Set("groupMsg", false)
    eq(ns.SendState("PARTY"), false, "the switch stops the messages")
    ns.Receive("GulliAT", "S\tONY=R", "PARTY", "Ann")
    eq(ns.others.Ann, nil)
    ns.Set("tooltip", false)
    eq(#ns.TooltipLines("Bob"), 0)
end)

test("ask the guild only in a guild", function()
    local W = Fake({ guild = true })
    local ns = Load()
    eq(ns.AskGuild(), true); eq(W.addon[1].channel, "GUILD"); eq(W.addon[1].msg, "H")
    Fake({})
    eq(Load().AskGuild(), false)
end)

test("news: a step done and a chain ready go to the hub; the guild only with the switch", function()
    local W = Fake({ guild = true, done = { [4742] = true } })
    local ns = Load()
    local notes = {}
    GulliToolkit = { Notify = function(_, t) notes[#notes + 1] = t end }
    ns.Scan()
    W.done[4182] = true
    ns.Scan()
    eq(notes[1], "Onyxia's Lair: step 1 of 16 done")
    W.done[4743] = true
    ns.Scan()
    eq(notes[2], "Upper Blackrock Spire: ready!")
    eq(#W.chat, 0, "no guild line by default")
    ns.Set("announce", true)
    W.items[11000] = 1
    ns.Scan()
    eq(W.chat[1].channel, "GUILD"); eq(W.chat[1].msg, "I can now enter Blackrock Depths!")
    GulliToolkit = nil
end)

test("a step taken says where it is in the chain", function()
    local W = Fake({})
    local ns = Load()
    ns.Scan()
    ns.OnAccepted(4184)
    assert(W.printed[#W.printed]:find("Step 3 of 16: Onyxia's Lair", 1, true), W.printed[#W.printed])
end)

test("export and the hub: one text for every character, a summary line, reset", function()
    local reg
    Fake({ done = { [4182] = true, [4183] = true } })
    GulliToolkit = { Register = function(t) reg = t end }
    local ns = Load()
    ns.Scan()
    eq(ns.Export(), "GAT1;Tester-Realm:PRIEST:60:ONY=2/16,UBRS=0/2,BRD=0/2,SCHOLO=0/8,DALARAN=0/2,MARA=0/2")
    eq(reg.summary(), "Onyxia's Lair: 2 of 16")
    eq(#reg.options, 4)
    reg.options[3].set(true)
    eq(ns.Get("announce"), true)
    reg.reset()
    eq(ns.Get("announce"), false)
    local p = ns.ParseShort("ONY=2/16,UBRS=R")
    eq(p.ONY.total, 16); eq(p.UBRS.ready, true)
    GulliToolkit = nil
end)

test("the window: every tab", function()
    Fake({ party = { "Bob" }, db = { chars = { ["Alt-Realm"] = { name = "Alt", level = 60, faction = "Alliance",
                                                                 done = { [4742] = true }, active = {} } } } })
    local ns = Load()
    ns.Scan()
    ns.Toggle()
    for i = 1, 4 do ns.ShowTab(i) end
    ns.Set("hideEmpty", true); ns.Set("onlyAvail", true)
    ns.ShowTab(1); ns.ShowTab(2)
end)

test("every language has every key, with the same placeholders", function()
    Fake({})
    W.CheckLocales(Load())
end)

test("a secret unit on the world cursor tooltip is skipped, a plain one gets its lines", function()
    Fake({ party = { "Bob" } })
    local ns = Load()
    ns.Receive("GulliAT", "S\tONY=9/16", "PARTY", "Bob-Realm")
    local SECRET = {}
    issecretvalue = function(v) return v == SECRET end
    local called = 0
    UnitIsPlayer = function(u) called = called + 1; if u == SECRET then error("secret unit") end return true end
    local added = {}
    local function tip(unit) return { GetUnit = function() return nil, unit end,
        AddLine = function(_, l) added[#added + 1] = l end } end
    ns.UnitTooltip(tip(SECRET))
    eq(called, 0, "a secret unit never reaches UnitIsPlayer"); eq(#added, 0)
    UnitName = function() return SECRET end
    ns.UnitTooltip(tip("mouseover"))
    eq(#added, 0, "a secret name is skipped")
    UnitName = function() return "Bob" end
    ns.UnitTooltip(tip("mouseover"))
    eq(added[1], "Onyxia's Lair: 9 of 16 steps")
    issecretvalue = nil
end)

W.finish()
