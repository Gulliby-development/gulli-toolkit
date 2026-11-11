-- Run from the repository root: lua5.1 tests/quickchat/test.lua
local W = dofile("tests/quickchat/wow.lua")
local test, eq = W.test, W.eq

test("default phrases follow the client language; own phrases replace them", function()
    Fake({ locale = "ruRU" })
    local ns = Load()
    eq(ns.Phrases()[2], "Готов!")
    assert(ns.AddPhrase("  Сундук мой  "))
    eq(#ns.Phrases(), 9)
    eq(ns.Phrases()[9], "Сундук мой")
    ns.RemovePhrase(1)
    eq(ns.Phrases()[1], "Готов!")
    eq(ns.AddPhrase("   "), false)
    ns.ResetPhrases()
    eq(#ns.Phrases(), 8)
end)

test("tokens become the target, zone, name and level", function()
    Fake({ target = "Hogger", level = 12 })
    local ns = Load()
    eq(ns.Fill("Pull {target} in {zone}, {me} {level}"), "Pull Hogger in Westfall, Tester 12")
    W.target = nil
    eq(ns.Fill("Kill {target} now"), "Kill now", "no target, no double space")
    eq(ns.Fill("{unknown} stays"), "{unknown} stays")
end)

test("Group sends to raid, party or say; a fixed channel is kept", function()
    Fake({})
    local ns = Load()
    ns.Say("hi")
    eq(W.chat[1][2], "SAY")
    W.group = true
    ns.Say("hi")
    eq(W.chat[2][2], "PARTY")
    W.raid = true
    ns.Say("hi")
    eq(W.chat[3][2], "RAID")
    ns.db.channel = "GUILD"
    ns.Say("hi")
    eq(W.chat[4][2], "GUILD")
end)

test("whisper goes to the target player, else to who whispered last", function()
    Fake({})
    local ns = Load()
    ns.db.channel = "WHISPER"
    eq(ns.Say("hello"), false, "nobody to whisper")
    W.Fire("CHAT_MSG_WHISPER", "yo", "Ann-Realm")
    ns.Say("hello")
    eq(W.chat[1][3], "Ann-Realm")
    W.target = "Bob"
    ns.Say("hello")
    eq(W.chat[2][3], "Bob")
end)

test("the group message is built from a quest, group quests first", function()
    Fake({ quests = {
        { title = "Westfall", isHeader = true },
        { title = "Westfall Stew", questID = 36, level = 10 },
        { title = "The Defias Brotherhood", questID = 155, level = 18, suggestedGroup = 5 },
    } })
    local ns = Load()
    local q = ns.Quests()
    eq(q[1].id, 155)
    eq(ns.LFM(q[1], 2, { TANK = true, HEALER = true }), "LFM 2 for The Defias Brotherhood, need tank, healer")
    eq(ns.LFM(nil, 1, {}), "LFM 1 for Westfall")
end)

test("the LookingForGroup channel is found by name in any language", function()
    Fake({ channels = { 1, "General - Elwynn", false, 4, "ПоискСпутников", false } })
    local ns = Load()
    eq(ns.LFGChannel(), 4)
    ns.PostLFM("LFM 1")
    eq(W.chat[1][2], "CHANNEL"); eq(W.chat[1][3], 4)
    Fake({})
    ns = Load()
    eq(ns.LFGChannel(), 1, "General when not in LookingForGroup")
end)

test("whispers are kept in fights and while away; reply and busy", function()
    Fake({})
    local ns = Load()
    W.Fire("CHAT_MSG_WHISPER", "hello", "Ann-Realm")
    eq(#ns.missed, 0, "not busy: the chat shows it")
    W.combat = true
    W.Fire("CHAT_MSG_WHISPER", "inv?", "Bob-Realm")
    W.combat = false
    W.afk = true
    W.Fire("CHAT_MSG_WHISPER", "there?", "Cid")
    eq(#ns.missed, 2)
    eq(ns.missed[1].short, "Cid")
    ns.Reply(ns.missed[2])
    eq(W.opened[1], "/w Bob-Realm ")
    ns.Busy(ns.missed[2])
    eq(W.chat[1][2], "WHISPER"); eq(W.chat[1][3], "Bob-Realm")
    issecretvalue = function(v) return v == "secret" end
    W.Fire("CHAT_MSG_WHISPER", "secret", "Dan")
    eq(#ns.missed, 2, "a secret message is skipped")
end)

test("the window draws every page", function()
    Fake({})
    local ns = Load()
    SlashCmdList.GULLIQUICKCHAT("")
    ns.Refresh()
end)

test("every language has every key, with the same placeholders", function()
    Fake({})
    W.CheckLocales(Load())
end)

W.finish()
