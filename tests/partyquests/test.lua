-- Run from the repository root: lua5.1 tests/partyquests/test.lua
local W = dofile("tests/partyquests/wow.lua")
local test, eq = W.test, W.eq

local LOG = {
    { title = "Westfall", isHeader = true },
    { title = "The Defias Brotherhood", questID = 155, level = 18 },
    { title = "Red Leather Bandanas", questID = 153, level = 15 },
    { title = "Hidden", questID = 7, level = 1, isHidden = true },
    { title = "Not shareable", questID = 999, level = 16 },
}
local PARTY = {
    { name = "Ann", quests = { [155] = true } },
    { name = "Bob", quests = { [155] = true, [153] = true } },
}

test("my quests keep their zone; hidden quests are left out", function()
    Fake({ quests = LOG })
    local ns = Load()
    local q = ns.MyQuests()
    eq(#q, 3)
    eq(q[1].zone, "Westfall")
    eq(q[3].pushable, false)
end)

test("rows: who has each quest, the shared ones first, share only when someone lacks it", function()
    Fake({ quests = LOG, party = PARTY })
    local ns = Load()
    local rows, party = ns.Ours()
    eq(#party, 2)
    eq(rows[1].quest.id, 155, "everyone has it")
    eq(rows[1].have, 3)
    eq(rows[1].canShare, false)
    eq(rows[2].quest.id, 153)
    eq(rows[2].cells[1].state, "no"); eq(rows[2].cells[2].state, "has")
    eq(rows[2].canShare, true)
    eq(rows[3].canShare, false, "a quest the game does not let you share")
    ns.Share(153)
    eq(W.pushed[1], 153)
end)

test("the quest list goes to the group in parts and comes back the same", function()
    Fake({ quests = LOG, party = PARTY, complete = { [153] = true } })
    local ns = Load()
    local parts = ns.Encode(ns.MyQuests())
    eq(parts[1], "B"); eq(parts[#parts], "E")
    eq(parts[2], "Q155,153*,999")
    local many = {}
    for i = 1, 100 do many[i] = { id = 10000 + i } end
    for _, p in ipairs(ns.Encode(many)) do assert(#p <= 240, "a part is too long") end
    for _, p in ipairs(parts) do ns.Receive(p, "Ann-Realm") end
    assert(ns.remote.Ann.ids[155] and ns.remote.Ann.done[153])
end)

test("their quests: what members have and I do not, and done objectives show", function()
    Fake({ quests = LOG, party = PARTY, titles = { [64] = "The Forgotten Heirloom" } })
    local ns = Load()
    for _, p in ipairs({ "B", "Q155*,64,65", "E" }) do ns.Receive(p, "Bob") end
    for _, p in ipairs({ "B", "Q64", "E" }) do ns.Receive(p, "Ann") end
    local theirs = ns.Theirs()
    eq(#theirs, 2)
    eq(theirs[1].id, 64); eq(#theirs[1].who, 2)
    eq(theirs[1].title, "The Forgotten Heirloom")
    eq(theirs[2].title, "Quest 65")
    eq(W.loaded[1] ~= nil, true, "an unknown quest is asked from the server")
    local rows = ns.Ours()
    eq(rows[1].cells[2].state, "done", "Bob finished the objectives of 155")
    ns.Ask("The Forgotten Heirloom")
    eq(W.chat[1][2], "PARTY")
    assert(W.chat[1][1]:find("Forgotten Heirloom", 1, true))
end)

test("a member who left is forgotten; my own messages are ignored", function()
    Fake({ quests = LOG, party = PARTY })
    local ns = Load()
    for _, p in ipairs({ "B", "Q1", "E" }) do ns.Receive(p, "Ann") end
    for _, p in ipairs({ "B", "Q1", "E" }) do ns.Receive(p, "Tester-Realm") end
    eq(ns.remote.Tester, nil)
    W.party = { PARTY[2] }
    W.Fire("GROUP_ROSTER_UPDATE")
    eq(ns.remote.Ann, nil)
end)

test("quest updates send one list after a pause; nothing is sent alone", function()
    Fake({ quests = LOG, party = PARTY })
    Load()
    W.Fire("QUEST_LOG_UPDATE")
    W.Fire("QUEST_LOG_UPDATE")
    eq(#W.timers, 1, "one broadcast for many updates")
    W.RunTimers()
    eq(W.sent[1][2], "B"); eq(W.sent[1][3], "PARTY")
    Fake({ quests = LOG })
    local ns = Load()
    ns.Broadcast()
    eq(#W.sent, 0, "no group, nothing sent")
end)


test("objectives go out as a new message type and come back as progress", function()
    Fake({ quests = LOG, party = PARTY, objectives = {
        [155] = { { text = "Defias Pillager slain: 3/8", type = "monster", numFulfilled = 3, numRequired = 8 } },
        [153] = { { text = "Red Leather Bandana: 15/15", type = "item", numFulfilled = 15, numRequired = 15, finished = true } },
    } })
    local ns = Load()
    local parts = ns.Encode(ns.MyQuests())
    eq(parts[2], "Q155,153,999", "old message types stay as they were")
    eq(parts[3], "O155:3/8,153:15/15")
    for _, p in ipairs({ "B", "Q155", "O155:5/8", "E" }) do ns.Receive(p, "Bob") end
    local rows = ns.Ours()
    eq(rows[1].cells[2].have, 5); eq(rows[1].cells[2].need, 8)
    eq(rows[1].mine.have, 3)
    eq(ns.remote.Bob.obj[155][1][1], 5)
end)

test("member status: module, old data, no module, offline; offline cells are unknown", function()
    local party = { { name = "Ann", quests = { [155] = true } }, { name = "Bob", quests = {}, offline = true } }
    Fake({ quests = LOG, party = party })
    local ns = Load()
    local m = ns.Members()
    eq(ns.Status(m[1]), "none"); eq(ns.Status(m[2]), "offline")
    for _, p in ipairs({ "B", "Q155", "E" }) do ns.Receive(p, "Ann") end
    eq(ns.Status(m[1]), "fresh")
    W.now = W.now + 400
    eq(ns.Status(m[1]), "stale")
    local rows = ns.Ours()
    eq(rows[1].cells[2].state, "unknown")
    eq(m[1].leader, true)
end)

test("the summary says what to share and when the group is in sync", function()
    Fake({ quests = { LOG[1], LOG[2], LOG[3] }, party = { { name = "Ann", quests = { [155] = true } } } })
    local ns = Load()
    local text, synced = ns.Summary(ns.Ours())
    eq(synced, false); assert(text:find("1"))
    Fake({ quests = { LOG[1], LOG[2] }, party = { { name = "Ann", quests = { [155] = true } } }, complete = { [155] = true } })
    ns = Load()
    for _, p in ipairs({ "B", "Q155*", "E" }) do ns.Receive(p, "Ann") end
    text, synced = ns.Summary(ns.Ours())
    eq(synced, true)
    eq(text, ns.L.SYNC_READY:format(1))
end)

test("a member who turned in a quest is not offered it; the game's share reply teaches that too", function()
    Fake({ quests = LOG, party = PARTY, turned = { [64] = true } })
    local ns = Load()
    for _, p in ipairs({ "B", "Q64", "C153", "E" }) do ns.Receive(p, "Ann") end
    local rows = ns.Ours()
    local r153
    for _, r in ipairs(rows) do if r.quest.id == 153 then r153 = r end end
    eq(r153.cells[1].state, "turned")
    eq(r153.canShare, false, "Bob has it, Ann did it before")
    eq(ns.TurnedForOthers()[1], 64, "I tell Ann I did 64 before")
    local parts = ns.Encode(ns.MyQuests(), ns.TurnedForOthers())
    eq(parts[#parts - 1], "C64")
    ns.Share(155)
    local who, what = ns.ShareReply("Bob has completed that quest.")
    eq(who, "Bob"); eq(what, "turned")
    eq(ns.turnedByShare.Bob[155], true)
end)

test("Share all shares each missing quest one second apart; auto share waits for its switch", function()
    Fake({ quests = LOG, party = { { name = "Ann", quests = {} } } })
    local ns = Load()
    eq(ns.ShareAll(), 2)
    eq(#W.pushed, 1)
    W.RunTimers()
    eq(#W.pushed, 2)
    W.Fire("GROUP_ROSTER_UPDATE"); W.RunTimers(); W.pushed = {}
    W.party[2] = { name = "Cid", quests = {} }
    W.Fire("GROUP_ROSTER_UPDATE"); W.RunTimers()
    eq(#W.pushed, 0, "auto share is off by default")
    ns.Set("autoShare", true)
    W.party[3] = { name = "Dan", quests = {} }
    W.Fire("GROUP_ROSTER_UPDATE"); W.RunTimers(); W.RunTimers()
    assert(#W.pushed > 0, "a new member gets my quests")
end)

test("a request goes to the owner through the module, else as a whisper; the owner sees it", function()
    Fake({ quests = LOG, party = PARTY })
    local ns = Load()
    eq(ns.Request(64, "Heirloom", "Ann"), "whisper")
    eq(W.chat[1][2], "WHISPER"); eq(W.chat[1][3], "Ann")
    for _, p in ipairs({ "B", "Q64", "E" }) do ns.Receive(p, "Ann") end
    eq(ns.Request(64, "Heirloom", "Ann"), "addon")
    eq(W.sent[#W.sent][2], "R64:Ann")
    ns.Receive("R155:Tester", "Bob-Realm")
    eq(ns.requests[1].from, "Bob"); eq(ns.requests[1].id, 155)
    ns.Receive("R153:Someone", "Bob")
    eq(#ns.requests, 1, "a request for someone else is ignored")
end)

test("group events become messages, each behind its switch; the whole group finishing too", function()
    GulliPartyQuestsDB = nil
    Fake({ quests = { LOG[1], LOG[2] }, party = { { name = "Ann", quests = { [155] = true } } }, complete = { [155] = true } })
    local ns = Load()
    for _, p in ipairs({ "B", "Q155", "O155:7/8", "E" }) do ns.Receive(p, "Ann") end
    eq(#W.printed, 0, "the first list is not news")
    for _, p in ipairs({ "B", "Q155*,64", "O155:8/8", "E" }) do ns.Receive(p, "Ann") end
    local all = table.concat(W.printed, "\n")
    assert(all:find("Ann took"), "accept"); assert(all:find("Ann finished"), "complete")
    assert(all:find("whole group finished"), "all done")
    W.printed = {}
    for _, p in ipairs({ "B", "Q64", "E" }) do ns.Receive(p, "Ann") end
    assert(table.concat(W.printed):find("handed in"), "turn in")
    ns.Set("nAccept", false)
    W.printed = {}
    for _, p in ipairs({ "B", "Q64,70", "E" }) do ns.Receive(p, "Ann") end
    eq(#W.printed, 0, "switched off")
    local d = ns.Diff({ ids = { [1] = true }, done = {}, obj = { [1] = { { 2, 3 } } }, turned = {} },
                      { ids = { [1] = true }, done = {}, obj = { [1] = { { 3, 3 } } }, turned = {} })
    eq(d[1][1], "objective")
end)

test("the zone filter and the search narrow my quests", function()
    local log = { LOG[1], LOG[2], { title = "Elwynn Forest", isHeader = true }, { title = "Wolves", questID = 33, level = 5 } }
    Fake({ quests = log, party = PARTY })
    local ns = Load()
    eq(#ns.Ours({ zone = "Westfall" }), 1)
    eq(#ns.Ours({}), 2)
    eq(#ns.Ours({ text = "wol" }), 1)
end)

test("spare quest items, track for all and the tooltip lines", function()
    Fake({ quests = LOG, party = PARTY, items = { [10] = "Red Leather Bandana" }, bags = { { id = 10, count = 17 } },
           objectives = { [153] = { { text = "Red Leather Bandana: 15/15", type = "item", numFulfilled = 15, numRequired = 15 } } } })
    local ns = Load()
    for _, q in ipairs(ns.MyQuests(true)) do if q.id == 153 then eq(q.spare, 2) end end
    for _, p in ipairs({ "B", "Q153", "O153:4/15", "E" }) do ns.Receive(p, "Bob") end
    local lines = ns.TooltipLines("Red Leather Bandana")
    eq(#lines, 1); eq(lines[1][1], "Bob"); eq(lines[1][2], "4/15")
    eq(#ns.TooltipLines("Red Leather"), 0, "a name must match the whole objective")
    ns.TrackForAll(153)
    eq(W.watched[1], 153); eq(W.sent[#W.sent][2], "T153")
    ns.Receive("T153", "Bob")
    eq(W.watched[2], 153)
    ns.Set("track", false)
    ns.Receive("T153", "Bob")
    eq(#W.watched, 2, "track requests follow their switch")
    ns.Set("tooltip", false)
    eq(#ns.TooltipLines("Red Leather Bandana"), 0)
end)

test("the window draws every tab and the request card", function()
    Fake({ quests = LOG, party = PARTY })
    local ns = Load()
    SlashCmdList.GULLIPARTYQUESTS("")
    for i = 1, 3 do ns.Refresh() end
    ns.OnRequest("Bob", 155)
    assert(ns.ShowRequest())
end)

test("the window opens and draws both tabs", function()
    Fake({ quests = LOG, party = PARTY })
    local ns = Load()
    SlashCmdList.GULLIPARTYQUESTS("")
    ns.Refresh()
end)

test("every language has every key, with the same placeholders", function()
    Fake({})
    W.CheckLocales(Load())
end)

test("a secret unit or name on the world cursor tooltip is skipped", function()
    Fake({ quests = LOG, party = PARTY,
           objectives = { [153] = { { text = "Red Leather Bandana: 15/15", type = "item", numFulfilled = 15, numRequired = 15 } } } })
    local ns = Load()
    for _, p in ipairs({ "B", "Q153", "O153:4/15", "E" }) do ns.Receive(p, "Bob") end
    local SECRET = setmetatable({}, { __eq = function() error("compared a secret") end,
                                      __lt = function() error("compared a secret") end })
    issecretvalue = function(v) return rawequal(v, SECRET) end
    eq(#ns.TooltipLines(SECRET), 0, "a secret name is never compared")
    local shown = 0
    local function tip(unit) return { GetUnit = function() return nil, unit end,
        AddDoubleLine = function() shown = shown + 1 end, Show = function() end } end
    local names = 0
    local real = UnitName
    UnitName = function(u)
        if u == "mouseover" or u == "nameplate1" or u == SECRET then
            names = names + 1; return u == "mouseover" and "Red Leather Bandana" or SECRET
        end
        return real(u)
    end
    ns.UnitTooltip(tip(SECRET))
    eq(names, 0, "a secret unit never reaches UnitName"); eq(shown, 0)
    ns.UnitTooltip(tip("nameplate1"))
    eq(shown, 0, "a secret name is skipped")
    ns.UnitTooltip(tip("mouseover"))
    eq(shown, 1)
    issecretvalue = nil
end)

W.finish()
