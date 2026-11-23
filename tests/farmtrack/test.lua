-- Run from the repository root: lua5.1 tests/farmtrack/test.lua
local W = dofile("tests/farmtrack/wow.lua")
local test, eq = W.test, W.eq

local CLOTH, ORE = 4338, 2772

test("every language has every text", function()
    Fake({})
    W.CheckLocales(Load())
end)

test("what comes into the bags counts, what was there before does not", function()
    Fake({ bags = { [CLOTH] = 5 }, now = 0 })
    local ns = Load()
    W.now = 60; W.Loot(CLOTH, 3)
    W.now = 120; W.Loot(ORE, 2)
    eq(ns.s.items[CLOTH], 3)
    eq(ns.s.items[ORE], 2)
    W.Loot(CLOTH, -4) -- used or destroyed: no minus, and looting again counts again
    W.Loot(CLOTH, 2)
    eq(ns.s.items[CLOTH], 5)
end)

test("an item in the hand does not count when it goes back", function()
    Fake({ bags = { [CLOTH] = 20 } })
    local ns = Load()
    W.cursor = CLOTH; W.bags[CLOTH] = 0; W.Fire("CURSOR_CHANGED")
    W.cursor = nil; W.bags[CLOTH] = 20; W.Fire("CURSOR_CHANGED")
    eq(ns.s.items[CLOTH], nil)
end)

