-- Dungeon Journal: each dungeon's quests (in the log, can take now and where, not yet), their
-- rewards and chains, and the way there with the entrance. Journal.lua adds the bosses and their
-- loot. What runs out on the road (repairs, food, the hearthstone) is the hub's Ready card.

local ADDON, ns = ...
local L = ns.L

local function data()
    return ns.Data or { dungeons = {}, byDungeon = {}, quest = {} }
end

-- Settings: the switches. Each change goes through ns.Set.
ns.DEFAULTS = {
    keys = true, remind = true, tomtom = true, hideLater = false,
    warnEnter = true, wishAlert = true, learn = true, mainOnly = true,
}

function ns.Get(key)
    local v = ns.db and ns.db[key]
    if v == nil then return ns.DEFAULTS[key] end
    return v
end

function ns.Set(key, value)
    if ns.db then ns.db[key] = value end
    if ns.Refresh then ns.Refresh() end
    if ns.RefreshTracker then ns.RefreshTracker() end
end

-- Puts every setting back to its default and shows hidden quests again.
function ns.Reset()
    if not ns.db then return end
    for k in pairs(ns.DEFAULTS) do ns.db[k] = nil end
    ns.db.hidden = {}
    if ns.Refresh then ns.Refresh() end
end

function ns.Hidden(id) return ns.db and ns.db.hidden and ns.db.hidden[id] == true end

function ns.SetHidden(id, on)
    if not ns.db then return end
    ns.db.hidden = ns.db.hidden or {}
    ns.db.hidden[id] = on and true or nil
    if ns.Refresh then ns.Refresh() end
end

-- Game API wrappers.
local Q = C_QuestLog or {}
local function questDone(id)
    if Q.IsQuestFlaggedCompleted then return Q.IsQuestFlaggedCompleted(id) end
    return IsQuestFlaggedCompleted and IsQuestFlaggedCompleted(id) or false
end
local function onQuest(id)
    if Q.IsOnQuest then return Q.IsOnQuest(id) end
    return Q.GetLogIndexForQuestID and Q.GetLogIndexForQuestID(id) ~= nil or false
end
local function areaName(id)
    local name = id and id > 0 and C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(id)
    return (type(name) == "string" and name ~= "") and name or nil
end
local function itemCount(id)
    return ((C_Item and C_Item.GetItemCount) or GetItemCount or function() return 0 end)(id) or 0
end
local function itemInfo(id)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not get then return nil end
    local name, link, quality, ilvl, _, _, _, _, equipLoc, icon, _, classID, subclassID = get(id)
    if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    return name, link, quality, ilvl, equipLoc, icon, classID, subclassID
end

-- Whether bit `id` (1-based) is set in a race or class mask; 0 means everyone. Masks pass
-- 2^32 on Forever, past what bit.band takes, so this uses plain arithmetic.
local function hasBit(mask, id)
    if not mask or mask == 0 or not id then return true end
    return math.floor(mask / 2 ^ (id - 1)) % 2 == 1
end

local FACTION = { Alliance = "A", Horde = "H" }

local function forMe(q)
    local side = q[11] or ""
    if side ~= "" and FACTION[UnitFactionGroup("player") or ""] and side ~= FACTION[UnitFactionGroup("player")] then
        return false
    end
    return hasBit(q[4], select(3, UnitRace("player"))) and hasBit(q[5], select(3, UnitClass("player")))
end

-- The highest quest level that is gray for this player level.
function ns.GrayLevel(level)
    if level == UnitLevel("player") then
        local range = (UnitQuestTrivialLevelRange and UnitQuestTrivialLevelRange("player"))
            or (GetQuestGreenRange and GetQuestGreenRange())
        if range then return math.max(0, level - range - 1) end
    end
    if level <= 5 then return 0 end
    if level <= 39 then return level - 5 - math.floor(level / 10) end
    if level <= 59 then return level - 1 - math.floor(level / 5) end
    return level - 9
end

-- The game's quest colours: red, orange, yellow, green, gray.
ns.DIFF_COLOR = {
    IMPOSSIBLE = { 1.00, 0.10, 0.10, 1 }, VERYDIFFICULT = { 1.00, 0.50, 0.25, 1 },
    DIFFICULT = { 1.00, 0.82, 0.00, 1 }, STANDARD = { 0.25, 0.75, 0.25, 1 }, TRIVIAL = { 0.50, 0.50, 0.50, 1 },
}

-- How hard a quest of this level is for the player, as the game colours it.
function ns.Difficulty(questLevel, level)
    local diff = questLevel - level
    if diff >= 5 then return "IMPOSSIBLE" end
    if diff >= 3 then return "VERYDIFFICULT" end
    if diff >= -2 then return "DIFFICULT" end
    if questLevel > ns.GrayLevel(level) then return "STANDARD" end
    return "TRIVIAL"
end

-- The same colours for a dungeon: red below its range, orange just below, yellow in its
-- lower half, green in the upper half, gray above it.
function ns.DungeonDifficulty(d, level)
    if level < d.min - 2 then return "IMPOSSIBLE" end
    if level < d.min then return "VERYDIFFICULT" end
    if level <= (d.min + d.max) / 2 then return "DIFFICULT" end
    if level <= d.max then return "STANDARD" end
    return "TRIVIAL"
end

-- A game icon for each dungeon, by key.
ns.ICONS = {
    RFC = "Spell_Fire_Fire", WC = "Spell_Nature_Sleep", DM = "INV_Pick_02", SFK = "Ability_Hunter_Pet_Wolf",
    BFD = "Spell_Frost_SummonWaterElemental", STOCKS = "INV_BannerPVP_02", GNOMER = "INV_Gizmo_02",
    RFK = "Ability_Hunter_Pet_Boar", SM = "Spell_Holy_HolyBolt", RFD = "Spell_Shadow_AnimateDead",
    ULDA = "INV_Misc_StoneTablet_05", ZF = "INV_Misc_Head_Troll_01", MARA = "Spell_Nature_ResistNature",
    ST = "INV_Misc_Head_Dragon_Green", BRD = "Spell_Fire_Volcano", BRS = "INV_Misc_Head_Dragon_Black",
    DIREMAUL = "INV_Crown_01", SCHOLO = "INV_Misc_Bone_HumanSkull_01", STRAT = "Spell_Shadow_RaiseDead",
    THANES = "INV_Misc_Head_Dwarf_01", LORDAERON = "Ability_Creature_Disease_02", EXCAVATION = "INV_Misc_Shovel_01",
    DALARAN = "Spell_Holy_MagicalSentry", DROWNED = "INV_Misc_Idol_03", KROLDOK = "INV_Misc_Head_Orc_01",
    ALCAZ = "INV_Misc_Bandana_03", BLACKMAW = "Ability_Druid_Maul", SHAPERS = "INV_Misc_Gem_Crystal_02",
}

