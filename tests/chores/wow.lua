-- A fake WoW client for the Gulli-Chores tests: the shared basics plus the character's state.
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

-- W.char holds what the fake character has: xp, rested, resting, mail, free, durability,
-- spells (known spell ids), cooldowns (id -> {start, duration}), items (id -> count).
function Fake(spec)
    W.Base(spec)
    W.char = { xpMax = 1000, rested = 0, resting = false, mail = false, free = 16, durability = { 100, 100 },
               spells = {}, cooldowns = {}, items = {}, money = 12345 }
    GetMaxPlayerLevel = function() return 60 end
    UnitXPMax = function() return W.char.xpMax end
    GetXPExhaustion = function() return W.char.rested end
    IsResting = function() return W.char.resting end
    HasNewMail = function() return W.char.mail end
    GetMoney = function() return W.char.money end
    GetInventoryItemDurability = function(slot)
        local d = W.char.durability[slot]
        if d then return d, 100 end
    end
    IsPlayerSpell = function(id) return W.char.spells[id] == true end
    C_Spell = { GetSpellCooldown = function(id)
        local c = W.char.cooldowns[id] or { 0, 0 }
        return { startTime = c[1], duration = c[2] }
    end }
    C_Container = {
        GetContainerNumFreeSlots = function(bag) if bag == 0 then return W.char.free, 0 end return 0, 0 end,
        GetItemCooldown = function(id) local c = W.char.cooldowns[id] or { 0, 0 }; return c[1], c[2], 1 end,
    }
    C_Item = { GetItemCount = function(id) return W.char.items[id] or 0 end }
    -- W.char.bags / bank: bag -> { { id, count } }; inbox: { { money, cod, days, items } };
    -- profs: { { name, skill, cap } }; saved: { { name, reset, locked } }.
    W.char.bags, W.char.bank, W.char.inbox, W.char.profs, W.char.saved = {}, {}, {}, nil, nil
    C_Container.GetContainerNumSlots = function(bag)
        local b = W.char.bags[bag] or W.char.bank[bag]
        return b and #b or 0
    end
    C_Container.GetContainerItemInfo = function(bag, slot)
        local b = W.char.bags[bag] or W.char.bank[bag]
        local it = b and b[slot]
        if it then return { itemID = it[1], stackCount = it[2] } end
    end
    GetInboxNumItems = function() return #W.char.inbox end
    GetInboxHeaderInfo = function(i)
        local m = W.char.inbox[i]
        return nil, nil, "Someone", "Subject", m[1], m[2], m[3], m[4]
    end
    GetBindLocation = function() return W.char.bind end
    GetProfessions = function()
        if not W.char.profs then return end
        local idx = {}
        for i = 1, #W.char.profs do idx[i] = i end
        return unpack(idx)
    end
    GetProfessionInfo = function(i) local p = W.char.profs[i]; return p[1], "icon", p[2], p[3] end
    GetNumSavedInstances = function() return W.char.saved and #W.char.saved or 0 end
    GetSavedInstanceInfo = function(i) local l = W.char.saved[i]; return l[1], 1, l[2], 1, l[3] end
    W.playedAsked = 0
    RequestTimePlayed = function() W.playedAsked = W.playedAsked + 1 end
    ChatFrame_DisplayTimePlayed = function() W.printed[#W.printed + 1] = "played shown" end
    GulliCraftProfitCharDB, GulliToolkit = nil, nil
    GulliChoresDB = spec.db
    return W
end

function Load()
    return W.Load("Gulli-Chores", { "Locales.lua", "Core.lua", "Skin.lua", "UI.lua" })
end

return W
