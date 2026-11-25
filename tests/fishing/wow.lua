-- A fake WoW client for the Gulli-Fishing tests: the shared basics plus spells, the pole, lures,
-- loot, CVars and bindings.
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

-- spec: spells (ids known), pole (true: a fishing pole in the main hand), lure (seconds left),
-- bags (item id -> count), cvars, db, cdb, mounted, mouseover, slots (bag -> { item ids }, bag 5
-- is the reagent bag), interact (the game's Interact key), skill ({ rank, cap }), channel
-- (seconds a cast lasts as the game tells it).
function Fake(spec)
    W.Base(spec)
    W.spells = spec.spells or { [7620] = true }
    W.pole, W.lureLeft, W.bags = spec.pole ~= false, spec.lure or 0, spec.bags or {}
    W.cvars = spec.cvars or { Sound_EnableAllSound = "1", Sound_EnableSFX = "1", Sound_SFXVolume = "0.4",
        Sound_MasterVolume = "0.5", Sound_MusicVolume = "0.6", Sound_AmbienceVolume = "0.7",
        Sound_EnableSoundWhenGameIsInBG = "0", SoftTargetInteract = "0", SoftTargetInteractRange = "10",
        autoLootDefault = "0" }
    W.bindings, W.looted, W.toasts = {}, {}, {}
    W.loot, W.fishing = {}, true
    W.mounted, W.mouseover = spec.mounted, spec.mouseover
    C_Spell = { GetSpellName = function(id) return "Fishing" .. id end }
    C_SpellBook = { IsSpellKnown = function(id) return W.spells[id] == true end }
    C_CVar = { GetCVar = function(n) return W.cvars[n] end,
               SetCVar = function(n, v) assert(W.cvars[n] ~= nil, "unknown cvar " .. n); W.cvars[n] = v; return true end }
    C_Item = {
        GetItemNameByID = function(id) return "Item" .. id end,
        GetItemIconByID = function(id) return "icon" .. id end,
        GetItemCount = function(id) return W.bags[id] or 0 end,
        IsUsableItem = function() return true end,
        GetItemInfoInstant = function(id)
            if id == 6256 then return id, "Weapon", "Fishing Poles", "INVTYPE_2HWEAPON", 1, 2, 20 end
            return id, "Weapon", "Swords", "INVTYPE_WEAPON", 1, 2, 7
        end,
        GetWeaponEnchantInfo = function(slot)
            assert(slot == 0)
            return { { hasEnchant = W.lureLeft > 0, timeLeft = W.lureLeft * 1000, charges = 0, enchantID = 0 } }
        end,
    }
    W.slots, W.equipped, W.interact, W.skill, W.channel = spec.slots or {}, {}, spec.interact, spec.skill, spec.channel
    NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
    C_Container = {
        GetContainerNumSlots = function(bag) return W.slots[bag] and #W.slots[bag] or 0 end,
        GetContainerItemID = function(bag, slot) return W.slots[bag] and W.slots[bag][slot] or nil end,
    }
    C_Item.EquipItemByName = function(id)
        assert(not W.combat, "equipping in a fight")
        W.equipped[#W.equipped + 1] = id
        W.pole = id == 6256
    end
    GetBindingKey = function(name) if name == "INTERACTTARGET" then return W.interact end end
    GetBindingText = function(key) return key end
    GetProfessions = function() return nil, nil, nil, W.skill and 4 or nil end
    GetProfessionInfo = function(i)
        assert(i == 4)
        return "Fishing", "icon", W.skill[1], W.skill[2], 0, 0, 356, W.skill[3] or 0
    end
    UnitChannelInfo = function(unit)
        assert(unit == "player")
        if not W.channel then return nil end
        return "Fishing", "Fishing", "icon", W.now * 1000, (W.now + W.channel) * 1000
    end
    IsAltKeyDown, IsControlKeyDown, IsShiftKeyDown = function() return false end, function() return false end, function() return false end
    GetInventoryItemID = function(_, slot) if slot == 16 then return W.pole and 6256 or 2131 end end
    IsMounted = function() return W.mounted end
    IsFlying = function() return false end
    UnitExists = function(u) return u == "mouseover" and W.mouseover end
    CursorHasItem = function() return false end
    WorldFrame = W.stub()
    SetOverrideBindingClick = function(owner, _, key, name) W.bindings[key] = { owner = owner, name = name } end
    ClearOverrideBindings = function(owner)
        for k, b in pairs(W.bindings) do if b.owner == owner then W.bindings[k] = nil end end
    end
    IsFishingLoot = function() return W.fishing end
    GetNumLootItems = function() return #W.loot end
    GetLootSlotLink = function(i) return W.loot[i] and ("|Hitem:" .. W.loot[i][1] .. ":0|h") end
    GetLootSlotInfo = function(i) return "icon", "name", W.loot[i] and W.loot[i][2] end
    LootSlot = function(i) W.looted[#W.looted + 1] = i end
    GulliFishingDB = spec.db
    GulliFishingCharDB = spec.cdb
    return W
end

-- A press of the right mouse button on the world at time t.
function W.Press(t)
    W.now = t
    WorldFrame._OnMouseDown(WorldFrame, "RightButton")
end

-- A cast of Fishing starts.
function W.Cast(id)
    W.Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-1", id or 7620)
end

-- The loot window opens on these items ({ id, count }).
function W.Catch(items, autoLoot)
    W.loot = items
    W.Fire("LOOT_READY", autoLoot)
    W.Fire("LOOT_CLOSED")
end

-- The bobber is out of the water.
function W.Stop()
    W.Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "Cast-1", 7620)
end

function Load()
    return W.Load("Gulli-Fishing", { "Locales.lua", "Core.lua", "Skin.lua", "UI.lua", "Bar.lua" })
end

return W
