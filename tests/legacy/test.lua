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
    eq(first[1], 70001, "18 tailoring points")
    eq(first[2], 70040, "two areas to explore")
    eq(first[3], 70010, "one dungeon")
    eq(steps[1].eta, 18 * ns.TIME.skill + ns.TIME.shop)
    local alch = has(steps, 70002)
    eq(alch.learn, true, "one profession: a second can be learned")
    local lock = has(steps, 62009)
    eq(lock.new, true, "no warlock yet: a new character")
    eq(lock.eta, ns.LevelSeconds(1, 0, 25) + ns.TIME.switch)
    assert(ns.Detail(steps[1]):find("18 skill points (132 to 150)", 1, true), ns.Detail(steps[1]))
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
    eq(has(ns.Steps(), 70020), nil, "a raid waits for level 60")
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
    eq(#reg.options, 4)
    ns.Scan()
    ns.Snapshot()
    eq(reg.summary():match("^[^\n]*"), "Legacy 12/65, 3 to Replica Ironforge Air Rifle")
    assert(reg.summary():find("Next: Journeyman Tailor", 1, true), reg.summary())
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

W.finish()