function ns.Icon(key)
    return "Interface\\Icons\\" .. (ns.ICONS[key] or "INV_Misc_QuestionMark")
end

-- The game's own dungeon pictures: the Encounter Journal instance (its banner) and the file
-- name both the journal banner and the dungeon finder portrait use. WoW Forever's own dungeons
-- have none and keep their icon.
ns.ART = {
    RFC = { 226, "RagefireChasm" }, WC = { 240, "WailingCaverns" }, DM = { 63, "TheDeadmines", "Deadmines" },
    SFK = { 64, "ShadowfangKeep" }, BFD = { 227, "BlackfathomDeeps" },
    STOCKS = { 238, "TheStockade", "StormwindStockades" }, GNOMER = { 231, "Gnomeregan" },
    RFK = { 234, "RazorfenKraul" }, SM = { 316, "ScarletMonastery" }, RFD = { 233, "RazorfenDowns" },
    ULDA = { 239, "Uldaman" }, ZF = { 241, "ZulFarrak", "ZulFarak" }, MARA = { 232, "Maraudon" },
    ST = { 237, "SunkenTemple" }, BRD = { 228, "BlackrockDepths" }, BRS = { 229, "BlackrockSpire" },
    DIREMAUL = { 230, "DireMaul" }, SCHOLO = { 246, "Scholomance" }, STRAT = { 236, "Stratholme" },
}

-- WoW Forever's own dungeons have no journal picture: ours, drawn for the addon
-- (tools/dungeonprep/banners/, made into Banners/<KEY>.tga by tools/dungeonprep/banners.py).
ns.OWN_BANNERS = { THANES = true, LORDAERON = true, EXCAVATION = true, DALARAN = true, DROWNED = true,
                   KROLDOK = true, ALCAZ = true, BLACKMAW = true, SHAPERS = true }

-- The loading screen the game shows on the way into each dungeon: its file id in the client
-- (Map.LoadingScreenID, then LoadingScreens: the classic 4:3 screen, or for Forever's own
-- dungeons the 2992x1684 main image) and the height, 0 to 1, the band is centred on.
ns.LOADING = {
    RFC = { 131862, 0.53 }, WC = { 131882, 0.5 }, DM = { 131833, 0.49 }, SFK = { 131869, 0.55 },
    BFD = { 131823, 0.45 }, STOCKS = { 131870, 0.49 }, GNOMER = { 131841, 0.49 }, RFK = { 131865, 0.49 },
    SM = { 131852, 0.49 }, RFD = { 131864, 0.48 }, ULDA = { 131876, 0.47 }, ZF = { 131885, 0.57 },
    MARA = { 131850, 0.49 }, ST = { 131872, 0.49 }, BRD = { 131824, 0.49 }, BRS = { 131825, 0.46 },
    DIREMAUL = { 131835, 0.5 }, SCHOLO = { 131868, 0.51 }, STRAT = { 131871, 0.49 },
    ALCAZ = { 7963734, 0.5, true }, BLACKMAW = { 7963784, 0.5, true }, DALARAN = { 7963775, 0.5, true },
    EXCAVATION = { 7963777, 0.5, true }, KROLDOK = { 7963780, 0.5, true }, LORDAERON = { 7963782, 0.5, true },
    DROWNED = { 7963741, 0.5, true }, THANES = { 7963781, 0.5, true }, SHAPERS = { 7963783, 0.5, true },
}

-- A classic screen is a 4:3 picture in a square texture, painted between the logo band
-- (0.17) and the parchment (0.80); a Forever one shows its picture in rows 266-1418 of 1684.
local SCREEN = { classic = { 4 / 3, 0.17, 0.80 }, forever = { 2992 / 1684, 266 / 1684, 1418 / 1684 } }

-- Texture coordinates of a band `aspect` times wider than high across the whole screen.
function ns.LoadingCoords(key, aspect)
    local l = ns.LOADING[key]
    if not l then return nil end
    local s = SCREEN[l[3] and "forever" or "classic"]
    local h = math.min(s[1] / aspect, s[3] - s[2])
    local c = math.max(s[2] + h / 2, math.min(s[3] - h / 2, l[2]))
    return { 0, 1, c - h / 2, c + h / 2 }
end

local JOURNAL_TC = { 0, 0.68359375, 0.08, 0.62 }
local OWN_TC = { 0, 1, 0.1, 0.9 }

