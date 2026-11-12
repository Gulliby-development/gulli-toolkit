-- A fake WoW client for the Gulli-AutoQuest tests: the shared basics plus quest givers.
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

-- W.npc = { active = { { id, complete } }, available = { { id, trivial } }, gossip = true|false }
-- W.did lists what the addon called, as "accept", "complete", "reward:N", "active:ID", "available:ID".
function Fake(spec)
    W.Base(spec)
    W.did, W.shift = {}, false
    W.npc = spec.npc or { active = {}, available = {}, gossip = true }
    W.choices, W.prices, W.completable, W.moneyToGet = 0, {}, true, 0
    local function did(s) W.did[#W.did + 1] = s end
    C_GossipInfo = {
        GetActiveQuests = function()
            local out = {}
            for _, q in ipairs(W.npc.active) do out[#out + 1] = { questID = q[1], isComplete = q[2] } end
            return out
        end,
        GetAvailableQuests = function()
            local out = {}
            for _, q in ipairs(W.npc.available) do out[#out + 1] = { questID = q[1], isTrivial = q[2] } end
            return out
        end,
        SelectActiveQuest = function(id) did("active:" .. id) end,
        SelectAvailableQuest = function(id) did("available:" .. id) end,
    }
    GetNumActiveQuests = function() return #W.npc.active end
    GetActiveTitle = function(i) return "Q", W.npc.active[i][2] end
    GetNumAvailableQuests = function() return #W.npc.available end
    GetAvailableQuestInfo = function(i) return W.npc.available[i][2] end
    SelectActiveQuest = function(i) did("active#" .. i) end
    SelectAvailableQuest = function(i) did("available#" .. i) end
    IsShiftKeyDown = function() return W.shift end
    AcceptQuest = function() did("accept") end
    QuestGetAutoAccept = function() return false end
    CompleteQuest = function() did("complete") end
    IsQuestCompletable = function() return W.completable end
    GetQuestMoneyToGet = function() return W.moneyToGet end
    GetNumQuestChoices = function() return W.choices end
    GetQuestReward = function(n) did("reward:" .. tostring(n)) end
    GetQuestItemLink = function(_, i) return "item:" .. i end
    C_Item = { GetItemInfo = function(link)
        local i = tonumber(link:match("%d+"))
        return "Item", link, 2, 1, 1, "", "", 1, "", 1, W.prices[i] or 0
    end }
    W.shift, W.ctrl = false, false
    IsControlKeyDown = function() return W.ctrl end
    IsAltKeyDown = function() return false end
    W.questID, W.title, W.tags, W.required, W.classes, W.log, W.options = spec.questID or 101, "A Quest", {}, {}, {}, 0, {}
    GetQuestID = function() return W.questID end
    GetTitleText = function() return W.title end
    GetSuggestedGroupNum = function() return W.group or 0 end
    UnitGUID = function(u) if u == "npc" then return W.npcGuid end end
    W.npcGuid = "Creature-0-1-2-3-" .. (spec.npcID or 500) .. "-0000"
    GetNumQuestItems = function() return #W.required end
    local link = GetQuestItemLink
    GetQuestItemLink = function(kind, i) if kind == "required" then return W.required[i] end return link(kind, i) end
    C_Item.GetItemInfoInstant = function(l) return 1, "", "", "", "", W.classes[l] or 12 end
    C_QuestLog = {
        GetNumQuestLogEntries = function() return W.log + 2, W.log end,
        GetMaxNumQuestsCanAccept = function() return 20 end,
        GetQuestTagInfo = function(id) return W.tags[id] end,
        SetSelectedQuest = function(id) did("select:" .. id) end,
        SetAbandonQuest = function() end,
        AbandonQuest = function() did("abandon") end,
    }
    ConfirmAcceptQuest = function() did("confirm") end
    C_GossipInfo.GetOptions = function() return W.options end
    C_GossipInfo.SelectOption = function(id) did("option:" .. id) end
    GulliAutoQuestDB = spec.db
    return W
end

function Load()
    return W.Load("Gulli-AutoQuest", { "Locales.lua", "Core.lua", "Skin.lua", "UI.lua" })
end

return W
