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

W.finish()
