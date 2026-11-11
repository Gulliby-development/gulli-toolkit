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
    eq(rows[2].cells[1], "no"); eq(rows[2].cells[2], "has")
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
    local rows = ns.Ours()
    eq(rows[1].cells[2], "done", "Bob finished the objectives of 155")
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

W.finish()
