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
    eq(#rows, #ns.KNOWN, "an addon that is not a Gulli module is not listed")
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
    eq(rows[#ns.KNOWN + 1].key, "Zeta")
    eq(r.Zeta.title, "Gulli-Zeta", "the title from the TOC without colour codes")
end)

test("switching a module waits for a reload", function()
    Fake({ addons = { QC, { name = "Gulli-MobFinder", enabled = false, meta = { ["X-Gulli-Module"] = "MobFinder" } } } })
    local ns = Load()
    GulliToolkit.Register({ key = "QuestCleaner", open = function() end })
    local r = byKey(ns.List())
    ns.SetEnabled(r.MobFinder, true)
    eq(W.addons[2].enabled, true, "enabled in the addon list")
    eq(W.unsaved, false, "the change is saved at once, so the reload keeps it")
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
    eq(#ns.List(), #ns.KNOWN + 1)
end)

test("the hub fits the screen: it shrinks on a small one, the module list scrolls", function()
    Fake({})
    local ns = Load()
    eq(ns.HubScale(1, 1920, 1080, 940, 580), 1, "full size on a big screen")
    local s = ns.HubScale(1, 800, 480, 940, 580)
    assert(940 * s <= 800 * 0.96 + 0.01 and 580 * s <= 480 * 0.9 + 0.01, "fits a handheld: " .. s)
    eq(ns.HubScale(5, 1920, 1080, 940, 580), 1.3, "the player's scale is capped")
    eq(ns.HubScale(nil, 1920, 1080, 940, 580), 1)
    assert(580 * ns.HubScale(1, 1024, 768, 940, 580) <= 768 * 0.85 + 1, "fits 85% of a 768 high screen")
end)

test("categories: known modules have one, others name one, the rest are Other", function()
    Fake({ addons = { QC,
        { name = "Gulli-Zeta", enabled = true, loaded = true, meta = { ["X-Gulli-Module"] = "Zeta", ["X-Gulli-Category"] = "Items" } },
        { name = "Gulli-Eta", enabled = true, loaded = true, meta = { ["X-Gulli-Module"] = "Eta", ["X-Gulli-Category"] = "Nope" } } } })
    local ns = Load()
    GulliToolkit.Register({ key = "Late", open = function() end, category = "Social" })
    local r = byKey(ns.List())
    eq(r.QuestCleaner.category, "Quests")
    eq(r.Zeta.category, "Items", "from the TOC")
    eq(r.Eta.category, "Other", "an unknown category")
    eq(r.Late.category, "Social", "from Register")
    for _, k in ipairs(ns.KNOWN) do
        assert(ns.CATEGORY_OF[k], k .. " has no category")
        assert(ns.T.en["CAT_" .. ns.CATEGORY_OF[k]], "no text for its category")
    end
    local groups = ns.Groups(ns.List())
    eq(groups[1].key, "Quests", "sidebar order")
    eq(groups[#groups].key, "Other", "Other last")
end)

test("counts, the On/Off filter and the search", function()
    Fake({ addons = { QC, { name = "Gulli-Merchant", enabled = false, meta = { ["X-Gulli-Module"] = "Merchant" } } } })
    local ns = Load()
    GulliToolkit.Register({ key = "QuestCleaner", open = function() end, slash = "/gqc" })
    local rows = ns.List()
    local c = ns.Counts(rows)
    eq(c.All.total, #ns.KNOWN)
    eq(c.All.on, 1)
    eq(c.Quests.on, 1)
    eq(c.Items.on, 0)
    eq(#ns.Filter(rows, "Quests", "all", ""), 3)
    eq(#ns.Filter(rows, "All", "on", ""), 1)
    eq(#ns.Filter(rows, "Quests", "off", ""), 2)
    eq(ns.Filter(rows, "All", "all", "  GQC ")[1].key, "QuestCleaner", "by slash, any case")
    eq(ns.Filter(rows, "Items", "all", "sells gray")[1].key, "Merchant", "by the line about it")
    eq(ns.Filter(rows, "Social", "all", "quest cleaner")[1].key, "QuestCleaner", "a search looks in every category")
    eq(#ns.Filter(rows, "All", "all", "zzz"), 0)
end)

test("a module's options: only valid ones, and the search finds a module by them", function()
    Fake({ addons = { QC } })
    local ns = Load()
    local db = { sell = true }
    GulliToolkit.Register({ key = "QuestCleaner", open = function() end, options = {
        { label = "Sell", get = function() return db.sell end, set = function(on) db.sell = on end,
          icon = "Interface\\Icons\\INV_Misc_Coin_02", tip = "Sells junk at a vendor" },
        { label = "Broken" }, "nonsense" } })
    local row = byKey(ns.List()).QuestCleaner
    eq(#row.options, 1, "only options with a label, get and set")
    eq(row.options[1].icon, "Interface\\Icons\\INV_Misc_Coin_02", "the option keeps its icon")
    eq(ns.Filter(ns.List(), "All", "all", "sell")[1].key, "QuestCleaner", "by an option's label")
    eq(ns.Filter(ns.List(), "All", "all", "junk at a")[1].key, "QuestCleaner", "by an option's tip")
    ns.Toggle()
    local view = ns.View()
    view.query = "nothing like it"
    ns.Refresh()
    view.query = ""
    ns.Refresh()
end)

test("the home page shows the modules' summaries and the feed; a click opens the module", function()
    Fake({ addons = { QC, { name = "Gulli-XP", enabled = true, loaded = true, meta = { ["X-Gulli-Module"] = "XP" } } } })
    local ns = Load()
    local S = ns.Skin
    local win = S.Window(nil, "XP", S.NARROW_W, 300)
    GulliToolkit.Register({ key = "XP", open = function() end, window = function() return win end,
                            summary = function() return "Level 24 in 1 h", "Interface\\Icons\\XP" end })
    GulliToolkit.Register({ key = "QuestCleaner", open = function() end, summary = function() error("boom") end })
    local sums = ns.Summaries()
    eq(#sums, 1, "a summary that fails is left out")
    eq(sums[1].text, "Level 24 in 1 h")
    eq(sums[1].icon, "Interface\\Icons\\XP")
    GulliToolkit.Notify("XP", "Level 23 reached")
    ns.Toggle()
    local view = ns.View()
    eq(view.page, "home", "nothing opened yet: the home page")
    eq(ns.Home():IsShown(), true)
    ns.Enter("XP")
    eq(view.page, "module")
    eq(ns.Home():IsShown(), false, "the module takes the centre")
    eq(ns.Card():IsShown(), true, "a narrow window keeps the card beside it")
    eq(ns.Last(), "XP", "remembered")
    eq(ns.Ago(1000 - 30, 1000), ns.L.AGO_NOW)
    eq(ns.Ago(1000 - 600, 1000), "10 min")
    eq(ns.Ago(1000 - 7300, 1000), "2 h")
    eq(ns.Ago(1000 - 3 * 86400, 1000), "3 d")
    GulliToolkit.ClearFeed()
    eq(#ns.Feed(), 0, "Clear empties the feed")
end)

test("the hub opens the module that was open last, back goes home and stays there", function()
    Fake({ addons = { QC } })
    local ns = Load()
    local S = ns.Skin
    local win = S.Window(nil, "Quest Cleaner", S.WIDE_W, 300)
    GulliToolkit.Register({ key = "QuestCleaner", open = function() end, window = function() return win end })
    ns.Toggle()
    ns.Enter("QuestCleaner")
    eq(ns.Card():IsShown(), false, "a wide window takes the whole centre")
    local _, hub = ns.View()
    hub:Hide()
    hub:GetScript("OnHide")()
    eq(win.docked, false)
    ns.Toggle()
    eq(ns.View().inside, "QuestCleaner", "opened where the player left it")
    win.dockOpts.back(win)
    eq(ns.View().page, "home")
    eq(ns.Last(), nil, "back to home: the hub opens on home next time")
    hub:Hide()
    hub:GetScript("OnHide")()
    ns.Toggle()
    eq(ns.View().inside, nil)
end)

test("presets switch their modules on and the others off; a group switches together", function()
    Fake({ addons = { QC, { name = "Gulli-Merchant", enabled = false, meta = { ["X-Gulli-Module"] = "Merchant" } },
                      { name = "Gulli-Loot", enabled = true, meta = { ["X-Gulli-Module"] = "Loot" } } } })
    local ns = Load()
    for _, p in ipairs(ns.PRESETS) do
        assert(ns.T.en["PRESET_" .. p.key], "no text for preset " .. p.key)
        for _, k in ipairs(p.modules) do assert(ns.CATEGORY_OF[k], p.key .. ": unknown module " .. k) end
    end
    eq(ns.ApplyPreset("Minimum"), 3, "QuestCleaner and Loot off, Merchant on")
    local r = byKey(ns.List())
    eq(r.Merchant.on, true)
    eq(r.QuestCleaner.on, false)
    eq(r.Loot.on, false)
    eq(ns.ApplyPreset("Minimum"), 0, "nothing left to switch")
    eq(ns.ApplyPreset("Nope"), 0)
    eq(ns.SetGroup("Quests", true), 1)
    eq(byKey(ns.List()).QuestCleaner.on, true)
    eq(ns.SetGroup("Items", false), 1)
    eq(byKey(ns.List()).Merchant.on, false)
end)

test("/gulli move unlocks every module's frames, reset goes back to defaults", function()
    Fake({ addons = { QC } })
    local ns = Load()
    local moving, reset
    GulliToolkit.Register({ key = "QuestCleaner", open = function() end,
        move = function(on) moving = on end, reset = function() reset = true end })
    GulliToolkit.Register({ key = "Broken", open = function() end, move = function() error("x") end })
    SlashCmdList.GULLITOOLKIT("move")
    eq(moving, true)
    eq(ns.moving, true)
    SlashCmdList.GULLITOOLKIT("move")
    eq(moving, false)
    eq(ns.Reset(byKey(ns.List()).QuestCleaner), true)
    eq(reset, true)
    eq(ns.Reset(byKey(ns.List()).Broken), false, "no reset: nothing to do")
end)

test("export and import every Gulli setting as one line, and refuse anything else", function()
    Fake({ addons = { { name = "Gulli-XP", enabled = true, loaded = true,
        meta = { ["X-Gulli-Module"] = "XP", SavedVariables = "GulliXPDB", SavedVariablesPerCharacter = "GulliXPCharDB" } } } })
    local ns = Load()
    GulliXPDB = { bar = true, alpha = 80, name = 'a "b" | c\\n', list = { 1, 2.5, -3 }, nested = { x = { y = false } } }
    GulliXPCharDB = { point = { "CENTER", 0, -120 } }
    GulliToolkitDB.protected = { [6948] = true }
    local line = ns.Export()
    assert(line:sub(1, 7) == "GULLI1:", "has the prefix")
    assert(not line:find("|", 1, true), "no | that the edit box would eat")
    assert(not line:find("\n", 1, true), "one line")
    local before = GulliXPDB
    GulliXPDB, GulliXPCharDB, GulliToolkitDB = nil, nil, nil
    eq(ns.Import("  " .. line .. "\n"), 3, "the toolkit's and both XP tables")
    eq(GulliXPDB.alpha, 80)
    eq(GulliXPDB.name, before.name, "quotes, pipes and backslashes survive")
    eq(GulliXPDB.list[2], 2.5)
    eq(GulliXPDB.list[3], -3)
    eq(GulliXPDB.nested.x.y, false)
    eq(GulliXPCharDB.point[3], -120)
    eq(GulliToolkitDB.protected[6948], true)
    eq(ns.Import("hello"), nil)
    eq(ns.Import("GULLI1:{\"a\"=os.exit();}"), nil, "never runs code")
    eq(ns.Import("GULLI1:{\"a\"=1;"), nil, "broken text")
    eq(ns.Import('GULLI1:{"print"={};"GulliX"={};}'), 0, "only Gulli...DB names are set")
    eq(print ~= nil and type(print), "function")
end)

test("versions: a newer one in the group is told once, New marks an updated module", function()
    Fake({ addons = { { name = "Gulli-Toolkit", enabled = true, loaded = true, meta = { Version = "1.6.0" } },
        { name = "Gulli-XP", enabled = true, loaded = true, meta = { ["X-Gulli-Module"] = "XP", Version = "1.3.0" } } } })
    local ns = Load()
    GulliToolkit.Register({ key = "XP", open = function() end })
    eq(ns.CompareVersions("1.10.0", "1.9.2"), 1)
    eq(ns.CompareVersions("1.2", "1.2.0"), 0)
    eq(ns.CompareVersions("0.9", "1.0"), -1)
    local msgs = ns.VersionMessages()
    assert(msgs[1]:find("|Core=1.6.0", 1, true) and msgs[1]:find("|XP=1.3.0", 1, true), msgs[1])
    for _, m in ipairs(msgs) do assert(#m <= 240) end
    local newer = ns.ReadVersions("V|Core=1.6.0|XP=1.4.0|Nope=9.0")
    eq(#newer, 1, "only XP is newer, an unknown module is skipped")
    eq(newer[1].key, "XP")
    eq(#ns.ReadVersions("V|XP=1.4.0"), 0, "told once")
    eq(#ns.ReadVersions("V|XP=1.5.0"), 1, "a still newer one is told again")
    eq(#ns.ReadVersions("junk"), 0)

    eq(byKey(ns.List()).XP.new, nil, "the first version seen is not new")
    W.addons[2].meta.Version = "1.4.0"
    eq(byKey(ns.List()).XP.new, true, "updated since the player opened it")
    ns.MarkSeen(byKey(ns.List()).XP)
    eq(byKey(ns.List()).XP.new, nil)
    SlashCmdList.GULLITOOLKIT("help")
    local all = table.concat(W.printed, "\n")
    assert(all:find("/gulli move", 1, true), "help names the toolkit's commands")
end)

test("protected items: by id or link, saved, listed, switched off again", function()
    Fake({})
    local ns = Load()
    eq(GulliToolkit.IsProtected(6948), false)
    assert(GulliToolkit.Protect(6948, true))
    assert(GulliToolkit.Protect("|cffffffff|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r", true))
    eq(GulliToolkit.IsProtected(6948), true)
    eq(GulliToolkit.IsProtected("item:2589"), true, "a link is read as its item id")
    eq(GulliToolkitDB.protected[2589], true, "saved account-wide")
    eq(#ns.Protected(), 2)
    GulliToolkit.Protect(6948, false)
    eq(GulliToolkit.IsProtected(6948), false)
    eq(GulliToolkit.Protect("nothing", true), false, "no item id, nothing saved")
    SlashCmdList.GULLITOOLKIT("protect |Hitem:4306::|h[Silk Cloth]|h")
    eq(GulliToolkit.IsProtected(4306), true, "/gulli protect <link> switches it on")
    SlashCmdList.GULLITOOLKIT("protect |Hitem:4306::|h[Silk Cloth]|h")
    eq(GulliToolkit.IsProtected(4306), false, "and off again")
end)

test("the feed keeps the newest lines first and only the last ones", function()
    Fake({})
    local ns = Load()
    for i = 1, ns.FEED_MAX + 5 do GulliToolkit.Notify("InstanceLimit", "line " .. i) end
    local feed = ns.Feed()
    eq(#feed, ns.FEED_MAX)
    eq(feed[1].text, "line " .. (ns.FEED_MAX + 5))
    eq(feed[1].key, "InstanceLimit")
    eq(GulliToolkit.Notify("X", ""), false, "an empty line is not added")
    ns.Toggle()
    ns.Refresh()
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

test("a module opens inside the hub, goes back, and its command takes it out", function()
    Fake({ addons = { QC, { name = "Gulli-Merchant", enabled = false, loaded = false,
                            meta = { ["X-Gulli-Module"] = "Merchant" } } } })
    local ns = Load()
    local S = ns.Skin
    local win = S.Window(nil, "Quest Cleaner", S.NARROW_W, 300)
    local opened = 0
    GulliToolkit.Register({ key = "QuestCleaner", open = function() opened = opened + 1 end,
                            window = function() return win end })
    ns.Toggle()
    local view = ns.View()
    ns.Enter("QuestCleaner")
    eq(view.inside, "QuestCleaner", "the hub is inside the module")
    eq(win.docked, true, "the window sits in the hub")
    eq(win:IsShown(), true)
    eq(win:GetHeight(), S.DOCK_H, "it takes the hub's height")
    eq(view.narrow, true, "a narrow window keeps the module card beside it")
    eq(opened, 0, "the module's own open is not called")
    win.dockOpts.back(win)
    eq(view.inside, nil, "back goes to the home page")
    eq(win.docked, false)
    eq(win:IsShown(), false, "the window is closed again")

    ns.Enter("QuestCleaner")
    S.FitWindow(win, 200)
    eq(win:GetHeight(), S.DOCK_H, "a window that fits itself keeps the hub's height inside")
    S.ToggleWindow(win)
    eq(view.inside, nil, "the slash command takes the window out of the hub")
    eq(win.docked, false)
    eq(win:IsShown(), true, "and shows it alone")
    eq(win:GetHeight(), S.HEADER_H + 2 * S.PAD + 200, "at its own height")
    S.ToggleWindow(win)
    eq(win:IsShown(), false, "the command closes it alone as before")

    ns.Enter("Merchant")
    eq(view.inside, "Merchant", "a module that is off opens its page inside too")
    local page = ns.Inside()
    assert(page and page ~= win and page.docked, "the page for a module that is off")
    eq(page.empty.title:GetText(), ns.L.INSIDE_OFF)
    local _, hub = ns.View()
    hub:Hide()
    hub:GetScript("OnHide")()
    eq(view.inside, nil, "closing the hub leaves the module")
end)

test("a module without a window, or a window too big for the hub, opens alone", function()
    Fake({ addons = { QC } })
    local ns = Load()
    local opened = 0
    local big = ns.Skin.Window(nil, "Big", 2000, 300)
    GulliToolkit.Register({ key = "QuestCleaner", open = function() opened = opened + 1 end,
                            window = function() return big end })
    ns.Toggle()
    ns.Enter("QuestCleaner")
    eq(opened, 1, "too big: the module opens its own window")
    eq(ns.View().inside, nil)
    GulliToolkit.Register({ key = "QuestCleaner", open = function() opened = opened + 1 end })
    ns.Toggle()
    ns.Enter("QuestCleaner")
    eq(opened, 2, "no window: the module opens its own window")
end)

test("every module gives its window to the hub, in a size the hub has room for", function()
    local p = io.popen("ls -d Gulli-*/")
    local n = 0
    for dir in p:lines() do
        local name = dir:gsub("/$", "")
        if name ~= "Gulli-Toolkit" then
            n = n + 1
            local all = ""
            for _, f in ipairs({ "Core.lua", "UI.lua" }) do
                local fh = io.open(name .. "/" .. f)
                if fh then all = all .. fh:read("*a"); fh:close() end
            end
            assert(all:find("window = function", 1, true), name .. ": Register has no window")
            assert(all:find("function ns.Window", 1, true), name .. ": no ns.Window")
            assert(all:find("S.NARROW_W", 1, true) or all:find("S.WIDE_W", 1, true),
                name .. ": the window is not S.NARROW_W or S.WIDE_W wide")
        end
    end
    p:close()
    assert(n > 0, "found the modules")
end)

test("the switch shows what the game will load: off is off, a module it refuses says why", function()
    Fake({ addons = {
        { name = "Gulli-MobFinder", enabled = false, state = 1, meta = { ["X-Gulli-Module"] = "MobFinder" } },
        { name = "Gulli-XP", enabled = true, blocked = "INTERFACE_VERSION", meta = { ["X-Gulli-Module"] = "XP" } },
        { name = "Gulli-Loot", enabled = true, meta = { ["X-Gulli-Module"] = "Loot" } } } })
    ADDON_INTERFACE_VERSION = "Out of date"
    local ns = Load()
    local r = byKey(ns.List())
    eq(r.MobFinder.on, false, "enabled only for other characters: off here")
    eq(r.MobFinder.state, "off")
    eq(r.XP.on, true)
    eq(r.XP.state, "blocked", "on but the game will not load it")
    eq(r.XP.reason, "INTERFACE_VERSION")
    eq(ns.ReasonText(r.XP.reason), "Out of date", "the game's own words")
    eq(ns.ReasonText("SOMETHING_NEW"), "SOMETHING_NEW")
    eq(r.Loot.state, "reload", "on and loadable, not loaded yet: a reload loads it")
    eq(ns.Counts(ns.List()).All.on, 2)
    ns.Toggle()
    ns.Enter("XP")
    eq(ns.Inside().empty.title:GetText(), ns.L.INSIDE_OUTDATED, "the page says how to load it")
    ADDON_INTERFACE_VERSION = nil
end)

test("the home page counts what runs, waits, is refused or updated, and lists every running summary", function()
    Fake({ addons = {
        { name = "Gulli-XP", enabled = false, loaded = true, meta = { ["X-Gulli-Module"] = "XP", Version = "1.4.0" } },
        { name = "Gulli-Loot", enabled = true, blocked = "INTERFACE_VERSION", meta = { ["X-Gulli-Module"] = "Loot" } },
        { name = "Gulli-Chores", enabled = true, loaded = true, meta = { ["X-Gulli-Module"] = "Chores", Version = "1.4.0" } } } })
    GulliToolkitDB = { seen = { Chores = "1.3.0" } }
    UpdateAddOnMemoryUsage = function() end
    GetAddOnMemoryUsage = function(name) return ({ ["Gulli-XP"] = 360, ["Gulli-Chores"] = 2048 })[name] or 0 end
    local ns = Load()
    GulliToolkit.Register({ key = "XP", open = function() end, slash = "/gxp", summary = function() return "8k XP/h" end })
    GulliToolkit.Register({ key = "Chores", open = function() end, slash = "/gch" })
    local o = ns.Overview()
    eq(o.on, 2, "Loot and Chores are on")
    eq(o.running, 2, "XP and Chores run")
    eq(#o.reload, 1, "XP runs but is switched off")
    eq(o.reload[1].key, "XP")
    eq(#o.blocked, 1)
    eq(o.blocked[1].key, "Loot")
    eq(#o.new, 1, "Chores was updated")
    eq(o.heavy[1].row.key, "Chores", "heaviest first")
    eq(ns.Size(o.kb), "2.4 MB")
    eq(ns.Size(360), "360 KB")
    local sums = ns.Summaries()
    eq(#sums, 1, "a module that still runs while it waits for a reload keeps its summary")
    eq(sums[1].row.key, "XP")
    ns.Toggle()
    eq(ns.Home():IsShown(), true, "the home page builds with the Modules card and the commands")
    UpdateAddOnMemoryUsage, GetAddOnMemoryUsage = nil, nil
end)

test("the minimap button sits on the circle, or on the edge of a square minimap", function()
    Fake({})
    local ns = Load()
    local function near(a, b, what) assert(math.abs(a - b) < 0.001, what .. ": " .. a .. " ~= " .. b) end
    local x, y = ns.MinimapOffset(0, 76)
    near(x, 76, "x at 0"); near(y, 0, "y at 0")
    x, y = ns.MinimapOffset(90, 76)
    near(x, 0, "x at 90"); near(y, 76, "y at 90")
    x, y = ns.MinimapOffset(45, 76, true)
    near(x, 76, "square corner x"); near(y, 76, "square corner y")
    near(ns.AngleTo(0, 0, -1, 0), 180, "left")
    near(ns.AngleTo(0, 0, 0, -1), 270, "below")
end)

test("the minimap button opens the hub, moves by drag and hides with /gulli minimap", function()
    local W = Fake({})
    local ns = Load()
    local b = ns.MinimapButton()
    assert(b, "the button is made at load")
    eq(b:IsShown(), true, "shown by default")
    eq(ns.MinimapAngle(), 225, "default place")
    b:GetScript("OnClick")(b)
    local _, frame = ns.View()
    eq(frame:IsShown(), true, "a click opens the hub")
    W.cursor = { 100, 0 }
    b:GetScript("OnDragStart")(b)
    b:GetScript("OnUpdate")(b)
    b:GetScript("OnDragStop")(b)
    eq(GulliToolkitDB.minimap.angle, 270, "dragged below the minimap")
    SlashCmdList.GULLITOOLKIT("minimap")
    eq(b:IsShown(), false, "hidden")
    eq(GulliToolkitDB.minimap.hide, true, "saved")
    SlashCmdList.GULLITOOLKIT("minimap")
    eq(b:IsShown(), true, "back")
    eq(GulliToolkitDB.minimap.hide, nil, "saved")
end)

test("a saved hidden minimap button stays hidden after a reload", function()
    Fake({})
    GulliToolkitDB = { minimap = { hide = true, angle = 10 } }
    local ns = Load()
    eq(ns.MinimapButton():IsShown(), false)
    eq(ns.MinimapAngle(), 10)
end)

test("one state: the switch is the game's AddOns list, also for a module that runs", function()
    Fake({ addons = { QC, { name = "Gulli-Loot", enabled = true, loaded = true, meta = { ["X-Gulli-Module"] = "Loot" } },
                      { name = "Gulli-XP", enabled = false, stuck = true, meta = { ["X-Gulli-Module"] = "XP" } } } })
    local ns = Load()
    GulliToolkit.Register({ key = "QuestCleaner", open = function() end })
    GulliToolkit.Register({ key = "Loot", open = function() end })
    eq(ns.NeedsReload(), false)
    -- The player switched Loot off in the game's AddOns list; it still runs until a reload.
    W.addons[2].enabled = false
    local r = byKey(ns.List())
    eq(r.Loot.on, false, "the switch shows the game's off, not that it runs")
    eq(r.Loot.state, "reload")
    assert(ns.NeedsReload())
    ns.SetEnabled(r.Loot, true)
    eq(byKey(ns.List()).Loot.state, "ready", "switched back on: nothing to reload")
    eq(ns.NeedsReload(), false)
    -- The game ignores the switch: the hub keeps showing off and says so.
    eq(ns.SetEnabled(byKey(ns.List()).XP, true), false)
    eq(byKey(ns.List()).XP.on, false, "never on when the game says off")
    assert(W.printed[#W.printed]:find("XP", 1, true), "tells the player")
end)

test("the switches work on a client that names the character by GUID", function()
    Fake({ guidOnly = true, addons = { QC, { name = "Gulli-MobFinder", enabled = true, loaded = true,
        meta = { ["X-Gulli-Module"] = "MobFinder" } } } })
    local ns = Load()
    GulliToolkit.Register({ key = "QuestCleaner", open = function() end })
    GulliToolkit.Register({ key = "MobFinder", open = function() end })
    eq(byKey(ns.List()).MobFinder.on, true)
    eq(ns.SetEnabled(byKey(ns.List()).MobFinder, false), true, "the game took it")
    eq(W.addons[2].enabled, false)
    eq(byKey(ns.List()).MobFinder.on, false, "the switch shows the game's off")
    eq(byKey(ns.List()).MobFinder.state, "reload")
    eq(ns.SetEnabled(byKey(ns.List()).MobFinder, true), true)
    eq(byKey(ns.List()).MobFinder.on, true)
    eq(byKey(ns.List()).MobFinder.state, "ready")
    local lines = ns.Debug("MobFinder")
    assert(lines and lines[1]:find("Gulli-MobFinder", 1, true))
end)

io.write(string.format("%d/%d passed\n", count - failed, count))
os.exit(failed == 0 and 0 or 1)
