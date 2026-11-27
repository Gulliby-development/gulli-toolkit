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
    W.Fire("MAIL_SHOW")
    ns.Pick("Bank")
    eq(W.to, "Bank"); eq(W.tab, 2)
end)

test("names: a character with a surname is saved and offered by its whole name", function()
    Fake({ name = "Bullet", surname = "Rainy", faction = "Horde", db = {
        alts = { Realm = { Horde = { Bullet = true, Hero = true } } },
        chars = { Realm = { Bullet = { seen = 5, ends = {} } } },
        recent = { Realm = { "bullet rainy", "Niviera Smiles" } } } })
    local ns = Load()
    W.Fire("PLAYER_LOGIN")
    eq(ns.db.alts.Realm.Horde.Bullet, nil, "the first name alone is gone")
    eq(ns.db.alts.Realm.Horde["Bullet Rainy"], true)
    eq(ns.db.chars.Realm.Bullet, nil); eq(ns.db.chars.Realm["Bullet Rainy"].seen, 5)
    local names = ns.Names()
    eq(#names, 2, "the player is never listed, in any case")
    eq(names[1].name, "Hero"); eq(names[2].name, "Niviera Smiles")
    -- on the other character the whole name is the one to write to
    Fake({ name = "Hero", faction = "Horde", db = { alts = { Realm = { Horde = { ["Bullet Rainy"] = true } } } } })
    ns = Load()
    W.Fire("PLAYER_LOGIN")
    W.Fire("MAIL_SHOW")
    names = ns.Names()
    eq(names[1].name, "Bullet Rainy"); eq(names[1].alt, true)
    ns.Pick(names[1].name)
    eq(W.to, "Bullet Rainy")
end)

test("names: a player whose letter was taken is someone to write back to", function()
    Fake({ inbox = { { sender = "Pen Pal", items = { 1 } } } })
    local ns = Load()
    W.Fire("PLAYER_LOGIN")
    W.Fire("MAIL_SHOW")
    ns.TakeAll()
    W.Drain()
    local found = false
    for _, n in ipairs(ns.Names()) do if n.name == "Pen Pal" then found = n.group == "recent" end end
    assert(found, "the sender is listed with the recent names")
    eq(ns.db.recent.Realm[1], "Pen Pal")
end)

test("names: an empty realm finds the saved names even when the normalized realm name differs", function()
    Fake({ name = "Hero", faction = "Horde", db = {
        alts = { ["R 4"] = { Horde = { Hero = true, Dali = true } } }, recent = { ["R 4"] = { "Niviera" } } } })
    GetRealmName = function() return "" end
    GetNormalizedRealmName = function() return "R4" end
    local ns = Load()
    W.Fire("PLAYER_LOGIN")
    local names = ns.Names()
    GetNormalizedRealmName = nil
    eq(names[1].name, "Dali"); eq(names[2].name, "Niviera")
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

test("Take all takes everything but cash on delivery and GM letters; old switches are dropped", function()
    Fake({ db = { money = false, player = false, sold = false, keepFree = 5, keepGold = 10, subject = false,
                  rules = { { kind = "cloth", to = "Bob" } } },
           free = 3,
           inbox = { { sender = "AH", invoice = "seller", money = 100 }, { sender = "Bob", money = 50, items = { 1 } },
                     { sender = "Cod", cod = 10, items = { 2 } } } })
    local ns = Load()
    for _, k in ipairs({ "money", "player", "sold", "keepFree", "keepGold", "subject" }) do
        eq(ns.db[k], nil, k .. " is gone from the save")
    end
    eq(ns.db.rules[1].to, "Bob", "the mailing rules stay")
    eq(ns.db.panel, true)
    W.Fire("MAIL_SHOW")
    local s = ns.Summary()
    eq(s.money, 150); eq(s.items, 1); eq(s.cod, 1)
    ns.TakeAll()
    W.Drain()
    eq(W.money, 150); eq(#W.taken, 1, "down to the last free slot, and never the cash on delivery")
    eq(ns.visit.sold, 100)
end)

test("one letter: Take takes only it; Take selected takes the ticked ones", function()
    Fake({ inbox = { { sender = "A", money = 1, items = { 1 } }, { sender = "B", money = 2 }, { sender = "C", money = 4 } } })
    local ns = Load()
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

test("quick attach and the kind tiles also take the reagent bag (bag 5 on WoW Forever)", function()
    Fake({ bags = { [5] = { [1] = { id = 10, count = 7 } } }, classes = { [10] = { 7, 5 } } })
    NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
    local ns = Load()
    eq(ns.KindInfo("cloth").stacks, 1)
    SendMailFrame:Show()
    eq(ns.AttachKind("cloth"), 1)
    eq(W.used[1], 10)
    NUM_TOTAL_EQUIPPED_BAG_SLOTS = nil
end)

test("the auction tile takes what sells better at the auction than at a vendor, only with prices", function()
    Fake({ bags = { [0] = { [1] = { id = 10 }, [2] = { id = 30 }, [3] = { id = 31 }, [4] = { id = 32 }, [5] = { id = 33, bound = true } } },
           classes = { [10] = { 7, 5 }, [30] = { 4, 2 }, [31] = { 7, 5 }, [32] = { 4, 1 }, [33] = { 4, 2 } } })
    local ns = Load()
    SendMailFrame:Show()
    eq(ns.KindInfo("auction").stacks, 0, "no price addon: nothing")
    local prices = { [10] = 100, [30] = 50, [31] = 1, [33] = 500 }
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(_, id) return prices[id] end } } }
    local info = ns.KindInfo("auction")
    eq(info.stacks, 2, "cloth and gear above the vendor; 1 copper less the cut is not; no price; bound")
    eq(ns.KindInfo("all").stacks, 2, "all stays trade goods")
    eq(ns.AttachKind("auction"), 2)
    eq(W.used[1], 10); eq(W.used[2], 30)
    Auctionator = nil
end)

test("all gold goes less the postage, and the button opens the send tab itself", function()
    Fake({})
    local ns = Load()
    W.money = 250000
    eq(ns.FillGold(), 0, "away from a mailbox nothing happens")
    W.Fire("MAIL_SHOW")
    eq(ns.GoldToSend(), 250000 - 30, "the amount is known before the click")
    eq(SendMailFrame:IsShown(), false)
    eq(ns.FillGold(), 250000 - 30, "less the postage, or the game refuses the letter")
    eq(SendMailFrame:IsShown(), true, "the click opened the send tab")
    eq(W.sendMoney, 250000 - 30)
    W.postage = 60
    eq(ns.FillGold(), 250000 - 60)
    W.money = 20
    eq(ns.FillGold(), 0, "never below nothing")
end)

test("a tile opens the send tab itself; paused it does nothing", function()
    Fake({ bags = { [0] = { [1] = { id = 10 }, [2] = { id = 12 } } }, classes = { [10] = { 7, 5 }, [12] = { 7, 9 } } })
    local ns = Load()
    eq(ns.AttachKind("cloth"), 0, "no mailbox, no letter")
    W.Fire("MAIL_SHOW")
    ns.paused = true
    eq(ns.AttachKind("cloth"), 0)
    eq(SendMailFrame:IsShown(), false)
    ns.paused = false
    eq(ns.AttachKind("cloth"), 1)
    eq(SendMailFrame:IsShown(), true)
    eq(W.used[1], 10)
end)

test("our Send clicks the game's button only while the game would send; the name stays after", function()
    Fake({})
    local ns = Load()
    W.Fire("MAIL_SHOW")
    local line, can = ns.SendLine()
    eq(line, ns.L.ST_PICK); eq(can, false)
    eq(ns.Send(), false); eq(W.sends, 0, "no name: nothing is sent")
    ns.Pick("Bob")
    eq(SendMailFrame:IsShown(), true); eq(W.to, "Bob")
    local st = ns.SendState()
    eq(st.to, "Bob"); eq(st.items, 0); eq(st.money, 0); eq(st.can, true)
    line = ns.SendLine()
    assert(line:find("Bob", 1, true) and line:find(ns.L.ST_EMPTY, 1, true), line)
    W.sendItems, W.sendMoney = 3, 120000
    line = ns.SendLine()
    assert(line:find("3", 1, true) and not line:find(ns.L.ST_EMPTY, 1, true), line)
    eq(ns.SendState().money, 120000)
    -- the game says no (no subject yet, a send running): our button follows it
    W.canSend = false
    eq(ns.Send(), false); eq(W.sends, 0)
    W.canSend = nil
    ns.paused = true
    eq(ns.Send(), false); eq(W.sends, 0, "a paused module sends nothing")
    ns.paused = false
    eq(ns.Send(), true); eq(W.sends, 1)
    -- the game empties the letter; the name comes back
    W.to, W.sendItems, W.sendMoney = "", 0, 0
    W.Fire("MAIL_SEND_SUCCESS")
    W.Drain()
    eq(W.to, "Bob", "the next letter goes to the same character")
    -- a name the player typed stays too
    W.to = "Ann"
    eq(ns.Send(), true)
    W.to = ""
    W.Fire("MAIL_SEND_SUCCESS")
    W.Drain()
    eq(W.to, "Ann")
    -- a new visit starts clean
    W.Fire("MAIL_CLOSED")
    SendMailFrame:Hide()
    W.to = ""
    W.Fire("MAIL_SHOW")
    eq(ns.SendState().to, "")
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
    eq(#reg.options, 1, "one switch: the panel")
    for _, o in ipairs(reg.options) do assert(o.tip, "a tip for " .. o.label) end
    ns.db.panel = false
    reg.reset()
    eq(ns.db.panel, true)
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

test("take by kind takes only the items of that kind, from every letter, and no money", function()
    Fake({ classes = { [10] = { 7, 9 }, [11] = { 7, 9 }, [20] = { 7, 5 }, [30] = { 4, 1 }, [40] = { 7, 9 } },
           inbox = { { sender = "A", money = 50, items = { 10, 20 } }, { sender = "AH", invoice = "buyer", items = { 11 } },
                     { sender = "C", cod = 100, items = { 40 } }, { sender = "D", items = { 30 } } } })
    local ns = Load()
    W.Fire("MAIL_SHOW")
    local info = ns.InboxKindInfo("herb")
    eq(info.stacks, 2, "cash on delivery left out")
    eq(ns.InboxKindInfo("cloth").stacks, 1)
    eq(ns.InboxKindInfo("ore").stacks, 0)
    ns.TakeAll(nil, "herb")
    W.Drain()
    table.sort(W.taken)
    eq(#W.taken, 2); eq(W.taken[1], 10); eq(W.taken[2], 11)
    eq(W.money, 0, "no money")
    eq(ns.InboxKindInfo("herb").stacks, 0)
    ns.TakeAll(nil, "all")
    W.Drain()
    eq(#W.taken, 3, "all goods: the cloth too, not the armour")
    eq(W.taken[3], 20)
end)

test("gems go by id as WoW Forever files them, consumables by subclass and not in all goods", function()
    -- Forever: Malachite and Hot Spices are both Trade Goods, Other (7/11); a potion 0/1, a
    -- sharpening stone 0/8, food 0/5, Linen 7/5.
    Fake({ classes = { [774] = { 7, 11 }, [2692] = { 7, 11 }, [13446] = { 0, 1 }, [2862] = { 0, 8 },
                       [1645] = { 0, 5 }, [2589] = { 7, 5 }, [12800] = { 7, 11 } },
           inbox = { { sender = "A", items = { 774, 2692, 2589 } }, { sender = "AH", invoice = "buyer", items = { 13446, 2862, 1645 } },
                     { sender = "B", items = { 12800 } } } })
    local ns = Load()
    W.Fire("MAIL_SHOW")
    eq(ns.InboxKindInfo("gem").stacks, 2, "Malachite and the diamond, not the spices")
    eq(ns.InboxKindInfo("consumable").stacks, 2, "the potion and the stone, not the food")
    eq(ns.InboxKindInfo("cloth").stacks, 1)
    eq(ns.InboxKindInfo("all").stacks, 3, "all goods: cloth and gems, no potions")
    ns.TakeAll(nil, "consumable")
    W.Drain()
    table.sort(W.taken)
    eq(#W.taken, 2); eq(W.taken[1], 2862); eq(W.taken[2], 13446)
    ns.TakeAll(nil, "gem")
    W.Drain()
    eq(#W.taken, 4)
    eq(ns.KindHas(ns.KindOf("gem"), 3, 0, 99999), true, "a client with the Gem class still counts it")
end)

test("take by kind stops when the bags are full", function()
    Fake({ free = 1, classes = { [10] = { 7, 9 }, [11] = { 7, 9 } }, inbox = { { sender = "A", items = { 10, 11 } } } })
    local ns = Load()
    W.Fire("MAIL_SHOW")
    ns.TakeAll(nil, "herb")
    W.Drain()
    eq(#W.taken, 1)
    assert(W.printed[#W.printed]:find("bags are full", 1, true))
end)

test("walking away from the mailbox closes the panel, once", function()
    Fake({ inbox = { { sender = "AH", invoice = "seller", money = 300 } } })
    local fed = {}
    GulliToolkit = { Notify = function(_, text) fed[#fed + 1] = text end }
    local ns = Load()
    local hidden = 0
    local hide = ns.HidePanel
    ns.HidePanel = function() hidden = hidden + 1; hide() end
    W.Fire("MAIL_SHOW")
    ns.TakeAll()
    W.Drain()
    W.Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 5) -- another window: stays
    eq(hidden, 0, "another interaction leaves it")
    eq(ns.open, true)
    W.Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 17)
    eq(hidden, 1, "walking away hides it")
    eq(ns.open, false)
    W.Fire("MAIL_CLOSED")
    eq(#fed, 1, "the visit is told once")
    eq(hidden, 1, "and hidden once")
    -- next visit: the mailbox frame hides (walked away) with no event at all
    W.Fire("MAIL_SHOW")
    eq(ns.open, true)
    if MailFrame and MailFrame.Hide then MailFrame:Show(); MailFrame:Hide() end
    if MailFrame then eq(hidden, 2, "the mailbox frame hiding closes it too") end
    GulliToolkit = nil
end)

test("an empty realm name never splits one realm into two", function()
    Fake({ db = { alts = { [""] = { Alliance = { Tester = true } }, Realm = { Alliance = { Alt = true } } },
                  chars = { [""] = { Tester = { ends = { 5 }, seen = 20 } },
                            Realm = { Tester = { ends = {}, seen = 10 }, Alt = { ends = {}, seen = 1 } } },
                  recent = { [""] = { "Bob" }, Realm = { "Ann", "bob" } } } })
    GetRealmName = function() return "" end
    local ns = Load()
    eq(ns.db.alts[""], nil); eq(ns.db.chars[""], nil); eq(ns.db.recent[""], nil)
    eq(ns.db.alts.Realm.Alliance.Tester, true)
    eq(ns.db.alts.Realm.Alliance.Alt, true)
    eq(ns.db.chars.Realm.Tester.seen, 20, "the newer snapshot wins")
    eq(table.concat(ns.db.recent.Realm, ","), "Bob,Ann")
    eq(ns.Realm(), "Realm", "the one realm saved stands in")
    ns.Snapshot()
    eq(ns.db.chars[""], nil, "a snapshot without a realm keeps the saved realm")
end)

test("a letter of gold alone gets a subject, which the player can change", function()
    Fake({})
    local ns = Load()
    local box = { text = "" }
    function box:GetText() return self.text end
    function box:SetText(t) self.text = t end
    SendMailSubjectEditBox = box
    local copper = 0
    MoneyInputFrame_GetCopper = function() return copper end
    SendMailFrame_Update = function() end
    W.Fire("MAIL_SHOW")
    assert(W.hooks.SendMailFrame_Update, "hooked once the mail frame exists")
    SendMailFrame:Show()
    eq(ns.AutoSubject(), "", "no money, no subject")
    copper = 125050
    eq(ns.AutoSubject(), "12g 50s")
    eq(box.text, "12g 50s")
    copper = 300000
    ns.AutoSubject()
    eq(box.text, "30g", "a filled subject follows the amount")
    box.text = "Rent"
    copper = 10
    ns.AutoSubject()
    eq(box.text, "Rent", "the player's own subject stays")
    box.text = ""
    ns.AutoSubject()
    eq(box.text, "10c")
    -- an item in the letter: its name takes the place of the amount
    W.sendItems = 1
    ns.AutoSubject()
    eq(box.text, "Item10")
    -- the game left the subject of a letter with items empty: never empty
    box.text = ""
    W.sendCount = 3
    ns.AutoSubject()
    eq(box.text, "Item10 (3)")
    box.text = "For you"
    ns.AutoSubject()
    eq(box.text, "For you", "a typed subject stays with items too")
    -- the item leaves: a subject we filled goes back to the amount
    box.text = ""
    ns.AutoSubject()
    W.sendItems = 0
    ns.AutoSubject()
    eq(box.text, "10c")
    -- paused: nothing
    box.text = ""
    ns.paused = true
    eq(ns.AutoSubject(), nil); eq(box.text, "")
    ns.paused = false
    SendMailFrame:Hide()
    eq(ns.AutoSubject(), nil, "only on the send tab")
    SendMailSubjectEditBox, MoneyInputFrame_GetCopper, SendMailFrame_Update = nil, nil, nil
end)

test("a kind goes to the own character whose profession uses it, never to this one", function()
    Fake({ profs = { { "Mining", 120, 300, nil, 186 } },
           db = { alts = { Realm = { Alliance = { Zot = true, Amy = true, Kim = true } } },
                  profs = { Realm = { Alliance = { Zot = { [171] = 120 }, Amy = { [171] = 250, [197] = 75 }, Kim = { [164] = 90 } } } } },
           bags = { [0] = { [1] = { id = 10, count = 20 }, [2] = { id = 12, count = 5 }, [3] = { id = 14, count = 8 } } },
           classes = { [10] = { 7, 9 }, [12] = { 7, 5 }, [14] = { 7, 7 } } })
    local ns = Load()
    W.Fire("PLAYER_LOGIN")
    eq(ns.db.profs.Realm.Alliance.Tester[186], 120, "this character's professions are noted at login")
    eq((ns.ProfAlt("herb")), "Amy", "the highest skill")
    eq((ns.ProfAlt("ore")), "Kim", "blacksmith or engineer")
    eq(ns.ProfAlt("gem"), nil, "a kind no profession is tied to")
    local letters = ns.RuleLetters()
    eq(#letters, 3, "herbs and cloth to Amy, ore to Kim")
    eq(letters[1].kind, "cloth", "in the order of the kinds"); eq(letters[2].to, "Amy"); eq(letters[2].total, 20)
    ns.db.profs.Realm.Alliance.Tester[171] = 1
    eq(ns.ProfAlt("herb"), nil, "an alchemist keeps their own herbs")
end)

test("the player's rules come first, a default can go off and comes back", function()
    Fake({ db = { alts = { Realm = { Alliance = { Amy = true, Bob = true } } }, profs = { Realm = { Alliance = { Amy = { [171] = 50 } } } } },
           bags = { [0] = { [1] = { id = 10 }, [2] = { id = 11 } } }, classes = { [10] = { 7, 9 }, [11] = { 7, 9 } } })
    local ns = Load()
    local rules = ns.Rules()
    eq(#rules, 1); eq(rules[1].auto, true); eq(rules[1].to, "Amy")
    ns.SetRuleOn(rules[1], false)
    eq(#ns.RuleLetters(), 0, "turned off")
    eq(ns.Rules()[1].off, true, "still listed, to turn on again")
    ns.SetRuleOn(ns.Rules()[1], true)
    eq(#ns.RuleLetters(), 1)
    ns.SetRuleTo(ns.Rules()[1], "Bob")
    rules = ns.Rules()
    eq(#rules, 1, "the default became the player's own rule"); eq(rules[1].auto, nil); eq(rules[1].to, "Bob")
    ns.AddRule("herb", "Cy")
    eq(ns.RuleLetters()[1].total, 2, "an item goes to the first rule only")
    eq(#ns.RuleLetters(), 1)
    ns.RemoveRule(1); ns.RemoveRule(1)
    eq(ns.Rules()[1].auto, true, "no rule of its own: the profession rule is back")
    ns.AddRule("herb", "Tester")
    eq(#ns.RuleLetters(), 0, "nothing goes to the character playing, and the default stays behind the own rule")
end)

test("fill puts one letter of a rule together, up to twelve; the player sends it", function()
    local bag = {}
    for i = 1, 14 do bag[i] = { id = 10 } end
    Fake({ db = { rules = { { kind = "cloth", to = "Bob" } } }, bags = { [0] = bag }, classes = { [10] = { 7, 5 } } })
    local ns = Load()
    eq(ns.FillRule(1), 0, "away from a mailbox nothing happens")
    W.Fire("MAIL_SHOW")
    eq(ns.RuleLetters()[1].letters, 2)
    eq(ns.FillRule(1), 12)
    eq(W.to, "Bob"); eq(SendMailFrame:IsShown(), true)
    eq(W.sends, 0, "never sent without the player's click")
    eq(ns.RuleLetters()[1].stacks, 2)
end)

test("Chores' snapshot fills in a character Mail has not seen yet", function()
    Fake({ db = { alts = { Realm = { Alliance = { ["Amy Rose"] = true } } } } })
    GulliChoresDB = { chars = { ["Amy-Realm"] = { name = "Amy", faction = "Alliance", profs = { { name = "Tailoring", line = 197, skill = 80 } } } } }
    local ns = Load()
    eq((ns.ProfAlt("cloth")), "Amy Rose")
    GulliChoresDB = nil
end)

W.finish()
