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
    ns.SesEvent("PLAYER_ENTERING_WORLD", true, false)
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
    farm = { worth = -5 }
    eq(ns.SessionCard().empty, true)
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

test("money shows each coin in its colour, short drops copper from 1 gold, a loss keeps its minus", function()
    Fake({ addons = { QC } })
    local S = Load().Skin
    local plain = function(t) return (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    eq(plain(S.MoneyText(26664)), "2g 66s 64c")
    eq(plain(S.MoneyText(26664, true)), "2g 66s")
    eq(plain(S.MoneyText(-150)), "-1s 50c")
    eq(plain(S.MoneyText(0)), "0c")
    assert(S.MoneyText(26664):find(S.Hex(S.GOLD) .. "2g", 1, true), "gold in the gold colour")
    assert(S.MoneyText(26664):find(S.Hex(S.COPPER) .. "64c", 1, true), "copper in the copper colour")
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

test("a module gets its own minimap button only when the player pins it", function()
    local W = Fake({ addons = { QC, { name = "Gulli-Loot", enabled = true, loaded = true, meta = { ["X-Gulli-Module"] = "Loot" } } } })
    local ns = Load()
    local opened, paused = 0, false
    GulliToolkit.Register({ key = "QuestCleaner", open = function() opened = opened + 1 end,
                            summary = function() return "4 grey quests" end })
    GulliToolkit.Register({ key = "Loot", open = function() end, pause = function(on) paused = on end })
    eq(#ns.Pins(), 0, "nothing is pinned by default")
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
    eq(GulliToolkitDB.pins.QuestCleaner, nil)
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

io.write(string.format("%d/%d passed\n", count - failed, count))
os.exit(failed == 0 and 0 or 1)
