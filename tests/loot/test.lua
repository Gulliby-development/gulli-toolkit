-- Run from the repository root: lua5.1 tests/loot/test.lua
local W = dofile("tests/loot/wow.lua")
local test, eq = W.test, W.eq

test("every language has every text", function()
    Fake({})
    W.CheckLocales(Load())
end)

test("by default gray is passed and everything else is left to the player", function()
    Fake({ rolls = { { 1, 0 }, { 2, 1 }, { 3, 2 } } })
    Load()
    for i = 1, 3 do W.Fire("START_LOOT_ROLL", i) end
    eq(W.rolled[1], 0)
    eq(W.rolled[2], nil); eq(W.rolled[3], nil)
end)

test("quality rules greed or pass; bind on pickup always stays with the player", function()
    Fake({ rolls = { { 1, 2 }, { 2, 2, true } }, db = { quality = { [2] = "greed" } } })
    Load()
    W.Fire("START_LOOT_ROLL", 1); W.Fire("START_LOOT_ROLL", 2)
    eq(W.rolled[1], 2)
    eq(W.rolled[2], nil)
end)

test("an item rule wins, even on bind on pickup, and its confirmation is answered", function()
    Fake({ rolls = { { 7, 3, true } }, db = { items = { [7] = "need" } } })
    local ns = Load()
    W.Fire("START_LOOT_ROLL", 1)
    eq(W.rolled[1], 1)
    W.Fire("CONFIRM_LOOT_ROLL", 1, 1)
    eq(W.confirmed[1], 1)
    eq(ns.OnConfirm(2, 1), false, "a roll we did not make is not confirmed")
end)

test("need falls back to greed; no greed leaves it to the player", function()
    Fake({ rolls = { { 7, 2, false, false }, { 8, 2, false, false, false } }, db = { items = { [7] = "need", [8] = "greed" } } })
    Load()
    W.Fire("START_LOOT_ROLL", 1); W.Fire("START_LOOT_ROLL", 2)
    eq(W.rolled[1], 2)
    eq(W.rolled[2], nil)
end)

test("protected items are not passed by a quality rule", function()
    Fake({ rolls = { { 9, 0 } } })
    Load()
    GulliToolkit = { IsProtected = function(id) return id == 9 end }
    W.Fire("START_LOOT_ROLL", 1)
    eq(W.rolled[1], nil)
end)

