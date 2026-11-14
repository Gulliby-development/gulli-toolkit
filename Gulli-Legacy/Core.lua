-- The Legacy challenges of WoW Forever: which ones the account still misses, and the fastest
-- next steps to the next Legacy point and the next reward of the Progress Track. Challenges are
-- the game's achievements that give Legacy points; everything is read from the game, nothing is
-- spent or clicked for the player. Each character saves a snapshot (level, skills, points) when
-- it plays, so the plan can suggest another character.

local ADDON, ns = ...
local L = ns.L

-- Game ids of the Legacy system (WoW Forever 1.60).
ns.CURRENCY = 4225             -- the trait currency of Legacy points
ns.TREES = { 1187, 1188, 1189 } -- the Professions, Adventure and Progression trees
ns.FACTION = 2802              -- the Progress Track: its renown level is the points earned
ns.MAX_SPEND = 16              -- points one character can spend
ns.TOTAL = 65                  -- points the account can earn
ns.REWARDS = { 15, 25, 40, 55 } -- the Progress Track rewards
-- Achievement categories by what the player does there. A category not listed is solo play.
-- A sub-category takes the activity of its parent.
ns.ACTIVITY = {
    [15593] = "dungeon", [15594] = "raid", [15626] = "raid",
    [15595] = "pvp", [15597] = "pvp", [15598] = "pvp", [15620] = "pvp",
    [15425] = "ignore",
}
-- The class challenges: achievement id -> class and the level it asks for.
ns.CLASS_ACH = {}
for class, ids in pairs({ WARRIOR = { 61499, 61500, 61501 }, DRUID = { 61502, 61503, 61504 },
    HUNTER = { 61989, 61992, 61993 }, MAGE = { 61994, 61995, 61996 }, PALADIN = { 61997, 61998, 61999 },
    PRIEST = { 62000, 62001, 62002 }, ROGUE = { 62003, 62004, 62005 }, SHAMAN = { 62006, 62007, 62008 },
    WARLOCK = { 62009, 62010, 62011 } }) do
    for i, id in ipairs(ids) do ns.CLASS_ACH[id] = { class, ({ 25, 45, 60 })[i] } end
end
-- Primary professions by skill line: a character with fewer than two can learn one more.
ns.PRIMARY = { [171] = true, [164] = true, [333] = true, [202] = true, [165] = true, [197] = true,
               [182] = true, [186] = true, [393] = true }
-- The lowest level for the dungeon challenges, in the order of their achievement ids
-- (Novice, Experienced, Master Spelunker), and for a raid.
ns.DUNGEON_MIN = { 15, 30, 45 }
ns.RAID_MIN = 60
-- XP to the next level, levels 1-59.
ns.XP_TO = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400,
    16000, 17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
    50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800,
    117500, 123200, 129100, 135100, 141200, 147500, 153900, 160400, 167100, 173900, 180800, 187900, 195000,
    202300, 209800 }
-- Time guesses in seconds. A new kind of step gets its guess here and a case in the test.
ns.TIME = {
    switch = 300,  -- logging another character in and getting there
    skill = 45,    -- one skill point: a craft plus a share of the shopping
    shop = 600,    -- buying the reagents once
    train = 600,   -- finding the trainer for a new profession
    dungeon = 3600, -- one dungeon with finding the group
    boss = 1200,   -- one raid boss with the trash before it
    task = 900,    -- one other open part of a challenge (a quest)
    zone = 300,    -- getting to a zone to explore and across it
    area = 60,     -- one more area of that zone
}
-- Challenges the achievement data says too little about, by guide kind: the level they need,
-- whether they need a group, and the time they take from the start.
ns.SPECIAL = {
    valthalak = { minLevel = 60, group = true, eta = 7 * 3600 }, -- five dungeons, some twice, and the summon
}
-- The level a profession's skill needs: Journeyman from 10, Expert from 20, Artisan from 35.
function ns.SkillLevel(need)
    need = need or 0
    if need > 225 then return 35 elseif need > 150 then return 20 elseif need > 75 then return 10 end
    return 0
end
ns.SAMPLE = 900 -- XP's session counts as your pace after this many seconds of play

local function secret(v) return issecretvalue and issecretvalue(v) end

-- Game API wrappers ---------------------------------------------------------------------------

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local r = { pcall(fn, ...) }
    if not r[1] then return nil end
    return unpack(r, 2, table.maxn(r))
end

local function categories() return call(GetCategoryList) or {} end
local function numAchievements(cat) return tonumber((call(GetCategoryNumAchievements, cat, true))) or 0 end
local function categoryParent(cat) local _, parent = call(GetCategoryInfo, cat) return parent end
local function achievement(a, b) return call(GetAchievementInfo, a, b) end
local function numCriteria(id) return tonumber((call(GetAchievementNumCriteria, id))) or 0 end
local function criterion(id, i) return call(GetAchievementCriteriaInfo, id, i) end
local function achievementCategory(id) return call(GetAchievementCategory, id) end

-- The Legacy points an achievement gives (a number, or a table with the amount).
local function pointsFor(id)
    local T = C_Traits
    local v = T and call(T.GetTraitCurrencyForAchievement, ns.CURRENCY, id)
    if type(v) == "table" then v = v.quantity or v.amount or v[1] end
    return tonumber(v) or 0
end
ns.PointsFor = pointsFor

local function renown()
    local M = C_MajorFactions
    return M and tonumber((call(M.GetCurrentRenownLevel, ns.FACTION))) or nil
