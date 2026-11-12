-- Run from the repository root: lua5.1 tests/reminders/test.lua
local W = dofile("tests/reminders/wow.lua")
local test, eq = W.test, W.eq

test("every language has every text", function()
    Fake({})
    W.CheckLocales(Load())
end)

test("a buff the class knows and lacks is shown; any rank or group spell counts", function()
    Fake({ class = "PRIEST", known = { 1243, 588 }, auras = { "Spell21562" } })
    local ns = Load()
    eq(W.Keys(ns.Missing()), "INNER_FIRE", "Prayer of Fortitude counts as Fortitude")
    W.auras = { "Spell21562", "Spell588" }
    eq(W.Keys(ns.Missing()), "")
end)

test("a buff the player does not know yet is not asked for", function()
    Fake({ class = "MAGE", known = { 168 } })
    eq(W.Keys(Load().Missing()), "ARMOR")
end)

test("rogue poisons from level 20, the off hand only when it holds a weapon", function()
    Fake({ class = "ROGUE", level = 19 })
    local ns = Load()
    eq(W.Keys(ns.Missing()), "")
    W.level = 20
    W.weapon = { true, 30 * 60 * 1000, false, 0 }
    eq(W.Keys(ns.Missing()), "", "no off hand")
    W.offHand = 99 -- a shield, not a weapon
    eq(W.Keys(ns.Missing()), "")
    W.offHand = 50
    eq(W.Keys(ns.Missing()), "WEAPON")
    W.weapon = { true, 30000, true, 30 * 60 * 1000 }
    eq(W.Keys(ns.Missing()), "WEAPON", "less than a minute left")
end)

test("a shaman who knows an imbue is reminded", function()
    Fake({ class = "SHAMAN", known = { 8017, 324 }, auras = { "Spell324" } })
    eq(W.Keys(Load().Missing()), "WEAPON")
end)

test("hunter ammo and warlock shards below the set numbers", function()
    Fake({ class = "HUNTER", ammo = 150 })
    local ns = Load()
    eq(W.Keys(ns.Missing()), "AMMO")
    ns.db.ammoMin = 100
    eq(W.Keys(ns.Missing()), "")
    Fake({ class = "WARLOCK", shards = 1 })
    eq(W.Keys(Load().Missing()), "SHARDS")
end)

