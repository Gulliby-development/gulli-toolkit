-- Run from the repository root: lua5.1 tests/social/test.lua
local W = dofile("tests/social/wow.lua")
local test, eq = W.test, W.eq

test("every language has every text", function()
    Fake({})
    W.CheckLocales(Load())
end)

test("a whisper that is a key word gets an invite", function()
    Fake({})
    Load()
    W.Fire("CHAT_MSG_WHISPER", " INV ", "Bob-Realm")
    W.Fire("CHAT_MSG_WHISPER", "can you inv me later?", "Ann")
    eq(table.concat(W.did, ","), "invite:Bob-Realm")
end)

test("no invite when the group is full or someone else leads", function()
    Fake({ group = { 5, true } })
    Load()
    W.Fire("CHAT_MSG_WHISPER", "inv", "Bob")
    Fake({ group = { 2, false } })
    Load()
    W.Fire("CHAT_MSG_WHISPER", "inv", "Bob")
    eq(#W.did, 0)
    assert(W.printed[#W.printed]:find("cannot invite", 1, true))
end)

test("invites only friends and guild when asked to", function()
    Fake({ friends = { "Ann" }, guild = { "Gus-Realm" }, db = { inviteKnown = true } })
    Load()
    W.Fire("CHAT_MSG_WHISPER", "inv", "Bob")
    W.Fire("CHAT_MSG_WHISPER", "inv", "Ann")
    W.Fire("CHAT_MSG_WHISPER", "123", "Gus-Realm")
    eq(table.concat(W.did, ","), "invite:Ann,invite:Gus-Realm")
end)

test("invites from friends are accepted; strangers only turned away when switched on", function()
    Fake({ friends = { "Ann" } })
    local ns = Load()
    W.Fire("PARTY_INVITE_REQUEST", "Ann")
    W.Fire("PARTY_INVITE_REQUEST", "Bob")
    eq(table.concat(W.did, ","), "accept")
    ns.db.blockStrangers = true
    W.Fire("PARTY_INVITE_REQUEST", "Bob")
    eq(W.did[2], "decline")
end)

test("duels and guild invites are turned away only when switched on", function()
    Fake({})
    local ns = Load()
    W.Fire("DUEL_REQUESTED", "Bob"); W.Fire("GUILD_INVITE_REQUEST", "Bob", "Guild")
    eq(#W.did, 0)
    ns.db.noDuels, ns.db.noGuildInvites = true, true
    W.Fire("DUEL_REQUESTED", "Bob"); W.Fire("GUILD_INVITE_REQUEST", "Bob", "Guild")
    eq(table.concat(W.did, ","), "noduel,noguild")
end)

test("everything off does nothing; secret names are skipped", function()
    Fake({ friends = { "Ann" }, db = { invite = false, acceptKnown = false } })
    local ns = Load()
    W.Fire("CHAT_MSG_WHISPER", "inv", "Ann")
    W.Fire("PARTY_INVITE_REQUEST", "Ann")
    eq(#W.did, 0)
    ns.db.invite = true
    issecretvalue = function() return true end
    W.Fire("CHAT_MSG_WHISPER", "inv", "Ann")
    eq(#W.did, 0)
    ns.Toggle()
end)

test("Battle.net friends count as friends while the switch is on", function()
    Fake({ bnet = { "Bnetpal" } })
    local ns = Load()
    eq(ns.Known("Bnetpal-Other"), true)
    ns.db.bnet = false
    eq(ns.Known("Bnetpal"), false)
end)

test("a whisper back when no invite can go out", function()
    Fake({ group = { 5, true } })
    local ns = Load()
    W.Fire("CHAT_MSG_WHISPER", "inv", "Bob")
    eq(W.said[1], "WHISPER:Bob:Sorry, my group is full.")
    Fake({ group = { 2, false } })
    Load()
    W.Fire("CHAT_MSG_WHISPER", "inv", "Bob")
    eq(W.said[1], "WHISPER:Bob:Sorry, I am not the group leader.")
    Fake({ db = { inviteKnown = true } })
    ns = Load()
    W.Fire("CHAT_MSG_WHISPER", "inv", "Bob")
    eq(W.said[1], "WHISPER:Bob:Sorry, I only invite friends and guild.")
    ns.db.reply = false
    W.Fire("CHAT_MSG_WHISPER", "inv", "Bob")
    eq(#W.said, 1, "the switch stops it")
end)

test("a full party becomes a raid only with the switch", function()
    Fake({ group = { 5, true }, db = { toRaid = true } })
    local ns = Load()
    eq(ns.InviteState(), "raid")
    W.Fire("CHAT_MSG_WHISPER", "inv", "Bob")
    eq(table.concat(W.did, ","), "raid,invite:Bob")
end)

test("key words: the whole whisper or its start", function()
    Fake({})
    local ns = Load()
    eq(ns.IsAsk("inv please"), false)
    ns.db.match = "START"
    eq(ns.IsAsk("inv please"), true)
    eq(ns.IsAsk("invisible"), false, "a word, not a prefix")
    eq(ns.IsAsk("INV"), true)
end)

test("the Recent log, today's count and the hub feed", function()
    Fake({ friends = { "Ann" }, db = { blockStrangers = true, noDuels = true } })
    local notes = {}
    GulliToolkit = { Notify = function(_, t) notes[#notes + 1] = t end }
    local ns = Load()
    W.Fire("PARTY_INVITE_REQUEST", "Bob")
    W.Fire("DUEL_REQUESTED", "Cid")
    W.Fire("DUEL_REQUESTED", "Ann")
    W.Fire("CHAT_MSG_WHISPER", "inv", "Dan")
    eq(#ns.db.log, 3, "a duel from a friend still comes")
    eq(ns.db.log[1].what, "invited"); eq(ns.db.log[3].what, "invite"); eq(ns.db.log[3].who, "Bob")
    eq(ns.Today(), 2)
    eq(#notes, 2, "only what was turned away goes to the feed")
    for i = 1, 25 do ns.Log("invited", "P" .. i) end
    eq(#ns.db.log, ns.LOG_MAX)
    ns.ShowPage(2)
    ns.ShowPage(1)
end)

test("allow and deny lists win over everything", function()
    Fake({ friends = { "Ann" }, db = { inviteKnown = true } })
    local ns = Load()
    ns.AddTo("allow", "Bob-Realm")
    eq(ns.db.allow, "Bob")
    W.Fire("CHAT_MSG_WHISPER", "inv", "Bob")
    eq(W.did[1], "invite:Bob")
    ns.AddTo("deny", "Ann")
    W.Fire("PARTY_INVITE_REQUEST", "Ann")
    eq(W.did[2], "decline", "a friend on the deny list is declined")
    ns.AddTo("allow", "Ann")
    eq(ns.db.deny, "", "allowing takes the name off the deny list")
    eq(ns.db.allow, "Bob, Ann")
end)

test("summons and resurrections only with their switch and out of combat", function()
    Fake({})
    local ns = Load()
    W.Fire("CONFIRM_SUMMON"); W.Fire("RESURRECT_REQUEST", "Pri")
    eq(#W.did, 0)
    ns.db.summon, ns.db.res = true, true
    W.combat = true
    W.Fire("CONFIRM_SUMMON"); W.Fire("RESURRECT_REQUEST", "Pri")
    eq(#W.did, 0)
    W.combat = false
    W.Fire("CONFIRM_SUMMON"); W.Fire("RESURRECT_REQUEST", "Pri")
    eq(table.concat(W.did, ","), "summon,res")
end)

test("trades and charters from strangers close; from friends they stay", function()
    Fake({ friends = { "Ann" } })
    local ns = Load()
    W.trader, W.petition = "Bob", "Bob"
    W.Fire("TRADE_SHOW"); W.Fire("PETITION_SHOW")
    eq(#W.did, 0)
    ns.db.noTrade, ns.db.noPetition = true, true
    W.Fire("TRADE_SHOW"); W.Fire("PETITION_SHOW")
    eq(table.concat(W.did, ","), "notrade,nopetition")
    W.trader, W.petition = "Ann", "Ann"
    W.Fire("TRADE_SHOW"); W.Fire("PETITION_SHOW")
    eq(#W.did, 2)
end)

test("spam whispers from strangers are hidden only with the switch", function()
    Fake({ friends = { "Ann" } })
    local ns = Load()
    local filter = W.filters.CHAT_MSG_WHISPER
    eq(filter(nil, "CHAT_MSG_WHISPER", "Cheap gold at www.example.com", "Spammer"), false)
    ns.db.spam = true
    eq(filter(nil, "CHAT_MSG_WHISPER", "Cheap gold at www.example.com", "Spammer"), true)
    eq(filter(nil, "CHAT_MSG_WHISPER", "1000g = 5 usd", "Spammer2"), true)
    eq(filter(nil, "CHAT_MSG_WHISPER", "want some gold for the run?", "Ann"), false, "friends are never spam")
    eq(filter(nil, "CHAT_MSG_WHISPER", "hi, are you going to RFC?", "Bob"), false)
    eq(ns.db.log[1].what, "spam")
end)

test("the hub gets a summary and a reset", function()
    Fake({ db = { noDuels = true } })
    local got
    GulliToolkit = { Register = function(info) got = info end }
    local ns = Load()
    eq(got.summary(), nil, "nothing to say")
    W.Fire("DUEL_REQUESTED", "Cid")
    eq(got.summary(), "1 turned away today")
    got.reset()
    eq(ns.db.noDuels, false)
    assert(#got.options <= 6)
end)

W.finish()