end

-- Points this character can still spend and has spent, from the first Legacy tree that answers.
local function treePoints()
    local T = C_Traits
    if not T then return nil end
    for _, tree in ipairs(ns.TREES) do
        local cfg = call(T.GetConfigIDByTreeID, tree)
        local rows = cfg and call(T.GetTreeCurrencyInfo, cfg, tree, false)
        if type(rows) == "table" then
            for _, r in pairs(rows) do
                if type(r) == "table" and r.traitCurrencyID == ns.CURRENCY then
                    return tonumber(r.quantity) or 0, tonumber(r.spent) or 0
                end
            end
        end
    end
end

-- The character's skill lines: skill line id -> rank. C_SkillInfo first, the professions list after.
local function readSkills()
    local S = C_SkillInfo
    local out, any = {}, false
    if S and S.GetNumSkillLines and S.GetSkillLineInfo then
        for i = 1, tonumber((call(S.GetNumSkillLines))) or 0 do
            local info = call(S.GetSkillLineInfo, i)
            if type(info) == "table" and not info.isHeader and info.skillID and info.rank then
                out[info.skillID] = info.rank
                any = true
                local name = info.skillLineName or info.name or info.skillName
                if type(name) == "string" and name ~= "" and ns.db then ns.db.skillNames[info.skillID] = name end
            end
        end
    elseif GetProfessions and GetProfessionInfo then
        for _, idx in ipairs({ call(GetProfessions) }) do
            local _, _, rank, _, _, _, line = call(GetProfessionInfo, idx)
            if line and rank then out[line] = rank; any = true end
        end
    end
    return any and out or nil
end

local function playerXP()
    local cur = UnitXP and UnitXP("player")
    return (not secret(cur) and tonumber(cur)) or 0
end

-- The challenges ------------------------------------------------------------------------------

-- What the player does for a category: dungeon, raid, pvp, ignore, or solo.
function ns.ActivityOf(cat)
    local seen = 0
    while cat and seen < 6 do
        if ns.ACTIVITY[cat] then return ns.ACTIVITY[cat] end
        cat = categoryParent(cat)
        seen = seen + 1
    end
    return "solo"
end

