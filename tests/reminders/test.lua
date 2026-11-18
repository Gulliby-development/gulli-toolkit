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
    eq(W.Keys(ns.Missing()), "WEAPON_OFF", "the off hand has its own icon")
    W.weapon = { true, 30000, true, 30 * 60 * 1000 }
    eq(W.Keys(ns.Missing()), "WEAPON", "less than a minute left")
    W.weapon = { false, 0, false, 0 }
    eq(W.Keys(ns.Missing()), "WEAPON,WEAPON_OFF")
    W.mainHand = false
    eq(W.Keys(ns.Missing()), "WEAPON_OFF", "no main hand weapon, nothing to put on it")
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
    eq(#cb, 5, "a Human priest gets no other race's buffs")
    eq(cb[3].key, "SPIRIT"); eq(cb[3].known, nil, "Divine Spirit not learned")
end)

test("racial priest buffs: Touch of Weakness for the Undead, Shadowguard for Trolls", function()
    Fake({ class = "PRIEST", race = "Scourge", known = { 2652 } })
    local ns = Load()
    local keys = {}
    for _, b in ipairs(ns.ClassBuffs()) do keys[#keys + 1] = b.key end
    eq(table.concat(keys, ","), "FORTITUDE,INNER_FIRE,SPIRIT,SHADOW_PROT,TOUCH,SHADOWFORM")
    eq(W.Keys(ns.Missing()), "TOUCH", "on by default")
    ns.SetTracked("TOUCH", false)
    eq(W.Keys(ns.Missing()), "", "its switch turns it off")
    Fake({ class = "PRIEST", race = "Troll", known = { 18137 } })
    ns = Load()
    eq(W.Keys(ns.Missing()), "SHADOWGUARD")
    Fake({ class = "PRIEST", race = "Dwarf", known = { 6346 } })
    ns = Load()
    eq(W.Keys(ns.Missing()), "", "Fear Ward starts off")
    ns.SetTracked("FEAR_WARD", true)
    eq(W.Keys(ns.Missing()), "FEAR_WARD")
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
    ns.Move(true)
    eq(#ns.Sample(), 3, "Fortitude, Inner Fire and Well Fed to place")
    W.auras = { "Spell1243", "Spell588" }
    eq(#ns.Refresh(), 0)
    ns.Move(false)
    local unlocked = false
    GulliToolkit = { Unlock = function() unlocked = true; return true end }
    SlashCmdList.GULLIREMINDERS("unlock")
    eq(unlocked, true, "/grm unlock opens the hub's Unlock mode")
    GulliToolkit = nil
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
    eq(e.weapon.kind, "POISON"); eq(e.pet, nil); eq(e.ammo, nil); eq(e.items, nil)
    eq(#ns.ClassBuffs(), 0)
    ns.Toggle()
    e = ns.Extras("HUNTER")
    eq(e.pet, true); eq(e.ammo, true); eq(e.weapon.kind, "STONE_OIL")
    e = ns.Extras("MAGE")
    eq(e.weapon.kind, "OIL"); eq(e.items, true); eq(e.pet, nil); eq(e.shards, nil)
    eq(ns.Extras("SHAMAN").weapon.kind, "IMBUE")
    eq(ns.Extras("WARRIOR").weapon.kind, "STONE")
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

test("in the Unlock mode the icons are samples and cast nothing", function()
    Fake({ class = "PRIEST", known = { 1243 } })
    local ns = Load()
    ns.Move(true)
    eq(_G.GulliRemindersIcon1:GetAttribute("type1"), nil)
    eq(rawget(_G.GulliRemindersIcon1, "_OnDragStart"), nil, "the icons are never dragged themselves")
end)

test("the panel starts hidden, once also for older saves, and has no lock of its own", function()
    Fake({ class = "PRIEST", known = { 588 }, fresh = true })
    local ns = Load()
    eq(ns.db.show, false)
    local _, why = ns.Missing()
    eq(why, "off")
    Fake({ class = "PRIEST", known = { 588 }, db = { show = true, locked = true } })
    ns = Load()
    eq(ns.db.show, false, "hidden once"); eq(ns.db.locked, nil)
    ns.SetPref("show", true)
    W.Fire("ADDON_LOADED", "Gulli-Reminders")
    eq(ns.db.show, true, "a later choice stays")
end)

test("Well Fed and oils: shown where asked, a click eats or applies the best item in the bags", function()
    Fake({ class = "PRIEST", items = { [13928] = 2, [20748] = 1 }, instance = "party" })
    local ns = Load()
    eq(W.Keys(ns.Missing()), "FOOD", "oils start off")
    ns.SetClassPref("weapon", true)
    local list = ns.Missing()
    eq(W.Keys(list), "WEAPON,FOOD")
    eq(list[1].act.macrotext, "/use item:20748\n/use 16")
    eq(list[2].act.item, "item:13928")
    ns.db.foodItem = 99999
    W.items[99999] = 1
    eq(ns.Missing()[2].act.item, "item:99999", "the food the player set comes first")
    W.auras = { "Spell19705" }
    eq(W.Keys(ns.Missing()), "WEAPON")
    W.instance = nil
    eq(W.Keys(ns.Missing()), "", "consumables only in instances by default")
    ns.SetPref("whereItems", "always")
    eq(W.Keys(ns.Missing()), "WEAPON")
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

test("Camp Benefits with as much Stamina or more covers Fortitude, also when asking others", function()
    -- Rank 4 (2791) gives 32 Stamina; the camp gives 34.
    Fake({ class = "PRIEST", known = { 1243, 2791 }, auras = { "Camp Benefits" },
           camp = { "Gained the following camp benefits:", "First Aid Kit: Stamina increased by 34." } })
    local ns = Load()
    ns.SetTracked("INNER_FIRE", false)
    eq(W.Keys(ns.Missing()), "", "Fortitude covered")
    W.camp[2] = "First Aid Kit: Stamina increased by 20."
    eq(W.Keys(ns.Missing()), "FORTITUDE", "a weaker camp")
    -- A level 60 warrior asks a priest only when the camp is under 54 Stamina.
    Fake({ class = "WARRIOR", auras = { "Camp Benefits" }, camp = { "First Aid Kit: Stamina increased by 54." } })
    ns = Load()
    ns.SetPref("others", true)
    W.group = { { class = "PRIEST", name = "Pia" } }
    UnitPowerType = function() return 1 end
    eq(W.Keys(ns.Missing()), "")
    W.camp[1] = "First Aid Kit: Stamina increased by 34."
    eq(W.Keys(ns.Missing()), "ASK_FORTITUDE")
    UnitPowerType = nil
end)

test("a buff the game refuses as weaker after a click is not asked for again", function()
    Fake({ class = "PRIEST", known = { 1243 } })
    local ns = Load()
    ns.SetTracked("INNER_FIRE", false)
    eq(W.Keys(ns.Missing()), "FORTITUDE")
    ns.NoteClick("FORTITUDE")
    W.Fire("UI_ERROR_MESSAGE", 50, "A more powerful spell is already active")
    eq(W.Keys(ns.Missing()), "", "blocked")
    W.now = W.now + 601
    eq(W.Keys(ns.Missing()), "FORTITUDE", "back after ten minutes")
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

test("a buff of yours that comes or goes shows on the next frame", function()
    Fake({ class = "PRIEST", known = { 588 } })
    Load()
    W.RunTimers()
    W.lastDelay = nil
    local before = #W.timers
    W.Fire("UNIT_AURA", "player")
    eq(W.lastDelay, 0, "UNIT_AURA refreshes without the half-second wait")
    W.Fire("UNIT_AURA", "player")
    eq(#W.timers, before + 1, "a burst gives one refresh")
    W.RunTimers()
    W.Fire("BAG_UPDATE_DELAYED")
    eq(W.lastDelay, 0.5, "other events still wait")
end)

test("each class gets its own weapon kit, and only its own", function()
    Fake({})
    local ns = Load()
    for _, class in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
        local kit = ns.KITS[class]
        assert(kit, class .. " has no kit")
        assert(ns.KIT_ICON[kit.kind], kit.kind .. " has no icon")
        for _, tag in ipairs(ns.TAGS) do
            assert(ns.T[tag]["KIT_" .. kit.kind], tag .. " misses KIT_" .. kit.kind)
        end
        for _, name in ipairs(kit.lists or {}) do
            assert(name == "STONES" or type(ns[name]) == "table", class .. ": no list " .. name)
        end
    end
    for _, list in pairs(ns.CLASS_ITEMS) do
        for _, c in ipairs(list) do
            for _, tag in ipairs(ns.TAGS) do assert(ns.T[tag][c.key] and ns.T[tag]["OPT_" .. c.key], tag .. " misses " .. c.key) end
        end
    end
end)

test("a warrior's stones follow the weapon: sharpening for a blade, weight for a mace, both hands", function()
    Fake({ class = "WARRIOR", items = { [2862] = 5, [3239] = 5 }, mainHand = 70, offHand = 71,
           sub = { [70] = 7, [71] = 4 }, instance = "party" })
    local ns = Load()
    eq(W.Keys(ns.Missing()), "FOOD", "stones start off: they cost money")
    ns.SetClassPref("weapon", true)
    local list = ns.Missing()
    eq(W.Keys(list), "WEAPON,WEAPON_OFF,FOOD")
    eq(list[1].act.macrotext, "/use item:2862\n/use 16")
    eq(list[1].icon, "icon2862", "the icon is the stone it will use")
    eq(list[2].act.macrotext, "/use item:3239\n/use 17")
    ns.SetClassPref("main", 3239)
    eq(ns.Missing()[1].act.macrotext, "/use item:3239\n/use 16", "the player's pick comes first")
    W.items[3239] = 0
    eq(ns.Missing()[1].act.macrotext, "/use item:2862\n/use 16", "a pick that is used up falls back")
    eq(ns.WeaponPick("main", true), 2862)
end)

test("a rogue below 20 may use stones; poisons from 20, the picked poison first", function()
    Fake({ class = "ROGUE", level = 15, items = { [2862] = 1, [6947] = 2, [2892] = 2 }, sub = { [1] = 15 } })
    local ns = Load()
    eq(ns.Missing()[1].act.macrotext, "/use item:2862\n/use 16")
    W.level = 30
    eq(ns.Missing()[1].act.macrotext, "/use item:6947\n/use 16", "poisons before stones")
    ns.SetClassPref("main", 2892)
    eq(ns.Missing()[1].act.macrotext, "/use item:2892\n/use 16")
    ns.SetClassPref("weapon", false)
    eq(W.Keys(ns.Missing()), "")
end)

test("a shaman casts the imbue picked, else the best known", function()
    Fake({ class = "SHAMAN", known = { 8017, 8024, 324 }, auras = { "Spell324" } })
    local ns = Load()
    local m = ns.Missing()[1]
    eq(m.key, "WEAPON"); eq(m.act.spell, "Spell8024", "Flametongue before Rockbiter")
    ns.SetClassPref("imbue", 8017)
    eq(ns.Missing()[1].act.spell, "Spell8017")
    ns.SetClassPref("imbue", 8232) -- Windfury, not learned
    eq(ns.Missing()[1].act.spell, "Spell8024")
end)

test("a mage is told about a missing mana gem, a warlock about a healthstone", function()
    Fake({ class = "MAGE", known = { 759, 3552 } })
    local ns = Load()
    local m = ns.Missing()[1]
    eq(m.key, "GEM"); eq(m.act.spell, "Spell3552", "the best conjure spell known")
    W.items[5514] = 1
    eq(W.Keys(ns.Missing()), "", "any gem in the bags counts")
    W.items[5514] = 0
    ns.SetClassPref("gem", false)
    eq(W.Keys(ns.Missing()), "")
    Fake({ class = "WARLOCK", known = { 6201, 6202 }, shards = 5 })
    ns = Load()
    m = ns.Missing()[1]
    eq(m.key, "HEALTHSTONE"); eq(m.act.spell, "Spell6202")
    W.items[19005] = 1
    eq(W.Keys(ns.Missing()), "", "an improved healthstone counts too")
    Fake({ class = "WARLOCK", shards = 5 })
    eq(W.Keys(Load().Missing()), "", "nothing before the spell is learned")
end)

test("old weapon switches move into the class settings", function()
    Fake({ class = "SHAMAN", db = { weapon = false, anyWeapon = true, imbue = 8024 } })
    local ns = Load()
    eq(ns.db.weapon, nil); eq(ns.db.anyWeapon, nil); eq(ns.db.imbue, nil)
    eq(ns.ClassPref("weapon", "ROGUE"), false); eq(ns.ClassPref("weapon", "SHAMAN"), false)
    eq(ns.ClassPref("weapon", "WARRIOR"), true); eq(ns.ClassPref("imbue", "SHAMAN"), 8024)
    eq(ns.ClassPref("weapon", "MAGE"), true)
    Fake({ class = "ROGUE", db = { weapon = true, anyWeapon = false } })
    ns = Load()
    eq(ns.ClassPref("weapon"), true); eq(ns.ClassPref("weapon", "WARRIOR"), false)
end)

test("the window has no show switch and no move button: both are the hub's", function()
    Fake({ class = "PRIEST", known = { 588 } })
    local ns = Load()
    local f = ns.Window()
    eq(rawget(f, "move"), nil)
    for _, card in ipairs(f.cards) do
        for _, row in ipairs(card.rows or {}) do
            local label = row.label and row.label:GetText()
            assert(label ~= "Show the panel" and label ~= "Position", "found " .. tostring(label))
        end
    end
end)

test("the food and weapon picks show the item they use", function()
    Fake({ class = "WARRIOR", items = { [13928] = 1, [2862] = 1 }, sub = { [1] = 7 } })
    local ns = Load()
    local f = ns.Window()
    eq(f.tiles.food.shown, 13928, "the best food in the bags, as the automatic pick")
    eq(f.tiles.food.mine, false)
    ns.SetPref("foodItem", 21023)
    f.tiles.food:Refresh()
    eq(f.tiles.food.shown, 21023); eq(f.tiles.food.mine, true)
    eq(f.tiles.main.shown, 2862)
    -- An item dropped on a pick becomes the pick.
    GetCursorInfo = function() return "item", 7964 end
    ClearCursor = function() end
    f.tiles.main:GetScript("OnReceiveDrag")(f.tiles.main)
    eq(ns.ClassPref("main"), 7964); eq(f.tiles.main.shown, 7964)
    GetCursorInfo = nil
    f.tiles.main:GetScript("OnClick")(f.tiles.main, "RightButton")
    eq(ns.ClassPref("main"), nil, "right-click clears it")
end)

test("each icon has a short caption of its own under it: MH/OH and what goes on the weapon", function()
    Fake({ class = "ROGUE", level = 30, items = { [6949] = 3 } })
    local ns = Load()
    W.weapon = { false, 0, false, 0 }
    W.offHand = 50
    local list = ns.Missing()
    eq(ns.Caption(list[1]), "MH: poison")
    eq(ns.Caption(list[2]), "OH: poison")
    eq(ns.KitCaption("main", 2862, nil, "POISON"), "MH: stone")
    eq(ns.KitCaption("main", 20748, nil, "OIL"), "MH: oil")
    eq(ns.KitCaption("main", nil, 8232, "IMBUE"), "MH: imbue")
    eq(ns.KitCaption("off", nil, nil, "STONE_OIL"), "OH: stone")
    eq(ns.Caption({ key = "FOOD", text = ns.L.FOOD }), "Well Fed")
    eq(ns.Caption({ key = "BAGS", text = "Free bag slots: 2" }), "Bags")
    ns.SetPref("labels", true)
    ns.SetPref("vertical", false)
    ns.Refresh()
    ns.SetPref("vertical", true)
    ns.Refresh()
end)

test("the hub gets a summary, move and reset", function()
    Fake({ class = "PRIEST", known = { 588 } })
    local got
    GulliToolkit = { Register = function(m) got = m end }
    local ns = Load()
    eq(got.summary(), "Missing: 1")
    got.move(true)
    eq(ns.moving, true)
    got.move(false)
    local fr = got.frames[1]
    eq(fr.key, "panel"); eq(fr.get(), true)
    fr.set(false)
    eq(ns.db.show, false)
    assert(fr.frame(), "the hub gets the panel")
    ns.db.size = 60
    got.reset()
    eq(ns.db.size, 40); eq(ns.db.show, false); eq(ns.db.hudHidden, true)
    GulliToolkit = nil
end)

W.finish()
