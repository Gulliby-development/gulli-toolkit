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

test("nothing in combat, in towns, or when switched off", function()
    Fake({ class = "PRIEST", known = { 588 } })
    local ns = Load()
    W.combat = true
    eq(#ns.Missing(), 0)
    W.combat = false
    W.resting = true
    eq(#ns.Missing(), 0)
    ns.db.notResting = false
    eq(#ns.Missing(), 1)
    ns.db.buffs = false
    eq(#ns.Missing(), 0)
end)

test("the strip shows the icons and hides when nothing is missing", function()
    Fake({ class = "PRIEST", known = { 588 } })
    local ns = Load()
    eq(#ns.Refresh(), 1)
    W.auras = { "Spell588" }
    eq(#ns.Refresh(), 0)
    ns.Toggle()
end)

W.finish()
