-- Run from the repository root: lua5.1 tests/legacy/test.lua
local W = dofile("tests/legacy/wow.lua")
local test, eq = W.test, W.eq

local world = W.World

local function ids(steps)
    local out = {}
    for i, s in ipairs(steps) do out[i] = s.ch.id end
    return out
end

local function has(steps, id)
    for _, s in ipairs(steps) do if s.ch.id == id then return s end end
end

test("every language has every text, and every text the code uses is there", function()
    Fake(world())
    local ns = Load()
    W.CheckLocales(ns)
    for _, f in ipairs({ "Core.lua", "UI.lua" }) do
        local fh = io.open("Gulli-Legacy/" .. f)
        local src = fh:read("*a")
        fh:close()
        for key in src:gmatch("L%.([%u_]+[%u%d_]*)") do
            assert(ns.T.en[key], f .. " uses L." .. key .. " that has no text")
        end
    end
    for _, k in ipairs({ "HELP_CraftProfit", "HELP_XP", "HELP_Bulletin", "HELP_DungeonPrep", "HELP_Attune" }) do
        assert(ns.T.en[k], k)
    end
    for _, r in ipairs(ns.REWARDS) do assert(ns.T.en["REWARD_" .. r], "REWARD_" .. r) end
end)

test("the challenges are the achievements that give Legacy points", function()
    Fake(world())
    local ns = Load()
    ns.Scan()
    eq(#ns.list, 11, "points only, the ignored category left out")
    local c = ns.byID
    eq(c[728], nil, "a chain step without points is not a challenge")
    eq(c[99999], nil, "Do Not Display")
    eq(c[62000].done, true)
    eq(c[62001].kind, "level"); eq(c[62001].class, "PRIEST"); eq(c[62001].need, 45)
    eq(c[70001].kind, "skill"); eq(c[70001].skill, 197); eq(c[70001].need, 150)
    eq(c[70010].activity, "dungeon"); eq(c[70010].open, 1); eq(c[70010].total, 6)
    eq(c[70010].minLevel, 15); eq(c[70011].minLevel, 30)
    eq(c[70020].activity, "raid")
    eq(c[70030].activity, "pvp", "a sub-category takes its parent's activity")
    eq(c[70040].activity, "solo")
    eq(c[70040].open, 2, "a chain counts the open parts of its step")
    eq(c[70040].total, 3)
end)

test("the scan runs over several frames and keeps the last list until it is whole", function()
    Fake(world())
    local ns = Load()
    ns.Scan()
    local old = ns.list
    local ms = 0
    debugprofilestop = function() ms = ms + 3; return ms end
    ns.scannedAt = nil
    local done = false
    ns.ScanJob(function() done = true end)
    local frames = 0
    while not done and frames < 1000 do
        eq(ns.list, old, "the old list stays while it scans")
        for _, g in ipairs(W.frames) do
            local fn = rawget(g, "_OnUpdate")
            if fn then fn(g, 0.016) end
        end
        frames = frames + 1
    end
    debugprofilestop = nil
    eq(done, true)
    assert(frames > 1, "it took more than one frame")
    eq(#ns.list, 11)
    eq(ns.ScanFresh(), true)
end)

test("points: earned on the account, spent and free on this character", function()
    Fake(world())
    local ns = Load()
    ns.Scan()
    local p = ns.Points()
    eq(p.earned, 12); eq(p.avail, 3); eq(p.spent, 9)
    eq(ns.NextReward(p.earned).level, 15)
    eq(ns.NextReward(55), nil)
    W.renown = nil
    eq(ns.Points().earned, 1, "without the track the done challenges count")
end)

test("the next steps: fastest first, hidden ones counted", function()
    Fake(world())
    local ns = Load()
    ns.Scan()
    ns.Snapshot()
    local steps, hidden = ns.Steps()
    eq(hidden, 2, "raid and PvP are off by default")
    local first = ids(steps)
    eq(first[1], 70040, "two areas of one zone to explore")
    eq(first[2], 70001, "18 tailoring points")
    eq(first[3], 70010, "one dungeon")
    eq(steps[1].eta, ns.TIME.zone + 2 * ns.TIME.area, "exploring: the zone plus each dark area")
    eq(steps[2].eta, 18 * ns.TIME.skill + ns.TIME.shop)
    local alch = has(steps, 70002)
    eq(alch.learn, true, "one profession: a second can be learned")
    local lock = has(steps, 62009)
    eq(lock.new, true, "no warlock yet: a new character")
    eq(lock.eta, ns.LevelSeconds(1, 0, 25) + ns.TIME.switch)
    assert(ns.Detail(steps[2]):find("18 skill points (132 to 150)", 1, true), ns.Detail(steps[2]))
    assert(ns.Detail(steps[3]):find("Shadowfang Keep", 1, true), ns.Detail(steps[3]))
    eq(ns.Tag(steps[3]), "group")
end)

test("the settings decide what is suggested", function()
    Fake(world())
    local ns = Load()
    ns.Scan()
    ns.Snapshot()
    ns.SetPref("dungeon", false)
    eq(has(ns.Steps(), 70010), nil, "no dungeons")
    ns.SetPref("newClass", false)
    eq(has(ns.Steps(), 62009), nil, "no new class")
    ns.SetPref("raid", true)
    local raid = has(ns.Steps(), 70020)
    eq(raid.needLevel, 60, "a raid needs level 60: the levelling comes first")
    eq(raid.eta, ns.TIME.boss + raid.levelEta)
    assert(raid.levelEta > 20 * 3600, "23 levels take long")
    assert(ns.Detail(raid):find("From level 60", 1, true), ns.Detail(raid))
    ns.SetPref("pvp", true)
    local pvp = has(ns.Steps(), 70030)
    eq(pvp.eta, nil, "PvP has no time guess")
    local steps = ns.Steps()
    eq(steps[#steps].ch.id, 70030, "a step without a guess comes last")
end)

test("another character can be faster, and the switch is counted", function()
    Fake(world({ db = { chars = { ["Gulliwar-Realm"] = { name = "Gulliwar", class = "WARLOCK", level = 22, skills = {} } } } }))
    local ns = Load()
    ns.Scan()
    ns.Snapshot()
    local lock = has(ns.Steps(), 62009)
    eq(lock.new, nil)
    eq(lock.key, "Gulliwar-Realm")
    eq(lock.eta, ns.LevelSeconds(22, 0, 25) + ns.TIME.switch)
    assert(ns.Detail(lock):find("On Gulliwar", 1, true), ns.Detail(lock))
    eq(ns.BestFor("Gulliwar-Realm").ch.id, 70010, "a dungeon is faster than three levels on the warlock")
    ns.SetPref("alts", false)
    eq(has(ns.Steps(), 62009), nil, "the warlock exists, so no new one is suggested either")
end)

test("the pace comes from the XP module when its session is long enough", function()
    Fake(world({ xpdb = { s = { active = 1800, gained = 20000 } } }))
    local ns = Load()
    ns.Scan()
    ns.Snapshot()
    eq(ns.MeasuredRate(), 40000)
    local priest = has(ns.Steps(), 62001)
    eq(priest.eta, ns.LevelSeconds(37, 0, 45, 40000))
    assert(ns.Detail(priest):find("40k XP/h", 1, true), ns.Detail(priest))
    eq(ns.LevelSeconds(37, 0, 38, 7600), math.floor(76100 * 3600 / 7600))
    GulliXPCharDB.s.active = 60
    eq(ns.MeasuredRate(), nil, "a minute is too short")
end)

test("a goal: the fastest steps to a reward of the track", function()
    Fake(world())
    local ns = Load()
    ns.Scan()
    ns.Snapshot()
    eq(ns.GoalPlan(ns.Steps(), 12), nil, "no goal by default")
    eq(ns.NextGoal(), 15)
    ns.SetGoal(15)
    local steps = ns.Steps()
    local plan, need, total = ns.GoalPlan(steps, 12)
    eq(need, 3); eq(#plan, 3)
    eq(total, steps[1].eta + steps[2].eta + steps[3].eta)
    local _, done = ns.GoalPlan(steps, 15)
    eq(done, 0, "reached")
    ns.SetGoal(55)
    eq(ns.NextGoal(), 0, "the last goal goes back to none")
end)

test("a new point shows a notice and a line in the hub", function()
    Fake(world())
    local ns = Load()
    ns.Scan()
    local notes, toasts = {}, {}
    GulliToolkit = { Notify = function(key, text) notes[#notes + 1] = { key, text } end }
    ns.Announce = function(title, name, text) toasts[#toasts + 1] = name .. "|" .. text end
    W.ach[70001].done = true
    W.renown = 13
    W.Fire("ACHIEVEMENT_EARNED", 70001)
    eq(#notes, 1)
    eq(notes[1][1], "Legacy")
    assert(notes[1][2]:find("Journeyman Tailor", 1, true) and notes[1][2]:find("13", 1, true), notes[1][2])
    assert(toasts[1]:find("2 to Replica Ironforge Air Rifle", 1, true), toasts[1])
    W.Fire("ACHIEVEMENT_EARNED", 728)
    eq(#notes, 1, "an achievement without points says nothing")
    ns.SetPref("announce", false)
    W.Fire("ACHIEVEMENT_EARNED", 70002)
    eq(#notes, 1, "switched off")
end)

test("pins decide the tracker; a paused module reads nothing and hides it", function()
    Fake(world())
    local ns = Load()
    ns.Scan()
    ns.Snapshot()
    local list, pinned = ns.Tracked(ns.Steps())
    eq(pinned, false); eq(#list, 3)
    ns.Pin(70011)
    list, pinned = ns.Tracked(ns.Steps())
    eq(pinned, true); eq(#list, 1); eq(list[1].ch.id, 70011)
    ns.Pin(70011)
    eq(ns.db.pins[70011], nil, "a second click unpins")
    local t = _G.GulliLegacyTracker
    ns.Refresh()
    local called = false
    GulliToolkit = { Notify = function() called = true end }
    ns.Pause(true)
    W.Fire("ACHIEVEMENT_EARNED", 70001)
    eq(called, false, "paused: the event is ignored")
    W.Fire("CRITERIA_UPDATE")
    eq(ns.waiting, nil, "paused: no rescan")
    ns.Pause(false)
    W.Fire("CRITERIA_UPDATE")
    eq(ns.waiting, true)
    W.RunTimers()
    eq(ns.waiting, nil)
    eq(t, nil)
end)

test("a character's snapshot keeps its skills and points", function()
    Fake(world())
    local ns = Load()
    ns.Scan()
    local c = ns.Snapshot()
    eq(c.level, 37); eq(c.class, "PRIEST"); eq(c.skills[197], 132); eq(c.avail, 3); eq(c.spent, 9)
    eq(ns.db.chars["Gullipriest-Realm"], c)
    ns.Forget("Gullipriest-Realm")
    assert(ns.db.chars["Gullipriest-Realm"], "this character is never forgotten")
    issecretvalue = function(v) return v == 37 end
    c = ns.Snapshot()
    eq(c.level, 37, "a secret level keeps the saved one")
    issecretvalue = nil
end)

test("before the game sends the achievements the list waits", function()
    Fake(world({ cats = {} }))
    local ns = Load()
    eq(#ns.Scan(), 0)
    eq(ns.Summary(), nil)
    ns.Toggle()
    ns.Refresh()
    W.cats[1] = { id = 15593, achs = { 70010 } }
    eq(#ns.Scan(), 0, "the categories do not change by themselves in the fake; a later scan finds them")
end)

test("the window builds every tab, and the hub gets a summary", function()
    Fake(world())
    local reg
    GulliToolkit = { Register = function(t) reg = t end }
    local ns = Load()
    assert(reg, "registered")
    eq(reg.key, "Legacy")
    assert(reg.window and reg.pause and reg.summary and reg.move and reg.reset, "hub fields")
    eq(#reg.options, 3)
    ns.Scan()
    ns.Snapshot()
    eq(reg.summary():match("^[^\n]*"), "Legacy 12/65, 3 to Replica Ironforge Air Rifle")
    assert(reg.summary():find("Next: Explorer", 1, true), reg.summary())
    ns.Toggle()
    for i = 1, 4 do ns.ShowTab(i); ns.Refresh() end
    ns.SetGoal(25)
    ns.ShowTab(1)
    ns.Move(true)
    ns.Move(false)
    reg.reset()
    eq(ns.db.goal, 0)
    eq(ns.db.raid, false)
end)

test("the game's Legacy window opens at a challenge", function()
    Fake(world())
    local ns = Load()
    local shown = false
    LegacySystemFrame = { IsShown = function() return shown end }
    ToggleLegacySystemUI = function() shown = true end
    ns.OpenInGame(70010)
    eq(shown, true)
    W.RunTimers()
    local names = {}
    for _, e in ipairs(W.events) do names[#names + 1] = e[1] .. "=" .. tostring(e[2]) end
    eq(table.concat(names, " "), "Legacy.SelectPage=2 Legacy.OpenToChallengeCategory=15593 Legacy.SelectChallenge=70010")
    W.combat = true
    W.events = {}
    ns.OpenInGame(70010)
    W.RunTimers()
    eq(#W.events, 0, "never in combat")
end)

test("a compact window stands beside the game's Legacy window, clear of its tabs, and closes with it", function()
    Fake(world())
    local ns = Load()
    local game = W.stub()
    rawset(game, "GetHeight", function() return 577 end)
    rawset(game, "GetScale", function() return 1 end)
    rawset(game, "GetRight", function() return 700 end)
    rawset(game, "GetTop", function() return 967 end)
    rawset(UIParent, "GetWidth", function() return 1920 end)
    rawset(UIParent, "GetHeight", function() return 1080 end)
    LegacySystemFrame = game
    W.Fire("ADDON_LOADED", "Blizzard_LegacySystem")
    assert(rawget(game, "_OnShow"), "the game's window is hooked")
    local full = ns.Window()
    local c = ns.Compact()
    local placed
    rawset(c, "SetPoint", function(_, p, rel, rp, x, y) placed = { p, rel, rp, x, y } end)
    game:Show(); rawget(game, "_OnShow")(game)
    eq(c:IsShown(), true, "opens with the game's window")
    eq(full:IsShown(), false, "the full window stays closed")
    eq(placed[1], "TOPLEFT"); eq(placed[2], game); eq(placed[3], "TOPRIGHT")
    eq(placed[4], ns.BESIDE_GAP, "a gap for the game's side tabs")
    eq(ns.COMPACT_W * 2, ns.Skin.WIDE_W, "half as wide as the full window")
    game:Hide(); rawget(game, "_OnHide")(game)
    eq(c:IsShown(), false, "closes with it")

    ns.SetPref("beside", false)
    rawget(game, "_OnShow")(game)
    eq(c:IsShown(), false, "the switch keeps it closed")
    ns.SetPref("beside", true)

    -- No room to the right: it hugs the screen's edge at the game window's height.
    rawset(game, "GetRight", function() return 1600 end)
    rawget(game, "_OnShow")(game)
    eq(placed[1], "TOPRIGHT"); eq(placed[2], UIParent)
    LegacySystemFrame = nil
end)

test("where the compact window stands: the game window's height, a gap, inside the screen", function()
    Fake(world())
    local ns = Load()
    local k, gap, fits = ns.BesidePlace(577, 1, 968, 1920)
    eq(k, 1); eq(gap, 40); eq(fits, true)
    k, gap, fits = ns.BesidePlace(577, 1.2, 800, 1920)
    eq(math.floor(k * 100 + 0.5), 120, "as high as a scaled game window")
    eq(math.floor(gap * k + 0.5), 48, "the gap grows with the game window")
    eq(fits, true)
    k = ns.BesidePlace(2000, 1, 900, 1920)
    eq(k, 1.6, "never huge")
    k = ns.BesidePlace(100, 1, 900, 1920)
    eq(k, 0.8, "never tiny")
    local _, _, f2 = ns.BesidePlace(577, 1, 1500, 1920)
    eq(f2, false, "no room to the right")
    k, gap, fits = ns.BesidePlace(nil, nil, nil, nil)
    eq(k, 1); eq(fits, true)
end)

test("the compact window shows five steps: the pinned first, then the fastest", function()
    Fake(world())
    local ns = Load()
    ns.Scan()
    ns.Snapshot()
    local steps = ns.Steps()
    assert(#steps > 5, "the sample has more than five steps")
    local five, pinned = ns.CompactSteps(steps, steps)
    eq(#five, 5); eq(pinned, 0)
    for i = 1, 5 do eq(five[i], steps[i], "the fastest in order") end
    local last = steps[#steps].ch.id
    ns.Pin(last)
    five, pinned = ns.CompactSteps(steps, steps)
    eq(#five, 5); eq(pinned, 1)
    eq(five[1].ch.id, last, "a pinned step comes first")
    eq(five[2], steps[1], "the rest are the fastest")
    for i = 2, 5 do assert(five[i].ch.id ~= last, "no step twice") end
    -- With a goal the rest comes from the plan to it.
    local few = ns.CompactSteps(steps, { steps[2] })
    eq(#few, 2); eq(few[2], steps[2])

    local c = ns.Compact()
    c:Show()
    ns.Refresh()
    eq(#c.shown, 5)
    eq(c.shown[1].ch.id, last)
    c.ShowSettings(true)
    eq(c.settings:IsShown(), true); eq(c.plan:IsShown(), false)
    c.ShowSettings(false)
    eq(c.plan:IsShown(), true)
end)

test("Full window opens the full window in the middle; its Legacy window button gives way to the game's", function()
    Fake(world())
    local ns = Load()
    ns.Scan()
    ns.Snapshot()
    local shown = false
    local game = W.stub()
    rawset(game, "IsShown", function() return shown end)
    LegacySystemFrame = game
    ToggleLegacySystemUI = function() shown = true end
    local c = ns.Compact()
    local full = ns.Window()
    local placed
    rawset(full, "SetPoint", function(_, p) placed = p end)
    c.full:GetScript("OnClick")(c.full)
    eq(full:IsShown(), true)
    eq(placed, "CENTER")
    ns.ToGame()
    eq(shown, true, "the game's window opens")
    eq(full:IsShown(), false, "and the full window steps aside for it")
    -- With `beside` off there is no compact window, so the full one stays.
    ns.SetPref("beside", false)
    full:Show()
    ns.ToGame()
    eq(full:IsShown(), true)
    LegacySystemFrame = nil
    ToggleLegacySystemUI = nil
end)

test("the tracker starts hidden, shows to be placed in the Unlock mode, and the hub can switch it", function()
    Fake(world())
    local reg
    GulliToolkit = { Register = function(t) reg = t end }
    local ns = Load()
    ns.Scan()
    ns.Snapshot()
    eq(ns.db.tracker, false, "hidden by default")
    eq(ns.db.locked, nil, "no lock of its own")
    ns.Move(true)
    local t = ns.TrackerFrame()
    assert(t and t:IsShown(), "in the Unlock mode the tracker shows to be placed even when it is off")
    assert(t.mover:IsShown(), "and the mover lies over it")
    ns.Move(false)
    eq(t:IsShown(), false, "off again when the mode ends")
    local fr = reg.frames[1]
    eq(fr.get(), false)
    fr.set(true)
    eq(ns.db.tracker, true)
    eq(fr.frame(), t)
end)

test("a tracker shown before is hidden once by the update", function()
    Fake(world())
    GulliLegacyDB = { tracker = true, locked = false }
    local ns = Load()
    eq(ns.db.tracker, false)
    eq(ns.db.locked, nil)
    ns.SetPref("tracker", true)
    eq(ns.db.tracker, true, "the player can show it again")
end)

test("the detail page: what is left, part by part, and how to do it", function()
    Fake(world())
    local ns = Load()
    ns.Scan()
    ns.Snapshot()
    local parts = ns.Parts(ns.byID[70040])
    eq(#parts, 1)
    eq(parts[1].text, "Explore Durotar")
    eq(parts[1].got, 1); eq(parts[1].total, 3)
    eq(table.concat(parts[1].left, ", "), "Razor Hill, Sen'jin Village", "the areas still to find")
    eq(ns.GuideKind(ns.byID[70040]), "explore")
    local sp = ns.Parts(ns.byID[70010])
    eq(sp[1].text, "Shadowfang Keep", "open parts first")
    eq(sp[2].done, true)
    eq(ns.GuideKind(ns.byID[70010]), "dungeon")
    eq(ns.GuideKind(ns.byID[62001]), "level")
    eq(ns.GuideKind(ns.byID[70001]), "skill")
    local lines = ns.Guide(ns.byID[62001], nil)
    assert(lines[1]:find("level 45", 1, true), lines[1])
    eq(ns.WowheadURL(ns.byID[70040]), "https://www.wowhead.com/search?q=Explorer")
    eq(ns.WowheadURL({ name = "Lord Valthalak Laid to Rest" }), "https://www.wowhead.com/search?q=Lord%20Valthalak%20Laid%20to%20Rest")
    ns.ShowTab(3)
    ns.ShowDetail(70040)
    eq(ns.DetailID(), 70040)
    ns.Refresh()
    ns.ShowTab(3)
    eq(ns.DetailID(), nil, "a tab leaves the detail page")
end)

test("a meta achievement is opened up: Explore Azeroth lists its zones", function()
    local spec = world()
    spec.cats[#spec.cats].achs = { 99999 }
    spec.cats[7].achs = { 80000, 728 }
    spec.ach[80000] = { name = "Explore Azeroth", points = 1, crit = { { "Explore Kalimdor", 8, false, 0, 1, 80001 } } }
    spec.ach[80001] = { name = "Explore Kalimdor", points = 0, crit = { { "Explore Durotar", 8, false, 0, 1, 728 },
        { "Explore Mulgore", 8, true, 1, 1, 80002 } } }
    spec.ach[80002] = { name = "Explore Mulgore", points = 0, done = true, crit = { { "Bloodhoof Village", 0, true } } }
    Fake(spec)
    local ns = Load()
    ns.Scan()
    local parts = ns.Parts(ns.byID[80000])
    eq(#parts, 2, "the two zones, not the continent")
    eq(parts[1].text, "Explore Durotar"); eq(#parts[1].left, 2)
    eq(parts[2].text, "Explore Mulgore"); eq(parts[2].done, true)
end)

test("Lord Valthalak gets its own steps", function()
    local spec = world()
    spec.cats[7].achs = { 80010 }
    spec.ach[80010] = { name = "Lord Valthalak Laid to Rest", points = 1, crit = { { "Mea Culpa, Lord Valthalak", 27, false } } }
    Fake(spec)
    local ns = Load()
    ns.Scan()
    local ch = ns.byID[80010]
    eq(ns.GuideKind(ch), "valthalak")
    local lines = ns.Guide(ch, nil)
    eq(#lines, 4)
    assert(lines[2]:find("An Earnest Proposition", 1, true), lines[2])
end)

test("a step the character is too low for counts the levelling and goes down the list", function()
    local spec = world()
    spec.cats[7].achs = { 80010, 70040, 728 }
    spec.ach[80010] = { name = "Lord Valthalak Laid to Rest", points = 1, crit = {} }
    Fake(spec)
    local ns = Load()
    ns.Scan()
    ns.Snapshot()
    local ch = ns.byID[80010]
    eq(ch.minLevel, 60)
    eq(ch.activity, "dungeon", "five dungeons need a group")
    local steps = ns.Steps()
    local v = has(steps, 80010)
    eq(v.needLevel, 60)
    eq(v.eta, ns.SPECIAL.valthalak.eta + v.levelEta)
    eq(ns.Tag(v), "group")
    local function index(id) for i, s in ipairs(steps) do if s.ch.id == id then return i end end end
    assert(index(80010) > index(70001), "not before 18 tailoring points")
    local parts = ns.Parts(ch)
    eq(#parts, 1, "no part in the game: the chain itself is left")
    eq(parts[1].done, false); eq(parts[1].whole, true)
    local _, _, notes = ns.Guide(ch, v)
    assert(notes[1]:find("level 60", 1, true), notes[1])
    ns.SetPref("dungeon", false)
    eq(has(ns.Steps(), 80010), nil, "a group step follows the dungeon switch")
    ns.ShowDetail(80010)
end)

test("skills need the level of their rank", function()
    eq(Load().SkillLevel(150), 10)
    local spec = world({ level = 15 })
    spec.skills = { [197] = 190 }
    spec.ach[70001].crit = { { "Tailoring 225", 7, false, 190, 225, 197 } }
    Fake(spec)
    local ns = Load()
    ns.Scan()
    ns.Snapshot()
    eq(ns.SkillLevel(75), 0); eq(ns.SkillLevel(225), 20); eq(ns.SkillLevel(300), 35)
    local t = has(ns.Steps(), 70001)
    eq(t.needLevel, 20, "Expert needs level 20")
    assert(t.eta > 35 * ns.TIME.skill + ns.TIME.shop, "with the levelling")
end)

test("exploring: the time from the dark areas, zones by level, above the level counted", function()
    local spec = world()
    spec.cats[7].achs = { 80000, 728 }
    spec.ach[80000] = { name = "Explore Azeroth", points = 1, crit = { { "Explore Kalimdor", 8, false, 0, 1, 80001 } } }
    spec.ach[80001] = { name = "Explore Kalimdor", points = 0, crit = { { "Explore Winterspring", 8, false, 0, 1, 80003 },
        { "Explore Durotar", 8, false, 0, 1, 728 }, { "Explore Mulgore", 8, true, 1, 1, 80002 } } }
    spec.ach[80002] = { name = "Explore Mulgore", points = 0, done = true, icon = 236850, crit = { { "Bloodhoof Village", 0, true } } }
    spec.ach[80003] = { name = "Explore Winterspring", points = 0, icon = 134400, crit = {
        { "Everlook", 0 }, { "Frostfire Hot Springs", 0 }, { "Lake Kel'Theril", 0 }, { "Mazthoril", 0 } } }
    Fake(spec)
    C_Map = { GetMapChildrenInfo = function(root)
                  if root ~= 947 then return {} end
                  return { { mapID = 1, name = "Durotar" }, { mapID = 2, name = "Winterspring" }, { mapID = 3, name = "Mulgore" } }
              end,
              GetMapLevels = function(id) return ({ 1, 55, 1 })[id], ({ 10, 60, 10 })[id] end }
    local ns = Load()
    ns.Scan()
    ns.Snapshot()
    local ch = ns.byID[80000]
    eq(ch.open, 2); eq(ch.total, 3, "zones, not the continent")
    eq(ch.zonesAbove, 1, "Winterspring is above level 37")
    eq(ch.eta, 2 * ns.TIME.zone + 6 * ns.TIME.area)
    local parts = ns.Parts(ch)
    eq(parts[1].text, "Explore Durotar", "the zone of the level first")
    eq(parts[2].text, "Explore Winterspring"); eq(parts[2].minLevel, 55); eq(parts[2].icon, nil, "no question mark")
    eq(parts[3].icon, 236850)
    local s = has(ns.Steps(), 80000)
    assert(ns.Detail(s):find("Zones left: 2, above your level: 1", 1, true), ns.Detail(s))
    eq(ns.ZoneLevels("Explore Western Plaguelands"), nil, "a zone the map does not list")
    ns.ShowDetail(80000)
    C_Map = nil
end)

test("the Challenges tab sorts by progress by default, or by type or name", function()
    Fake(world())
    local ns = Load()
    ns.Scan()
    local list = ns.Challenges()
    eq(list[1].done, true, "done first")
    local function index(id) for i, ch in ipairs(list) do if ch.id == id then return i end end end
    assert(index(70010) < index(62001), "5 of 6 dungeons before a level challenge with nothing done")
    assert(index(70040) < index(70011), "a third explored before nothing")
    ns.SetPref("sort", "name")
    list = ns.Challenges()
    eq(list[1].name, "Conqueror of the Lair")
    ns.SetPref("sort", "kind")
    list = ns.Challenges()
    eq(list[1].kind, "level")
    ns.ShowTab(3)
end)

test("an empty realm name never makes a second entry for one character", function()
    Fake({ db = { chars = {
        ["Tester-"] = { name = "Tester", class = "PRIEST", level = 50, realm = "", skills = {}, t = 200 },
        ["Tester-Realm"] = { name = "Tester", class = "PRIEST", level = 49, realm = "Realm", skills = {}, t = 100,
                             rate = 7 } } } })
    GetRealmName = function() return "" end
    local ns = Load()
    eq(ns.db.chars["Tester-"], nil, "merged on load")
    eq(ns.db.chars["Tester-Realm"].level, 50, "the newer entry wins")
    eq(ns.db.chars["Tester-Realm"].rate, 7, "and keeps what only the older one had")
    ns.Snapshot()
    eq(ns.db.chars["Tester-"], nil, "a snapshot without a realm keeps the saved realm")
    eq(ns.db.chars["Tester-Realm"].realm, "Realm")
    eq(#ns.Chars(), 1)
end)

W.finish()
