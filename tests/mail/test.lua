-- Run from the repository root: lua5.1 tests/mail/test.lua
local W = dofile("tests/mail/wow.lua")
local test, eq = W.test, W.eq

test("every language has every text", function()
    Fake({})
    W.CheckLocales(Load())
end)

test("take all gets money and items, and leaves cash on delivery alone", function()
    Fake({ inbox = { { sender = "A", money = 500 }, { sender = "B", items = { 1, 2 } },
                     { sender = "C", cod = 100, items = { 3 } }, { sender = "GM", gm = true, money = 9 } } })
    local ns = Load()
    W.Fire("MAIL_SHOW")
    local s = ns.Summary()
    eq(s.items, 2); eq(s.money, 500); eq(s.cod, 2)
    ns.TakeAll()
    W.Drain()
    eq(W.money, 500)
    eq(#W.taken, 2)
    assert(W.printed[#W.printed]:find("took 2 items", 1, true), W.printed[#W.printed])
end)

test("take all stops when the bags are full", function()
    Fake({ free = 1, inbox = { { sender = "A", items = { 1, 2, 3 } } } })
    local ns = Load()
    W.Fire("MAIL_SHOW")
    ns.TakeAll()
    W.Drain()
    eq(#W.taken, 1)
    assert(W.printed[#W.printed]:find("bags are full", 1, true))
end)

test("closing the mailbox stops take all", function()
    Fake({ inbox = { { sender = "A", items = { 1, 2, 3 } } } })
    local ns = Load()
    W.Fire("MAIL_SHOW")
    ns.TakeAll()
    W.Fire("MAIL_CLOSED")
    W.Drain()
    eq(#W.taken, 1)
end)

test("an item the game refuses is tried a few times, then left and counted", function()
    Fake({ refuse = { [2] = true }, inbox = { { sender = "A", items = { 1, 2, 3 } }, { sender = "B", money = 7 } } })
    local ns = Load()
    W.Fire("MAIL_SHOW")
    ns.TakeAll()
    W.Drain()
    eq(ns.taking, nil, "take all ended")
    eq(#W.taken, 2); eq(W.money, 7)
    local last = W.printed[#W.printed]
    assert(last:find("took 2 items", 1, true), last)
    assert(last:find("1 items could not be taken", 1, true), last)
end)

test("more than 50 letters: take all asks the server for the rest and goes on", function()
    local inbox, server = {}, {}
    for i = 1, 50 do inbox[i] = { sender = "AH", money = 1 } end
    for i = 1, 30 do server[i] = { sender = "AH", money = 1 } end
    Fake({ inbox = inbox, server = server })
    local ns = Load()
    W.Fire("MAIL_SHOW")
    eq(ns.Summary().more, 30)
    ns.TakeAll()
    for _ = 1, 400 do
        if #W.timers == 0 then break end
        W.now = W.now + 5
        W.RunTimers()
    end
    eq(W.money, 80)
    assert(W.checks > 0, "asked the server")
    eq(ns.taking, nil)
end)

test("names: own characters of this faction first, then recent recipients", function()
    Fake({ name = "Me", db = { alts = { Realm = { Alliance = { Me = true, Bank = true }, Horde = { Orc = true } } } } })
    local ns = Load()
    W.Fire("PLAYER_LOGIN")
    W.hooks.SendMail("Friend")
    W.hooks.SendMail("Other")
    W.hooks.SendMail("friend")
    local names = ns.Names()
    eq(#names, 3)
    eq(names[1].name, "Bank"); eq(names[1].alt, true)
    eq(names[2].name, "friend")
    eq(names[3].name, "Other")
    ns.Pick("Bank")
    eq(W.to, "Bank"); eq(W.tab, 2)
end)

test("a new character has no names yet and the panel says how the list fills", function()
    Fake({ inbox = { { sender = "Auction House", money = 5 } } })
    local ns = Load()
    W.Fire("PLAYER_LOGIN")
    eq(#ns.Names(), 0, "only the player, who is never listed")
    W.Fire("MAIL_SHOW")
    assert(ns.L.NO_NAMES ~= "" and ns.L.NO_NAMES_SUB ~= "", "the empty list has its texts")
end)

test("the panel moves next to an open letter and back", function()
    Fake({ inbox = { { sender = "A", money = 5 } } })
    local ns = Load()
    MailFrame = W.stub()
    OpenMailFrame = W.stub()
    W.Fire("MAIL_SHOW")
    eq(ns.PanelAnchor(), MailFrame, "next to the mailbox")
    OpenMailFrame:Show()
    OpenMailFrame._OnShow()
    eq(ns.PanelAnchor(), OpenMailFrame, "next to the open letter")
    OpenMailFrame:Hide()
    OpenMailFrame._OnHide()
    eq(ns.PanelAnchor(), MailFrame, "back next to the mailbox")
    MailFrame, OpenMailFrame = nil, nil
end)

test("the panel opens at the mailbox unless it is turned off", function()
    Fake({ inbox = { { sender = "A", money = 5 } } })
    Load()
    local before = #W.frames
    W.Fire("MAIL_SHOW")
    assert(#W.frames > before, "the panel was built")
    Fake({ db = { panel = false } })
    Load()
    before = #W.frames
    W.Fire("MAIL_SHOW")
    eq(#W.frames, before)
end)

test("switches: auction sales on, player letters off; money switch off", function()
    Fake({ inbox = { { sender = "AH", invoice = "seller", money = 100 }, { sender = "Bob", money = 50, items = { 1 } } } })
    local ns = Load()
    ns.db.player = false
    W.Fire("MAIL_SHOW")
    local s = ns.Summary()
    eq(s.money, 100); eq(s.items, 0); eq(s.off, 1)
    ns.TakeAll()
    W.Drain()
    eq(W.money, 100); eq(#W.taken, 0)
    eq(ns.visit.sold, 100)
    Fake({ inbox = { { sender = "Bob", money = 50, items = { 1 } } } })
    ns = Load()
    ns.db.money = false
    W.Fire("MAIL_SHOW")
    ns.TakeAll()
    W.Drain()
    eq(W.money, 0); eq(#W.taken, 1)
end)

test("keeps the free bag slots it is told to", function()
    Fake({ free = 3, inbox = { { sender = "A", items = { 1, 2, 3 } } } })
    local ns = Load()
    ns.db.keepFree = 2
    W.Fire("MAIL_SHOW")
    ns.TakeAll()
    W.Drain()
    eq(#W.taken, 1)
end)

test("one letter: Take takes only it, even with its kind switched off; Take selected takes the ticked ones", function()
    Fake({ inbox = { { sender = "A", money = 1, items = { 1 } }, { sender = "B", money = 2 }, { sender = "C", money = 4 } } })
    local ns = Load()
    ns.db.player = false
    W.Fire("MAIL_SHOW")
    ns.TakeAll({ 1 })
    W.Drain()
    eq(W.money, 1); eq(#W.taken, 1)
    eq(#W.inbox, 2, "the empty letter went")
    ns.TakeAll({ 1, 2 })
    W.Drain()
    eq(W.money, 7)
end)

test("Take selected does not take a letter that slides into a taken one's place", function()
    Fake({ inbox = { { sender = "AH", money = 1 }, { sender = "AH", money = 2 }, { sender = "AH", money = 4 } } })
    local ns = Load()
    W.Fire("MAIL_SHOW")
    ns.TakeAll({ 2 })
    W.Drain()
    eq(W.money, 2)
end)

test("Return sends a player's letter back, never an auction letter", function()
    Fake({ inbox = { { sender = "Bob", items = { 1 } }, { sender = "AH", invoice = "buyer", items = { 2 } } } })
    local ns = Load()
    eq(ns.Return(1), true)
    eq(ns.Return(2), false)
    eq(#W.returned, 1); eq(W.returned[1], "Bob")
    local letters = ns.Letters()
    eq(letters[1].canReturn, true); eq(letters[2].canReturn, false)
    eq(letters[2].kind, "bought")
end)

test("the visit total goes to the hub feed, the takes to the log", function()
    Fake({ inbox = { { sender = "AH", invoice = "seller", money = 300 }, { sender = "Bob", items = { 5 } } } })
    local ns = Load()
    local fed = {}
    GulliToolkit = { Notify = function(_, text) fed[#fed + 1] = text end }
    W.Fire("MAIL_SHOW")
    ns.TakeAll()
    W.Drain()
    W.Fire("MAIL_CLOSED")
    eq(#fed, 1)
    assert(fed[1]:find("1 items", 1, true), fed[1])
    eq(#ns.db.log, 2)
    GulliToolkit = nil
end)

test("letters that run out soon: a warning here, and on the other characters at login", function()
    Fake({ name = "Bank", inbox = { { sender = "Bob", items = { 1 }, days = 1.5 }, { sender = "Ann", money = 5, days = 20 } } })
    local ns = Load()
    W.Fire("MAIL_SHOW")
    W.Fire("MAIL_INBOX_UPDATE")
    assert(W.printed[#W.printed]:find("run out soon", 1, true), W.printed[#W.printed])
    local db = GulliMailDB
    Fake({ name = "Main", db = db })
    ns = Load()
    W.Fire("PLAYER_LOGIN")
    local o = ns.OthersExpiring()
    eq(#o, 1); eq(o[1].name, "Bank"); eq(o[1].n, 1)
    assert(W.printed[#W.printed]:find("Bank has 1", 1, true), W.printed[#W.printed])
end)

test("names: friends and guild after own characters and recent; a search filters them", function()
    Fake({ name = "Me", friends = { "Zed", "Amy" }, guild = { "Gil-Realm", "Amy" } })
    local ns = Load()
    W.Fire("PLAYER_LOGIN")
    W.hooks.SendMail("Rex")
    local all = ns.Names()
    eq(#all, 4)
    eq(all[1].name, "Rex"); eq(all[2].name, "Amy"); eq(all[2].group, "friend")
    eq(all[4].name, "Gil"); eq(all[4].group, "guild")
    local found = ns.Names("am")
    eq(#found, 1); eq(found[1].name, "Amy")
end)

test("quick attach puts unbound, unprotected items of a kind into the letter", function()
    Fake({ bags = { [0] = { [1] = { id = 10 }, [2] = { id = 11, bound = true }, [3] = { id = 12 }, [4] = { id = 13 } } },
           classes = { [10] = { 7, 5 }, [11] = { 7, 5 }, [12] = { 7, 9 }, [13] = { 7, 5 } } })
    local ns = Load()
    GulliToolkit = { IsProtected = function(id) return id == 13 end }
    eq(ns.AttachKind("cloth"), 0, "the send tab is closed")
    SendMailFrame:Show()
    eq(ns.AttachKind("cloth"), 1)
    eq(W.used[1], 10)
    GulliToolkit = nil
end)

test("a quick attach tile counts the stacks that fit and shows the icon of the item it has most of", function()
    Fake({ bags = { [0] = { [1] = { id = 10, count = 5 }, [2] = { id = 20, count = 20 }, [3] = { id = 20, count = 20 },
                            [4] = { id = 12, count = 3 } } },
           classes = { [10] = { 7, 5 }, [20] = { 7, 5 }, [12] = { 7, 9 } } })
    local ns = Load()
    local cloth = ns.KindInfo("cloth")
    eq(cloth.stacks, 3); eq(cloth.total, 45); eq(cloth.items[1].id, 20); eq(cloth.icon, "icon20")
    local ore = ns.KindInfo("ore")
    eq(ore.stacks, 0); eq(ore.icon, "icon2770", "an empty kind shows its sample item")
    eq(ns.KindInfo("all").stacks, 4, "all takes cloth and herbs")
    W.sendItems = 11
    SendMailFrame:Show()
    eq(ns.KindInfo("cloth").going, 1, "one place left in the letter")
end)

test("gold for another character keeps what the player asked for", function()
    Fake({})
    local ns = Load()
    W.money = 250000
    ns.db.keepGold = 10
    eq(ns.FillGold(), 150000)
    eq(W.sendMoney, 150000)
end)

test("a mailing rule fills the name and the items; the player sends", function()
    Fake({ bags = { [0] = { [1] = { id = 10 }, [2] = { id = 12 } } }, classes = { [10] = { 7, 5 }, [12] = { 7, 9 } } })
    local ns = Load()
    ns.AddRule("herb", "Alchy")
    ns.AddRule("cloth", "Tailor")
    SendMailFrame:Show()
    local r, n = ns.ApplyRule()
    eq(r.to, "Alchy"); eq(n, 1); eq(W.to, "Alchy"); eq(W.used[1], 12)
    r = ns.ApplyRule()
    eq(r.to, "Tailor")
    ns.RemoveRule(1)
    eq(#ns.db.rules, 1)
end)

test("the next take waits for the inbox to change", function()
    Fake({ inbox = { { sender = "A", items = { 1, 2 } } } })
    local ns = Load()
    W.Fire("MAIL_SHOW")
    ns.TakeAll()
    eq(#W.taken, 1)
    W.Fire("MAIL_INBOX_UPDATE")
    W.Drain()
    eq(#W.taken, 2)
end)

test("the panel and the settings window build", function()
    Fake({ inbox = { { sender = "A", money = 5 } } })
    local ns = Load()
    W.Fire("MAIL_SHOW")
    ns.ShowTab(2)
    ns.ShowTab(1)
    ns.open = false
    ns.Toggle()
    ns.Refresh()
end)

test("the hub gets a summary, a reset and a tip on each switch", function()
    Fake({})
    local reg
    GulliToolkit = { Register = function(t) reg = t end }
    local ns = Load()
    GulliToolkit = nil
    for _, o in ipairs(reg.options) do assert(o.tip, "a tip for " .. o.label) end
    ns.db.money = false
    reg.reset()
    eq(ns.db.money, true)
    eq(reg.summary(), nil, "no letters run out")
    ns.db.chars[GetRealmName()] = { Alt = { ends = { time() + 2 * 86400 } } }
    assert(reg.summary():find("1", 1, true))
end)

test("paused from the hub the mailbox panel stays closed", function()
    Fake({ inbox = { { sender = "A", money = 500 } } })
    local reg
    GulliToolkit = { Register = function(t) reg = t end }
    local ns = Load()
    GulliToolkit = nil
    reg.pause(true)
    W.Fire("MAIL_SHOW")
    eq(ns.open, nil, "paused: the visit is not watched")
    W.Fire("MAIL_CLOSED")
    reg.pause(false)
    W.Fire("MAIL_SHOW")
    eq(ns.open, true, "started again")
end)

-- Random inboxes: take all never touches cash on delivery or GM letters.
test("random inboxes: never take from cash on delivery or GM letters", function()
    math.randomseed(20261114)
    local taken = 0
    for round = 1, 200 do
        local inbox, safeMoney = {}, 0
        for i = 1, math.random(1, 12) do
            local l = { sender = "P" .. i }
            local kind = math.random(4)
            local items = {}
            for _ = 1, math.random(0, 3) do items[#items + 1] = (kind <= 2 and 1 or 1000) + math.random(50) end
            if #items > 0 then l.items = items end
            if math.random() < 0.5 then l.money = math.random(1, 900) end
            if kind == 3 then l.cod = math.random(1, 500) end
            if kind == 4 then l.gm = true; l.sender = "GM" end
            if kind <= 2 then safeMoney = safeMoney + (l.money or 0) end
            inbox[#inbox + 1] = l
        end
        Fake({ inbox = inbox, free = 40 })
        local ok, err = pcall(function()
            local ns = Load()
            W.Fire("MAIL_SHOW")
            ns.TakeAll()
            W.Drain()
            taken = taken + #W.taken
            for _, id in ipairs(W.taken) do assert(id < 1000, "took item " .. id .. " from a COD or GM letter") end
            assert(W.money <= safeMoney, "took money from a COD or GM letter")
        end)
        if not ok then error("round " .. round .. ": " .. tostring(err), 0) end
    end
    assert(taken > 100, "the rounds took too little to prove anything: " .. taken)
end)

W.finish()
