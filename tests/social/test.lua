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

W.finish()