test("vendors, mail, bank, auction house and trade do not count", function()
    for _, ev in ipairs({ { "MERCHANT_SHOW", "MERCHANT_CLOSED" }, { "MAIL_SHOW", "MAIL_CLOSED" },
                          { "BANKFRAME_OPENED", "BANKFRAME_CLOSED" }, { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" },
                          { "TRADE_SHOW", "TRADE_CLOSED" } }) do
        Fake({ now = 100 })
        local ns = Load()
        W.Fire(ev[1])
        W.Loot(ORE, 10)
        W.Fire(ev[2])
        W.Loot(ORE, 1) -- still settling right after closing
        eq(ns.s.items[ORE], nil, ev[1])
        W.now = 110
        W.Loot(ORE, 2)
        eq(ns.s.items[ORE], 2, ev[1] .. " later")
    end
end)

test("a close event that never came does not stop the counting", function()
    Fake({ now = 100 })
    local ns = Load()
    -- the game knows the vendor window is shut
    W.Fire("MERCHANT_SHOW")
    MerchantFrame = W.stub(); MerchantFrame:Hide()
    W.now = 110
    W.Loot(ORE, 3)
    eq(ns.s.items[ORE], 3, "a hidden window does not keep the counter deaf")
    W.Money(500)
    eq(ns.s.money, 500)
    MerchantFrame = nil
    -- the interaction manager says the mailbox is over
    W.Fire("MAIL_SHOW")
    C_PlayerInteractionManager = { IsInteractingWithNpcOfType = function() return false end }
    Enum = { PlayerInteractionType = { MailInfo = 17, Merchant = 5, Banker = 8, Auctioneer = 21, TradePartner = 1 } }
    W.now = 120
    W.Loot(ORE, 1)
    eq(ns.s.items[ORE], 4)
    -- while it is still open, nothing counts
    C_PlayerInteractionManager.IsInteractingWithNpcOfType = function(k) return k == 8 end
    W.Fire("BANKFRAME_OPENED")
    W.Loot(ORE, 5)
    eq(ns.s.items[ORE], 4, "the bank is open")
    C_PlayerInteractionManager, Enum = nil, nil
    -- no way to ask the game: looting proves the window is gone
    W.Fire("TRADE_SHOW")
    W.Loot(ORE, 1)
    eq(ns.s.items[ORE], 4)
    W.Fire("LOOT_READY")
    W.now = 130
    W.Loot(ORE, 2)
    eq(ns.s.items[ORE], 6, "after looting it counts again")
    ns.Slash("debug")
end)

test("looted gold counts; vendor sales only with their switch; mail never", function()
    Fake({ money = 1000 })
    local ns = Load()
    W.Money(250)
    eq(ns.s.money, 250)
    W.Money(-100)
    eq(ns.s.money, 250, "spending does not take it away")
    W.Fire("MERCHANT_SHOW"); W.Money(500); W.Fire("MERCHANT_CLOSED")
    eq(ns.s.money, 750, "sales count by default")
    ns.SetPref("sales", false)
    W.Fire("MERCHANT_SHOW"); W.Money(500); W.Fire("MERCHANT_CLOSED")
    eq(ns.s.money, 750, "the switch stops it")
    ns.SetPref("sales", true)
    W.Fire("MAIL_SHOW"); W.Money(10000); W.Fire("MAIL_CLOSED")
    eq(ns.s.money, 750, "mail is not farmed")
end)

test("mail and the auction house count only with their switch", function()
    Fake({ now = 100, money = 1000 })
    local ns = Load()
    eq(ns.db.mail, false, "off by default")
    -- a letter taken through another addon's mail window: the game's frame is hidden
    W.Fire("MAIL_SHOW")
    MailFrame = W.stub(); MailFrame:Hide()
    ns.MailTake()
    W.Loot(ORE, 4); W.Money(5000)
    eq(ns.s.items[ORE], nil, "items from a letter")
    eq(ns.s.money, 0, "gold from a letter")
    MailFrame = nil
    W.Fire("MAIL_CLOSED")
    -- looting while the game still says the auction house is open keeps it closed off
    C_PlayerInteractionManager = { IsInteractingWithNpcOfType = function(k) return k == 21 end }
    Enum = { PlayerInteractionType = { MailInfo = 17, Merchant = 5, Banker = 8, Auctioneer = 21, TradePartner = 1 } }
    W.now = 120
    W.Fire("AUCTION_HOUSE_SHOW"); W.Fire("LOOT_READY")
    W.Loot(ORE, 2)
    eq(ns.s.items[ORE], nil, "an auction buy")
    W.Fire("AUCTION_HOUSE_CLOSED")
    C_PlayerInteractionManager, Enum = nil, nil
    -- with the switch, both count
    ns.SetPref("mail", true)
    W.now = 130
    W.Fire("MAIL_SHOW"); ns.MailTake()
    W.Loot(ORE, 3); W.Money(700)
    eq(ns.s.items[ORE], 3, "letters count with the switch")
    eq(ns.s.money, 700)
    W.Fire("MAIL_CLOSED")
    W.Fire("AUCTION_HOUSE_SHOW"); W.Loot(ORE, 1); W.Fire("AUCTION_HOUSE_CLOSED")
    eq(ns.s.items[ORE], 4, "auction buys count with the switch")
    -- the bank stays out either way
    W.Fire("BANKFRAME_OPENED"); W.Loot(ORE, 5); W.Fire("BANKFRAME_CLOSED")
    eq(ns.s.items[ORE], 4, "the bank never counts")
end)

test("the loot's worth: vendor, auction, disenchant, and the gold looted", function()
    local GREY, TOOTH, CLOTH2, BLUE, BLUE_BOP, GREEN, QUEST, UNKNOWN = 1, 2, 3, 4, 5, 6, 7, 8
    local items = {
        [GREY] = { quality = 0, sell = 100, class = 4 },
        [TOOTH] = { quality = 1, sell = 20, class = 15 },              -- plain white: vendor
        [CLOTH2] = { quality = 1, sell = 50, class = 7 },              -- trade goods: auction
        [BLUE] = { quality = 3, sell = 1000, class = 4, bind = 2 },    -- BoE blue: auction
        [BLUE_BOP] = { quality = 3, sell = 900, class = 2, bind = 1 }, -- bound: vendor
        [GREEN] = { quality = 2, sell = 300, class = 4, bind = 2, ilvl = 33 },
        [QUEST] = { quality = 1, sell = 0, class = 12 },
        [9] = { quality = 1, sell = 1, class = 15 },                   -- a writ: no vendor worth
        [10] = { quality = 1, sell = 1, class = 15, bind = 1 },        -- bound: stays at the vendor
    }
    Fake({ items = items, ah = { [9] = 25000, [10] = 25000, [CLOTH2] = 400, [BLUE] = 50000, [BLUE_BOP] = 99999, [TOOTH] = 9999,
                                 [11137] = 2000, [11134] = 1500 } })
    local ns = Load()
    W.Loot(GREY, 2); W.Loot(TOOTH, 3); W.Loot(CLOTH2, 10); W.Loot(BLUE, 1); W.Loot(BLUE_BOP, 1)
    W.Loot(GREEN, 1); W.Loot(QUEST, 1); W.Loot(UNKNOWN, 1)
    W.Money(777)
    eq(select(2, ns.ItemValue(TOOTH)), "vendor", "a white tooth goes to a vendor, not the auction")
    eq(select(2, ns.ItemValue(CLOTH2)), "auction")
    eq(select(2, ns.ItemValue(BLUE)), "auction")
    eq(select(2, ns.ItemValue(BLUE_BOP)), "vendor")
    eq(select(2, ns.ItemValue(GREEN)), "vendor", "no Enchanting: a vendor")
    eq(ns.ItemValue(9), 25000, "a tradeable item a vendor pays nothing for goes to the auction")
    eq(ns.ItemValue(10), 1)
    local total, unknown = ns.SessionValue()
    eq(unknown, 1, "an item the client does not know yet")
    eq(total, 777 + 200 + 60 + 4000 + 50000 + 900 + 300)
    -- with Enchanting a green is worth its cheapest disenchant result, when that beats the vendor
    Fake({ items = items, enchanter = true, ah = { [11137] = 2000, [11134] = 1500 } })
    ns = Load()
    eq(ns.ItemValue(GREEN, true), 1500)
    eq(select(2, ns.ItemValue(GREEN, true)), "disenchant")
    W.ah[11134] = 100; W.ah[11137] = 100
    eq(ns.ItemValue(GREEN, true), 300, "the vendor when it pays more")
    -- without Auctionator everything counts at the vendor
    Fake({ items = items })
    ns = Load()
    eq(ns.ItemValue(BLUE), 1000)
    -- vendor only: no auction and no disenchanting, every item at the vendor's price
    Fake({ items = items, enchanter = true, ah = { [9] = 25000, [CLOTH2] = 400, [BLUE] = 50000, [11137] = 2000, [11134] = 1500 } })
    ns = Load()
    ns.SetPref("vendorOnly", true)
    eq(ns.ItemValue(BLUE), 1000)
    eq(select(2, ns.ItemValue(CLOTH2)), "vendor")
    eq(select(2, ns.ItemValue(GREEN, true)), "vendor", "no disenchanting with vendor only")
    eq(select(2, ns.ItemValue(9)), "vendor")
    eq(select(2, ns.ItemValue(QUEST)), "quest")
    ns.SetPref("vendorOnly", false)
    eq(select(2, ns.ItemValue(BLUE)), "auction", "back to the auction when it goes off")
end)

test("the Session tab shows how the estimate is made, item by item", function()
    local GREY, CLOTH, NOPRICE, QUEST, UNKNOWN = 1, 2, 3, 4, 5
    local items = {
        [GREY] = { quality = 0, sell = 100, class = 4 },
        [CLOTH] = { quality = 1, sell = 50, class = 7 },
        [NOPRICE] = { quality = 1, sell = 30, class = 7 },
        [QUEST] = { quality = 1, sell = 0, class = 12 },
    }
    Fake({ items = items, ah = { [CLOTH] = 400 } })
    local ns = Load()
    W.Loot(GREY, 2); W.Loot(CLOTH, 10); W.Loot(NOPRICE, 3); W.Loot(QUEST, 1); W.Loot(UNKNOWN, 1)
    W.Money(1000)
    W.Fire("MERCHANT_SHOW"); W.Loot(GREY, -2); W.Money(200); W.Fire("MERCHANT_CLOSED")
    local rows = ns.WorthRows()
    eq(rows[1].id, CLOTH, "the most worth first"); eq(rows[1].total, 4000); eq(rows[1].how, "auction")
    eq(rows[2].how, "vendor"); eq(rows[2].total, 200)
    eq(rows[3].how, "noprice", "an auction item without a price counts at the vendor"); eq(rows[3].total, 90)
    eq(rows[4].how, "quest"); eq(rows[4].total, 0)
    eq(rows[5].how, "unknown", "not known yet: last")
    local p = ns.WorthParts()
    eq(p.gold, 1000, "the vendor sale is not gold looted")
    eq(p.sold, 200)
    eq(p.by.auction, 4000); eq(p.by.vendor, 200); eq(p.by.noprice, 90)
    eq(p.total, ns.SessionValue(), "the parts make the panel's worth")
    eq(p.total, 1000 + 4000 + 200 + 90)
    local lines, note = ns.WorthLines()
    eq(#lines, 5)
    assert(note:find("200", 1, true) or note:find("2s", 1, true), note)
    assert(note:find(ns.L.NOTE_NOPRICE, 1, true), "says why some items count at the vendor")
    eq(#ns.WorthItems(), 3, "items that add nothing are left off the list")
    ns.Toggle()
    local _, _, tabs, pages = ns.Parts()
    eq(#pages, 3, "Session, Farm, Settings")
    tabs:Select(2); tabs:Select(3); tabs:Select(1)
    ns.Refresh()
end)

test("the hub's session card gets the worth of the looted items", function()
    Fake({ items = { [9] = { quality = 0, sell = 100 } } })
    local ns = Load()
    eq(ns.Session(), nil, "nothing looted")
    W.Money(500)
    eq(ns.Session(), nil, "gold is the hub's own number")
    W.Loot(9, 3)
    local d = ns.Session()
    eq(d.worth, 300, "the items only, without the gold")
    eq(d.tile, nil)
    eq(ns.ItemsWorth(), 300)
    eq(ns.SessionValue(), 800)
end)

test("the worth line shows with its switch, and sales are not counted twice", function()
    Fake({ items = { [9] = { quality = 0, sell = 100 } } })
    local ns = Load()
    ns.SetPref("panel", true)
    ns.Refresh()
    assert(not ns.Parts(), "no panel: no target and no worth line")
    ns.SetPref("value", true)
    local panel = ns.Parts()
    assert(panel and panel:IsShown(), "the worth line alone shows the panel")
    W.Loot(9, 2)
    ns.Refresh()
    assert(ns.WorthText():find("2s"), ns.WorthText())
    W.Fire("MERCHANT_SHOW"); W.Loot(9, -2); W.Money(200); W.Fire("MERCHANT_CLOSED")
    eq(ns.s.money, 200, "the sale counts as gold")
    eq(ns.SessionValue(), 200, "but the worth counts the loot only once")
    ns.SetPref("value", false)
    eq(ns.WorthText(), nil)
end)

test("targets: at most three, one per item, gold once", function()
    Fake({})
    local ns = Load()
    assert(ns.AddTarget("item", CLOTH, 100))
    assert(ns.AddTarget("item", CLOTH, 40), "the same item sets its goal")
    eq(#ns.Targets(), 1)
    eq(ns.Targets()[1].goal, 40)
    assert(ns.AddTarget("gold"))
    assert(ns.AddTarget("item", ORE))
    assert(not ns.AddTarget("item", 999), "full")
    assert(ns.Tracked("gold"))
    ns.RemoveTarget(2)
    assert(not ns.Tracked("gold"))
    eq(ns.Targets()[2].id, ORE)
end)

test("the hub's session card gets the first item target that gained as a tile", function()
    Fake({ now = 0 })
    local got
    GulliToolkit = { Register = function(m) got = m end }
    local ns = Load()
    eq(got.session(), nil, "no target")
    ns.AddTarget("gold")
    ns.AddTarget("item", ORE)
    ns.AddTarget("item", CLOTH)
    eq(got.session(), nil, "nothing gained yet")
    ns.Gain("gold", 5000, 10)
    eq(got.session(), nil, "gold is the hub's own number")
    W.now = 60; W.Loot(CLOTH, 86)
    local s = got.session()
    eq(s.value, nil, "a tile only: it never leads the card")
    eq(s.tile.value, "86")
    eq(s.tile.label, ns.ItemName(CLOTH))
    eq(#s.tip.rows, 2, "every target that gained is a line of the tooltip")
    GulliToolkit = nil
end)

test("rate, goal and time to the goal", function()
    Fake({ now = 0 })
    local ns = Load()
    ns.AddTarget("item", CLOTH, 100)
    W.now = 1800; W.Loot(CLOTH, 25)
    local i = ns.Info(ns.Targets()[1], 1800)
    eq(i.gained, 25)
    eq(i.rate, 25 * 3600 / ns.IDLE, "30 minutes before the first loot count as a 10 minute break")
    eq(i.pct, 0.25)
    eq(i.eta, math.floor(75 / i.rate * 3600))
    assert(not i.done)
end)

test("a reached goal tells once, with a notice and the hub's feed", function()
    Fake({ now = 0 })
    local notes = {}
    GulliToolkit = { Register = function() end, Notify = function(k, t) notes[#notes + 1] = k .. ": " .. t end }
    local ns = Load()
    local toasts = 0
    ns.OnGoal = function() toasts = toasts + 1 end
    ns.AddTarget("item", CLOTH, 10)
    W.now = 300; W.Loot(CLOTH, 8)
    eq(#notes, 0)
    W.Loot(CLOTH, 4)
    W.Loot(CLOTH, 4)
    eq(#notes, 1)
    eq(toasts, 1)
    assert(notes[1]:find("Item4338", 1, true), notes[1])
    ns.SetPref("alert", false)
    ns.AddTarget("gold", nil, 100)
    W.Money(200)
    eq(#notes, 2, "the feed always gets it")
    eq(toasts, 1, "the switch stops the notice")
end)

test("a /reload keeps the session, a new login starts one; targets stay", function()
    Fake({ now = 0 })
    local ns = Load()
    ns.AddTarget("item", CLOTH)
    W.Loot(CLOTH, 7)
    local db, cdb = GulliFarmTrackDB, GulliFarmTrackCharDB
    Fake({ now = 50, db = db, cdb = cdb, bags = { [CLOTH] = 7 } })
    ns = Load()
    W.Fire("PLAYER_ENTERING_WORLD", false, true)
    eq(ns.s.items[CLOTH], 7)
    W.Fire("PLAYER_LOGOUT")
    W.Fire("PLAYER_ENTERING_WORLD", true, false)
    eq(ns.s.items[CLOTH], 7, "a quick relog keeps the session")
    W.now = W.now + ns.Skin.RELOG_KEEP + 1
    W.Fire("PLAYER_ENTERING_WORLD", true, false)
    eq(ns.s.items[CLOTH], nil)
    eq(#ns.Targets(), 1)
end)

test("slash commands add items by link or id, gold with a goal in gold", function()
    Fake({})
    local ns = Load()
    ns.Slash("add |cffffffff|Hitem:4338::::::::20:::::|h[Mageweave Cloth]|h|r 60")
    eq(ns.Targets()[1].id, CLOTH)
    eq(ns.Targets()[1].goal, 60)
    ns.Slash("add 2772")
    eq(ns.Targets()[2].id, ORE)
    ns.Slash("gold 5")
    eq(ns.Targets()[3].goal, 50000)
    ns.Slash("clear")
    eq(#ns.Targets(), 0)
end)

test("the Farm tab adds an item typed as an id, a link or a name", function()
    Fake({})
    local ns = Load()
    ns.Window():Show()
    local box = W.stub()
    box:SetText("4338")
    eq(ns.AddTyped(box), true)
    eq(ns.Targets()[1].id, CLOTH)
    eq(box:GetText(), "", "the box empties after an add")
    box:SetText("|cffffffff|Hitem:2772::::::::20:::::|h[Iron Ore]|h|r")
    ns.AddTyped(box)
    eq(ns.Targets()[2].id, ORE)
    ns.Slash("clear")
    W.Loot(ORE, 3)
    box:SetText("  item2772 ")
    eq(ns.AddTyped(box), true, "a name of an item in the bags, any case")
    eq(ns.Targets()[1].id, ORE)
    box:SetText("no such thing")
    eq(ns.AddTyped(box), false)
    eq(#ns.Targets(), 1)
    eq(ns.ParseItem(""), nil)
end)

test("the panel shows with a target, or in the Unlock mode to place it", function()
    Fake({})
    local ns = Load()
    eq(ns.db.panel, false, "it starts hidden")
    ns.SetPref("panel", true)
    ns.Refresh()
    local panel = ns.Parts()
    assert(not panel, "no panel without a target")
    ns.Move(true)
    panel = ns.Parts()
    assert(panel and panel:IsShown(), "the Unlock mode shows it")
    eq(rawget(panel, "mover"):IsShown(), true)
    ns.Move(false)
    assert(not panel:IsShown())
    ns.AddTarget("item", CLOTH, 20)
    assert(panel:IsShown())
    ns.SetPref("panel", false)
    assert(not panel:IsShown(), "the switch hides it")
    ns.Move(true)
    assert(panel:IsShown(), "/gulli move shows it")
end)

test("the window draws targets and loot", function()
    Fake({ now = 0 })
    local ns = Load()
    ns.AddTarget("item", CLOTH, 20)
    ns.AddTarget("gold", nil, 10000)
    W.now = 600; W.Loot(CLOTH, 4); W.Loot(ORE, 9); W.Money(1234)
    ns.Window():Show()
    ns.Refresh()
    local rows = ns.LootRows()
    eq(rows[1].kind, "gold")
    eq(rows[2].id, ORE)
    eq(rows[3].id, CLOTH)
    local text = ns.Summary()
    eq(text, "Item4338: 4 of 20, 24/h")
end)

test("the hub gets the module's window and switches", function()
    Fake({})
    local got
    GulliToolkit = { Register = function(m) got = m end }
    local ns = Load()
    eq(got.key, "FarmTrack")
    assert(got.window() == ns.Window())
    eq(#got.options, 4, "the panel's show switch is the hub's, in Frames on screen")
    got.options[1].set(false)
    eq(ns.db.sales, false)
    local fr = got.frames[1]
    eq(fr.key, "panel"); eq(fr.get(), false)
    assert(fr.frame(), "the hub gets the panel")
    fr.set(true)
    eq(ns.db.panel, true)
end)

test("older saves hide the panel once and lose the lock", function()
    Fake({ db = { panel = true, locked = false } })
    local ns = Load()
    eq(ns.db.panel, false); eq(ns.db.locked, nil)
    ns.SetPref("panel", true)
    ns.Reset()
    eq(ns.db.hudHidden, true, "a reset does not hide it again later")
end)

W.finish()
