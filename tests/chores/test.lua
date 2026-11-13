-- Run from the repository root: lua5.1 tests/chores/test.lua
local W = dofile("tests/chores/wow.lua")
local test, eq = W.test, W.eq

local function has(tasks, key)
    for _, t in ipairs(tasks) do if t.key == key then return t end end
end

test("every language has every text", function()
    Fake({})
    W.CheckLocales(Load())
end)

test("a fresh character has nothing to do and counts its trainer as visited", function()
    Fake({ level = 20 })
    local ns = Load()
    W.Fire("PLAYER_ENTERING_WORLD")
    local c = ns.db.chars[ns.CharKey()]
    eq(c.trainer, 20)
    eq(#ns.Tasks(c), 0)
end)

test("a new even level asks for the trainer until the trainer window opens", function()
    Fake({ level = 20 })
    local ns = Load()
    W.Fire("PLAYER_ENTERING_WORLD")
    W.level = 21
    assert(not has(ns.Tasks(ns.Snapshot()), "TRAINER"), "an odd level brings no spells")
    W.level = 22
    local c = ns.Snapshot()
    assert(has(ns.Tasks(c), "TRAINER"))
    W.Fire("TRAINER_SHOW")
    assert(not has(ns.Tasks(ns.Snapshot()), "TRAINER"))
end)

test("mail, low durability and full bags show up", function()
    Fake({})
    local ns = Load()
    W.char.mail, W.char.free, W.char.durability = true, 1, { 80, 20 }
    local tasks = ns.Tasks(ns.Snapshot())
    assert(has(tasks, "MAIL"))
    eq(has(tasks, "REPAIR").text, "Repair: gear at 20%")
    eq(has(tasks, "BAGS").text, "Free bag slots: 1")
end)

test("rested XP grows offline and is full after enough days in an inn", function()
    Fake({ level = 30 })
    local ns = Load()
    W.char.rested, W.char.resting = 500, true -- half a level
    local c = ns.Snapshot()
    eq(ns.RestedNow(c, W.now), 0.5)
    assert(not has(ns.Tasks(c, W.now), "RESTED"))
    local full = W.now + 8 * 3600 * 20 -- one level more needs 20 x 8 hours
    eq(ns.RestedNow(c, full), 1.5)
    assert(has(ns.Tasks(c, full), "RESTED"))
    -- Outside an inn it grows four times slower.
    c.resting = false
    eq(ns.RestedNow(c, full), 0.5 + 0.25)
end)

test("no rested task at the top level", function()
    Fake({ level = 60 })
    local ns = Load()
    W.char.rested = 1500
    assert(not has(ns.Tasks(ns.Snapshot(), W.now + 86400 * 30), "RESTED"))
end)

test("a crafting cooldown is saved as real time and is ready later", function()
    Fake({ now = 50000 })
    local ns = Load()
    W.char.spells[18560] = true
    W.char.cooldowns[18560] = { 50000 - 3600, 4 * 86400 } -- started an hour ago, 4 days long
    local c = ns.Snapshot()
    local ready = 50000 - 3600 + 4 * 86400
    eq(c.cooldowns.CD_MOONCLOTH, ready)
    assert(not has(ns.Tasks(c, W.now), "CD"))
    eq(ns.NextReady(c, W.now), ready)
    eq(has(ns.Tasks(c, ready), "CD").text, "Mooncloth is ready")
    eq(ns.NextReady(c, ready), nil)
end)

test("a cooldown the character does not know is not tracked", function()
    Fake({})
    local ns = Load()
    W.char.cooldowns[18560] = { W.now, 86400 }
    eq(ns.Snapshot().cooldowns.CD_MOONCLOTH, nil)
    W.char.items[15846] = 1 -- the Salt Shaker is tracked while it is in the bags
    eq(has(ns.Tasks(ns.Snapshot()), "CD").text, "Salt Shaker is ready")
end)

test("login prints what waits on the other characters", function()
    Fake({ name = "Me", db = { chars = {
        ["Alt-Realm"] = { name = "Alt", level = 30, t = 1000, trainer = 30, mail = true, cooldowns = {} },
        ["Done-Realm"] = { name = "Done", level = 60, maxLevel = true, t = 1000, cooldowns = {} },
    } } })
    local ns = Load()
    local feed = {}
    GulliToolkit = { Notify = function(key, text) feed[#feed + 1] = key .. ":" .. text end }
    W.Fire("PLAYER_ENTERING_WORLD")
    local last = W.printed[#W.printed]
    assert(last:find("Alt: You have mail", 1, true), last)
    assert(not last:find("Done", 1, true))
    eq(#feed, 1)
end)

test("the list puts this character first and forget removes another one", function()
    Fake({ name = "Me", level = 10, db = { chars = {
        ["Alt-Realm"] = { name = "Alt", level = 50, t = 1000, cooldowns = {} },
    } } })
    local ns = Load()
    ns.Snapshot()
    local list = ns.Chars()
    eq(list[1].key, "Me-Realm")
    eq(list[2].key, "Alt-Realm")
    ns.Toggle()
    ns.Forget("Alt-Realm")
    eq(#ns.Chars(), 1)
end)

test("time spans read in days, hours and minutes", function()
    Fake({})
    local ns = Load()
    eq(ns.Span(2 * 86400 + 5), "2 d")
    eq(ns.Span(3 * 3600 + 59), "3 h")
    eq(ns.Span(20), "1 min")
end)

test("tasks are coloured by how urgent they are", function()
    Fake({})
    local ns = Load()
    local S = ns.Skin
    eq(ns.TaskColor("REPAIR"), S.BAD); eq(ns.TaskColor("BAGS"), S.BAD)
    eq(ns.TaskColor("CD"), S.GOOD); eq(ns.TaskColor("RESTED"), S.GOOD)
    eq(ns.TaskColor("MAIL"), S.TEXT)
end)

test("the shared skin colours levels like the quest log and items by quality", function()
    Fake({ level = 30 })
    local ns = Load()
    local S = ns.Skin
    GetQuestDifficultyColor = nil
    eq(S.LevelColor(36)[2], 0.1, "red"); eq(S.LevelColor(33)[2], 0.5, "orange")
    eq(S.LevelColor(29)[2], 1, "yellow"); eq(S.LevelColor(24)[2], 0.75, "green")
    eq(S.LevelColor(20)[1], 0.5, "grey")
    eq(S.LevelColor(nil), S.MUTED)
    GetQuestDifficultyColor = function() return { r = 0.1, g = 0.2, b = 0.3 } end
    eq(S.LevelColor(30)[1], 0.1, "the game's rule wins")
    GetQuestDifficultyColor = nil
    eq(S.QualityHex(0), "|cff9d9d9d"); eq(S.QualityHex(4), "|cffa335ee"); eq(S.QualityHex(nil), "|cffffffff")
end)

test("mail with items that runs out soon is a task, and COD letters are counted", function()
    Fake({})
    local ns = Load()
    W.char.inbox = { { 0, 0, 29, 0 }, { 0, 0, 2.5, 1 }, { 500, 0, 10, 0 }, { 0, 300, 20, 1 } }
    local c = ns.ReadMail()
    eq(c.mailItems, 3)
    eq(c.cod, 1)
    eq(c.mailUntil, W.now + math.floor(2.5 * 86400))
    eq(has(ns.Tasks(c), "EXPIRE").text, "Mail runs out in 2 d")
    eq(ns.Tasks(c)[1].key, "EXPIRE", "the most urgent first")
    ns.SetPref("mailDays", 2)
    assert(not has(ns.Tasks(c), "EXPIRE"))
    -- The snapshot keeps what only the mailbox shows.
    eq(ns.Snapshot().mailUntil, c.mailUntil)
    W.char.inbox = {}
    eq(ns.ReadMail().mailUntil, nil)
end)

test("each task has a switch and the limits are settings", function()
    Fake({})
    local ns = Load()
    W.char.mail, W.char.free, W.char.durability = true, 4, { 45 }
    local c = ns.Snapshot()
    assert(has(ns.Tasks(c), "MAIL"))
    ns.SetTask("MAIL", false)
    assert(not has(ns.Tasks(c), "MAIL"))
    assert(not has(ns.Tasks(c), "REPAIR"))
    ns.SetPref("repairAt", 50)
    assert(has(ns.Tasks(c), "REPAIR"))
    assert(not has(ns.Tasks(c), "BAGS"))
    ns.SetPref("bagsAt", 4)
    assert(has(ns.Tasks(c), "BAGS"))
    ns.Reset()
    assert(has(ns.Tasks(c), "MAIL"))
    eq(ns.db.repairAt, 30)
end)

test("rested XP says when it is full", function()
    Fake({ level = 30 })
    local ns = Load()
    W.char.rested, W.char.resting = 1000, true -- one level, half a level to go
    local c = ns.Snapshot()
    eq(ns.RestedFullIn(c, W.now), 10 * 8 * 3600)
    eq(ns.RestedFullIn(c, W.now + 10 * 8 * 3600), 0)
    c.maxLevel = true
    eq(ns.RestedFullIn(c, W.now), nil)
end)

test("bags, bank, hearthstone, professions, lockouts and played time are saved", function()
    Fake({})
    local ns = Load()
    W.char.bags[0] = { { 7, 5 }, { 7, 3 } }
    W.char.bank[-1] = { { 7, 10 } }
    W.char.bank[5] = { { 8, 1 } }
    W.char.items[6948] = 1
    W.char.cooldowns[6948] = { W.now - 600, 3600 }
    W.char.bind = "Goldshire"
    W.char.profs = { { "Tailoring", 75, 75 }, { "Cooking", 300, 300 } }
    W.char.saved = { { "Onyxia's Lair", 3 * 86400, true }, { "Old", 0, false } }
    local c = ns.Snapshot()
    eq(c.items[7], 8)
    eq(c.bank, nil, "the bank only at the bank")
    W.Fire("BANKFRAME_OPENED")
    c = ns.db.chars[ns.CharKey()]
    eq(c.bank[7], 10); eq(c.bank[8], 1)
    eq(ns.Snapshot().bank[7], 10, "the bank stays")
    c = ns.db.chars[ns.CharKey()]
    eq(c.hearth, W.now + 3000)
    eq(c.bind, "Goldshire")
    eq(#c.lockouts, 1)
    eq(has(ns.Tasks(c), "PROF").text, "Tailoring 75/75: learn the next rank")
    local tailoring
    for _, p in ipairs(c.profs) do if p.name == "Tailoring" then tailoring = p end end
    assert(tailoring.icon, "the profession keeps its icon")
    eq(has(ns.Tasks(c), "PROF").icon, tailoring.icon, "a full rank shows the profession's own icon")
    local info = ns.CardInfo(c, ns.CharKey(), W.now)
    eq(info.hearth[1], "50 min"); eq(info.hearth[3], "Goldshire")
    local lines = table.concat(info.extra, "\n")
    assert(lines:find("Saved: Onyxia's Lair 3 d", 1, true), lines)
    eq(info.profs[1].full, true, "a full rank is marked for the trainer")
    -- Played time is asked without the chat lines.
    ns.AskPlayed()
    eq(W.playedAsked, 1)
    ChatFrame_DisplayTimePlayed()
    W.Fire("TIME_PLAYED_MSG", 7200, 600)
    eq(ns.db.chars[ns.CharKey()].played, 7200)
    ChatFrame_DisplayTimePlayed()
    eq(W.printed[#W.printed], "played shown", "the game's own line works again")
end)

test("profession skill comes from Gulli Craft Profit when the game has no API", function()
    Fake({})
    local ns = Load()
    GetProfessions = nil
    GulliCraftProfitCharDB = { profs = { Leatherworking = { skill = 150, cap = 150 } } }
    assert(has(ns.Tasks(ns.Snapshot()), "PROF"))
end)

test("alerts tell a cooldown or full rested XP once, not what was ready at login", function()
    Fake({ name = "Me", db = { chars = {
        ["Alt-Realm"] = { name = "Alt", level = 30, t = 1000, trainer = 30, cooldowns = { CD_MOONCLOTH = 100500 } },
    } } })
    local ns = Load()
    local feed = {}
    GulliToolkit = { Notify = function(key, text) feed[#feed + 1] = text end }
    W.Fire("PLAYER_ENTERING_WORLD")
    eq(#ns.CheckAlerts(W.now), 0, "nothing new yet")
    local out = ns.CheckAlerts(100500)
    eq(#out, 1)
    eq(out[1], "Alt: Mooncloth is ready")
    eq(#ns.CheckAlerts(100600), 0, "told once")
    ns.SetPref("alerts", false)
    ns.db.chars["Alt-Realm"].cooldowns.CD_MOONCLOTH = 200000
    eq(#ns.CheckAlerts(200001), 0, "the switch stops it")
    ns.SetPref("alerts", true)
    -- Rested XP that becomes full.
    local alt = ns.db.chars["Alt-Realm"]
    alt.rested, alt.resting, alt.t = 1.4, true, 200001
    eq(#ns.CheckAlerts(200001), 0)
    eq(ns.CheckAlerts(200001 + 3 * 8 * 3600)[1], "Alt: Rested XP is full")
end)

test("the login line can be switched off", function()
    Fake({ name = "Me", db = { login = false, chars = {
        ["Alt-Realm"] = { name = "Alt", level = 30, t = 1000, trainer = 30, mail = true, cooldowns = {} },
    } } })
    local ns = Load()
    eq(ns.LoginSummary(), nil)
end)

test("hidden characters and the realm and faction filters", function()
    Fake({ name = "Me", db = { chars = {
        ["Bank-Realm"] = { name = "Bank", level = 1, t = 1000, realm = "Realm", faction = "Alliance", mail = true, cooldowns = {} },
        ["Orc-Realm"] = { name = "Orc", level = 20, t = 1000, realm = "Realm", faction = "Horde", cooldowns = {} },
        ["Far-Other"] = { name = "Far", level = 30, t = 1000, realm = "Other", faction = "Alliance", money = 50000, cooldowns = {} },
    } } })
    local ns = Load()
    ns.Snapshot()
    eq(#ns.Chars(), 4)
    ns.SetHidden("Bank-Realm", true)
    eq(#ns.Chars(), 3)
    eq(#ns.Chars(true), 4)
    eq(ns.Chars(true)[4].key, "Bank-Realm", "hidden ones last")
    eq(ns.Summary(), "Nothing waits on your characters")
    ns.SetHidden("Bank-Realm", false)
    eq(ns.Summary(), "1 tasks on 1 characters")
    ns.SetPref("filter", "realm")
    eq(#ns.Chars(), 3)
    ns.SetPref("filter", "faction")
    eq(#ns.Chars(), 3)
    ns.SetPref("filter", "all")
    local gold = ns.RealmGold()
    eq(gold[1].realm, "Other"); eq(gold[1].money, 50000)
    ns.SetNote("Orc-Realm", "  crafter  ")
    eq(ns.db.chars["Orc-Realm"].note, "crafter")
    ns.SetNote("Orc-Realm", "")
    eq(ns.db.chars["Orc-Realm"].note, nil)
end)

test("the overview sorts by any column", function()
    Fake({ name = "Me", level = 10, db = { chars = {
        ["A-Realm"] = { name = "A", level = 50, t = 1000, money = 10, cooldowns = {} },
        ["B-Realm"] = { name = "B", level = 30, t = 1000, money = 900, cooldowns = {} },
    } } })
    local ns = Load()
    ns.Snapshot()
    eq(ns.Overview("name")[1].name, "A")
    eq(ns.Overview("level", true)[1].name, "A")
    eq(ns.Overview("money", true)[1].name, "Me")
    eq(ns.Overview("money")[1].name, "A")
end)

test("overview cells are coloured by state, money by coin", function()
    Fake({ name = "Me", level = 10 })
    local ns = Load()
    eq(ns.Tone("durability", 95), "GOOD"); eq(ns.Tone("durability", 60), "WARN"); eq(ns.Tone("durability", 20), "BAD")
    eq(ns.Tone("free", 14), "GOOD"); eq(ns.Tone("free", 8), "WARN"); eq(ns.Tone("free", 3), "BAD")
    ns.SetPref("bagsAt", 8)
    eq(ns.Tone("free", 8), "BAD", "the player's own bag limit")
    eq(ns.Tone("tasks", 2), nil); eq(ns.Tone("tasks", 4), "WARN"); eq(ns.Tone("tasks", 6), "BAD")
    eq(ns.Tone("rested", 1.5), "GOOD"); eq(ns.Tone("rested", 0), "MUTED"); eq(ns.Tone("cd", 0), "GOOD")
    local S = ns.Skin
    local m = S.MoneyText(284205)
    assert(m:find("28g", 1, true) and m:find("42s", 1, true) and m:find("5c", 1, true), m)
    assert(m:find(S.Hex(S.GOLD), 1, true), "gold in its colour")
    eq(S.MoneyText(0):find("0c", 1, true) ~= nil, true)
    eq(S.MoneyText(10000):find("s", 1, true), nil, "empty parts are left out")
end)

test("the window has three tabs and the hub gets a summary and options", function()
    Fake({ name = "Me" })
    local reg
    GulliToolkit = { Register = function(info) reg = info end }
    local ns = Load()
    eq(reg.key, "Chores")
    eq(#reg.options, 4)
    assert(reg.summary())
    reg.options[1].set(false)
    eq(ns.db.login, false)
    reg.options[3].set(false)
    eq(ns.TaskOn("EXPIRE"), false)
    reg.reset()
    eq(ns.db.login, true)
    eq(ns.TaskOn("EXPIRE"), true)
    ns.Toggle()
    ns.Window():GetScript("OnShow")()
    for i = 1, 3 do ns.Tabs():Select(i) end
    ns.Tabs():Select(2)
    ns.SortBy("money")
    ns.SortBy("money")
end)

W.finish()
