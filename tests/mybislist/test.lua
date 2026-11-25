-- Run from the repository root: lua5.1 tests/mybislist/test.lua
local W = dofile("tests/mybislist/wow.lua")
local test, eq = W.test, W.eq

-- Small lists of our own on WARRIOR_ARMS L40, so the rules do not hang on the weekly data.
-- Items: 1xx head, 2xx rings, 3xx main hand, 4xx off hand. 102 is Horde only, 301 a two-hander.
local function fakeData(ns, mainTwoHand)
    local D = ns.Data
    local function it(slot, side) return { slot, 3, 30, 30, 1, side, "Item" } end
    D.item[101], D.item[102], D.item[103] = it("head"), it("head", "H"), it("head")
    D.item[201], D.item[202], D.item[203] = it("finger"), it("finger"), it("finger")
    D.item[301], D.item[302], D.item[401] = it(mainTwoHand and "2h" or "mh"), it("mh"), it("oh")
    D.lists.WARRIOR_ARMS.L40 = { head = { 101, 102, 103 }, finger1 = { 201, 202 }, finger2 = { 202, 203 },
                                 main = { 301, 302 }, off = { 401 } }
    D.ench.WARRIOR_ARMS = {}
    D.src[1] = { "boss", "Boss", "SM" }
end
local REF = "site:WARRIOR_ARMS:L40"
local function row(rows, slot) for _, r in ipairs(rows) do if r.slot == slot then return r end end end

test("every language has every text", function()
    Fake({})
    W.CheckLocales(Load())
end)

