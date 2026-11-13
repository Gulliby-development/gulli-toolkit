-- Run from the repository root: lua5.1 tests/quickchat/test.lua
local W = dofile("tests/quickchat/wow.lua")
local test, eq = W.test, W.eq

test("default phrases follow the client language; own phrases replace them", function()
    Fake({ locale = "ruRU" })
    local ns = Load()
    eq(ns.Phrases()[2], "Готов!")
    assert(ns.AddPhrase("  Сундук мой  "))
    eq(#ns.Phrases(), 11)
    eq(ns.Phrases()[11], "Сундук мой")
    ns.RemovePhrase(1)
    eq(ns.Phrases()[1], "Готов!")
    eq(ns.AddPhrase("   "), false)
    ns.ResetPhrases()
    eq(#ns.Phrases(), 10)
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

test("phrases have categories; a phrase can keep its own channel", function()
    Fake({})
    local ns = Load()
    eq(ns.Category("inv please"), "GROUP")
    eq(#ns.PhrasesIn("TRADE"), 2)
    ns.AddPhrase("Mine", "SOCIAL")
    eq(ns.Category("Mine"), "SOCIAL")
    ns.AddPhrase("Other")
    eq(ns.Category("Other"), "OWN")
    eq(ns.CycleChannel("Mine"), "AUTO")
    eq(ns.CycleChannel("Mine"), "SAY")
    ns.Say("Mine")
    eq(W.chat[1][2], "SAY", "the phrase's own channel wins")
    ns.db.chan["Mine"] = "LEADER"
    eq(ns.CycleChannel("Mine"), nil, "after the last channel it follows the window again")
    ns.ResetPhrases()
    eq(next(ns.db.chan), nil); eq(ns.Category("Mine"), "OWN")
end)

test("favourites fill the wheel and the panel, else the first phrases", function()
    Fake({})
    local ns = Load()
    eq(#ns.Favorites(8), 8)
    eq(ns.Favorites(8)[1], "inv please")
    ns.ToggleFav("brb"); ns.ToggleFav("Ready!")
    local f = ns.Favorites(8)
    eq(#f, 2); eq(f[1], "Ready!"); eq(f[2], "brb")
    ns.ToggleFav("brb")
    eq(#ns.Favorites(8), 1)
end)

test("the wheel opens on its key and sends a favourite", function()
    Fake({})
    local ns = Load()
    ns.SetKey("F5")
    eq(W.bindings["F5"], "GulliQuickChatWheelButton")
    ns.SetKey("ESCAPE")
    eq(ns.db.wheelKey, nil); eq(next(W.bindings), nil)
    W.combat = true
    ns.db.wheelKey = "F6"
    eq(ns.ApplyKey(), false, "bindings wait for the end of the fight")
    W.combat = false
    W.Fire("PLAYER_REGEN_ENABLED")
    eq(W.bindings["F6"], "GulliQuickChatWheelButton")
    ns.ToggleFav("Ready!")
    eq(ns.ToggleWheel(), true)
    SlashCmdList.GULLIQUICKCHAT("wheel")
    eq(ns.ToggleWheel(), true, "the slash command closed it, this opens it again")
    ns.ToggleFav("brb")
    ns.ToggleWheel(); ns.ToggleWheel()
    ns.WheelHover(2)
    eq(ns.ToggleWheel(), false, "the wheel key on a lit slot sends it")
    eq(W.chat[#W.chat][1], "brb")
    ns.ToggleWheel()
    W.now = W.now + 5
    ns.WheelSend(1)
    eq(W.chat[#W.chat][1], "Ready!")
    eq(ns.WheelSend(5), false, "only two favourites")
end)

test("secret health and mana in combat leave {hp} and {mana} empty, without an error", function()
    Fake({ target = "Hogger" })
    local ns = Load()
    local SECRET = {}
    issecretvalue = function(v) return v == SECRET end
    W.hp, W.mana = SECRET, SECRET
    eq(ns.Fill("hp {hp} mana {mana} ok"), "hp mana ok")
end)

test("more tokens: target class and level, health, mana, leader, item, quest", function()
    Fake({ target = "Hogger" })
    local ns = Load()
    eq(ns.Fill("{targetclass} {targetlevel} {hp} {mana}"), "Priest 60 50% 50%")
    eq(ns.Fill("{leader}"), "", "no group, no leader")
    W.group, W.leader = true, "Ann"
    eq(ns.Fill("{leader} lead"), "Ann lead")
    W.hooks.ChatEdit_InsertLink("|cffffffff|Hitem:2589::|h[Linen Cloth]|h|r")
    eq(ns.Fill("WTS {item}"), "WTS |cffffffff|Hitem:2589::|h[Linen Cloth]|h|r")
    ns.pickedQuest = "The Defias Brotherhood"
    eq(ns.Fill("on {quest}"), "on The Defias Brotherhood")
end)

test("Leader whispers the group leader; nothing without one", function()
    Fake({})
    local ns = Load()
    eq(ns.Say("hi", "LEADER"), false)
    W.group, W.leader = true, "Ann"
    ns.Say("hi", "LEADER")
    eq(W.chat[1][2], "WHISPER"); eq(W.chat[1][3], "Ann")
end)

test("a double tap sends once; the history repeats a message", function()
    Fake({})
    local ns = Load()
    eq(ns.Say("hi"), true)
    eq(ns.Say("hi"), false, "the same text within 3 seconds")
    eq(#W.chat, 1)
    W.now = W.now + 4
    eq(ns.Say("hi"), true)
    eq(#ns.db.history, 2)
    W.now = W.now + 4
    ns.Repeat(ns.db.history[1])
    eq(#W.chat, 3); eq(W.chat[3][1], "hi")
    for i = 1, 30 do ns.Say("m" .. i) end
    eq(#ns.db.history, ns.HISTORY_MAX)
end)

test("group messages for a Forever dungeon and looking for a group", function()
    Fake({ areas = { [2017] = "Stratholme" } })
    local ns = Load()
    eq(ns.LFM("STRAT", 3, { HEALER = true }), "LFM 3 for Stratholme, need healer")
    eq(ns.DungeonName("HYJAL"), "Hyjal Summit", "an area new in Forever has our own name")
    W.level = 58
    eq(ns.LFG("STRAT", "HEALER"), "LFG Stratholme, healer, level 58")
    for _, d in ipairs(ns.DUNGEONS) do
        assert(d[1] ~= "MC" and d[1] ~= "BWL" and d[1] ~= "NAXX" and d[1] ~= "AQ40", d[1] .. " is not in Forever")
    end
    local list = ns.DungeonsFor(20)
    eq(list[1], "WC"); eq(list[2], "DM"); eq(list[3], "RFC")
    eq(#list, #ns.DUNGEONS)
end)

test("a posted group message reminds once after two minutes, unless posted again", function()
    Fake({})
    local ns = Load()
    ns.PostLFM("LFM 1 for Stratholme")
    W.now = W.now + 10
    ns.PostLFM("LFM 2 for Stratholme")
    W.RunTimers()
    eq(#W.printed, 1, "only the newer post reminds")
    ns.db.remind = false
    W.now = W.now + 10
    ns.PostLFM("LFM 3")
    W.RunTimers()
    eq(#W.printed, 1)
end)

test("Bulletin's My LFM opens the group page on that dungeon", function()
    Fake({})
    local ns = Load()
    GulliQuickChat.OpenLFM("STRAT")
    assert(ns.Window():IsShown())
end)

test("busy auto-reply goes once per player every few minutes, only when on", function()
    Fake({})
    local ns = Load()
    W.combat = true
    W.Fire("CHAT_MSG_WHISPER", "hi", "Ann")
    eq(#W.chat, 0, "off by default")
    ns.db.autoBusy = true
    W.Fire("CHAT_MSG_WHISPER", "hi", "Ann")
    W.Fire("CHAT_MSG_WHISPER", "hi?", "Ann")
    eq(#W.chat, 1)
    W.now = W.now + ns.db.busyMinutes * 60
    W.Fire("CHAT_MSG_WHISPER", "hi??", "Ann")
    eq(#W.chat, 2)
end)

test("the whisper history keeps both sides by player; replies with a phrase", function()
    Fake({})
    local ns = Load()
    W.Fire("CHAT_MSG_WHISPER", "hello", "Ann-Realm")
    W.Fire("CHAT_MSG_WHISPER_INFORM", "hi Ann", "Ann-Realm")
    W.Fire("CHAT_MSG_WHISPER", "yo", "Bob")
    eq(#ns.Log(), 3)
    local ann = ns.Log("Ann-Realm")
    eq(#ann, 2); eq(ann[1].out, true); eq(ann[2].out, false)
    ns.ReplyWith({ from = "Bob" }, "Ready!")
    eq(W.chat[1][3], "Bob"); eq(W.chat[1][1], "Ready!")
    ns.db.keepLog = false
    W.Fire("CHAT_MSG_WHISPER", "more", "Bob")
    eq(#ns.Log(), 3, "history off")
end)

test("emotes and raid marks", function()
    Fake({})
    local ns = Load()
    ns.Emote("WAVE")
    eq(W.emotes[1], "WAVE")
    ns.Mark(8)
    eq(#W.marks, 0, "no target")
    W.target = "Hogger"
    ns.Mark(8)
    eq(W.marks[1][2], 8)
end)

test("the hub gets a summary, the panel moves, defaults come back", function()
    local reg
    Fake({})
    GulliToolkit = { Register = function(t) reg = t end }
    local ns = Load()
    eq(reg.summary(), nil)
    W.combat = true
    W.Fire("CHAT_MSG_WHISPER", "inv?", "Ann")
    eq(reg.summary(), "Missed whispers: 1")
    eq(#reg.options, 3)
    reg.move(true)
    eq(ns.movingPanel, true)
    reg.move(false)
    ns.db.autoBusy, ns.db.busyMinutes, ns.db.channel = true, 20, "GUILD"
    reg.reset()
    eq(ns.db.autoBusy, false); eq(ns.db.busyMinutes, 5); eq(ns.db.channel, "AUTO")
    reg.options[1].set(true)
    eq(ns.db.panelShow, true)
end)

test("the window draws every page", function()
    Fake({})
    local ns = Load()
    SlashCmdList.GULLIQUICKCHAT("")
    ns.Refresh()
    for i = 1, 5 do ns.ShowPage(i) end
    ns.ShowPage(1, { editing = true })
    ns.ShowPage(2, { mode = 2 }); ns.ShowPage(2, { mode = 3 })
    ns.ShowPage(3, { view = 2 })
    ns.db.panelShow = true
    ns.Panel()
end)

test("every language has every key, with the same placeholders", function()
    Fake({})
    W.CheckLocales(Load())
end)

W.finish()
