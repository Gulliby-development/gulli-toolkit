-- Run from the repository root: lua5.1 tests/fishing/test.lua
local W = dofile("tests/fishing/wow.lua")
local test, eq = W.test, W.eq

local BAUBLE, ATTRACTOR, FISH = 6529, 6533, 6303

test("every language has every text", function()
    Fake({})
    W.CheckLocales(Load())
end)

test("a double right-click with a pole binds the click to Fishing", function()
    Fake({})
    local ns = Load()
    W.Press(10); W.Press(10.2)
    local b = W.bindings.BUTTON2
    assert(b, "the second release goes to the cast button")
    eq(b.name, "GulliFishingCast")
    eq(b.owner:GetAttribute("type"), "spell")
    eq(b.owner:GetAttribute("spell"), "Fishing7620")
    -- the click took the binding away again
    b.owner._PostClick(b.owner)
    eq(W.bindings.BUTTON2, nil)
    eq(ns.armed, nil)
end)

test("a slow second press, or a third, is no double-click", function()
    Fake({})
    Load()
    W.Press(10); W.Press(11)
    eq(W.bindings.BUTTON2, nil, "too slow")
    W.Press(11.1)
    assert(W.bindings.BUTTON2, "the slow press starts a new pair")
    W.bindings = {}
    W.Press(11.2)
    eq(W.bindings.BUTTON2, nil, "a third press starts again")
end)

test("no cast in a fight, mounted, on a unit, without the skill or the switch", function()
    for _, case in ipairs({
        { "in a fight", { combat = true } }, { "mounted", { mounted = true } },
        { "on a unit", { mouseover = true } }, { "no Fishing", { spells = {} } },
        { "switch off", { db = { cast = false } } }, { "no pole, no cast yet", { pole = false } },
    }) do
        Fake(case[2])
        Load()
        W.Press(10); W.Press(10.1)
        eq(W.bindings.BUTTON2, nil, case[1])
    end
end)

test("without a pole the double-click works for a while after a cast", function()
    Fake({ pole = false, spells = { [131474] = true } })
    local ns = Load()
    W.now = 100
    W.Cast(131474)
    W.Press(200); W.Press(200.1)
    assert(W.bindings.BUTTON2, "a recent cast")
    eq(W.bindings.BUTTON2.owner:GetAttribute("spell"), "Fishing131474", "the retail spell")
    ns.Disarm()
    W.Press(100 + ns.RECENT + 10); W.Press(100 + ns.RECENT + 10.1)
    eq(W.bindings.BUTTON2, nil, "too long ago")
end)

test("the double-click puts the best lure on a pole without one", function()
    Fake({ bags = { [BAUBLE] = 3, [ATTRACTOR] = 1 } })
    local ns = Load()
    W.Press(10); W.Press(10.1)
    local b = W.bindings.BUTTON2.owner
    eq(b:GetAttribute("type"), "item")
    eq(b:GetAttribute("item"), "item:" .. ATTRACTOR)
    eq(b:GetAttribute("target-slot"), 16)
    ns.Disarm()
    -- with a lure on, it casts
    W.lureLeft = 300
    W.Press(20); W.Press(20.1)
    eq(W.bindings.BUTTON2.owner:GetAttribute("type"), "spell")
    eq(b:GetAttribute("item"), nil)
    ns.Disarm()
    -- the switch off: it always casts
    W.lureLeft = 0
    ns.SetPref("lure", false)
    W.Press(30); W.Press(30.1)
    eq(W.bindings.BUTTON2.owner:GetAttribute("type"), "spell")
end)

test("a binding left without a click goes away, after the fight if there is one", function()
    Fake({})
    local ns = Load()
    W.Press(10); W.Press(10.1)
    W.combat = true
    W.now = 12
    W.RunTimers()
    assert(W.bindings.BUTTON2, "bindings do not change in a fight")
    W.combat = false
    W.Fire("PLAYER_REGEN_ENABLED")
    eq(W.bindings.BUTTON2, nil)
    eq(ns.armed, nil)
end)

