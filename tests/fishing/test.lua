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
    assert(told[1][2]:find("next cast"), "the next cast puts it on")
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
    W.Fire("PLAYER_LOGOUT")
    W.Fire("PLAYER_ENTERING_WORLD", true, false)
    eq(ns.s.catches, 1, "a quick relog keeps the session")
    W.now = W.now + ns.Skin.RELOG_KEEP + 1
    W.Fire("PLAYER_ENTERING_WORLD", true, false)
    eq(ns.s.catches, 0)
    eq(ns.Summary(), nil)
end)

test("the window builds and its strip says what to do now", function()
    Fake({ bags = { [BAUBLE] = 1 }, interact = "F" })
    local ns = Load()
    local L = ns.L
    ns.Toggle()
    assert(ns.Window(), "a window")
    local title, sub, tone = ns.Status()
    eq(title, L.STATUS_READY); eq(tone, "good")
    assert(sub:find("Double right%-click casts") and sub:find("F reels in"), sub)
    eq(ns.LureText(), L.NO_LURE)
    W.lureLeft = 600
    eq(ns.LureText(), "10 min")
    ns.SetPref("cast", false)
    eq((ns.Status()), L.STATUS_NO_WAY, "no double-click and no key")
    ns.SetCastKey("F9")
    title, sub = ns.Status()
    eq(title, L.STATUS_READY)
    assert(sub:find("F9 casts"), sub)
    ns.SetPref("cast", true)
    assert(select(2, ns.Status()):find("Double right%-click or F9 casts"))
    W.pole = false
    eq((ns.Status()), L.STATUS_POLE)
    W.spells = {}
    eq((ns.Status()), L.STATE_NO_SKILL)
    ns.Pause(true)
    eq((ns.Status()), L.STATE_PAUSED)
end)