-- Every Legacy challenge: walks the achievement categories once and keeps the ones that give
-- points. Returns false while the game has not sent the achievements yet.
local function discover()
    local found = {}
    for _, cat in ipairs(categories()) do
        if ns.ActivityOf(cat) ~= "ignore" then
            for i = 1, numAchievements(cat) do
                local id = achievement(cat, i)
                if id and pointsFor(id) > 0 then found[#found + 1] = { id = id, cat = cat } end
            end
        end
    end
    table.sort(found, function(a, b) return a.id < b.id end)
    if #found == 0 then return false end
    ns.ids = found
    return true
end

-- The open parts of a chain step (criteria type 8 is another achievement).
local function childOpen(childID)
    local open, total = 0, 0
    for i = 1, numCriteria(childID) do
        local _, _, done = criterion(childID, i)
        total = total + 1
        if not done then open = open + 1 end
    end
    if total == 0 then
        local _, _, _, completed = achievement(childID)
        return completed and 0 or 1, 1
    end
    return open, total
end

local function build(e, dungeonIndex)
    local id, name, _, completed, _, _, _, desc, _, icon = achievement(e.id)
    local ch = { id = e.id, name = name or ("#" .. e.id), icon = icon, done = completed == true,
                 desc = type(desc) == "string" and desc ~= "" and desc or nil,
                 cat = e.cat, activity = ns.ActivityOf(e.cat), points = pointsFor(e.id), parts = {} }
    local cls = ns.CLASS_ACH[e.id]
    if cls then ch.kind, ch.class, ch.need = "level", cls[1], cls[2] end
    local open, total = 0, 0
    for i = 1, numCriteria(e.id) do
        local text, ctype, done, qty, req, _, _, asset = criterion(e.id, i)
        if ctype == 7 and not ch.kind then
            ch.kind, ch.skill, ch.need = "skill", asset, tonumber(req)
        elseif ctype == 5 and not ch.kind then
            ch.kind, ch.need = "level", tonumber(req)
        end
        if ctype == 8 and asset then
            local o, t = childOpen(asset)
            open, total = open + (done and 0 or o), total + t
        elseif numCriteria(e.id) == 1 and (tonumber(req) or 0) > 1 then
            open, total = math.max(0, req - (tonumber(qty) or 0)), req
        else
            open, total = open + (done and 0 or 1), total + 1
        end
        ch.parts[#ch.parts + 1] = { text = text, done = done == true, qty = qty, req = req, type = ctype, asset = asset }
    end
    if total == 0 then open, total = ch.done and 0 or 1, 1 end
    if ch.done then open = 0 end
    ch.open, ch.total = open, total
    ch.kind = ch.kind or ch.activity
    if ch.activity == "dungeon" then ch.minLevel = ns.DUNGEON_MIN[dungeonIndex] or ns.DUNGEON_MIN[#ns.DUNGEON_MIN] end
    if ch.activity == "raid" then ch.minLevel = ns.RAID_MIN end
    return ch
end

-- Reads every challenge again. Returns the list (empty while the game is not ready).
function ns.Scan()
    if not ns.ids and not discover() then ns.list = {}; return ns.list end
    local list, dungeons = {}, 0
    for _, e in ipairs(ns.ids) do
        local d
        if ns.ActivityOf(e.cat) == "dungeon" then dungeons = dungeons + 1; d = dungeons end
        list[#list + 1] = build(e, d)
    end
    ns.list = list
    ns.byID = {}
    for _, ch in ipairs(list) do ns.byID[ch.id] = ch; ns.Refine(ch) end
    return list
end

-- Points: earned (account), available and spent (this character).
function ns.Points()
    local done = 0
    for _, ch in ipairs(ns.list or {}) do if ch.done then done = done + (ch.points or 1) end end
    local avail, spent = treePoints()
    return { earned = renown() or done, avail = avail, spent = spent }
end

-- The Progress Track rewards: { level, name, icon, got }.
function ns.Rewards(earned)
    local out = {}
    local M = C_MajorFactions
    for _, lvl in ipairs(ns.REWARDS) do
        local name, icon
        local list = M and call(M.GetRenownRewardsForLevel, ns.FACTION, lvl)
        local r = type(list) == "table" and list[1]
        if type(r) == "table" then
            name, icon = r.name, r.icon
            if (not name or name == "") and r.itemID and C_Item and C_Item.GetItemNameByID then
                name = call(C_Item.GetItemNameByID, r.itemID)
            end
        end
        out[#out + 1] = { level = lvl, name = (name and name ~= "") and name or L["REWARD_" .. lvl],
                          icon = icon or ns.REWARD_ICON[lvl], got = (earned or 0) >= lvl }
    end
    return out
end
ns.REWARD_ICON = {
    [15] = "Interface\\Icons\\INV_Musket_04", [25] = "Interface\\Icons\\Ability_Hunter_Pet_Bear",
    [40] = "Interface\\Icons\\INV_Shirt_GuildTabard_01", [55] = "Interface\\Icons\\Ability_Mount_WhiteDireWolf",
}

-- The next reward not reached yet, or nil.
function ns.NextReward(earned)
    for _, r in ipairs(ns.Rewards(earned)) do if not r.got then return r end end
end

-- Characters ----------------------------------------------------------------------------------

function ns.CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "")
end

-- The pace from the XP module when its session is long enough: XP per hour, or nil.
function ns.MeasuredRate()
    local s = GulliXPCharDB and GulliXPCharDB.s
    if type(s) == "table" and (tonumber(s.active) or 0) >= ns.SAMPLE and (tonumber(s.gained) or 0) > 0 then
        return s.gained * 3600 / s.active
    end
end

-- Saves this character: class, level, XP, skills, pace and points.
function ns.Snapshot()
    if not ns.db then return end
    local key = ns.CharKey()
    local c = ns.db.chars[key] or {}
    local _, class = UnitClass("player")
    c.name, c.realm, c.class = UnitName("player"), GetRealmName and GetRealmName() or "", class
    local lvl = UnitLevel("player")
    if not secret(lvl) then c.level = lvl end
    c.xp = playerXP()
    c.skills = readSkills() or c.skills or {}
    c.rate = ns.MeasuredRate() or c.rate
    local avail, spent = treePoints()
    if avail then c.avail, c.spent = avail, spent end
    c.t = time()
    ns.db.chars[key] = c
    return c
end

-- Every saved character, this one first, then by level.
function ns.Chars()
    local out, me = {}, ns.CharKey()
    for key, c in pairs(ns.db and ns.db.chars or {}) do out[#out + 1] = { key = key, char = c, me = key == me } end
    table.sort(out, function(a, b)
        if a.me ~= b.me then return a.me end
        if (a.char.level or 0) ~= (b.char.level or 0) then return (a.char.level or 0) > (b.char.level or 0) end
        return a.key < b.key
    end)
    return out
end

function ns.Forget(key)
    if key and key ~= ns.CharKey() and ns.db then ns.db.chars[key] = nil end
    if ns.Refresh then ns.Refresh() end
end

-- XP per hour at a level when there is no measured pace.
function ns.DefaultRate(level)
    return 2500 + 250 * (level or 1)
end

-- Seconds of play from (level, xp into it) to the start of level `to`. rate: XP per hour, or
-- nil for the default pace of each level.
function ns.LevelSeconds(from, xp, to, rate)
    local sec = 0
    for l = from, to - 1 do
        local need = ns.XP_TO[l] or ns.XP_TO[#ns.XP_TO]
        if l == from then need = math.max(0, need - (xp or 0)) end
        sec = sec + need * 3600 / (rate or ns.DefaultRate(l))
    end
    return math.floor(sec)
end

-- The plan -------------------------------------------------------------------------------------

-- Settings; a new one gets its default here and a row in the window.
ns.DEFAULTS = { dungeon = true, raid = false, pvp = false, alts = true, newClass = true,
                tracker = true, locked = true, announce = true, alpha = 80, goal = 0, sort = "progress" }
ns.OPT_ICON = {
    dungeon = "Interface\\Icons\\INV_Misc_Key_14",
    raid = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
    pvp = "Interface\\Icons\\INV_BannerPVP_02",
    alts = "Interface\\Icons\\INV_Misc_GroupNeedMore",
    newClass = "Interface\\Icons\\Spell_Holy_Resurrection",
    tracker = "Interface\\Icons\\INV_Misc_Spyglass_02",
    locked = "Interface\\Icons\\INV_Misc_Key_04",
    announce = "Interface\\Icons\\INV_Misc_Note_02",
    alpha = "Interface\\Icons\\INV_Misc_Gem_Pearl_04",
}

-- Whether the settings let the plan suggest this challenge.
function ns.Allowed(ch)
    local a = ch.activity
    if a == "dungeon" then return ns.db.dungeon end
    if a == "raid" then return ns.db.raid end
    if a == "pvp" then return ns.db.pvp end
    return a ~= "ignore"
end

local function rateOf(c, me)
    if me then return ns.MeasuredRate() or c.rate end
    return c.rate
end

-- A way for a character below the level the step needs: the levelling comes first and counts.
local function levelFirst(w, need)
    local c = w.char or {}
    local lvl = c.level or 1
    if need and need > lvl and w.eta then
        w.needLevel = need
        w.levelEta = ns.LevelSeconds(lvl, c.xp, need, rateOf(c, w.me))
        w.eta = w.eta + w.levelEta
    end
    return w
end

-- The ways to finish one challenge: one per character that can do it (and a new character for
-- a class the account does not have). Each way: { ch, char, key, me, eta, from, to, learn, new }.
function ns.Ways(ch)
    local ways = {}
    local meKey = ns.CharKey()
    local function add(w)
        w.ch = ch
        if not w.me then
            if w.new then
                if not ns.db.newClass then return end
            elseif not ns.db.alts then return end
            if w.eta then w.eta = w.eta + ns.TIME.switch end
        end
        ways[#ways + 1] = w
    end
    local chars = ns.Chars()
    if ch.kind == "level" and ch.need then
        local any = false
        for _, e in ipairs(chars) do
            local c = e.char
            if (not ch.class or c.class == ch.class) and (c.level or 0) < ch.need then
                any = true
                add({ char = c, key = e.key, me = e.me, from = c.level or 1, to = ch.need,
                      eta = ns.LevelSeconds(c.level or 1, c.xp, ch.need, rateOf(c, e.me)) })
            elseif not ch.class or c.class == ch.class then
                any = true
            end
        end
        if ch.class and not any then
            add({ new = true, class = ch.class, from = 1, to = ch.need, eta = ns.LevelSeconds(1, 0, ch.need) })
        end
    elseif ch.kind == "skill" and ch.skill and ch.need then
        local me
        for _, e in ipairs(chars) do
            local rank = e.char.skills and e.char.skills[ch.skill]
            if rank and rank < ch.need then
                add(levelFirst({ char = e.char, key = e.key, me = e.me, from = rank, to = ch.need,
                      eta = (ch.need - rank) * ns.TIME.skill + ns.TIME.shop }, ns.SkillLevel(ch.need)))
            end
            if e.me then me = e end
        end
        if #ways == 0 and me then
            local n = 0
            for line in pairs(me.char.skills or {}) do if ns.PRIMARY[line] then n = n + 1 end end
            if n < 2 then
                add(levelFirst({ char = me.char, key = me.key, me = true, learn = true, from = 1, to = ch.need,
                      eta = (ch.need - 1) * ns.TIME.skill + ns.TIME.shop + ns.TIME.train }, ns.SkillLevel(ch.need)))
            end
        end
    else
        local per = ch.activity == "dungeon" and ns.TIME.dungeon or ch.activity == "raid" and ns.TIME.boss
            or ch.activity ~= "pvp" and ns.TIME.task or nil
        local eta = ch.eta or (per and ch.open * per) or nil
        for _, e in ipairs(chars) do
            local lvl = e.char.level or 0
            if (e.me or ch.minLevel) and lvl >= (ch.minLevel or 0) then
                add({ char = e.char, key = e.key, me = e.me, eta = eta })
            elseif e.me and eta then
                -- Too low for it now: the way counts the levelling first.
                add(levelFirst({ char = e.char, key = e.key, me = true, eta = eta }, ch.minLevel))
            end
        end
    end
    return ways
end

-- Faster first; a step without a time guess last; this character before the others.
local function better(a, b)
    if (a.eta ~= nil) ~= (b.eta ~= nil) then return a.eta ~= nil end
    if a.eta and a.eta ~= b.eta then return a.eta < b.eta end
    if (a.me == true) ~= (b.me == true) then return a.me == true end
    local fa, fb = a.ch.open / math.max(1, a.ch.total), b.ch.open / math.max(1, b.ch.total)
    if fa ~= fb then return fa < fb end
    return a.ch.id < b.ch.id
end
ns.Better = better

-- The next steps: the best way to each open challenge the settings allow, fastest first.
-- The second value counts the open challenges the settings hide.
function ns.Steps()
    local out, hidden = {}, 0
    for _, ch in ipairs(ns.list or {}) do
        if not ch.done then
            if not ns.Allowed(ch) then
                hidden = hidden + 1
            else
                local ways = ns.Ways(ch)
                table.sort(ways, better)
                if ways[1] then
                    ways[1].others = #ways - 1
                    out[#out + 1] = ways[1]
                end
            end
        end
    end
    table.sort(out, better)
    return out, hidden
end

-- The fastest step of one character (by its key), for the Characters tab.
function ns.BestFor(key)
    local best
    for _, ch in ipairs(ns.list or {}) do
        if not ch.done and ns.Allowed(ch) then
            for _, w in ipairs(ns.Ways(ch)) do
                if w.key == key and (not best or better(w, best)) then best = w end
            end
        end
    end
    return best
end

-- The goal: a Progress Track reward (0 = no goal, the best next steps). Returns the steps that
-- reach it, the points still missing and the total time (nil when a step has no guess).
function ns.GoalPlan(steps, earned)
    local goal = tonumber(ns.db.goal) or 0
    if goal <= 0 then return nil end
    local need = goal - (earned or 0)
    if need <= 0 then return {}, 0, 0 end
    local out, total = {}, 0
    for i = 1, math.min(need, #steps) do
        out[i] = steps[i]
        total = steps[i].eta and total and total + steps[i].eta or nil
    end
    return out, need, total
end

function ns.SetGoal(level)
    ns.db.goal = tonumber(level) or 0
    if ns.Refresh then ns.Refresh() end
end

-- The goals in the order the goal button walks through them.
function ns.NextGoal()
    local goals = { 0 }
    for _, r in ipairs(ns.REWARDS) do goals[#goals + 1] = r end
    for i, g in ipairs(goals) do
        if g == (tonumber(ns.db.goal) or 0) then return goals[i % #goals + 1] end
    end
    return 0
end

function ns.Pin(id)
    ns.db.pins[id] = not ns.db.pins[id] or nil
    if ns.Refresh then ns.Refresh() end
end

-- What the tracker shows: the pinned steps that are still open, else the first three steps.
function ns.Tracked(steps)
    local pinned = {}
    for _, s in ipairs(steps) do if ns.db.pins[s.ch.id] then pinned[#pinned + 1] = s end end
    if #pinned > 0 then return pinned, true end
    local top = {}
    for i = 1, math.min(3, #steps) do top[i] = steps[i] end
    return top, false
end

-- Text -----------------------------------------------------------------------------------------

function ns.Span(sec)
    if not sec then return L.ETA_NONE end
    sec = math.max(60, math.floor(sec))
    if sec >= 3600 then
        local h = sec / 3600
        local m = math.floor(sec % 3600 / 60)
        if h >= 10 or m == 0 then return L.H:format(math.floor(h + 0.5)) end
        return L.HM:format(math.floor(h), m)
    end
    return L.M:format(math.floor(sec / 60))
end

-- A profession's name: what the game told us, else its trade skill name, else its id.
function ns.SkillName(id)
    local n = ns.db and ns.db.skillNames[id]
    if n then return n end
    if ns.T.en["PROF_" .. tostring(id)] then return L["PROF_" .. id] end
    local T = C_TradeSkillUI
    n = T and call(T.GetTradeSkillDisplayName, id)
    return (type(n) == "string" and n ~= "") and n or ("#" .. tostring(id))
end

function ns.ClassName(class)
    local t = LOCALIZED_CLASS_NAMES_MALE
    return (t and t[class]) or (class and (class:sub(1, 1) .. class:sub(2):lower())) or "?"
end

-- The names of the open parts, at most three.
local function openParts(ch)
    local names = {}
    for _, p in ipairs(ch.parts) do
        if not p.done and p.text and p.text ~= "" then
            names[#names + 1] = p.text
            if #names == 3 then break end
        end
    end
    return table.concat(names, ", ")
end

-- The grey line under a step.
function ns.Detail(s)
    local ch = s.ch
    local who = (not s.me and s.char) and L.D_ON:format(s.char.name or "?") or ""
    if s.new then return L.D_NEW_CLASS:format(ns.ClassName(s.class), s.to) end
    if ch.kind == "level" and s.from then
        local pace = (s.me and ns.MeasuredRate()) and L.D_PACE_XP:format(ns.Short(ns.MeasuredRate()))
            or (s.char and s.char.rate) and L.D_PACE_SAVED:format(ns.Short(s.char.rate)) or L.D_PACE_GUESS
        return who .. L.D_LEVELS:format(s.to - s.from, s.from, s.to) .. " · " .. pace
    end
    if ch.kind == "skill" and s.from then
        local first = s.needLevel and L.D_FROM_LEVEL:format(s.needLevel, ns.Span(s.levelEta or 0)) or ""
        if s.learn then return first .. L.D_LEARN:format(s.to - 1) end
        return who .. first .. L.D_SKILL:format(s.to - s.from, s.from, s.to)
    end
    local first = s.needLevel and L.D_FROM_LEVEL:format(s.needLevel, ns.Span(s.levelEta or 0)) or ""
    if ch.zones then
        return who .. first .. L.D_ZONES:format(ch.open, ch.zonesAbove or 0)
    end
    local left = openParts(ch)
    local line = left ~= "" and L.D_LEFT:format(left) or L.D_OPEN:format(ch.open, ch.total)
    return who .. first .. line
end

-- The detail page ------------------------------------------------------------------------------

-- An icon worth showing: the game's question mark (no icon set) is none.
local function realIcon(icon)
    if icon == nil or icon == 134400 or icon == 0 then return nil end
    if type(icon) == "string" and icon:lower():find("questionmark", 1, true) then return nil end
    return icon
end

-- Whether an achievement is made only of other achievements (Explore Azeroth, Explore Kalimdor).
local function isMeta(id)
    local n = numCriteria(id)
    if n == 0 then return false end
    for i = 1, n do
        local _, ctype, _, _, _, _, _, asset = criterion(id, i)
        if ctype ~= 8 or not asset then return false end
    end
    return true
end

-- One row per part of a challenge, open ones first. A part that is another achievement shows
-- its name, how far it is and the names of its open parts (left); one made of achievements
-- again is opened up, at most three levels deep, so Explore Azeroth lists the zones.
local function partRows(id, out, depth, seen)
    for i = 1, numCriteria(id) do
        local text, ctype, done, qty, req, _, _, asset = criterion(id, i)
        if ctype == 8 and asset and not seen[asset] and depth < 3 and isMeta(asset) then
            seen[asset] = true
            partRows(asset, out, depth + 1, seen)
        elseif ctype == 8 and asset then
            local left, total, got = {}, 0, 0
            for j = 1, numCriteria(asset) do
                local t2, _, d2 = criterion(asset, j)
                total = total + 1
                if d2 then got = got + 1 elseif type(t2) == "string" and t2 ~= "" then left[#left + 1] = t2 end
            end
            local _, cname, _, cdone, _, _, _, _, _, icon = achievement(asset)
            local all = done == true or cdone == true
            if total == 0 then total, got = 1, all and 1 or 0 end
            local lo, hi = ns.ZoneLevels(cname or text)
            out[#out + 1] = { text = cname or text or "", done = all, got = all and total or got, total = total,
                              left = all and {} or left, id = asset, icon = realIcon(icon), type = 8,
                              minLevel = lo, maxLevel = hi }
        else
            local q, r = tonumber(qty), tonumber(req)
            local big = r and r > 1
            out[#out + 1] = { text = text or "", done = done == true, got = big and math.min(q or 0, r) or nil,
                              total = big and r or nil, left = {}, type = ctype, asset = asset }
        end
    end
    return out
end

-- Open parts first; zones by their lowest level, so the ones the player can do now lead.
function ns.Parts(ch)
    local out = partRows(ch.id, {}, 1, {})
    if #out == 0 and not ch.done then
        -- The game lists no part (a quest chain): the challenge itself is what is left.
        out[1] = { text = ch.name, done = false, left = {}, icon = realIcon(ch.icon), whole = true }
    end
    for i, r in ipairs(out) do r.order = i end
    table.sort(out, function(a, b)
        if a.done ~= b.done then return not a.done end
        if not a.done and (a.minLevel or 0) ~= (b.minLevel or 0) and a.minLevel and b.minLevel then
            return a.minLevel < b.minLevel
        end
        return a.order < b.order
    end)
    return out
end

-- Zone levels by map name, read once from the world map; nil when the client does not say.
local zoneLevels
local ROOT_MAPS = { 947, 12, 13, 1414, 1415 }
local function readZones()
    local found, any = {}, false
    if not (C_Map and C_Map.GetMapChildrenInfo and C_Map.GetMapLevels) then return found, false end
    local zoneType = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
    for _, root in ipairs(ROOT_MAPS) do
        local kids = call(C_Map.GetMapChildrenInfo, root, zoneType, true)
        for _, m in ipairs(type(kids) == "table" and kids or {}) do
            if type(m.name) == "string" and m.name ~= "" and not found[m.name] then
                local lo, hi = call(C_Map.GetMapLevels, m.mapID)
                lo, hi = tonumber(lo), tonumber(hi)
                if lo and lo > 0 then found[m.name] = { lo, hi or lo }; any = true end
            end
        end
    end
    return found, any
end

-- The levels of the zone named inside a text ("Explore Redridge Mountains"): the longest
-- map name it holds wins, so "Western Plaguelands" is not read as a shorter name.
function ns.ZoneLevels(text)
    if type(text) ~= "string" then return nil end
    if not zoneLevels then
        local found, any = readZones()
        if not any then return nil end
        zoneLevels = found
    end
    local best, len = nil, 0
    for name, lv in pairs(zoneLevels) do
        if #name > len and text:find(name, 1, true) then best, len = lv, #name end
    end
    if best then return best[1], best[2] end
end

-- What the achievement data alone gets wrong: the level and group a challenge needs, and the
-- time of exploring from the areas still dark. Runs after every scan.
function ns.Refine(ch)
    local kind = ns.GuideKind(ch)
    ch.guide = kind
    local sp = ns.SPECIAL[kind]
    if sp then
        if sp.minLevel then ch.minLevel = math.max(ch.minLevel or 0, sp.minLevel) end
        if sp.group and ch.activity == "solo" then
            ch.activity = "dungeon"
            if ch.kind == "solo" then ch.kind = "dungeon" end
        end
        ch.eta = sp.eta
    end
    if kind == "explore" and not ch.done then
        local parts = ns.Parts(ch)
        local lvl = UnitLevel and tonumber((UnitLevel("player"))) or 0
        local open, sec, above = 0, 0, 0
        for _, p in ipairs(parts) do
            if not p.done then
                open = open + 1
                local areas = p.total and (p.total - (p.got or 0)) or 1
                sec = sec + ns.TIME.zone + areas * ns.TIME.area
                if p.minLevel and p.minLevel > lvl then above = above + 1 end
            end
        end
        if #parts > 1 then
            ch.open, ch.total, ch.zones, ch.zonesAbove = open, #parts, true, above
        end
        ch.eta = sec
    end
end

-- Which guide a challenge gets on its detail page.
local EXPLORE_WORDS = { "xplor", "rkund", "сслед", "探索", "badaj", "xplora" }
function ns.GuideKind(ch)
    local lower = (ch.name or ""):lower()
    if lower:find("valthalak", 1, true) or (ch.name or ""):find("Валтхалак", 1, true) then return "valthalak" end
    if ch.kind == "level" or ch.kind == "skill" then return ch.kind end
    if ch.activity == "dungeon" or ch.activity == "raid" or ch.activity == "pvp" then return ch.activity end
    for _, p in ipairs(ch.parts or {}) do if p.type == 43 then return "explore" end end
    for _, w in ipairs(EXPLORE_WORDS) do if lower:find(w, 1, true) then return "explore" end end
    for _, p in ipairs(ch.parts or {}) do if p.type == 27 then return "quest" end end
    return "solo"
end

-- The lines of what to do, in order. step is the best way the plan found (may be nil).
function ns.Guide(ch, step)
    local k = ns.GuideKind(ch)
    local out = {}
    if k == "level" then
        out[#out + 1] = L.G_LEVEL:format(ns.ClassName(ch.class), ch.need or 60)
        out[#out + 1] = L.G_LEVEL_2
    elseif k == "skill" then
        out[#out + 1] = L.G_SKILL:format(ns.SkillName(ch.skill), ch.need or 300)
        out[#out + 1] = L.G_SKILL_2
    elseif k == "dungeon" then
        out[#out + 1] = L.G_DUNGEON:format(ch.minLevel or ns.DUNGEON_MIN[1])
        out[#out + 1] = L.G_DUNGEON_2
    elseif k == "raid" then
        out[#out + 1] = L.G_RAID
    elseif k == "pvp" then
        out[#out + 1] = L.G_PVP
    elseif k == "explore" then
        out[#out + 1] = L.G_EXPLORE
        out[#out + 1] = L.G_EXPLORE_2
        out[#out + 1] = L.G_EXPLORE_3
    elseif k == "valthalak" then
        for i = 1, 4 do out[#out + 1] = L["G_VAL_" .. i] end
    elseif k == "quest" then
        out[#out + 1] = L.G_QUEST
    else
        out[#out + 1] = L.G_SOLO
    end
    -- The notes under the steps: the level it needs first, and the time.
    local notes = {}
    if ch.done then
        notes[1] = L.G_DONE
    elseif step then
        local span = step.eta and ns.Span(step.eta) or L.NO_GUESS
        -- Levels and skills name the character and the pace; other steps only take time.
        if step.new or step.from or not step.me then
            notes[#notes + 1] = L.G_BEST:format(ns.Detail(step), span)
        else
            if step.needLevel then
                notes[#notes + 1] = L.G_LEVEL_FIRST:format(step.needLevel, ns.Span(step.levelEta or 0))
            end
            notes[#notes + 1] = L.G_TIME:format(span)
        end
    end
    return out, k, notes
end

-- A Wowhead search for the challenge: the game cannot open a link, so the player copies it.
function ns.WowheadURL(ch)
    local q = (ch.name or ""):gsub("[^%w%-%.]", function(c) return string.format("%%%02X", c:byte()) end)
    return "https://www.wowhead.com/search?q=" .. q
end

-- The tag of a step: what the player does, and whether it needs a group.
function ns.Tag(s)
    if s.new then return L.TAG_NEW end
    local a = s.ch.activity
    if a == "dungeon" then return L.TAG_GROUP end
    if a == "raid" then return L.TAG_RAID end
    if a == "pvp" then return L.TAG_PVP end
    return L.TAG_SOLO
end

-- The other Gulli module that helps with a step, when it is loaded.
function ns.Helper(s)
    local mods = GulliToolkit and GulliToolkit.modules
    if not mods or s.new then return nil end
    local a, k = s.ch.activity, s.ch.kind
    local want = k == "skill" and { "CraftProfit" } or k == "level" and { "XP" }
        or a == "dungeon" and { "Bulletin", "DungeonPrep" } or a == "raid" and { "Attune", "Bulletin" } or {}
    for _, key in ipairs(want) do if mods[key] then return key end end
end

function ns.OpenHelper(key)
    if key and GulliToolkit and GulliToolkit.Open then GulliToolkit.Open(key) end
end

function ns.Short(n)
    n = math.floor((n or 0) + 0.5)
    if n >= 10000 then return string.format("%dk", math.floor(n / 1000)) end
    if n >= 1000 then return string.format("%.1fk", n / 1000) end
    return tostring(n)
end

-- One line for the hub's home page.
function ns.Summary()
    if not ns.list or #ns.list == 0 then return nil end
    local p = ns.Points()
    local r = ns.NextReward(p.earned)
    local line = r and L.SUM:format(p.earned, ns.TOTAL, r.level - p.earned, r.name) or L.SUM_ALL:format(p.earned, ns.TOTAL)
    local steps = ns.Steps()
    if steps[1] then line = line .. "\n" .. L.SUM_NEXT:format(steps[1].ch.name, ns.Span(steps[1].eta)) end
    return line, "Interface\\AddOns\\Gulli-Legacy\\icon"
end

-- The game's Legacy window, open at one challenge when id is given.
function ns.OpenInGame(id)
    if InCombatLockdown and InCombatLockdown() then print(L.IN_COMBAT) return end
    if not LegacySystemFrame then
        if type(LegacySystemFrame_LoadUI) == "function" then call(LegacySystemFrame_LoadUI)
        else call((C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn, "Blizzard_LegacySystem") end
    end
    local f = LegacySystemFrame
    if not f then print(L.NO_WINDOW) return end
    if not f:IsShown() then
        if type(ToggleLegacySystemUI) == "function" then call(ToggleLegacySystemUI) else call(ShowUIPanel, f) end
    end
    if id and EventRegistry and C_Timer then
        C_Timer.After(0, function()
            call(EventRegistry.TriggerEvent, EventRegistry, "Legacy.SelectPage", 2)
            local cat = achievementCategory(id)
            if cat then call(EventRegistry.TriggerEvent, EventRegistry, "Legacy.OpenToChallengeCategory", cat) end
            call(EventRegistry.TriggerEvent, EventRegistry, "Legacy.SelectChallenge", id)
        end)
    end
end

-- Settings -------------------------------------------------------------------------------------

function ns.SetPref(key, value)
    ns.db[key] = value
    if ns.Refresh then ns.Refresh() end
end

function ns.Reset()
    local keep = { chars = ns.db.chars, pins = ns.db.pins, skillNames = ns.db.skillNames }
    for k in pairs(ns.db) do ns.db[k] = nil end
    for k, v in pairs(ns.DEFAULTS) do ns.db[k] = v end
    for k, v in pairs(keep) do ns.db[k] = v end
    if ns.Refresh then ns.Refresh() end
end

ns.moving = false
function ns.Move(on)
    ns.moving = on and true or false
    if ns.Refresh then ns.Refresh() end
end

-- The hub's switch: a paused module reads nothing and hides its tracker.
function ns.Pause(on)
    ns.paused = on and true or nil
    if ns.Refresh then ns.Refresh() end
end

-- Events ---------------------------------------------------------------------------------------

-- A new point: a notice and a line in the hub's Recent feed.
function ns.Earned(id)
    if pointsFor(id) <= 0 then return false end
    ns.Scan()
    local ch = ns.byID and ns.byID[id]
    local p = ns.Points()
    local r = ns.NextReward(p.earned)
    local name = ch and ch.name or (select(2, achievement(id))) or ("#" .. id)
    local text = r and L.EARNED_NEXT:format(p.earned, ns.TOTAL, r.level - p.earned, r.name)
        or L.EARNED_ALL:format(p.earned, ns.TOTAL)
    if ns.db.announce then
        if ns.Announce then ns.Announce(L.EARNED, name, text, ch and ch.icon) end
        if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("Legacy", L.EARNED_FEED:format(name, p.earned)) end
    end
    return true
end

-- Reads everything again a moment later, so a burst of events reads once.
function ns.Later()
    if ns.waiting then return end
    ns.waiting = true
    C_Timer.After(1, function()
        ns.waiting = nil
        if ns.paused then return end
        ns.Scan()
        ns.Snapshot()
        if ns.Refresh then ns.Refresh() end
    end)
end

local EVENTS = { "PLAYER_ENTERING_WORLD", "ACHIEVEMENT_EARNED", "CRITERIA_UPDATE", "RECEIVED_ACHIEVEMENT_LIST",
                 "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "TRAIT_CONFIG_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED",
                 "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "PLAYER_LOGOUT" }

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliLegacyDB = GulliLegacyDB or {}
        ns.db = GulliLegacyDB
        for k, v in pairs(ns.DEFAULTS) do if ns.db[k] == nil then ns.db[k] = v end end
        ns.db.chars = ns.db.chars or {}
        ns.db.pins = ns.db.pins or {}
        ns.db.skillNames = ns.db.skillNames or {}
        -- An event the client does not know must not stop the rest.
        local ok = C_EventUtils and C_EventUtils.IsEventValid
        for _, e in ipairs(EVENTS) do
            if not ok or ok(e) then pcall(self.RegisterEvent, self, e) end
        end
        return
    end
    if ns.paused then return end
    if event == "ACHIEVEMENT_EARNED" then
        local id = tonumber(a1)
        if id and ns.Earned(id) then ns.Snapshot() end
        if ns.Refresh then ns.Refresh() end
    elseif event == "PLAYER_LOGOUT" then
        ns.Snapshot()
    else
        ns.Later()
    end
end)

SLASH_GULLILEGACY1 = "/glg"
SLASH_GULLILEGACY2 = "/gullilegacy"
SlashCmdList.GULLILEGACY = function(msg)
    local cmd = strtrim(msg or ""):lower()
    if cmd == "game" or cmd == "legacy" then ns.OpenInGame() return end
    ns.Toggle()
end

function GulliLegacy_Toggle() ns.Toggle() end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "Legacy",
        icon = "Interface\\AddOns\\Gulli-Legacy\\icon",
        slash = "/glg",
        category = "Info",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        summary = function() return ns.Summary() end,
        move = function(on) ns.Move(on) end,
        reset = function() ns.Reset() end,
        pause = function(on) ns.Pause(on) end,
        options = {
            { label = ns.L.OPT_DUNGEON, icon = ns.OPT_ICON.dungeon, tip = ns.L.OPT_DUNGEON_D,
              get = function() return ns.db ~= nil and ns.db.dungeon == true end, set = function(v) ns.SetPref("dungeon", v) end },
            { label = ns.L.OPT_RAID, icon = ns.OPT_ICON.raid, tip = ns.L.OPT_RAID_D,
              get = function() return ns.db ~= nil and ns.db.raid == true end, set = function(v) ns.SetPref("raid", v) end },
            { label = ns.L.OPT_PVP, icon = ns.OPT_ICON.pvp, tip = ns.L.OPT_PVP_D,
              get = function() return ns.db ~= nil and ns.db.pvp == true end, set = function(v) ns.SetPref("pvp", v) end },
            { label = ns.L.OPT_TRACKER, icon = ns.OPT_ICON.tracker, tip = ns.L.OPT_TRACKER_D,
              get = function() return ns.db ~= nil and ns.db.tracker == true end, set = function(v) ns.SetPref("tracker", v) end },
        },
    })
end
