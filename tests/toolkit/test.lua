-- Run from the repository root: lua5.1 tests/toolkit/test.lua
local W = dofile("tests/toolkit/wow.lua")
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

local function byKey(rows)
    local t = {}
    for _, r in ipairs(rows) do t[r.key] = r end
    return t
end

local QC = { name = "Gulli-QuestCleaner", enabled = true, loaded = true,
             meta = { ["X-Gulli-Module"] = "QuestCleaner", Title = "|cff9ad0ffGulli|r-QuestCleaner" } }

test("a module registers with . and with :", function()
    Fake({})
    Load()
    assert(GulliToolkit.Register({ key = "A", open = function() end }))
    assert(GulliToolkit:Register({ key = "B", open = function() end }))
    assert(GulliToolkit.modules.A and GulliToolkit.modules.B)
    eq(GulliToolkit.Register({ open = function() end }), false, "a module without a key")
end)

test("known modules are listed first, also when not installed", function()
    Fake({ addons = { { name = "Other", enabled = true, loaded = true } } })
    local ns = Load()
    local rows = ns.List()
    eq(rows[1].key, "QuestCleaner")
    eq(rows[2].key, "MobFinder")
    eq(rows[3].key, "GroupBuffs")
    eq(#rows, 3, "an addon that is not a Gulli module is not listed")
    eq(rows[2].state, "missing")
    eq(rows[2].title, "Mob Finder")
end)

test("a registered module is ready, a disabled one is off, an unknown module is listed after", function()
    Fake({ addons = { QC,
        { name = "Gulli-MobFinder", enabled = false, meta = { ["X-Gulli-Module"] = "MobFinder" } },
        { name = "Gulli-Zeta", enabled = true, loaded = true, meta = { ["X-Gulli-Module"] = "Zeta", Title = "|cffffffffGulli|r-Zeta" } } } })
    local ns = Load()
    GulliToolkit.Register({ key = "QuestCleaner", open = function() end, slash = "/gqc" })
    local rows = ns.List()
    local r = byKey(rows)
    eq(r.QuestCleaner.state, "ready")
    eq(r.QuestCleaner.slash, "/gqc")
    eq(r.MobFinder.state, "off")
    eq(r.GroupBuffs.state, "missing")
    eq(rows[4].key, "Zeta")
    eq(r.Zeta.title, "Gulli-Zeta", "the title from the TOC without colour codes")
end)

test("switching a module waits for a reload", function()
    Fake({ addons = { QC, { name = "Gulli-MobFinder", enabled = false, meta = { ["X-Gulli-Module"] = "MobFinder" } } } })
    local ns = Load()
    GulliToolkit.Register({ key = "QuestCleaner", open = function() end })
    local r = byKey(ns.List())
    ns.SetEnabled(r.MobFinder, true)
    eq(W.addons[2].enabled, true, "enabled in the addon list")
    assert(ns.NeedsReload())
    eq(byKey(ns.List()).MobFinder.state, "reload")
    ns.SetEnabled(byKey(ns.List()).MobFinder, false)
    eq(ns.NeedsReload(), false, "switching back needs no reload")
    ns.SetEnabled(r.QuestCleaner, false)
    eq(W.addons[1].enabled, false)
    eq(byKey(ns.List()).QuestCleaner.on, false)
    assert(ns.NeedsReload())
end)

test("/gulli opens the hub, /gulli <module> opens the module", function()
    Fake({ addons = { QC } })
    local ns = Load()
    local opened = 0
    GulliToolkit.Register({ key = "QuestCleaner", open = function() opened = opened + 1 end })
    SlashCmdList.GULLITOOLKIT("questcleaner")
    eq(opened, 1)
    SlashCmdList.GULLITOOLKIT("  QuestCleaner ")
    eq(opened, 2)
    SlashCmdList.GULLITOOLKIT("nothing")
    assert(W.printed[1]:find("nothing", 1, true), "says the module is unknown")
    SlashCmdList.GULLITOOLKIT("")
    local hub
    for _, f in ipairs(W.frames) do if rawget(f, "_OnShow") then hub = f end end
    assert(hub and hub:IsShown(), "the hub window is open")
    GulliToolkit_Toggle()
    eq(hub:IsShown(), false, "the compartment button closes it again")
end)

test("the hub window builds its rows", function()
    Fake({ addons = { QC } })
    local ns = Load()
    GulliToolkit.Register({ key = "QuestCleaner", open = function() end })
    ns.Toggle()
    ns.Refresh()
    GulliToolkit.Register({ key = "Late", open = function() end })
    eq(#ns.List(), 4)
end)

test("every language has every key, with the same placeholders", function()
    Fake({})
    local ns = Load()
    for _, tag in ipairs(ns.TAGS) do
        local t = ns.T[tag]
        assert(t, "no table for " .. tag)
        for key, text in pairs(ns.T.en) do
            assert(t[key], tag .. " misses " .. key)
            for _, p in ipairs({ "%%d", "%%s" }) do
                local _, a = text:gsub(p, "")
                local _, b = t[key]:gsub(p, "")
                assert(a == b, tag .. "." .. key .. " placeholders differ")
            end
        end
        for key in pairs(t) do assert(ns.T.en[key], tag .. " has an extra key " .. key) end
    end
end)

test("the client language picks the table, English is the fallback", function()
    Fake({ locale = "ruRU" })
    local ns = Load()
    eq(ns.L.OPEN, "Открыть")
    Fake({ locale = "koKR" })
    ns = Load()
    eq(ns.L.OPEN, "Open")
end)

io.write(string.format("%d/%d passed\n", count - failed, count))
os.exit(failed == 0 and 0 or 1)
