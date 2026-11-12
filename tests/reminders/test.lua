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
    eq(#ns.Sample(), 2, "Fortitude and Inner Fire to place")
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

W.finish()
