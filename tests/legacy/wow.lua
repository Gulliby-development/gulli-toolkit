-- A fake WoW client for the Gulli-Legacy tests: the shared basics plus achievements, Legacy points and skills.
local W = {}

local function stub()
    return setmetatable({}, { __index = function(t, k)
        if k == "GetWidth" then return function() return 400 end end
        if k == "GetHeight" then return function() return 300 end end
        if k == "GetStringWidth" or k == "GetValue" then return function() return 0 end end
        if k == "IsShown" then return function() return rawget(t, "_shown") == true end end
        if k == "Show" then return function() rawset(t, "_shown", true) end end
        if k == "Hide" then return function() rawset(t, "_shown", false) end end
        if k == "SetShown" then return function(_, v) rawset(t, "_shown", v and true or false) end end
        if k == "IsEnabled" then return function() return rawget(t, "_enabled") ~= false end end
        if k == "SetEnabled" then return function(_, v) rawset(t, "_enabled", v and true or false) end end
        if k == "GetText" then return function() return rawget(t, "_text") end end
        if k == "SetText" then return function(_, v) rawset(t, "_text", v) end end
        if k == "GetNumber" then return function() return tonumber(rawget(t, "_text")) or 0 end end
        if k == "SetScript" then return function(_, n, f) rawset(t, "_" .. n, f) end end
        if k == "HookScript" then return function(_, n, f) rawset(t, "_" .. n, f) end end
        if k == "GetScript" then return function(_, n) return rawget(t, "_" .. n) end end
        if k == "RegisterEvent" then return function(_, e) rawget(t, "_events")[e] = true end end
        if k == "UnregisterEvent" then return function(_, e) rawget(t, "_events")[e] = nil end end
        return function() return stub() end
    end })
end
W.stub = stub

