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
    eq(#D.specs, 28, "specs")
    for _, s in ipairs(D.specs) do
        assert(ns.SpecName(s[1]), "no name for " .. s[1])
        assert(ns.ROLE_ICON[s[3]], "no role icon for " .. s[1])
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
    eq(#r.options, 3, "options")
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

W.finish()
