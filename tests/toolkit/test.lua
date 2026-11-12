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

test("a module's options are shown and switched from the hub", function()
    Fake({ addons = { QC } })
    local ns = Load()
    local db = { sell = true }
    GulliToolkit.Register({ key = "QuestCleaner", open = function() end, options = {
        { label = "Sell", get = function() return db.sell end, set = function(on) db.sell = on end,
          icon = "Interface\\Icons\\INV_Misc_Coin_02" },
        { label = "Broken" }, "nonsense" } })
    local row = byKey(ns.List()).QuestCleaner
    eq(#row.options, 1, "only options with a label, get and set")
    eq(row.options[1].icon, "Interface\\Icons\\INV_Misc_Coin_02", "the option keeps its icon")
    ns.Toggle()
    local view = ns.View()
    view.selected = "QuestCleaner"
    ns.Refresh()
    eq(view.selected, "QuestCleaner")
    view.query = "nothing like it"
    ns.Refresh()
    eq(view.selected, nil, "nothing selected when the search finds nothing")
    view.query, view.state, view.cat = "", "off", "Group"
    ns.Refresh()
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
    eq(view.inside, nil, "back goes to the list")
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

io.write(string.format("%d/%d passed\n", count - failed, count))
os.exit(failed == 0 and 0 or 1)