-- The globals every Gulli module uses. spec: locale, level, class, now, combat.
function W.Base(spec)
    W.frames, W.printed, W.timers, W.sent = {}, {}, {}, {}
    W.now = spec.now or 100000
    W.combat = spec.combat or false
    W.level = spec.level or 60
    GetLocale = function() return spec.locale or "enUS" end
    UnitName = function(u) if u == "player" then return spec.name or "Tester" end end
    UnitClass = function() return "Priest", spec.class or "PRIEST" end
    UnitLevel = function(u) if u == "player" then return W.level end return 60 end
    UnitRace = function() return "Human", spec.race or "Human" end
    UnitFactionGroup = function() return spec.faction or "Alliance" end
    GetRealmName = function() return "Realm" end
    InCombatLockdown = function() return W.combat end
    time = function() return W.now end
    GetTime = function() return W.now end
    SlashCmdList = {}
    CreateFrame = function()
        local f = stub()
        rawset(f, "_events", {})
        W.frames[#W.frames + 1] = f
        return f
    end
    UIParent, GameTooltip, UISpecialFrames = stub(), stub(), {}
    tinsert, tremove, wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end
    strtrim = function(s) return (s or ""):match("^%s*(.-)%s*$") end
    C_Timer = { After = function(_, fn) W.timers[#W.timers + 1] = fn end,
                NewTicker = function(_, fn) W.timers[#W.timers + 1] = fn; return stub() end }
    hooksecurefunc = function() end
    PlaySound = function() end
    SOUNDKIT = {}
    RAID_CLASS_COLORS = nil
    issecretvalue = nil
    ChatFrame_OpenChat = function() end
    print = function(...) W.printed[#W.printed + 1] = table.concat({ ... }, " ") end
    GulliToolkit = nil
end

-- Runs the addon files in TOC order with one shared addon table, then ADDON_LOADED.
function W.Load(addon, files)
    local ns = {}
    for _, f in ipairs(files) do
        assert(loadfile(addon .. "/" .. f))(addon, ns)
    end
    W.Fire("ADDON_LOADED", addon)
    return ns
end

-- Sends an event to every frame that registered it (ADDON_LOADED always).
function W.Fire(event, ...)
    for _, f in ipairs(W.frames) do
        local on = rawget(f, "_OnEvent")
        if on and (event == "ADDON_LOADED" or rawget(f, "_events")[event]) then on(f, event, ...) end
    end
end

function W.RunTimers()
    local t = W.timers
    W.timers = {}
    for _, fn in ipairs(t) do fn() end
end

-- Every language has every English key, with the same placeholders, and no extra key.
function W.CheckLocales(ns)
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
end

-- A tiny test runner: W.test(name, fn), W.eq(a, b, what), W.finish().
local failed, count = 0, 0
function W.test(name, fn)
    count = count + 1
    local ok, err = pcall(fn)
    if ok then io.write("ok   ", name, "\n")
    else failed = failed + 1; io.write("FAIL ", name, "\n     ", tostring(err), "\n") end
end
function W.eq(a, b, what)
    if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
function W.finish()
    io.write(string.format("%d/%d passed\n", count - failed, count))
    os.exit(failed == 0 and 0 or 1)
end

-- spec.cats: { { id, parent, achs = { ids } } }; spec.ach[id] = { name, done, icon, points,
-- crit = { { text, type, done, qty, req, asset } } }; spec.renown; spec.avail, spec.spent;
-- spec.skills = { [skillID] = rank }; spec.xp.
function Fake(spec)
    W.Base(spec)
    W.spec = spec
    W.ach = spec.ach or {}
    W.cats = spec.cats or {}
    W.renown = spec.renown
    W.events = {}
    local catByID = {}
    for _, c in ipairs(W.cats) do catByID[c.id] = c end
    GetCategoryList = function()
        local out = {}
        for _, c in ipairs(W.cats) do out[#out + 1] = c.id end
        return out
    end
    GetCategoryNumAchievements = function(cat) return #((catByID[cat] or {}).achs or {}) end
    GetCategoryInfo = function(cat) local c = catByID[cat] return c and ("Cat" .. cat), c and c.parent end
    GetAchievementCategory = function(id)
        for _, c in ipairs(W.cats) do for _, a in ipairs(c.achs or {}) do if a == id then return c.id end end end
    end
    GetAchievementInfo = function(a, b)
        local id = a
        if b then id = ((catByID[a] or {}).achs or {})[b] end
        local x = id and W.ach[id]
        if not x then return nil end
        return id, x.name, 10, x.done == true, 1, 1, 2026, "", 0, x.icon, "", false, x.done == true, nil
    end
    GetAchievementNumCriteria = function(id) return #((W.ach[id] or {}).crit or {}) end
    GetAchievementCriteriaInfo = function(id, i)
        local c = ((W.ach[id] or {}).crit or {})[i]
        if not c then return nil end
        return c[1], c[2], c[3] == true, c[4] or 0, c[5] or 1, "", 0, c[6], "", i
    end
    C_Traits = {
        GetTraitCurrencyForAchievement = function(cur, id)
            assert(cur == 4225)
            return (W.ach[id] or {}).points or 0
        end,
        GetConfigIDByTreeID = function(tree) return tree == 1187 and 77 or nil end,
        GetTreeCurrencyInfo = function(cfg, tree)
            if spec.avail == nil then return {} end
            return { { traitCurrencyID = 4225, quantity = spec.avail, spent = spec.spent or 0 } }
        end,
    }
    C_MajorFactions = {
        GetCurrentRenownLevel = function(f) assert(f == 2802) return W.renown end,
        GetRenownRewardsForLevel = function() return {} end,
    }
    local skills = spec.skills or {}
    C_SkillInfo = {
        GetNumSkillLines = function() local n = 0 for _ in pairs(skills) do n = n + 1 end return n end,
        GetSkillLineInfo = function(i)
            local n = 0
            for id, rank in pairs(skills) do
                n = n + 1
                if n == i then return { skillID = id, rank = rank, maxRank = 300, isHeader = false } end
            end
        end,
    }
    W.xp = spec.xp or 0
    UnitXP = function() return W.xp end
    UnitXPMax = function() return 1000 end
    C_EventUtils = nil
    EventRegistry = { TriggerEvent = function(_, name, arg) W.events[#W.events + 1] = { name, arg } end }
    LegacySystemFrame = nil
    GulliLegacyDB = spec.db
    GulliXPCharDB = spec.xpdb
    return W
end

-- A small account: a level 37 priest tailor, some challenges done, a few open.
function W.World(extra)
    local spec = {
        level = 37, class = "PRIEST", name = "Gullipriest", renown = 12, avail = 3, spent = 9,
        skills = { [197] = 132 },
        cats = {
            { id = 15586, achs = { 62000, 62001, 62009, 61994 } },
            { id = 15590, parent = 15586, achs = { 70001, 70002 } },
            { id = 15593, achs = { 70010, 70011 } },
            { id = 15594, achs = { 70020 } },
            { id = 15620, parent = 15595, achs = { 70030 } },
            { id = 15595, achs = {} },
            { id = 15600, achs = { 70040, 728 } },
            { id = 15425, achs = { 99999 } },
        },
        ach = {
            [62000] = { name = "Novice Priest", done = true, points = 1, crit = { { "Level 25", 5, true, 25, 25 } } },
            [62001] = { name = "Experienced Priest", points = 1, crit = { { "Level 45", 5, false, 37, 45 } } },
            [62009] = { name = "Novice Warlock", points = 1, crit = { { "Level 25", 5, false, 0, 25 } } },
            [61994] = { name = "Novice Mage", points = 1, crit = { { "Level 25", 5, false, 0, 25 } } },
            [70001] = { name = "Journeyman Tailor", points = 1, crit = { { "Tailoring 150", 7, false, 132, 150, 197 } } },
            [70002] = { name = "Journeyman Alchemist", points = 1, crit = { { "Alchemy 150", 7, false, 0, 150, 171 } } },
            [70010] = { name = "Novice Spelunker", points = 1, crit = {
                { "Ragefire Chasm", 0, true }, { "Wailing Caverns", 0, true }, { "The Deadmines", 0, true },
                { "Ruins of Lordaeron", 0, true }, { "Excavation Site", 0, true }, { "Shadowfang Keep", 0, false } } },
            [70011] = { name = "Experienced Spelunker", points = 1, crit = {
                { "Gnomeregan", 0 }, { "Blackfathom Deeps", 0 }, { "Razorfen Kraul", 0 }, { "Scarlet Monastery", 0 },
                { "City of Dalaran", 0 }, { "The Drowned City", 0 }, { "Krol'dok Stronghold", 0 } } },
            [70020] = { name = "Conqueror of the Lair", points = 1, crit = { { "Onyxia", 0 } } },
            [70030] = { name = "Sergeant", points = 1, crit = { { "Rank 3", 0 } } },
            [70040] = { name = "Explorer", points = 1, crit = { { "Explore Durotar", 8, false, 0, 1, 728 } } },
            [728] = { name = "Explore Durotar", points = 0, crit = { { "Valley of Trials", 0, true }, { "Razor Hill", 0 }, { "Sen'jin Village", 0 } } },
            [99999] = { name = "Hidden", points = 1, crit = { { "x", 0 } } },
        },
    }
    for k, v in pairs(extra or {}) do spec[k] = v end
    return spec
end

function Load()
    return W.Load("Gulli-Legacy", { "Locales.lua", "Core.lua", "Skin.lua", "UI.lua" })
end

return W