test("the splash is loud while fishing and the sound comes back after", function()
    Fake({ db = { mute = true } })
    local ns = Load()
    W.now = 100
    W.Cast()
    eq(W.cvars.Sound_SFXVolume, "1")
    eq(W.cvars.Sound_MasterVolume, "0.8", "the master volume up to 0.8")
    eq(W.cvars.Sound_EnableSoundWhenGameIsInBG, "1")
    eq(W.cvars.Sound_MusicVolume, "0", "mute is on")
    eq(W.cvars.SoftTargetInteract, "3")
    -- a second cast keeps the player's own values, not the loud ones
    W.Cast()
    eq(ns.db.saved.Sound_SFXVolume, "0.4")
    -- a cast a moment ago: the timer of the first cast leaves the sound loud
    W.now = 110; W.Cast()
    W.now = 125; W.RunTimers()
    eq(W.cvars.Sound_SFXVolume, "1", "still fishing")
    W.now = 131; W.RunTimers()
    eq(W.cvars.Sound_SFXVolume, "0.4")
    eq(W.cvars.Sound_MasterVolume, "0.5")
    eq(W.cvars.Sound_MusicVolume, "0.6")
    eq(W.cvars.SoftTargetInteract, "0")
    eq(ns.db.saved, nil)
end)

test("a louder master volume stays, and the switches choose what changes", function()
    Fake({ db = { interact = false } })
    local ns = Load()
    W.cvars.Sound_MasterVolume = "1"
    W.Cast()
    eq(W.cvars.Sound_MasterVolume, "1")
    eq(W.cvars.Sound_MusicVolume, "0.6", "mute is off by default")
    eq(W.cvars.SoftTargetInteract, "0", "interact is off")
    ns.SetPref("loud", false)
    eq(W.cvars.Sound_SFXVolume, "0.4", "turning loud off while fishing puts it back")
end)

test("the sound comes back at logout, after a crash, after a fight and on pause", function()
    Fake({})
    local ns = Load()
    W.Cast()
    W.Fire("PLAYER_LOGOUT")
    eq(W.cvars.Sound_SFXVolume, "0.4", "logout")
    -- a crash: the next load finds the saved values
    W.Cast()
    local saved = ns.db
    Fake({ db = saved, cvars = W.cvars })
    Load()
    eq(W.cvars.Sound_SFXVolume, "0.4", "next login")
    eq(saved.saved, nil)
    -- in a fight it waits
    ns = Load()
    W.Cast()
    W.combat = true
    ns.Restore()
    eq(W.cvars.Sound_SFXVolume, "1")
    W.combat = false
    W.Fire("PLAYER_REGEN_ENABLED")
    eq(W.cvars.Sound_SFXVolume, "0.4", "after the fight")
    -- the hub's pause
    W.Cast()
    ns.Pause(true)
    eq(W.cvars.Sound_SFXVolume, "0.4", "pause")
end)

