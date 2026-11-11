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

test("the interval is a number of seconds between 0.5 and 60, a comma works too", function()
    Fake {}
    local ns = Load()
    eq(ns.Interval("2"), 2)
    eq(ns.Interval("0,5"), 0.5)
    eq(ns.Interval("0.1"), 0.5, "too short")
    eq(ns.Interval("600"), 60, "too long")
    eq(ns.Interval("abc"), nil, "not a number")
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
    eq(W.banners[1], "Found: Mor'Ladim", "screen warning")
    W.Ticker().fn()
    eq(#W.sounds, 1, "still in sight: no repeat")
    W.plates = {}
    W.Ticker().fn()
    W.plates = { { name = "Mor'Ladim", guid = "2" } }
    W.Ticker().fn()
    eq(#W.sounds, 2, "seen again after it was gone")
    eq(ns.lastFound.names[1], "Mor'Ladim")
end)

test("with repeat on, every scan with the mob in sight alerts", function()
    Fake { db = { names = { "Bob" }, enabled = true, again = true, banner = false },
           plates = { { name = "Bob" } } }
    Load()
    Fire("PLAYER_LOGIN")
    W.Ticker().fn()
    W.Ticker().fn()
    eq(#W.sounds, 3, "login scan and two polls")
    eq(#W.banners, 0, "screen warning off")
end)

test("a new plate between polls alerts at once", function()
    Fake { db = { names = { "Bob" }, enabled = true } }
    Load()
    Fire("PLAYER_LOGIN")
    W.plates = { { name = "Bob" } }
    Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    eq(#W.sounds, 1)
end)

test("the switch starts and stops the timer at the saved interval, and turns on enemy plates", function()
    Fake { db = { names = { "Bob" }, interval = 5 } }
    local ns = Load()
    Fire("PLAYER_LOGIN")
    eq(W.Ticker(), nil, "off by default")
    ns.SetEnabled(true)
    eq(W.Ticker().seconds, 5)
    eq(W.cvars.nameplateShowEnemies, "1", "enemy plates on")
    ns.SetInterval("1,5")
    eq(W.Ticker().seconds, 1.5, "restarted at the new interval")
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
    SlashCmdList.GULLIMOBFINDER("on")
    eq(GulliMobFinderDB.enabled, true)
    SlashCmdList.GULLIMOBFINDER("clear")
    eq(#GulliMobFinderDB.names, 0)
    W.target = { name = "Gulliby", player = true }
    eq(ns.AddTarget(), nil, "players are not added")
end)

test("the window builds and shows the saved settings", function()
    Fake { db = { names = { "Bob", "Hogger" }, enabled = true } }
    local ns = Load()
    ns.Toggle()
    ns.Refresh()
end)

test("registers with Gulli Toolkit when the core is loaded", function()
    local got
    Fake { toolkit = { Register = function(m) got = m end } }
    local ns = Load()
    eq(got.key, "MobFinder")
    eq(got.title, "Mob Finder")
    eq(got.open, ns.Toggle)
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
