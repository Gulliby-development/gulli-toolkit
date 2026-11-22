-- A fake WoW client for the Gulli-MyBisList tests: the shared basics plus worn gear, the bags and
-- the talent tabs.
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
        if k == "SetAttribute" then return function(_, n, v) rawget(t, "_attr")[n] = v end end
        if k == "GetAttribute" then return function(_, n) return rawget(t, "_attr")[n] end end
        if k == "GetName" then return function() return rawget(t, "_name") end end
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
    CreateFrame = function(_, name)
        local f = stub()
        rawset(f, "_events", {})
        rawset(f, "_attr", {})
        rawset(f, "_name", name)
        W.frames[#W.frames + 1] = f
        return f
    end
    UIParent, GameTooltip, UISpecialFrames = stub(), stub(), {}
    tinsert, tremove, wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end
    strtrim = function(s) return (s or ""):match("^%s*(.-)%s*$") end
    C_Timer = { After = function(d, fn) W.timers[#W.timers + 1] = { at = W.now + (d or 0), fn = fn } end,
                NewTicker = function(_, fn) return stub() end }
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

-- Runs the timers that are due by now.
function W.RunTimers()
    local t = W.timers
    W.timers = {}
    for _, x in ipairs(t) do
        if x.at <= W.now then x.fn() else W.timers[#W.timers + 1] = x end
    end
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

-- spec: class, faction, level, worn (inventory slot -> item id), enchanted, spells, items (item id -> count, bags and
-- bank, worn ones included as the game counts them), spec (retail specialization id), tabs
-- (points per talent tab), db, cdb, hub.
local CLASS_ID = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }
function Fake(spec)
    spec = spec or {}
    W.Base(spec)
    W.worn, W.items = spec.worn or {}, spec.items or {}
    W.toasts, W.notes, W.tips = {}, {}, {}
    UnitClass = function() return "Class", spec.class or "WARRIOR", CLASS_ID[spec.class or "WARRIOR"] end
    UnitFactionGroup = function() return spec.faction or "Alliance" end
    LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue",
        PRIEST = "Priest", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
    GetInventoryItemID = function(_, slot) return W.worn[slot] end
    -- enchanted: inventory slot -> the enchant id in the worn item's link; spells: id -> name
    W.enchanted, W.spells = spec.enchanted or {}, spec.spells or {}
    GetInventoryItemLink = function(_, slot)
        return W.worn[slot] and ("|Hitem:" .. W.worn[slot] .. ":" .. (W.enchanted[slot] or "") .. ":::|h[x]|h") or nil
    end
    C_Spell = { GetSpellName = function(id) return W.spells[id] end,
                GetSpellTexture = function(id) return W.spells[id] and ("spell" .. id) or nil end }
    W.loot, W.rolls, W.sounds = spec.loot or {}, spec.rolls or {}, 0
    GetNumLootItems = function() return #W.loot end
    GetLootSlotLink = function(i) return W.loot[i] and ("|Hitem:" .. W.loot[i] .. "::|h[x]|h") or nil end
    GetLootRollItemLink = function(id) return W.rolls[id] and ("|Hitem:" .. W.rolls[id] .. "::|h[x]|h") or nil end
    PlaySound = function() W.sounds = W.sounds + 1 end
    C_Item = {
        GetItemNameByID = function(id) return "Item" .. id end,
        GetItemIconByID = function(id) return "icon" .. id end,
        GetItemQualityByID = function() return 3 end,
        RequestLoadItemDataByID = function() end,
        GetItemCount = function(id) return W.items[id] or 0 end,
        -- equip: item id -> the game's equip location, for the set pieces the data has no slot for
        GetItemInfoInstant = function(id) return id, "Armor", "", (W.equip or {})[id] or "" end,
        GetItemInfo = function(id)
            return "Item" .. id, nil, 3, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, (W.setOf or {})[id]
        end,
        GetItemSetInfo = function(id) return (W.setNames or {})[id] end,
    }
    -- tips: item id -> the lines of its tooltip
    W.equip, W.setOf, W.setNames, W.tipLines = spec.equip or {}, spec.setOf or {}, spec.setNames or {}, spec.tipLines or {}
    C_TooltipInfo = { GetItemByID = function(id)
        local t = W.tipLines[id]
        if not t then return nil end
        local lines = {}
        for i, x in ipairs(t) do lines[i] = { leftText = x } end
        return { lines = lines }
    end }
    ITEM_SET_BONUS_GRAY, ITEM_SET_BONUS = "(%d) Set: %s", "Set: %s"
    GetSpecialization = spec.spec and function() return 1 end or nil
    GetSpecializationInfo = spec.spec and function() return spec.spec end or nil
    GetTalentTabInfo = spec.tabs and function(i) return i, "Tab", "", "", spec.tabs[i] or 0 end or nil
    GulliHUD = nil
    GulliDungeonJournal = nil
    GulliMyBisListDB = spec.db
    GulliMyBisListCharDB = spec.cdb
    if spec.hub then
        GulliToolkit = { Register = function(t) W.registered = t end,
                         Notify = function(key, text) W.notes[#W.notes + 1] = { key, text } end }
    end
    return W
end

function Load()
    local ns = W.Load("Gulli-MyBisList", { "Locales.lua", "Data.lua", "Core.lua", "Skin.lua", "UI.lua" })
    ns.Skin.Toast = function(o) W.toasts[#W.toasts + 1] = o end
    ns.Skin.TipProvider = function(kind, key, fn) W.tips[key] = fn end
    return ns
end

return W
