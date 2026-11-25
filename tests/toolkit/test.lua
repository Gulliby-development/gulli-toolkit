-- Run from the repository root: lua5.1 tests/toolkit/test.lua
local W = dofile("tests/toolkit/wow.lua")
local failed, count = 0, 0

-- A font string that remembers what the skin set on it.
function stubText()
    local s = { shown = true }
    function s:SetShown(v) self.shown = v and true or false end
    function s:SetFontObject(o) self.object = o end
    function s:SetFont(_, size) self.size = size end
    return setmetatable(s, { __index = function() return function() end end })
end

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

test("only installed modules are listed, the known ones first in their order", function()
    Fake({ addons = { { name = "Other", enabled = true, loaded = true },
        { name = "Gulli-GroupBuffs", enabled = false, meta = { ["X-Gulli-Module"] = "GroupBuffs" } },
        { name = "Gulli-MobFinder", enabled = true, loaded = true, meta = { ["X-Gulli-Module"] = "MobFinder" } } } })
    local ns = Load()
    local rows = ns.List()
    eq(#rows, 2, "a module that is not installed and an addon that is not a Gulli module are not listed")
    eq(rows[1].key, "MobFinder")
    eq(rows[2].key, "GroupBuffs")
    eq(rows[1].title, "Mob Finder")
    eq(rows[2].state, "off", "a module switched off in the game stays listed")
    eq(ns.Counts(rows).All.total, 2, "the counts take only installed modules")
end)

test("a module shows up once it is installed", function()
    Fake({ addons = { QC } })
    local ns = Load()
    eq(byKey(ns.List()).Loot, nil)
    GulliToolkit.Register({ key = "Loot", open = function() end })
    eq(byKey(ns.List()).Loot.state, "ready")
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
    eq(r.GroupBuffs, nil, "not installed, not listed")
    eq(rows[#rows].key, "Zeta")
    eq(r.Zeta.title, "Zeta", "the title from the TOC without colour codes or the Gulli prefix")
end)

test("a module that can pause stops and starts at once; not loading it waits for a reload", function()
    Fake({ addons = { QC, { name = "Gulli-Loot", enabled = true, loaded = true, meta = { ["X-Gulli-Module"] = "Loot" } } } })
    local ns = Load()
    local calls = {}
    GulliToolkit.Register({ key = "Loot", open = function() end, summary = function() return "12 rules" end,
                            pause = function(on) calls[#calls + 1] = on end })
    GulliToolkit.Register({ key = "QuestCleaner", open = function() end })
    local r = byKey(ns.List())
    eq(r.Loot.canPause, true)
    eq(r.QuestCleaner.canPause, false, "a module without pause keeps the old switch")
    eq(ns.Switch(r.Loot, false), true)
    eq(calls[1], true, "paused at once")
    eq(W.addons[2].enabled, true, "still loaded in the game")
    r = byKey(ns.List())
    eq(r.Loot.on, false, "the switch shows off")
    eq(r.Loot.paused, true)
    eq(r.Loot.state, "ready")
    eq(ns.NeedsReload(), false, "a pause needs no reload")
    eq(#ns.Summaries(), 0, "a paused module says nothing on the home page")
    eq(#ns.Overview().paused, 1)
    eq(GulliToolkit.IsPaused("Loot"), true)
    ns.Switch(r.Loot, true)
    eq(calls[2], false, "started again at once")
    eq(byKey(ns.List()).Loot.on, true)
    -- The pause is saved: after a reload the module pauses as soon as it registers.
    ns.Switch(byKey(ns.List()).Loot, false)
    local saved = GulliToolkitDB
    Fake({ addons = { QC, { name = "Gulli-Loot", enabled = true, loaded = true, meta = { ["X-Gulli-Module"] = "Loot" } } } })
    GulliToolkitDB = saved
    ns = Load()
    local again
    GulliToolkit.Register({ key = "Loot", open = function() end, pause = function(on) again = on end })
    eq(again, true, "paused again after the reload")
    -- Not loading it at all is the game's list and waits for a reload.
    ns.SetLoaded(byKey(ns.List()).Loot, false)
    eq(W.addons[2].enabled, false)
    eq(byKey(ns.List()).Loot.state, "reload")
    ns.SetLoaded(byKey(ns.List()).Loot, true)
    eq(GulliToolkit.IsPaused("Loot"), false, "loading it again ends the pause")
    -- A module without pause still goes through the game's list.
    ns.Switch(byKey(ns.List()).QuestCleaner, false)
    eq(W.addons[1].enabled, false)
    eq(ns.NeedsReload(), true)
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
    eq(#ns.List(), 2, "QuestCleaner and the module that registered late")
end)

test("the hub fits the screen: it shrinks on a small one, the module list scrolls", function()
    Fake({})
    local ns = Load()
    local function near(a, b, msg) assert(math.abs(a - b) < 0.001, (msg or "") .. ": " .. a .. " ~= " .. b) end
    near(ns.HubScale(1, 1920, 1080, 1086, 700), 1080 * 0.9 / 700, "a 0.71 UI scale: 90% of the height")
    near(ns.HubScale(1, 1366, 768, 1086, 700), 768 * 0.9 / 700, "a 768 high screen: as before")
    near(ns.HubScale(1, 1024, 768, 1086, 700), 1024 * 0.96 / 1086, "a narrow screen: by its width")
    near(ns.HubScale(1, 2560, 1440, 1086, 700), 1.6, "a big screen: at most 1.6 times")
    near(ns.HubScale(nil, 1920, 1080, 1086, 700), ns.HubScale(1, 1920, 1080, 1086, 700))
    near(ns.HubScale(1.3, 1920, 1080, 1086, 700), 1080 * 0.98 / 700, "the player's + stops at the screen")
    near(ns.HubScale(0.7, 1366, 768, 1086, 700), 0.7 * 768 * 0.9 / 700, "the player's - makes it smaller")
    near(ns.HubScale(5, 2560, 1440, 1086, 700), 1440 * 0.98 / 700, "the player's scale is capped")
    for _, sz in ipairs({ { 1920, 1080 }, { 1366, 768 }, { 1024, 768 }, { 2560, 1440 }, { 800, 480 } }) do
        local k = ns.HubScale(1.3, sz[1], sz[2], 1086, 700)
        assert(1086 * k <= sz[1] * 0.98 + 0.01 and 700 * k <= sz[2] * 0.98 + 0.01, "fits " .. sz[1] .. "x" .. sz[2])
    end
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
    eq(c.All.total, 2, "only installed modules count")
    eq(c.All.on, 1)
    eq(c.Quests.on, 1)
    eq(c.Items.on, 0)
    eq(#ns.Filter(rows, "Quests", "all", ""), 1)
    eq(#ns.Filter(rows, "All", "on", ""), 1)
    eq(#ns.Filter(rows, "Items", "off", ""), 1)
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

test("home tiles: the number a line starts with goes big, trouble comes first, a quiet tile goes first", function()
    local mods = {}
    for _, k in ipairs({ "QuestCleaner", "BagSpace", "Merchant", "XP", "Chores", "Loot", "Mail", "GroupBuffs" }) do
        mods[#mods + 1] = { name = "Gulli-" .. k, enabled = true, loaded = true, meta = { ["X-Gulli-Module"] = k } }
    end
    Fake({ addons = mods })
    local ns = Load()
    local sums = {
        QuestCleaner = function() return "Quest log 23 of 25" end,
        BagSpace = function() return "26 free bag slots", nil, { ready = "BAGS" } end,
        Merchant = function() return "3 junk items worth 1g\nsecond line" end,
        XP = function() return "Level 48 in 1 h" end,
        Chores = function() return "Nothing waits", nil, { quiet = true } end,
        Loot = function() return "Maraudon: 0 in log, 8 to pick up", nil, { value = 8, tone = "warn" } end,
        Mail = function() return "5 of 5 entries left", nil, { pips = { 4, 5 }, tone = "nonsense" } end,
        GroupBuffs = function() return "1 buffs missing", nil, { tone = "bad" } end,
    }
    for k, fn in pairs(sums) do GulliToolkit.Register({ key = k, open = function() end, summary = fn }) end
    local by = {}
    for _, s in ipairs(ns.Summaries()) do by[s.row.key] = ns.TileOf(s) end
    eq(by.Merchant.value, "3", "the number the line starts with")
    eq(by.Merchant.label, "junk items worth 1g", "the rest of the first line")
    eq(by.QuestCleaner.value, nil, "a line that starts with a word has no number")
    eq(by.QuestCleaner.label, "Quest log 23 of 25")
    eq(by.Loot.value, "8", "the module names its number")
    eq(by.Loot.label, "Maraudon: 0 in log, 8 to pick up")
    eq(by.Mail.pips[1], 4)
    eq(by.Mail.pips[2], 5)
    eq(by.Mail.tone, nil, "an unknown tone is no tone")
    local tiles = ns.Tiles()
    eq(#tiles, ns.TILES_MAX, "at most TILES_MAX tiles")
    eq(tiles[1].row.key, "GroupBuffs", "bad first")
    eq(tiles[2].row.key, "Loot", "then warn")
    for _, t in ipairs(tiles) do assert(t.row.key ~= "Chores", "the quiet tile is the first to go") end
    tiles = ns.Tiles(nil, { BAGS = true }, "XP", 20)
    eq(#tiles, 6, "the Ready check and the session card take two tiles")
    for _, t in ipairs(tiles) do assert(t.row.key ~= "BagSpace" and t.row.key ~= "XP", t.row.key) end
    eq(tiles[#tiles].row.key, "Chores", "quiet goes last")
    tiles = ns.Tiles(nil, {}, nil, 20)
    eq(#tiles, 8, "with the Ready card off its tile is back")
end)

test("a module's session: a number that can lead, a tile, facts and its part of the tooltip", function()
    local mods = {}
    for _, k in ipairs({ "QuestCleaner", "FarmTrack", "XP" }) do
        mods[#mods + 1] = { name = "Gulli-" .. k, enabled = true, loaded = true, meta = { ["X-Gulli-Module"] = k } }
    end
    Fake({ addons = mods })
    local ns = Load()
    local bars = {}
    for i = 1, 20 do bars[i] = i end
    local xp, farm
    GulliToolkit.Register({ key = "XP", open = function() end, session = function() return xp end })
    GulliToolkit.Register({ key = "FarmTrack", open = function() end, pause = function() end,
        session = function() return farm end })
    GulliToolkit.Register({ key = "QuestCleaner", open = function() end, session = function() error("boom") end })
    local rows = byKey(ns.List())
    eq(ns.SessionOf(rows.XP), nil, "nothing to say")
    eq(ns.SessionOf(rows.QuestCleaner), nil, "an error is no session")
    xp = { value = "19k", unit = "XP / h", line = "Level 48 in 1 h", span = "1 h", bars = bars, at = 990,
           progress = { value = 0.9, extra = 0.5, left = 47, right = "90%" },
           tile = { value = "+22k", label = "XP" }, facts = { "3.1k to hand in", 5, "" },
           tip = { head = "Experience", value = "22k", rows = { { "kills", "61%" }, "junk", { "quests" } } } }
    local s = ns.SessionOf(rows.XP)
    eq(#s.bars, ns.SESSION_BARS, "only the newest bars")
    eq(s.bars[#s.bars], 20)
    eq(s.progress.left, "47")
    assert(math.abs(s.progress.extra - 0.1) < 1e-9, "the lighter part never passes the end")
    eq(s.tile.value, "+22k")
    eq(#s.facts, 1, "only texts are facts")
    eq(#s.tip.rows, 2, "only rows with a left side")
    eq(s.tip.rows[2][2], "")
    xp = { unit = "no value" }
    eq(ns.SessionOf(rows.XP), nil, "neither a value nor a tile is no session")
    farm = { tile = { value = 86, label = "Runecloth", icon = "cloth" } }
    s = ns.SessionOf(rows.FarmTrack)
    eq(s.value, nil, "a tile alone never leads")
    eq(s.tile.value, "86")
    GulliToolkitDB.paused = { FarmTrack = true }
    eq(ns.SessionOf(byKey(ns.List()).FarmTrack), nil, "a paused module gives none")
end)

local function sessionWorld(keys)
    local mods = {}
    for _, k in ipairs(keys or {}) do
        mods[#mods + 1] = { name = "Gulli-" .. k, enabled = true, loaded = true, meta = { ["X-Gulli-Module"] = k } }
    end
    local w = Fake({ addons = mods })
    local ns = Load()
    ns.SesEvent("PLAYER_ENTERING_WORLD", true, false)
    return ns, w
end

test("the session counts honor from one source only", function()
    local ns, w = sessionWorld()
    eq(ns.HonorIn("Boar dies, honorable kill Rank: Scout (Estimated Honor Points: 12)"), 12)
    eq(ns.HonorIn("You have been awarded 1,240 honor points."), 1240)
    eq(ns.HonorIn("You have been awarded 1.240 honor points."), 1240)
    eq(ns.HonorIn("Awarded 12.50 honor."), 12, "two digits after the point are a fraction")
    eq(ns.HonorIn("no number"), nil)
    ns.SesEvent("CHAT_MSG_COMBAT_HONOR_GAIN", "honorable kill (Estimated Honor Points: 12)")
    ns.SesEvent("CURRENCY_DISPLAY_UPDATE", 1792, 500, 12)
    eq(ns.ses.honor, 12, "the same kill told twice counts once")
    ns.SesEvent("CHAT_MSG_COMBAT_HONOR_GAIN", "awarded 30 honor points")
    ns.SesEvent("CURRENCY_DISPLAY_UPDATE", 1792, 530, 30)
    eq(ns.ses.honor, 42)
    eq(ns.ses.honorSrc, "chat")
    -- another character's client: only the honor bar tells, and a new honor level wraps it
    ns, w = sessionWorld()
    w.honor = { 100, 1000 }
    ns.SesEvent("PLAYER_ENTERING_WORLD", true, false)
    w.honor = { 900, 1000 }
    ns.SesEvent("HONOR_XP_UPDATE")
    w.honor = { 50, 1200 }
    ns.SesEvent("HONOR_XP_UPDATE")
    eq(ns.ses.honor, 800 + 100 + 50)
    ns.SesEvent("CURRENCY_DISPLAY_UPDATE", 1, 10, 10)
    eq(ns.ses.honor, 950, "another currency is not honor")
    -- honorable kills: the lifetime number when the game has it, else the events
    w.hk = 100
    ns.SesEvent("PLAYER_ENTERING_WORLD", true, false)
    w.hk = 103
    ns.SesEvent("PLAYER_PVP_KILLS_CHANGED")
    eq(ns.ses.hk, 3)
    GetPVPLifetimeStats = nil
    ns.SesEvent("PLAYER_ENTERING_WORLD", true, false)
    ns.SesEvent("PLAYER_PVP_KILLS_CHANGED")
    ns.SesEvent("PLAYER_PVP_KILLS_CHANGED")
    eq(ns.ses.hk, 2)
    -- a secret amount is left alone
    issecretvalue = function(v) return v == "secret" end
    ns.SesEvent("CHAT_MSG_COMBAT_HONOR_GAIN", "secret")
    ns.SesEvent("CURRENCY_DISPLAY_UPDATE", 1792, 5, "secret")
    eq(ns.ses.honor, 0)
    issecretvalue = nil
end)

test("the session's gold is what was earned: loot, quests, vendors, less repairs", function()
    local ns, w = sessionWorld()
    local function gain(n) w.money = w.money + n; ns.SesEvent("PLAYER_MONEY") end
    gain(500)
    eq(ns.ses.gold.loot, 500)
    -- a quest: its money comes after the event, or just before it
    ns.SesEvent("QUEST_TURNED_IN", 1, 100, 300)
    gain(300)
    eq(ns.ses.gold.quest, 300)
    eq(ns.ses.gold.loot, 500, "the reward is not loot too")
    gain(200)
    ns.SesEvent("QUEST_TURNED_IN", 2, 100, 200)
    eq(ns.ses.gold.quest, 500)
    eq(ns.ses.gold.loot, 500, "money that came first moves from loot to the quest")
    eq(ns.ses.quests, 2)
    -- the mailbox only moves money
    MailFrame = { IsShown = function() return true end }
    ns.SesEvent("MAIL_SHOW")
    gain(10000)
    gain(-4000)
    MailFrame = { IsShown = function() return false end }
    ns.SesEvent("MAIL_CLOSED")
    eq(ns.SesEarned(), 1000)
    -- a vendor: a sale counts, a purchase does not, a repair is taken off
    MerchantFrame = { IsShown = function() return true end }
    w.repair = 150
    ns.SesEvent("MERCHANT_SHOW")
    gain(250)
    eq(ns.ses.gold.vendor, 250)
    gain(-90)
    eq(ns.ses.gold.repair, 0, "a purchase is no repair")
    w.repair = 0
    gain(-150)
    eq(ns.ses.gold.repair, 150)
    -- the bill may also drop a moment after the money left
    w.repair = 40
    ns.SesEvent("UPDATE_INVENTORY_DURABILITY")
    gain(-40)
    w.repair = 0
    ns.SesEvent("UPDATE_INVENTORY_DURABILITY")
    eq(ns.ses.gold.repair, 190)
    -- a guild repair costs the character nothing
    w.repair = 70
    ns.SesEvent("UPDATE_INVENTORY_DURABILITY")
    w.repair = 0
    ns.SesEvent("UPDATE_INVENTORY_DURABILITY")
    eq(ns.ses.gold.repair, 190)
    eq(ns.SesEarned(), 500 + 500 + 250 - 190)
    -- a close event that never came: the flag ends when the game says the window is gone
    MerchantFrame = { IsShown = function() return false end }
    gain(60)
    eq(ns.ses.gold.loot, 560)
end)

test("the session keeps kills, deaths and the best loot, and a reload keeps the session", function()
    local ns, w = sessionWorld()
    ns.SesEvent("CHAT_MSG_COMBAT_XP_GAIN", "Boar dies, you gain 45 experience.")
    ns.SesEvent("CHAT_MSG_COMBAT_XP_GAIN", "no number")
    ns.SesEvent("PLAYER_DEAD")
    eq(ns.ses.kills, 1)
    eq(ns.ses.deaths, 1)
    w.quality = { ["1"] = 2, ["2"] = 3, ["3"] = 4, ["4"] = 3 }
    local function loot(id, name, who, guid)
        ns.SesEvent("CHAT_MSG_LOOT", "You receive loot: |cff0070dd|Hitem:" .. id .. "::::|h[" .. name .. "]|h|r.", who,
            nil, nil, nil, nil, nil, nil, nil, nil, nil, guid)
    end
    loot(1, "Green Belt", "Tester")
    eq(ns.ses.best, nil, "an uncommon item is not worth a word")
    loot(3, "Epic Blade", "Other-Realm", "Player-9")
    eq(ns.ses.best, nil, "someone else's loot")
    loot(2, "Blue Staff", "Tester-Realm")
    eq(ns.ses.best.name, "Blue Staff")
    loot(3, "Epic Blade", nil, w.GUID)
    eq(ns.ses.best.name, "Epic Blade")
    loot(4, "Blue Ring", "Tester")
    eq(ns.ses.best.name, "Epic Blade", "a lower quality does not replace it")
    -- a /reload goes on, a loading screen too, a login starts anew
    ns.ses, ns.sesBusy = nil, nil
    ns.SesEvent("PLAYER_ENTERING_WORLD", false, true)
    eq(ns.ses.kills, 1)
    ns.SesEvent("PLAYER_ENTERING_WORLD", false, false)
    eq(ns.ses.deaths, 1)
    ns.SesEvent("PLAYER_LOGOUT")
    ns.SesEvent("PLAYER_ENTERING_WORLD", true, false)
    eq(ns.ses.kills, 1, "a quick relog keeps the session")
    local clock = time
    time = function() return clock() + ns.Skin.RELOG_KEEP + 1 end
    ns.SesEvent("PLAYER_ENTERING_WORLD", true, false)
    time = clock
    eq(ns.ses.kills, 0)
    eq(GulliToolkitCharDB.session, ns.ses)
    -- an older save without a field
    GulliToolkitCharDB.session = { t = 5, kills = 7, gold = { loot = 9 } }
    ns.ses = nil
    ns.SesEvent("PLAYER_ENTERING_WORLD", false, true)
    eq(ns.ses.kills, 7)
    eq(ns.ses.gold.repair, 0)
    eq(ns.ses.honor, 0)
    eq(ns.Num(1240), "1 240")
    eq(ns.Num(999), "999")
    eq(ns.Num(1234567), "1 234 567")
end)

test("the session card: who leads, the tiles under it, the facts and the tooltip", function()
    local ns, w = sessionWorld({ "XP", "InstanceLimit", "FarmTrack" })
    local card = ns.SessionCard()
    eq(card.empty, true, "nothing happened yet")
    local xp, runs, farm
    GulliToolkit.Register({ key = "XP", open = function() end, session = function() return xp end })
    GulliToolkit.Register({ key = "InstanceLimit", open = function() end, session = function() return runs end })
    GulliToolkit.Register({ key = "FarmTrack", open = function() end, session = function() return farm end })
    -- everything at once: XP leads, gold, honor and the dungeons stand under it
    xp = { value = "19k", unit = "XP / h", line = "Level 48 in 1 h", span = "2 h 40 min", at = 1000,
           tile = { value = "+50k", label = "XP" }, facts = { "3.1k to hand in" },
           tip = { head = "Experience", value = "50k", rows = { { "kills", "61%" } } } }
    runs = { value = "2", unit = "dungeons", at = 400, tile = { value = "2", label = "Dungeons" },
             tip = { head = "Dungeons", value = "2", rows = { { "Maraudon", "41 min" } } } }
    farm = { tile = { value = "86", label = "Runecloth" } }
    w.money = 5000; ns.SesEvent("PLAYER_MONEY")
    ns.SesEvent("CHAT_MSG_COMBAT_HONOR_GAIN", "awarded 1240 honor")
    for _ = 1, 3 do ns.SesEvent("CHAT_MSG_COMBAT_XP_GAIN", "you gain 45 experience") end
    ns.SesEvent("PLAYER_DEAD")
    card = ns.SessionCard()
    eq(card.hero.key, "XP")
    eq(card.span, "2 h 40 min", "the leader's own span")
    eq(#card.stats, ns.SES_STATS)
    eq(card.stats[1].key, "Gold")
    eq(card.stats[2].key, "Honor")
    eq(card.stats[2].value, "+1 240")
    eq(card.stats[3].key, "InstanceLimit")
    eq(card.facts[1], "Kills: 3", "what found no tile is a fact")
    eq(card.facts[2], "Deaths: 1")
    eq(card.facts[3], "3.1k to hand in")
    eq(card.tip[1].head, "Experience")
    eq(card.tip[#card.tip].head, "Other")
    eq(card.tip[#card.tip].rows[1][2], "3")
    -- no XP for a quarter of an hour: honor, gained just now, leads
    xp.at = 1000 - ns.SES_RECENT - 1
    card = ns.SessionCard()
    eq(card.hero.key, "Honor")
    eq(card.hero.unit, "honor / h")
    eq(card.stats[1].key, "Gold")
    eq(card.stats[3].key, "FarmTrack", "the tiles keep their order, XP last")
    -- at the top level there is no XP: honor, then the dungeons, then gold
    xp = nil
    card = ns.SessionCard(nil, 1000)
    eq(card.hero.key, "Honor")
    card = ns.SessionCard(nil, 1000 + ns.SES_RECENT + 1)
    eq(card.hero.key, "Honor", "nobody gained lately: the first of the order")
    ns.ses.honor = 0
    runs.at = 1000
    card = ns.SessionCard()
    eq(card.hero.key, "InstanceLimit")
    eq(card.stats[1].key, "Gold")
    eq(card.stats[2].key, "FarmTrack")
    eq(card.stats[3].key, "kills", "a free place takes a small counter")
    eq(card.facts[1], "Deaths: 1")
    runs, farm = nil, nil
    card = ns.SessionCard()
    eq(card.hero.key, "Gold")
    eq(card.hero.unit, "/ h")
    eq(#card.stats, 2)
    -- only small counters: the first one leads
    ns.ses.gold.loot = 0
    card = ns.SessionCard()
    eq(card.hero.key, "kills")
    eq(card.hero.value, "3")
    eq(card.hero.unit, "Kills")
    eq(card.stats[1].key, "deaths")
    -- the best loot is the last fact and a line of the tooltip
    ns.ses.best = { name = "Epic Blade", q = 4 }
    card = ns.SessionCard()
    assert(card.facts[#card.facts]:find("Epic Blade", 1, true), "the best loot is a fact")
    assert(card.tip[#card.tip].rows[#card.tip[#card.tip].rows][2]:find("Epic Blade", 1, true))
end)

test("the session card's gold is an estimate when a module tells what the loot is worth", function()
    local ns, w = sessionWorld({ "FarmTrack" })
    local farm
    GulliToolkit.Register({ key = "FarmTrack", open = function() end, session = function() return farm end })
    local function gold(card)
        for _, g in ipairs(card.tip or {}) do if g.head == "Gold" then return g end end
    end
    local function plain(text) return (text:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    w.money = 20000; ns.SesEvent("PLAYER_MONEY")
    ns.SesEvent("MERCHANT_SHOW"); w.money = 50000; ns.SesEvent("PLAYER_MONEY"); ns.SesEvent("MERCHANT_CLOSED")
    local card = ns.SessionCard()
    eq(ns.SesEarned(), 50000)
    eq(#gold(card).rows, 2, "looted and sold")
    local before = plain(gold(card).value)
    -- the loot is worth 12 gold: it replaces the sales, since what was sold is in the worth
    farm = { worth = 120000 }
    card = ns.SessionCard()
    eq(card.hero.key, "Gold", "a worth alone gives no tile and no leader of its own")
    local g = gold(card)
    eq(#g.rows, 2)
    eq(g.rows[1][1], "Loot")
    eq(g.rows[2][1], "Loot worth (estimate)")
    assert(plain(g.value) ~= before, "the total is the estimate")
    assert(plain(g.value):find("14"), plain(g.value))
    -- nothing earned yet, but loot in the bags: the gold shows
    ns.SesStart(time())
    card = ns.SessionCard()
    eq(card.hero.key, "Gold")
    -- a worth that is no plain number is left out
    farm = { worth = "many" }
    eq(ns.SessionCard().empty, true)
    -- crafting that cost more than it made: the estimate goes down, the vendor sales stay out
    ns.SesEvent("MERCHANT_SHOW"); w.money = w.money + 30000; ns.SesEvent("PLAYER_MONEY"); ns.SesEvent("MERCHANT_CLOSED")
    farm = { worth = -5000 }
    card = ns.SessionCard()
    g = gold(card)
    assert(plain(g.value):find("^%-50s"), plain(g.value))
    eq(g.rows[#g.rows][3], true, "a loss shows as bad")
    -- a worth of 0 still keeps the sales out (what was sold was crafted and counted there)
    farm = { worth = 0 }
    g = gold(ns.SessionCard())
    assert(not plain(g.value):find("30s"), plain(g.value))
end)

test("the home page always shows the session card, empty at first", function()
    local ns, w = sessionWorld({ "XP" })
    local xp
    GulliToolkit.Register({ key = "XP", open = function() end, session = function() return xp end })
    ns.Toggle()
    local home = ns.Home()
    eq(home.session:IsShown(), true)
    eq(home.sesEmpty:IsShown(), true, "nothing yet: the card says what will come")
    eq(home.sesFull:IsShown(), false)
    eq(home.session.data.hero, nil)
    xp = { value = "19k", bars = { 1, 2, 3 }, progress = { value = 0.5, left = 47, right = "50%" } }
    ns.Refresh()
    eq(home.sesEmpty:IsShown(), false)
    eq(home.session.data.hero.row.key, "XP", "a click opens the module that leads")
    eq(home.sesBar:IsShown(), true)
    xp = nil
    w.money = 900; ns.SesEvent("PLAYER_MONEY")
    eq(home.session.data.hero.row, nil, "the core's own source opens nothing")
    eq(home.sesBar:IsShown(), false, "no level bar without a level")
    home.sessionOpen:GetScript("OnEnter")(home.sessionOpen)
    home.sessionOpen:GetScript("OnClick")(home.sessionOpen)
    eq(home.ready:IsShown(), true)
    ns.ReadySet("show", false)
    ns.Refresh()
    eq(ns.Home().ready:IsShown(), false, "the Ready card is a setting")
end)

test("the Recent feed joins lines of one module that follow each other", function()
    Fake({ addons = { QC } })
    local ns = Load()
    GulliToolkit.Notify("XP", "one")
    GulliToolkit.Notify("AutoQuest", "a")
    GulliToolkit.Notify("AutoQuest", "b")
    GulliToolkit.Notify("AutoQuest", "c")
    GulliToolkit.Notify("XP", "two")
    local rows = ns.FeedRows()
    eq(#rows, 3)
    eq(rows[1].text, "two")
    eq(rows[1].n, 1)
    eq(rows[2].key, "AutoQuest")
    eq(rows[2].text, "c", "the newest text")
    eq(rows[2].n, 3)
    eq(rows[3].text, "one", "the same module again after another is a row of its own")
end)

test("the Ready ring gives each check a run of marks with a dark one between", function()
    Fake({})
    local ns = Load()
    local marks = ns.RingTicks({ { ok = false }, { ok = true }, { ok = true } }, 12)
    eq(marks[1], false)
    eq(marks[3], false)
    eq(marks[4], nil, "the gap after the first check")
    eq(marks[5], true)
    eq(marks[8], nil)
    eq(marks[11], true)
    eq(marks[12], nil)
    marks = ns.RingTicks({ { ok = true } }, 12)
    eq(marks[12], true, "one check: a whole ring")
    local frac, mark = ns.ReadyBar(5, 10)
    eq(frac, 0.25, "the limit sits in the middle of the bar")
    eq(mark, 0.5)
    eq((ns.ReadyBar(50, 10)), 1, "never past the end")
    frac, mark = ns.ReadyBar(3, 0)
    eq(frac, 1, "no limit: a full bar")
    eq(mark, nil, "and no mark")
end)

test("Unlock frames is a link in the header; the Setup page holds the presets and the hub's switches", function()
    Fake({ addons = { QC } })
    local ns = Load()
    local shown = false
    GulliToolkit.Register({ key = "QuestCleaner", open = function() end,
        frames = { { key = "bar", label = "Bar", get = function() return shown end, set = function(v) shown = v end } } })
    ns.Toggle()
    local link = ns.UnlockLink()
    eq(link.text:GetText(), ns.L.UNLOCK)
    eq(link.count:GetText(), "0/1", "the frames that show, counted")
    shown = true
    ns.Refresh()
    eq(link.count:GetText(), "1/1")
    link:GetScript("OnClick")(link)
    eq(ns.moving, true, "a click starts the Unlock mode")
    ns.SetMoving(false)
    ns.OpenSetupPage()
    local view = ns.View()
    eq(view.page, "setup")
    eq(ns.Home():IsShown(), false)
    local page = ns.SetupPage()
    eq(page:IsShown(), true)
    page.scale.plus:GetScript("OnClick")(page.scale.plus)
    eq(GulliToolkitDB.scale, 1.1, "the window size moved here")
    page.scale.minus:GetScript("OnClick")(page.scale.minus)
    eq(GulliToolkitDB.scale, 1)
end)

test("the Setup page: the board switches a module, a waiting reload has its button", function()
    Fake({ addons = { QC, { name = "Gulli-Merchant", enabled = false, meta = { ["X-Gulli-Module"] = "Merchant" } },
                      { name = "Gulli-Loot", enabled = true, loaded = true, meta = { ["X-Gulli-Module"] = "Loot" } } } })
    local ns = Load()
    ns.Toggle()
    ns.OpenSetupPage()
    local page = ns.SetupPage()
    local board = page.board
    eq(board.shown, 3, "every installed module has an icon")
    eq(board.groups, 3, "a line per group that has modules")
    eq(page.waits, 0)
    eq(page.waitChip:IsShown(), false, "no reload button while nothing waits")
    local merchant
    for i = 1, board.shown do
        if board.icons[i].row.key == "Merchant" then merchant = board.icons[i] end
    end
    assert(merchant, "Merchant is on the board")
    eq(merchant.row.on, false)
    eq(merchant.dotIn:IsShown(), true, "off shows as a hollow dot, not by colour alone")
    merchant:GetScript("OnClick")(merchant)
    eq(byKey(ns.List()).Merchant.on, true, "a click on the icon switches the module on")
    eq(merchant.row.state, "reload", "the board shows the new state")
    eq(merchant.dotIn:IsShown(), false)
    eq(page.waits, 1)
    eq(page.waitChip:IsShown(), true, "the reload that waits is on the page")
    eq(W.reloaded, false, "the click that switches does not reload")
    page.waitChip:GetScript("OnClick")(page.waitChip)
    eq(W.reloaded, true, "its own click reloads")
    merchant:GetScript("OnClick")(merchant)
    eq(byKey(ns.List()).Merchant.on, false, "and a second click switches it off again")
end)

test("the Setup page: preset cards show their installed modules, the tools are tiles", function()
    Fake({ addons = { QC, { name = "Gulli-Merchant", enabled = false, meta = { ["X-Gulli-Module"] = "Merchant" } },
                      { name = "Gulli-Loot", enabled = true, loaded = true, meta = { ["X-Gulli-Module"] = "Loot" } } } })
    local ns = Load()
    ns.Toggle()
    ns.OpenSetupPage()
    local page = ns.SetupPage()
    eq(#page.presets, #ns.PRESETS)
    local have = byKey(ns.List())
    for i, p in ipairs(ns.PRESETS) do
        local n = 0
        for _, k in ipairs(p.modules) do if have[k] then n = n + 1 end end
        eq(page.presets[i].shown, n, p.key .. ": one small icon per installed module of the preset")
    end
    local min
    for _, c in ipairs(page.presets) do if c.key == "Minimum" then min = c end end
    min.apply:GetScript("OnClick")(min.apply)
    local now = byKey(ns.List())
    eq(now.Merchant.on, true, "Apply switches the preset's modules on")
    eq(now.Loot.on, false, "and the others off")
    eq(page.protect.value:GetText(), 0, "the protected items, counted on their tile")
    GulliToolkit.Protect(6948, true)
    ns.Refresh()
    eq(page.protect.value:GetText(), 1)
    page.protect:GetScript("OnClick")(page.protect)
    eq(ns.View().page, "protect")
    eq(ns.View().from, "setup", "a tool's page goes back to Setup")
    ns.OpenSetupPage()
    page.transfer:GetScript("OnClick")(page.transfer)
    eq(ns.View().page, "transfer")
    ns.OpenSetupPage()
    local pins = page.pins
    eq(pins.shown, 4, "the hub's button and one icon per installed module")
    eq(pins.icons[1].on, true, "the hub's own button is there from the start")
    eq(pins.count, 1, "and no module's")
    assert(pins.size >= 26, "big enough for a finger")
    pins.icons[1]:GetScript("OnClick")(pins.icons[1])
    eq(ns.MinimapShown(), false, "a click on the hub's icon hides its button")
    eq(pins.icons[1].dot:IsShown(), false, "the dot goes with it, not only the colour")
    pins.icons[1]:GetScript("OnClick")(pins.icons[1])
    eq(ns.MinimapShown(), true)
    local loot
    for i = 1, pins.shown do if pins.icons[i].row.key == "Loot" then loot = pins.icons[i] end end
    loot:GetScript("OnClick")(loot)
    eq(ns.Pinned("Loot"), true, "a click on a module's icon puts its button at the minimap")
    eq(loot.dot:IsShown(), true)
    eq(pins.hint:GetText(), ns.L.PIN_N:format(2, 4))
    loot:GetScript("OnClick")(loot)
    eq(ns.Pinned("Loot"), false, "and a second click takes it away")
end)

test("every texture path is written with double backslashes", function()
    local p = io.popen("ls Gulli-*/*.lua")
    for file in p:lines() do
        local n = 0
        for line in io.lines(file) do
            n = n + 1
            -- "Interface\Icons" in the source; a single backslash is eaten as an escape and
            -- the icon comes out empty.
            assert(not line:find('"Interface\\[^\\]'), file .. ":" .. n .. ": a path with a single backslash")
        end
    end
    p:close()
end)

test("the hub's emblem has a clear background", function()
    local f = assert(io.open("Gulli-Toolkit/Art/Mark.tga", "rb"))
    local data = f:read("*a")
    f:close()
    local w = data:byte(13) + data:byte(14) * 256
    local h = data:byte(15) + data:byte(16) * 256
    eq(#data, 18 + w * h * 4, "32 bit, not packed")
    local function alpha(x, y) return data:byte(18 + (y * w + x) * 4 + 4) end
    eq(alpha(0, 0), 0, "top left")
    eq(alpha(w - 1, 0), 0, "top right")
    eq(alpha(0, h - 1), 0, "bottom left: a picture with its own background shows as a pale square")
    eq(alpha(w - 1, h - 1), 0, "bottom right")
    local clear, some = 0, 0
    for y = 0, h - 1, 8 do
        for x = 0, w - 1, 8 do
            if alpha(x, y) == 0 then clear = clear + 1 else some = some + 1 end
        end
    end
    assert(some > 0 and clear > some / 4, "the emblem is a shape, not a filled square")
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
        assert(type(p.icon) == "string" and p.icon:find("^Interface\\Icons\\"), "no icon for preset " .. p.key)
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
    assert(all:find("/gulli unlock", 1, true), "help names the toolkit's commands")
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

test("a module's name in the game has no Gulli prefix, in the hub and in its own window", function()
    Fake({ addons = {} })
    local ns = Load()
    eq(ns.ShortName("Gulli-Zeta"), "Zeta"); eq(ns.ShortName("Gulli Zeta"), "Zeta"); eq(ns.ShortName("Gulli"), "Gulli")
    local p = io.popen("ls -d Gulli-*/")
    local n = 0
    for dir in p:lines() do
        local name = dir:gsub("/$", "")
        local fh = name ~= "Gulli-Toolkit" and io.open(name .. "/Locales.lua")
        if fh then
            local text = fh:read("*a"); fh:close()
            for title in text:gmatch('\n%s*TITLE = "([^"]*)"') do
                n = n + 1
                assert(not title:find("^Gulli"), name .. ": TITLE starts with Gulli: " .. title)
            end
            local core = io.open(name .. "/Core.lua")
            local body = core and core:read("*a") or ""
            if core then core:close() end
            assert(not body:find("title = ns.L.TITLE", 1, true), name .. ": the hub's own name is enough")
        end
    end
    p:close()
    assert(n > 0, "found the titles")
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
    ns.MeasureMemory()
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

test("the hub never measures the addons' memory while it draws: only a loading screen or a click", function()
    Fake({ addons = { { name = "Gulli-Chores", enabled = true, loaded = true, meta = { ["X-Gulli-Module"] = "Chores" } } } })
    local calls = 0
    UpdateAddOnMemoryUsage = function() calls = calls + 1 end
    GetAddOnMemoryUsage = function() return 100 end
    local ns = Load()
    GulliToolkit.Register({ key = "Chores", open = function() end, slash = "/gch" })
    eq(ns.Overview().kb, 0, "nothing measured yet: no memory shown")
    ns.Toggle(); ns.Refresh(); ns.Overview()
    eq(calls, 0, "opening and drawing the hub never measures")
    ns.MeasureMemory()
    eq(calls, 1)
    eq(ns.Overview().kb, 100, "the last measure shows")
    ns.Toggle(); ns.Toggle()
    eq(calls, 1, "a second open reads the last numbers")
    UpdateAddOnMemoryUsage, GetAddOnMemoryUsage = nil, nil
end)

test("the home page asks the modules a few a frame, so opening the hub never stops the game", function()
    local addons = {}
    local keys = { "XP", "Chores", "Loot", "Mail", "Social", "Merchant" }
    for _, k in ipairs(keys) do
        addons[#addons + 1] = { name = "Gulli-" .. k, enabled = true, loaded = true, meta = { ["X-Gulli-Module"] = k } }
    end
    Fake({ addons = addons })
    local ns = Load()
    local asked = 0
    for _, k in ipairs(keys) do
        GulliToolkit.Register({ key = k, open = function() end, summary = function() asked = asked + 1; return "3 things" end })
    end
    local t = 0
    debugprofilestop = function() t = t + 3; return t end -- every look at the clock costs 3 ms
    ns.Toggle()
    local S = ns.Skin
    assert(S.JobRunning("hubHome"), "the home page goes on in the next frames")
    assert(asked < #keys, "not every module in the first frame: " .. asked)
    local driver
    for _, f in ipairs(W.frames) do
        if f:GetScript("OnUpdate") then driver = f end
    end
    local frames = 0
    while S.JobRunning("hubHome") and frames < 100 do
        driver:GetScript("OnUpdate")(driver)
        frames = frames + 1
    end
    debugprofilestop = nil
    assert(not S.JobRunning("hubHome"))
    assert(frames > 0)
    eq(asked, #keys, "every module was asked once")
    assert(ns.perf and ns.perf.total > 0, "/gulli perf has the open")
    local named = {}
    for _, st in ipairs(ns.perf.steps) do named[st.name] = true end
    assert(named.Tiles and named["Module list"], "the steps are named")
    ns.PrintPerf()
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

test("Gulli HUD: short keys, notices stack and replace by key, icons show their state", function()
    Fake({})
    local ns = Load()
    local S = ns.Skin
    eq(S.ShortKey("SHIFT-F"), "sF")
    eq(S.ShortKey("CTRL-BUTTON4"), "cM4")
    eq(S.ShortKey(nil), "")
    GulliHUD = nil
    local a = S.Toast({ key = "a", title = "A", seconds = 5 })
    local b = S.Toast({ key = "b", title = "B", buttons = { { text = "Go", primary = true } } })
    eq(#GulliHUD.toasts, 2)
    eq(GulliHUD.toasts[1], b, "the newest is on top")
    eq(S.Toast({ key = "a", title = "A again" }), a, "the same key reuses its card")
    eq(#GulliHUD.toasts, 2)
    eq(a.title:GetText(), "A again")
    a:Dismiss()
    eq(#GulliHUD.toasts, 1, "a closed card leaves the stack")
    local closed = false
    local c = S.Toast({ key = "c", title = "C", seconds = 1, onClose = function() closed = true end })
    c:GetScript("OnUpdate")(c, 2)
    eq(c:IsShown(), false, "the card hides when its time runs out")
    eq(closed, true)
    local icon = S.HudIcon(CreateFrame("Button"), 40)
    icon:SetState("need")
    eq(icon.pulser:IsShown(), true, "a missing one pulses")
    icon:SetState("soon")
    eq(icon.pulser:IsShown(), false)
    icon:SetKey("ALT-Q")
    eq(icon.key:GetText(), "aQ")
end)

test("move mode shows the grid and the bar, and a fight ends it", function()
    Fake({})
    local ns = Load()
    local moved
    GulliToolkit.Register({ key = "XP", open = function() end, move = function(on) moved = on end })
    eq(ns.SetMoving(true), 1)
    eq(moved, true)
    eq(ns.MoveGrid():IsShown(), true)
    eq(ns.MoveGrid().bar:IsShown(), true)
    for _, f in ipairs(W.frames) do
        local fn = f.GetScript and f:GetScript("OnEvent")
        if fn then fn(f, "PLAYER_REGEN_DISABLED") end
    end
    eq(ns.moving, false)
    eq(moved, false)
    eq(ns.MoveGrid().bar:IsShown(), false)
end)

test("the Unlock mode lists every frame with its switch; Cancel puts the switches back, Save keeps them", function()
    local XPA = { name = "Gulli-XP", enabled = true, loaded = true,
                  meta = { ["X-Gulli-Module"] = "XP", Title = "Gulli-XP" } }
    Fake({ addons = { XPA } })
    local ns = Load()
    local on, built = true, 0
    local bar = CreateFrame("Frame")
    GulliToolkit.Register({ key = "XP", open = function() end, move = function() end,
        frames = { { key = "bar", get = function() return on end, set = function(v) on = v end,
                     frame = function() built = built + 1; return bar end } } })
    local frames = ns.Frames()
    eq(#frames, 2, "the bar and the notices")
    eq(frames[1].module, "XP"); eq(frames[1].key, "bar")
    eq(frames[1].label, "XP bar", "the hub's own name for the frame")
    eq(frames[2].key, "toasts"); eq(frames[2].get, nil, "notices only get a place")
    eq(select(2, ns.FrameCount(frames)), 1)
    ns.SetMoving(true)
    assert(ns.UnlockPanel():IsShown(), "the panel shows")
    assert(built > 0, "the hub asks the module for its frame")
    ns.SetFrameShown(ns.Frames()[1], false)
    eq(on, false)
    ns.SetMoving(false, true)
    eq(on, true, "Cancel shows it again")
    eq(ns.moving, false)
    ns.SetMoving(true)
    ns.SetFrameShown(ns.Frames()[1], false)
    ns.SetMoving(false)
    eq(on, false, "Save keeps it hidden")
    eq(GulliToolkit.Unlock(), true)
    eq(ns.moving, true, "a module's button opens the Unlock mode")
    ns.SetMoving(false)
end)

test("the Unlock mode never starts in a fight, lists module icons and darkens a frame switched off", function()
    local XPA = { name = "Gulli-XP", enabled = true, loaded = true,
                  meta = { ["X-Gulli-Module"] = "XP", Title = "Gulli-XP", IconTexture = "Interface\\AddOns\\Gulli-XP\\icon" } }
    Fake({ addons = { XPA } })
    local ns = Load()
    local S = ns.Skin
    local on, moved = true, nil
    local bar = CreateFrame("Frame")
    S.Mover(bar, { label = "XP bar" })
    GulliToolkit.Register({ key = "XP", open = function() end, move = function(v) moved = v end,
        frames = { { key = "bar", icon = "Interface\\Icons\\Spell_Holy_Heal", get = function() return on end,
                     set = function(v) on = v end, frame = function() return bar end } } })
    local row
    for _, r in ipairs(ns.List()) do if r.key == "XP" then row = r end end
    eq(ns.Frames()[1].icon, row.icon, "a module frame shows the module's own icon")
    _G.InCombatLockdown = function() return true end
    eq(ns.SetMoving(true), nil, "a fight refuses the start")
    eq(ns.moving, false); eq(moved, nil, "no module is asked to move in a fight")
    GulliToolkit.Unlock()
    eq(ns.moving, false)
    _G.InCombatLockdown = nil
    ns.SetMoving(true)
    eq(bar.mover.off, false)
    ns.SetFrameShown(ns.Frames()[1], false)
    eq(bar.mover.off, true, "the switched off frame is darkened")
    assert(bar.mover.name.text:GetText():find(ns.L.UNLOCK_OFF, 1, true), "and marked hidden")
    ns.SetFrameShown(ns.Frames()[1], true)
    eq(bar.mover.off, false)
    ns.SetMoving(false)
end)

test("the hub steps aside in the Unlock mode and comes back after Save or Cancel", function()
    Fake({})
    local ns = Load()
    ns.Toggle()
    local _, hub = ns.View()
    eq(hub:IsShown(), true)
    ns.SetMoving(true)
    eq(hub:IsShown(), false, "the hub hides while frames are placed")
    ns.SetMoving(false)
    eq(hub:IsShown(), true, "Save brings it back")
    ns.SetMoving(true)
    ns.SetMoving(false, true)
    eq(hub:IsShown(), true, "Cancel brings it back")
    hub:Hide()
    ns.SetMoving(true)
    ns.SetMoving(false)
    eq(hub:IsShown(), false, "a closed hub stays closed")
end)

test("an edit box hint hides while there is text, even after the module sets OnTextChanged", function()
    Fake({ addons = { QC } })
    local ns = Load()
    local S = ns.Skin
    -- Like the game: SetScript drops the hooks set before it.
    local edit = { text = "", hooks = {} }
    function edit:GetText() return self.text end
    function edit:HookScript(_, fn) self.hooks[#self.hooks + 1] = fn end
    function edit:SetScript(_, fn) self.handler, self.hooks = fn, {} end
    function edit:CreateFontString() return stubText() end
    local function type(s)
        edit.text = s
        if edit.handler then edit.handler(edit) end
        for _, h in ipairs(edit.hooks) do h(edit) end
    end
    local hint = S.Placeholder(edit, "Search a name")
    local refreshed = 0
    edit:SetScript("OnTextChanged", function() refreshed = refreshed + 1 end)
    type("Гул")
    eq(hint.shown, false, "hint hidden while typing")
    eq(refreshed, 1, "the module's own handler still runs")
    type("")
    eq(hint.shown, true, "hint back on an empty box")
end)

test("text uses a font family with Cyrillic and CJK glyphs when the game has one", function()
    Fake({ addons = { QC } })
    local made = {}
    CreateFontFamily = function(name, members)
        local alphabets = {}
        for _, m in ipairs(members) do alphabets[m.alphabet] = m.file end
        made[name] = alphabets
        return { name = name }
    end
    local ns = Load()
    local t = stubText()
    ns.Skin.SetFont(t, 13)
    CreateFontFamily = nil
    local f = made.GulliHearthbody13
    assert(f, "family made")
    assert(f.russian and f.korean and f.simplifiedchinese)
    assert(f.roman:find("FiraSans%-Medium"), "body text in Fira Sans")
    eq(f.korean, "Fonts\\2002.TTF", "Korean keeps the game's font")
    eq(t.object and t.object.name, "GulliHearthbody13", "the text uses the family")
    CreateFontFamily = function(name, members)
        local alphabets = {}
        for _, m in ipairs(members) do alphabets[m.alphabet] = m.file end
        made[name] = alphabets
        return { name = name }
    end
    ns.Skin.SetFont(t, 20, nil, "title")
    CreateFontFamily = nil
    eq(made.GulliHearthtitle20.roman, "Fonts\\FRIZQT__.TTF", "titles in Friz Quadrata by path")
    eq(made.GulliHearthtitle20.russian, "Fonts\\FRIZQT___CYR.TTF")
end)

test("tabs take an icon per label, and an empty label shows the icon alone with a tooltip", function()
    Fake({ addons = { QC } })
    local ns = Load()
    local S = ns.Skin
    local t = S.Tabs(CreateFrame("Frame"), { "Rules", "" }, 60, nil, nil, { S.TAB.rules, "dice" })
    assert(rawget(t.buttons[1], "btnIcon"), "a labelled tab has its icon")
    assert(rawget(t.buttons[2], "btnIcon"), "an icon-only tab has its icon")
    local shown
    GameTooltip = { SetOwner = function() end, SetText = function(_, s) shown = s end, Show = function() end, Hide = function() end }
    t.buttons[2].tip = "Need"
    t.buttons[2]._OnEnter(t.buttons[2])
    GameTooltip = nil
    eq(shown, "Need", "the cursor names an icon-only tab")
end)

test("an icon tile shows its title and count and greys out when disabled", function()
    Fake({ addons = { QC } })
    local ns = Load()
    local S = ns.Skin
    local tile = S.IconTile(CreateFrame("Frame"), 80, 52, true)
    tile.title, tile.item.count = stubText(), stubText()
    local texts = {}
    tile.title.SetText = function(_, v) texts.title = v end
    tile.item.count.SetText = function(_, v) texts.count = v end
    tile:Set({ icon = "x", title = "Cloth", count = 3 })
    eq(texts.title, "Cloth"); eq(texts.count, "3")
    tile:Set({ icon = "x", title = "Herbs", count = 0 })
    eq(texts.count, "", "no count on an empty kind")
end)

test("an icon tile dims exactly when it is disabled, also without OnEnable/OnDisable", function()
    -- the game sends no OnDisable to a hidden frame, so the look must follow SetEnabled
    Fake({ addons = { QC } })
    local S = Load().Skin
    local tile = S.IconTile(CreateFrame("Frame"), 80, 52, true)
    local alpha
    tile.item.SetAlpha = function(_, a) alpha = a end
    tile:SetEnabled(false)
    eq(alpha, 0.4, "an empty kind is dim")
    tile:SetEnabled(true)
    eq(alpha, 1, "a kind with items is bright")
    alpha = nil
    tile:GetScript("OnEnable")(tile)
    eq(alpha, 1, "a late OnEnable reads the state, never flips it")
end)

test("a button with an icon keeps its text after the icon when hovered or pressed", function()
    Fake({ addons = { QC } })
    local S = Load().Skin
    local b = S.Button(CreateFrame("Frame"), 120, 30)
    S.SetButtonIcon(b, "Interface\\Icons\\INV_Misc_Map_01")
    local left = {}
    rawset(b, "text", setmetatable({ SetPoint = function(_, p, x, y) if p == "LEFT" then left[#left + 1] = { x, y } end end },
                                   { __index = function() return function() end end }))
    b:GetScript("OnEnter")(b)
    eq(left[#left][1], 27, "hover keeps the text after the icon")
    b.down = true
    b:GetScript("OnEnable")(b)
    eq(left[#left][1], 27, "a press keeps it too")
    eq(left[#left][2], -1, "a press moves it one pixel down")
    local tile = S.IconTile(CreateFrame("Frame"), 120)
    local before = #left
    rawset(tile, "text", b.text)
    tile:GetScript("OnEnter")(tile)
    eq(#left, before, "a tile's title keeps its own place")
end)

test("money shows each coin in its colour, no copper from 1 gold, a loss keeps its minus", function()
    Fake({ addons = { QC } })
    local S = Load().Skin
    local plain = function(t) return (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    eq(plain(S.MoneyText(26664)), "2g 66s")
    eq(plain(S.MoneyText(20064)), "2g")
    eq(plain(S.MoneyText(6664)), "66s 64c")
    eq(plain(S.MoneyIcons(26664)):find("Copper", 1, true), nil)
    eq(plain(S.MoneyText(26664, true)), "2g 66s")
    eq(plain(S.MoneyText(-150)), "-1s 50c")
    eq(plain(S.MoneyText(0)), "0c")
    assert(S.MoneyText(26664):find(S.Hex(S.GOLD) .. "2g", 1, true), "gold in the gold colour")
    assert(S.MoneyText(6664):find(S.Hex(S.COPPER) .. "64c", 1, true), "copper in the copper colour")
end)

test("money on a coloured button: plain numbers with the game's coin pictures, no colour codes", function()
    Fake({ addons = { QC } })
    local S = Load().Skin
    local t = S.MoneyIcons(26664, true)
    assert(not t:find("|c", 1, true), "no colour codes")
    eq((t:gsub("|T.-UI%-(%a+)Icon.-|t", "%1")), "2Gold 66Silver")
    eq((S.MoneyIcons(0):gsub("|T.-UI%-(%a+)Icon.-|t", "%1")), "0Copper")
    eq((S.MoneyIcons(-150):gsub("|T.-UI%-(%a+)Icon.-|t", "%1")), "-1Silver 50Copper")
end)

test("errors of Gulli addons are kept to copy, others only go on to the game", function()
    local W = Fake({ addons = { { name = "Gulli-XP", meta = { Version = "1.4.0" } } } })
    local ns = Load()
    W.handler("Interface/AddOns/Gulli-XP/Core.lua:12: attempt to index a nil value")
    W.handler("Interface/AddOns/OtherAddon/Main.lua:3: boom")
    W.stack = "[string \"@Interface/AddOns/Gulli-XP/UI.lua\"]:40: in function <...>\n[C]: in ?"
    W.handler("attempt to compare number with nil")
    W.handler("Interface/AddOns/Gulli-XP/Core.lua:12: attempt to index a nil value")
    eq(#W.handled, 4, "every error still reaches the handler that was there before")
    local list = ns.Errors()
    eq(#list, 2, "two different Gulli errors; the other addon's is not kept")
    eq(list[1].msg, "Interface/AddOns/Gulli-XP/Core.lua:12: attempt to index a nil value", "a repeat moves to the top")
    eq(list[1].count, 2)
    eq(list[1].version, "1.4.0")
    eq(list[2].addon, "Gulli-XP", "found from the stack")
    -- the game's blocked calls name the addon
    for _, f in ipairs(W.frames) do
        local h = rawget(f, "_OnEvent")
        if h then h(f, "ADDON_ACTION_BLOCKED", "Gulli-Crates", "C_AuctionHouse.ConfirmCommoditiesPurchase()") end
    end
    eq(ns.Errors()[1].kind, "blocked")
    eq(ns.Errors()[1].addon, "Gulli-Crates")
    local text = ns.ErrorsText()
    assert(text:find("client 1.16.1 (70783)", 1, true), text)
    assert(text:find("Gulli-XP 1.4.0, 2x", 1, true), text)
    assert(text:find("ConfirmCommoditiesPurchase", 1, true), text)
    eq(ns.Overview().errors, 3)
    ns.OpenErrors()
    local view = ns.View()
    eq(view.page, "errors", "the Errors line and /gulli errors open the errors page")
    ns.ClearErrors()
    eq(#ns.Errors(), 0)
    eq(ns.Overview().errors, 0)
    for i = 1, ns.ERRORS_MAX + 5 do W.handler("Interface/AddOns/Gulli-XP/Core.lua:" .. i .. ": x") end
    eq(#ns.Errors(), ns.ERRORS_MAX, "at most ERRORS_MAX kept")
    eq(ns.RecordError(nil, nil), nil, "nothing to keep without a Gulli file")
end)

test("Reduce motion: the Setup page's switch saves calm, and calm stops every animation", function()
    Fake({})
    local ns = Load()
    local S = ns.Skin
    ns.Toggle()
    local sw = ns.SetupPage().calm.switch
    eq(sw:GetChecked(), false, "off by default")
    eq(S.Calm(), false)
    sw:GetScript("OnClick")(sw)
    eq(GulliToolkitDB.calm, true, "saved")
    eq(S.Calm(), true, "the skin reads it")
    eq(sw:GetChecked(), true)
    local f = CreateFrame("Frame")
    local seen
    S.Tween(f, "x", 0, 10, 0.4, function(v) seen = v end)
    eq(seen, 10, "a calm tween jumps to its end")
    eq(rawget(f, "gulliTweens"), nil, "and starts no timer")
    S.MotionIn(f, 8)
    eq(rawget(f, "gulliMotion"), nil, "no animation group while calm")
    sw:GetScript("OnClick")(sw)
    eq(GulliToolkitDB.calm, nil, "off again")
end)

test("the hub builds the side list with its selection plate and opens on Home", function()
    Fake({ addons = { QC } })
    local ns = Load()
    GulliToolkit.Register({ key = "QuestCleaner", open = function() end })
    ns.Toggle()
    ns.Enter(nil)
    ns.Refresh()
    local view = ns.View()
    eq(view.page, "home")
end)

test("Ready: repairs, bags, food and drink apart, the hearthstone and class supplies, each against its limit", function()
    Fake({ addons = { QC } })
    -- Bag 0: 3 bread, 4 water; 5 free slots. Gear at 40%.
    local items = { [1] = { itemID = 4540, stackCount = 3 }, [2] = { itemID = 159, stackCount = 4 } }
    C_Container = {
        GetContainerNumSlots = function(bag) return bag == 0 and 8 or 0 end,
        GetContainerNumFreeSlots = function(bag) return bag == 0 and 5 or 0, 0 end,
        GetContainerItemInfo = function(bag, slot) return bag == 0 and items[slot] or nil end,
        GetItemCooldown = function() return 100, 1800 end,
    }
    C_Item = { GetItemInfo = function() end, GetItemInfoInstant = function() return 1, "", "", "", 0, 0, 5 end,
               GetItemSpell = function(id) return id == 159 and "Drink" or "Food" end,
               GetItemCount = function() return 0 end }
    C_Spell = { GetSpellName = function(id) return id == 430 and "Drink" or "?" end }
    GetInventoryItemDurability = function(slot) if slot == 1 then return 40, 100 end end
    GetTime = function() return 400 end
    UnitLevel = function() return 50 end
    local ns = Load()
    local by = {}
    for _, c in ipairs(ns.Readiness()) do by[c.key] = c end
    eq(by.REPAIR.ok, false, "40% is under 50%")
    eq(by.REPAIR.value, "40%")
    eq(by.BAGS.value, "5")
    eq(by.BAGS.ok, false, "5 free slots is under 6")
    eq(by.FOOD.value, "3", "only the bread")
    eq(by.DRINK.value, "4", "only the water")
    eq(by.HEARTH.ok, false, "the hearthstone waits")
    eq(by.HEARTH.text, "Hearthstone in 25 min")
    eq(by.REPAIR.frac, 0.4, "the bar of the gear is its durability")
    eq(by.REPAIR.mark, 0.5, "with the limit marked on it")
    eq(by.REPAIR.label, ns.L.RD_L_REPAIR, "a short name beside the bar")
    assert(by.HEARTH.frac > 0.16 and by.HEARTH.frac < 0.17, "the hearthstone's bar fills as the cooldown runs out")
    eq(by.HEARTH.mark, nil)
    eq(by.REAGENT.ok, false, "a priest of 50 has no candles")
    -- Legacy's Reagent Economy: the priest needs no candles, and the switch is per character
    ns.SetReagentEconomy(true)
    eq(GulliToolkitCharDB.reagentEconomy, true)
    by = {}
    for _, c in ipairs(ns.Readiness()) do by[c.key] = c end
    eq(by.REAGENT, nil, "no candle check with Reagent Economy")
    UnitClass = function() return "Rogue", "ROGUE" end
    by = {}
    for _, c in ipairs(ns.Readiness()) do by[c.key] = c end
    assert(by.REAGENT, "Vanish still takes Flash Powder")
    UnitClass = function() return "Priest", "PRIEST" end
    -- Gulli Restock keeps the same switch: its answer counts, and a change goes to it too
    local restockOn
    GulliRestock = { ReagentEconomy = function() return restockOn == true end,
                     SetReagentEconomy = function(on, quiet) restockOn = on; assert(quiet, "no echo back") end }
    eq(ns.ReagentEconomy(), false, "Restock's answer")
    ns.SetReagentEconomy(true)
    eq(restockOn, true)
    GulliRestock = nil
    ns.SetReagentEconomy(false)
    eq(GulliToolkitCharDB.reagentEconomy, nil)
    ns.ReadySet("durMin", 30)
    ns.ReadySet("bagsMin", 5)
    by = {}
    for _, c in ipairs(ns.Readiness()) do by[c.key] = c end
    eq(by.REPAIR.ok, true, "the limit is a setting")
    eq(by.BAGS.ok, true)
    eq(GulliToolkitDB.ready.durMin, 30, "saved in the hub's own settings")
    UnitClass = function() return "Warrior", "WARRIOR" end
    by = {}
    for _, c in ipairs(ns.Readiness()) do by[c.key] = c end
    eq(by.DRINK, nil, "a warrior does not drink")
    ns.ReadyReset()
    eq(ns.ReadyGet("durMin"), 50, "back to the default")
    GulliRestock = { Missing = function() return { { name = "Ice Cold Milk", have = 5, want = 20 },
        { name = "Arrow", have = 0, want = 1000 }, { name = "Light Feather", have = 2, want = 10 } } end }
    by = {}
    for _, c in ipairs(ns.Readiness()) do by[c.key] = c end
    eq(by.RESTOCK.ok, false, "Restock's list misses three")
    eq(by.RESTOCK.value, "3")
    assert(by.RESTOCK.text:find("Ice Cold Milk 5/20, Arrow 0/1000, ...", 1, true), by.RESTOCK.text)
    GulliRestock.Missing = function() return {} end
    by = {}
    for _, c in ipairs(ns.Readiness()) do by[c.key] = c end
    eq(by.RESTOCK.ok, true, "nothing missing")
    ns.ReadySet("show", false)
    eq(ns.ReadyGet("show"), false, "the card can be hidden")
    GulliRestock = nil
end)

local function mod(name, key, extra)
    local a = { name = "Gulli-" .. name, enabled = true, loaded = true, meta = { ["X-Gulli-Module"] = key or name } }
    for k, v in pairs(extra or {}) do a[k] = v end
    return a
end

local function planBy(plan)
    local t = {}
    for _, p in ipairs(plan) do t[p.row.key] = p end
    return t
end

local function fire(event, ...)
    for _, f in ipairs(W.frames) do
        local h = rawget(f, "_OnEvent")
        if h then h(f, event, ...) end
    end
end

test("first setup: a module whose job another addon does starts off and says why", function()
    Fake({ addons = { mod("Merchant"), mod("Crates"), mod("XP"), mod("Mail"), mod("Social"),
                      { name = "Scrap", enabled = true, loaded = true }, { name = "Auctionator", enabled = true },
                      { name = "Postal", enabled = false } } })
    local ns = Load()
    local by = planBy(ns.SetupPlan())
    eq(by.Merchant.on, false, "Scrap sells junk")
    eq(by.Merchant.why, "Because you have Scrap")
    eq(by.Crates.on, true, "Crates reads Auctionator's prices")
    eq(by.Crates.why, "Works with Auctionator")
    eq(by.XP.on, true)
    eq(by.XP.why, nil, "nothing to say: no grey reason")
    eq(by.Mail.on, true, "Postal is installed but switched off: it does not count")
    eq(by.Social.on, true)
end)

test("first setup: Obvious Fishing does Fishing's job", function()
    Fake({ addons = { mod("Fishing"), { name = "ObviousFishing", enabled = true, loaded = true } } })
    local ns = Load()
    local by = planBy(ns.SetupPlan())
    eq(by.Fishing.on, false)
    eq(by.Fishing.why, "Because you have Obvious Fishing")
end)

test("first setup: Leatrix Plus counts only for the settings it has on", function()
    Fake({ addons = { mod("Merchant"), mod("AutoQuest"), mod("Social"), { name = "Leatrix_Plus", enabled = true, loaded = true } } })
    local ns = Load()
    LeaPlusDB = { AutoSellJunk = "Off", AutoRepairGear = "Off", AutomateQuests = "On" }
    local by = planBy(ns.SetupPlan())
    eq(by.Merchant.on, true, "Leatrix Plus neither sells nor repairs")
    eq(by.AutoQuest.on, false)
    eq(by.AutoQuest.why, "Because you have Leatrix Plus")
    eq(by.Social.on, true)
    LeaPlusDB.AutoRepairGear = "On"
    eq(planBy(ns.SetupPlan()).Merchant.on, false, "it repairs now")
    LeaPlusDB = nil
    by = planBy(ns.SetupPlan())
    eq(by.Merchant.on and by.AutoQuest.on, true, "settings it cannot read count as off")
end)

test("first setup: several addons are named together, the class can switch a module off", function()
    Fake({ addons = { mod("GroupBuffs"), mod("Reminders"), mod("MobFinder") } })
    local ns = Load()
    UnitClass = function() return "Rogue", "ROGUE" end
    local by = planBy(ns.SetupPlan({ SilverDragon = true, RareScanner = true, SmartBuff = true }))
    eq(by.MobFinder.on, false)
    assert(by.MobFinder.why:find("SilverDragon", 1, true) and by.MobFinder.why:find("RareScanner", 1, true), by.MobFinder.why)
    eq(by.Reminders.why, "Because you have SmartBuff")
    eq(planBy(ns.SetupPlan({})).GroupBuffs.why, "Because you play a Rogue")
    UnitClass = function() return "Priest", "PRIEST" end
    eq(planBy(ns.SetupPlan({})).GroupBuffs.on, true)
end)

test("first setup: every rule names a known module and a folder", function()
    Fake({})
    local ns = Load()
    for _, e in ipairs(ns.OTHERS) do
        assert(type(e.name) == "string" and e.name ~= "", "an entry without a name")
        assert(type(e.addons) == "table" and #e.addons > 0, e.name .. ": no folder")
        for _, part in ipairs({ "same", "with" }) do
            for key, v in pairs(e[part] or {}) do
                assert(ns.CATEGORY_OF[key], e.name .. ": unknown module " .. key)
                if type(v) == "table" then assert(e.db, e.name .. ": settings without a saved variable") end
            end
        end
    end
    for key in pairs(ns.CLASS_OFF) do assert(ns.CATEGORY_OF[key], "unknown module " .. key) end
end)

test("first setup: Apply switches as picked, a module that cannot pause asks for a reload", function()
    Fake({ addons = { mod("Merchant"), mod("XP"), mod("Mail") } })
    local ns = Load()
    GulliToolkit.Register({ key = "Merchant", open = function() end, pause = function() end })
    GulliToolkit.Register({ key = "XP", open = function() end })
    local plan = ns.SetupPlan({ Scrap = true })
    eq(ns.SetupNeedsReload(plan), false, "Merchant pauses at once")
    eq(ns.ApplySetup(plan), 1)
    eq(GulliToolkit.IsPaused("Merchant"), true)
    eq(GulliToolkitDB.setup, true)
    plan = ns.SetupPlan({})
    planBy(plan).XP.on = false
    eq(ns.SetupNeedsReload(plan), true, "XP has no pause")
    local win = ns.OpenSetup()
    assert(win, "the window opens from /gulli setup and Quick setup")
    win.apply:GetScript("OnClick")(win.apply)
    eq(W.reloaded, false, "nothing that needs a reload was picked")
end)

test("first setup: the reload gets its own click, and a failed module never stops the rest", function()
    Fake({ addons = { mod("XP"), mod("Mail"), mod("Bulletin") } })
    local ns = Load()
    local win, plan = ns.OpenSetup()
    for _, p in ipairs(plan) do p.on = false end
    eq(ns.SetupNeedsReload(plan), true)
    local real = ns.Switch
    ns.Switch = function(row, on)
        if row.key == "Mail" then error("boom") end
        return real(row, on)
    end
    win.apply:GetScript("OnClick")(win.apply)
    ns.Switch = real
    eq(W.reloaded, false, "the click that switches does not reload")
    eq(win:IsShown(), true, "the window stays for the reload")
    eq(win.apply:GetText(), ns.L.SETUP_RELOAD)
    eq(GulliToolkitDB.setup, true)
    for _, row in ipairs(ns.List()) do
        if row.key ~= "Mail" then eq(row.on, false, row.key .. " was switched off") end
    end
    win.apply:GetScript("OnClick")(win.apply)
    eq(W.reloaded, true, "the second click reloads")
end)

test("first setup: a switch changed after Apply applies again before the reload", function()
    Fake({ addons = { mod("XP"), mod("Mail") } })
    local ns = Load()
    local win, plan = ns.OpenSetup()
    planBy(plan).XP.on = false
    win.apply:GetScript("OnClick")(win.apply)
    eq(win.apply:GetText(), ns.L.SETUP_RELOAD)
    planBy(plan).XP.on = true
    eq(ns.SetupNeedsReload(plan), true, "XP is off in the game now")
    eq(ns.ApplySetup(plan), 1, "XP goes back on")
end)

test("first setup: the window opens by itself only when the toolkit has no settings yet", function()
    Fake({ addons = { mod("Merchant") } })
    local ns = Load()
    local opened = 0
    local real = ns.OpenSetup
    ns.OpenSetup = function(auto) opened = opened + 1; return real(auto) end
    fire("PLAYER_ENTERING_WORLD", true, false)
    eq(opened, 1, "first run")
    fire("PLAYER_ENTERING_WORLD", false, true)
    eq(opened, 1, "only once")

    Fake({ addons = { mod("Merchant") } })
    GulliToolkitDB = { feed = {} }
    ns = Load()
    opened = 0
    real = ns.OpenSetup
    ns.OpenSetup = function(auto) opened = opened + 1; return real(auto) end
    fire("PLAYER_ENTERING_WORLD", true, false)
    eq(opened, 0, "a player with settings is not asked")
    SlashCmdList.GULLITOOLKIT("setup")
    eq(opened, 1, "/gulli setup opens it")

    Fake({})
    ns = Load()
    eq(ns.OpenSetup(true), nil, "no module installed: nothing to ask")
end)

test("Gulli Hearth: S.Emph whitens numbers in plain text only; no text under 12", function()
    Fake({ addons = { QC } })
    local S = Load().Skin
    eq(S.Emph("Level 24 in 1 h"), "Level |cffffffff24|r in |cffffffff1|r h", "plain")
    eq(S.Emph("|cffff0000red 12|r x 3"), "|cffff0000red 12|r x |cffffffff3|r", "a colour code")
    eq(S.Emph("|Hitem:1234:0|h[Thing]|h 2"), "|Hitem:1234:0|h[Thing]|h |cffffffff2|r", "an item link")
    eq(S.Emph("|TInterface\\Icons\\X:14|t 5"), "|TInterface\\Icons\\X:14|t |cffffffff5|r", "a texture")
    eq(S.Emph(""), "", "empty")
    eq(S.Emph(nil), nil)
    local size
    local fs = { SetFontObject = function() end, SetFont = function(_, _, s) size = s end }
    local keep = CreateFontFamily
    CreateFontFamily = nil
    S.SetFont(fs, 9)
    eq(size, 12, "a 9 unit text becomes 12")
    S.SetFont(fs, 14.7)
    eq(size, 14, "whole units")
    CreateFontFamily = keep
end)

test("a right-click on the minimap button starts the Unlock mode, the next one saves it", function()
    local W = Fake({})
    local ns = Load()
    local b = ns.MinimapButton()
    b:GetScript("OnClick")(b, "RightButton")
    eq(ns.moving, true, "the frames are unlocked at once")
    local _, hub = ns.View()
    eq(hub ~= nil and hub:IsShown() or false, false, "the hub does not open for it")
    b:GetScript("OnClick")(b, "RightButton")
    eq(ns.moving, false, "a second right-click saves and locks")
    InCombatLockdown = function() return true end
    b:GetScript("OnClick")(b, "RightButton")
    eq(ns.moving, false, "never in a fight")
    InCombatLockdown = function() return false end
end)

test("a small module gets its own minimap button only when the player pins it", function()
    local W = Fake({ addons = { QC, { name = "Gulli-Loot", enabled = true, loaded = true, meta = { ["X-Gulli-Module"] = "Loot" } } } })
    local ns = Load()
    local opened, paused = 0, false
    GulliToolkit.Register({ key = "QuestCleaner", open = function() opened = opened + 1 end,
                            summary = function() return "4 grey quests" end })
    GulliToolkit.Register({ key = "Loot", open = function() end, pause = function(on) paused = on end })
    eq(#ns.Pins(), 0, "a small module has no button by default")
    eq(ns.PinButton("QuestCleaner"), nil, "and no button is made")
    eq(ns.MinimapButton():IsShown(), true, "only the hub's own button shows")

    ns.SetPinned("QuestCleaner", true)
    local b = ns.PinButton("QuestCleaner")
    assert(b and b:IsShown(), "pinned: the module has its button")
    local step = ns.pinStep
    eq(GulliToolkitDB.pins.QuestCleaner, 225 - step, "it starts beside the hub's button")
    b:GetScript("OnClick")(b, "LeftButton")
    eq(opened, 1, "a click opens the module")
    local tip = ns.PinTip(b.row)
    eq(tip[1].title, b.row.title)
    eq(tip[2].text, "4 grey quests", "the tooltip has the module's line of the home page")
    assert(tip[3].text:find(ns.L.MM_OPEN, 1, true))

    ns.SetPinned("Loot", true)
    eq(GulliToolkitDB.pins.Loot, 225 - 2 * step, "the next one takes the next free place")
    W.cursor = { 100, 0 }
    b:GetScript("OnDragStart")(b)
    b:GetScript("OnUpdate")(b)
    b:GetScript("OnDragStop")(b)
    eq(GulliToolkitDB.pins.QuestCleaner, 270, "a drag moves it around the minimap and is saved")
    eq(ns.PinButton("Loot"):IsShown(), true, "the other button stays")

    local rows = byKey(ns.List())
    ns.Switch(rows.Loot, false)
    eq(paused, true)
    eq(ns.PinButton("Loot"):IsShown(), false, "a paused module's button hides")
    eq(ns.Pinned("Loot"), true, "but stays pinned")
    ns.Switch(byKey(ns.List()).Loot, true)
    eq(ns.PinButton("Loot"):IsShown(), true, "and comes back with the module")

    ns.SetPinned("QuestCleaner", false)
    eq(b:IsShown(), false, "unpinned: the button is gone")
    eq(GulliToolkitDB.pins.QuestCleaner, false, "and the player's choice is kept")
end)

local function crates() return { name = "Gulli-Crates", enabled = true, loaded = true, meta = { ["X-Gulli-Module"] = "Crates" } } end

test("a module of ns.PIN_DEFAULT shows its button until the player turns it off", function()
    Fake({ addons = { crates(), QC } })
    local ns = Load()
    GulliToolkit.Register({ key = "Crates", open = function() end })
    GulliToolkit.Register({ key = "QuestCleaner", open = function() end })
    eq(ns.Pinned("Crates"), true, "nobody switched it: it shows")
    eq(ns.Pinned("QuestCleaner"), false, "a module not in the list does not")
    local b = ns.PinButton("Crates")
    assert(b and b:IsShown(), "the button is there without a click")
    eq(GulliToolkitDB.pins.Crates, 225 - ns.pinStep, "it took the first free place and keeps it")
    ns.SetPinned("Crates", false)
    eq(b:IsShown(), false)
    eq(GulliToolkitDB.pins.Crates, false, "turned off is remembered")

    Fake({ addons = { crates() } })
    GulliToolkitDB = { setup = true, pins = { Crates = false } }
    ns = Load()
    GulliToolkit.Register({ key = "Crates", open = function() end })
    eq(ns.Pinned("Crates"), false, "after a reload it stays off")
    eq(ns.PinButton("Crates"), nil)
    ns.SetPinned("Crates", true)
    eq(ns.PinButton("Crates"):IsShown(), true, "and the switch brings it back")
end)

test("a full ring of minimap buttons goes on to the second ring", function()
    Fake({})
    local ns = Load()
    local step = 30
    GulliToolkitDB.pins = {}
    for i = 1, 11 do GulliToolkitDB.pins["M" .. i] = (225 - i * step) % 360 end
    local a, ring = ns.FreeAngle(step, 20)
    eq(ring, 2, "no place left beside the hub's button")
    eq(a, 225 - 20, "the second ring starts beside it again")
    ns.SetPinAngle("M1", a, ring)
    eq(ns.PinRing("M1"), 2)
    eq(select(2, ns.FreeAngle(step, 20)), 1, "the place M1 left on the first ring is free again")
end)

-- A module's Skin.lua alone: GulliToolkit is not there, the module handed its table to ns.alone.
local function loadAlone(folder, info)
    local ns = { alone = info, L = { TITLE = folder } }
    local before = #W.frames
    assert(loadfile(folder .. "/Skin.lua"))(folder, ns)
    for i = before + 1, #W.frames do
        local on = rawget(W.frames[i], "_OnEvent")
        if on then on(W.frames[i], "PLAYER_LOGIN") end
    end
    return ns
end

test("a module without the hub shows its own minimap button, always", function()
    W = Fake({ addons = { { name = "Gulli-Crates", meta = { SavedVariables = "GulliCratesDB" } },
                          { name = "Gulli-VendorFlip", meta = { SavedVariables = "GulliVendorFlipDB" } } } })
    GulliToolkit, GulliHUD, GulliCratesDB, GulliVendorFlipDB = nil, nil, nil, nil
    local opened = 0
    local ns = loadAlone("Gulli-Crates", { key = "Crates", icon = "x", open = function() opened = opened + 1 end,
                                           summary = function() return "2 crates" end })
    local b = ns.aloneButton
    assert(b and b:IsShown(), "the button shows with no switch to ask")
    b:GetScript("OnClick")(b, "LeftButton")
    eq(opened, 1, "a click opens the module")
    eq(GulliCratesDB.gulliMap.angle, 200, "its place is kept in the module's own saved variable")
    local other = loadAlone("Gulli-VendorFlip", { key = "VendorFlip", open = function() end })
    assert(other.aloneButton, "a second module alone has its button too")
    eq(GulliVendorFlipDB.gulliMap.angle, 200 - ns.Skin.MapStep(1), "beside the first, not on it")
    W.cursor = { 100, 0 }
    b:GetScript("OnDragStart")(b)
    b:GetScript("OnUpdate")(b)
    b:GetScript("OnDragStop")(b)
    eq(GulliCratesDB.gulliMap.angle, 270, "a drag moves it")

    GulliToolkit = { Register = function() return true end }
    eq(loadAlone("Gulli-Crates", { key = "Crates", open = function() end }).aloneButton, nil,
       "with the hub there the module draws no button: the hub does")
    GulliToolkit = nil
end)

test("every module hands its Register table to ns.alone when the hub is not there", function()
    local p = io.popen("ls -d Gulli-*/")
    for d in p:lines() do
        d = d:gsub("/$", "")
        if d ~= "Gulli-Toolkit" then
            local found = false
            for _, f in ipairs({ "Core.lua", "UI.lua" }) do
                local h = io.open(d .. "/" .. f)
                if h then
                    local text = h:read("*a"); h:close()
                    if text:find("function(info) ns.alone = info end", 1, true) then found = true end
                end
            end
            assert(found, d .. " registers through `register` with the ns.alone fallback")
        end
    end
    p:close()
end)

test("pinned buttons come back after a reload, and the module page has the switch", function()
    Fake({ addons = { QC } })
    GulliToolkitDB = { setup = true, pins = { QuestCleaner = 180 } }
    local ns = Load()
    local S = ns.Skin
    local win = S.Window(nil, "Quest Cleaner", S.NARROW_W, 300)
    GulliToolkit.Register({ key = "QuestCleaner", open = function() end, window = function() return win end })
    assert(ns.PinButton("QuestCleaner") and ns.PinButton("QuestCleaner"):IsShown(), "the saved button shows once the module registers")
    ns.Toggle()
    ns.Enter("QuestCleaner")
    local box = ns.PinBox()
    eq(box:IsShown(), true, "the switch sits in the module page's header")
    eq(box.switch:GetChecked(), true)
    box.switch:GetScript("OnClick")(box.switch)
    eq(ns.Pinned("QuestCleaner"), false, "the switch takes the button away")
    eq(box.switch:GetChecked(), false)
    eq(ns.PinButton("QuestCleaner"):IsShown(), false)
    box.switch:GetScript("OnClick")(box.switch)
    eq(ns.Pinned("QuestCleaner"), true)
end)

test("the minimap tooltip names each action in colour", function()
    local ns = Load()
    local lines = ns.MinimapTip()
    eq(#lines, 5, "a title and four actions")
    eq(lines[1].title, ns.L.TITLE, "the title")
    assert(lines[2].text:find(ns.L.MM_CLICK_KEY, 1, true) and lines[2].text:find("|cffffd100", 1, true), "the click in yellow")
    assert(lines[3].text:find(ns.L.MM_RIGHT, 1, true), "the right-click")
    assert(lines[4].text:find(ns.L.MM_DRAG, 1, true), "the drag")
    assert(lines[5].text:find("/gulli minimap", 1, true), "the command")
end)

test("an item name the client has not loaded yet is asked for, never shown as item:123, and kept once known", function()
    Fake({})
    local ns = Load()
    local name, asked = nil, {}
    C_Item = { GetItemNameByID = function() return name end,
               RequestLoadItemDataByID = function(id) asked[#asked + 1] = id end }
    local redraws = 0
    ns.Refresh = function() redraws = redraws + 1 end
    eq(ns.ItemName(17028), nil, "not loaded yet")
    eq(asked[1], 17028, "the game is asked for it")
    ns.OnItemInfo(99999)
    eq(redraws, 0, "an item nobody waits for redraws nothing")
    name = "Holy Candle"
    ns.OnItemInfo(17028)
    eq(redraws, 1, "the page redraws when the name comes")
    eq(ns.ItemName(17028), "Holy Candle")
    name = nil
    eq(ns.ItemName(17028), "Holy Candle", "a name once known stays, even when the client drops it")
    C_Item = nil
end)

test("a bound key works on every keyboard layout", function()
    Fake({ addons = { QC } })
    local S = Load().Skin
    eq(S.KeyBase("Ъ"), "]", "a Russian letter names its US key")
    eq(S.KeyBase("CTRL-SHIFT-ж"), "CTRL-SHIFT-;", "modifiers stay")
    eq(S.KeyBase("F5"), "F5")
    eq(S.KeyBase("SHIFT--"), "SHIFT--", "the minus key")
    eq(table.concat(S.KeyVariants("]"), " "), "] Ъ ъ Ї ї")
    eq(table.concat(S.KeyVariants("ALT-Ъ"), " "), "ALT-] ALT-Ъ ALT-ъ ALT-Ї ALT-ї", "a key saved on another layout")
    eq(table.concat(S.KeyVariants("BUTTON4"), " "), "BUTTON4", "mouse buttons have one name")
    eq(#S.KeyVariants(nil), 0)
    for us, list in pairs(S.KEY_ALIASES) do
        for _, ch in ipairs(list) do eq(S.KeyBase(ch), us, "every letter names one key: " .. ch) end
    end
    local bound = {}
    local old = SetOverrideBindingClick
    SetOverrideBindingClick = function(_, _, key, button) bound[key] = button end
    S.BindKey(CreateFrame("Frame"), true, "Q", "B")
    SetOverrideBindingClick = old
    eq(bound.Q, "B"); eq(bound["Й"], "B"); eq(bound["й"], "B")
end)

test("a box border stays one screen pixel at any scale, so it never breaks", function()
    Fake({ addons = { QC } })
    local S = Load().Skin
    local oldPU = PixelUtil
    PixelUtil = { GetNearestPixelSize = function(u, k, minPx) return math.max(minPx, math.floor(u * k * 0.75 + 0.5)) / (k * 0.75) end }
    local scale = 1
    local texs = {}
    local f = { GetEffectiveScale = function() return scale end, IsVisible = function() return true end }
    function f:CreateTexture()
        local t = { w = 0, h = 0 }
        function t:SetTexture() end; function t:SetVertexColor() end; function t:SetPoint() end
        function t:SetAllPoints() end; function t:SetTexCoord() end
        function t:SetWidth(v) self.w = v end; function t:SetHeight(v) self.h = v end
        function t:SetSize(a, b) self.w, self.h = a, b end
        texs[#texs + 1] = t
        return t
    end
    S.Box(f, nil, nil, 13)
    local lines = f.hair
    eq(#lines, 4, "four straight edges")
    for _, h in ipairs(lines) do
        local v = h[2] == "v" and h[1].w or h[1].h
        assert(math.abs(v * 0.75 - 1) < 1e-9, "one pixel at 0.75 pixels a unit, got " .. v)
    end
    scale = 1.2
    S.SnapLines()
    for _, h in ipairs(lines) do
        local v = h[2] == "v" and h[1].w or h[1].h
        assert(math.abs(v * 1.2 * 0.75 - 1) < 1e-9, "follows a new scale")
    end
    local g = { GetEffectiveScale = f.GetEffectiveScale, IsVisible = f.IsVisible, CreateTexture = f.CreateTexture }
    S.Box(g, nil, nil, 8, "top")
    eq(#g.hair, 8, "a sharp corner's two short edges are hairlines too")
    PixelUtil = oldPU
end)

test("a window that opens at a place closes with it, walking away too, once per visit", function()
    Fake({ addons = { QC } })
    local S = Load().Skin
    local made, hooks = {}, {}
    local oldCF, oldMail = CreateFrame, MailFrame
    CreateFrame = function()
        local f = { events = {} }
        function f:RegisterEvent(e) self.events[e] = true end
        function f:SetScript(_, fn) self.on = fn end
        made[#made + 1] = f
        return f
    end
    MailFrame = { HookScript = function(_, name, fn) hooks[name] = fn end }
    local closed = 0
    eq(S.ClosesWith("nowhere", function() end), false, "an unknown place")
    eq(S.ClosesWith("mail", function(place) eq(place, "mail"); closed = closed + 1 end), true)
    CreateFrame, MailFrame = oldCF, oldMail
    local f = made[#made]
    assert(f.events.MAIL_CLOSED and f.events.PLAYER_INTERACTION_MANAGER_FRAME_HIDE, "listens for both")
    assert(hooks.OnHide, "the mailbox frame's OnHide is hooked")
    f.on(f, "MAIL_CLOSED")
    eq(closed, 0, "no visit yet: nothing to close")
    f.on(f, "MAIL_SHOW")
    f.on(f, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", S.PlaceKind("merchant"))
    eq(closed, 0, "another place")
    f.on(f, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", S.PlaceKind("mail"))
    eq(closed, 1, "walking away")
    f.on(f, "MAIL_CLOSED")
    hooks.OnHide()
    eq(closed, 1, "once per visit")
    f.on(f, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", S.PlaceKind("mail"))
    hooks.OnHide()
    eq(closed, 2, "the game's frame hiding closes it too")
    for place in pairs(S.PLACES) do assert(S.PlaceKind(place), place) end
end)

-- Tweaks -----------------------------------------------------------------------------------------

local function tweakNs()
    Fake({ addons = { QC } })
    local ns = Load()
    return ns
end

test("own tweaks keep the page order whatever order their files load in", function()
    local ns = tweakNs()
    local keys = {}
    for _, t in ipairs(ns.TWEAKS) do keys[#keys + 1] = t.key end
    eq(keys[1], "levelShot")
    ns.AddTweak({ key = "spellRanks", group = "level" })
    eq(ns.TWEAKS[2].key, "spellRanks", "a tweak of the list goes to its place")
    eq(ns.AddTweak({ key = "bad", group = "nowhere" }), false, "a tweak needs a known group")
    eq(ns.AddTweak({ group = "ui" }), false, "and a key")
end)

test("every own tweak has its texts in every language, an icon and a known group", function()
    local ns = tweakNs()
    for _, t in ipairs(ns.TWEAKS) do
        local K = t.key:upper()
        for _, lang in ipairs(ns.TAGS) do
            assert(ns.T[lang]["TW_" .. K], lang .. " TW_" .. K)
            assert(ns.T[lang]["TW_" .. K .. "_D"], lang .. " TW_" .. K .. "_D")
        end
        assert(type(t.icon) == "string" and t.icon:match("^Interface\\"), t.key .. " icon")
        for _, part in ipairs(t.panel or {}) do
            assert(part.kind == "head" or part.key, t.key .. ": a setting without a key")
            assert(type(part.label) == "string" and not part.label:match("^TWP_"), t.key .. ": a setting without its text")
        end
    end
    for _, g in ipairs(ns.TWEAK_GROUPS) do
        for _, lang in ipairs(ns.TAGS) do assert(ns.T[lang]["TWG_" .. g:upper()], lang .. " TWG_" .. g:upper()) end
        assert(ns.TWEAK_GROUP_ICON[g], g .. " icon")
    end
end)

test("a tweak starts at login when on, and the switch starts and stops it at once", function()
    local ns = tweakNs()
    local log = {}
    ns.AddTweak({ key = "zzTest", group = "ui", icon = "Interface\\Icons\\X", defaults = { n = 3 },
        enable = function(get) log[#log + 1] = "on" .. get("n") end,
        disable = function() log[#log + 1] = "off" end })
    GulliToolkitDB.tweaks = { zzTest = { on = true, n = 5 } }
    ns.StartTweaks()
    eq(log[1], "on5", "a saved setting wins over the default")
    ns.SetTweak("zzTest", false)
    eq(log[2], "off")
    eq(ns.TweakOn("zzTest"), false)
    ns.SetTweak("zzTest", true)
    eq(log[3], "on5")
    ns.SetTweakOpt("zzTest", "n", 7)
    eq(log[4], "off", "a change without its own changed() starts the tweak again")
    eq(log[5], "on7")
    ns.SetTweak("zzTest", false)
    ns.SetTweakOpt("zzTest", "n", 8)
    eq(#log, 6, "a setting of a tweak that is off starts nothing")
    eq(ns.TweakGet("zzTest", "n"), 8)
end)

test("a tweak that breaks never stops the others", function()
    local ns = tweakNs()
    local started = false
    ns.AddTweak({ key = "aaBroken", group = "ui", icon = "Interface\\Icons\\X", enable = function() error("boom") end })
    ns.AddTweak({ key = "aaFine", group = "ui", icon = "Interface\\Icons\\X", enable = function() started = true end })
    GulliToolkitDB.tweaks = { aaBroken = { on = true }, aaFine = { on = true } }
    ns.StartTweaks()
    assert(started, "the next tweak still started")
end)

test("module rows come from Register, dim while the module is paused", function()
    Fake({ addons = { QC, { name = "Gulli-Loot", enabled = true, loaded = true, meta = { ["X-Gulli-Module"] = "Loot" } } } })
    local ns = Load()
    local db = { fast = true }
    GulliToolkit.Register({ key = "Loot", open = function() end, pause = function() end,
        tweaks = { { key = "fast", group = "loot", label = "Fast loot", desc = "Takes all",
                     get = function() return db.fast end, set = function(on) db.fast = on end },
                   { key = "broken", group = "nowhere", label = "x", get = function() end, set = function() end },
                   { key = "noset", group = "loot", label = "y", get = function() end } } })
    local rows = ns.TweakRows()
    local mod
    for _, r in ipairs(rows) do if r.kind == "module" then assert(not mod, "only the valid row"); mod = r end end
    eq(mod.key, "Loot:fast")
    eq(mod.on, true)
    eq(mod.live, true)
    eq(rows[#rows], mod, "module rows come after the own tweaks")
    eq(#ns.TweakFilter(rows, "all", "loot"), 1, "the search finds a row by its module's name")
    GulliToolkitDB.paused = { Loot = true }
    mod = ns.TweakRows()[#ns.TweakRows()]
    eq(mod.live, false, "a paused module lends a dim row")
    eq(mod.on, false)
end)

test("a module row may bring a panel of its own settings", function()
    Fake({ addons = { QC, { name = "Gulli-Loot", enabled = true, loaded = true, meta = { ["X-Gulli-Module"] = "Loot" } } } })
    local ns = Load()
    local db = { feed = true, rows = 5, bare = false }
    GulliToolkit.Register({ key = "Loot", open = function() end, pause = function() end,
        tweaks = { { key = "feed", group = "loot", label = "Loot feed",
                     get = function() return db.feed end, set = function(on) db.feed = on end,
                     panel = { { kind = "head", label = "Look" },
                               { kind = "switch", key = "bare", label = "No background",
                                 get = function() return db.bare end, set = function(v) db.bare = v end },
                               { kind = "step", key = "rows", label = "Lines", min = 1, max = 8,
                                 get = function() return db.rows end, set = function(v) db.rows = v end },
                               { kind = "switch", key = "bad", label = "Broken",
                                 get = function() error("x") end, set = function() error("y") end } } } } })
    local rows = ns.TweakRows()
    local mod = rows[#rows]
    eq(mod.key, "Loot:feed")
    eq(#mod.panel, 4)
    local get, set = ns.TweakPanelAccess(mod)
    eq(get("rows"), 5)
    eq(set("rows", 3), true)
    eq(db.rows, 3)
    set("bare", true)
    eq(get("bare"), true)
    eq(get("bad"), nil, "a part that fails reads as unset")
    eq(set("bad", true), false)
    eq(get("nothing"), nil)
end)

test("Recommended and Turn all off change only own tweaks, and Undo puts them back", function()
    local ns = tweakNs()
    local db = { fast = false }
    GulliToolkit.Register({ key = "Loot", open = function() end,
        tweaks = { { key = "fast", group = "loot", label = "Fast loot",
                     get = function() return db.fast end, set = function(on) db.fast = on end } } })
    ns.SetTweak("guildMotd", true)
    local was, n = ns.TweaksRecommended()
    for _, t in ipairs(ns.TWEAKS) do
        eq(ns.TweakOn(t.key), t.star == true or t.key == "guildMotd", t.key)
    end
    eq(n, ns.RecommendedCount())
    eq(db.fast, false, "a module's setting stays")
    ns.TweaksRestore(was)
    eq(ns.TweakOn("levelShot"), false, "Undo")
    eq(ns.TweakOn("guildMotd"), true, "Undo keeps what was on")
    was, n = ns.TweaksAllOff()
    eq(n, 1)
    eq(ns.TweakOn("guildMotd"), false)
    ns.TweaksRestore(was)
    eq(ns.TweakOn("guildMotd"), true)
end)

test("the filter, the counts and the groups of the page", function()
    local ns = tweakNs()
    ns.SetTweak("levelShot", true)
    local rows = ns.TweakRows()
    local c = ns.TweakCounts(rows)
    eq(c.all.on, 1)
    eq(c.level.on, 1)
    eq(c.people.total >= 1, true)
    eq(#ns.TweakFilter(rows, "on", ""), 1)
    local people = {}
    for _, r in ipairs(ns.TweakFilter(rows, "people", "")) do people[r.key] = r.group end
    eq(people.guildMotd, "people", "a group's filter keeps its rows")
    eq(#ns.TweakFilter(rows, "all", "screenshot"), 1, "the search reads the name and the line")
    local groups = ns.TweakGroups(rows)
    eq(groups[1].key, "level", "groups in the track's order, empty ones left out")
end)

test("level-up screenshot: a level, and an achievement only with its switch", function()
    local ns = tweakNs()
    local shots = 0
    Screenshot = function() shots = shots + 1 end
    ns.SetTweak("levelShot", true)
    ns.LevelShotEvent(nil, "PLAYER_LEVEL_UP")
    eq(shots, 1)
    ns.LevelShotEvent(nil, "ACHIEVEMENT_EARNED")
    eq(shots, 1, "no achievement shot by default")
    ns.SetTweakOpt("levelShot", "achievement", true)
    ns.LevelShotEvent(nil, "ACHIEVEMENT_EARNED")
    eq(shots, 2)
    Screenshot = nil
end)

test("guild message of the day: a notice once per text, nothing for a secret one", function()
    local ns = tweakNs()
    local shown = {}
    ns.Skin.Toast = function(o) shown[#shown + 1] = o.text end
    IsInGuild = function() return true end
    GetGuildRosterMOTD = function() return "Raid at 8" end
    ns.SetTweak("guildMotd", true)
    eq(shown[1], "Raid at 8", "at the switch")
    ns.GuildMotdEvent(nil, "GUILD_MOTD", "Raid at 8")
    eq(#shown, 1, "the same text once")
    ns.GuildMotdEvent(nil, "GUILD_MOTD", "Raid at 9")
    eq(shown[2], "Raid at 9")
    issecretvalue = function(v) return v == "secret" end
    ns.GuildMotdEvent(nil, "GUILD_MOTD", "secret")
    eq(#shown, 2)
    issecretvalue, IsInGuild, GetGuildRosterMOTD = nil, nil, nil
end)

test("appearance collector: new looks get a line and keep junk selling away, by its switches", function()
    local ns = tweakNs()
    -- item 1: new look; 2: a known look from another item; 3: another class's; 4: known
    C_TransmogCollection = {
        GetItemInfo = function(id) return id * 10, id * 100 end,
        PlayerKnowsSource = function(s) return s == 400 or s == 999 end,
        PlayerCanCollectSource = function(s) return true, s ~= 300 end,
        GetAllAppearanceSources = function(look) return look == 20 and { 200, 999 } or { look * 10 } end,
    }
    eq(ns.AppearanceState(1), "new"); eq(ns.AppearanceState(2), "source")
    eq(ns.AppearanceState(3), "alt"); eq(ns.AppearanceState(4), nil)
    eq(#ns.AppearanceTip(1), 0, "nothing while the tweak is off")
    eq(GulliToolkit.KeepsAppearance(1), false)
    ns.SetTweak("appearances", true)
    eq(#ns.AppearanceTip(1), 1)
    eq(#ns.AppearanceTip(2), 0, "another item of a known look only with its switch")
    eq(#ns.AppearanceTip(3), 0)
    ns.SetTweakOpt("appearances", "source", true)
    ns.SetTweakOpt("appearances", "alts", true)
    eq(#ns.AppearanceTip(2), 1); eq(#ns.AppearanceTip(3), 1); eq(#ns.AppearanceTip(4), 0)
    eq(GulliToolkit.KeepsAppearance(1), true, "junk selling keeps it")
    ns.SetTweakOpt("appearances", "keep", false)
    eq(GulliToolkit.KeepsAppearance(1), false, "unless the keep switch is off")
    ns.SetTweak("appearances", false)
    C_TransmogCollection = nil
end)

test("equip new bags: a new plain bag goes into an empty slot, never in a fight or with Shift", function()
    local ns = tweakNs()
    local bags = { [0] = { 101 }, [1] = {}, [2] = {}, [3] = {}, [4] = {} }
    local worn = { [31] = 50, [32] = 50, [33] = 50 }   -- the fourth bag slot is empty
    local put = {}
    C_Container = {
        GetContainerNumSlots = function(b) return (b == 0 and 16) or (worn[30 + b] and 6) or 0 end,
        GetContainerItemID = function(b, s) return bags[b] and bags[b][s] end,
        ContainerIDToInventoryID = function(b) return 30 + b end,
        PickupContainerItem = function(b, s) put.from = bags[b][s] end,
    }
    GetInventoryItemID = function(_, inv) return worn[inv] end
    C_Item.GetItemInfoInstant = function(id) return id, nil, nil, nil, nil, (id >= 100 and 1 or 4), (id == 102 and 2 or 0) end
    PutItemInBag = function(inv) put[#put + 1] = inv; worn[inv] = put.from end
    C_TooltipInfo = { GetItemByID = function() return { lines = { { leftText = "10 Slot Bag" } } } end }
    ns.SetTweak("autoBags", true)
    eq(#put, 0, "what was in the bags at the start is not new")
    bags[0][2] = 103
    IsShiftKeyDown = function() return true end
    eq(ns.EquipNewBags(), 0, "Shift skips it once"); IsShiftKeyDown = nil
    bags[0][3] = 102                                     -- a quiver-like bag: not plain
    InCombatLockdown = function() return true end
    bags[0][4] = 104
    eq(ns.EquipNewBags(), 0, "nothing in a fight")
    InCombatLockdown = nil
    eq(ns.EquipNewBags(), 1, "after the fight it goes on")
    eq(put[1], 34); eq(worn[34], 104)
    local toasts = {}
    ns.Skin.Toast = function(o) toasts[#toasts + 1] = o end
    bags[0][5] = 105
    eq(ns.EquipNewBags(), 0, "no empty slot")
    eq(#toasts, 1, "a bigger bag gets a notice")
    eq(toasts[1].buttons[1] ~= nil, true, "the smaller bag is empty: it can swap")
    toasts[1].buttons[1].onClick()
    eq(put[2], 31)
    ns.SetTweak("autoBags", false)
    C_Container, GetInventoryItemID, PutItemInBag, C_TooltipInfo, C_Item.GetItemInfoInstant = nil, nil, nil, nil, nil
end)

test("new spell ranks: a lower rank on a button gets the new one, a higher rank and a fight wait", function()
    local ns = tweakNs()
    local names = { [10] = "Fireball", [11] = "Fireball", [12] = "Fireball", [20] = "Frost Nova" }
    local ranks = { [10] = "Rank 1", [11] = "Rank 2", [12] = "Rank 3", [20] = "Rank 1" }
    local bar = { [1] = 10, [2] = 20, [3] = 12, [4] = 11 }
    C_Spell = { GetSpellName = function(id) return names[id] end,
        GetSpellSubtext = function(id) return ranks[id] end,
        PickupSpell = function(id) _G.held = id end }
    GetActionInfo = function(slot) if bar[slot] then return "spell", bar[slot] end end
    GetCursorInfo = function() return nil end
    PlaceAction = function(slot) bar[slot] = _G.held end
    ClearCursor = function() _G.held = nil end
    local fight = true
    InCombatLockdown = function() return fight end
    ns.SetTweak("spellRanks", true)
    ns.SpellRanksEvent(nil, "LEARNED_SPELL_IN_SKILL_LINE", 11)
    eq(bar[1], 10, "nothing changes in a fight")
    fight = false
    ns.SpellRanksEvent(nil, "PLAYER_REGEN_ENABLED")
    eq(bar[1], 11, "rank 1 became rank 2 after the fight")
    eq(bar[3], 12, "rank 3 stays: it is higher")
    eq(bar[2], 20, "another spell stays")
    eq(bar[4], 11)
    eq(#ns.LowerRankSlots(12), 2, "rank 3 would take both rank 2 buttons")
    C_Spell, GetActionInfo, GetCursorInfo, PlaceAction, ClearCursor, InCombatLockdown = nil, nil, nil, nil, nil, nil
end)

test("train all: everything the money covers, cheapest first, bought from the last index down", function()
    local ns = tweakNs()
    local services = { { "A", "available", 500 }, { "B", "used", 0 }, { "C", "available", 100 },
        { "D", "available", 2000 }, { "E", "unavailable", 10 } }
    GetNumTrainerServices = function() return #services end
    GetTrainerServiceInfo = function(i) return services[i][1], "", services[i][2] end
    GetTrainerServiceCost = function(i) return services[i][3] end
    local plan, total = ns.TrainPlan(1000)
    eq(#plan, 2)
    eq(plan[1].index, 3, "cheapest first")
    eq(total, 600)
    local bought = {}
    BuyTrainerService = function(i) bought[#bought + 1] = i end
    GetMoney = function() return 1000 end
    eq(ns.TrainAll(), 2)
    eq(bought[1], 3)
    eq(bought[2], 1, "the highest index first, so the others keep their place")
    GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceCost, BuyTrainerService, GetMoney = nil, nil, nil, nil, nil
end)

test("skip NPC talk: one ticked service opens, quests, two services and Shift keep the talk", function()
    local ns = tweakNs()
    ns.SetTweak("skipGossip", true)
    local get = ns.TweakGetter("skipGossip")
    local taxi = { icon = 132057, gossipOptionID = 7 }
    local inn = { icon = 132052, gossipOptionID = 8 }
    local shop = { icon = 132060, gossipOptionID = 9 }
    eq(ns.GossipPick({ taxi }, get), taxi)
    eq(ns.GossipPick({ inn, shop }, get), shop, "the innkeeper's shop: innkeepers are off")
    eq(ns.GossipPick({ taxi, shop }, get), nil, "two services keep the talk")
    eq(ns.GossipPick({ { icon = "Interface\\GossipFrame\\VendorGossipIcon" } }, get) ~= nil, true, "a classic path")
    local picked
    local quests = 0
    C_GossipInfo = { GetOptions = function() return { taxi } end,
        GetNumAvailableQuests = function() return quests end, GetNumActiveQuests = function() return 0 end,
        SelectOption = function(id) picked = id end }
    ns.SkipGossipEvent()
    eq(picked, 7)
    picked, quests = nil, 1
    ns.SkipGossipEvent()
    eq(picked, nil, "an NPC with quests keeps its talk")
    quests = 0
    IsShiftKeyDown = function() return true end
    ns.SkipGossipEvent()
    eq(picked, nil, "Shift shows the talk")
    IsShiftKeyDown, C_GossipInfo = nil, nil
end)

test("reward value: the dearest choice, nothing while a price loads or with one reward", function()
    local ns = tweakNs()
    eq(ns.BestReward({ 10, 50, 20 }, 3), 2)
    eq(ns.BestReward({ 10 }, 1), nil, "one reward is no choice")
    eq(ns.BestReward({ 0, 0 }, 2), nil, "nothing sells")
    local at, waiting = ns.BestReward({ 10, nil }, 2)
    eq(at, nil)
    eq(waiting, true, "waits for the item")
end)

test("hide quest tracker: always, or only in the places that are on", function()
    local ns = tweakNs()
    local o = { where = "places", dungeon = true, pvp = false, combat = false, guide = true }
    local g = function(k) return o[k] end
    eq(ns.TrackerHidden(g, { instance = "party" }), true)
    eq(ns.TrackerHidden(g, { instance = "pvp" }), false, "battlegrounds are off")
    eq(ns.TrackerHidden(g, { instance = "none", combat = true }), false)
    eq(ns.TrackerHidden(g, { instance = "none", guide = true }), true)
    o.where = "always"
    eq(ns.TrackerHidden(g, { instance = "none" }), true)
    local tracker = CreateFrame("Frame")
    tracker:Show()
    ObjectiveTrackerFrame = tracker
    IsInInstance = function() return true, "party" end
    ns.SetTweak("hideTracker", true)
    eq(tracker:IsShown(), false, "hidden in a dungeon")
    ns.SetTweak("hideTracker", false)
    eq(tracker:IsShown(), true, "back when the tweak goes off")
    ObjectiveTrackerFrame, IsInInstance = nil, nil
end)

test("quest marks on mobs: an open objective or a rare, never a player or a secret line", function()
    local ns = tweakNs()
    eq(ns.OpenObjective({ type = 8, leftText = " - Kobold slain: 3/10" }), true)
    eq(ns.OpenObjective({ type = 8, leftText = " - Kobold slain: 10/10" }), false)
    eq(ns.OpenObjective({ type = 8, leftText = "Find it", completed = true }), false)
    eq(ns.OpenObjective({ type = 0, leftText = "Level 12" }), false)
    issecretvalue = function(v) return v == "secret" end
    eq(ns.OpenObjective({ type = 8, leftText = "secret" }), false)
    local lines = { { type = 8, leftText = "Wolf Meat: 1/8" } }
    local class = "normal"
    UnitExists = function() return true end
    UnitIsPlayer = function(u) return u == "nameplate2" end
    UnitClassification = function() return class end
    C_TooltipInfo = { GetUnit = function() return { lines = lines } end }
    local o = { quest = true, rare = true }
    local g = function(k) return o[k] end
    eq(ns.PlateMark("nameplate1", g), "quest")
    eq(ns.PlateMark("nameplate2", g), nil, "a player gets nothing")
    lines = {}
    class = "rareelite"
    eq(ns.PlateMark("nameplate1", g), "rare")
    o.rare = false
    eq(ns.PlateMark("nameplate1", g), nil)
    issecretvalue, UnitExists, UnitIsPlayer, UnitClassification, C_TooltipInfo = nil, nil, nil, nil, nil
end)

test("quest progress sounds: an objective, then the whole quest, nothing for a new quest", function()
    local ns = tweakNs()
    local before = { [1] = { done = false, obj = { false, false } } }
    eq(ns.QuestProgress(before, { [1] = { done = false, obj = { true, false } } }), "objective")
    eq(ns.QuestProgress(before, { [1] = { done = true, obj = { true, true } } }), "complete")
    eq(ns.QuestProgress(before, { [1] = before[1], [2] = { done = true, obj = { true } } }), nil, "taking a quest is no progress")
    local log = { { questID = 5 } }
    local fin = false
    C_QuestLog = { GetNumQuestLogEntries = function() return #log end, GetInfo = function(i) return log[i] end,
        IsComplete = function() return fin end,
        GetQuestObjectives = function() return { { finished = fin } } end }
    local played = {}
    PlaySound = function(id) played[#played + 1] = id end
    ns.SetTweak("questSounds", true)
    ns.QuestSoundsEvent()
    eq(#played, 0, "the first look only notes")
    fin = true
    ns.QuestSoundsEvent()
    eq(#played, 1)
    ns.SetTweakOpt("questSounds", "complete", false)
    fin = false
    ns.QuestSoundsEvent()
    fin = true
    ns.QuestSoundsEvent()
    eq(#played, 1, "the switch of the whole quest is off")
    C_QuestLog, PlaySound = nil, nil
end)

test("the Tweaks page opens under Home, its gear opens the settings and the hub's search finds tweaks", function()
    local ns = tweakNs()
    ns.OpenTweaks()
    local view = ns.View()
    eq(view.page, "tweaks")
    assert(ns.TweaksPage():IsShown())
    ns.TweaksView().open.levelShot = true
    ns.FillTweaks()
    ns.Refresh()
    ns.OpenTweaks("screenshot")
    eq(ns.TweaksView().query, "screenshot")
    ns.TweaksSearch("")
    ns.Enter(nil)
    eq(view.page, "home")
end)

-- Combat, interface and sound tweaks -------------------------------------------------------------

-- A client with these settings (name -> value as text); a name not in the table is missing.
local function fakeCVars(values)
    C_CVar = {
        GetCVarInfo = function(n) return values[n] end,
        GetCVar = function(n) return values[n] end,
        SetCVar = function(n, v) if values[n] ~= nil then values[n] = tostring(v) end end,
    }
    return values
end

local function enterWorld()
    for _, f in ipairs(W.frames) do
        local onEvent = rawget(f, "_OnEvent")
        if onEvent then onEvent(f, "PLAYER_ENTERING_WORLD") end
    end
end

test("a tweak's game setting goes back to the player's own, unless the player changed it since", function()
    local cv = fakeCVars({ mapFade = "1", autoQuestWatch = "1" })
    local ns = tweakNs()
    eq(ns.HasCVar("mapFade"), true)
    eq(ns.HasCVar("nothing"), false)
    eq(ns.TweakCVar("x", "nothing", 1), false, "a setting the client lacks is never touched")
    ns.TweakCVar("x", "mapFade", 0)
    eq(cv.mapFade, "0")
    ns.TweakCVar("x", "mapFade", 0)
    ns.TweakCVarsRestore("x")
    eq(cv.mapFade, "1", "the value from before the first change")
    ns.TweakCVar("x", "autoQuestWatch", 0)
    cv.autoQuestWatch = "1"
    ns.TweakCVarsRestore("x")
    eq(cv.autoQuestWatch, "1", "the player's own later change stays")
    -- after a crash: saved, but its tweak no longer runs
    ns.TweakCVar("gameSettings", "mapFade", 0)
    enterWorld()
    eq(cv.mapFade, "1", "a setting of a tweak that is off goes back at login")
    C_CVar = nil
end)

test("hidden game settings: each switch on its own, a higher value of the player's stays", function()
    local cv = fakeCVars({ cameraDistanceMaxZoomFactor = "1.9", nameplateMaxDistance = "80", SpellQueueWindow = "400",
        mapFade = "1", autoQuestWatch = "1", alwaysCompareItems = "0" })
    local ns = tweakNs()
    ns.SetTweak("gameSettings", true)
    eq(cv.cameraDistanceMaxZoomFactor, "2.6")
    eq(cv.nameplateMaxDistance, "80", "only raised, never lowered")
    eq(cv.SpellQueueWindow, "400", "the spell queue is off by default")
    eq(cv.mapFade, "0")
    eq(cv.autoQuestWatch, "1", "off by default")
    eq(cv.alwaysCompareItems, "1")
    ns.SetTweakOpt("gameSettings", "queue", true)
    eq(cv.SpellQueueWindow, "200")
    ns.SetTweakOpt("gameSettings", "queueMs", 125)
    eq(cv.SpellQueueWindow, "125", "the number is the window in ms")
    ns.SetTweakOpt("gameSettings", "mapFade", false)
    eq(cv.mapFade, "1", "one switch off gives back only its own setting")
    eq(cv.cameraDistanceMaxZoomFactor, "2.6")
    ns.SetTweak("gameSettings", false)
    eq(cv.cameraDistanceMaxZoomFactor, "1.9")
    eq(cv.SpellQueueWindow, "400")
    eq(cv.alwaysCompareItems, "0")
    local step
    for _, part in ipairs(ns.Tweak("gameSettings").panel) do if part.key == "queueMs" then step = part end end
    eq(step.when(function(k) return k == "queue" end), true, "the number shows with its switch")
    eq(step.when(function() return false end), false)
    C_CVar = nil
end)

test("cooldown numbers: only on a client with the setting", function()
    C_CVar = nil
    local ns = tweakNs()
    eq(ns.Tweak("cdNumbers"), nil, "without the setting there is no row")
    local cv = fakeCVars({ countdownForCooldowns = "0" })
    ns = tweakNs()
    assert(ns.Tweak("cdNumbers"))
    ns.SetTweak("cdNumbers", true)
    eq(cv.countdownForCooldowns, "1")
    ns.SetTweak("cdNumbers", false)
    eq(cv.countdownForCooldowns, "0")
    C_CVar = nil
end)

test("error filter: hides the ticked kinds, always or only in a fight, and gives them back", function()
    local cv = fakeCVars({ Sound_EnableErrorSpeech = "1" })
    LE_GAME_ERR_OUT_OF_RAGE, LE_GAME_ERR_SPELL_COOLDOWN, LE_GAME_ERR_BADATTACKFACING = 1, 2, 3
    LE_GAME_ERR_SPELL_FAILED_ANOTHER_IN_PROGRESS = 4
    BLACK_LISTED_MESSAGE_TYPES = { [4] = true }
    UIErrorsFrame = { SetMessageTypeEnabled = function(_, t, on) BLACK_LISTED_MESSAGE_TYPES[t] = not on end }
    local fight = false
    InCombatLockdown = function() return fight end
    local ns = tweakNs()
    local bl = BLACK_LISTED_MESSAGE_TYPES
    ns.SetTweak("errorFilter", true)
    eq(bl[1], true, "not enough rage")
    eq(bl[2], true, "not ready yet")
    eq(bl[3], nil, "facing is not ticked by default")
    eq(cv.Sound_EnableErrorSpeech, "0", "no voice for the rest")
    ns.SetTweak("errorFilter", false)
    eq(bl[1], nil, "a type goes back as it was")
    eq(bl[4], true, "and one the game hid itself stays hidden")
    eq(cv.Sound_EnableErrorSpeech, "1")
    GulliToolkitDB.tweaks.errorFilter = { combat = true }
    ns.SetTweak("errorFilter", true)
    eq(bl[1], nil, "only in combat: nothing hidden out of a fight")
    fight = true
    ns.ErrorFilterEvent(nil, "PLAYER_REGEN_DISABLED")
    eq(bl[1], true)
    fight = false
    ns.ErrorFilterEvent(nil, "PLAYER_REGEN_ENABLED")
    eq(bl[1], nil)
    ns.SetTweak("errorFilter", false)
    eq(bl[4], true)
    LE_GAME_ERR_OUT_OF_RAGE, LE_GAME_ERR_SPELL_COOLDOWN, LE_GAME_ERR_BADATTACKFACING = nil, nil, nil
    LE_GAME_ERR_SPELL_FAILED_ANOTHER_IN_PROGRESS, BLACK_LISTED_MESSAGE_TYPES, UIErrorsFrame = nil, nil, nil
    InCombatLockdown, C_CVar = nil, nil
end)

test("consumable macros: the best item the level allows, made, changed and deleted out of combat", function()
    local bags = {}
    local macros, fight, level = {}, false, 30
    InCombatLockdown = function() return fight end
    UnitLevel = function() return level end
    GetNumMacros = function() return 0, #macros end
    GetMacroIndexByName = function(n) for i, m in ipairs(macros) do if m.name == n then return i end end return 0 end
    GetMacroInfo = function(i) local m = macros[i]; return m.name, m.icon, m.body end
    CreateMacro = function(n, icon, body, perChar) assert(perChar, "per character"); macros[#macros + 1] = { name = n, icon = icon, body = body } end
    EditMacro = function(i, n, icon, body) macros[i] = { name = n, icon = icon, body = body } end
    DeleteMacro = function(i) table.remove(macros, i) end
    local ns = tweakNs()
    C_Item.GetItemCount = function(id) return bags[id] or 0 end
    local F = ns.MACRO_LISTS
    bags[4599], bags[4544], bags[8952] = 2, 5, 3 -- level 35, 25 and 45 food
    eq(ns.BestConsumable(F.FOOD, 30), 4544, "the best one the character may eat")
    eq(ns.BestConsumable(F.FOOD, 40), 4599)
    eq(ns.BestConsumable(F.FOOD, 50), 8952)
    eq(ns.BestConsumable(F.DRINK, 50), nil)
    ns.SetTweak("macros", true)
    eq(#macros, 3, "food, drink and health by default")
    local food = macros[GetMacroIndexByName(ns.L.TWM_FOOD)]
    eq(food.body, "#showtooltip item:4544\n/use item:4544")
    local drink = macros[GetMacroIndexByName(ns.L.TWM_DRINK)]
    assert(drink.body:find("item:19301"), "without a drink: the first of the list, greyed out on the bar")
    level = 40
    fight = true
    ns.UpdateMacros()
    eq(macros[GetMacroIndexByName(ns.L.TWM_FOOD)].body:find("4599"), nil, "no change in a fight")
    fight = false
    ns.MacrosEvent(nil, "PLAYER_REGEN_ENABLED")
    assert(macros[GetMacroIndexByName(ns.L.TWM_FOOD)].body:find("item:4599"), "after the fight")
    bags[4599], bags[4544], bags[8952] = nil, nil, nil
    ns.UpdateMacros()
    assert(macros[GetMacroIndexByName(ns.L.TWM_FOOD)].body:find("item:4599"), "the last item stays, greyed out")
    ns.SetTweakOpt("macros", "rest", true)
    bags[8075], bags[1645] = 1, 1
    ns.UpdateMacros()
    eq(macros[GetMacroIndexByName(ns.L.TWM_REST)].body, "#showtooltip item:8075\n/use item:8075\n/use item:1645")
    ns.SetTweakOpt("macros", "food", false)
    eq(GetMacroIndexByName(ns.L.TWM_FOOD), 0, "unticked: deleted")
    ns.SetTweak("macros", false)
    eq(#macros, 3, "switching the tweak off leaves the macros on the bars")
    for _, lang in ipairs({ "en", "de", "es", "fr", "pl", "pt", "ru", "zh" }) do
        for _, m in ipairs(ns.MACROS) do
            local name = ns.T[lang]["TWM_" .. m.key:upper()]
            assert(name and #name <= 16, lang .. " " .. m.key .. " macro name fits 16 bytes")
        end
    end
    C_Item.GetItemCount, InCombatLockdown, UnitLevel, GetNumMacros, GetMacroIndexByName = nil, nil, nil, nil, nil
    GetMacroInfo, CreateMacro, EditMacro, DeleteMacro = nil, nil, nil, nil
end)

test("quieter game: mutes the ticked kinds and gives every sound back", function()
    local muted = {}
    MuteSoundFile = function(id) muted[id] = true end
    UnmuteSoundFile = function(id) muted[id] = nil end
    local ns = tweakNs()
    for _, kind in ipairs(ns.MUTE_KINDS) do
        assert(#(ns.MUTE_SOUNDS[kind] or {}) > 0, kind .. " has sounds")
        assert(ns.T.en["TWP_MUTE_" .. kind:upper()], kind .. " has a text")
    end
    local rain = ns.MUTE_SOUNDS.weather[1]
    local hoof = ns.MUTE_SOUNDS.hooves[1]
    ns.SetTweak("muteSounds", true)
    eq(muted[hoof], true)
    eq(muted[rain], nil, "rain is not ticked by default")
    ns.SetTweakOpt("muteSounds", "weather", true)
    eq(muted[rain], true)
    ns.SetTweakOpt("muteSounds", "hooves", false)
    eq(muted[hoof], nil, "unticked: back at once")
    ns.SetTweak("muteSounds", false)
    eq(next(muted), nil, "off: every sound back")
    MuteSoundFile, UnmuteSoundFile = nil, nil
end)

test("swing timer style: paints the game's bars, red out of reach, and gives their look back", function()
    local cv = fakeCVars({ showSwingTimer = "0" })
    local function swingFrame(atlas)
        local sb = { tex = atlas, color = { 1, 1, 1 } }
        function sb:SetStatusBarTexture(t) self.tex = t end
        function sb:SetStatusBarColor(r, g, b) self.color = { r, g, b } end
        local bg = { SetVertexColor = function(self, r) self.r = r end }
        local f = { StatusBar = sb, Background = bg, barTexture = atlas, hooks = {} }
        function f:ApplyRangePresentation() end
        return f
    end
    SwingTimerMainHandFrame = swingFrame("ui-swingtimerbar-filling-mainhand")
    SwingTimerRangedFrame = swingFrame("ui-swingtimerbar-filling-ranged")
    hooksecurefunc = function(t, m, fn) local old = t[m]; t[m] = function(...) old(...); fn(...) end end
    RAID_CLASS_COLORS = { PRIEST = { r = 1, g = 1, b = 1 } }
    local ns = tweakNs()
    ns.SetTweak("swingStyle", true)
    local mh = SwingTimerMainHandFrame
    eq(mh.StatusBar.tex, "Interface\\Buttons\\WHITE8X8")
    eq(mh.StatusBar.color[1], 1, "class colour")
    eq(cv.showSwingTimer, "1", "the game's bars show")
    mh.isOutOfRange = true
    mh:ApplyRangePresentation()
    eq(mh.StatusBar.color[2], 0.25, "red while out of reach")
    ns.SetTweakOpt("swingStyle", "range", false)
    eq(mh.StatusBar.color[2], 1)
    ns.SetTweakOpt("swingStyle", "color", "bronze")
    eq(mh.StatusBar.color[1], 0.643)
    ns.SetTweak("swingStyle", false)
    eq(mh.StatusBar.tex, "ui-swingtimerbar-filling-mainhand", "the game's own bar again")
    eq(cv.showSwingTimer, "0")
    mh:ApplyRangePresentation()
    eq(mh.StatusBar.tex, "ui-swingtimerbar-filling-mainhand", "a hook does nothing while off")
    SwingTimerMainHandFrame, SwingTimerRangedFrame, hooksecurefunc, RAID_CLASS_COLORS, C_CVar = nil, nil, nil, nil, nil
end)

test("right-click guild invite: only for another readable player, only when the player may invite", function()
    local menus = {}
    Menu = { ModifyMenu = function(tag, fn) menus[tag] = fn end }
    local opened
    ChatFrameUtil = { OpenChat = function(t) opened = t end }
    local can = true
    IsInGuild = function() return true end
    CanGuildInvite = function() return can end
    UnitIsPlayer = function(u) return u ~= "npc" end
    local ns = tweakNs()
    eq(ns.InviteName({ name = "Thrall" }), "Thrall")
    eq(ns.InviteName({ name = "Tester" }), nil, "never the player's own name")
    eq(ns.InviteName({ unit = "npc", name = "Hogger" }), nil)
    issecretvalue = function(v) return v == "secret" end
    eq(ns.InviteName({ name = "secret" }), nil, "a secret name is left alone")
    issecretvalue = nil
    eq(next(menus), nil, "the menu is changed only once the tweak is on")
    ns.SetTweak("guildInvite", true)
    local fn = menus.MENU_UNIT_FRIEND
    assert(fn, "the chat name menu")
    local made = {}
    local root = { CreateDivider = function() end, CreateButton = function(_, text, click) made[#made + 1] = { text, click } end }
    fn(nil, root, { name = "Thrall" })
    eq(made[1][1], ns.L.TW_GI_MENU)
    made[1][2]()
    eq(opened, "/ginvite Thrall", "the chat box gets the command, the player's Enter sends it")
    can = false
    fn(nil, root, { name = "Jaina" })
    eq(#made, 1, "nothing for a player who may not invite")
    can = true
    ns.SetTweak("guildInvite", false)
    fn(nil, root, { name = "Jaina" })
    eq(#made, 1, "nothing while the tweak is off")
    Menu, ChatFrameUtil, IsInGuild, CanGuildInvite, UnitIsPlayer = nil, nil, nil, nil, nil
end)

io.write(string.format("%d/%d passed\n", count - failed, count))
os.exit(failed == 0 and 0 or 1)