test("a paused module casts, loots and changes nothing", function()
    Fake({})
    local ns = Load()
    ns.Pause(true)
    W.Press(10); W.Press(10.1)
    eq(W.bindings.BUTTON2, nil, "no double-click")
    W.Cast()
    eq(W.cvars.Sound_SFXVolume, "0.4", "no sound change")
    W.Catch({ { FISH, 1 } })
    eq(#W.looted, 0, "no loot")
    eq(ns.s.catches, 0)
    ns.Pause(false)
    W.Press(20); W.Press(20.1)
    assert(W.bindings.BUTTON2, "back on")
end)

test("fishing loot is taken and counted; other loot is left alone", function()
    Fake({})
    local ns = Load()
    W.Catch({ { FISH, 1 }, { 2, 3 } })
    eq(#W.looted, 2)
    eq(ns.s.catches, 1)
    eq(ns.s.items[FISH], 1)
    eq(ns.s.items[2], 3)
    W.looted = {}
    W.fishing = false
    W.Catch({ { 7, 1 } })
    eq(#W.looted, 0, "a mob's loot")
    eq(ns.s.catches, 1)
    -- the game loots by itself: counted, not looted twice
    W.fishing = true
    W.Catch({ { FISH, 2 } }, true)
    eq(#W.looted, 0)
    eq(ns.s.items[FISH], 3)
    -- LOOT_READY twice for one window counts once
    W.loot = { { FISH, 1 } }
    W.Fire("LOOT_READY"); W.Fire("LOOT_READY"); W.Fire("LOOT_CLOSED")
    eq(ns.s.catches, 3)
    -- the switch off: counted, not looted
    W.looted = {}
    ns.SetPref("loot", false)
    W.Catch({ { FISH, 1 } })
    eq(#W.looted, 0)
    eq(ns.s.catches, 4)
    eq(ns.Caught()[1].id, FISH)
    assert(ns.Summary():find("4", 1, true))
end)

test("a missing lure is told once, and again after the next one ran out", function()
    Fake({ bags = { [BAUBLE] = 2 } })
    local ns = Load()
    local told = {}
    ns.OnLureMissing = function(id, text) told[#told + 1] = { id, text } end
    W.Cast()
    eq(#told, 1)
    eq(told[1][1], BAUBLE)
    assert(told[1][2]:find("Double%-click"), "names the double-click")
    W.Cast()
    eq(#told, 1, "once")
    W.lureLeft = 600
    W.Cast()
    W.lureLeft = 0
    W.Cast()
    eq(#told, 2, "the lure ran out")
    -- no lure in the bags: nothing to say
    W.bags = {}
    ns.told = nil
    W.Cast()
    eq(#told, 2)
    -- the switch off
    W.bags = { [BAUBLE] = 1 }
    ns.SetPref("remind", false)
    W.Cast()
    eq(#told, 2)
    -- without the double-click it says to put it on by hand
    ns.SetPref("remind", true)
    ns.SetPref("cast", false)
    W.Cast()
    assert(told[3][2]:find("Put on"), told[3][2])
end)

test("a real login starts a new session, a reload keeps it", function()
    Fake({})
    local ns = Load()
    W.Catch({ { FISH, 1 } })
    W.Fire("PLAYER_ENTERING_WORLD", false, true)
    eq(ns.s.catches, 1)
    W.Fire("PLAYER_ENTERING_WORLD", true, false)
    eq(ns.s.catches, 0)
    eq(ns.Summary(), nil)
end)

test("the window builds and shows the state", function()
    Fake({ bags = { [BAUBLE] = 1 } })
    local ns = Load()
    ns.Toggle()
    assert(ns.Window(), "a window")
    eq(ns.StateText(), ns.L.STATE_READY)
    eq(ns.LureText(), ns.L.NO_LURE)
    W.lureLeft = 600
    eq(ns.LureText(), "10 min")
    ns.SetPref("cast", false)
    eq(ns.StateText(), ns.L.STATE_OFF)
    W.pole = false
    ns.SetPref("cast", true)
    eq(ns.StateText(), ns.L.STATE_NO_POLE)
end)

test("the hub gets the module's window, pause, reset and switches", function()
    Fake({})
    local reg
    GulliToolkit = { Register = function(t) reg = t end }
    local ns = Load()
    eq(reg.key, "Fishing")
    assert(reg.window() == ns.Window())
    assert(#reg.options <= 6)
    for _, o in ipairs(reg.options) do assert(o.icon and o.label and o.get() == true, o.label) end
    ns.db.mute = true
    reg.reset()
    eq(ns.db.mute, false)
    reg.pause(true)
    eq(ns.paused, true)
end)

W.finish()