test("the steps show the pole, the keys and what is missing", function()
    Fake({ pole = false, slots = { [0] = { 2131 }, [5] = { 6256 } }, interact = "F" })
    local ns = Load()
    local st = ns.Steps()
    eq(#st, 3)
    eq(st[1].done, false); eq(st[1].state, "STEP_POLE_BAG"); eq(st[1].equip, 6256, "a pole in the reagent bag counts")
    eq(st[2].desc, "STEP_CAST_D"); eq(st[2].state, "STEP_CAST_NOKEY")
    eq(st[3].desc, "STEP_CATCH_D"); eq(st[3].arg, "F"); eq(st[3].state, nil)
    -- every text a step names exists
    for _, s in ipairs(st) do
        assert(ns.L["STEP_" .. s.key], s.key)
        assert(ns.L[s.desc or ("STEP_" .. s.key .. "_D")], "desc of " .. s.key)
        if s.state then assert(ns.L[s.state], s.state) end
    end
    -- Equip puts it in the hand, never in a fight
    W.combat = true
    eq(ns.EquipPole(), false)
    eq(#W.equipped, 0)
    W.combat = false
    eq(ns.EquipPole(), true)
    eq(W.equipped[1], 6256)
    st = ns.Steps()
    eq(st[1].done, true); eq(st[1].state, "STEP_POLE_OK"); eq(st[1].equip, nil)
    eq(ns.EquipPole(), false, "nothing to equip with the pole in hand")
    -- no pole anywhere, a key set, no Interact key
    Fake({ pole = false, db = { cast = false, castKey = "F9" } })
    ns = Load()
    st = ns.Steps()
    eq(st[1].state, "STEP_POLE_NONE")
    eq(st[2].desc, "STEP_CAST_KEY_D"); eq(st[2].state, "STEP_CAST_KEY"); eq(st[2].arg, "F9")
    eq(st[3].desc, "STEP_CATCH_CLICK_D"); eq(st[3].state, "STEP_CATCH_UNSET")
end)

test("the steps fold once something was caught, and open again on request", function()
    Fake({})
    local ns = Load()
    ns.Toggle()
    eq(ns.HowtoOpen(), true, "before the first catch")
    W.Catch({ { FISH, 1 } })
    eq(ns.HowtoOpen(), false)
    ns.howto = true
    eq(ns.HowtoOpen(), true)
end)

test("the cast key is bound only while fishing and casts like the double-click", function()
    Fake({ pole = false, bags = { [BAUBLE] = 1 } })
    local ns = Load()
    ns.SetCastKey("F9")
    eq(ns.db.castKey, "F9")
    eq(W.bindings.F9, nil, "no pole, no cast yet: the key stays the player's")
    W.pole = true
    W.Fire("PLAYER_EQUIPMENT_CHANGED", 16)
    local b = W.bindings.F9
    assert(b, "bound with the pole in hand")
    eq(b.name, "GulliFishingKey")
    -- before each press the button takes the next action: the lure first, then the cast
    local key = ns.KeyCastButton()
    key._PreClick(key)
    eq(key:GetAttribute("type"), "item")
    eq(key:GetAttribute("item"), "item:" .. BAUBLE)
    W.lureLeft = 600
    key._PreClick(key)
    eq(key:GetAttribute("type"), "spell")
    eq(key:GetAttribute("spell"), "Fishing7620")
    -- the double-click's own binding comes and goes without touching the key
    W.Press(10); W.Press(10.1)
    assert(W.bindings.BUTTON2 and W.bindings.F9)
    ns.Disarm()
    eq(W.bindings.BUTTON2, nil)
    assert(W.bindings.F9, "the key stays")
    -- the pole goes away: the key is free again
    W.pole = false
    W.Fire("PLAYER_EQUIPMENT_CHANGED", 16)
    eq(W.bindings.F9, nil)
    -- in a fight nothing is bound; it comes after the fight
    W.pole, W.combat = true, true
    W.Fire("PLAYER_EQUIPMENT_CHANGED", 16)
    eq(W.bindings.F9, nil)
    W.combat = false
    W.Fire("PLAYER_REGEN_ENABLED")
    assert(W.bindings.F9)
    -- paused: free; a cleared key: free
    ns.Pause(true)
    eq(W.bindings.F9, nil)
    ns.Pause(false)
    assert(W.bindings.F9)
    ns.SetCastKey(nil)
    eq(W.bindings.F9, nil)
    eq(ns.db.castKey, nil)
end)

test("the bar shows the cast, the catch, then asks for the next cast, and hides", function()
    Fake({ channel = 20, skill = { 187, 225 } })
    local ns = Load()
    W.now = 1000
    eq(ns.BarState(), nil, "nothing before the first cast")
    W.Cast()
    eq(ns.BarState(), "cast")
    local v = ns.BarView("cast", 1005)
    eq(v.right, "15 s"); eq(v.frac, 0.75); eq(v.low, false)
    v = ns.BarView("cast", 1017)
    eq(v.right, "3 s"); eq(v.low, true, "the last seconds warn")
    assert(ns.BarFrame():IsShown(), "the bar is on the screen")
    W.now = 1012
    W.Catch({ { FISH, 2 } })
    W.Stop()
    eq(ns.BarState(), "got")
    v = ns.BarView("got")
    eq(v.name, "Item" .. FISH); eq(v.right, "+2")
    W.now = 1012 + ns.BAR_GOT + 0.1
    eq(ns.BarState(), "idle")
    eq(ns.BarView("idle").name, ns.L.BAR_AGAIN)
    W.now = 1012 + ns.BAR_IDLE + 0.1
    eq(ns.BarState(), nil)
    ns.TickBar()
    eq(ns.BarFrame():IsShown(), false, "the bar went away")
    -- a cast that ran out without a catch
    W.Cast(); W.now = W.now + 20; W.Stop()
    eq(ns.BarState(), "idle")
    -- the game gave no times: the bar still runs
    W.channel = nil
    W.Cast()
    eq(ns.BarState(), "cast")
    eq(ns.cast.finish - ns.cast.start, ns.CHANNEL)
    eq((ns.SkillText()), "187/225")
end)

test("the bar's switch and the pause keep it off the screen; Unlock shows it to place", function()
    Fake({ channel = 20 })
    local reg
    GulliToolkit = { Register = function(t) reg = t end }
    local ns = Load()
    GulliToolkit = nil
    eq(ns.db.bar, true, "the bar starts shown (owner's decision)")
    eq(#reg.frames, 1)
    local fr = reg.frames[1]
    eq(fr.get(), true)
    fr.set(false)
    eq(ns.db.bar, false)
    W.Cast()
    eq(ns.BarState(), nil, "the switch is off")
    reg.move(true)
    assert(fr.frame():IsShown(), "shown in the Unlock mode")
    reg.move(false)
    eq(fr.frame():IsShown(), false)
    fr.set(true)
    W.Cast()
    eq(ns.BarState(), "cast")
    reg.pause(true)
    eq(ns.BarState(), nil, "paused")
    eq(fr.frame():IsShown(), false)
end)

test("the game's cast bar hides only while a cast runs and the switch is on", function()
    Fake({ channel = 20 })
    local ns = Load()
    local alpha = 1
    PlayerCastingBarFrame = { GetAlpha = function() return alpha end, SetAlpha = function(_, a) alpha = a end }
    W.Cast()
    ns.TickBar()
    eq(alpha, 0)
    W.Stop()
    W.now = W.now + 2
    W.RunTimers()
    eq(alpha, 1, "back after the cast")
    ns.SetPref("hideCast", false)
    W.Cast()
    ns.TickBar()
    eq(alpha, 1, "the switch is off")
    PlayerCastingBarFrame = nil
end)

test("fishing time counts casts and catches without the breaks", function()
    Fake({})
    local ns = Load()
    W.now = 1000; W.Cast()
    W.now = 1020; W.Catch({ { FISH, 1 } })
    W.now = 1030; W.Cast()
    W.now = 1050; W.Catch({ { FISH, 1 } })
    eq(ns.s.secs, 50)
    eq(ns.PerHour(), nil, "too little to tell")
    W.now = 2000; W.Cast()
    eq(ns.s.secs, 50, "a break is not fishing time")
    for i = 1, 5 do
        W.now = W.now + 20; W.Catch({ { FISH, 1 } })
        W.now = W.now + 5; W.Cast()
    end
    eq(ns.s.secs, 175)
    eq(ns.PerHour(), 144)
    eq(ns.SessionLine(), ns.L.FOOT_SUM:format(7, "3 min"))
    ns.Start()
    eq(ns.SessionLine(), ns.L.FOOT_NONE)
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
    ns.SetCastKey("F9")
    ns.db.barPoint = { "CENTER", "CENTER", 0, 0 }
    reg.reset()
    eq(ns.db.mute, false)
    eq(ns.db.castKey, nil, "the cast key goes back to none")
    eq(ns.db.barPoint, nil, "the bar goes back to its place")
    eq(ns.db.bar, true)
    reg.pause(true)
    eq(ns.paused, true)
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
        assert(type(o.label) == "string" and type(o.desc) == "string" and o.icon, "texts and icon for " .. o.key)
        assert(not seen[o.key], "one row per key"); seen[o.key] = true
        o.set(true); eq(ns.db[o.key], true, o.key .. " on"); eq(o.get(), true)
        o.set(false); eq(ns.db[o.key], false, o.key .. " off"); eq(o.get(), false)
    end
    assert(seen.cast and seen.loud and seen.loot)
end)

W.finish()