test("nothing in combat, when dead, or when the panel is off; cities only when asked", function()
    Fake({ class = "PRIEST", known = { 588 } })
    local ns = Load()
    W.combat = true
    local list, why = ns.Missing()
    eq(#list, 0); eq(why, "combat")
    W.combat = false
    W.resting = true
    eq(#ns.Missing(), 1, "in cities by default")
    ns.SetPref("inRest", false)
    list, why = ns.Missing()
    eq(#list, 0); eq(why, "rest")
    W.resting = false
    W.dead = true
    eq(select(2, ns.Missing()), "dead")
    W.dead = false
    ns.SetPref("show", false)
    eq(select(2, ns.Missing()), "off")
end)

test("each class buff has its own switch; some start off", function()
    Fake({ class = "PRIEST", known = { 1243, 588, 976 } })
    local ns = Load()
    eq(W.Keys(ns.Missing()), "FORTITUDE,INNER_FIRE", "Shadow Protection is off until switched on")
    ns.SetTracked("SHADOW_PROT", true)
    ns.SetTracked("FORTITUDE", false)
    eq(W.Keys(ns.Missing()), "INNER_FIRE,SHADOW_PROT")
    local cb = ns.ClassBuffs()
    eq(#cb, 4)
    eq(cb[3].key, "SPIRIT"); eq(cb[3].known, nil, "Divine Spirit not learned")
end)

test("every class buff has a name in every language", function()
    Fake({})
    local ns = Load()
    for _, list in pairs(ns.BUFFS) do
        for _, b in ipairs(list) do
            for _, tag in ipairs(ns.TAGS) do assert(ns.T[tag]["BUFF_" .. b.key], tag .. " misses BUFF_" .. b.key) end
        end
    end
end)

test("a buff that ends within the set minutes counts as missing", function()
    Fake({ class = "MAGE", known = { 1459 }, auras = { "Spell1459" }, left = { Spell1459 = 100 } })
    local ns = Load()
    local m = ns.Missing()
    eq(W.Keys(m), "INTELLECT"); eq(m[1].left, 100)
    W.left.Spell1459 = 1200
    eq(W.Keys(ns.Missing()), "")
    W.left.Spell1459 = 100
    ns.SetPref("soonMin", 0)
    eq(W.Keys(ns.Missing()), "", "warning off")
end)

test("a hunter or warlock without a pet is reminded", function()
    Fake({ class = "WARLOCK", known = { 688 }, shards = 5 })
    local ns = Load()
    eq(W.Keys(ns.Missing()), "PET")
    W.pet = true
    eq(W.Keys(ns.Missing()), "")
    W.pet = false
    ns.SetPref("pet", false)
    eq(W.Keys(ns.Missing()), "")
end)

test("old saves: the buffs switch off turns every buff off, the towns switch goes", function()
    Fake({ class = "PRIEST", known = { 588 }, db = { buffs = false, notResting = true } })
    local ns = Load()
    eq(ns.db.notResting, nil)
    eq(ns.db.inRest, true)
    eq(W.Keys(ns.Missing()), "")
end)

test("the panel shows the missing icons, every icon while unlocked, and hides when all is there", function()
    Fake({ class = "PRIEST", known = { 1243, 588 }, auras = { "Spell1243" } })
    local ns = Load()
    eq(#ns.Refresh(), 1)
    local panel = _G.GulliRemindersPanel or W.panel
    ns.SetPref("locked", false)
    eq(#ns.Sample(), 3, "Fortitude, Inner Fire and Well Fed to place")
    W.auras = { "Spell1243", "Spell588" }
    eq(#ns.Refresh(), 0)
    ns.SetPref("locked", true)
    SlashCmdList.GULLIREMINDERS("unlock")
    eq(ns.db.locked, false)
    SlashCmdList.GULLIREMINDERS("reset")
    eq(ns.db.point, nil)
    ns.Toggle()
    ns.SetPref("size", 48)
    ns.SetPref("vertical", true)
    ns.Refresh()
end)

test("the settings list only the checks of the class", function()
    Fake({ class = "ROGUE" })
    local ns = Load()
    local e = ns.Extras()
    eq(e.weapon, true); eq(e.pet, nil); eq(e.ammo, nil)
    eq(#ns.ClassBuffs(), 0)
    ns.Toggle()
    e = ns.Extras("HUNTER")
    eq(e.pet, true); eq(e.ammo, true); eq(e.weapon, nil)
end)

test("a click casts the missing buff on you, applies poison, summons the picked pet", function()
    Fake({ class = "PRIEST", known = { 1243 } })
    local ns = Load()
    local m = ns.Missing()[1]
    eq(m.act.type, "spell"); eq(m.act.spell, "Spell1243")
    ns.Refresh()
    local b = _G.GulliRemindersIcon1
    eq(b:GetAttribute("type1"), "spell")
    eq(b:GetAttribute("unit1"), "player")
    local opened = false
    ns.Toggle = function() opened = true end
    rawget(b, "_PostClick")(b, "RightButton", false)
    eq(opened, true, "right click opens the settings")
    Fake({ class = "ROGUE", level = 30, items = { [6949] = 3 } })
    ns = Load()
    m = ns.Missing()[1]
    eq(m.key, "WEAPON"); eq(m.act.macrotext, "/use item:6949\n/use 16")
    Fake({ class = "WARLOCK", known = { 688, 697 }, shards = 5, db = { lockPet = 697 } })
    ns = Load()
    eq(ns.Missing()[1].act.spell, "Spell697")
end)

test("while unlocked the icons are samples and cast nothing", function()
    Fake({ class = "PRIEST", known = { 1243 } })
    local ns = Load()
    ns.SetPref("locked", false)
    eq(_G.GulliRemindersIcon1:GetAttribute("type1"), nil)
end)

test("Well Fed and oils: shown where asked, a click eats or applies the best item in the bags", function()
    Fake({ class = "WARRIOR", items = { [13928] = 2, [20748] = 1 }, db = { anyWeapon = true }, instance = "party" })
    GetInventoryItemID = function(_, slot) if slot == 16 then return 1 end end
    local ns = Load()
    local list = ns.Missing()
    eq(W.Keys(list), "WEAPON_ITEM,FOOD")
    eq(list[1].act.macrotext, "/use item:20748\n/use 16")
    eq(list[2].act.item, "item:13928")
    ns.db.foodItem = 99999
    W.items[99999] = 1
    eq(ns.Missing()[2].act.item, "item:99999", "the food the player set comes first")
    W.auras = { "Spell19705" }
    eq(W.Keys(ns.Missing()), "WEAPON_ITEM")
    W.instance = nil
    eq(W.Keys(ns.Missing()), "", "consumables only in instances by default")
    ns.SetPref("whereItems", "always")
    eq(W.Keys(ns.Missing()), "WEAPON_ITEM")
end)

test("class buffs only in a group when asked", function()
    Fake({ class = "PRIEST", known = { 588 }, db = { where = "group" } })
    local ns = Load()
    eq(W.Keys(ns.Missing()), "")
    W.group = { { class = "WARRIOR", name = "Tank" } }
    eq(W.Keys(ns.Missing()), "INNER_FIRE")
end)

test("own reminders: an elixir's buff, a count to keep, a spell; a count icon buys at a vendor", function()
    Fake({ class = "WARRIOR", itemSpells = { [13452] = "Elixir of the Mongoose" }, items = { [13452] = 1, [6451] = 2 },
           db = { whereItems = "always", food = false } })
    local ns = Load()
    eq(ns.AddItem(13452), true)
    eq(ns.AddItem(6451), true)
    eq(ns.AddItem(6451), false, "no twice")
    eq(ns.db.custom[1].kind, "buff"); eq(ns.db.custom[2].kind, "count")
    ns.SetCustom(2, "min", 10)
    W.known = { 6673 }
    eq(ns.AddSpell(6673), true)
    local list = ns.Missing()
    eq(W.Keys(list), "CUSTOM1,CUSTOM2,CUSTOM3")
    eq(list[1].act.item, "item:13452")
    eq(list[2].text, "Item6451: 2 of 10")
    eq(list[3].act.spell, "Spell6673")
    W.auras = { "Elixir of the Mongoose" }
    eq(W.Keys(ns.Missing()), "CUSTOM2,CUSTOM3")
    W.merchant = { { 1, 1, 1, 20 }, { 6451, 50, 1, 5 } }
    eq(ns.Buy(ns.Missing()[1]), 8)
    eq(#W.bought, 2, "in stacks of 5")
    W.money = 100
    eq(ns.Buy(ns.Missing()[1]), 2, "only what the money pays")
    ns.RemoveCustom(1)
    eq(#ns.db.custom, 2)
    SlashCmdList.GULLIREMINDERS("item |cff|Hitem:2459::|h[x]|h|r")
    eq(ns.db.custom[3].id, 2459)
end)

test("durability, bag space; group buffs others can give, with their name", function()
    Fake({ class = "WARRIOR", durability = 10, free = 1 })
    local ns = Load()
    eq(W.Keys(ns.Missing()), "DURABILITY,BAGS")
    W.durability, W.free = 50, 10
    eq(W.Keys(ns.Missing()), "")
    ns.SetPref("others", true)
    W.group = { { class = "PRIEST", name = "Pia" }, { class = "MAGE", name = "Mo" } }
    UnitPowerType = function() return 1 end
    local list = ns.Missing()
    eq(W.Keys(list), "ASK_FORTITUDE", "no Intellect for a warrior")
    eq(list[1].text, "Power Word: Fortitude: ask Pia")
    UnitPowerType = nil
end)

test("Righteous Fury is on for a tank unless switched off", function()
    Fake({ class = "PALADIN", known = { 25780 } })
    local ns = Load()
    eq(W.Keys(ns.Missing()), "")
    W.role = "TANK"
    eq(W.Keys(ns.Missing()), "FURY")
    ns.SetTracked("FURY", false)
    eq(W.Keys(ns.Missing()), "")
end)

test("a new reminder plays a sound once, in instances by default", function()
    Fake({ class = "PRIEST", known = { 588 }, instance = "party" })
    local ns = Load()
    ns.Refresh()
    eq(#W.sounds, 1)
    ns.Refresh()
    eq(#W.sounds, 1, "not again for the same one")
    W.known = { 588, 1243 }
    W.instance = nil
    ns.Refresh()
    eq(#W.sounds, 1, "not outside")
end)

test("the hub gets a summary, move and reset", function()
    Fake({ class = "PRIEST", known = { 588 } })
    local got
    GulliToolkit = { Register = function(m) got = m end }
    local ns = Load()
    eq(got.summary(), "Missing: 1")
    got.move(true)
    eq(ns.db.locked, false)
    ns.db.size = 60
    got.reset()
    eq(ns.db.size, 40); eq(ns.db.locked, true)
    GulliToolkit = nil
end)

W.finish()
