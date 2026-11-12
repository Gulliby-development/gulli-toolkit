-- A fake WoW client for the Gulli-BagSpace tests: the shared basics plus bags, items and the cursor.
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

-- spec.bags = { [bag] = { size = n, family = 0, slots = { [slot] = { id, count } } } }
-- spec.items = { [id] = { name, quality, maxStack, price, classID } }
function Fake(spec)
    W.Base(spec)
    W.bags, W.items = spec.bags or {}, spec.items or {}
    W.cursor, W.deleted, W.sold = nil, {}, {}
    local function bag(b) return W.bags[b] or { size = 0, slots = {} } end
    C_Container = {
        GetContainerNumSlots = function(b) return bag(b).size end,
        GetContainerNumFreeSlots = function(b)
            local used = 0
            for _ in pairs(bag(b).slots) do used = used + 1 end
            return bag(b).size - used, bag(b).family or 0
        end,
        GetContainerItemInfo = function(b, s)
            local x = bag(b).slots[s]
            if not x then return nil end
            local it = W.items[x.id] or {}
            return { itemID = x.id, stackCount = x.count or 1, isLocked = false, hyperlink = "item:" .. x.id,
                     iconFileID = 1, quality = it.quality }
        end,
        PickupContainerItem = function(b, s)
            local x = bag(b).slots[s]
            if W.cursor then
                -- drop: merge into the same item
                if x and x.id == W.cursor.id then x.count = x.count + W.cursor.count
                elseif not x then bag(b).slots[s] = W.cursor end
                W.cursor = nil
            elseif x then
                W.cursor = { id = x.id, count = x.count, from = { b, s } }
                bag(b).slots[s] = nil
            end
        end,
        SplitContainerItem = function(b, s, n)
            local x = bag(b).slots[s]
            x.count = x.count - n
            W.cursor = { id = x.id, count = n }
            if x.count == 0 then bag(b).slots[s] = nil end
        end,
        UseContainerItem = function(b, s)
            W.sold[#W.sold + 1] = bag(b).slots[s].id
            bag(b).slots[s] = nil
        end,
    }
    C_Item = { GetItemInfo = function(id)
        local it = W.items[id]
        if not it then return nil end
        return it.name, "item:" .. id, it.quality, 1, 1, "", "", it.maxStack or 1, "", 1, it.price or 0, it.classID or 15,
            it.subclassID or 0
    end }
    W.sets, W.refuse = spec.sets or {}, {}
    C_Container.GetContainerItemEquipmentSetInfo = function(b, s) return W.sets[b] and W.sets[b][s] or false end
    GetCursorInfo = function() if W.cursor then return "item", W.cursor.id end end
    ClearCursor = function()
        if W.cursor and W.cursor.from then bag(W.cursor.from[1]).slots[W.cursor.from[2]] = W.cursor end
        W.cursor = nil
    end
    DeleteCursorItem = function()
        -- A refused delete leaves the item where it was.
        if W.refuse[W.cursor.id] then ClearCursor() return end
        W.deleted[#W.deleted + 1] = W.cursor.id; W.cursor = nil
    end
    GulliBagSpaceDB = spec.db
    return W
end

function Load()
    return W.Load("Gulli-BagSpace", { "Locales.lua", "Core.lua", "Skin.lua", "UI.lua" })
end

return W
