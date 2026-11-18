-- Run from the repository root: lua5.1 tests/mobfinder/test.lua
local W = dofile("tests/mobfinder/wow.lua")
local failed, count = 0, 0

local function test(name, fn)
    count = count + 1
    local ok, err = pcall(fn)
    if ok then
        io.write("ok   ", name, "\n")
    else
        failed = failed + 1
        io.write("FAIL ", name, "\n     ", tostring(err), "\n")
    end
end

local function eq(a, b, what)
    if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local function names(found)
    local t = {}
    for _, h in ipairs(found) do t[#t + 1] = h.name end
    return table.concat(t, ",")
end

test("the list: one name per line, trimmed, no blanks or repeats", function()
    Fake {}
    local ns = Load()
    local list = ns.ParseNames("  Mor'Ladim \n\n\r\nmor'ladim\r\nOld Murk-Eye\n")
    eq(table.concat(list, "|"), "Mor'Ladim|Old Murk-Eye")
    eq(#ns.ParseNames(""), 0, "empty text")
end)

test("a name matches by any part, in any case, also in Cyrillic", function()
    Fake {}
    local ns = Load()
    eq(ns.Match("Mor'Ladim", { "ladim" }), "ladim")
    eq(ns.Match("Old Murk-Eye", { "Bob", "OLD MURK" }), "OLD MURK")
    eq(ns.Match("Кабан-Хряк", { "кабан" }), "кабан", "Cyrillic upper and lower")
    eq(ns.Match("Ёжик", { "ёж" }), "ёж", "Ё")
    eq(ns.Match("Defias Thug", { "Murloc" }), nil, "no match")
end)

test("scan finds the living mobs on the list, skips the dead and secret names", function()
    Fake { plates = {
        { name = "Defias Thug", guid = "1" },
        { name = "Mor'Ladim", guid = "2" },
        { name = "Mor'Ladim", guid = "3", dead = true },
        { secret = true, guid = "4" },
    } }
    local ns = Load()
    eq(names(ns.Scan({ "mor'ladim" })), "Mor'Ladim")
    eq(#ns.Scan({}), 0, "empty list")
end)

test("a mob alerts once when it appears, and again after it was gone", function()
    Fake { db = { names = { "Mor'Ladim" }, enabled = true, sound = "READY_CHECK" } }
    local ns = Load()
    Fire("PLAYER_LOGIN")
    eq(#W.sounds, 0, "nothing in sight")
    W.plates = { { name = "Mor'Ladim", guid = "2" } }
    W.Ticker().fn()
    eq(#W.sounds, 1, "first sight")
    eq(W.sounds[1].id, 8960, "the chosen sound")
    eq(W.sounds[1].channel, "Master", "plays even with effects muted")
    eq(#W.banners, 0, "no screen warning any more")
    W.Ticker().fn()
    eq(#W.sounds, 1, "still in sight: no repeat")
    W.plates = {}
    W.Ticker().fn()
    W.plates = { { name = "Mor'Ladim", guid = "2" } }
    W.Ticker().fn()
    eq(#W.sounds, 1, "back within the cooldown: quiet")
    W.plates = {}
    W.Ticker().fn()
    W.now = W.now + 61
    W.plates = { { name = "Mor'Ladim", guid = "2" } }
    W.Ticker().fn()
    eq(#W.sounds, 2, "seen again after it was gone and the cooldown passed")
    eq(ns.lastFound.names[1], "Mor'Ladim")
end)

test("settings of older versions are dropped and no longer change the search", function()
    Fake { resting = true, combat = false,
           db = { names = { "Bob" }, enabled = true, again = true, banner = true, interval = 30, cooldown = 0,
                  quietRest = true, card = false, mark = true, sources = false, vignettes = false,
                  skipTapped = false, share = false },
           plates = { { name = "Bob", guid = "G" } } }
    local ns = Load()
    Fire("PLAYER_LOGIN")
    for _, k in ipairs({ "again", "banner", "interval", "cooldown", "quietRest", "card", "mark", "sources",
                         "vignettes", "skipTapped", "share" }) do
        eq(GulliMobFinderDB[k], nil, k .. " is gone")
    end
    eq(W.Ticker().seconds, 2, "a look every 2 seconds")
    eq(#W.sounds, 1, "the sound plays in a town too")
    W.Ticker().fn()
    W.Ticker().fn()
    eq(#W.sounds, 1, "a mob that stays in sight alerts once")
    eq(W.marks.nameplate1, nil, "no skull")
    assert(W.named.GulliMobFinderCard:IsShown(), "the card always shows")
    eq(ns.db.enabled, true)
end)

test("a new player starts with the search on", function()
    Fake {}
    local ns = Load()
    Fire("PLAYER_LOGIN")
    eq(ns.db.enabled, true)
    eq(ns.db.flash, true)
    eq(ns.db.repeatSound, false)
end)

test("a paused module looks for nothing, hears no shared finds, and starts again at once", function()
    local got
    Fake { toolkit = { Register = function(m) got = m end },
           db = { names = { "Bob" }, enabled = true }, plates = { { name = "Bob", guid = "G" } } }
    local ns = Load()
    Fire("PLAYER_LOGIN")
    eq(#W.sounds, 1)
    assert(got.pause, "the hub gets pause")
    got.pause(true)
    eq(W.Ticker(), nil, "the timer stopped")
    assert(not W.named.GulliMobFinderCard:IsShown(), "the card is hidden")
    W.plates = { { name = "Bob", guid = "H" } }
    Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    Fire("PLAYER_TARGET_CHANGED")
    eq(#W.sounds, 1, "no alert while paused")
    eq(ns.Receive("GulliMF", "F1\tAnn\t1431\t0.5\t0.25", "Ann-Realm"), nil, "no shared finds")
    eq(got.summary(), nil)
    got.pause(false)
    eq(W.Ticker().seconds, 2, "running again")
    eq(#W.sounds, 2, "the mob in sight alerts")
end)

test("a new plate between polls alerts at once", function()
    Fake { db = { names = { "Bob" }, enabled = true } }
    Load()
    Fire("PLAYER_LOGIN")
    W.plates = { { name = "Bob" } }
    Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    eq(#W.sounds, 1)
end)

test("the switch starts and stops the timer, and turns on enemy plates", function()
    Fake { db = { names = { "Bob" }, enabled = false } }
    local ns = Load()
    Fire("PLAYER_LOGIN")
    eq(W.Ticker(), nil, "a saved off stays off")
    ns.SetEnabled(true)
    eq(W.Ticker().seconds, 2)
    eq(W.cvars.nameplateShowEnemies, "1", "enemy plates on")
    ns.SetEnabled(false)
    eq(W.Ticker(), nil, "stopped")
    eq(GulliMobFinderDB.enabled, false, "saved")
end)

test("slash commands add names, the target, and switch the search", function()
    Fake { target = { name = "Hogger" } }
    local ns = Load()
    SlashCmdList.GULLIMOBFINDER("add Bob")
    SlashCmdList.GULLIMOBFINDER("add bob")
    SlashCmdList.GULLIMOBFINDER("target")
    eq(table.concat(GulliMobFinderDB.names, ","), "Bob,Hogger")
    SlashCmdList.GULLIMOBFINDER("target")
    eq(#GulliMobFinderDB.names, 2, "the target is added once")
    eq(ns.Info("Hogger").exact, true, "a mob from the target is looked for by its whole name")
    eq(ns.Info("Bob").exact, nil, "a typed name matches as a part")
    SlashCmdList.GULLIMOBFINDER("on")
    eq(GulliMobFinderDB.enabled, true)
    SlashCmdList.GULLIMOBFINDER("clear")
    eq(#GulliMobFinderDB.names, 0)
    W.target = { name = "Gulliby", player = true }
    eq(ns.AddTarget(), nil, "players are not added")
end)

test("players' pets, tagged mobs and switched-off entries do not alert; exact needs the whole name", function()
    Fake { plates = {
        { name = "Bob", guid = "1", pet = true },
        { name = "Bob", guid = "2", tapped = true },
        { name = "Bobby", guid = "3" },
    } }
    local ns = Load()
    eq(names(ns.Scan({ "Bob" })), "Bobby", "pet and tagged skipped")
    ns.Info("Bob").exact = true
    eq(#ns.Scan({ "Bob" }), 0, "exact: Bobby is not Bob")
    ns.Info("Bob").exact = nil
    ns.Info("Bob").off = true
    eq(#ns.Scan({ "Bob" }), 0, "off")
end)

test("a rare from the zone list is found by its npc id, in any client language", function()
    Fake { locale = "ruRU", plates = { { name = "Мор'Ладим", guid = "Creature-0-1-2-3-522-0000ABCD" } } }
    local ns = Load()
    ns.RARES = { [10] = { { 522, "Mor'Ladim", 35, 35, 1 } }, [12] = { { 99, "Hogger", 11, 11, 1 } } }
    eq(#ns.ZoneRares(), 1, "only the zone the player is in")
    eq(ns.AddZoneRares(), 1)
    eq(ns.AddZoneRares(), 0, "added once")
    local found = ns.Scan({})
    eq(names(found), "Мор'Ладим")
    eq(found[1].entry, "Mor'Ladim")
    eq(ns.NpcID("Player-1-0000"), nil, "not a creature")
end)

test("the generated data has rares with an id, a name and levels", function()
    Fake {}
    local ns = Load()
    local n = 0
    for area, list in pairs(ns.RARES) do
        assert(type(area) == "number")
        for _, r in ipairs(list) do
            assert(type(r[1]) == "number" and type(r[2]) == "string" and r[3] <= r[4], "bad rare in " .. area)
            n = n + 1
        end
    end
    assert(n > 100, "too few rares: " .. n)
end)

test("the minimap rare markers always count", function()
    Fake { vignettes = { { name = "Mor'Ladim", objectGUID = "Creature-0-1-2-3-522-01" } } }
    local ns = Load()
    eq(names(ns.Scan({ "Mor" })), "Mor'Ladim")
end)

test("a find goes into the history and the mob row, and is shared with the group", function()
    Fake { group = true, db = { names = { "Bob" }, enabled = true },
           plates = { { name = "Bob", guid = "G" } } }
    local ns = Load()
    Fire("PLAYER_LOGIN")
    local h = ns.db.history[1]
    eq(h.name, "Bob")
    eq(h.zone, "Duskwood")
    eq(h.x, 0.405)
    eq(ns.Info("Bob").count, 1)
    eq(W.addon[1][1], "GulliMF")
    eq(W.addon[1][2], "F1\tBob\t1431\t0.4050\t0.6025")
    eq(W.addon[1][3], "PARTY")
    eq(ns.Pin(h), true)
    eq(W.pins[1].map, 1431)
end)

test("a find shared by another player lands in the history; our own message does not", function()
    Fake {}
    local ns = Load()
    eq(ns.Receive("GulliMF", "F1\tBob\t1431\t0.5\t0.25", "Ann-Realm"), "Bob")
    eq(ns.db.history[1].who, "Ann")
    eq(ns.db.history[1].zone, "Duskwood")
    eq(ns.Receive("GulliMF", "X9\tsomething", "Ann"), nil, "unknown type")
    eq(ns.Receive("Other", "F1\tBob\t1\t0\t0", "Ann"), nil, "other prefix")
    eq(#ns.db.history, 1)
end)

test("Tell group writes the name, the zone and the coordinates, and needs a group", function()
    Fake {}
    local ns = Load()
    eq(ns.TellText("Bob"), "Bob in Duskwood at 40.5, 60.3")
    eq(ns.TellGroup("Bob"), false, "no group")
    W.group = true
    eq(ns.TellGroup("Bob"), true)
    eq(W.said[1][2], "PARTY")
    W.pos = nil
    eq(ns.TellText("Bob"), "Bob in Duskwood")
end)

test("the card's Target button gets a /targetexact macro out of combat, and waits in combat", function()
    Fake { db = { names = { "Bob" }, enabled = true }, plates = { { name = "Bob", guid = "G", level = 30, class = "rare" } } }
    local ns = Load()
    Fire("PLAYER_LOGIN")
    local btn = W.named.GulliMobFinderTarget
    assert(btn, "no Target button")
    eq(btn:GetAttribute("macrotext1") or btn:GetAttribute("macrotext"), "/targetexact Bob")
    assert(W.named.GulliMobFinderCard:IsShown(), "the card shows")
    W.combat = true
    W.now = W.now + 100
    W.plates = { { name = "Alice", guid = "H" } }
    ns.db.names = { "Bob", "Alice" }
    ns.Tick()
    eq(btn:GetAttribute("macrotext1") or btn:GetAttribute("macrotext"), "/targetexact Bob", "unchanged in combat")
    W.combat = false
    Fire("PLAYER_REGEN_ENABLED")
    eq(btn:GetAttribute("macrotext1") or btn:GetAttribute("macrotext"), "/targetexact Alice", "applied after combat")
end)

test("a secret level in combat shows the card without an error", function()
    Fake { db = { names = { "Bob" }, enabled = true }, plates = { { name = "Bob", guid = "G", level = W.SECRET_VALUE } } }
    Load()
    Fire("PLAYER_LOGIN")
    assert(W.named.GulliMobFinderCard:IsShown(), "the card shows")
end)

test("Alt+click on a mob or its corpse adds it by its whole name, with Undo; Tab never does", function()
    Fake { db = { names = {}, enabled = true } }
    local ns = Load()
    Fire("PLAYER_LOGIN")
    local mob = { name = "Hogger", guid = "Creature-0-1-2-3-448-01" }
    W.target, W.mouseover, W.alt = mob, nil, true
    Fire("PLAYER_TARGET_CHANGED")
    eq(#ns.db.names, 0, "a target taken without the mouse on it")
    W.mouseover, W.alt = mob, false
    Fire("PLAYER_TARGET_CHANGED")
    eq(#ns.db.names, 0, "a plain click")
    W.alt = true
    Fire("PLAYER_TARGET_CHANGED")
    eq(ns.db.names[1], "Hogger")
    eq(ns.Info("Hogger").exact, true)
    Fire("PLAYER_TARGET_CHANGED")
    eq(#ns.db.names, 1, "added once")
    -- The mob just added is in sight: it does not alert at once, another one of its name does.
    W.plates = { { name = "Hogger", guid = mob.guid } }
    ns.Tick()
    eq(#W.sounds, 0, "no alert for the mob the player just clicked")
    W.plates = { { name = "Hogger", guid = "Creature-0-1-2-3-448-02" } }
    ns.Tick()
    eq(#W.sounds, 1, "another Hogger alerts")
    eq(ns.RemoveName("hogger"), true, "Undo")
    eq(#ns.db.names, 0)
    eq(ns.db.mobs.hogger, nil)
    W.target = { name = "Gulliby", player = true }; W.mouseover = W.target
    Fire("PLAYER_TARGET_CHANGED")
    eq(#ns.db.names, 0, "players are not added")
end)

test("a paused module adds nothing on Alt+click and shows no menu entry", function()
    local got
    Fake { toolkit = { Register = function(m) got = m end }, db = { names = {}, enabled = true } }
    local ns = Load()
    Fire("PLAYER_LOGIN")
    got.pause(true)
    W.target = { name = "Hogger" }; W.mouseover, W.alt = W.target, true
    Fire("PLAYER_TARGET_CHANGED")
    eq(#ns.db.names, 0)
    eq(#W.OpenMenu("MENU_UNIT_TARGET", "target"), 0)
end)

test("the target's menu adds the mob, then offers to stop; not for players or secret names", function()
    Fake { db = { names = {}, enabled = true } }
    local ns = Load()
    Fire("PLAYER_LOGIN")
    eq(#W.OpenMenu("MENU_UNIT_TARGET", "target"), 0, "no target")
    W.target = { name = "Hogger", guid = "Creature-0-1-2-3-448-01" }
    local items = W.OpenMenu("MENU_UNIT_TARGET", "target")
    eq(#items, 1)
    eq(items[1].text, "Look for this mob")
    items[1].fn()
    eq(ns.db.names[1], "Hogger")
    items = W.OpenMenu("MENU_UNIT_FOCUS", "target")
    eq(items[1].text, "Stop looking for this mob")
    items[1].fn()
    eq(#ns.db.names, 0)
    W.target = { name = "Gulliby", player = true }
    eq(#W.OpenMenu("MENU_UNIT_TARGET", "target"), 0, "a player")
    W.target = { name = W.SECRET_VALUE }
    eq(#W.OpenMenu("MENU_UNIT_TARGET", "target"), 0, "a secret name")
end)

test("the target key binds to the Target button", function()
    Fake { db = { key = "F6" } }
    local ns = Load()
    Fire("PLAYER_LOGIN")
    eq(W.bindings.F6, "GulliMobFinderTarget")
end)

test("the summary counts the watched mobs, and says nothing when the search is off", function()
    local got
    Fake { toolkit = { Register = function(m) got = m end }, db = { names = { "Bob", "Ann" }, enabled = true } }
    Load()
    eq(got.summary(), "Looking for 2 mobs")
    GulliMobFinderDB.enabled = false
    eq(got.summary(), nil)
    assert(#got.options >= 1 and got.options[1].tip, "options with tips")
end)

test("the window builds and shows the saved settings", function()
    Fake { db = { names = { "Bob", "Hogger" }, enabled = true } }
    local ns = Load()
    for _, k in ipairs({ "SetInterval", "Interval", "Quiet" }) do eq(ns[k], nil, k .. " is gone") end
    ns.Toggle()
    ns.Refresh()
    ns.db.history = { { name = "Bob", zone = "Duskwood", t = 1000000, map = 1431, x = 0.5, y = 0.5, who = "Ann" } }
    ns.db.ids = { [522] = "Mor'Ladim" }
    for i = 1, 3 do if ns.ShowPage then ns.ShowPage(i) end; ns.Refresh() end
end)

test("registers with Gulli Toolkit when the core is loaded", function()
    local got
    Fake { toolkit = { Register = function(m) got = m end } }
    local ns = Load()
    eq(got.key, "MobFinder")
    eq(got.title, "Mob Finder")
    eq(got.open, ns.Toggle)
end)

test("the Unlock mode in a fight never shows or hides the card", function()
    local got
    Fake { toolkit = { Register = function(m) got = m end } }
    local ns = Load()
    local card = got.frames[1].frame()
    assert(card, "the hub gets the card")
    local calls = 0
    for _, k in ipairs({ "Show", "Hide", "SetShown" }) do rawset(card, k, function() calls = calls + 1 end) end
    W.combat = true
    got.move(true)
    got.move(false)
    eq(calls, 0, "the card holds a secure button: nothing in combat lockdown")
    W.combat = false
    got.move(true)
    assert(calls > 0, "out of a fight the card shows")
    got.move(false)
end)

test("every sound has a name and a fallback id", function()
    Fake {}
    local ns = Load()
    for _, s in ipairs(ns.SOUNDS) do
        assert(ns.T.en["SND_" .. s.key], "no name for " .. s.key)
        assert(type(s.id) == "number", "no id for " .. s.key)
    end
end)

test("every language has every key, with the same placeholders", function()
    Fake {}
    local ns = Load()
    for _, tag in ipairs(ns.TAGS) do
        local t = ns.T[tag]
        assert(t, "no table for " .. tag)
        for key, text in pairs(ns.T.en) do
            assert(t[key], tag .. " has no " .. key)
            for _, p in ipairs({ "%%d", "%%s" }) do
                local _, a = text:gsub(p, "")
                local _, b = t[key]:gsub(p, "")
                assert(a == b, tag .. "." .. key .. " has a different number of " .. p)
            end
        end
    end
end)

io.write(string.format("\n%d tests, %d failed\n", count, failed))
os.exit(failed == 0 and 0 or 1)
