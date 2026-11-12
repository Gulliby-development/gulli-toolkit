-- A fake WoW client for the Gulli-Restock tests: the shared basics plus bags, money and a vendor.
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

-- W.bags: item id -> count. W.vendor: { { id, price, stack, available, extended } }.
-- W.bought: { { index, quantity } } in the order BuyMerchantItem was called.
function Fake(spec)
    W.Base(spec)
    W.bags, W.vendor, W.bought, W.money = spec.bags or {}, spec.vendor or {}, {}, spec.money or 1000000
    -- spec.items: id -> { stack, classID, subclassID, minLevel } (stack 20, consumable by default).
    -- spec.containers: bag -> { size, family, [slot] = { id, n, locked } }; without it the bags
    -- are five empty 16-slot bags and W.bags holds the counts.
    W.items, W.cont, W.moved = spec.items or {}, spec.containers, {}
    local function inBags(id, bank)
        if not W.cont then return (W.bags[id] or 0) + (bank and spec.bank and spec.bank[id] or 0) end
        local n = 0
        for bag, c in pairs(W.cont) do
            if bag >= 0 and bag <= 4 or bank then
                for slot = 1, c.size do if c[slot] and c[slot].id == id then n = n + c[slot].n end end
            end
        end
        return n
    end
    C_Item = {
        GetItemCount = inBags,
        GetItemNameByID = function(id) return "Item" .. id end,
        GetItemIconByID = function() return 1 end,
        GetItemInfo = function(id)
            local it = W.items[id] or {}
            return "Item" .. id, nil, 1, nil, it.minLevel or 0, nil, nil, it.stack or 20, nil, nil, 1,
                it.classID or 0, it.subclassID or 0
        end,
    }
    BANK_CONTAINER, NUM_BAG_SLOTS, NUM_BANKBAGSLOTS = -1, 4, 1
    C_Container = {
        GetContainerNumSlots = function(bag)
            if not W.cont then return bag >= 0 and bag <= 4 and 16 or 0 end
            return W.cont[bag] and W.cont[bag].size or 0
        end,
        GetContainerNumFreeSlots = function(bag)
            if not W.cont then return bag >= 0 and bag <= 4 and 16 or 0, 0 end
            local c = W.cont[bag]
            if not c then return 0, 0 end
            local free = 0
            for slot = 1, c.size do if not c[slot] then free = free + 1 end end
            return free, c.family or 0
        end,
        GetContainerItemInfo = function(bag, slot)
            local s = W.cont and W.cont[bag] and W.cont[bag][slot]
            if not s then return nil end
            return { itemID = s.id, stackCount = s.n, isLocked = s.locked }
        end,
        UseContainerItem = function(bag, slot) W.moved[#W.moved + 1] = { "use", bag, slot } end,
        SplitContainerItem = function(bag, slot, n) W.moved[#W.moved + 1] = { "split", bag, slot, n } end,
        PickupContainerItem = function(bag, slot) W.moved[#W.moved + 1] = { "drop", bag, slot } end,
    }
    W.shift, W.alt = false, false
    IsShiftKeyDown = function() return W.shift end
    IsAltKeyDown = function() return W.alt end
    GetMoney = function() return W.money end
    GetMerchantNumItems = function() return #W.vendor end
    GetMerchantItemID = function(i) return W.vendor[i] and W.vendor[i][1] end
    GetMerchantItemInfo = function(i)
        local v = W.vendor[i]
        return "Item" .. v[1], 1, v[2], v[3] or 1, v[4] or -1, true, true, v[5] or false
    end
    GetMerchantItemMaxStack = function() return 20 end
    BuyMerchantItem = function(i, q)
        W.bought[#W.bought + 1] = { i, q }
        local v = W.vendor[i]
        local n = (v[3] or 1) > 1 and v[3] or (q or 1) -- a stack item buys one stack per call
        W.bags[v[1]] = (W.bags[v[1]] or 0) + n
        W.money = W.money - v[2] * (q or 1)
    end
    GetCursorInfo = function() return W.cursor and "item", W.cursor end
    ClearCursor = function() W.cursor = nil end
    GulliRestockDB, GulliRestockCharDB = spec.db, spec.char
    return W
end

function Load()
    return W.Load("Gulli-Restock", { "Locales.lua", "Core.lua", "Skin.lua", "UI.lua" })
end

return W