test("dropping an item adds a greed rule", function()
    Fake({})
    local ns = Load()
    ns.Toggle()
    W.cursor = 4306
    for _, fr in ipairs(W.frames) do
        local fn = rawget(fr, "_OnReceiveDrag")
        if fn then fn(fr) end
    end
    eq(ns.db.items[4306], "greed")
    eq(#ns.Items(), 1)
end)

test("every roll goes into the log with its reason, newest first, at most 30, and who won", function()
    Fake({ rolls = { { 1, 0 }, { 2, 2, true }, { 3, 2 } } })
    local ns = Load()
    for i = 1, 3 do W.Fire("START_LOOT_ROLL", i) end
    eq(ns.db.log[1].reason, "ask"); eq(ns.db.log[2].reason, "bop"); eq(ns.db.log[3].reason, "quality")
    eq(ns.db.log[3].rule, "pass")
    local note
    GulliToolkit = { Notify = function(_, text) note = text end }
    W.Fire("CHAT_MSG_LOOT", "You won: |Hitem:3|h[Item]|h")
    eq(ns.db.log[1].winner, "Tester")
    assert(note and note:find("Item"), "the hub's Recent feed gets it")
    W.Fire("CHAT_MSG_LOOT", "Bob won: |Hitem:2|h[Item]|h")
    eq(ns.db.log[2].winner, "Bob")
    GulliToolkit = nil
    for i = 1, 40 do W.rolls[i] = { 100 + i, 0 }; W.Fire("START_LOOT_ROLL", i) end
    eq(#ns.db.log, 30)
end)

test("the main switch and Shift leave a roll to the player", function()
    Fake({ rolls = { { 1, 0 } } })
    local ns = Load()
    W.shift = true
    W.Fire("START_LOOT_ROLL", 1)
    eq(W.rolled[1], nil); eq(ns.db.log[1].reason, "shift")
    W.shift = false
    SlashCmdList.GULLILOOT("off")
    eq(ns.db.on, false)
    W.Fire("START_LOOT_ROLL", 1)
    eq(W.rolled[1], nil); eq(ns.db.log[1].reason, "off")
end)

test("rules by slash command and Alt-click; Ask on an item keeps a quality rule away", function()
    Fake({ rolls = { { 5, 0 } } })
    local ns = Load()
    SlashCmdList.GULLILOOT("ask |cff9d9d9d|Hitem:5::|h[Junk]|h|r")
    eq(ns.db.items[5], "ask")
    W.Fire("START_LOOT_ROLL", 1)
    eq(W.rolled[1], nil, "gray would be passed, but the item says ask")
    SlashCmdList.GULLILOOT("need 6")
    eq(ns.db.items[6], "need")
    ns.OnAltClick("|Hitem:6|h[x]|h")
    eq(ns.db.items[6], "greed", "Alt-click goes to the next rule")
    ns.OnAltClick("|Hitem:7|h[x]|h")
    eq(ns.db.items[7], "greed")
end)

test("type rules, where the rules apply, green you cannot use, upgrades", function()
    Fake({ rolls = { { 10, 2 }, { 11, 2, false, false }, { 12, 2 } },
           items = { [10] = { 9 }, [11] = { 4, "INVTYPE_CHEST", 30 }, [12] = { 4, "INVTYPE_CHEST", 30 } },
           worn = { [5] = 25 } })
    local ns = Load()
    ns.SetType(9, "pass")
    W.Fire("START_LOOT_ROLL", 1)
    eq(W.rolled[1], 0, "recipes: pass"); eq(ns.db.log[1].reason, "type")
    ns.SetPref("where", "raid")
    W.rolled = {}
    W.Fire("START_LOOT_ROLL", 1)
    eq(W.rolled[1], nil, "only in a raid")
    ns.SetPref("where", "always")
    ns.SetPref("greedUnusable", true)
    W.Fire("START_LOOT_ROLL", 2)
    eq(W.rolled[2], 2, "greed on green the class cannot use")
    ns.SetPref("needUpgrade", true)
    W.Fire("START_LOOT_ROLL", 3)
    eq(W.rolled[3], 1, "need: better than what is worn")
    W.worn[5] = 40
    W.rolled = {}
    W.Fire("START_LOOT_ROLL", 3)
    eq(W.rolled[3], nil, "not an upgrade: left to the player")
end)

test("quality and type rules can roll Need, or Need only when the item fits you", function()
    -- 30 a green chest piece, 31 a green chest piece the class cannot need, 32 a recipe.
    Fake({ rolls = { { 30, 2 }, { 31, 2, false, false }, { 32, 2 }, { 30, 2 } },
           items = { [30] = { 4, "INVTYPE_CHEST", 30 }, [31] = { 4, "INVTYPE_CHEST", 30 }, [32] = { 9 } },
           worn = { [5] = 25 } })
    local ns = Load()
    eq(table.concat(ns.RULES, ","), "ask,need,safe,greed,pass")
    ns.db.quality[2] = "need"
    W.Fire("START_LOOT_ROLL", 1); W.Fire("START_LOOT_ROLL", 2)
    eq(W.rolled[1], 1, "plain need"); eq(W.rolled[2], 2, "need not allowed: greed")
    ns.db.quality[2] = "safe"
    W.rolled = {}
    W.Fire("START_LOOT_ROLL", 1)
    eq(W.rolled[1], 1, "an upgrade you can use: need"); eq(ns.db.log[1].reason, "fits")
    W.Fire("START_LOOT_ROLL", 2)
    eq(W.rolled[2], 2, "cannot need: greed"); eq(ns.db.log[1].reason, "nofit")
    W.worn[5] = 40
    W.Fire("START_LOOT_ROLL", 4)
    eq(W.rolled[4], 2, "not better than what you wear: greed")
    ns.SetType(9, "safe")
    W.Fire("START_LOOT_ROLL", 3)
    eq(W.rolled[3], 1, "not gear and you can need it: need"); eq(ns.db.log[1].reason, "fits")
    assert(ns.Test("32"):find("fits you", 1, true), ns.Test("32"))
end)

test("/glt test tells what would happen, and chat lines come as one", function()
    Fake({ rolls = { { 20, 0 }, { 21, 0 } }, items = { [20] = { 15, nil, 5, 0 } } })
    local ns = Load()
    eq(ns.Test("20"), "|Hitem:20|h[Item20]|h: Pass (quality rule).")
    W.Fire("START_LOOT_ROLL", 1); W.Fire("START_LOOT_ROLL", 2)
    eq(#W.printed, 0)
    W.RunTimers()
    eq(#W.printed, 1)
    assert(W.printed[1]:find("Pass on ", 1, true), W.printed[1])
end)

test("fast loot takes every slot; the bind question is answered only alone", function()
    Fake({})
    local ns = Load()
    W.lootN = 3
    W.Fire("LOOT_READY")
    eq(#W.looted, 0, "off by default")
    ns.SetPref("fastLoot", true)
    W.Fire("LOOT_READY")
    eq(#W.looted, 3)
    ns.SetPref("soloConfirm", true)
    W.group = true
    eq(ns.OnBindConfirm(1), false)
    W.group = false
    eq(ns.OnBindConfirm(2), true); eq(W.confirmedSlot, 2)
end)

test("item rules are sorted by name and can be searched; the window has three pages", function()
    Fake({})
    local ns = Load()
    ns.SetItem(30, "greed"); ns.SetItem(4, "pass")
    eq(ns.Items()[1].id, 30, "Item30 before Item4 by name")
    eq(#ns.Items("item4"), 1)
    ns.Toggle()
    ns.Refresh()
end)

test("an item rule shows its name in the quality colour, not a broken colour code", function()
    Fake({ items = { [2907] = { nil, nil, nil, 2 } } })
    ITEM_QUALITY_COLORS = { [2] = { r = 0.12, g = 1, b = 0, hex = "|cff1eff00" } }
    local ns = Load()
    ns.SetItem(2907, "greed")
    eq(ns.ItemLabel(ns.Items()[1]), "|cff1eff00Item2907|r")
    ITEM_QUALITY_COLORS = nil
    eq(ns.ItemLabel(ns.Items()[1]), "|cff1eff00Item2907|r", "the fallback colours too")
end)

test("paused from the hub it rolls nothing", function()
    Fake({ rolls = { { 1, 0 } } })
    local reg
    GulliToolkit = { Register = function(t) reg = t end }
    Load()
    GulliToolkit = nil
    reg.pause(true)
    W.Fire("START_LOOT_ROLL", 1)
    eq(W.rolled[1], nil, "paused")
    reg.pause(false)
    W.Fire("START_LOOT_ROLL", 1)
    eq(W.rolled[1], 0, "started again")
end)

test("the loot window takes what is not locked; its rows skip empty slots", function()
    Fake({ slots = { { "i1", "Coins", 1, 1, false, true }, { "i2", "Ruby", 2, 3, true }, nil, { "i4", "Cloth", 5, 1 } } })
    W.lootN = 4
    local ns = Load()
    local rows = ns.LootRows()
    eq(#rows, 3)
    eq(rows[2].locked, true)
    eq(ns.TakeAll(), 2)
    eq(table.concat(W.looted, ","), "4,1")
end)

test("our window replaces the game's only while the switch is on and the module runs", function()
    Fake({})
    local ns = Load()
    W.Fire("PLAYER_ENTERING_WORLD")
    eq(LootFrame.events.LOOT_OPENED, true, "off by default")
    ns.SetPref("window", true)
    eq(LootFrame.events.LOOT_OPENED, nil)
    ns.paused = true; ns.ApplyWindow()
    eq(LootFrame.events.LOOT_OPENED, true, "paused gives the game's window back")
    ns.paused = false; ns.SetPref("window", false)
    eq(LootFrame.events.LOOT_OPENED, true)
end)

test("the window opens with the loot, closes with it, and shows auto loot for a moment", function()
    Fake({ slots = { { "i1", "Ruby", 1, 3 } }, db = { window = true } })
    W.lootN = 1
    local ns = Load()
    W.Fire("LOOT_OPENED", false)
    local w = ns.LootWindowFrame()
    eq(w:IsShown(), true)
    eq(ns.LootPicked(), false)
    W.Fire("LOOT_CLOSED")
    eq(w:IsShown(), false)
    W.Fire("LOOT_OPENED", true)
    eq(w:IsShown(), true); eq(ns.LootPicked(), true)
    W.RunTimers()
    eq(w:IsShown(), false, "the list of what auto loot took goes away")
    ns.SetPref("window", false)
    W.Fire("LOOT_OPENED", false)
    eq(w:IsShown(), false, "switched off it stays away")
end)

test("loot rolls stay where the game puts them until the player placed them", function()
    Fake({})
    local ns = Load()
    ns.PlaceRolls()
    eq(#GroupLootContainer.points, 0)
    ns.db.rollPoint = { "CENTER", "CENTER", 10, 20 }
    ns.SetPref("rollScale", 120)
    eq(#GroupLootContainer.points, 0, "only with the switch")
    ns.SetPref("rollMove", true)
    eq(GroupLootContainer.scale, 1.2)
    -- the game anchors it again: ours follows
    GroupLootContainer:ClearAllPoints()
    GroupLootContainer:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 100)
    local last = GroupLootContainer.points[#GroupLootContainer.points]
    eq(last[1], "BOTTOM"); eq(last[3], "BOTTOM"); eq(last[2] ~= UIParent, true)
end)

test("the Unlock mode shows a sample window and the roll place, never in combat", function()
    Fake({})
    local ns = Load()
    W.combat = true
    ns.MoveFrames(true)
    eq(ns.LootWindowFrame():IsShown(), false)
    W.combat = false
    ns.MoveFrames(true)
    eq(ns.LootWindowFrame():IsShown(), true)
    eq(ns.RollAnchor():IsShown(), true)
    ns.MoveFrames(false)
    eq(ns.LootWindowFrame():IsShown(), false)
    eq(ns.RollAnchor():IsShown(), false)
end)

test("the hub's Tweaks page gets rows on the window's own saved keys", function()
    Fake({})
    local reg
    GulliToolkit = { Register = function(t) reg = t end }
    local ns = Load()
    GulliToolkit = nil
    local GROUPS = { level = true, quests = true, combat = true, loot = true, people = true, ui = true, requests = true }
    assert(#reg.tweaks >= 3)
    local seen = {}
    for _, o in ipairs(reg.tweaks) do
        assert(GROUPS[o.group], "a group of the page for " .. o.key)
        assert(type(o.label) == "string" and o.icon, "label and icon for " .. o.key)
        assert(not seen[o.key], "one row per key"); seen[o.key] = true
        o.set(true); eq(ns.db[o.key], true, o.key .. " on"); eq(o.get(), true)
        o.set(false); eq(ns.db[o.key], false, o.key .. " off"); eq(o.get(), false)
    end
    assert(seen.fastLoot and seen.window and seen.soloConfirm and seen.feed and seen.rollMove)
end)

test("a roll frame placed before the switch keeps its place", function()
    Fake({ db = { rollPoint = { "CENTER", "CENTER", 0, 0 } } })
    local ns = Load()
    eq(ns.db.rollMove, true)
    Fake({})
    ns = Load()
    eq(ns.db.rollMove, false, "off for a new player")
end)

local LINK = "|cff1eff00|Hitem:7|h[Ruby]|h|r"

test("the loot feed shows what was looted, items and money, and fades away", function()
    Fake({ items = { [7] = { 7, nil, 10, 3 } } })
    local reg
    GulliToolkit = { Register = function(t) reg = t end }
    local ns = Load()
    GulliToolkit = nil
    W.Fire("CHAT_MSG_LOOT", "You receive loot: " .. LINK .. ".")
    eq(#ns.FeedEntries(), 0, "off by default")
    local fr
    for _, x in ipairs(reg.frames) do if x.key == "feed" then fr = x end end
    eq(fr.get(), false)
    fr.set(true)
    eq(ns.db.feed, true)
    -- fast loot: the window opens, money comes in, the loot chat names the items
    W.Fire("LOOT_READY")
    W.money = W.money + 1682
    W.Fire("PLAYER_MONEY")
    W.Fire("CHAT_MSG_LOOT", "You receive loot: " .. LINK .. ".")
    W.Fire("CHAT_MSG_LOOT", "You receive loot: " .. LINK .. "x3.")
    W.Fire("CHAT_MSG_LOOT", "Someone receives loot: " .. LINK .. ".")
    W.Fire("LOOT_CLOSED")
    local e = ns.FeedEntries()
    eq(#e, 2)
    eq(e[1].kind, "item"); eq(e[1].count, 4, "the same item adds up"); eq(e[1].quality, 3); eq(e[1].icon, "icon7")
    eq(e[2].kind, "money"); eq(e[2].copper, 1682)
    eq(ns.FeedFrame():IsShown(), true)
    -- money that does not come from loot is not in it
    W.now = W.now + 10
    W.money = W.money + 500
    W.Fire("PLAYER_MONEY")
    ns.FeedTick()
    eq(#ns.FeedEntries(), 0, "every line goes after a few seconds")
    eq(ns.FeedFrame():IsShown(), false)
end)

test("the loot feed is quiet while paused, safe with secret text, and shows a sample in Unlock mode", function()
    Fake({ db = { feed = true } })
    local ns = Load()
    ns.paused = true
    W.Fire("CHAT_MSG_LOOT", "You receive loot: " .. LINK .. ".")
    eq(#ns.FeedEntries(), 0)
    ns.paused = false
    issecretvalue = function() return true end
    W.Fire("CHAT_MSG_LOOT", "You receive loot: " .. LINK .. ".")
    issecretvalue = nil
    eq(#ns.FeedEntries(), 0)
    ns.MoveFeed(true)
    eq(ns.FeedFrame():IsShown(), true)
    W.now = W.now + 60; ns.FeedTick()
    eq(ns.FeedFrame():IsShown(), true, "the sample stays while placing")
    ns.MoveFeed(false)
    eq(ns.FeedFrame():IsShown(), false)
    ns.SetPref("feed", false)
    W.Fire("CHAT_MSG_LOOT", "You receive loot: " .. LINK .. ".")
    eq(#ns.FeedEntries(), 0)
end)

local function link(id, name) return "|cffffffff|Hitem:" .. id .. "|h[" .. name .. "]|h|r" end
local function loot(id, n) W.Fire("CHAT_MSG_LOOT", "You receive loot: " .. link(id, "Item" .. id) .. (n and ("x" .. n) or "") .. ".") end

-- items: 1 grey junk, 2 cloth (trade goods), 3 green BoE chest, 4 quest item a quest asks for,
-- 5 quest item nobody asks for that a vendor buys, 6 a bound white thing, 10940 strange dust
local FEED_ITEMS = {
    [1] = { 15, nil, 1, 0, 0, 375 }, [2] = { 7, nil, 50, 1, 0, 100 },
    [3] = { 4, "INVTYPE_CHEST", 40, 2, 2, 2000 }, [4] = { 12, nil, 1, 1, 4, 0 },
    [5] = { 12, nil, 1, 1, 4, 250 }, [6] = { 15, nil, 1, 1, 1, 80 },
}

test("a feed line prices its item at a vendor or the auction, whichever pays more", function()
    Fake({ db = { feed = true }, items = FEED_ITEMS })
    local ns = Load()
    local S = ns.Skin
    local prices = { [1] = 9000, [2] = 480, [3] = 18500, [6] = 9000 }
    S.AuctionPrice = function(id) return prices[id] end
    local v, how = ns.FeedValue(1); eq(v, 375); eq(how, "vendor", "grey never goes to the auction")
    v, how = ns.FeedValue(2); eq(v, 480); eq(how, "auction")
    v, how = ns.FeedValue(3); eq(v, 18500); eq(how, "auction")
    v, how = ns.FeedValue(6); eq(v, 80); eq(how, "vendor", "a plain white thing a vendor buys stays there")
    eq(ns.FeedValue(4), nil, "nothing to say about an item worth nothing")
    prices[2] = 60
    v, how = ns.FeedValue(2); eq(v, 100); eq(how, "vendor", "the vendor pays more than the auction")
    S.AuctionPrice = function() error("broken price addon") end
    v, how = ns.FeedValue(2); eq(v, 100, "a failing price addon leaves the vendor price")
    S.AuctionPrice = function() return nil end
    v, how = ns.FeedValue(3); eq(v, 2000); eq(how, "vendor", "without a price addon: the vendor")
    -- an enchanter: green gear as dust when that brings most
    GetProfessions = function() return 1 end
    GetProfessionInfo = function() return "Enchanting", nil, 1, 1, 0, 0, 333 end
    S.AuctionPrice = function(id) if id == 11137 then return 30000 elseif id == 11135 then return 26000 end end
    v, how = ns.FeedValue(3); eq(v, 26000); eq(how, "disenchant")
    GetProfessions, GetProfessionInfo = nil, nil
end)

test("a feed line names the quest, the count in the bags, better gear and a farm goal", function()
    Fake({ db = { feed = true }, items = FEED_ITEMS, worn = { [5] = 30 }, bags = { [2] = 43, [4] = 7 },
           quests = { { 77, "Hope for Hatchlings", { { "7/12 Item4", 7, 12 } } },
                      { 78, "Other", { { "Large Item5: 0/3", 0, 3 } } } } })
    local ns = Load()
    local S = ns.Skin
    S.AuctionPrice = function(id) return ({ [2] = 480, [3] = 18500 })[id] end
    local function facts(id, n) return ns.FeedFacts({ kind = "item", id = id, count = n or 1, name = "Item" .. id, link = link(id, "Item" .. id) }) end
    local f = facts(4)
    eq(f.notes[1].key, "quest"); eq(f.notes[1].right, "7/12")
    assert(f.notes[1].text:find("Hope for Hatchlings", 1, true), "the quest's name")
    eq(f.total, nil, "an item a quest still needs has no price")
    f = facts(5)
    eq(f.notes[1].key, "sell", "the whole name must match: Large Item5 is another item")
    eq(f.total, 250); eq(f.how, "vendor")
    f = facts(2, 3)
    eq(f.total, 1440, "the price of the whole stack"); eq(f.notes[1].key, "bags")
    assert(f.notes[1].text:find("43"))
    f = facts(3)
    eq(f.notes[1].key, "upgrade", "item level 40 over the worn 30")
    C_PlayerInfo = { CanUseItem = function() return false end }
    eq(#facts(3).notes, 0, "gear the class cannot use is no upgrade")
    C_PlayerInfo = nil
    f = facts(1)
    eq(f.notes[1].key, "junk")
    GulliFarmTrackCharDB = { targets = { { kind = "item", id = 2, goal = 60 } }, s = { items = { [2] = 43 } } }
    f = facts(2, 3)
    eq(f.notes[1].key, "goal"); assert(f.notes[1].text:find("43/60", 1, true))
    GulliFarmTrackCharDB = nil
    -- the switches: no price, no notes
    ns.SetPref("feedPrice", false)
    eq(facts(2, 3).total, nil)
    ns.SetPref("feedPrice", true); ns.SetPref("feedNotes", false)
    f = facts(2, 3)
    eq(#f.notes, 0); eq(f.total, 1440)
    -- secret quest text is left alone
    ns.SetPref("feedNotes", true)
    issecretvalue = function(v) return type(v) == "string" and v:find("Hatchlings") ~= nil end
    eq(facts(4).notes[1].key, "questitem")
    issecretvalue = nil
end)

test("the feed's two looks: a second line only when there is a note, a total of the lines", function()
    Fake({ db = { feed = true }, items = FEED_ITEMS, bags = { [2] = 43 },
           quests = { { 77, "Hope for Hatchlings", { { "7/12 Item4", 7, 12 } } } } })
    local ns = Load()
    ns.Skin.AuctionPrice = function(id) return ({ [2] = 480 })[id] end
    eq(ns.db.feedCompact, false, "detailed by default")
    loot(2, 3); loot(4); loot(1)
    local e = ns.FeedEntries()
    local junk, quest, cloth = ns.FeedLine(e[1]), ns.FeedLine(e[2]), ns.FeedLine(e[3])
    assert(cloth.right:find("14s") and cloth.right:find("40c"), "the stack's price")
    eq(cloth.src, "auction"); assert(cloth.note:find("43"))
    eq(quest.src, nil); assert(quest.right:find("7/12")); assert(quest.note:find("Hope for Hatchlings", 1, true))
    eq(junk.src, "vendor")
    local total, parts = ns.FeedTotal()
    eq(total, 1440 + 375); eq(parts, 2, "the quest item adds nothing")
    -- the bags changed: the count is read again, not on every frame
    local reads = 0
    local count = C_Item.GetItemCount
    C_Item.GetItemCount = function(id) reads = reads + 1; return count(id) end
    ns.FeedTick(); ns.FeedTick()
    eq(reads, 0, "nothing is read again while nothing changed")
    W.bags[2] = 46
    W.now = W.now + 1
    W.Fire("BAG_UPDATE_DELAYED")
    ns.FeedTick()
    assert(ns.FeedLine(e[3]).note:find("46"), "the new count after the bags changed")
    -- compact: one line, the quest's count on the right, no second line
    ns.SetPref("feedCompact", true)
    e = ns.FeedEntries()
    quest, cloth = ns.FeedLine(e[2]), ns.FeedLine(e[3])
    eq(cloth.note, nil); eq(quest.note, nil)
    assert(quest.right:find("7/12") and quest.right:find("Quest", 1, true))
    assert(cloth.right:find("14s"))
    -- an item without anything to say stays one line in the detailed look
    ns.SetPref("feedCompact", false)
    ns.SetPref("feedNotes", false); ns.SetPref("feedPrice", false)
    eq(ns.FeedLine(ns.FeedEntries()[3]).note, nil)
    local _, n = ns.FeedTotal()
    eq(n, 0)
    -- paused: nothing new comes in
    ns.FeedClear(); ns.paused = true
    loot(2)
    eq(#ns.FeedEntries(), 0)
end)

local function rollStrings()
    LOOT_ROLL_NEED = "%s has selected Need for: %s"
    LOOT_ROLL_GREED = "%s has selected Greed for: %s"
    LOOT_ROLL_PASSED = "%s passed on: %s"
    LOOT_ROLL_PASSED_AUTO = "%s automatically passed on: %s because he cannot loot that item."
    LOOT_ROLL_NEED_SELF = "You have selected Need for: %s"
    LOOT_ROLL_PASSED_SELF = "You passed on: %s"
    LOOT_ROLL_ROLLED_NEED = "Need Roll - %d for %s by %s"
end

local function lootFrame(i, rollID)
    local f = W.stub()
    rawset(f, "rollID", rollID)
    f:Show()
    rawset(f, "IsMouseOver", function() return rawget(f, "_over") == true end)
    _G["GroupLootFrame" .. i] = f
    return f
end

test("who rolled what: off by default, then the chat choices of the group under the roll frame", function()
    Fake({ rolls = { { 7, 2 } } })
    rollStrings()
    local ns = Load()
    eq(ns.db.rollers, false, "off by default")
    lootFrame(1, 1)
    W.Fire("START_LOOT_ROLL", 1)
    eq(ns.RollersFrame():IsShown(), false, "nothing shows while off")
    ns.SetPref("rollers", true)
    W.Fire("START_LOOT_ROLL", 1)
    local item = "|Hitem:7|h[Item]|h"
    W.Fire("CHAT_MSG_LOOT", "Bob has selected Greed for: " .. item)
    W.Fire("CHAT_MSG_LOOT", "Ann has selected Need for: " .. item)
    W.Fire("CHAT_MSG_LOOT", "Cid automatically passed on: " .. item .. " because he cannot loot that item.")
    W.Fire("CHAT_MSG_LOOT", "Bob has selected Need for: |Hitem:99|h[Other]|h")
    local r, list, counts = ns.RollersPaint()
    eq(ns.RollersFrame():IsShown(), true)
    eq(#list, 4, "three choices and the player still waiting")
    eq(list[1].name, "Ann"); eq(list[1].choice, "need")
    eq(list[2].name, "Bob"); eq(list[3].choice, "pass")
    eq(list[4].name, "Tester"); eq(list[4].choice, "wait"); eq(list[4].self, true)
    eq(counts.need, 1); eq(counts.greed, 1); eq(counts.pass, 1); eq(counts.wait, 1)
    W.Fire("CHAT_MSG_LOOT", "You have selected Need for: " .. item)
    W.Fire("CHAT_MSG_LOOT", "Need Roll - 87 for " .. item .. " by Ann")
    r, list, counts = ns.RollersPaint()
    eq(counts.need, 2); eq(counts.wait, 0)
    eq(r.by.Ann.roll, 87, "the roll number shows once known")
    -- a secret line is left alone, and the roll's end hides the panel
    issecretvalue = function(v) return v == "secret" end
    eq(ns.RollerChat("secret"), nil)
    issecretvalue = nil
    GroupLootFrame1:Hide()
    ns.RollersPaint()
    eq(ns.RollersFrame():IsShown(), false)
    ns.paused = true
    GroupLootFrame1:Show()
    ns.RollersPaint()
    eq(ns.RollersFrame():IsShown(), false, "paused from the hub")
    GroupLootFrame1 = nil
end)

test("who rolled what: the loot history gives the class, Main or Off spec and those still waiting", function()
    Fake({ rolls = { { 7, 2 }, { 7, 2 } }, db = { rollers = true } })
    rollStrings()
    Enum = { EncounterLootDropRollState = { NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, NoRoll = 4, Pass = 5 } }
    C_LootHistory = { GetSortedInfoForDrop = function(enc, key)
        return { itemHyperlink = "|Hitem:7|h[Item]|h", rollInfos = {
            { playerName = "Ann", playerClass = "WARRIOR", state = 1 },
            { playerName = "Bob", playerClass = "PALADIN", state = 0 },
            { playerName = "Tester", playerClass = "PRIEST", state = 4, isSelf = true },
            { playerName = "Cid", playerClass = "MAGE", state = 5 },
        } }
    end }
    local ns = Load()
    lootFrame(1, 1)
    local f2 = lootFrame(2, 2)
    W.Fire("START_LOOT_ROLL", 1)
    W.now = W.now + 1
    W.Fire("START_LOOT_ROLL", 2)
    W.Fire("LOOT_HISTORY_UPDATE_DROP", 5, 1)
    eq(ns.RollerData(1).drop, "5:1", "the history drop goes to the older roll of the same item")
    local _, list, counts = ns.RollersPaint()
    eq(list[1].name, "Bob"); eq(list[1].spec, "main", "Main spec before Off spec")
    eq(list[2].name, "Ann"); eq(list[2].spec, "off"); eq(list[2].class, "WARRIOR")
    eq(list[3].choice, "pass"); eq(list[4].choice, "wait")
    eq(counts.need, 2); eq(counts.pass, 1)
    -- the mouse on the second roll frame shows that roll
    rawset(f2, "_over", true)
    local r = ns.RollersPaint()
    eq(r, ns.RollerData(2))
    -- chat for the same item goes to the roll that lacks that name
    W.Fire("CHAT_MSG_LOOT", "Ann has selected Greed for: |Hitem:7|h[Item]|h")
    eq(ns.RollerData(2).by.Ann.choice, "greed")
    eq(ns.RollerData(1).by.Ann.choice, "need")
    -- Unlock mode shows a sample under the roll anchor
    GroupLootFrame1, GroupLootFrame2 = nil, nil
    ns.MoveRollers(true)
    eq(ns.RollersFrame():IsShown(), true)
    ns.MoveRollers(false)
    eq(ns.RollersFrame():IsShown(), false)
    C_LootHistory, Enum = nil, nil
end)

test("a format with numbered arguments is read in its own order", function()
    Fake({})
    local ns = Load()
    local pat, order = ns.CompileFormat("%2$s : %1$s a choisi Besoin")
    local a, b = ("[Item] : Bob a choisi Besoin"):match(pat)
    eq(a, "[Item]"); eq(b, "Bob"); eq(order[1], 2); eq(order[2], 1)
end)

local function realWorld(spec)
    Fake(spec)
    GulliLootCharDB = spec.cdb
    W.real = { qty = spec.qty or 10, max = spec.max or 250 }
    C_CurrencyInfo = { GetCurrencyInfo = function(id)
        if id ~= 3469 then return nil end
        return { name = "Tarnished Undermine Real", quantity = W.real.qty, maxQuantity = W.real.max, iconFileID = 7 }
    end }
    C_DateAndTime = { GetSecondsUntilDailyReset = function() return 3600 end }
    W.inst = spec.inst or { "Scholomance", "party", 1, "Normal", 5, 0, false, 289 }
    GetInstanceInfo = function() return unpack(W.inst) end
    W.bossLevel = spec.bossLevel or 61
    UnitExists = function(u) return u == "boss1" end
    UnitCanAttack = function() return true end
    UnitLevel = function(u) if u == "player" then return W.level end return W.bossLevel end
end

local function kill(id)
    W.Fire("ENCOUNTER_START", id, "Boss", 1, 5)
    W.RunTimers()
    W.Fire("ENCOUNTER_END", id, "Boss", 1, 5, 1)
end

local function gain(n)
    W.real.qty = W.real.qty + n
    W.Fire("CURRENCY_DISPLAY_UPDATE", 3469, W.real.qty, n)
end

test("after a boss that drops a Real, an icon shows until it is looted", function()
    realWorld({ db = {} })
    local reg
    GulliToolkit = { Register = function(t) reg = t end }
    local ns = Load()
    GulliToolkit = nil
    kill(101)
    eq(#ns.RealPending(), 0, "off by default")
    local fr
    for _, x in ipairs(reg.frames) do if x.key == "real" then fr = x end end
    eq(fr.get(), false)
    fr.set(true)
    eq(ns.db.real, true)
    W.Fire("PLAYER_ENTERING_WORLD")
    kill(101)
    eq(#ns.RealPending(), 1)
    eq(ns.RealFrame():IsShown(), true)
    W.Fire("CURRENCY_DISPLAY_UPDATE", 1, 5, 5)
    eq(ns.RealFrame():IsShown(), true, "another currency changes nothing")
    gain(1)
    eq(#ns.RealPending(), 0)
    eq(ns.RealFrame():IsShown(), false, "looted: the icon goes")
    eq(ns.RealLootedToday(101), true)
    kill(101)
    eq(#ns.RealPending(), 0, "a boss looted today is skipped")
    kill(102)
    eq(#ns.RealPending(), 1, "another boss still counts")
    W.now = W.now + ns.REAL_WAIT + 1
    ns.RealPaint()
    eq(ns.RealFrame():IsShown(), false, "it goes when no Real came")
    W.now = W.now + 3600
    eq(ns.RealLootedToday(101), false, "a new day after the daily reset")
end)

test("the Real reminder stays quiet below 60, at the cap, for low bosses and outside its dungeons", function()
    realWorld({ db = { real = true }, level = 59 })
    local ns = Load()
    kill(1); eq(#ns.RealPending(), 0, "below level 60")
    W.level = 60
    W.real.qty = 250
    kill(1); eq(#ns.RealPending(), 0, "at the cap")
    W.real.qty, W.real.max = 250, 0
    kill(1); eq(#ns.RealPending(), 0, "the cap of 250 when the game names none")
    W.real.qty = 10
    W.bossLevel = 50
    kill(1); eq(#ns.RealPending(), 0, "a boss below 55")
    W.bossLevel = -1
    kill(1); eq(#ns.RealPending(), 1, "a skull counts")
    ns.RealClear()
    W.inst = { "Zul'Farrak", "party", 1, "Normal", 5, 0, false, 209 }
    kill(2); eq(#ns.RealPending(), 0, "a dungeon without Reals")
    W.inst = { "Blackmaw Hold", "party", 1, "Normal", 5, 0, false, 9001 }
    kill(3); eq(#ns.RealPending(), 1, "WoW Forever's own dungeon by name")
    gain(1)
    eq(ns.db.realLearned[9001], true, "its id is learned with the Real")
    W.Fire("ENCOUNTER_END", 4, "Boss", 1, 5, 0)
    eq(#ns.RealPending(), 0, "a wipe is no kill")
    issecretvalue = function() return true end
    W.inst = { "Scholomance", "party", 1, "Normal", 5, 0, false, 289 }
    kill(5)
    issecretvalue = nil
    eq(#ns.RealPending(), 1, "secret values are left alone: it still reminds")
    ns.RealClear()
    ns.paused = true
    kill(6); eq(#ns.RealPending(), 0, "paused")
    ns.paused = false
    ns.MoveReal(true)
    eq(ns.RealFrame():IsShown(), true, "Unlock mode shows it to place")
    ns.MoveReal(false)
    eq(ns.RealFrame():IsShown(), false)
end)

W.finish()
