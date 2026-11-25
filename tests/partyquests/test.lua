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

test("zones travel with the list; an old module's list still reads", function()
    Fake({ quests = LOG, party = PARTY, titles = { [64] = "The Forgotten Heirloom", [70] = "Wolves" } })
    local ns = Load()
    local parts = ns.Encode(ns.MyQuests())
    eq(parts[3], "ZWestfall|155:18,153:15,999:16")
    local long = {}
    for i = 1, 60 do long[i] = { id = 10000 + i, level = 60, zone = "Eastern Plaguelands" } end
    for _, p in ipairs(ns.Encode(long)) do
        assert(#p <= 240, "a part is too long")
        assert(p:sub(1, 1) ~= "Z" or p:find("^ZEastern Plaguelands|%d"), "each zone part names its zone")
    end
    eq(#ns.Encode({ { id = 1, zone = ("x"):rep(61) }, { id = 2, zone = "a|b" } }), 3, "a zone that cannot travel is left out")
    for _, p in ipairs({ "B", "Q64,70,71", "ZDuskwood|64:25", "ZWestfall|70:12", "Z" .. ("x"):rep(61) .. "|71:1", "E" }) do
        ns.Receive(p, "Ann")
    end
    for _, p in ipairs({ "B", "Q64,72", "E" }) do ns.Receive(p, "Bob") end
    local theirs = ns.Theirs()
    eq(theirs[1].id, 64); eq(theirs[1].zone, "Duskwood"); eq(theirs[1].level, 25)
    local list = ns.ByZone(theirs, function(item) return item.zone end)
    eq(list[1].head, true); eq(list[1].zone, "Westfall"); eq(list[1].here, true, "the player's zone first")
    eq(list[2].id, 70)
    eq(list[3].zone, "Duskwood"); eq(list[3].count, 1); eq(list[3].here, false)
    eq(list[5].head, true); eq(list[5].zone, nil, "quests without a zone come last")
    eq(list[5].count, 2)
end)

test("my quests are cut into zones: the player's zone first, then the quest log order", function()
    local log = { { title = "Tanaris", isHeader = true }, { title = "Thistleshrub Valley", questID = 1, level = 50 },
                  { title = "Elwynn Forest", isHeader = true }, { title = "Wolves", questID = 33, level = 5 },
                  LOG[1], LOG[2], LOG[3] }
    Fake({ quests = log, party = PARTY })
    local ns = Load()
    local list = ns.ByZone(ns.Ours(), function(r) return r.quest.zone end, function(r) return r.order end)
    local seen = {}
    for _, item in ipairs(list) do seen[#seen + 1] = item.head and (item.zone .. ":" .. item.count) or item.quest.id end
    eq(table.concat(seen, " "), "Westfall:2 155 153 Tanaris:1 1 Elwynn Forest:1 33")
    list = ns.ByZone(ns.Ours({ zone = "Westfall" }), function(r) return r.quest.zone end)
    eq(#list, 3); eq(list[1].here, true)
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
    local names = 0
    local real = UnitName
    UnitName = function(u)
        if u == "mouseover" or u == "nameplate1" or u == SECRET then
            names = names + 1; return u == "mouseover" and "Red Leather Bandana" or SECRET
        end
        return real(u)
    end
    eq(#ns.UnitTip(SECRET), 0)
    eq(names, 0, "a secret unit never reaches UnitName")
    eq(#ns.UnitTip("nameplate1"), 0, "a secret name gives no lines")
    issecretvalue = nil
    local lines = ns.UnitTip("mouseover")
    eq(#lines, 1, "a plain name gets the group's progress")
    eq(lines[1].group, "quest"); eq(lines[1].left, "Bob"); eq(lines[1].right, "4/15")
    eq(lines[1].rcolor, ns.Skin.TEXT, "not done yet")
    for _, p in ipairs({ "B", "Q153", "O153:15/15", "E" }) do ns.Receive(p, "Bob") end
    lines = ns.UnitTip("mouseover")
    eq(lines[1].rcolor, ns.Skin.GOOD, "done is green")
    assert(lines[1].right:find("ReadyCheck", 1, true), "and has a check mark, not colour alone")
    issecretvalue = nil
end)

test("without a group the note goes to the footer, never over my quests", function()
    Fake({ quests = LOG })
    local ns = Load()
    local S, made = ns.Skin, {}
    local empty, footer = S.Empty, S.Footer
    S.Empty = function(...) local e = empty(...); made.empty = e; return e end
    S.Footer = function(...) local f = footer(...); made.footer = f; return f end
    SlashCmdList.GULLIPARTYQUESTS("")
    ns.Refresh()
    eq(made.empty:IsShown(), false, "the list has quests: no empty state over it")
    eq(made.footer.status:GetText(), ns.L.NO_GROUP)
end)

test("an escort in a group: who it waits for, the ask and the answers", function()
    Fake({ quests = LOG, party = {
        { name = "Ann", quests = { [155] = true } },
        { name = "Bob", quests = {} },
        { name = "Cid", quests = {} },
    } })
    local ns = Load()
    eq(ns.EVENT_QUESTS[155], true)
    eq(ns.EVENT_QUESTS[94927], true, "Dunston Checks Out: help ... break out is an escort")
    W.party[1].quests[155] = nil
    W.party[2].quests = {}
    -- Ann runs the module, Bob and Cid do not (yet)
    for _, m in ipairs({ "B", "Q153", "E" }) do ns.Receive(m, "Ann-Realm") end
    GetQuestID = function() return 155 end
    GetTitleText = function() return "The Defias Brotherhood" end
    W.Fire("QUEST_DETAIL")
    assert(ns.escort and ns.escort.id == 155, "the card shows")
    local st = ns.EscortState(155)
    eq(#st.lack, 3); eq(st.noAddon, 2); eq(st.allReady, false)
    ns.AskEscort()
    eq(W.sent[#W.sent][2], "X155:The Defias Brotherhood")
    eq(W.chat[#W.chat][2], "PARTY", "members without the module get a chat line")
    ns.Receive("Y155:1", "Ann-Realm")
    ns.Receive("Y155:0", "Bob-Realm")
    W.party[3].quests[155] = true
    st = ns.EscortState(155)
    eq(table.concat(st.ready, ","), "Ann,Cid"); eq(table.concat(st.wait, ","), "Bob"); eq(#st.lack, 0)
    assert(ns.EscortText(st):find("Bob"), "the card names who is not ready")
    ns.Receive("Y155:1", "Bob-Realm")
    eq(ns.EscortState(155).allReady, true)
    eq(ns.EscortText(ns.EscortState(155)), ns.L.ESC_ALL_READY)
    W.Fire("QUEST_ACCEPTED", 155)
    eq(ns.escort, nil, "taking the quest closes the card")
end)

test("an escort: no card when everyone has it, off with its switch, solo nothing", function()
    Fake({ quests = LOG, party = PARTY })
    local ns = Load()
    GetQuestID = function() return 155 end
    W.Fire("QUEST_DETAIL")
    eq(ns.escort, nil, "Ann and Bob have it already")
    W.party[2].quests = {}
    ns.Set("escort", false)
    W.Fire("QUEST_DETAIL")
    eq(ns.escort, nil, "switched off")
    ns.Set("escort", true)
    GetQuestID = function() return 153 end
    W.Fire("QUEST_DETAIL")
    eq(ns.escort, nil, "not an event quest")
    Fake({ quests = LOG })
    ns = Load()
    GetQuestID = function() return 155 end
    W.Fire("QUEST_DETAIL")
    eq(ns.escort, nil, "alone")
end)

test("a member asks: ready at once with the quest in my log, else a card", function()
    Fake({ quests = LOG, party = PARTY })
    local ns = Load()
    ns.Receive("X155:The Defias Brotherhood", "Ann-Realm")
    eq(W.sent[#W.sent][2], "Y155:1", "I have it")
    eq(ns.Receive("X1234:Some Escort", "Ann-Realm"), nil)
    eq(ns.escortAsk.id, 1234); eq(ns.escortAsk.title, "Some Escort"); eq(ns.escortAsk.from, "Ann")
    ns.AnswerEscort(1234, false)
    eq(W.sent[#W.sent][2], "Y1234:0")
end)

test("the hub's Tweaks page gets rows on the window's own saved keys", function()
    Fake({})
    local reg
    GulliToolkit = { Register = function(t) reg = t end }
    local ns = Load()
    GulliToolkit = nil
    local GROUPS = { level = true, quests = true, combat = true, loot = true, people = true, ui = true, requests = true }
    assert(#reg.tweaks >= 2)
    local seen = {}
    for _, o in ipairs(reg.tweaks) do
        assert(GROUPS[o.group], "a group of the page for " .. o.key)
        assert(type(o.label) == "string" and type(o.desc) == "string" and o.icon, "texts and icon for " .. o.key)
        assert(not seen[o.key], "one row per key"); seen[o.key] = true
        o.set(true); eq(GulliPartyQuestsDB[o.key], true, o.key .. " on"); eq(o.get(), true)
        o.set(false); eq(GulliPartyQuestsDB[o.key], false, o.key .. " off"); eq(o.get(), false)
    end
    assert(seen.autoShare and seen.track)
end)

W.finish()