test("the data: every spec has every stage, at most five known items a slot, and its texts", function()
    Fake({})
    local ns = Load()
    local D = ns.Data
    eq(#D.specs, 30, "specs")
    assert(ns.SpecName("HUNTER_SURVIVALMELEE") and ns.SpecName("PALADIN_SHOCKADIN"), "the specs wowtbc.gg added")
    for _, s in ipairs(D.specs) do
        assert(ns.SpecName(s[1]), "no name for " .. s[1])
        assert(ns.ROLE_ICON[s[3]], "no role icon for " .. s[1])
        assert(ns.SPEC_ICON[s[1]], "no spec icon for " .. s[1])
        for _, stage in ipairs(D.stages) do
            local l = D.lists[s[1]] and D.lists[s[1]][stage]
            assert(l, s[1] .. " has no " .. stage)
            assert(ns.StageName(stage), "no name for " .. stage)
            for slot, ids in pairs(l) do
                assert(ns.INV[slot], "unknown slot " .. slot)
                assert(#ids <= 5, s[1] .. " " .. stage .. " " .. slot .. " has more than five")
                for _, id in ipairs(ids) do
                    local item = D.item[id]
                    assert(item, "unknown item " .. id)
                    assert(D.src[item[5]], "item " .. id .. " has no source")
                end
            end
        end
    end
    for class, tabs in pairs(ns.TABS) do
        for _, key in ipairs(tabs) do assert(ns.SpecInfo(key)[2] == class, key) end
    end
    for _, slot in ipairs(D.slots) do assert(ns.L["SLOT_" .. slot], "no text for slot " .. slot) end
    for _, src in ipairs(D.src) do assert(ns.SRC_ICON[src[1]], "no icon for source " .. src[1]) end
end)

test("the data: every enchant has a spell, a name, a known kind and a slot", function()
    Fake({})
    local ns = Load()
    local n = 0
    for spec, stages in pairs(ns.Data.ench) do
        assert(ns.SpecInfo(spec), "unknown spec " .. spec)
        for stage, slots in pairs(stages) do
            for slot, e in pairs(slots) do
                n = n + 1
                assert(ns.INV[slot], "unknown slot " .. slot)
                assert(type(e[1]) == "number" and type(e[2]) == "string" and e[2] ~= "", spec .. " " .. slot)
                assert(ns.ENCH_ICON[e[3]], "unknown kind " .. tostring(e[3]))
                if e[3] ~= "other" then assert(rawget(ns.T.en, "ENCH_SRC_" .. e[3]:upper()), "no text for " .. e[3]) end
            end
        end
    end
    assert(n > 100, "the lists have enchants")
end)

test("a slot's enchant: the client's name, else English, and whether the worn item has one", function()
    Fake({ worn = { [1] = 101, [16] = 301 }, enchanted = { [16] = 1900 }, spells = { [20034] = "Рыцарь" } })
    local ns = Load()
    fakeData(ns)
    ns.Data.ench.WARRIOR_ARMS = { L40 = { head = { 15397, "Lesser Arcanum of Voracity", "arcanum" },
                                          main = { 20034, "Enchant Weapon - Crusader", "ench" },
                                          finger1 = { 5, "Ring Thing", "new kind" } } }
    local list = ns.Resolve(REF)
    local head, main, ring = ns.Enchant(list, "head"), ns.Enchant(list, "main"), ns.Enchant(list, "finger1")
    eq(head.name, "Lesser Arcanum of Voracity", "English until the client knows the spell")
    eq(head.icon, ns.ENCH_ICON.arcanum, "the kind's icon until then")
    eq(head.state, "none", "worn without an enchant")
    eq(main.name, "Рыцарь", "the client's name")
    eq(main.icon, "spell20034", "the spell's icon")
    eq(main.state, "on", "worn with an enchant")
    eq(ring.state, nil, "nothing worn")
    eq(ring.kind, "other", "an unknown kind")
    eq(ns.Enchant(list, "off"), nil, "a slot without an enchant")
    local have, of = ns.EnchantProgress(list)
    eq(have, 1, "enchanted"); eq(of, 3, "slots with an enchant")
    -- the window: the badge on the slot and the row under the list
    ns.Window():Show()
    ns.ViewList("WARRIOR_ARMS", "L40")
    local gear = ns.Parts()
    eq(gear.slots.head.ench:IsShown(), true, "the badge")
    eq(gear.slots.head.enchant.state, "none", "its state")
    eq(gear.slots.off.ench:IsShown(), false, "no badge without an enchant")
    ns.slot = "main"; ns.Refresh()
    eq(gear.card.ench:IsShown(), true, "the row")
    eq(gear.card.ench.enchant.id, 20034, "of the chosen slot")
    ns.slot = "finger2"; ns.Refresh()
    eq(gear.card.ench:IsShown(), false, "no row without an enchant")
end)

test("the tooltip names the best enchant of a list item and what the worn one has", function()
    Fake({ worn = { [1] = 103, [16] = 999 }, enchanted = { [1] = 77 }, db = { tooltip = true } })
    local ns = Load()
    fakeData(ns)
    ns.Data.ench.WARRIOR_ARMS = { L40 = { head = { 15397, "Lesser Arcanum of Voracity", "arcanum" },
                                          main = { 20034, "Enchant Weapon - Crusader", "ench" } } }
    ns.SetMain(REF)
    local function find(lines, text) for _, l in ipairs(lines or {}) do if l.left == text or l.right == text then return l end end end
    local L = ns.L
    local lines = ns.TipLines(101)
    assert(find(lines, "Lesser Arcanum of Voracity"), "a list item names the enchant")
    eq(find(lines, L.ENCH_ON), nil, "no state for an item that is not worn")
    eq(find(lines, L.ENCH_NONE), nil, "no state for an item that is not worn")
    assert(find(ns.TipLines(103), L.ENCH_ON), "the worn item is enchanted")
    lines = ns.TipLines(999)
    assert(find(lines, "Enchant Weapon - Crusader"), "what is worn and not on the list gets the enchant too")
    assert(find(lines, L.ENCH_NONE), "and that it has none")
    eq(ns.TipLines(888), nil, "an item that is neither listed nor worn")
    ns.SetPref("tooltip", false)
    eq(ns.TipLines(101), nil, "switch off")
end)

test("the other faction's items leave the list and the rest move up", function()
    Fake({ faction = "Alliance" })
    local ns = Load()
    fakeData(ns)
    eq(table.concat(ns.Resolve(REF).slots.head, ","), "101,103", "alliance")
    Fake({ faction = "Horde" })
    ns = Load()
    fakeData(ns)
    eq(table.concat(ns.Resolve(REF).slots.head, ","), "101,102,103", "horde")
end)

test("a slot's state against what is worn and carried", function()
    Fake({ worn = { [1] = 103, [16] = 302 }, items = { [103] = 1, [302] = 1, [401] = 1 } })
    local ns = Load()
    fakeData(ns)
    local rows = ns.SlotRows(ns.Resolve(REF))
    eq(row(rows, "head").state, "rank", "head worn, not the first")
    eq(row(rows, "head").rank, 2, "head rank after the filter")
    eq(row(rows, "main").state, "rank", "main")
    eq(row(rows, "off").state, "bag", "off hand in the bags")
    eq(row(rows, "off").have, 401, "which")
    eq(row(rows, "finger1").state, "miss", "no ring")
    eq(row(rows, "neck").state, "none", "no list")
    eq(row(rows, "neck").counted, false, "not counted")
    W.worn[1] = 101
    eq(row(ns.SlotRows(ns.Resolve(REF)), "head").state, "bis", "the first worn")
    W.items[101] = 1
    W.worn[1] = 103
    eq(row(ns.SlotRows(ns.Resolve(REF)), "head").state, "bag", "a better one in the bags")
end)

test("a worn ring counts in the slot where it ranks best", function()
    -- 203 sits in the first finger and 201 in the second: swapped, both are the first of their list
    Fake({ worn = { [11] = 203, [12] = 201 }, items = { [201] = 1, [203] = 1 } })
    local ns = Load()
    fakeData(ns)
    local rows = ns.SlotRows(ns.Resolve(REF))
    eq(row(rows, "finger1").worn, 201, "first finger")
    eq(row(rows, "finger1").state, "bis", "first finger state")
    eq(row(rows, "finger2").state, "rank", "second finger state")
end)

test("a two-hander as the first weapon leaves the off hand out of the count", function()
    Fake({})
    local ns = Load()
    fakeData(ns, true)
    local list = ns.Resolve(REF)
    local off = row(ns.SlotRows(list), "off")
    eq(off.state, "covered", "off hand")
    eq(off.counted, false, "not counted")
    local _, of = ns.Progress(list)
    eq(of, 4, "head, two fingers, main")
end)

test("progress counts the slots whose first item is worn", function()
    Fake({ worn = { [1] = 101, [16] = 301, [11] = 201 } })
    local ns = Load()
    fakeData(ns)
    local have, of = ns.Progress(ns.Resolve(REF))
    eq(have, 3, "have")
    eq(of, 5, "of")
end)

test("the stage follows the level, and the realistic switch at the top", function()
    Fake({ level = 60 })
    local ns = Load()
    eq(ns.AutoStage(20), "L20", "20")
    eq(ns.AutoStage(21), "L30", "21")
    eq(ns.AutoStage(50), "L50", "50")
    eq(ns.AutoStage(51), "PRE", "51")
    local _, stage, auto = ns.ParseRef("auto")
    eq(stage, "PRE", "auto at 60")
    eq(auto, true, "auto")
    ns.SetPref("real", true)
    _, stage = ns.ParseRef("auto")
    eq(stage, "REAL", "realistic")
    eq(ns.ParseRef("site:NOPE:L20"), nil, "unknown spec")
    eq(ns.ParseRef("site:WARRIOR_ARMS:L99"), nil, "unknown stage")
end)

test("the spec: the game's specialization, else the talent tab with most points, else the first", function()
    Fake({ class = "PALADIN", spec = 66 })
    eq(Load().DetectSpec(), "PALADIN_PROTECTION", "specialization")
    Fake({ class = "PRIEST", tabs = { 5, 0, 31 } })
    eq(Load().DetectSpec(), "PRIEST_SHADOW", "talent points")
    Fake({ class = "MAGE" })
    local ns = Load()
    eq(ns.DetectSpec(), "MAGE_ARCANE", "first")
    ns.SetMySpec("MAGE_FROST")
    eq(ns.MySpec(), "MAGE_FROST", "the player's pick")
    ns.SetMySpec("WARRIOR_NOPE")
    eq(ns.MySpec(), "MAGE_FROST", "an unknown spec is refused")
end)

test("the star and the main list are apart", function()
    Fake({})
    local ns = Load()
    ns.SetFav(REF, true)
    ns.SetFav("auto", true)
    eq(#ns.Favs(), 1, "one favourite")
    eq(ns.IsFav("auto"), false, "auto is never a favourite")
    eq(ns.MainRef(), "auto", "the star does not change the main list")
    ns.SetMain(REF)
    eq(ns.Main().ref, REF, "main")
    ns.SetFav(REF, false)
    eq(#ns.Favs(), 0, "taken off")
    eq(ns.MainRef(), REF, "the main list stays")
end)

test("tooltip lines: the item's place on the main list and what is worn", function()
    Fake({ worn = { [1] = 103 }, cdb = { main = REF } })
    local ns = Load()
    fakeData(ns)
    W.Fire("PLAYER_LOGIN")
    assert(W.tips.MyBisList, "provider")
    local lines = W.tips.MyBisList(101)
    eq(#lines, 1, "one line")
    eq(lines[1].group, "note", "group")
    assert(lines[1].left:find("1"), "rank")
    eq(lines[1].right, ns.L.TIP_YOURS:format(2), "what is worn")
    eq(W.tips.MyBisList(103)[1].right, ns.L.TIP_WORN, "worn")
    eq(W.tips.MyBisList(999999), nil, "unknown item")
    ns.SetPref("tooltip", false)
    eq(W.tips.MyBisList(101), nil, "switch off")
    ns.SetPref("tooltip", true)
    ns.Pause(true)
    eq(W.tips.MyBisList(101), nil, "paused")
end)

test("a better list item in the bags is told once, never on the first look", function()
    Fake({ hub = true, worn = { [1] = 103 }, items = { [103] = 1 }, cdb = { main = REF } })
    local ns = Load()
    fakeData(ns)
    W.items[101] = 1
    eq(ns.CheckBags(true), 0, "first look is quiet")
    eq(#W.toasts, 0, "no toast")
    Fake({ hub = true, worn = { [1] = 103 }, items = { [103] = 1 }, cdb = { main = REF } })
    ns = Load()
    fakeData(ns)
    ns.CheckBags(true)
    W.items[101] = 1
    eq(ns.CheckBags(false), 1, "news")
    eq(#W.toasts, 1, "toast")
    eq(#W.notes, 1, "hub feed")
    eq(ns.CheckBags(false), 0, "told once")
    eq(#W.toasts, 1, "still one toast")
    W.items[201] = 1
    ns.SetPref("notify", false)
    ns.CheckBags(false)
    eq(#W.toasts, 1, "notify off: no toast")
    eq(#W.notes, 2, "but the feed")
    ns.Pause(true)
    W.items[202] = 1
    eq(ns.CheckBags(false), 0, "paused")
end)

test("the hub: summary, options, pause and reset", function()
    Fake({ hub = true, worn = { [1] = 101 }, cdb = { main = REF } })
    local ns = Load()
    fakeData(ns)
    local r = W.registered
    eq(r.key, "MyBisList", "key")
    eq(r.slash, "/gbis", "slash")
    assert(r.window and r.pause and r.reset and r.summary, "fields")
    eq(#r.options, 4, "options")
    local line, _, tile = r.summary()
    assert(line, "line")
    eq(tile.value, "1/5", "tile")
    ns.SetPref("notify", false)
    r.reset()
    eq(ns.db.notify, true, "reset")
    r.pause(true)
    eq(r.summary(), nil, "paused")
    Fake({})
    ns = Load()
    assert(ns.alone and ns.alone.key == "MyBisList", "alone")
end)

test("the window builds and shows a slot", function()
    Fake({ worn = { [1] = 103 }, items = { [103] = 1 } })
    local ns = Load()
    fakeData(ns)
    assert(ns.Window(), "window")
    ns.Show("head")
    ns.Refresh()
    ns.Slash("help")
    assert(#W.printed > 0, "help")
end)

test("an own list: a copy of a site list the player edits", function()
    Fake({ faction = "Alliance" })
    local ns = Load()
    fakeData(ns)
    local ref = ns.CopyList(REF)
    eq(ref, "own:1", "ref")
    local list = ns.Resolve(ref)
    eq(list.own, 1, "own")
    eq(list.spec, "WARRIOR_ARMS", "spec")
    eq(list.stage, "L40", "stage")
    eq(table.concat(list.slots.head, ","), "101,103", "the copy is of what the character can take")
    eq(ns.ListName(list), ns.L.OWN_NAME:format(ns.ListName(ns.Resolve(REF))), "name")
    eq(ns.RefOf(list), ref, "ref of")
    -- edits
    eq(ns.OwnAdd(ref, "head", 101), false, "no item twice")
    eq(ns.OwnAdd(ref, "head", 102, 1), true, "added")
    eq(table.concat(ns.Resolve(ref).slots.head, ","), "102,101,103", "at the place")
    eq(ns.OwnMove(ref, "head", 102, 1), true, "down")
    eq(ns.OwnMove(ref, "head", 103, 1), false, "the last goes no lower")
    eq(table.concat(ns.Resolve(ref).slots.head, ","), "101,102,103", "moved")
    eq(ns.OwnRemove(ref, "head", 102), true, "removed")
    for id = 1, ns.OWN_MAX do ns.OwnAdd(ref, "head", 500 + id) end
    eq(#ns.Resolve(ref).slots.head, ns.OWN_MAX, "full")
    eq(ns.OwnAdd(ref, "head", 600), false, "no more than OWN_MAX")
    eq(ns.OwnAdd(ref, "neck", 201), true, "a slot the site list did not have")
    eq(ns.RenameOwn(ref, "  Tank set  "), true, "rename")
    eq(ns.ListName(ns.Resolve(ref)), "Tank set", "new name")
    eq(ns.RenameOwn(ref, "   "), false, "no empty name")
    eq(ns.OwnAdd(REF, "head", 600), false, "a site list stays as it is")
    -- the site list is untouched
    eq(table.concat(ns.Resolve(REF).slots.head, ","), "101,103", "site")
    eq(#ns.OwnLists(), 1, "listed")
    eq(ns.PickItems()[1].head, ns.L.PICK_OWN, "the picker shows own lists first")
end)

test("deleting an own list lets the main list and the star go, and Undo brings all back", function()
    Fake({})
    local ns = Load()
    fakeData(ns)
    local ref = ns.CopyList(REF)
    ns.SetMain(ref)
    ns.SetFav(ref, true)
    eq(ns.Main().ref, ref, "main")
    local undo = ns.DeleteOwn(ref)
    eq(ns.Resolve(ref), nil, "gone")
    eq(ns.MainRef(), "auto", "main back to auto")
    eq(ns.IsFav(ref), false, "star")
    ns.RestoreOwn(undo)
    eq(ns.Resolve(ref).own, 1, "back")
    eq(ns.MainRef(), ref, "main again")
    eq(ns.IsFav(ref), true, "star again")
    eq(ns.CopyList(ref), "own:2", "a copy of an own list")
    eq(ns.db.own[2].from, REF, "keeps the site list it came from")
end)

test("an own list tells when the site's first item of a slot changed", function()
    Fake({})
    local ns = Load()
    fakeData(ns)
    local ref = ns.CopyList(REF)
    eq(#ns.SiteNews(ref), 0, "nothing new")
    ns.Data.lists.WARRIOR_ARMS.L40.head = { 103, 101 }
    local news = ns.SiteNews(ref)
    eq(#news, 1, "one slot")
    eq(news[1], "head", "head")
    ns.AckNews(ref)
    eq(#ns.SiteNews(ref), 0, "seen")
end)

test("the items that fit a slot: armour and weapons of the class, the spec's own first", function()
    Fake({ class = "PRIEST" })
    local ns = Load()
    local D = ns.Data
    local function it(slot, kind, ilvl, side) return { slot, 3, ilvl or 30, 30, 1, side, "Name" .. slot .. kind, kind } end
    D.item[901], D.item[902], D.item[903] = it("head", "plate"), it("head", "cloth", 20), it("head", "cloth", 40)
    D.item[904], D.item[905], D.item[906] = it("oh", "shield"), it("held", ""), it("1h", "dagger")
    D.item[907], D.item[908] = it("mh", "axe"), it("mh", "mace")
    D.item[909] = it("head", "cloth", 10, "H")
    eq(ns.Fits("PRIEST", "head", 901), false, "no plate")
    eq(ns.Fits("PRIEST", "head", 902), true, "cloth")
    eq(ns.Fits("PRIEST", "off", 904), false, "no shield")
    eq(ns.Fits("PRIEST", "off", 905), true, "held in off hand")
    eq(ns.Fits("PRIEST", "off", 906), false, "no dual wield")
    eq(ns.Fits("ROGUE", "off", 906), true, "a rogue's off hand dagger")
    eq(ns.Fits("PRIEST", "main", 907), false, "no axe")
    eq(ns.Fits("PRIEST", "main", 908), true, "mace")
    eq(ns.Fits("WARRIOR", "off", 904), true, "a warrior's shield")
    eq(ns.Fits("PRIEST", "finger2", 201), ns.Data.item[201] ~= nil, "a ring for anyone")
    D.lists.PRIEST_SHADOW.L40 = { head = { 902 } }
    local ref = ns.CopyList("site:PRIEST_SHADOW:L40")
    local ids = ns.Candidates(ref, "head", "")
    local pos = {}
    for i, id in ipairs(ids) do pos[id] = i end
    eq(pos[902], nil, "not what the slot has")
    eq(pos[901], nil, "not plate")
    eq(pos[909], nil, "not the other faction")
    assert(pos[903], "cloth found")
    local found = ns.Candidates(ref, "head", "namehead")
    for _, id in ipairs(found) do assert(D.item[id][7]:lower():find("namehead"), "the search") end
    eq(#ns.Candidates(ref, "head", "nothing like this"), 0, "no match")
    -- the spec's own site items come first
    D.lists.PRIEST_SHADOW.PRE = D.lists.PRIEST_SHADOW.PRE or {}
    D.lists.PRIEST_SHADOW.PRE.neck = { 903 }
    D.item[910] = it("head", "cloth", 99)
    pos = {}
    for i, id in ipairs(ns.Candidates(ref, "head", "")) do pos[id] = i end
    assert(pos[903] < pos[910], "the spec's item before a better one no list has")
end)

test("the window shows an own list with its tools", function()
    Fake({ worn = { [1] = 103 } })
    local ns = Load()
    fakeData(ns)
    local ref = ns.CopyList(REF)
    ns.Window():Show()
    ns.ViewRefSet(ref)
    eq(ns.ShownRef(), ref, "shown")
    local items = ns.CardItems(ns.Shown(), { slot = "head", ids = { 101, 103 }, worn = 103 })
    eq(items[1].ref, ref, "a row knows its list")
    eq(items[2].last, true, "last")
    eq(#ns.AddItems(""), math.min(60, #ns.Candidates(ref, "head", "")), "the search's rows")
    ns.OpenAdd(ns.Window())
    ns.ViewList("WARRIOR_ARMS", "L40")
    eq(ns.CardItems(ns.Shown(), { slot = "head", ids = { 101 } })[1].ref, nil, "a site row has no tools")
end)

test("the slot shows the list's first item and where it is: worn, carried, not found", function()
    Fake({ worn = { [1] = 103, [11] = 201 }, items = { [301] = 1 } })
    local ns = Load()
    fakeData(ns)
    local rows = ns.SlotRows(ns.Resolve(REF))
    eq(row(rows, "head").top, 101, "the first item")
    eq(row(rows, "head").topAt, "alt", "the first not found, but the list's second is worn")
    eq(row(rows, "head").alt, 103, "which one")
    eq(row(rows, "head").altRank, 2, "its place (102 is Horde)")
    eq(row(rows, "head").altAt, "worn", "worn")
    eq(row(rows, "finger2").topAt, "miss", "nothing of the list")
    eq(#ns.AtLines(row(rows, "head")), 3, "not found, what is had instead, where")
    eq(#ns.AtLines(row(rows, "finger2")), 1, "not found only")
    eq(row(rows, "finger1").topAt, "worn", "worn")
    eq(row(rows, "main").topAt, "bag", "in the bags or the bank")
    local text = ns.TopText(row(rows, "head"))
    assert(text:find("Item101"), "the slot names the first item")
    -- another item of the list in the bags or the bank counts too
    W.worn[1], W.items[103] = 999, 1
    local carried = row(ns.SlotRows(ns.Resolve(REF)), "head")
    eq(carried.topAt, "alt", "a list item carried")
    eq(carried.altAt, "bag", "in the bags or the bank")
    W.items[103] = nil
    -- the card: the top five, then what is worn under a line when it is not on the list
    W.worn[1] = 999
    local r = row(ns.SlotRows(ns.Resolve(REF)), "head")
    local items = ns.CardItems(ns.Resolve(REF), r)
    eq(#items, 3, "two of the list (102 is Horde) and the worn one")
    eq(items[3].id, 999, "worn last")
    eq(items[3].sep, true, "under a line")
    eq(items[3].rank, nil, "without a place")
end)

test("My target: a site list makes its own copy once, main and shown; an own list moves the item up", function()
    Fake({ worn = { [1] = 999 } })
    local ns = Load()
    fakeData(ns)
    ns.Window():Show()
    ns.ViewRefSet(REF)
    local mine = ns.SetTarget(REF, "head", 103)
    assert(mine and mine:match("^own:"), "an own list")
    eq(ns.MainRef(), mine, "it is the main list")
    eq(ns.ShownRef(), mine, "and the one shown")
    eq(table.concat(ns.Resolve(mine).slots.head, ","), "103,101", "the target first")
    eq(ns.SetTarget(REF, "head", 999), mine, "the same copy the next time")
    eq(table.concat(ns.Resolve(mine).slots.head, ","), "999,103,101", "what is worn can be the target")
    eq(#ns.OwnLists(), 1, "one copy")
    for i = 1, ns.OWN_MAX do ns.OwnAdd(mine, "head", 700 + i) end
    ns.SetTarget(mine, "head", 800)
    eq(#ns.Resolve(mine).slots.head, ns.OWN_MAX, "a full slot lets its last go")
    eq(ns.Resolve(mine).slots.head[1], 800, "first")
end)

test("adding any item by id or link, also from a site list", function()
    Fake({})
    local ns = Load()
    fakeData(ns)
    eq(ns.ParseId("12345"), 12345, "an id")
    eq(ns.ParseId("|cff0070dd|Hitem:19019::::|h[Thunderfury]|h|r"), 19019, "a link")
    eq(ns.ParseId("helm"), nil, "a name is no id")
    eq(ns.Candidates(REF, "head", "55555")[1], 55555, "an unknown id is offered first")
    eq(#ns.Candidates(REF, "head", "|Hitem:55555|h[x]|h"), 1, "a link offers that item alone")
    local ok, mine = ns.AddTo(REF, "head", 55555)
    eq(ok, true, "added")
    eq(ns.Resolve(mine).slots.head[3], 55555, "at the end of its own copy")
    eq(table.concat(ns.Resolve(REF).slots.head, ","), "101,103", "the site list stays")
    ns.Window():Show()
    ns.OpenAdd(ns.Window())
end)

test("a wanted item in the loot or a roll rings once, behind its switch", function()
    Fake({ hub = true, worn = { [1] = 103 }, cdb = { main = REF }, loot = { 101, 555 }, rolls = { [7] = 101 } })
    local ns = Load()
    fakeData(ns)
    eq(ns.Wanted(101), "head", "better than what is worn")
    eq(ns.Wanted(103), nil, "what is worn is not wanted")
    W.Fire("LOOT_READY")
    eq(W.sounds, 1, "a sound")
    eq(#W.toasts, 1, "a notice")
    eq(#W.notes, 1, "the hub's feed")
    W.Fire("START_LOOT_ROLL", 7)
    eq(W.sounds, 1, "once a minute per item")
    ns.dropAt = nil
    ns.SetPref("drop", false)
    W.Fire("START_LOOT_ROLL", 7)
    eq(W.sounds, 1, "the switch stops it")
    ns.SetPref("drop", true)
    W.items[101] = 1
    eq(ns.CheckDrop({ "|Hitem:101|h" }), 0, "carried already")
    W.items[101] = nil
    ns.Pause(true)
    eq(ns.CheckDrop({ "|Hitem:101|h" }), 0, "paused")
end)

-- Sets ------------------------------------------------------------------------------------------------

-- Two small sets of our own: 9001 a tier 0 set (head 101, a ring 201) and 9002 the tier 0.5 set
-- made from it, with two head variants (501, 502: slots only from the game) and a ring.
local function fakeSets(ns)
    local D = ns.Data
    D.item[503] = { "finger", 3, 60, 0, 1, nil, "Ring of Sets" }
    D.sets = {
        { 9001, "Old Set", "t0", "WARRIOR", "plate", false, false, { 101, 201 }, { 2 } },
        { 9002, "New Set", "t05", "WARRIOR", "plate", false, 9001, { 501, 502, 503 }, { 2, 3 } },
        { 9003, "Mage Set", "pvp", "MAGE", "cloth", "H", false, { 101, 201 }, { 2 } },
        { 9004, "Any Plate", "any", false, "plate", false, false, { 101, 201 }, { 2 } },
        { 9005, "Any Cloth", "any", false, "cloth", false, false, { 101, 201 }, { 2 } },
        { 9006, "Horde Plate", "any", false, "plate", "H", false, { 101, 201 }, { 2 } },
    }
    D.setSteps = { "First Quest", "Second Quest" }
    D.setStep = { [501] = 2, [502] = 2, [503] = 1 }
    D.names = { [501] = "Helm of Sets" }
end
local SET_EQUIP = { [501] = "INVTYPE_HEAD", [502] = "INVTYPE_HEAD" }

test("the data: every set has a known kind, pieces, bonus counts and a class or an armour", function()
    Fake({})
    local ns = Load()
    local D = ns.Data
    local kinds, ids, t05 = {}, {}, 0
    for _, g in ipairs(ns.SET_GROUPS) do
        assert(ns.L["SETS_" .. g[1]] ~= "SETS_" .. g[1], "no text for the group " .. g[1])
        for k in pairs(g[2]) do
            kinds[k] = true
            assert(ns.L["SET_KIND_" .. k:upper()] ~= "SET_KIND_" .. k:upper(), "no text for the kind " .. k)
        end
    end
    assert(#D.sets > 50, "sets")
    for _, r in ipairs(D.sets) do
        assert(not ids[r[1]], "a set twice: " .. r[2])
        ids[r[1]] = r
        assert(kinds[r[3]], r[2] .. ": unknown kind " .. tostring(r[3]))
        assert(#r[8] >= 2, r[2] .. " has no pieces")
        assert(#r[9] >= 1, r[2] .. " has no bonuses")
        assert(r[4] == false or ns.ARMOR[r[4]], r[2] .. ": unknown class")
        assert(r[5] == "" or ns.ARMOR.WARRIOR[r[5]], r[2] .. ": unknown armour")
        for _, piece in ipairs(r[8]) do
            assert(D.item[piece] or D.names[piece], r[2] .. ": a piece without a name, " .. piece)
        end
        if r[3] ~= "any" then assert(r[4], r[2] .. " names no class") end
    end
    for _, r in ipairs(D.sets) do
        if r[3] == "t05" then
            t05 = t05 + 1
            local from = ids[r[7]]
            assert(from and from[3] == "t0" and from[4] == r[4], r[2] .. " is made from no tier 0 set of its class")
            for _, piece in ipairs(r[8]) do
                assert(D.setSteps[D.setStep[piece]], r[2] .. ": a piece without its quest, " .. piece)
            end
        end
    end
    eq(t05, 9, "a tier 0.5 set per class")
    for _, class in ipairs(ns.CLASSES) do
        local n = 0
        for _, it in ipairs(ns.SetList(class)) do if it.set then n = n + 1 end end
        assert(n >= 3, class .. " has too few sets: " .. n)
    end
end)

test("the sets of a class: its own, and any-class sets of its best armour and faction", function()
    Fake({ class = "WARRIOR", faction = "Alliance" })
    local ns = Load()
    fakeData(ns)
    fakeSets(ns)
    local got = {}
    for _, it in ipairs(ns.SetList("WARRIOR")) do got[#got + 1] = it.head or it.set end
    eq(table.concat(got, ","), "DUNGEON,9001,9002,ANY,9004", "a warrior's sets, group by group")
    got = {}
    for _, it in ipairs(ns.SetList("MAGE")) do got[#got + 1] = it.head or it.set end
    eq(table.concat(got, ","), "PVP,9003,ANY,9005", "no Alliance PvP set of the mage: the Horde one shows")
    ns.Data.sets[#ns.Data.sets + 1] = { 9007, "Mage Set A", "pvp", "MAGE", "cloth", "A", false, { 101, 201 }, { 2 } }
    got = {}
    for _, it in ipairs(ns.SetList("MAGE")) do got[#got + 1] = it.head or it.set end
    eq(table.concat(got, ","), "PVP,9007,ANY,9005", "with one of its own side only that one")
    ns.Data.sets[2][6] = "H"
    got = {}
    for _, it in ipairs(ns.SetList("WARRIOR")) do got[#got + 1] = it.head or it.set end
    eq(table.concat(got, ","), "DUNGEON,9001,9002,ANY,9004", "a dungeon set is the class's on either side")
end)

test("a set against what is worn: places, variants, the tier 0 piece, bonuses and the chain", function()
    Fake({ class = "WARRIOR", worn = { [11] = 503 }, items = { [503] = 1, [101] = 1 }, equip = SET_EQUIP,
           setOf = { [503] = 77 }, setNames = { [77] = "Neues Set" },
           tipLines = { [501] = { "Helm", "|cff808080(2) Set: +10 Armor.|r", "(3) Set: +5 Strength." } } })
    local ns = Load()
    fakeData(ns)
    fakeSets(ns)
    local info = ns.SetInfo(9002)
    eq(info.name, "Neues Set", "the game's name, asked through a piece")
    eq(info.of, 2, "two head variants are one place")
    eq(info.worn, 1, "the ring is worn")
    local head, ring = info.groups[1], info.groups[2]
    eq(head.code, "head", "the slot comes from the game")
    eq(#head.ids, 2, "variants")
    eq(head.id, 501, "the first variant")
    eq(head.from, 101, "made from the tier 0 helm")
    eq(head.fromHave, true, "which is in the bags")
    eq(ring.worn, true, "worn")
    eq(ring.fromHave, false, "no tier 0 ring")
    ns.SetTurn(9002, "head", 2)
    eq(ns.SetInfo(9002).groups[1].id, 502, "the next variant")
    W.items[501] = 1
    eq(ns.SetInfo(9002).groups[1].id, 501, "a carried variant wins")
    W.items[501] = nil
    ns.setPick = {}
    eq(ns.SetInfo(9002, { slots = { head = { 502 } } }).groups[1].id, 502, "the variant of the list shown")
    local b = ns.SetBonuses(info)
    eq(#b, 2, "bonuses from the tooltip")
    eq(b[1].count, 2, "count")
    eq(b[1].text, "+10 Armor.", "text without colour codes")
    eq(b[1].on, false, "one piece is not two")
    W.tipLines[501] = { "Set: +10 Armor." }
    b = ns.SetBonuses(info)
    eq(b[1].count, 2, "an active bonus takes the data's count")
    W.tipLines[501] = nil
    b = ns.SetBonuses(info)
    eq(b[1].text, "+10 Armor.", "what the game told once is kept")
    eq(ns.bonusWait, 9002, "and the game is asked again")
    ns.db.bonusLang = "deDE"
    b = ns.SetBonuses(info)
    eq(#b, 2, "the data's counts until the game shows the bonuses")
    eq(b[1].text, nil, "no text made up, none of another client language")
    local chain = ns.SetChain(info)
    eq(chain.step, 2, "the ring's quest is done, the helm's is next")
    eq(chain.quest, "Second Quest", "its quest")
    eq(chain.codes[1], "head", "its slot")
    eq(ns.SetChain(ns.SetInfo(9001)), nil, "only tier 0.5 has a chain")
    W.worn[1] = 501
    eq(ns.SetChain(ns.SetInfo(9002)), nil, "every piece is there")
    eq(ns.SetBonuses(ns.SetInfo(9002))[1].on, true, "two pieces worn")
    eq(ns.SetName(9001), "Old Set", "the English name without the game's")
end)

test("the set bonuses: no scrolling, they come by themselves and stay over a login", function()
    Fake({ class = "WARRIOR", worn = { [11] = 503 }, items = { [503] = 1 }, equip = SET_EQUIP, cdb = { main = REF } })
    local ns = Load()
    fakeData(ns)
    fakeSets(ns)
    local h, lines = ns.BonusLayout(5, 177)
    eq(h, 34, "five rows keep the full height")
    eq(lines, 2, "and two lines")
    h, lines = ns.BonusLayout(6, 177)
    assert(h * 6 <= 177 and lines == 2, "six rows share the room")
    h, lines = ns.BonusLayout(8, 177)
    assert(h * 8 <= 177 and lines == 1, "eight rows take one line each")
    ns.Window():Show()
    ns.ShowTab(2)
    ns.setId = 9002
    ns.Refresh()
    local _, _, _, _, sets = ns.Parts()
    local box = sets.card.bonuses
    eq(box.n, 2, "the data's counts")
    eq(box.rows[1].item.text, nil, "the game has not told yet")
    eq(ns.bonusWait, 9002, "the page waits for it")
    -- the client loads the piece: the page draws itself again
    W.tipLines[501] = { "(2) Set: +10 Armor.", "(3) Set: +5 Strength.", "(4) Set: +1.", "(5) Set: +2.", "(6) Set: +3." }
    W.Fire("TOOLTIP_DATA_UPDATE")
    W.now = W.now + 1
    W.RunTimers()
    eq(box.n, 5, "five bonuses, all shown")
    eq(box.rows[5]:IsShown(), true, "the fifth row")
    eq(box.rows[6]:IsShown(), false, "no sixth")
    eq(box.rows[1].item.text, "+10 Armor.", "its text")
    eq(ns.bonusWait, nil, "nothing to wait for")
    eq(#GulliMyBisListDB.bonus[9002], 5, "kept in the saved variables")
    -- a paused module does not listen
    ns.bonusWait = 9002
    ns.Pause(true)
    W.Fire("TOOLTIP_DATA_UPDATE")
    eq(ns.pending, nil, "paused: no refresh")
    ns.Pause(false)
    -- after a login the client has nothing loaded: the saved texts show at once
    local saved = GulliMyBisListDB
    Fake({ class = "WARRIOR", worn = { [11] = 503 }, items = { [503] = 1 }, equip = SET_EQUIP, cdb = { main = REF },
           db = saved })
    ns = Load()
    fakeData(ns)
    fakeSets(ns)
    local b = ns.SetBonuses(ns.SetInfo(9002))
    eq(#b, 5, "five bonuses from the save")
    eq(b[3].text, "+1.", "with their texts")
end)

test("a menu is a frame of the screen in the tooltip strata, never a child of the window", function()
    Fake({ class = "WARRIOR", worn = { [11] = 503 }, items = { [503] = 1 }, equip = SET_EQUIP, cdb = { main = REF } })
    local ns = Load()
    fakeData(ns)
    fakeSets(ns)
    local win = ns.Window()
    win:Show()
    ns.ShowTab(2)
    local gear, _, _, _, sets = ns.Parts()
    sets.chip._OnClick(sets.chip)
    ns.ShowTab(1)
    gear.chip._OnClick(gear.chip)
    ns.OpenAdd(gear.chip)
    eq(#ns.menus, 3, "the class menu, the list picker and the adder")
    eq(ns.MENU_STRATA, "TOOLTIP", "the strata over the hub's FULLSCREEN_DIALOG")
    for i, menu in ipairs(ns.menus) do
        eq(rawget(menu, "_parent"), UIParent, "menu " .. i .. " hangs on the screen, so the hub's levels never reach it")
        -- as in the game: a fixed strata or level ignores a change, and the first show fixed them
        local got = { fixed = true, fixedLevel = true }
        rawset(menu, "SetFrameStrata", function(_, v) if not got.fixed then got.strata = v end end)
        rawset(menu, "SetFixedFrameStrata", function(_, v) got.fixed = v end)
        rawset(menu, "SetFrameLevel", function(_, v) if not got.fixedLevel then got.level = v end end)
        rawset(menu, "SetFixedFrameLevel", function(_, v) got.fixedLevel = v end)
        rawset(menu, "SetScale", function(_, v) got.scale = v end)
        rawset(win, "GetEffectiveScale", function() return 0.9 end)
        rawset(UIParent, "GetEffectiveScale", function() return 0.6 end)
        menu._OnShow(menu)
        eq(got.strata, "TOOLTIP", "menu " .. i .. " over every window on each show")
        eq(got.fixed, true, "and nothing moves its strata")
        eq(got.level, ns.MENU_LEVEL, "at its own level")
        eq(got.fixedLevel, true, "which stays")
        assert(math.abs(got.scale - 1.5) < 1e-9, "at the window's own scale")
    end
    -- the window going away closes them, since they are no longer its children
    local hidden = 0
    for _, menu in ipairs(ns.menus) do rawset(menu, "Hide", function() hidden = hidden + 1 end) end
    win._OnHide(win)
    eq(hidden, 3, "all three close with the window")
end)

test("the sets page: a class's list, the chosen set and its pieces on the list", function()
    Fake({ class = "WARRIOR", worn = { [11] = 503 }, items = { [503] = 1 }, equip = SET_EQUIP, cdb = { main = REF } })
    local ns = Load()
    fakeData(ns)
    fakeSets(ns)
    ns.Window():Show()
    ns.ShowTab(2)
    local _, footer, mainBtn, _, sets = ns.Parts()
    eq(ns.ShownSet(), 9001, "the class's first set")
    ns.setId = 9002
    ns.Refresh()
    eq(sets.info.id, 9002, "the chosen set")
    eq(sets.card.cells[1]:IsShown(), true, "a piece")
    eq(sets.card.cells[3]:IsShown(), false, "two places")
    eq(sets.card.chain:IsShown(), true, "the chain's step")
    eq(mainBtn.text:GetText(), ns.L.SET_ADD, "the footer's button")
    assert(ns.PieceLine(sets.info.groups[1]):find("Item101"), "a tier 0.5 piece names the tier 0 one")
    eq(ns.AddShownSet(), 1, "the helm goes on the list, the worn ring does not")
    local mine = ns.MainRef()
    assert(mine:find("^own:"), "into the own copy of the site list")
    local head = ns.Resolve(mine).slots.head
    eq(head[#head], 501, "at the end of its slot")
    eq(ns.AddShownSet(), 0, "not twice")
    ns.PickSetClass("MAGE")
    eq(ns.ShownSet(), 9003, "another class")
    ns.Refresh()
    eq(mainBtn:IsEnabled(), false, "another class's set cannot go on the list")
    eq(ns.AddShownSet(), 0, "and does not")
    ns.ShowTab(3)
    eq(footer:IsShown(), false, "the settings have no footer")
end)

-- Stats: hit, crit, attack power or spell damage, healing -------------------------------------------

-- Worn: head 103, ring 203, main 302, off 401 (inventory slots 1, 11, 16, 17).
local STATS = {
    [101] = { ITEM_MOD_STRENGTH_SHORT = 20, ITEM_MOD_HIT_RATING_SHORT = 1 },
    [103] = { ITEM_MOD_STRENGTH_SHORT = 10 },
    [201] = { ITEM_MOD_AGILITY_SHORT = 20 },
    [202] = { ITEM_MOD_CRIT_RATING_SHORT = 1 },
    [301] = { ITEM_MOD_STRENGTH_SHORT = 30 },
    [302] = { ITEM_MOD_STRENGTH_SHORT = 10 },
    [401] = { ITEM_MOD_STRENGTH_SHORT = 5 },
}
local function statOf(sum, key) for _, st in ipairs(sum.stats) do if st.key == key then return st end end end
local function keys(sum)
    local t = {}
    for i, st in ipairs(sum.stats) do t[i] = st.key end
    return table.concat(t, ",")
end

test("stats: a warrior's hit, crit and attack power now and with the list, through the game's conversions", function()
    Fake({ worn = { [1] = 103, [11] = 203, [16] = 302, [17] = 401 }, stats = STATS,
           char = { hit = 2, crit = 10.5, ap = 900, heal = 0 } })
    local ns = Load()
    fakeData(ns)
    local sum = ns.StatSummary(ns.Resolve(REF))
    eq(sum.kind, "melee", "kind")
    eq(keys(sum), "hit,crit,ap", "no healing without healing")
    eq(statOf(sum, "hit").now, 2, "hit now")
    eq(statOf(sum, "hit").gain, 1, "the head's +1% hit")
    eq(statOf(sum, "hit").cap, ns.HIT_CAP.melee, "a cap for hit")
    eq(statOf(sum, "crit").gain, 2, "20 agility is 1%, and a ring's 1%")
    eq(statOf(sum, "ap").now, 900, "attack power now")
    eq(statOf(sum, "ap").gain, 60, "10 and 20 strength more, two AP each; the off hand stays")
    eq(sum.items.ap[1].id, 301, "the biggest change first")
    eq(sum.items.ap[1].gain, 60, "the main hand against the worn one")
    local total = 0
    for _, it in ipairs(sum.items.ap) do total = total + it.gain end
    eq(total, 60, "the items add up to the change")
    -- the list takes a two-hander: the off hand comes off
    Fake({ worn = { [1] = 103, [11] = 203, [16] = 302, [17] = 401 }, stats = STATS, char = { ap = 900 } })
    ns = Load()
    fakeData(ns, true)
    eq(statOf(ns.StatSummary(ns.Resolve(REF)), "ap").gain, 50, "the worn off hand's 5 strength go")
end)

test("stats: which stats a spec shows, healing only where it says more", function()
    Fake({ class = "PRIEST", char = { shit = 3, scrit = 6, sd = 200, heal = 200 } })
    local ns = Load()
    eq(ns.StatKind("PRIEST_SHADOW"), "spell", "shadow")
    eq(ns.StatKind("PRIEST_HOLY"), "heal", "holy")
    eq(ns.StatKind("HUNTER_MARKSMANSHIP"), "ranged", "hunter")
    eq(ns.StatKind("HUNTER_SURVIVALMELEE"), "melee", "melee hunter")
    eq(ns.StatKind("PALADIN_SHOCKADIN"), "spell", "shockadin")
    for _, s in ipairs(ns.Data.specs) do assert(ns.STAT_ORDER[ns.StatKind(s[1])], s[1]) end
    eq(keys(ns.StatSummary(ns.Resolve("site:PRIEST_SHADOW:PRE"))), "hit,crit,sd", "healing equal to damage: not shown")
    W.char.heal = 260
    eq(keys(ns.StatSummary(ns.Resolve("site:PRIEST_SHADOW:PRE"))), "hit,crit,sd,heal", "more healing: shown")
    eq(keys(ns.StatSummary(ns.Resolve("site:PRIEST_HOLY:PRE"))), "crit,heal,sd", "a healer")
    W.char.sd = 0
    W.stats = {}
    ns.itemStats = {}
    eq(keys(ns.StatSummary(ns.Resolve("site:PRIEST_HOLY:PRE"))), "crit,heal", "a healer without spell damage")
    -- the best school: +shadow damage counts for a shadow priest
    W.char.schools = { [6] = 150 }
    eq(ns.StatNow("spell").sd, 150, "the best school")
    -- a melee list with healing on it shows healing too
    W.char.heal = 30
    eq(keys(ns.StatSummary(ns.Resolve("site:WARRIOR_FURY:PRE"))), "hit,crit,ap,heal", "healing as the fifth")
end)

test("stats: WoW Forever's own keys, one hit and crit for all, school damage for the spec's school", function()
    -- a shadow priest swaps a +1% crit, 68 spell power blade for one with +88 Shadow damage
    Fake({ class = "PRIEST", worn = { [16] = 302 }, char = { shit = 1, scrit = 6, schools = { [6] = 268, [3] = 200 } },
           stats = { [302] = { ITEM_MOD_SPELL_POWER_SHORT = 68, ITEM_MOD_CRIT_CHANCE_SHORT = 1 },
                     [301] = { ITEM_MOD_SHADOW_DAMAGE_SHORT = 88, ITEM_MOD_HIT_CHANCE_SHORT = 1 } } })
    local ns = Load()
    eq(ns.StatOfKey("ITEM_MOD_SHADOW_DAMAGE_SHORT"), "school6", "shadow damage by its words")
    eq(ns.StatOfKey("ITEM_MOD_FIRE_RESISTANCE_SHORT"), nil, "a resistance is no damage")
    eq(ns.StatOfKey("ITEM_MOD_CRIT_CHANCE_SHORT"), "crit", "crit chance")
    eq(ns.StatOfKey("ITEM_MOD_HEALING_DONE_SHORT"), "heal", "healing")
    eq(ns.StatOfKey("ITEM_MOD_STAMINA_SHORT"), nil, "not shown")
    ns.Data.item[301], ns.Data.item[302] = { "mh", 3, 30, 30, 1, nil, "New" }, { "mh", 3, 30, 30, 1, nil, "Old" }
    ns.Data.lists.PRIEST_SHADOW.PRE = { main = { 301 } }
    local sum = ns.StatSummary(ns.Resolve("site:PRIEST_SHADOW:PRE"))
    eq(statOf(sum, "sd").now, 268, "shadow, not the best school by chance")
    eq(statOf(sum, "sd").gain, 88 - 68, "the new blade's shadow damage counts, the old one's spell power goes")
    eq(statOf(sum, "crit").gain, -1, "the old blade's crit counts for spells too")
    eq(statOf(sum, "hit").gain, 1, "one hit for all")
    eq(statOf(sum, "hit").cap, 17 - 5, "17% for spells, less Shadow Focus, which the game's number leaves out")
    eq(statOf(sum, "hit").talentSchool, 6, "the talent is for Shadow only")
    eq(ns.HIT_CAP.melee, 8, "8% for attacks")
    -- a fire mage gets nothing from shadow damage
    ns.Data.lists.MAGE_FIRE.PRE = { main = { 301 } }
    eq(statOf(ns.StatSummary(ns.Resolve("site:MAGE_FIRE:PRE")), "sd").gain, -68, "another school's damage is not counted")
end)

test("stats: each spec's hit cap, talents and schools from the WoW Forever guides", function()
    Fake({ class = "MAGE", char = { shit = 3, scrit = 6, schools = { [5] = 300, [3] = 120, [7] = 100 } } })
    local ns = Load()
    local function hit(spec) return statOf(ns.StatSummary(ns.Resolve("site:" .. spec .. ":PRE")), "hit") end
    -- every caster spec needs 17% in all, every attack spec 8%
    for _, sp in ipairs(ns.Data.specs) do
        local kind = ns.StatKind(sp[1])
        local h = hit(sp[1])
        if kind == "heal" then
            eq(h, nil, sp[1] .. ": a heal never misses, no hit shown")
        else
            local t = ns.SPEC_HIT[sp[1]]
            local want = ns.HIT_CAP[kind] - ((t and t[2]) and t[1] or 0)
            eq(h.cap, want, sp[1] .. ": the cap")
            eq(ns.HIT_CAP[kind], kind == "spell" and 17 or 8, sp[1] .. ": 17 or 8")
        end
        local sc = ns.SPEC_SCHOOL[sp[1]]
        if kind == "spell" and sp[1] ~= "PALADIN_SHOCKADIN" then assert(sc and #sc > 0, sp[1] .. " has a school") end
    end
    -- a frost mage: Frost damage is its spell damage, Precision is in the game's number
    local sum = ns.StatSummary(ns.Resolve("site:MAGE_FROST:PRE"))
    eq(statOf(sum, "sd").now, 300, "frost spell damage")
    eq(statOf(sum, "hit").cap, 17, "Precision counts for every spell: the full 17")
    eq(statOf(sum, "hit").talent, 6, "Precision 6%")
    eq(statOf(ns.StatSummary(ns.Resolve("site:MAGE_FIRE:PRE")), "sd").now, 120, "fire for a fire mage")
    -- destruction is a Fire caster in WoW Forever, Balance the best of Arcane and Nature
    eq(ns.SPEC_SCHOOL.WARLOCK_DESTRUCTION[1], 3, "destruction: fire first")
    eq(statOf(ns.StatSummary(ns.Resolve("site:WARLOCK_DESTRUCTION:PRE")), "sd").now, 120, "fire, not frost")
    W.char.schools[4] = 140
    eq(statOf(ns.StatSummary(ns.Resolve("site:DRUID_BALANCE:PRE")), "sd").now, 140, "balance: nature over arcane")
    -- an item's damage of one school counts when it is any of the spec's schools
    eq(ns.StatValue("spell", { school4 = 30 }, ns.SPEC_SCHOOL.DRUID_BALANCE).sd, 30, "+nature damage for balance")
    eq(ns.StatValue("spell", { school5 = 30 }, ns.SPEC_SCHOOL.DRUID_BALANCE).sd, 0, "+frost damage is not")
    -- two weapons: a note for the white hits
    eq(hit("ROGUE_COMBAT").dual, ns.DUAL_CAP, "dual wield")
    eq(hit("WARRIOR_ARMS").dual, nil, "a two-hander")
    -- feral attack power counts only for a feral druid
    eq(ns.StatOfKey("ITEM_MOD_FERAL_ATTACK_POWER_SHORT"), "fap", "feral attack power")
    eq(ns.StatValue("melee", { fap = 100 }, nil, true).ap, 100, "for a feral druid")
    eq(ns.StatValue("melee", { fap = 100 }).ap, 0, "not for anyone else")
end)

test("stats: an item not loaded yet waits, a value the game hides shows as unknown", function()
    Fake({ worn = { [1] = 103 }, stats = STATS, notLoaded = { [101] = true }, char = {} })
    local ns = Load()
    fakeData(ns)
    W.char.hit = W.SECRET
    local sum = ns.StatSummary(ns.Resolve(REF))
    eq(sum.wait, true, "waits for the head")
    eq(statOf(sum, "hit").now, nil, "a hidden value is no number")
    assert(ns.StatCell(statOf(sum, "hit")):find("?", 1, true), "the cell says it does not know")
    W.notLoaded[101] = nil
    sum = ns.StatSummary(ns.Resolve(REF))
    eq(sum.wait, false, "loaded")
    eq(statOf(sum, "ap").gain, 20 + 60 + 10, "now counted: head, main and off hand against nothing")
end)

test("stats: the bar beside the page tabs, only on the Gear page, with the cap in the tooltip", function()
    Fake({ worn = { [1] = 103, [11] = 203, [16] = 302, [17] = 401 }, stats = STATS,
           char = { hit = 2, crit = 10.5, ap = 900 } })
    local ns = Load()
    fakeData(ns)
    ns.Window():Show()
    ns.ShowTab(1)
    ns.StatRoom = function() return 500 end   -- the fake frames have no real widths
    ns.ViewList("WARRIOR_ARMS", "L40")
    local bar = ns.StatBar()
    eq(bar:IsShown(), true, "on the Gear page")
    eq(bar.shown, 3, "three stats")
    assert(bar.cells[1].text:GetText():find("+1.0", 1, true), "the change of hit")
    local lines = ns.StatTipLines(bar.cells[1].sum, bar.cells[1].st)
    local capped
    for _, l in ipairs(lines) do if l[1] == ns.L.STATS_CAP:format("8%") then capped = l[2] end end
    assert(capped and capped:find(ns.L.STATS_CAP_LEFT:format("5.0%"), 1, true), "the cap line: 3% of 8%")
    ns.ShowTab(2)
    eq(bar:IsShown(), false, "not on the Sets page")
    ns.ShowTab(1)
    eq(bar:IsShown(), true, "back on Gear")
    -- too narrow a row: the last stats give way
    ns.PaintStats(bar, ns.Shown(), -1)
    eq(bar.shown, 0, "nothing fits")
end)

W.finish()
