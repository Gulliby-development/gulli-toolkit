-- Run from the repository root: lua5.1 tests/tooltip/test.lua
local W = dofile("tests/tooltip/wow.lua")
local test, eq = W.test, W.eq

local LOG = {
    { 100, "Wolves", objectives = { { type = "item", text = "Wolf Pelt: 3/10", numFulfilled = 3, numRequired = 10 } } },
    { 101, "Kill boars", objectives = { { type = "monster", text = "Boar slain: 1/5", numFulfilled = 1, numRequired = 5 } } },
    { 102, "Done", objectives = { { type = "item", text = "Wolf Pelt: 5/5", numFulfilled = 5, numRequired = 5, finished = true } } },
}

test("every language has every text", function()
    Fake({})
    W.CheckLocales(Load())
end)

test("a stack item shows the full stack price; a single item does not", function()
    Fake({ items = { [1] = { "Linen", 20, 13 }, [2] = { "Sword", 1, 500 } } })
    Load()
    eq(W.HoverItem(1)[1], "Vendor ×20=2s 60c")
    eq(#W.HoverItem(2), 0)
end)

test("an item a quest still needs shows the quest and the count", function()
    Fake({ items = { [7] = { "Wolf Pelt", 20, 0 } }, log = LOG })
    Load()
    local lines = W.HoverItem(7)
    eq(#lines, 1)
    eq(lines[1], "Wolves=3/10")
end)

test("the quest lines follow the log", function()
    Fake({ items = { [7] = { "Wolf Pelt", 20, 0 } }, log = LOG })
    Load()
    eq(#W.HoverItem(7), 1)
    W.log = {}
    W.Fire("QUEST_LOG_UPDATE")
    eq(#W.HoverItem(7), 0)
end)

test("ids on items and NPCs only when switched on", function()
    Fake({ items = { [2] = { "Sword", 1, 500 } } })
    local ns = Load()
    eq(#W.HoverUnit("Creature-0-1-2-3-299-0000"), 0)
    ns.db.id = true
    eq(W.HoverItem(2)[1], "ID 2=")
    eq(W.HoverUnit("Creature-0-1-2-3-299-0000")[1], "ID 299=")
    eq(W.HoverSpell(17)[1], "ID 17=")
    eq(#W.HoverUnit("Player-1-00000001"), 0)
    issecretvalue = function() return true end
    eq(#W.HoverUnit("Creature-0-1-2-3-299-0000"), 0, "a secret guid is skipped")
    eq(#W.HoverItem(2), 0, "a secret item id is skipped")
    ns.Toggle()
end)

test("an NPC gets no quest line: the game shows its kill objectives", function()
    Fake({ log = LOG })
    Load()
    eq(#W.HoverUnit("Creature-0-1-2-3-113-0000", "Boar"), 0)
end)

test("the count turns green with a check mark once the bags hold enough", function()
    Fake({ items = { [7] = { "Wolf Pelt", 20, 0 } }, log = LOG })
    local ns = Load()
    local S = ns.Skin
    local l = ns.ItemLines(7)[1]
    eq(l.rcolor, S.TEXT, "3/10 stays plain")
    eq(l.icon ~= nil, true, "the quest mark")
    ns.QuestNeeds("Wolf Pelt")[1].have = 10
    l = ns.ItemLines(7)[1]
    eq(l.rcolor, S.GOOD, "10/10 is green")
    eq(l.right:find("ReadyCheck", 1, true) ~= nil, true, "and not by colour alone")
end)

test("the whole name must match: Wolf Pelt is not Large Wolf Pelt", function()
    Fake({ items = { [7] = { "Wolf Pelt", 20, 0 }, [8] = { "Large Wolf Pelt", 20, 0 } }, log = {
        { 100, "Wolves", objectives = { { type = "item", text = "Large Wolf Pelt: 1/4", numFulfilled = 1, numRequired = 4 } } },
    } })
    Load()
    eq(#W.HoverItem(7), 0)
    eq(W.HoverItem(8)[1], "Wolves=1/4")
end)

test("a count in front of the name is read too", function()
    Fake({})
    local ns = Load()
    eq(ns.ObjectiveName("3/10 Wolf Pelt"), "Wolf Pelt")
    eq(ns.ObjectiveName("Wolf Pelt: 3/10"), "Wolf Pelt")
end)

test("a protected item says so, only with the core and the switch", function()
    Fake({ items = { [2] = { "Sword", 1, 500 } } })
    local ns = Load()
    eq(#W.HoverItem(2), 0)
    GulliToolkit = { IsProtected = function(id) return id == 2 end }
    eq(W.HoverItem(2)[1], "Protected=")
    ns.db.protect = false
    eq(#W.HoverItem(2), 0)
end)

test("the auction price comes from Auctionator when it is there", function()
    Fake({ items = { [2] = { "Sword", 1, 500 } } })
    local ns = Load()
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(caller, id)
        assert(caller == "Gulli-Tooltip"); return id == 2 and 12345 or nil end } } }
    eq(#W.HoverItem(2), 0, "off by default: Auctionator shows its own line")
    ns.db.auction = true
    eq(W.HoverItem(2)[1], "Auction=1g 23s 45c")
    eq(#W.HoverItem(2), 1, "the auction pays more: no hint")
    ns.db.auction = false
    eq(#W.HoverItem(2), 0)
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() error("broken") end } } }
    ns.db.auction = true
    eq(#W.HoverItem(2), 0, "an error in Auctionator shows nothing")
    Auctionator = nil
end)

test("a vendor that pays more than the auction after its cut is named", function()
    Fake({ items = { [1] = { "Linen", 20, 100 } }, db = { price = false, auction = true, defaultsV = 2 } })
    Load()
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() return 104 end } } }
    local lines = W.HoverItem(1)
    eq(lines[1], "Auction ×20=20s 80c")
    eq(lines[2], "After the cut a vendor pays more=", "104 less 5% is under 100")
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() return 106 end } } }
    eq(#W.HoverItem(1), 1, "106 less 5% still beats the vendor")
    Auctionator = nil
end)

test("who holds the item: you from the game, the others from Gulli Chores", function()
    Fake({ items = { [7] = { "Wolf Pelt", 20, 0 }, [2] = { "Sword", 1, 500 } } })
    Load()
    eq(#W.HoverItem(7), 0, "none anywhere, no lines")
    W.counts[7] = { 4, 6 }
    GulliChoresDB = { chars = {
        ["Tester-Realm"] = { name = "Tester", items = { [7] = 99 }, bank = { [7] = 99 } },
        ["Alt-Realm"] = { name = "Alt", items = { [7] = 3 }, bank = { [7] = 2 } },
        ["Bob-Realm"] = { name = "Bob", items = { [7] = 1 } },
        ["Vault-Realm"] = { name = "Vault", bank = { [7] = 8 } },
        ["Empty-Realm"] = { name = "Empty", items = {} },
    } }
    local lines = W.HoverItem(7)
    eq(#lines, 5)
    eq(lines[1], "You have=24", "a total first; this character is counted by the game, not twice")
    eq(lines[2], "Tester=4 · bank 6")
    eq(lines[3], "Vault=bank 8", "the others by how many they hold")
    eq(lines[4], "Alt=3 · bank 2")
    eq(lines[5], "Bob=1")
    -- the game gives no realm name: this character is still not one of the others
    local realmName = GetRealmName
    GetRealmName = function() return "" end
    GulliChoresDB.realm = "Realm"
    GulliChoresDB.chars["Tester-"] = { name = "Tester", items = { [7] = 50 } }
    eq(#W.HoverItem(7), 5)
    GetRealmName = realmName
    GulliChoresDB = nil
    lines = W.HoverItem(7)
    eq(lines[1], "You have=10")
    eq(lines[2], "Tester=4 · bank 6")
    W.counts[7] = { 4, 0 }
    lines = W.HoverItem(7)
    eq(#lines, 1, "only the bags: the total says it all")
    eq(lines[1], "You have=4")
    W.counts[2] = { 1, 0 }
    eq(#W.HoverItem(2), 0, "one sword in the bags is no news")
end)

test("more than four holders end in a count", function()
    Fake({ items = { [7] = { "Wolf Pelt", 20, 0 } } })
    Load()
    local chars = {}
    for i = 1, 6 do chars["A" .. i .. "-Realm"] = { name = "A" .. i, items = { [7] = i } } end
    GulliChoresDB = { chars = chars }
    local lines = W.HoverItem(7)
    eq(#lines, 6)
    eq(lines[2], "A6=6")
    eq(lines[6], "and 2 more=")
    GulliChoresDB = nil
end)

test("a reagent of a learned recipe names the profession with its icon", function()
    Fake({ items = { [7] = { "Wolf Pelt", 20, 0 } } })
    local ns = Load()
    eq(ns.db.reagent, false, "off by default: the game says Crafting Reagent")
    ns.db.reagent = true
    GulliCraftProfitCharDB = { profs = {
        Leatherworking = { icon = "Interface\\Icons\\Trade_LeatherWorking", recipes = { { learned = true, r = { [7] = 2 } } } },
        Tailoring = { recipes = { { learned = false, r = { [7] = 1 } } } },
    } }
    eq(W.HoverItem(7)[1], "Leatherworking=")
    eq(ns.ItemLines(7)[1].icon, "Interface\\Icons\\Trade_LeatherWorking")
    GulliCraftProfitCharDB = nil
end)

test("where an item drops comes from the Dungeon Journal", function()
    Fake({ items = { [9] = { "Blade", 1, 500 }, [10] = { "Ring", 1, 500 } } })
    local ns = Load()
    eq(#W.HoverItem(9), 0, "no journal, no lines")
    GulliDungeonJournal = {
        DropsOf = function(id) return id == 9 and { { key = "MARA", boss = "Princess", pct = 12.5 }, { key = "X", boss = "Other", pct = 1 } } or {} end,
        Name = function(key) return key == "MARA" and "Maraudon" or nil end,
        Wished = function(id) return id == 9 or id == 10 end,
    }
    local lines = W.HoverItem(9)
    eq(lines[1], "Princess=12.5%", "the best chance")
    eq(lines[2], "Maraudon · on your wish list=")
    eq(W.HoverItem(10)[1], "On your wish list=", "a wish the bosses do not drop")
    GulliDungeonJournal = { DropsOf = function() return { { key = "MARA", boss = "Princess", pct = 0 } } end }
    lines = W.HoverItem(9)
    eq(#lines, 1, "an older journal gives no name and no wish")
    eq(lines[1], "Princess=")
    GulliDungeonJournal = { DropsOf = function() error("broken") end }
    eq(#W.HoverItem(9), 0, "an error in the journal shows nothing")
    ns.db.drops = false
    GulliDungeonJournal = { DropsOf = function() return { { key = "MARA", boss = "Princess", pct = 3 } } end }
    eq(#W.HoverItem(9), 0, "the switch stops it")
    GulliDungeonJournal = nil
end)

test("the lines stand in the block's order, whatever is on", function()
    Fake({ items = { [7] = { "Wolf Pelt", 20, 5 } }, log = LOG, db = { id = true, auction = true, reagent = true, defaultsV = 2 } })
    Load()
    GulliToolkit = { IsProtected = function() return true end }
    W.counts[7] = { 3, 0 }
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() return 50 end } } }
    GulliCraftProfitCharDB = { profs = { Skinning = { recipes = { { learned = true, r = { [7] = 1 } } } } } }
    GulliDungeonJournal = { DropsOf = function() return { { key = "K", boss = "Boss", pct = 2 } } end }
    local lines = W.HoverItem(7)
    local want = { "Protected=", "Wolves=3/10", "You have=3", "Vendor ×20=1s", "Auction ×20=10s", "Skinning=", "Boss=2%", "ID 7=" }
    for i, w in ipairs(want) do eq(lines[i], w) end
    eq(#lines, #want)
    eq(W.rules[1], "gold", "one gold line over the block")
    eq(#W.rules, 6, "a faint line over each further group but the id")
    for i = 2, #W.rules do eq(W.rules[i], "faint") end
    Auctionator, GulliCraftProfitCharDB, GulliDungeonJournal = nil, nil, nil
end)

test("with Shift mode prices and ids wait for Shift", function()
    Fake({ items = { [1] = { "Linen", 20, 13 } } })
    local ns = Load()
    ns.db.id, ns.db.shift = true, true
    local down = false
    IsShiftKeyDown = function() return down end
    eq(#W.HoverItem(1), 0)
    down = true
    eq(#W.HoverItem(1), 2)
    IsShiftKeyDown = nil
end)

test("spell ids under the id switch", function()
    Fake({})
    local ns = Load()
    eq(#W.HoverSpell(139), 0)
    ns.db.id = true
    eq(W.HoverSpell(139)[1], "ID 139=")
end)

test("summary, reset and the hub options", function()
    Fake({})
    local reg
    GulliToolkit = { Register = function(info) reg = info end }
    local ns = Load()
    eq(reg.key, "Tooltip")
    eq(#reg.options, 6)
    eq(reg.summary(), "5 of 8 tooltip lines on")
    reg.options[1].set(false)
    eq(ns.db.protect, false)
    eq(reg.summary(), "4 of 8 tooltip lines on")
    reg.reset()
    eq(ns.db.protect, true)
    for _, k in ipairs(ns.LINES) do
        assert(ns.DEFAULTS[k] ~= nil, k .. " has no default")
        assert(ns.OPT_ICON[k], k .. " has no icon")
        assert(ns.L["OPT_" .. k:upper()] and ns.L["TIP_" .. k:upper()], k .. " has no texts")
    end
end)

test("the window builds and the example follows the switches", function()
    Fake({})
    local ns = Load()
    local f = ns.Window()
    assert(f, "no window")
    f:Show()
    ns.Refresh()
    local n = #ns.ExampleLines()
    ns.Set("id", true)
    eq(#ns.ExampleLines(), n + 4, "the item's id, and the NPC with its id")
    ns.Set("shift", true)
    eq(ns.ExampleLines()[#ns.ExampleLines()].note, true, "the Shift note")
    for _, k in ipairs(ns.LINES) do ns.Set(k, false) end
    eq(#ns.ExampleLines(), 1, "all off: only the item's name")
    ns.Toggle()
end)

test("without a price addon the auction switch is off and grey; the choice comes back with one", function()
    Fake({})
    local ns = Load()
    Auctionator = nil
    ns.db.auction = true
    local f = ns.Window()
    f:Show()
    ns.Refresh()
    local r
    for _, x in ipairs(f.rows) do if x.key == "auction" then r = x end end
    eq(r:GetChecked(), false, "shows off")
    eq(r.switch:IsEnabled(), false, "grey")
    eq(ns.db.auction, true, "the player's choice stays")
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() return nil end } } }
    ns.Refresh()
    eq(r:GetChecked(), true, "on again with a price addon")
    eq(r.switch:IsEnabled(), true)
    Auctionator = nil
    ns.Toggle()
end)

test("the auction line gives a full stack for stack items", function()
    Fake({ items = { [1] = { "Linen", 20, 13 } } })
    local ns = Load()
    ns.db.auction, ns.db.price = true, false
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() return 13 end } } }
    eq(W.HoverItem(1)[1], "Auction ×20=2s 60c")
    Auctionator = nil
end)

test("new defaults reach saved settings once, then the player's choice stays", function()
    Fake({ items = {}, db = { price = true, auction = true, reagent = true, quest = true } })
    local ns = Load()
    eq(ns.db.auction, false); eq(ns.db.reagent, false); eq(ns.db.price, true)
    eq(ns.db.defaultsV, ns.DEFAULTS_V)
    ns.db.auction = true
    ns.Migrate(ns.db)
    eq(ns.db.auction, true, "a choice made after the change stays")
    eq(ns.db.drops, true, "a new line comes with its default")
    ns.db.mobs = true
    ns.Migrate(ns.db)
    eq(ns.db.mobs, nil, "the removed line's switch is dropped")
end)

test("the lines of several modules make one block, in the groups' order", function()
    Fake({ items = { [7] = { "Wolf Pelt", 20, 5 } }, log = LOG })
    local ns = Load()
    local S = ns.Skin
    S.TipProvider("item", "PartyQuests", function() return { { group = "quest", sub = true, icon = "q", left = "Bob", right = "2/8" } } end)
    S.TipProvider("item", "QuestCleaner", function()
        return { { group = "quest", sub = true, left = "Needed for Wolves", unless = "quest" },
                 { group = "state", left = "Always kept" } }
    end)
    S.TipProvider("item", "Broken", function() error("boom") end)
    S.TipProvider("item", "Zeta", function(id, tt) return { { left = "note " .. id .. (tt and "" or "?") } } end)
    local lines = W.HoverItem(7)
    local want = { "Always kept=", "Wolves=3/10", "Bob=2/8", "Vendor ×20=1s", "note 7=" }
    for i, w in ipairs(want) do eq(lines[i], w) end
    eq(#lines, #want, "the repeat of the quest line is left out; a broken module costs only its own lines")
    ns.db.quest = false
    lines = W.HoverItem(7)
    eq(lines[2], "Needed for Wolves=", "without the quest's own line the other module's line comes back")
    eq(lines[3], "Bob=2/8", "and the group still stands")
    local drawn = {}
    local tip = { AddDoubleLine = function(_, a) drawn[#drawn + 1] = a end, AddLine = function(_, a) drawn[#drawn + 1] = a end }
    S.TipDraw(tip, { { group = "quest", sub = true, icon = "Interface\\Icons\\X", left = "A" },
                     { group = "quest", sub = true, icon = "Interface\\Icons\\X", left = "B" } })
    assert(drawn[1]:find("Icons\\X", 1, true), "a line that leads its group shows its icon")
    assert(not drawn[2]:find("Icons\\X", 1, true) and drawn[2]:find("|T", 1, true), "the next stands under it")
    eq(S.TipDraw({ IsForbidden = function() return true end }, {}), 0)
    eq(S.Cap("junk"), "Junk"); eq(S.Cap("хлам"), "Хлам"); eq(S.Cap(""), "")
    for i, g in ipairs(S.TIP_GROUPS) do assert(type(g) == "string" and i, "a group key") end
end)

W.finish()