-- The dungeon's banner pictures for a band `aspect` times wider than high, best first, each
-- { file, texcoords }: the loading screen, the journal banner (a file id when the client has
-- the journal, else its path), then ours. The caller takes the first file that loads.
function ns.Banners(key, aspect)
    local list = {}
    local l = ns.LOADING[key]
    if l then list[#list + 1] = { l[1], ns.LoadingCoords(key, aspect or 2.6) } end
    local a = ns.ART[key]
    if a then
        local file = "Interface\\EncounterJournal\\UI-EJ-DUNGEONBUTTON-" .. a[2]
        if EJ_GetInstanceInfo then
            local ok, _, _, _, button = pcall(EJ_GetInstanceInfo, a[1])
            if ok and button and button ~= 0 and button ~= "" then file = button end
        end
        list[#list + 1] = { file, JOURNAL_TC }
    end
    if ns.OWN_BANNERS[key] then
        list[#list + 1] = { "Interface\\AddOns\\Gulli-DungeonPrep\\Banners\\" .. key, OWN_TC }
    end
    return list
end

-- The dungeon finder's round portrait files of a dungeon, best first (none for Forever's own).
function ns.Portraits(key)
    local a = ns.ART[key]
    if not a then return {} end
    local list = { "Interface\\LFGFrame\\LFGIcon-" .. a[2] }
    if a[3] then list[2] = "Interface\\LFGFrame\\LFGIcon-" .. a[3] end
    return list
end

-- Dungeons in level order: { key, areas, name, min, max, fits }.
function ns.Dungeons(level)
    local out = {}
    for _, d in ipairs(data().dungeons) do
        out[#out + 1] = { key = d[1], areas = d[2], en = d[3], min = d[4], max = d[5],
                          fits = level >= d[4] - 2 and level <= d[5],
                          entrance = d[6] and { area = d[6], x = d[7] or 0, y = d[8] or 0 } }
    end
    return out
end

-- The game's name of the dungeon; a Forever dungeon the client has no area for has a DG_ text.
function ns.DungeonName(d)
    return areaName(d.areas[1]) or rawget(L, "DG_" .. d.key) and L["DG_" .. d.key] or d.en
end

-- The dungeon for this level: of those whose range holds it, the one that starts highest.
function ns.Suggest(level)
    local best
    for _, d in ipairs(ns.Dungeons(level)) do
        if level >= d.min and level <= d.max and (not best or d.min >= best.min) then best = d end
    end
    return best or ns.Dungeons(level)[1]
end

-- The first earlier quest still missing: { id, name, who, area, x, y }, from the dungeon quests or D.pre.
local function missing(q)
    local D = data()
    local ids = {}
    for _, p in ipairs(q[8] or {}) do if not questDone(p) then ids[#ids + 1] = p end end
    if #(q[9] or {}) > 0 then
        local one = false
        for _, p in ipairs(q[9]) do if questDone(p) or onQuest(p) then one = true end end
        if not one then ids[#ids + 1] = q[9][1] end
    end
    for _, p in ipairs(ids) do
        local d = D.quest[p]
        if d then return { id = p, name = d[1], who = d[6], area = d[7], x = d[12] or 0, y = d[13] or 0 } end
        d = D.pre and D.pre[p]
        if d then return { id = p, name = d[1], who = d[3], area = d[4], x = d[5] or 0, y = d[6] or 0 } end
    end
    if ids[1] then return { id = ids[1] } end
end

local function matches(entry, text)
    if not text or text == "" then return true end
    text = text:lower()
    local function has(s) return s and s ~= "" and s:lower():find(text, 1, true) ~= nil end
    if has(entry.name) or has(entry.who) or has(entry.turnin and entry.turnin.who) then return true end
    for _, t in ipairs(entry.targets or {}) do if has(t) then return true end end
    return false
end

-- One dungeon quest as the window shows it.
local function entryOf(id, q)
    local D = data()
    local entry = { id = id, name = (Q.GetTitleForQuestID and Q.GetTitleForQuestID(id)) or q[1],
                    level = q[2], minLevel = q[3], who = q[6], area = q[7], side = q[11] or "",
                    x = q[12] or 0, y = q[13] or 0, step = q[18] or 0, steps = q[19] or 0,
                    reward = D.reward and D.reward[id], targets = D.target and D.target[id],
                    text = D.text and D.text[id] }
    if q[14] and q[14] ~= "" then
        entry.turnin = { who = q[14], area = q[15] or 0, zone = areaName(q[15]), x = q[16] or 0, y = q[17] or 0 }
    end
    return entry
end

-- Where a quest stands for this character: "done", "hidden", "log", "closed" (another quest
-- of its group was taken), "later" (with entry.why and entry.need) or "take".
local function stateOf(entry, q, level)
    local id = entry.id
    if questDone(id) then return "done" end
    if ns.Hidden(id) then return "hidden" end
    if onQuest(id) then return "log" end
    for _, other in ipairs(q[10] or {}) do if questDone(other) then return "closed" end end
    local pre = true
    for _, p in ipairs(q[8] or {}) do if not questDone(p) then pre = false end end
    if #(q[9] or {}) > 0 then
        local one = false
        for _, p in ipairs(q[9]) do if questDone(p) or onQuest(p) then one = true end end
        pre = pre and one
    end
    if not pre then
        entry.why = "WHY_EARLIER"
        entry.need = missing(q)
        return "later"
    elseif level < entry.minLevel then
        entry.why = "WHY_LEVEL"
        return "later"
    end
    return "take"
end

-- The levelling chains of a dungeon (D.main): quest id -> true, or nil when the data has none.
local mainSets = {}
function ns.MainSet(key)
    local D = data()
    local ids = D.main and D.main[key]
    if not ids or #ids == 0 then return nil end
    if not mainSets[key] then
        local set = {}
        for _, id in ipairs(ids) do set[id] = true end
        mainSets[key] = set
    end
    return mainSets[key]
end

-- The quests the window shows for a dungeon: only its levelling chains while mainOnly is on
-- and the data has them, else every quest that touches it.
function ns.ShownSet(key)
    if ns.Get("mainOnly") then return ns.MainSet(key) end
end

-- The quests of a dungeon for this character, one entry per chain: the quests of a chain show
-- as one card, named by its last step in the dungeon (`head`), whose state is the state of the
-- step to do now (the first of its dungeon steps that is not done). Lists: log (in the quest
-- log), take (can take now), later (level too low or an earlier quest missing), and a done
-- count of whole chains. A chain with a step the player hid goes to `hidden` instead;
-- `filter` is a text to find in the name, the quest givers or the mobs of any of its steps.
-- Only the levelling chains count while ns.ShownSet gives them; `more` is how many other
-- quests of the dungeon are for this character then.
local NOW = { log = 1, take = 2, later = 3 }
function ns.Quests(key, level, filter)
    local D = data()
    local out = { log = {}, take = {}, later = {}, hidden = {}, finished = {}, done = 0, more = 0 }
    local main, shown = ns.MainSet(key), ns.ShownSet(key)
    local mine, order = {}, {}
    for _, id in ipairs(D.byDungeon[key] or {}) do
        local q = D.quest[id]
        if q and forMe(q) and shown and not shown[id] then
            out.more = out.more + 1
        elseif q and forMe(q) and not mine[id] then
            local entry = entryOf(id, q)
            entry.main = main ~= nil and main[id] == true
            entry.state = stateOf(entry, q, level)
            mine[id] = entry
            order[#order + 1] = id
        end
    end
    -- The head of a quest: the last step of its chain that is a quest of this list (two
    -- quests that both lead to it, such as Testing the Wells and Murloc Gills, share it).
    local chainOf = function(id) return (D.chain and D.chain[id]) or { id } end
    local groups, heads = {}, {}
    for _, id in ipairs(order) do
        local chain, head = chainOf(id), id
        for i = #chain, 1, -1 do
            if mine[chain[i]] then head = chain[i] break end
        end
        if not groups[head] then groups[head] = {}; heads[#heads + 1] = head end
        local g = groups[head]
        g[#g + 1] = id
    end
    for _, head in ipairs(heads) do
        local ids, chain = groups[head], chainOf(head)
        local pos = function(id) for i, c in ipairs(chain) do if c == id then return i end end return 0 end
        table.sort(ids, function(a, b) return pos(a) < pos(b) end)
        -- A step before a done one counts as done too (the game may not flag every old step).
        local last = 0
        for i, id in ipairs(ids) do if mine[id].state == "done" then last = i end end
        -- The step to do now: one in the log first, then one to take, then one for later.
        local cur, hidden, found = nil, nil, false
        for i, id in ipairs(ids) do
            local e = mine[id]
            if e.state == "hidden" then hidden = hidden or e end
            if i > last and NOW[e.state] and (not cur or NOW[e.state] < NOW[cur.state]) then cur = e end
            if filter and filter ~= "" and matches(e, filter) then found = true end
        end
        local h = mine[head]
        local entry = hidden or cur or h
        if #ids > 1 then
            entry.head = { id = head, name = h.name, level = h.level }
            entry.members = ids
        end
        if not filter or filter == "" then found = true end
        local state = hidden and "hidden" or (cur and cur.state) or h.state
        if state == "done" then
            out.done = out.done + 1
            if found then out.finished[#out.finished + 1] = entry end
        elseif state ~= "closed" and found then
            local list = out[state]
            list[#list + 1] = entry
        end
    end
    local byLevel = function(a, b) if a.level ~= b.level then return a.level < b.level end return a.name < b.name end
    table.sort(out.log, byLevel); table.sort(out.take, byLevel); table.sort(out.later, byLevel)
    table.sort(out.hidden, byLevel); table.sort(out.finished, byLevel)
    return out
end

-- How many quests of a dungeon are in the log, to take, for later and done (for the list
-- of dungeons and the dungeon's header).
function ns.Counts(key, level)
    local q = ns.Quests(key, level)
    return { log = #q.log, take = #q.take, later = #q.later, done = q.done }
end

-- One dungeon quest with everything its page shows, or nil: the list entry plus `state`
-- (see stateOf), `chain` (ns.Chain) and `objectives` (ns.Objectives).
function ns.Quest(id, level)
    local q = data().quest[id]
    if not q then return nil end
    local entry = entryOf(id, q)
    entry.state = stateOf(entry, q, level or UnitLevel("player") or 1)
    entry.chain = ns.Chain(id)
    entry.objectives = ns.Objectives(entry)
    return entry
end

-- What of a dungeon quest happens inside the dungeon (D.inside): { take, work, turnin }.
-- Only a hint: where the data cannot tell, nothing is set.
function ns.Inside(key, id)
    local D = data()
    local f = (key and D.inside and D.inside[key] and D.inside[key][id]) or ""
    return { take = f:find("t", 1, true) ~= nil, work = f:find("d", 1, true) ~= nil,
             turnin = f:find("h", 1, true) ~= nil }
end

-- The way of a quest (ns.Quest) as its page shows it: taking it, its work, handing it in.
-- { kind = take|work|turnin, state = done|now|wait, inside (in the dungeon `key`), and for
-- the two ends who, area, x, y }.
function ns.Stages(q, key)
    local inside = ns.Inside(key, q.id)
    local done, log = q.state == "done", q.state == "log"
    local ready = log and Q.IsComplete ~= nil and Q.IsComplete(q.id) == true
    local function st(isDone, now) return (isDone and "done") or (now and "now") or "wait" end
    local t = q.turnin or {}
    return {
        { kind = "take", state = st(done or log, q.state == "take"), inside = inside.take,
          who = q.who or "", area = q.area or 0, x = q.x or 0, y = q.y or 0 },
        { kind = "work", state = st(done or ready, log), inside = inside.work },
        { kind = "turnin", state = st(done, ready), inside = inside.turnin,
          who = t.who or "", area = t.area or 0, x = t.x or 0, y = t.y or 0 },
    }
end

-- The whole chain a quest is in, first step first: { id, n, name, level, who, area, x, y,
-- done, active, this, missing, dungeon }. `missing` marks the first step before this quest
-- that is neither done nor in the log.
function ns.Chain(id)
    local D = data()
    local out = {}
    for i, c in ipairs((D.chain and D.chain[id]) or {}) do
        local s = { id = c, n = i, this = c == id, x = 0, y = 0, area = 0, who = "" }
        local q, p = D.quest[c], D.pre and D.pre[c]
        if q then
            s.name, s.level, s.who, s.area, s.x, s.y, s.dungeon = q[1], q[2], q[6], q[7], q[12] or 0, q[13] or 0, true
        elseif p then
            s.name, s.level, s.who, s.area, s.x, s.y = p[1], p[2], p[3], p[4], p[5] or 0, p[6] or 0
        end
        s.name = (Q.GetTitleForQuestID and Q.GetTitleForQuestID(c)) or s.name or ("#" .. c)
        s.done, s.active = questDone(c), onQuest(c)
        out[#out + 1] = s
    end
    for _, s in ipairs(out) do
        if s.this then break end
        if not s.done and not s.active then s.missing = true break end
    end
    return out
end

-- The objective lines: the game's own (with progress) while the quest is in the log, else
-- the English text of the data. { text, done }.
function ns.Objectives(entry)
    local out = {}
    if onQuest(entry.id) and Q.GetQuestObjectives then
        for _, o in ipairs(Q.GetQuestObjectives(entry.id) or {}) do
            if type(o.text) == "string" and o.text ~= "" then out[#out + 1] = { text = o.text, done = o.finished == true } end
        end
    end
    if #out == 0 and entry.text and entry.text ~= "" then out[1] = { text = entry.text } end
    return out
end

-- Whether a quest of the log is on the objective tracker, and a switch for it.
function ns.Tracked(id)
    if Q.GetQuestWatchType then return Q.GetQuestWatchType(id) ~= nil end
    return false
end

function ns.Track(id)
    if not onQuest(id) then return false end
    if ns.Tracked(id) then
        if Q.RemoveQuestWatch then Q.RemoveQuestWatch(id) end
    elseif Q.AddQuestWatch then
        Q.AddQuestWatch(id)
    end
    if ns.Refresh then ns.Refresh() end
    return ns.Tracked(id)
end

-- The tracker's rows for a dungeon, at most ns.TRACK_MAX, one per chain (ns.Quests): ready to
-- hand in, the rest of the log with their objectives, the ones to take, then chains that wait
-- for an earlier step. { id (the step to do now), key (the chain's head), name (the head's),
-- level, state = ready|log|take|chain, lines = { { text, done } }, steps (ns.Chain of the step,
-- for a row opened by a click) or nil, pin = { who, area, x, y } or nil, inside = true when
-- what the row asks for now (taking it, its work, handing it in) happens in the dungeon }, then
-- how many are ready and how many there are. A chain's first line says which step it is at.
ns.TRACK_MAX = 8
local TRACK_ORDER = { ready = 1, log = 2, take = 3, chain = 4 }
function ns.TrackerItems(key, level)
    local q = ns.Quests(key, level)
    local all, ready = {}, 0
    local function pinOf(who, area, x, y)
        if who and who ~= "" and area and area > 0 and x and (x > 0 or y > 0) then
            return { who = who, area = area, x = x, y = y }
        end
    end
    for _, e in ipairs(q.log) do
        local it = { id = e.id, name = e.name, level = e.level, state = "log", lines = {}, entry = e }
        local t = e.turnin
        local ins = ns.Inside(key, e.id)
        it.inside = ins.work or nil
        if Q.IsComplete and Q.IsComplete(e.id) then
            it.state, ready = "ready", ready + 1
            it.inside = ins.turnin or nil
            it.lines[1] = { text = (t and t.who ~= "") and L.TR_READY_TO:format(t.who) or L.TR_READY, done = true }
            if t then it.pin = pinOf(t.who, t.area, t.x, t.y) end
        else
            for i, o in ipairs(ns.Objectives(e)) do
                if i > 3 then break end
                it.lines[#it.lines + 1] = { text = o.text, done = o.done }
            end
        end
        all[#all + 1] = it
    end
    for _, e in ipairs(q.take) do
        local where = ns.Where(e)
        all[#all + 1] = { id = e.id, name = e.name, level = e.level, state = "take",
                          lines = { { text = where ~= "" and L.TR_TAKE:format(where) or L.Q_TAKE } },
                          pin = pinOf(e.who, e.area, e.x, e.y), entry = e,
                          inside = ns.Inside(key, e.id).take or nil }
    end
    for _, e in ipairs(q.later) do
        if e.why == "WHY_EARLIER" and e.need and e.need.name then
            local n = e.need
            all[#all + 1] = { id = e.id, name = e.name, level = e.level, state = "chain",
                              lines = { { text = "» " .. ns.NeedText(n) } }, pin = pinOf(n.who, n.area, n.x, n.y),
                              entry = e }
        end
    end
    local total = #all
    for _, it in ipairs(all) do
        local e = it.entry
        it.entry = nil
        it.key = e.head and e.head.id or e.id
        if e.head and e.head.id ~= e.id then it.name = e.head.name end
        local chain = ns.Chain(e.id)
        if #chain > 1 then
            it.steps = chain
            local at
            for _, st in ipairs(chain) do if st.this then at = st.n end end
            if at then
                table.insert(it.lines, 1, { text = L.STEP:format(at, #chain) .. ":  " .. e.name, step = true })
            end
        end
    end
    table.sort(all, function(a, b)
        if a.state ~= b.state then return TRACK_ORDER[a.state] < TRACK_ORDER[b.state] end
        if a.level ~= b.level then return a.level < b.level end
        return a.name < b.name
    end)
    while #all > ns.TRACK_MAX do all[#all] = nil end
    return all, ready, total
end

-- Where an earlier quest starts, as one line ("Name (who, zone)"), or just its name.
function ns.NeedText(need)
    if not need then return L.WHY_EARLIER end
    if not need.name then return L.WHY_EARLIER end
    local where = ns.Where({ who = need.who or "", area = need.area or 0 })
    return where ~= "" and L.NEEDS_AT:format(need.name, where) or L.NEEDS:format(need.name)
end

-- Armour each class wears best (plate and mail from level 40) and the weapon subclasses it
-- can learn. Item class 4 is armour, 2 weapons; armour subclass 0 is rings, necks, trinkets.
local ARMOR, WEAPON = 4, 2
local BEST_ARMOR = {
    WARRIOR = { 3, 4 }, PALADIN = { 3, 4 }, HUNTER = { 2, 3 }, SHAMAN = { 2, 3 }, ROGUE = { 2, 2 },
    DRUID = { 2, 2 }, PRIEST = { 1, 1 }, MAGE = { 1, 1 }, WARLOCK = { 1, 1 },
}
local SHIELD = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local WEAPONS = {
    WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }, PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
    HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }, ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
    PRIEST = { 4, 10, 15, 19 }, SHAMAN = { 0, 1, 4, 5, 10, 13, 15 }, MAGE = { 7, 10, 15, 19 },
    WARLOCK = { 7, 10, 15, 19 }, DRUID = { 4, 5, 10, 13, 15 },
}

-- Whether an item is meant for this class: its best armour, any cloak or jewellery, a
-- shield it can carry, or a weapon it can learn. Anything else (a potion, a bag) fits too.
function ns.Fits(classID, subclassID, equipLoc, class, level)
    if classID == ARMOR then
        if subclassID == 0 or equipLoc == "INVTYPE_CLOAK" then return true end
        if subclassID == 6 then return SHIELD[class] == true end
        local best = BEST_ARMOR[class]
        if not best then return true end
        return subclassID == best[(level or 1) >= 40 and 2 or 1]
    elseif classID == WEAPON then
        for _, s in ipairs(WEAPONS[class] or {}) do if s == subclassID then return true end end
        return WEAPONS[class] == nil
    end
    return true
end

-- The gear slots an equip location fills, to compare with what is worn.
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_SHIELD = { 17 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
}

-- The lowest item level worn in the slots, 0 for an empty one.
local function wornLevel(slots)
    local low
    for _, slot in ipairs(slots) do
        local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
        local ilvl = 0
        if link then ilvl = select(4, itemInfo(link)) or 0 end
        low = low and math.min(low, ilvl) or ilvl
    end
    return low or 0
end

-- Whether an item is for this class, and whether it beats what is worn there (a higher item
-- level). Both nil until the game has the item.
function ns.ItemFor(id)
    local name, _, _, ilvl, equipLoc, _, classID, subclassID = itemInfo(id)
    if not name then return nil, nil end
    local _, class = UnitClass("player")
    local fits = ns.Fits(classID, subclassID, equipLoc, class, UnitLevel("player") or 1)
    local slots = SLOTS[equipLoc or ""]
    return fits, fits and slots ~= nil and (ilvl or 0) > wornLevel(slots)
end

-- A quest's reward items: { id, name, link, icon, quality, fits, better }. `better` is an item
-- for this class with a higher item level than what is worn there. Names come once the game
-- has the item; until then only the id.
function ns.Rewards(entry)
    local out = {}
    for _, id in ipairs(entry.reward or {}) do
        local name, link, quality, _, _, icon = itemInfo(id)
        local r = { id = id, name = name, link = link, icon = icon, quality = quality }
        if name then r.fits, r.better = ns.ItemFor(id) end
        out[#out + 1] = r
    end
    return out
end

-- Experience and money of a quest in the log, when the game tells them.
function ns.LogReward(id)
    local xp = GetQuestLogRewardXP and GetQuestLogRewardXP(id)
    local money = GetQuestLogRewardMoney and GetQuestLogRewardMoney(id)
    return type(xp) == "number" and xp or 0, type(money) == "number" and money or 0
end

-- The experience a quest gives this character, and whether the game itself said so (a quest
-- in the log). Else it comes from the data (D.xp, at the quest's own level), cut like the
-- game cuts it for a character above the quest; 0 when nothing is known or at the top level.
ns.MAX_LEVEL = 60
function ns.QuestXP(id, level)
    local xp = ns.LogReward(id)
    if onQuest(id) and xp > 0 then return xp, true end
    local D = data()
    local base, q = D.xp and D.xp[id], D.quest[id]
    level = level or UnitLevel("player") or 1
    if not base or not q or level >= ns.MAX_LEVEL then return 0, false end
    local factor = math.max(1, math.min(10, 2 * (q[2] - level) + 20))
    xp = base * factor / 10
    local step, half = 50, 25
    if xp <= 100 then step, half = 5, 2 elseif xp <= 500 then step, half = 10, 5 elseif xp <= 1000 then step, half = 25, 12 end
    return step * math.floor((xp + half) / step), false
end

-- The same as a text in the experience colour: "5250 experience", with "~" when it is the data's.
function ns.XPText(id, level)
    local xp, exact = ns.QuestXP(id, level)
    if xp <= 0 then return nil end
    return ns.Skin.Hex(ns.Skin.XP) .. (exact and "" or "~") .. L.TT_XP:format(xp) .. "|r"
end

-- Group members (names) who have this quest too.
function ns.GroupOn(id)
    local out = {}
    if not (Q.IsUnitOnQuest and IsInGroup and IsInGroup()) then return out end
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists and UnitExists(unit) and Q.IsUnitOnQuest(unit, id) then
            local name = UnitName(unit)
            if not (issecretvalue and issecretvalue(name)) then out[#out + 1] = name end
        end
    end
    return out
end

-- Shares a quest of the log with the group. Returns true when it was offered.
function ns.Share(id)
    if not (IsInGroup and IsInGroup() and QuestLogPushQuest) then return false end
    if Q.SetSelectedQuest then
        Q.SetSelectedQuest(id)
    elseif SelectQuestLogEntry and Q.GetLogIndexForQuestID then
        SelectQuestLogEntry(Q.GetLogIndexForQuestID(id))
    end
    QuestLogPushQuest()
    print("|cff9ad0ffGulli-DungeonPrep|r: " .. L.SHARED)
    return true
end

function ns.Where(q)
    local zone = areaName(q.area)
    if q.who == "" then return zone or "" end
    return zone and L.WHERE:format(q.who, zone) or q.who
end

-- Where the player is: { zone (the zone map's name), x, y (map percent), kalimdor }, from
-- the world map; fields are nil where the game does not tell (inside an instance).
local MAP = C_Map or {}
local CONTINENT, ZONE, KALIMDOR, EASTERN = 2, 3, 1414, 1415
function ns.Here()
    local here = {}
    local id = MAP.GetBestMapForUnit and MAP.GetBestMapForUnit("player")
    local zoneMap
    while id do
        local info = MAP.GetMapInfo and MAP.GetMapInfo(id)
        if not info then break end
        if info.mapType == ZONE and not zoneMap then zoneMap, here.zone = id, info.name end
        if info.mapType == CONTINENT or id == KALIMDOR or id == EASTERN then
            here.kalimdor = id == KALIMDOR
            break
        end
        id = info.parentMapID ~= 0 and info.parentMapID or nil
    end
    local pos = zoneMap and MAP.GetPlayerMapPosition and MAP.GetPlayerMapPosition(zoneMap, "player")
    if pos then
        local x, y = pos:GetXY()
        if x and x > 0 then here.x, here.y = x * 100, y * 100 end
    end
    return here
end

local function onKalimdor(area)
    for _, a in ipairs(data().kalimdor or {}) do if a == area then return true end end
    return false
end

local function dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

-- The quests to take as stops on one way to the dungeon: { who, area, zone, x, y, quests,
-- here, inside }. Stops in the player's zone come first, nearest first from where the
-- player stands; then other zones on the same continent, then the other continent, each
-- zone with the most quests first. Quests started by an item or inside the dungeon go last.
function ns.Route(take, here, dungeon)
    here = here or {}
    local stops, byKey, inside = {}, {}, nil
    for _, q in ipairs(take) do
        if q.area == 0 or (q.x == 0 and q.y == 0) then
            inside = inside or { inside = true, quests = {} }
            inside.quests[#inside.quests + 1] = q
        else
            local key = q.who .. "@" .. q.area
            local s = byKey[key]
            if not s then
                s = { who = q.who, area = q.area, zone = areaName(q.area), x = q.x, y = q.y, quests = {},
                      kalimdor = onKalimdor(q.area) }
                s.here = here.zone ~= nil and s.zone == here.zone
                byKey[key] = s
                stops[#stops + 1] = s
            end
            s.quests[#s.quests + 1] = q
        end
    end
    local zones, byArea = {}, {}
    for _, s in ipairs(stops) do
        local z = byArea[s.area]
        if not z then
            z = { stops = {}, count = 0, here = s.here, area = s.area,
                  tier = s.here and 0 or ((here.kalimdor == nil or s.kalimdor == here.kalimdor) and 1 or 2) }
            byArea[s.area] = z
            zones[#zones + 1] = z
        end
        z.stops[#z.stops + 1] = s
        z.count = z.count + #s.quests
    end
    table.sort(zones, function(a, b)
        if a.tier ~= b.tier then return a.tier < b.tier end
        if a.count ~= b.count then return a.count > b.count end
        return a.area < b.area
    end)
    local out = {}
    for _, z in ipairs(zones) do
        local left = z.stops
        table.sort(left, function(a, b)
            if #a.quests ~= #b.quests then return #a.quests > #b.quests end
            return a.who < b.who
        end)
        local px, py
        if z.here and here.x then px, py = here.x, here.y end
        while #left > 0 do
            local best = 1
            if px then
                for i = 2, #left do
                    if dist(px, py, left[i].x, left[i].y) < dist(px, py, left[best].x, left[best].y) then best = i end
                end
            end
            local s = table.remove(left, best)
            out[#out + 1] = s
            px, py = s.x, s.y
        end
    end
    local e = dungeon and dungeon.entrance
    if e and e.area > 0 then
        out[#out + 1] = { entrance = true, who = ns.DungeonName(dungeon), area = e.area, zone = areaName(e.area),
                          x = e.x, y = e.y, quests = {} }
    end
    if inside then out[#out + 1] = inside end
    return out
end

-- A map pin on a stop, through the world map's own waypoint. Returns true when it is set.
-- With `open`, the world map opens on the pin's zone too (out of combat only).
local mapOfZone
function ns.SetPin(stop, open)
    if not (stop.zone and MAP.SetUserWaypoint and UiMapPoint and MAP.GetMapChildrenInfo) then return false end
    if not mapOfZone then
        mapOfZone = {}
        for _, c in ipairs({ KALIMDOR, EASTERN }) do
            for _, m in ipairs(MAP.GetMapChildrenInfo(c, nil, true) or {}) do
                if m.name and not mapOfZone[m.name] then mapOfZone[m.name] = m.mapID end
            end
        end
    end
    local id = mapOfZone[stop.zone]
    if not id then return false end
    MAP.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(id, stop.x / 100, stop.y / 100))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    -- TomTom's arrow too, when it is installed (never needed).
    if ns.Get("tomtom") and TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(id, stop.x / 100, stop.y / 100, { title = stop.who, from = "Gulli-DungeonPrep" })
    end
    if open then ns.OpenMap(id) end
    print("|cff9ad0ffGulli-DungeonPrep|r: " .. L.PIN_SET:format(stop.who))
    return true
end

-- Opens the world map on a map id. The map can be taken out of combat only.
function ns.OpenMap(id)
    if not id or (InCombatLockdown and InCombatLockdown()) then return false end
    if OpenWorldMap then
        OpenWorldMap(id)
        return true
    elseif WorldMapFrame and WorldMapFrame.SetMapID and ShowUIPanel then
        ShowUIPanel(WorldMapFrame)
        WorldMapFrame:SetMapID(id)
        return true
    end
    return false
end

-- Keys and items that open a dungeon or a part of it.
ns.KEYS = {
    SM = { 7146 },       -- The Scarlet Key
    GNOMER = { 6893 },   -- Workshop Key
    ZF = { 9240 },       -- Mallet of Zul'Farrak
    BRD = { 11000 },     -- Shadowforge Key
    BRS = { 12344 },     -- Seal of Ascension
    DIREMAUL = { 18249 }, -- Crescent Key
    SCHOLO = { 13704 },  -- Skeleton Key
    STRAT = { 12382 },   -- Key to the City
}

local function nameOf(id)
    return itemInfo(id) or ("item:" .. id)
end

-- The keys of a dungeon and whether they are in the bags: { id, name, have }.
function ns.KeyState(dungeonKey)
    local out = {}
    for _, id in ipairs(ns.KEYS[dungeonKey] or {}) do
        out[#out + 1] = { id = id, name = nameOf(id), have = itemCount(id) > 0 }
    end
    return out
end

-- Finished dungeon quests in the log: { entry with turnin }, for the reminder after a run.
function ns.HandIns()
    local D = data()
    local out, seen = {}, {}
    for _, ids in pairs(D.byDungeon) do
        for _, id in ipairs(ids) do
            local q = D.quest[id]
            if q and not seen[id] and onQuest(id) and Q.IsComplete and Q.IsComplete(id) then
                seen[id] = true
                out[#out + 1] = { id = id, name = (Q.GetTitleForQuestID and Q.GetTitleForQuestID(id)) or q[1],
                                  turnin = { who = q[14] or "", area = q[15] or 0, zone = areaName(q[15]),
                                             x = q[16] or 0, y = q[17] or 0 } }
            end
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

-- Leaving a dungeon: one line per finished quest with where to hand it in, a pin on the first.
function ns.Remind()
    if not ns.Get("remind") then return end
    local list = ns.HandIns()
    if #list == 0 then return end
    for _, q in ipairs(list) do
        local where = q.turnin.who ~= "" and ns.Where({ who = q.turnin.who, area = q.turnin.area }) or ""
        print("|cff9ad0ffGulli-DungeonPrep|r: " .. L.HAND_IN:format(q.name, where))
    end
    if GulliToolkit and GulliToolkit.Notify then
        GulliToolkit.Notify("DungeonPrep", L.HAND_IN_N:format(#list))
    end
    local first = list[1].turnin
    if first.who ~= "" and first.x > 0 then ns.SetPin(first) end
end

local wasInside = false
local function checkLeave()
    local inside, kind = false, nil
    if IsInInstance then inside, kind = IsInInstance() end
    inside = inside and (kind == "party" or kind == "raid")
    if wasInside and not inside then ns.Remind() end
    wasInside = inside and true or false
end
ns.CheckLeave = checkLeave

-- One line for the hub's home page: the dungeon for this level and its quests.
function ns.Summary()
    local level = UnitLevel("player") or 1
    local d = ns.Suggest(level)
    if not d then return nil end
    local q = ns.Quests(d.key, level)
    if #q.log + #q.take == 0 then return nil end
    -- the third value is for the hub's tile: the quests to take as its number, else those in the log
    local stat = #q.take > 0 and { value = #q.take, tone = "warn" } or { value = #q.log }
    return L.SUMMARY:format(ns.DungeonName(d), #q.log, #q.take), ns.Icon(d.key), stat
end

ns.ITEM_REFRESH = 0.5
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliDungeonPrepDB = GulliDungeonPrepDB or {}
        ns.db = GulliDungeonPrepDB
        ns.db.hidden = ns.db.hidden or {}
        -- Frames on the screen start hidden: older saves hide the tracker once. The hub's
        -- Unlock mode places it, so it has no lock of its own.
        if not ns.db.hudHidden then ns.db.tracker, ns.db.hudHidden = nil, true end
        ns.db.trackerLocked = nil
        self:RegisterEvent("QUEST_LOG_UPDATE")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        self:RegisterEvent("BAG_UPDATE_DELAYED")
        self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        self:RegisterEvent("LOOT_READY")
        self:RegisterEvent("QUEST_ACCEPTED")
        self:RegisterEvent("QUEST_TURNED_IN")
        return
    end
    if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        checkLeave()
        if ns.CheckEnter then ns.CheckEnter() end
    end
    if event == "LOOT_READY" then
        if ns.OnLoot then ns.OnLoot() end
        return
    end
    if (event == "QUEST_ACCEPTED" or event == "QUEST_TURNED_IN") and ns.guide and ns.StepGuide then ns.StepGuide() end
    -- A big dungeon asks for hundreds of loot items at once and each answer is an event:
    -- one refresh for the whole burst, not one per item.
    if event == "GET_ITEM_INFO_RECEIVED" and C_Timer and C_Timer.After then
        if not ns.refreshWaiting then
            ns.refreshWaiting = true
            C_Timer.After(ns.ITEM_REFRESH, function()
                ns.refreshWaiting = false
                if ns.Refresh then ns.Refresh() end
            end)
        end
        return
    end
    if ns.Refresh then ns.Refresh() end
    if ns.RefreshTracker then ns.RefreshTracker() end
end)

SLASH_GULLIDUNGEONPREP1 = "/gdj"
SLASH_GULLIDUNGEONPREP2 = "/gdp"
SLASH_GULLIDUNGEONPREP3 = "/gullidungeonjournal"
SlashCmdList.GULLIDUNGEONPREP = function(msg)
    msg = strtrim(msg or ""):upper()
    for _, d in ipairs(ns.Dungeons(UnitLevel("player") or 1)) do
        if d.key == msg then ns.selected, ns.openQuest, ns.home = d.key, nil, false end
    end
    ns.Toggle()
end

function GulliDungeonPrep_Toggle() ns.Toggle() end

-- For other addons (Gulli Tooltip): where an item drops, { key, boss, pct }, the game's name of
-- a dungeon by its key, and whether an item is on the wish list.
GulliDungeonJournal = {
    DropsOf = function(item) return ns.DropsOf and ns.DropsOf(item) or {} end,
    Name = function(key)
        for _, d in ipairs(ns.Dungeons(1)) do
            if d.key == key then return ns.DungeonName(d) end
        end
    end,
    Wished = function(item) return ns.Wished ~= nil and ns.Wished(item) end,
}

-- The game icon of each switch, in the window and in the hub.
ns.OPT_ICON = {
    remind = "Interface\\Icons\\INV_Letter_15", keys = "Interface\\Icons\\INV_Misc_Key_04",
    tomtom = "Interface\\Icons\\INV_Misc_Map_01", hideLater = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    warnEnter = "Interface\\Icons\\Ability_Warrior_BattleShout", wishAlert = "Interface\\Icons\\INV_Misc_Gem_Pearl_04",
    learn = "Interface\\Icons\\INV_Misc_Book_09",
}

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "DungeonPrep",
        icon = "Interface\\AddOns\\Gulli-DungeonPrep\\icon",
        slash = "/gdj",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        summary = function() return ns.Summary() end,
        move = function(on) if ns.MoveTracker then ns.MoveTracker(on) end end,
        frames = { { key = "tracker", icon = "Interface\\Icons\\INV_Misc_Map_02",
                     get = function() return ns.db ~= nil and ns.db.tracker ~= nil end,
                     set = function(on) if ns.SetTrackerShown then ns.SetTrackerShown(on) end end,
                     frame = function() return ns.TrackerFrame and ns.TrackerFrame() end } },
        reset = function() ns.Reset() end,
        options = {
            { label = L.OPT_REMIND, tip = L.OPT_REMIND_D, icon = ns.OPT_ICON.remind,
              get = function() return ns.Get("remind") end, set = function(v) ns.Set("remind", v) end },
            { label = L.OPT_KEYS, tip = L.OPT_KEYS_D, icon = ns.OPT_ICON.keys,
              get = function() return ns.Get("keys") end, set = function(v) ns.Set("keys", v) end },
            { label = L.OPT_ENTER, tip = L.OPT_ENTER_D, icon = ns.OPT_ICON.warnEnter,
              get = function() return ns.Get("warnEnter") end, set = function(v) ns.Set("warnEnter", v) end },
            { label = L.OPT_WISH, tip = L.OPT_WISH_D, icon = ns.OPT_ICON.wishAlert,
              get = function() return ns.Get("wishAlert") end, set = function(v) ns.Set("wishAlert", v) end },
            { label = L.OPT_TOMTOM, tip = L.OPT_TOMTOM_D, icon = ns.OPT_ICON.tomtom,
              get = function() return ns.Get("tomtom") end, set = function(v) ns.Set("tomtom", v) end },
        },
    })
end

-- A map pin on someone the data places on a zone map (a quest giver, a turn-in, a chain step).
-- Returns false when the spot is not on an outdoor map (inside a dungeon, an item).
-- The raid mark a quest giver gets when a pin button targets them (3, the diamond).
ns.MARK = 3

-- After a pin button's secure click targeted who: marks the target when it is them. The game
-- may hand back a secret name; then nothing is marked. A mark the target already has stays
-- (setting the same one again would take it off).
function ns.MarkTarget(who)
    if not who or who == "" or not (UnitExists and UnitExists("target")) then return false end
    local name = UnitName("target")
    if issecretvalue and issecretvalue(name) then return false end
    if name ~= who then return false end
    if GetRaidTargetIndex and GetRaidTargetIndex("target") == ns.MARK then return true end
    if SetRaidTarget then SetRaidTarget("target", ns.MARK) end
    return true
end

-- A pin on a dungeon's way in, with the map open on it; with `probe` it only says whether
-- the dungeon has one.
function ns.PinEntrance(key, probe)
    for _, d in ipairs(ns.Dungeons(UnitLevel("player") or 1)) do
        local e = d.key == key and d.entrance
        if e and e.area > 0 then
            if probe then return true end
            return ns.SetPin({ who = ns.DungeonName(d), zone = areaName(e.area), x = e.x, y = e.y }, true)
        end
    end
    return false
end

function ns.PinAt(who, area, x, y, open)
    if not area or area == 0 or not x or (x == 0 and y == 0) then return false end
    return ns.SetPin({ who = who ~= "" and who or "?", zone = areaName(area), x = x, y = y }, open)
end
